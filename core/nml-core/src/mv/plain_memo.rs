//! An EXACT, game-scoped memo for `MoveRules::plain_move`.
//!
//! `plain_move` is a pure function of its arguments, of the whole `State`, of the terrain and of two test-only switches
//! (`LADDER_DISABLED`, `STALL_DISABLED`). The parent search asks it for the same question again and again inside one game
//! (37.6 % of its calls repeat); a repeat is answered from a stored copy.
//!
//! KEY. Every argument (`Args`, floats by bit pattern, the terrain by `Terrain::uid`) plus a CLONE of the whole `State`.
//! A hit needs `Args ==` and `State ==` (derived, so a new field is compared without anyone remembering it, and a field
//! type that cannot be compared is a compile error) and a bitwise equal `positions` (`==` alone would equate 0.0 and -0.0).
//! The hash only picks a bucket; it is never trusted.
//!
//! SCOPE. Thread-local, DISARMED by default (tests, Godot and other callers are untouched). `begin_game()` (the Python
//! seam's `Core.set_header`) clears and arms. Exactness never depends on the clear, it only bounds the lifetime. Bypassed
//! while `NML_TRACE_RULES=1` (the trace lines of the fresh run stay identical). Debug builds recompute every hit.

use std::cell::RefCell;
use std::collections::HashMap;
use std::sync::atomic::Ordering;

use super::step::{Landing, LADDER_DISABLED, STALL_DISABLED};
use crate::geom::V3;
use crate::state::State;
use crate::terrain::Terrain;

/// Most stored answers per process; an overflow drops them all.
pub const MAX_ENTRIES: usize = 1_500;

/// Every argument of `plain_move` (floats as bit patterns).
#[derive(Clone, Debug, PartialEq)]
pub(crate) struct Args {
    pub rules_epoch: u32,
    pub terrain_uid: u64,
    pub si: usize,
    pub dest: [u32; 3],
    pub band_in: u64,
    pub hero_attach: bool,
    pub fast_planner: bool,
    pub guard: i64,
}

struct Entry {
    args: Args,
    state: State,
    land: Option<Landing>,
}

#[derive(Default)]
struct Memo {
    armed: bool,
    entries: usize,
    table: HashMap<u64, Vec<Entry>>,
    calls: u64,
    hits: u64,
}

/// `NML_TRACE_RULES=1`, read once per process.
fn trace_rules_on() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| std::env::var("NML_TRACE_RULES").as_deref() == Ok("1"))
}

thread_local! { static MEMO: RefCell<Memo> = RefCell::new(Memo::default()); }

fn bucket(a: &Args, s: &State) -> u64 {
    let mix = |h: u64, w: u64| (h.rotate_left(5) ^ w).wrapping_mul(0x517c_c1b7_2722_0a95);
    let mut h = mix(mix(a.terrain_uid, a.si as u64), a.band_in);
    h = mix(mix(h, u64::from(a.dest[0]) << 32 | u64::from(a.dest[2])), s.round as u64);
    for p in s.positions.get(a.si).into_iter().flatten() {
        h = mix(h, p[0].to_bits() ^ p[2].to_bits().rotate_left(17));
    }
    h
}

/// 0.0 == -0.0 and NaN != NaN under `==`: positions are the one float input that moves, so compare their bits.
fn same_positions(a: &State, b: &State) -> bool {
    a.positions.len() == b.positions.len()
        && a.positions.iter().zip(&b.positions).all(|(x, y)| {
            x.len() == y.len() && x.iter().zip(y).all(|(p, q)| (0..3).all(|k| p[k].to_bits() == q[k].to_bits()))
        })
}

/// Start of a game: drop everything stored, arm the memo (`Core.set_header`).
pub fn begin_game() {
    MEMO.with(|m| *m.borrow_mut() = Memo { armed: true, ..Memo::default() });
}

/// Stop memoising and drop everything (the default state of a thread).
pub fn disarm() {
    MEMO.with(|m| *m.borrow_mut() = Memo::default());
}

/// `(calls, hits)` of this thread's current game.
pub fn stats() -> (u64, u64) {
    MEMO.with(|m| (m.borrow().calls, m.borrow().hits))
}

/// `fresh` (the real `plain_move`) run through the memo.
#[allow(clippy::too_many_arguments)]
pub(crate) fn run(
    rules_epoch: u32, state: &State, t: &Terrain, si: usize, dest: V3, band_in: f64, hero_attach: bool,
    fast_planner: bool, guard: i64, fresh: impl FnOnce() -> Option<Landing>,
) -> Option<Landing> {
    let armed = MEMO.with(|m| m.borrow().armed);
    if !armed || t.uid() == 0 || trace_rules_on()
        || LADDER_DISABLED.load(Ordering::Relaxed) || STALL_DISABLED.load(Ordering::Relaxed) {
        return fresh();
    }
    let args = Args {
        rules_epoch, terrain_uid: t.uid(), si, dest: dest.map(f32::to_bits), band_in: band_in.to_bits(),
        hero_attach, fast_planner, guard,
    };
    let h = bucket(&args, state);
    let hit = MEMO.with(|m| {
        let mut m = m.borrow_mut();
        m.calls += 1;
        let found = m.table.get(&h).and_then(|b| {
            b.iter().find(|e| e.args == args && e.state == *state && same_positions(&e.state, state))
        });
        let found = found.map(|e| e.land.clone());
        m.hits += u64::from(found.is_some());
        found
    });
    if let Some(land) = hit {
        #[cfg(debug_assertions)]
        debug_assert_eq!(format!("{land:?}"), format!("{:?}", fresh()), "plain_move memo hit != fresh");
        return land;
    }
    let land = fresh();
    MEMO.with(|m| {
        let mut m = m.borrow_mut();
        if m.entries >= MAX_ENTRIES {
            m.table.clear();
            m.entries = 0;
        }
        m.entries += 1;
        m.table.entry(h).or_default().push(Entry { args, state: state.clone(), land: land.clone() });
    });
    land
}
