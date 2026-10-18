//! An EXACT, per-worker memo for `Policy::policy_step` inside full playouts.
//!
//! `policy_step` is a pure function of (State, player, effective `rich`, the `Policy`, the two input fields of `Scratch`).
//! The oracle's candidate rows play the same opening steps again and again (about 41 % of a worker's steps repeat at
//! the runner's default chunk of 4); a repeat is answered from a stored copy instead of re-running the whole menu.
//!
//! KEY. The `Policy` of a playout is a function of the Core's header and net (`gen`, fresh per `set_header` / `load_net`),
//! of the ROOT state (statics come from its profile table, the tier-2 reach index is built from it) and of the terrain.
//! `enter` registers that triple once per playout (root compared with the derived `State ==` and bitwise positions); the
//! step key is then (registered config, player, rich, `Scratch` inputs) plus a CLONE of the whole `State`. A hit needs the
//! derived `State ==` (a new field is compared without anyone remembering it) and bitwise equal `positions` (`==` alone
//! would equate 0.0 and -0.0). The bucket hash only picks a bucket; it is never trusted.
//!
//! SCOPE. Thread-local and OFF unless `enter` returned a live `Scope` on this thread, and then only for the one `Policy`
//! object `enter` was given (pointer check), so the parent search, Godot and tests are untouched. Bypassed when a test
//! switch or `NML_TRACE_RULES=1` is on, when `force_leaf` or a policy net is set, and for an `Err` answer (never stored).
//! BOUND. At most `MAX_ENTRIES` stored answers per thread (~16 KB each); reaching it drops them ALL (the oldest first
//! playouts are the least useful once seeds diverge), `begin_game` drops everything and issues a new generation.

use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};

use crate::io::Seams;
use crate::menu::{Candidate, Tuning};
use crate::playout::Policy;
use crate::sim::{Scratch, Unsupported};
use crate::state::State;

pub const MAX_ENTRIES: usize = 1_024;
const MAX_CFGS: usize = 64;

struct Cfg {
    gen: u64,
    terrain_uid: u64,
    seams: Seams,
    tuning: Tuning,
    root: State,
}

/// (config index, player, rich, `Scratch.rules_epoch`, `Scratch.bearers_last`)
type Ins = (usize, i64, bool, u32, bool);

struct Entry {
    ins: Ins,
    state: State,
    post: (u32, bool),
    answer: Option<Candidate>,
}

#[derive(Default)]
struct Memo {
    cur: Option<(usize, usize)>,
    cfgs: Vec<Cfg>,
    entries: usize,
    table: HashMap<u64, Vec<Entry>>,
    calls: u64,
    hits: u64,
}

thread_local! { static MEMO: RefCell<Memo> = RefCell::new(Memo::default()); }

/// Live while one playout runs; dropping it switches the memo off again.
pub struct Scope;
impl Drop for Scope {
    fn drop(&mut self) {
        MEMO.with(|m| m.borrow_mut().cur = None);
    }
}

/// Start of a game or a new net: drop everything stored and return a fresh, never reused generation (always > 0).
pub fn begin_game() -> u64 {
    static GEN: AtomicU64 = AtomicU64::new(1);
    MEMO.with(|m| *m.borrow_mut() = Memo::default());
    GEN.fetch_add(1, Ordering::Relaxed)
}

/// `(calls, hits)` of this thread since the last `begin_game`.
pub fn stats() -> (u64, u64) {
    MEMO.with(|m| (m.borrow().calls, m.borrow().hits))
}

/// Number of answers currently stored on this thread.
pub fn stored() -> usize {
    MEMO.with(|m| m.borrow().entries)
}

fn same_positions(a: &State, b: &State) -> bool {
    a.positions.len() == b.positions.len()
        && a.positions.iter().zip(&b.positions).all(|(x, y)| {
            x.len() == y.len() && x.iter().zip(y).all(|(p, q)| (0..3).all(|k| p[k].to_bits() == q[k].to_bits()))
        })
}

fn bucket(ins: &Ins, s: &State) -> u64 {
    let mix = |h: u64, w: u64| (h.rotate_left(5) ^ w).wrapping_mul(0x517c_c1b7_2722_0a95);
    let mut h = mix(mix(mix(ins.0 as u64, ins.1 as u64), u64::from(ins.2)), s.round as u64);
    for i in 0..s.units() {
        h = mix(h, s.alive[i] as u64 ^ u64::from(s.activated[i]) << 8 ^ u64::from(s.shaken[i]) << 9 ^ u64::from(s.fatigued[i]) << 10);
        h = s.positions[i].iter().fold(h, |h, p| mix(h, p[0].to_bits() ^ p[2].to_bits().rotate_left(17)));
        h = s.wounds[i].iter().fold(h, |h, w| mix(h, *w as u64));
    }
    h
}

/// The test switches that change a rule's reading (process globals) and the trace env: with any on, nothing is memoised.
fn bypass() -> bool {
    crate::mv::plain_memo::trace_rules_on()
        || crate::mv::step::LADDER_DISABLED.load(Ordering::Relaxed)
        || crate::mv::step::STALL_DISABLED.load(Ordering::Relaxed)
        || crate::rules::LEGACY_PREFIX_RULES.load(Ordering::Relaxed)
        || crate::unit::LEGACY_NO_COND_AP.load(Ordering::Relaxed)
}

/// Arm the memo for ONE playout of `policy` (the object `run` will be called on). `gen` 0 or an unset terrain: stay off.
pub fn enter(gen: u64, terrain_uid: u64, policy: &Policy, root: &State) -> Scope {
    MEMO.with(|m| {
        let mut m = m.borrow_mut();
        m.cur = None;
        if gen == 0 || terrain_uid == 0 || policy.force_leaf.is_some() || policy.policy_net.is_some() {
            return;
        }
        let same = |c: &Cfg| {
            c.gen == gen && c.terrain_uid == terrain_uid && c.seams == policy.seams && c.tuning == policy.tuning
                && c.root == *root && same_positions(&c.root, root)
        };
        let at = m.cfgs.iter().position(same).unwrap_or_else(|| {
            if m.cfgs.len() >= MAX_CFGS {
                *m = Memo::default();
            }
            m.cfgs.push(Cfg { gen, terrain_uid, seams: policy.seams, tuning: policy.tuning, root: root.clone() });
            m.cfgs.len() - 1
        });
        m.cur = Some((at, policy as *const Policy as usize));
    });
    Scope
}

/// `fresh` (the real `policy_step`) run through the memo.
pub(crate) fn run(
    p: &Policy, state: &State, player: i64, rich: bool, sc: &mut Scratch,
    fresh: impl FnOnce(&mut Scratch) -> Result<Option<Candidate>, Unsupported>,
) -> Result<Option<Candidate>, Unsupported> {
    let cfg = MEMO.with(|m| m.borrow().cur).filter(|c| c.1 == p as *const Policy as usize);
    let Some((cfg, _)) = cfg.filter(|_| !bypass()) else { return fresh(sc) };
    let ins: Ins = (cfg, player, rich, sc.rules_epoch, sc.bearers_last);
    let h = bucket(&ins, state);
    let hit = MEMO.with(|m| {
        let mut m = m.borrow_mut();
        m.calls += 1;
        let found = m.table.get(&h).and_then(|b| {
            b.iter().find(|e| e.ins == ins && e.state == *state && same_positions(&e.state, state))
        });
        let found = found.map(|e| (e.post, e.answer.clone()));
        m.hits += u64::from(found.is_some());
        found
    });
    if let Some((post, answer)) = hit {
        #[cfg(debug_assertions)]
        debug_assert_eq!(format!("{answer:?}"), format!("{:?}", fresh(&mut Scratch { rules_epoch: ins.3, bearers_last: ins.4, ..Scratch::default() })), "policy_step memo hit != fresh");
        (sc.rules_epoch, sc.bearers_last) = post;
        return Ok(answer);
    }
    let answer = fresh(sc)?;
    MEMO.with(|m| {
        let mut m = m.borrow_mut();
        if m.entries >= MAX_ENTRIES {
            m.table.clear();
            m.entries = 0;
        }
        m.entries += 1;
        let post = (sc.rules_epoch, sc.bearers_last);
        m.table.entry(h).or_default().push(Entry { ins, state: state.clone(), post, answer: answer.clone() });
    });
    Ok(answer)
}
