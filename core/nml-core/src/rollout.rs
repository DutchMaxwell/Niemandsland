//! The ROUND ROLLOUT and the blended value — `AiPlanner.rollout_boundaries`
//! (ai_planner.gd:365-397), `_imagined_round_end` (:344-362), `_cross_round`
//! (:462-476) with `_round_start_refresh` (:446-459) and `_blend_score`
//! (:439-452). This is what the 1-ply search pays per pool candidate, and the
//! number it returns is the one the pick is made on.
//!
//! The shape of a rollout: resolve the opener, then let the two sides alternate
//! greedy activations until BOTH are dry; that is a round end, and it is booked
//! like a real one (seize, destroy step, VP) before the boundary is snapshotted.
//! Cross into the next round and repeat, up to `horizon` rounds. `_blend_score`
//! then prices every boundary and folds them into one number.
//!
//! Five parity traps live here, each marked at its line:
//!   * the boundary snapshot is taken from the state the round end was booked
//!     ON, and the walker continues on a fresh clone — sharing them would let a
//!     later round rewrite an earlier boundary;
//!   * `vp`/`vp_memo` are REPLACED, never written in place, because
//!     `clone_state` hands both down by reference;
//!   * `w *= dd` is a repeated multiply, not `dd.powi(k)` — the two drift;
//!   * the guard is `(units + 2) * rounds_left` evaluated ONCE, on the opening
//!     state and the opening `rounds_left`;
//!   * a tail-cap truncation is priced MID-ROUND with NO round-end bookkeeping.

use std::rc::Rc;

use serde_json::{json, Value};

use crate::acts::Knobs;
use crate::menu::Candidate;
use crate::mission::{apply_destroy_step, playout_seize, vp_of, vp_score_round};
use crate::playout::{other_player, Policy};
use crate::score::score;
use crate::sim::{reply_threat, Scratch, Unsupported};
use crate::state::State;
use crate::unit::UnitStatic;
use crate::DISCOUNT;

/// `AiPlanner.ROLLOUT_HORIZON_ROUNDS` ai_planner.gd:280.
pub const ROLLOUT_HORIZON_ROUNDS: i64 = 2;
/// `AiPlanner.DEPTH_DISCOUNT` ai_planner.gd:400 — the same 0.5 the mission eval
/// discounts a future activation by, but a different rule; kept separate.
pub const DEPTH_DISCOUNT: f64 = DISCOUNT;
/// `GameUnit.CASTER_POINTS_CAP` game_unit.gd:56.
pub const CASTER_POINTS_CAP: i64 = 6;

/// WHY a rollout stopped. Not part of the GDScript (which returns the boundary
/// array alone), but the array cannot tell the four apart, and a gate that
/// cannot see how many of its rollouts hit the GUARD is measuring an unknown
/// mixture of the rule path and a logic error.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Stop {
    /// `rounds_left <= 0` — the horizon was played out in full.
    Horizon,
    /// `cur.round >= cur.rounds_total` — the imagined game ended first.
    GameEnd,
    /// SPEED L2's per-seat activation cap truncated the rollout mid-round.
    TailCap,
    /// The `(units + 2) * rounds_left` backstop ran out: a logic error in the
    /// policy, never the rule path.
    Guard,
}

/// One rollout's whole configuration: the greedy policy plus the search knobs
/// the recording ran with (`AiActRecorder._header_line`, act_recorder.gd:118-123).
#[derive(Clone, Copy)]
pub struct Rollout<'a> {
    pub policy: Policy<'a>,
    pub knobs: Knobs,
}

impl<'a> Rollout<'a> {
    pub fn new(policy: Policy<'a>, knobs: Knobs) -> Rollout<'a> {
        Rollout { policy, knobs }
    }

    fn statics(&self) -> &'a [UnitStatic] {
        self.policy.statics
    }

    /// `AiPlanner.horizon` ai_planner.gd:284-288 — the recorded knob already IS
    /// the resolved value (`clampi(int(NML_HORIZON), 1, 3)` or the const); a
    /// corpus that carries no knob at all answers with the const.
    pub fn horizon(&self) -> i64 {
        if self.knobs.horizon > 0 {
            self.knobs.horizon
        } else {
            ROLLOUT_HORIZON_ROUNDS
        }
    }

    /// `AiPlanner.depth_discount` ai_planner.gd:409-418 — the env override is
    /// accepted only inside (0.0, 1.0]; anything else keeps the const, and the
    /// same validation runs here so a junk knob cannot silently reshape a blend.
    pub fn depth_discount(&self) -> f64 {
        let dd = self.knobs.depth_discount;
        if dd > 0.0 && dd <= 1.0 {
            dd
        } else {
            DEPTH_DISCOUNT
        }
    }

    /// `AiPlanner._tail_cap_for` ai_planner.gd:325-333 — SPEED L2's per-seat cap
    /// on simulated activations. 0 = off, and the header records only seats 1
    /// and 2 (`NML_PLAYOUT_TAIL_CAP_P1/P2`), so any other seat id is uncapped —
    /// which is what an unset env var answers for it too.
    pub fn tail_cap_for(&self, me: i64) -> i64 {
        match me {
            1 => self.knobs.tail_cap_p1.max(0),
            2 => self.knobs.tail_cap_p2.max(0),
            _ => 0,
        }
    }

    /// `AiPlanner.rollout_boundaries` ai_planner.gd:365-397 — the state at every
    /// round boundary of the horizon (index 0 = end of the CURRENT round, last =
    /// the horizon end). `horizon_rounds <= 0` takes the knob.
    pub fn rollout_boundaries(
        &self,
        state: &State,
        first_action: &Candidate,
        me: i64,
        horizon_rounds: i64,
        sc: &mut Scratch,
    ) -> Result<Vec<State>, Unsupported> {
        Ok(self.rollout_traced(state, first_action, me, horizon_rounds, sc)?.0)
    }

    /// The same rollout, reporting WHY it stopped — see `Stop`.
    pub fn rollout_traced(
        &self,
        state: &State,
        first_action: &Candidate,
        me: i64,
        horizon_rounds: i64,
        sc: &mut Scratch,
    ) -> Result<(Vec<State>, Stop), Unsupported> {
        let horizon_rounds = if horizon_rounds <= 0 { self.horizon() } else { horizon_rounds };
        let mut out: Vec<State> = Vec::new();
        let mut cur = self.policy.resolve(state, first_action)?;
        let mut turn = other_player(state, me);
        let mut rounds_left = horizon_rounds.max(1);
        // Evaluated ONCE, on the OPENING state's unit count and the OPENING
        // rounds_left — it is a backstop against a policy that never goes dry,
        // not a per-round budget.
        let mut guard: i64 = (state.units() as i64 + 2) * rounds_left;
        let tail_cap = self.tail_cap_for(me);
        let mut steps: i64 = 0;
        while guard > 0 {
            guard -= 1;
            if tail_cap > 0 && steps >= tail_cap {
                // Truncated MID-ROUND: priced as it stands, with NO round-end
                // bookkeeping at all (NML-1051) — no seize, no destroy step, no VP.
                out.push(cur);
                return Ok((out, Stop::TailCap));
            }
            steps += 1;
            // R9: our OWN side steps danger-aware (rich leaf), the imagined
            // opponent greedily (cheap leaf).
            let mut a = self.policy.policy_step(&cur, turn, turn == me, sc)?;
            if a.is_none() {
                turn = other_player(&cur, turn);
                a = self.policy.policy_step(&cur, turn, turn == me, sc)?;
                if a.is_none() {
                    // BOTH sides dry: the round is over.
                    if self.knobs.imagined_round_end {
                        imagined_round_end(&mut cur); // book the end, THEN snapshot
                    }
                    // The snapshot must be frozen: the walker keeps mutating
                    // `cur` through the next round, and a shared reference would
                    // rewrite this boundary. GDScript freezes it the other way
                    // round (it keeps the reference and rebinds `cur` to a fresh
                    // `clone_state`); the two are the same deep copy.
                    out.push(cur.clone());
                    rounds_left -= 1;
                    if rounds_left <= 0 {
                        return Ok((out, Stop::Horizon));
                    }
                    if cur.round >= cur.rounds_total {
                        return Ok((out, Stop::GameEnd));
                    }
                    turn = cross_round(self.statics(), &mut cur);
                    continue;
                }
            }
            let a = a.expect("the dry branch returns above");
            cur = self.policy.resolve(&cur, &a)?;
            turn = other_player(&cur, turn);
        }
        out.push(cur); // guard backstop only — a logic error, never the rule path
        Ok((out, Stop::Guard))
    }

    /// `AiPlanner._blend_score` ai_planner.gd:439-452 — the rollout's boundaries
    /// priced as ONE number. `opener_seat` is the per-pick static
    /// (`AiPlanner.opener_seat`), which the act corpus records per activation.
    ///
    /// Mode 0 (today's default, promoted by the U-wave's 240 mirrored pairs):
    /// both seats take the geometric discount. Mode 1 lets the OPENER vote with
    /// the last boundary alone, mode 2 swaps which seat gets which.
    pub fn blend_score(&self, ends: &[State], player: i64, opener_seat: bool) -> f64 {
        let mode = self.knobs.seat_mode;
        if (mode == 1 && opener_seat) || (mode == 2 && !opener_seat) {
            let last = &ends[ends.len() - 1];
            let incoming = reply_threat(self.statics(), last, player);
            return score(last, player, &incoming);
        }
        let dd = self.depth_discount();
        let mut total = 0.0f64;
        let mut weights = 0.0f64;
        // REPEATED MULTIPLY, not `dd.powi(k)`: at dd = 0.5 the two agree to the
        // bit, at any other discount they do not, and the blend is a ratio of
        // two sums where that difference survives.
        let mut w = 1.0f64;
        for end in ends {
            let incoming = reply_threat(self.statics(), end, player);
            total += w * score(end, player, &incoming);
            weights += w;
            w *= dd;
        }
        total / weights
    }
}

/// `AiPlanner._imagined_round_end` ai_planner.gd:344-362 — a TRUE imagined round
/// boundary books the same round end the factory playout books: seize from the
/// final positions, the marker destroy step, then the round's VP.
///
/// `vp` and `vp_memo` are REPLACED, never written in place: `clone_state`
/// (battle_sim.gd:524) hands both down BY REFERENCE, so an in-place write would
/// leak into sibling rollouts and into the captured live state. In this port the
/// two are `Rc`s, and rebinding them is exactly that replacement.
pub fn imagined_round_end(cur: &mut State) {
    let mut owners: Vec<i64> = cur.objectives.iter().map(|o| o.owner).collect();
    playout_seize(cur, &mut owners);
    if !cur.markers_meta.is_empty() {
        // Taken out and put back so the borrow checker sees what the GDScript
        // does implicitly: these two arrays are the state's own, mutated in place.
        let mut markers = std::mem::take(&mut cur.markers_meta);
        let mut seq = std::mem::take(&mut cur.destroy_seq);
        apply_destroy_step(&mut markers, &mut owners, &mut seq);
        cur.markers_meta = markers;
        cur.destroy_seq = seq;
    }
    let mut vp = vp_of(cur.vp.as_deref());
    let mut memo = cur
        .vp_memo
        .as_deref()
        .and_then(|v| v.as_object())
        .cloned()
        .unwrap_or_default();
    let flavour: Value = cur.vp_flavour.as_deref().cloned().unwrap_or(Value::Null);
    vp_score_round(&owners, &mut vp, &flavour, &mut memo, &cur.markers_meta);
    cur.vp = Some(Rc::new(json!([vp[0], vp[1]])));
    cur.vp_memo = Some(Rc::new(Value::Object(memo)));
}

/// `AiPlanner._round_start_refresh` ai_planner.gd:446-459 — everything the game
/// refreshes at a round start that the imagined rounds ran without: activation
/// and fatigue clear (p.9), spell tokens refill, and Battleborn/Steadfast clears
/// Shaken for free.
///
/// The GDScript bails after the first two writes when the snapshot carries no
/// `GameUnit` (`if gu == null: return`); this port always has the unit's static
/// closure, so that early return has no counterpart — a state without a profile
/// cannot be loaded at all.
pub(crate) fn round_start_refresh(statics: &[UnitStatic], state: &mut State, i: usize) {
    state.activated[i] = false;
    state.fatigued[i] = false;
    let us = &statics[state.roster.profile[i]];
    if us.caster_group {
        // A Caster Group resets to its BEARER COUNT, it does not accumulate.
        state.casts[i] = state.alive[i];
    } else if us.casts_per_round > 0 {
        state.casts[i] = (state.casts[i] + us.casts_per_round).min(CASTER_POINTS_CAP);
    }
    if state.shaken[i] && (us.battleborn_active || us.steadfast_active) {
        state.shaken[i] = false;
    }
}

/// `AiPlanner._cross_round` ai_planner.gd:462-476 — cross the round boundary
/// inside the mental game and return the imagined new round's OPENER: under
/// strict alternation the side with FEWER alive units finished its activations
/// first and opens the next one (GF v3.5.1 p.4); a tie opens with the lower slot.
///
/// `BattleSim.reset_round_mods` (battle_sim.gd:1090) is deliberately NOT called:
/// its only caller is the trainer's round loop (tools/core_selfplay.gd:192), so
/// an imagined round INHERITS the last one's spell modifiers. That is the shipped
/// behaviour, not an oversight of this port.
pub fn cross_round(statics: &[UnitStatic], cur: &mut State) -> i64 {
    cur.round += 1;
    // `counts` is a Dictionary keyed by player id: insertion order is first
    // appearance in capture order, and `players.sort()` then orders it by id.
    let mut ids: Vec<i64> = Vec::new();
    let mut counts: Vec<i64> = Vec::new();
    for i in 0..cur.units() {
        round_start_refresh(statics, cur, i);
        if cur.alive[i] > 0 {
            let p = cur.player[i];
            match ids.iter().position(|k| *k == p) {
                Some(x) => counts[x] += 1,
                None => {
                    ids.push(p);
                    counts.push(1);
                }
            }
        }
    }
    let mut order: Vec<usize> = (0..ids.len()).collect();
    order.sort_by_key(|&x| ids[x]);
    if order.len() == 2 {
        let (a, b) = (order[0], order[1]);
        if counts[a] != counts[b] {
            return if counts[a] < counts[b] { ids[a] } else { ids[b] };
        }
    }
    match order.first() {
        Some(&x) => ids[x],
        None => 0,
    }
}
