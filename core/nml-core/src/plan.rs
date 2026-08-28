//! The SEARCH — `AiPlanner.plan_with_rollout` (ai_planner.gd:118-275) and the
//! 1-ply `AiPlanner.plan` (:21-45) it degrades to. This is the top of the solo
//! brain: everything the other modules of this crate port is machinery this file
//! spends.
//!
//! The shape of one activation:
//!   0. `base` — the ROOT's rich-leaf score, the "before" of the expectation;
//!   1. PREFILTER — every un-activated living unit of `player`, in CAPTURE
//!      order, contributes its whole menu (a SHAKEN unit contributes its
//!      recovery hold alone); each candidate is resolved once and priced 1-ply
//!      with the rich leaf. `idx` is the position in this unsorted build order
//!      and is the identity every later stage refers to;
//!   2. SORT by score descending with an EXPLICIT `idx` ascending tiebreak —
//!      Godot's `sort_custom` is not stable, so without that second clause the
//!      order of tied candidates would be an implementation detail of the sort.
//!      There are 277 tied rows in the 25-activation corpus, so this is not a
//!      theoretical worry;
//!   3. POOL — four guarantees, IN ORDER, deduped by candidate IDENTITY:
//!        a. per-unit coverage: every unit's best candidate is rolled out,
//!        b. the global top-K slice,
//!        c. every unit's first PATIENT candidate (R8),
//!        d. every second-wave candidate (D23).
//!      b/c/d rank low 1-ply by construction, which is exactly why they need a
//!      guarantee rather than a cut;
//!   4. ROLLOUT — exactly ONE round rollout per pool candidate, in pool order,
//!      priced by `_blend_score`; the winner is a STRICT first-wins argmax;
//!   5. ARBITRATION — on a CLOSE top-2 the stochastic playout decides. This port
//!      DECLINES that (`Unsupported::PlayoutArbitration`); the recorded corpus
//!      never triggers it (`playout_search` is false on all 25 acts);
//!   6. EMISSION — the pick plus `waits` (own units kept back) and
//!      `rolled_units` (the coverage keys).
//!
//! `_intent` (:279-323) is NOT ported: it is a German/English label for the
//! battle log, not a decision. `Pick` carries the search's own trace fields
//! instead, because a gate that can only compare the final answer cannot say
//! WHERE two searches diverged.

use std::cmp::Ordering;

use crate::acts::{ActStatics, Knobs};
use crate::arbitration::{arbitrate_bent, ArbBend, Arbitration};
use crate::io::Seams;
use crate::menu::{candidates_tuned, Candidate};
use crate::playout::Policy;
use crate::rollout::Rollout;
use crate::score::score;
use crate::mv::reach::ReachIndex;
use crate::sim::{reach_index_for_state, reply_threat, Scratch, Unsupported};
use crate::state::State;
use crate::terrain::Terrain;
use crate::unit::UnitStatic;

/// `AiPlanner.ROLLOUT_TOP_K` ai_planner.gd:48 — the rollout budget.
pub const ROLLOUT_TOP_K: i64 = 6;
/// `AiPlanner.playout_close_margin` ai_planner.gd:80 — the blend-score gap that
/// counts as "close" and hands the pick to the stochastic arbitration.
pub const PLAYOUT_CLOSE_MARGIN: f64 = 0.02;

/// One row of the PREFILTER — `plan_with_rollout`'s `scored` entry
/// (ai_planner.gd:139-140). `idx` is this row's position in the UNSORTED build
/// order and never changes; the sort reorders references to rows, not the rows.
#[derive(Debug, Clone)]
pub struct ScoredRow {
    pub idx: usize,
    pub unit_key: String,
    pub cand: Candidate,
    pub score: f64,
}

/// The 1-ply pick — `AiPlanner.plan` ai_planner.gd:42-45. It is a DIFFERENT
/// dictionary from `plan_with_rollout`'s: no `waits`, no `rolled_units`, and the
/// expectation's "after" is a 1-ply score, not a rollout value. Hence its own
/// type rather than a `Pick` with two fields quietly zeroed.
#[derive(Debug, Clone)]
pub struct OnePly {
    pub unit_key: String,
    pub action: Candidate,
    pub expectation_before: f64,
    pub expectation_after: f64,
    /// `(unit_key, action, score)` — empty in the GDScript when only one
    /// candidate was ever scored.
    pub runner_up: Option<(String, Candidate, f64)>,
}

/// What `plan_with_rollout` returns — the pick plus the SEARCH TRACE
/// (`AiPlanner.trace`, ai_planner.gd:97). The trace half exists so the parity
/// gate can compare the prefilter, the pool and the rollout values one stage at
/// a time instead of guessing from a wrong final answer.
#[derive(Debug, Clone)]
pub struct Pick {
    pub unit_key: String,
    pub action: Candidate,
    /// `expectation.before` — the ROOT score.
    pub expectation_before: f64,
    /// `expectation.after` — the WINNER's rollout value, not its 1-ply score.
    pub expectation_after: f64,
    pub runner_up: Option<(String, Candidate, f64)>,
    /// Own un-activated living units that are NOT the winner.
    pub waits: i64,
    /// `covered.keys()` — every unit that got at least one rollout, in the order
    /// the coverage guarantee discovered it.
    pub rolled_units: Vec<String>,
    /// `trace.scored`: `(idx, unit, kind, score)` in RANKED order.
    pub scored: Vec<(i64, String, i64, f64)>,
    /// `trace.pool_idx`: the build-order `idx` of every rolled candidate, in
    /// pool order.
    pub pool_idx: Vec<usize>,
    /// `trace.rs`: `(idx, rollout value)`, index-parallel to `pool_idx`.
    pub rs: Vec<(i64, f64)>,
    /// `trace.best_idx` / `trace.runner_idx`: positions in the SORTED `scored`
    /// array (ai_planner.gd:211, :217), NOT build-order `idx` values.
    pub best_idx: i64,
    pub runner_idx: i64,
    /// `AiPlanner._last_leaf_state` (:213) — the horizon end of the WINNING
    /// rollout, rebound every time the best is replaced. The controller reads it
    /// after the pick, so it is part of the function's answer, not a debug aid.
    ///
    /// NOTE it is NOT rebound by a playout swap: the GDScript sets it inside the
    /// rollout loop only (:213), so after an arbitration swap the leaf belongs to
    /// the branch that LOST. Mirrored, not corrected.
    pub last_leaf: Option<State>,
    /// `trace.arbitration` (:263-264) — `None` unless the playout arbitration
    /// fired on this pick.
    pub arbitration: Option<Arbitration>,
}

/// TEST SEAMS. Every shipping call uses `PlanBend::default()`, which is the
/// GDScript. Each field turns ONE load-bearing decision of the search off, so a
/// red proof can count how many activations that decision actually moves
/// instead of asserting green and hoping.
#[derive(Debug, Clone, Copy)]
pub struct PlanBend {
    /// `None` = the recorded knob. `Some(k)` forces a different rollout budget.
    pub top_k: Option<i64>,
    /// `false` drops the explicit `idx` tiebreak from the sort comparator and
    /// sorts UNSTABLY — what a naive port of `sort_custom` would do.
    pub idx_tiebreak: bool,
    /// `true` dedupes the pool by candidate CONTENT instead of by identity.
    pub dedupe_by_value: bool,
    /// `true` runs the global top-K guarantee BEFORE the per-unit coverage.
    pub top_k_first: bool,
    /// The playout arbitration's own seams — see `arbitration::ArbBend`.
    pub arb: ArbBend,
}

impl Default for PlanBend {
    fn default() -> Self {
        PlanBend {
            top_k: None,
            idx_tiebreak: true,
            dedupe_by_value: false,
            top_k_first: false,
            arb: ArbBend::default(),
        }
    }
}

/// One configured search: the rollout (policy + knobs) plus the per-activation
/// class statics the recorder captured, plus the test seams.
#[derive(Clone, Copy)]
pub struct Search<'a> {
    pub roll: Rollout<'a>,
    pub act: &'a ActStatics,
    pub bend: PlanBend,
    /// `AiPlanner._playout_sig(state, player)` (:1305-1307) for THIS activation.
    /// An INPUT, never recomputed — see the module header of `arbitration.rs`.
    /// `None` means the caller cannot supply one, and a close top-2 then declines
    /// with `Unsupported::PlayoutArbitration` instead of inventing a dice stream.
    pub sig: Option<i64>,
}

/// The three seams `resolve` branches on, off the resolved knobs.
fn seams_of(knobs: &Knobs) -> Seams {
    Seams {
        spacing: knobs.seam_spacing,
        cast: knobs.seam_cast,
        path: knobs.seam_path,
        hero_attach: knobs.hero_attach,
        charge_landing: knobs.charge_landing,
    }
}

/// NML-1073 M4-7 — the tier-2 obstacle index for THIS planner call, built once
/// from the root state and shared by every rollout underneath it. `None` unless
/// the path seam is on, which is what keeps a seam-off search byte-identical.
fn reach_of(seams: Seams, state: &State, terrain: &Terrain) -> Option<ReachIndex> {
    if !seams.path {
        return None;
    }
    reach_index_for_state(state, terrain)
}

/// The rollout policy for one search — and, since `plan::prefilter` reads the
/// SAME `Policy.tuning` for the root menu, the one place the header's menu
/// knobs are turned into that tuning. NML-1073 M3-5 added `charge_gate` there:
/// a caller that wires no charge-legality gate (tools/core_selfplay.gd) is
/// offered charges the arena's gate refuses, and both menus have to agree on it.
fn policy_of<'a>(
    statics: &'a [UnitStatic],
    terrain: &'a Terrain,
    seams: Seams,
    reach: Option<&'a ReachIndex>,
    knobs: &Knobs,
) -> Policy<'a> {
    let mut p = Policy::new(statics, terrain, seams);
    p.reach = reach;
    p.tuning = tuning_of(knobs);
    p
}

/// The menu tuning a header resolves to — see `policy_of`.
pub fn tuning_of(knobs: &Knobs) -> crate::menu::Tuning {
    crate::menu::Tuning { charge_gate: knobs.charge_gate, ..Default::default() }
}

/// `plan_with_rollout` with everything default — the entry point the game would
/// call. `knobs` carries the resolved search settings AND the two `resolve`
/// seams, so no environment is read here.
pub fn plan_with_rollout(
    state: &State,
    terrain: &Terrain,
    statics: &[UnitStatic],
    knobs: &Knobs,
    act: &ActStatics,
    player: i64,
) -> Result<Pick, Unsupported> {
    let seams = seams_of(knobs);
    let index = reach_of(seams, state, terrain);
    let roll = Rollout::new(policy_of(statics, terrain, seams, index.as_ref(), knobs), *knobs);
    let mut sc = Scratch::default();
    Search::new(roll, act).run(state, player, &mut sc)
}

/// The same entry point WITH the recorded playout signature, which is what a
/// corpus whose acts arbitrated has to be replayed through.
#[allow(clippy::too_many_arguments)]
pub fn plan_with_rollout_sig(
    state: &State,
    terrain: &Terrain,
    statics: &[UnitStatic],
    knobs: &Knobs,
    act: &ActStatics,
    player: i64,
    sig: Option<i64>,
) -> Result<Pick, Unsupported> {
    let seams = seams_of(knobs);
    let index = reach_of(seams, state, terrain);
    let roll = Rollout::new(policy_of(statics, terrain, seams, index.as_ref(), knobs), *knobs);
    let mut sc = Scratch::default();
    let mut search = Search::new(roll, act);
    search.sig = sig;
    search.run(state, player, &mut sc)
}

/// The 1-ply `AiPlanner.plan` (:21-45) on its own, for the `top_k <= 0` branch
/// and for the safety valve the GDScript documents as "byte-identical".
pub fn plan(
    state: &State,
    terrain: &Terrain,
    statics: &[UnitStatic],
    knobs: &Knobs,
    act: &ActStatics,
    player: i64,
) -> Result<Option<OnePly>, Unsupported> {
    let seams = seams_of(knobs);
    let index = reach_of(seams, state, terrain);
    let roll = Rollout::new(policy_of(statics, terrain, seams, index.as_ref(), knobs), *knobs);
    let mut sc = Scratch::default();
    Search::new(roll, act).plan(state, player, &mut sc)
}

impl<'a> Search<'a> {
    pub fn new(roll: Rollout<'a>, act: &'a ActStatics) -> Search<'a> {
        Search { roll, act, bend: PlanBend::default(), sig: None }
    }

    /// `AiPlanner.top_k_default` ai_planner.gd:52-56 — the recorded knob already
    /// IS the resolved value (`clampi(int(NML_TOP_K), 1, 32)` or the const), so a
    /// corpus that carries no knob answers with the const. Same contract as
    /// `Rollout::horizon`.
    pub fn top_k(&self) -> i64 {
        if let Some(k) = self.bend.top_k {
            return k;
        }
        if self.roll.knobs.top_k > 0 {
            self.roll.knobs.top_k
        } else {
            ROLLOUT_TOP_K
        }
    }

    /// `AiPlanner.close_margin` ai_planner.gd:82-86 — the env override is taken
    /// only when it parses to a NON-negative float; anything else keeps the knob.
    pub fn close_margin(&self) -> f64 {
        let m = self.roll.knobs.playout_margin;
        if m >= 0.0 {
            m
        } else {
            PLAYOUT_CLOSE_MARGIN
        }
    }

    /// The two whole-search declines, checked before any work is paid for: a
    /// net-guided playout and the fitted eval are different brains, and a green
    /// gate against either would be measuring the wrong thing.
    fn admissible(&self) -> Result<(), Unsupported> {
        if !self.act.heuristic_playout() {
            return Err(Unsupported::NetPlayout);
        }
        if self.act.fit_mode {
            return Err(Unsupported::FittedEval);
        }
        Ok(())
    }

    /// PHASE 0+1 — the ROOT score and the 1-ply prefilter, shared by `plan` and
    /// `plan_with_rollout` (the GDScript writes the same loop twice, :29-39 and
    /// :129-140; one copy here is one thing to keep in step).
    ///
    /// Iteration is CAPTURE order over the state's unit dictionary, and the menu
    /// is taken in BUILD order — both are the contract `idx` rests on.
    fn prefilter(
        &self,
        state: &State,
        player: i64,
        sc: &mut Scratch,
    ) -> Result<(f64, Vec<ScoredRow>), Unsupported> {
        let statics = self.roll.policy.statics;
        let terrain = self.roll.policy.terrain;
        let base = score(state, player, &reply_threat(statics, state, player));
        let mut scored: Vec<ScoredRow> = Vec::new();
        let hero_attach = self.roll.policy.seams.hero_attach;
        for i in 0..state.units() {
            // D1-B4b: the three-term pool filter, plus — only under
            // `Seams::hero_attach` — "a joined hero has no activation of its own".
            if !state.can_activate(i, player, hero_attach) {
                continue;
            }
            let key = state.key(i);
            // A SHAKEN unit gets its recovery hold and nothing else (:133-134) —
            // the same rule the rollout policy applies inside a playout.
            let menu: Vec<Candidate> = if state.shaken[i] {
                vec![Candidate::hold(key)]
            } else {
                // The ROOT menu reads the SAME two class constants the rollout
                // policy reads, so it takes the same `Tuning`: one knob in the
                // GDScript must stay one knob here.
                candidates_tuned(state, terrain, statics, i, sc, self.roll.policy.tuning)
            };
            for cand in menu {
                let next = self.roll.policy.resolve(state, &cand)?;
                let s = score(&next, player, &reply_threat(statics, &next, player));
                scored.push(ScoredRow {
                    idx: scored.len(),
                    unit_key: key.to_string(),
                    cand,
                    score: s,
                });
            }
        }
        Ok((base, scored))
    }

    /// `AiPlanner.plan` ai_planner.gd:21-45 — the 1-ply pick. The argmax runs in
    /// BUILD order with a STRICT `>`, so a tie keeps the first candidate seen;
    /// that is the same winner the sorted array's head names, and the runner-up
    /// is a RUNNING second best, not simply the second-ranked row.
    pub fn plan(
        &self,
        state: &State,
        player: i64,
        sc: &mut Scratch,
    ) -> Result<Option<OnePly>, Unsupported> {
        self.admissible()?;
        let (base, scored) = self.prefilter(state, player, sc)?;
        let mut best: Option<usize> = None;
        let mut runner: Option<usize> = None;
        for i in 0..scored.len() {
            let s = scored[i].score;
            if best.is_none() || s > scored[best.unwrap()].score {
                runner = best;
                best = Some(i);
            } else if runner.is_none() || s > scored[runner.unwrap()].score {
                runner = Some(i);
            }
        }
        let b = match best {
            None => return Ok(None), // `{"used": false}`
            Some(b) => b,
        };
        Ok(Some(OnePly {
            unit_key: scored[b].unit_key.clone(),
            action: scored[b].cand.clone(),
            expectation_before: base,
            expectation_after: scored[b].score,
            runner_up: runner.map(|r| {
                (scored[r].unit_key.clone(), scored[r].cand.clone(), scored[r].score)
            }),
        }))
    }

    /// `AiPlanner.plan_with_rollout` ai_planner.gd:118-275.
    pub fn run(
        &self,
        state: &State,
        player: i64,
        sc: &mut Scratch,
    ) -> Result<Pick, Unsupported> {
        self.admissible()?;
        let top_k = self.top_k();
        if top_k <= 0 {
            // :126 — the safety valve degrades to `plan()`, which answers with a
            // different dictionary. The caller routes, this function does not lie.
            return Err(Unsupported::OnePlyDegrade);
        }
        let (base, scored) = self.prefilter(state, player, sc)?;
        if scored.is_empty() {
            return Err(Unsupported::NoCandidate); // `{"used": false}`
        }

        // PHASE 2 — the sort.
        let order = rank(&scored, self.bend.idx_tiebreak);
        // `idx_to_pos` (:147) — build-order idx -> rank in the sorted array.
        let mut pos_of = vec![0usize; scored.len()];
        for (r, &i) in order.iter().enumerate() {
            pos_of[i] = r;
        }

        // PHASE 3 — the pool.
        let (covered, pool) = build_pool(&scored, &order, top_k, self.bend);

        // PHASE 4 — exactly ONE rollout per pool candidate, in pool order.
        let mut best: Option<(usize, f64)> = None;
        let mut runner: Option<(usize, f64)> = None;
        let mut best_idx: i64 = -1;
        let mut runner_idx: i64 = -1;
        let mut rs: Vec<(i64, f64)> = Vec::with_capacity(pool.len());
        let mut last_leaf: Option<State> = None;
        for &i in &pool {
            let ends = self.roll.rollout_boundaries(state, &scored[i].cand, player, -1, sc)?;
            let v = self.roll.blend_score(&ends, player, self.act.opener_seat);
            rs.push((i as i64, v));
            if best.is_none_or(|(_, b)| v > b) {
                // The OLD best becomes the runner, with its OLD sorted position
                // (:207-208) — `runner_idx` is set BEFORE `best_idx` moves.
                runner = best;
                runner_idx = best_idx;
                best = Some((i, v));
                best_idx = pos_of[i] as i64;
                if !ends.is_empty() {
                    last_leaf = ends.into_iter().next_back();
                }
            } else if runner.is_none_or(|(_, r)| v > r) {
                runner = Some((i, v));
                runner_idx = pos_of[i] as i64;
            }
        }
        let (bi, brs) = best.expect("a non-empty scored array always yields a non-empty pool");

        // PHASE 5 — the stochastic arbitration (ai_planner.gd:231-265).
        let mut bi = bi;
        let mut brs = brs;
        let mut runner = runner;
        let mut arbitration = None;
        if self.act.playout_search {
            if let Some((ri, r)) = runner {
                if (brs - r).abs() < self.close_margin() {
                    let Some(sig) = self.sig else {
                        // No recorded signature: the seeds cannot be built, and a
                        // guessed stream would be a silent lie. Decline instead.
                        return Err(Unsupported::PlayoutArbitration);
                    };
                    let arb = arbitrate_bent(
                        &self.roll,
                        state,
                        &scored[bi].cand,
                        &scored[ri].cand,
                        player,
                        sig,
                        self.bend.arb,
                        sc,
                    )?;
                    if arb.swapped {
                        // The whole record swaps, `expectation.after` included:
                        // the GDScript exchanges the two rolled DICTIONARIES
                        // (:258-261), so the winner carries the runner's rollout
                        // value. `best_idx`/`runner_idx` were written BEFORE this
                        // block (:219-220) and do NOT swap.
                        runner = Some((bi, brs));
                        bi = ri;
                        brs = r;
                    }
                    arbitration = Some(arb);
                }
            }
        }

        // PHASE 6 — emission.
        let unit_key = scored[bi].unit_key.clone();
        let mut waits = 0i64;
        for i in 0..state.units() {
            if state.can_activate(i, player, self.roll.policy.seams.hero_attach)
                && state.key(i) != unit_key
            {
                waits += 1;
            }
        }
        Ok(Pick {
            unit_key,
            action: scored[bi].cand.clone(),
            expectation_before: base,
            expectation_after: brs,
            runner_up: runner
                .map(|(r, v)| (scored[r].unit_key.clone(), scored[r].cand.clone(), v)),
            waits,
            rolled_units: covered,
            scored: order
                .iter()
                .map(|&i| {
                    (i as i64, scored[i].unit_key.clone(), scored[i].cand.kind, scored[i].score)
                })
                .collect(),
            pool_idx: pool,
            rs,
            best_idx,
            runner_idx,
            last_leaf,
            arbitration,
        })
    }
}

/// PHASE 2 — `scored.sort_custom(...)` ai_planner.gd:143-146: score DESCENDING,
/// with an EXPLICIT `idx` ASCENDING tiebreak. Returns the build-order indices in
/// ranked order.
///
/// `sort_unstable_by` is deliberate. With the idx clause the comparator is a
/// TOTAL order, so stability cannot matter and the result is the only one any
/// correct sort can reach — which is what makes it safe to compare against
/// Godot's `sort_custom`, whose stability is not specified. Rust's STABLE sort
/// would give the right answer even with the clause removed, hiding the missing
/// tiebreak behind its own stability and making the red proof vacuous.
pub fn rank(scored: &[ScoredRow], idx_tiebreak: bool) -> Vec<usize> {
    let mut order: Vec<usize> = (0..scored.len()).collect();
    if idx_tiebreak {
        order.sort_unstable_by(|&a, &b| {
            let (sa, sb) = (scored[a].score, scored[b].score);
            if sa != sb {
                sb.partial_cmp(&sa).unwrap_or(Ordering::Equal)
            } else {
                a.cmp(&b)
            }
        });
    } else {
        order.sort_unstable_by(|&a, &b| {
            scored[b].score.partial_cmp(&scored[a].score).unwrap_or(Ordering::Equal)
        });
    }
    order
}

/// PHASE 3 — the four pool guarantees, ai_planner.gd:156-185, IN ORDER. Returns
/// `(covered, pool)`: the coverage keys (the pick's `rolled_units`) and the
/// build-order `idx` of every candidate that gets a rollout, in pool order.
///
/// The order of the four passes is itself load-bearing: the pool is played out
/// front to back and the winner is a FIRST-WINS argmax, so two candidates with
/// the same rollout value are settled by which guarantee put them in the pool.
pub fn build_pool(
    scored: &[ScoredRow],
    order: &[usize],
    top_k: i64,
    bend: PlanBend,
) -> (Vec<String>, Vec<usize>) {
    // Both per-unit ledgers are filled in ONE pass over the RANKED order,
    // exactly where the GDScript fills them (:163-169).
    let mut covered: Vec<String> = Vec::new();
    let mut coverage: Vec<usize> = Vec::new(); // build idx of each unit's best
    let mut patient_units: Vec<&str> = Vec::new();
    let mut patient_of: Vec<usize> = Vec::new();
    for &i in order {
        let key = scored[i].unit_key.as_str();
        if !covered.iter().any(|k| k == key) {
            covered.push(key.to_string());
            coverage.push(i);
        }
        if scored[i].cand.patient && !patient_units.iter().any(|k| *k == key) {
            patient_units.push(key);
            patient_of.push(i);
        }
    }
    let mut pool: Vec<usize> = Vec::new();
    let slice = &order[..(top_k.max(0) as usize).min(order.len())];
    // a. per-unit coverage. The GDScript appends here WITHOUT a dedupe check
    //    (:164-166): `covered` already guarantees each unit appears once.
    // b. the global top-K slice.
    if bend.top_k_first {
        for &i in slice {
            push_pool(&mut pool, scored, i, bend.dedupe_by_value);
        }
        for &i in &coverage {
            push_pool(&mut pool, scored, i, bend.dedupe_by_value);
        }
    } else {
        pool.extend_from_slice(&coverage);
        for &i in slice {
            push_pool(&mut pool, scored, i, bend.dedupe_by_value);
        }
    }
    // c. R8 — every unit's first PATIENT candidate (:177-179).
    for &i in &patient_of {
        push_pool(&mut pool, scored, i, bend.dedupe_by_value);
    }
    // d. D23 — every SECOND-WAVE candidate (:182-185).
    for &i in order {
        if scored[i].cand.wave.as_deref().unwrap_or("").is_empty() {
            continue;
        }
        push_pool(&mut pool, scored, i, bend.dedupe_by_value);
    }
    (covered, pool)
}

/// `if not pool.has(cand): pool.append(cand)` — the pool's dedupe.
///
/// Each candidate dictionary carries its own `idx`, so CONTENT equality and
/// reference equality coincide on them: whichever of the two Godot's
/// `Array.has` uses, no two distinct rows can ever compare equal, and `idx` is
/// therefore the safe port of the check. `by_value` is the test seam that
/// compares the candidate's content with `idx` REMOVED — what a port that
/// reasons about "the same move" instead of "the same row" would do, and the
/// only reading of the check that can behave differently.
fn push_pool(pool: &mut Vec<usize>, scored: &[ScoredRow], i: usize, by_value: bool) {
    let dup = if by_value {
        pool.iter().any(|&j| same_value(&scored[j], &scored[i]))
    } else {
        pool.contains(&i)
    };
    if !dup {
        pool.push(i);
    }
}

/// Content equality of two prefilter rows, `idx` excluded. Floats compare BY
/// BITS: this is a dedupe, not a parity bar.
fn same_value(a: &ScoredRow, b: &ScoredRow) -> bool {
    a.unit_key == b.unit_key
        && a.score.to_bits() == b.score.to_bits()
        && a.cand.kind == b.cand.kind
        && a.cand.unit == b.cand.unit
        && a.cand.shoot == b.cand.shoot
        && a.cand.charge == b.cand.charge
        && a.cand.patient == b.cand.patient
        && a.cand.wave == b.cand.wave
        && match (&a.cand.dest, &b.cand.dest) {
            (None, None) => true,
            (Some(x), Some(y)) => (0..3).all(|k| x[k].to_bits() == y[k].to_bits()),
            _ => false,
        }
}
