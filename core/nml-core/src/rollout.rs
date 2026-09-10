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

use crate::acts::{rule_on, Knobs, EPOCH_7_TABLE_RULES};
use crate::deployment::{self, ArrivalZone, Occupied, Rect};
use crate::io::Seams;
use crate::menu::Candidate;
use crate::rules::has_special_rule;
use crate::terrain::Terrain;
use crate::mission::{apply_destroy_step, playout_seize, vp_of, vp_score_round};
use crate::rng::GodotRng;
use crate::playout::{other_player, Policy};
use crate::score::{score_with, score_with_variant, NO_INCOMING};
use crate::sim::{reply_threat, Scratch, Unsupported, DEFAULT_BASE_RADIUS_M};
use crate::state::State;
use crate::unit::UnitStatic;
use crate::{geom, DISCOUNT};

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

/// PRIMITIVE "Pass Turn", wave 4 — its only book user is `Delayed Action`:
/// "Once per round, if your opponent has more units left to activate than you,
/// then this model's unit may pass its turn instead of activating (may still be
/// activated later)." The table has shipped it since wave 5
/// (`SoloController.delayed_action_*`, solo_controller.gd:7919-8114, applied by
/// `main._solo_pass_turn` :1499); this is the same step in the core's own
/// alternation, which until now could only ever SPEND an activation.
///
/// The carrier that should pass, or `None`. Both guards the table names are
/// here, and they are what makes the step terminate:
///   (a) STRICTLY more (`delayed_action_surplus` :7959). The condition is
///       antisymmetric — `opp > own` for one side is `own >= opp` for the
///       other — so it can never hold for both sides at once and two carriers
///       cannot pass at each other forever.
///   (b) ONCE PER ROUND, per CARRIER UNIT ("this model's unit", ruling 2 at
///       :7943). A carrier already stamped in this round activates instead, so
///       at most one pass per carrier per round exists at all.
///
/// TWO DECLARED SIMPLIFICATIONS, in the `second_wind_candidate` manner (never
/// silent):
///   * WHICH carrier. The table picks its most valuable un-activated unit when
///     that unit carries the rule (`delayed_action_pass_choice` :8085, worth =
///     points); this bookkeeping layer has no points and picks by `alive`, the
///     same stand-in block B8 declared for `_plan_ev_of`.
///   * WHETHER to pass. The table only passes when the prize stands inside an
///     un-committed enemy's reach (`delayed_action_threatened` :8118 plus
///     `_has_los`); the greedy playout passes whenever the RULE's own condition
///     stands. The book text carries no threat clause — that half is the AI's
///     taste, not the rule — so this is the rule minus a heuristic.
///
/// Symmetric by construction: the core has no `ai_slot`/`human_slot` split, so
/// the step applies to whichever side holds the turn (the block-B8 FIRE GATE
/// note, sim.rs).
fn delayed_action_passer(
    statics: &[UnitStatic],
    state: &State,
    player: i64,
    seams: Seams,
) -> Option<usize> {
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) {
        return None;
    }
    let foe = other_player(state, player);
    if foe == player {
        return None; // one-sided state: nobody to hand the turn to
    }
    let (mut own, mut opp) = (0i64, 0i64);
    let mut best: Option<(usize, i64)> = None;
    for i in 0..state.units() {
        if state.can_activate(i, player, seams.hero_attach) {
            own += 1;
            if statics[state.roster.profile[i]].delayed_action_active
                && state.delayed_action_round[i] != state.round
                && best.map_or(true, |(_, v)| state.alive[i] > v)
            {
                best = Some((i, state.alive[i]));
            }
        } else if state.can_activate(i, foe, seams.hero_attach) {
            opp += 1;
        }
    }
    if opp <= own {
        return None; // guard (a): equality refuses, and that IS the guard
    }
    best.map(|(i, _)| i)
}

/// PRIMITIVE "Coordinate", wave 4 — an ACTIVATION-ORDER effect, not a stat
/// change (`main.gd:7954` classifies it exactly so): "At the end of this unit's
/// activation, another friendly unit within 12\" that hasn't activated yet may
/// be activated immediately. May not be used if this unit was activated via
/// Coordinate." Word-identical in both snapshot books that carry it, and the
/// table has shipped the whole flow since wave 4
/// (`SoloController.coordinate_*`, solo_controller.gd:770-868, fired from
/// `main._solo_after_activation` :1112). This is the SECOND user of the
/// extra-activation family Second Wind opened (sim.rs block B8), but at a
/// different moment: B8 fires when the ROUND would close, Coordinate fires at
/// the end of the BEARER's own activation, mid-round, and hands to somebody
/// else.
///
/// The friend that takes the hand-off, or `None`. All four of the table's gates
/// are here — `coordinate_refusal` (:792) plus the range read:
///   * DEAD — a bearer that did not survive its own activation hands nothing
///     off (maintainer ruling, :778); `alive[bearer] <= 0` refuses.
///   * CHAIN — "May not be used if this unit was activated via Coordinate", so
///     at most TWO activations ever ride one hand-off (:780).
///   * NONE — nobody legal within the reach.
///   * The reach is the registry's own `range_in` (`coordinate_range_of` :803),
///     measured BASE EDGE to base edge like `nearest_melee_gap_in` (:818-830),
///     never centre to centre — a 12\" reading off a vehicle oval's centre is
///     simply wrong.
/// Reserves are invisible to it (`dormant`), the same exclusion the table's
/// `is_eligible` already owns.
///
/// ONE DECLARED SIMPLIFICATION, in the `second_wind_candidate` manner (never
/// silent): WHICH friend. The table picks the highest `activation_payoff`
/// (`coordinate_candidate` :837-858), which runs the AI's own search tree; this
/// bookkeeping layer has no such tree and picks by `alive`, the stand-in block
/// B8 declared for `_plan_ev_of`. WHETHER to hand off is not a choice at all
/// here — the book grants it unconditionally, so the greedy playout takes it
/// whenever it is legal.
///
/// KNOWN GAP, stated plainly and inherited from B8: the table's own both-AI
/// arena driver never calls `_solo_after_activation`, so no recorded arena game
/// can show a table-side Coordinate hand-off. The fixture tests are this port's
/// correctness proof.
fn coordinate_receiver(
    statics: &[UnitStatic],
    state: &State,
    bearer: usize,
    seams: Seams,
) -> Option<usize> {
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) {
        return None;
    }
    let reach = statics[state.roster.profile[bearer]].coordinate_range_in;
    if reach <= 0.0 || state.alive[bearer] <= 0 {
        return None; // not a carrier, or it died in its own activation
    }
    if state.coordinate_via_round[bearer] == state.round {
        return None; // the anti-chain clause
    }
    let player = state.player[bearer];
    let mut best: Option<(usize, i64)> = None;
    for i in 0..state.units() {
        if i == bearer || state.dormant[i] || !state.can_activate(i, player, seams.hero_attach) {
            continue;
        }
        if best.map_or(false, |(_, v)| state.alive[i] <= v) {
            continue; // cheaper than the gap, so it goes first
        }
        let gap = geom::edge_gap_shaped_in(
            &state.positions[bearer],
            &state.radii[bearer],
            state.base_shape(bearer),
            &state.positions[i],
            &state.radii[i],
            state.base_shape(i),
            DEFAULT_BASE_RADIUS_M,
        );
        if gap <= reach {
            best = Some((i, state.alive[i]));
        }
    }
    best.map(|(i, _)| i)
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

    /// Coordinate's own step: the activation `acted` just spent hands the turn
    /// on to a friend in reach, IMMEDIATELY, off the same side's turn. `true`
    /// when one fired.
    ///
    /// The receiver's own action is picked exactly as `policy_step`
    /// (playout.rs:148-180) picks any other — the same candidate list, the same
    /// leaf score, the same `rich` split by seat — but over ONE unit instead of
    /// the whole pool, because the RULE names the unit and the greedy pick may
    /// not overrule it. That is the core's shape of the table's
    /// `coordinate_hand_off` (:864), which forces the next activation onto the
    /// receiver by stamping `_peeked_unit` and bypassing the seeded section
    /// draw: the rule names the unit, the D6 does not.
    fn coordinate_hand_off(
        &self,
        cur: &mut State,
        acted: &Candidate,
        me: i64,
        sc: &mut Scratch,
    ) -> Result<bool, Unsupported> {
        let Some(&bearer) = cur.roster.index.get(&acted.unit) else { return Ok(false) };
        let Some(recv) = coordinate_receiver(self.statics(), cur, bearer, self.policy.seams) else {
            return Ok(false);
        };
        let player = cur.player[bearer];
        let rich = player == me;
        let mut best: Option<Candidate> = None;
        let mut best_s = f64::NEG_INFINITY;
        for action in self.policy.policy_candidates(cur, recv, sc) {
            let next = self.policy.resolve(cur, &action)?;
            let s = if rich {
                let incoming = reply_threat(self.statics(), &next, player);
                score_with(&next, self.statics(), player, &incoming, self.policy.fit)
            } else {
                score_with(&next, self.statics(), player, NO_INCOMING, self.policy.fit)
            };
            if s > best_s {
                best_s = s;
                best = Some(action);
            }
        }
        let Some(action) = best else { return Ok(false) };
        let next = self.policy.resolve(cur, &action)?;
        *cur = next;
        // The anti-chain stamp lands on the RECEIVER, which is what the table
        // does too (`mark_activated_via_coordinate`, game_unit.gd:323): a unit
        // that took a hand-off may not pass one on in the same round.
        cur.coordinate_via_round[recv] = cur.round;
        Ok(true)
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
        // The OPENER is an activation like any other, so its own end is a
        // Coordinate trigger like any other. Skipping it here would make the
        // rule invisible to exactly the pick the search is pricing.
        self.coordinate_hand_off(&mut cur, first_action, me, sc)?;
        let mut turn = other_player(state, me);
        let mut rounds_left = horizon_rounds.max(1);
        // Evaluated ONCE, on the OPENING state's unit count and the OPENING
        // rounds_left — it is a backstop against a policy that never goes dry,
        // not a per-round budget.
        let mut guard: i64 = (state.units() as i64 + 2) * rounds_left;
        // Wave 4 — the backstop above is sized for ACTIVATIONS alone, and a
        // pass spends a loop turn without spending one. A carrier-rich army
        // would therefore hit `Stop::Guard` ("a logic error, never the rule
        // path") ON the rule path. Guard (b) caps the passes of a round at one
        // per carrier, so `units` per round is the exact headroom — added
        // inside the epoch gate, so an `rules_epoch < 7` record keeps the
        // byte-identical budget it replays with today.
        if rule_on(self.policy.seams.rules_epoch, EPOCH_7_TABLE_RULES) {
            guard += state.units() as i64 * rounds_left;
        }
        let tail_cap = self.tail_cap_for(me);
        let mut steps: i64 = 0;
        while guard > 0 {
            guard -= 1;
            // "Pass Turn" — the acting side DECLINES instead of activating. The
            // stamp is the only thing that moves: no unit is marked activated,
            // which is the rule's own last clause ("may still be activated
            // later"). `steps` is untouched too — a pass is not an activation,
            // so it must not eat the seat's tail-cap budget.
            if let Some(pi) = delayed_action_passer(self.statics(), &cur, turn, self.policy.seams) {
                cur.delayed_action_round[pi] = cur.round;
                turn = other_player(&cur, turn);
                continue;
            }
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
                    // Wave 4 — the Reinforcement beat sits at the ROUND START,
                    // after `cross_round`'s refresh exactly as the table runs
                    // it after its own round reset (main.gd:10174-10191). It
                    // does not touch `turn`: arriving and withdrawing are
                    // deployment, not activations, so the opener the round
                    // count just decided still opens.
                    reinforcement_round_start(
                        self.statics(),
                        self.policy.terrain,
                        self.policy.seams,
                        &mut cur,
                    );
                    continue;
                }
            }
            let a = a.expect("the dry branch returns above");
            cur = self.policy.resolve(&cur, &a)?;
            // Coordinate: the extra activation rides the SAME turn, so the
            // alternation below still flips exactly once. It IS an activation
            // (unlike Delayed Action's pass), so it spends a `steps` of the
            // seat's tail-cap budget.
            if self.coordinate_hand_off(&mut cur, &a, me, sc)? {
                steps += 1;
            }
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
        self.blend_score_leaf(ends, player, opener_seat, &[], 0.0)
    }

    /// NML-1165 R4 (DESIGN_value_net §7 "L2 leaf blend") — `blend_score` with a
    /// LEARNED value added at the leaf: every boundary is priced
    /// `hand + w * vals[k]` before the seat mode or the geometric discount
    /// folds it, so the net moves the number the pick is made on rather than
    /// the order it is made in. `vals` is index-parallel to `ends` and may be
    /// LONGER — the caller hands out one activation's whole leaf batch from
    /// this rollout's offset on, and only the first `ends.len()` are read.
    ///
    /// An EMPTY `vals` takes the hand score UNTOUCHED — not `+ 0.0 * v`, which
    /// would still round-trip the sum through an addition and turn a `-0.0`
    /// leaf into `+0.0`. That is what makes the default byte-identical.
    pub fn blend_score_leaf(&self, ends: &[State], player: i64, opener_seat: bool,
                            vals: &[f64], w: f64) -> f64 {
        let leaf = |k: usize, s: f64| if vals.is_empty() { s } else { s + w * vals[k] };
        let mode = self.knobs.seat_mode;
        // The evolved-eval seam's read site: `Knobs::eval_variant` (default 0,
        // today's frozen eval) picks which `score::score_hand_variant` arm
        // every taste read below plays.
        let variant = self.knobs.eval_variant;
        if (mode == 1 && opener_seat) || (mode == 2 && !opener_seat) {
            let last = &ends[ends.len() - 1];
            let incoming = reply_threat(self.statics(), last, player);
            let s = score_with_variant(last, self.statics(), player, &incoming, self.policy.fit, variant);
            return leaf(ends.len() - 1, s);
        }
        let dd = self.depth_discount();
        let mut total = 0.0f64;
        let mut weights = 0.0f64;
        // REPEATED MULTIPLY, not `dd.powi(k)`: at dd = 0.5 the two agree to the
        // bit, at any other discount they do not, and the blend is a ratio of
        // two sums where that difference survives.
        // Named `dw`, not `w`: the LEARNED blend weight is the parameter `w`,
        // and a shadowed name here would make the closure above read as if it
        // saw the discount.
        let mut dw = 1.0f64;
        for (k, end) in ends.iter().enumerate() {
            let incoming = reply_threat(self.statics(), end, player);
            let s = score_with_variant(end, self.statics(), player, &incoming, self.policy.fit, variant);
            total += dw * leaf(k, s);
            weights += dw;
            dw *= dd;
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
    if state.shaken[i]
        && (us.battleborn_active
            || us.steadfast_active
            || crate::mods::granted(state, i, "Steadfast"))
    {
        state.shaken[i] = false;
    }
}

/// Battleborn family wave 3 (rules-wave3-battleborn) — main.gd
/// `:_solo_battleborn_recovery` (the army-book round-start recovery): every
/// ALIVE Shaken unit whose whole closure carries one of the die-roll recover
/// aliases rolls ONE die (1..6) and stops being Shaken at its stamped
/// `recover_target` (`DiceRules.is_success` — face >= target, no modifier).
/// The playout books this from arbitration's round boundary, where the seeded
/// `GodotRng` answers the real tray roll; the planner's imagined refresh
/// (`round_start_refresh`, `cross_round`) never rolls — GDScript's
/// `AiPlanner._round_start_refresh` knows neither the aliases nor a die, so
/// the rollout keeps the free-clear Battleborn/Steadfast arm alone.
pub(crate) fn battleborn_recovery_roll(
    statics: &[UnitStatic],
    state: &mut State,
    i: usize,
    rng: &mut GodotRng,
) {
    let target = statics[state.roster.profile[i]].battleborn_recover_target;
    if target == 0 || !state.shaken[i] || state.alive[i] == 0 {
        return;
    }
    let face = rng.randi_range(1, 6);
    if face >= target as i64 {
        state.shaken[i] = false;
    }
    // Rules-must-log: one stderr line when NML_TRACE_RULES=1, same shape as
    // sim.rs's S10 arms.
    crate::sim::trace_rule(
        "round-start",
        "Battleborn recovery",
        &format!(
            "{} rolls {face}, target {target}+ -> {}",
            state.key(i),
            if state.shaken[i] { "stays Shaken" } else { "stops being Shaken" },
        ),
    );
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
/// PRIMITIVE "withdraw and recreate", wave 4 — S5, the seam the plan records
/// as missing ("no seam; the core creates units only at deployment"). Its
/// first book user is `Reinforcement`: "When a unit where all models have this
/// rule is Shaken or fully destroyed, you may remove it from the table as
/// destroyed and place a new copy of it fully within 12" of any table edge at
/// the beginning of the next round after Ambushers have been deployed."
///
/// The table's round-start beat (`main._solo_round_start`, main.gd:10183-10191)
/// in the core's ONLY round boundary, in the table's own order:
///
///   1. ARRIVALS first — the rule times itself AFTER the Ambushers (:10186),
///      and `_reinforcement_arrivals` is awaited before anything else runs.
///   2. WITHDRAWALS after (`_solo_reinforcement_ai_offers` :10191), which is
///      what stops a copy that just came back from being offered again in the
///      same breath.
///
/// WHY THE ROUND BOUNDARY AND NOT `resolve_with`. Neither half is an
/// activation: on the table neither produces an act record, and
/// `sim.rs::resolve_with` is the replay/parity path that applies exactly one
/// recorded act. A replayed corpus therefore reads both halves out of the
/// recorded state (the `reinforcement_used` ledger row and the dormant keys),
/// never out of this driver — the `delayed_action` precedent, one beat over.
///
/// Gated on the FROZEN `EPOCH_7_TABLE_RULES`: a record below 7 crosses the
/// round byte-identically to today.
pub fn reinforcement_round_start(
    statics: &[UnitStatic],
    terrain: &Terrain,
    seams: Seams,
    cur: &mut State,
) {
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) {
        return;
    }
    reinforcement_arrivals(statics, terrain, cur);
    reinforcement_withdrawals(statics, cur);
}

/// The table in WORLD METRES, centred on the origin, or `None` when the header
/// carried no board at all (`terrain.board_in()` is then zero and there is no
/// table to measure a 12" band against — the copy keeps its date, exactly as
/// it does when the strip is full).
fn table_rect(terrain: &Terrain) -> Option<Rect> {
    let [w_in, d_in] = terrain.board_in();
    if w_in <= 0.0 || d_in <= 0.0 {
        return None;
    }
    let (w, d) = (w_in * crate::IN2M, d_in * crate::IN2M);
    Some(Rect::new(-w / 2.0, -d / 2.0, w, d))
}

/// `_reinforcement_prefer_point` (main.gd:10404-10408): the point the automatic
/// search sorts its candidate slots by — the owner's own back edge, so a copy
/// comes back behind its own lines unless that edge is full. EVERY band stays
/// legal; this only decides which legal slot is taken first, and it rides in
/// through `arrive_one`'s `objectives`, whose score is exactly the distance to
/// the nearest listed point.
fn reinforcement_prefer(table: &Rect, player: i64) -> (f64, f64) {
    let frac = if player == 1 { 0.05 } else { 0.95 };
    (table.pos.0 + table.size.0 * 0.5, table.pos.1 + table.size.1 * frac)
}

/// `_reinforcement_blockers` (main.gd:10392-10402): every standing base a
/// returning model may not overlap. A unit in reserve stands nowhere, so it
/// projects nothing.
fn live_bases(st: &State) -> Vec<Occupied> {
    (0..st.units())
        .filter(|&i| !st.dormant[i] && st.alive[i] > 0)
        .flat_map(|i| {
            st.positions[i]
                .iter()
                .zip(&st.radii[i])
                .map(|(p, r)| Occupied { pos: (p[0], p[2]), radius: *r })
                .collect::<Vec<_>>()
        })
        .collect()
}

/// Half 1 — every promised copy that is due lands, in registration order
/// (`reinforcement_due`, solo_controller.gd:6041-6051, "stable order:
/// registration order"). A copy with no legal spot KEEPS its date rather than
/// evaporating (:6046, main.gd:10315-10320).
///
/// `reinforcement_used` is what marks a dormant unit as a Reinforcement
/// promise rather than an ambusher waiting its turn — the two share
/// `State.dormant`, and the plain Ambush arrival is not this driver's beat.
fn reinforcement_arrivals(statics: &[UnitStatic], terrain: &Terrain, st: &mut State) {
    let Some(table) = table_rect(terrain) else {
        return;
    };
    let due: Vec<usize> = (0..st.units())
        .filter(|&i| {
            st.dormant[i]
                && st.reinforcement_used[i]
                && st.earliest_arrival_round[i] >= 0
                && st.earliest_arrival_round[i] <= st.round
        })
        .collect();
    if due.is_empty() {
        return;
    }
    let mut occupied = live_bases(st);
    for i in due {
        let pi = st.roster.profile[i];
        let band_m = statics[pi].reinforcement.within_in * crate::IN2M;
        if band_m <= 0.0 {
            continue;
        }
        let p = &st.profiles.list[pi];
        let n = st.dormant_models[i].max(1) as usize;
        let (base_r, radius) = (p.base_radius, deployment::deploy_footprint_radius(n, p.base_radius));
        let footprint = deployment::deploy_footprint_offsets(n, p.base_radius, false);
        // The p.13 difficult-terrain exemption the arrival branches on, the
        // same two names `arrival_reads` reads (nml-core-py/src/lib.rs:1081).
        let flying = has_special_rule(&p.special_rules, "Flying")
            || has_special_rule(&p.special_rules, "Strider");
        // NO enemy ring and NO beacon. The maintainer's pinned reading
        // (solo_controller.gd:5970-5972): "The landing zone is LITERAL — 12" of
        // ANY edge, the enemy's included. The book names a minimum distance
        // from enemies for Ambush and deliberately does not here, so neither
        // do we."
        let spot = deployment::arrive_one(
            &ArrivalZone::EdgeStrip { table, band_m },
            &[reinforcement_prefer(&table, st.player[i])],
            &mut occupied,
            &[],
            &[],
            0.0,
            terrain,
            radius,
            &footprint,
            base_r,
            flying,
        );
        if !spot.0.is_finite() {
            continue; // the band is full — the promise keeps its date
        }
        let round = st.round;
        // 2b-1 stub: the parameter is declared; the beat itself is 2b-2's.
        deployment::arrive_unit(st, i, spot, round, &statics[pi]);
    }
}

/// Half 2 — every eligible carrier steps off the table. Deterministic, no dice
/// and no knob, exactly as NACHTMAHR plays it (`_solo_reinforcement_ai_offers`,
/// main.gd:10262-10274): a Shaken or destroyed unit is worth far more as a
/// fresh full-strength copy than as a marker, and the rule costs nothing.
///
/// TWO DECLARED SIMPLIFICATIONS, never silent:
///   * A carrier with a JOINED HERO does not withdraw here. The table detaches
///     the hero and leaves him standing (main.gd:10225-10235); the core has no
///     detach transition at all — `attached_to` is written by the loader and
///     by nothing else — so inventing one is a seam of its own. Refusing is
///     the conservative direction: the rule fires less often, never wrongly.
///   * The offer is not priced. The table takes it whenever the rule may fire,
///     and so does this; there is no "is the copy worth more here" heuristic
///     on either side to port.
fn reinforcement_withdrawals(statics: &[UnitStatic], st: &mut State) {
    for i in 0..st.units() {
        if st.dormant[i] || st.reinforcement_used[i] {
            continue;
        }
        let r = statics[st.roster.profile[i]].reinforcement;
        // `once` is READ as the reason a spent unit never withdraws again. A
        // hypothetical `once: false` entry (none ships) is declined outright
        // rather than half-modelled: the core has ONE roster index for the
        // original and its copy, so it has no second marker with which to tell
        // "promise pending" from "promise spent" — the table keeps two
        // (`reinforcement_due_round` and `reinforcement_spent`, main.gd:10253/
        // :10344) because it has two GameUnits.
        if r.within_in <= 0.0 || !r.once {
            continue;
        }
        if !st.attached[i].is_empty() || st.attached_to[i].is_some() {
            continue;
        }
        // "is Shaken or fully destroyed" — the offer stands for as long as the
        // unit IS Shaken, not only in the round it became so (:5971).
        if !st.shaken[i] && st.alive[i] > 0 {
            continue;
        }
        let round = st.round;
        deployment::withdraw_as_destroyed(st, i, round);
        st.reinforcement_used[i] = true;
    }
}

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

#[cfg(test)]
#[path = "tests/rollout/mod.rs"]
mod family_tests;

#[cfg(test)]
mod tests {
    use crate::rng::GodotRng;
    use crate::unit::UnitStatic;

    /// Battleborn family (rules-wave3-battleborn) — the round-start recovery
    /// leg end to end: a Shaken unit stamped `battleborn_recover_target` 4
    /// rolls the seeded `GodotRng` and stops being Shaken exactly when the
    /// face reaches the target (main.gd `_solo_battleborn_recovery` via
    /// `DiceRules.is_success`); the same seed's probe roll predicts which.
    /// A rule-less unit (target 0, the epoch-5 reading this wave must keep
    /// byte-exact) never rolls and never recovers.
    #[test]
    fn the_battleborn_recovery_leg_rolls_the_seeded_die_at_target() {
        use crate::acts::read_act_header;
        use crate::state::ProfileCache;
        use crate::{io, rollout};
        const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
          "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":3,
            "wounds_max":[3],"model_count":1,"caster_value":0,"base_radius":0.016,
            "game_system":"gf","faction_folder":"robot_legions","special_rules":[],
            "item_grants":[],"attached_hero_rules":[],
            "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;
        const PLAIN: &str = r#"{"round":2,"rounds_total":4,"scoring":"end","units":{
          "p1_0_a":{"player":1,"alive":1,"wounds":[3],"radii":[0.016],
            "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,
            "fatigued":false,"activated":false,"casts":0,"morale_bonus":0,
            "aircraft":false,"dormant":false,"ambush_arrived_round":-1,
            "earliest_arrival_round":-1,"wound_frac":0.0,"mods":{},"mods_base":{},
            "bands":{"advance":6.0,"rush":12.0}}}}"#;
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let mut st = io::state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let statics =
            vec![UnitStatic { battleborn_recover_target: 4, ..Default::default() }];
        let mut recovered = 0;
        let mut stayed = 0;
        for seed in 0..64i64 {
            st.shaken[0] = true;
            let face = GodotRng::new(seed).randi_range(1, 6);
            let mut rng = GodotRng::new(seed);
            rollout::battleborn_recovery_roll(&statics, &mut st, 0, &mut rng);
            if face >= 4 {
                assert!(!st.shaken[0], "face {face} reaches the 4+ target");
                recovered += 1;
            } else {
                assert!(st.shaken[0], "face {face} stays under the 4+ target");
                stayed += 1;
            }
        }
        assert!(recovered > 0 && stayed > 0, "both die halves must occur across the seeds");
        // Rule-less (the epoch-5 reading): target 0 -> no die, Shaken stays.
        let statics0 = vec![UnitStatic::default()];
        for seed in 0..64i64 {
            st.shaken[0] = true;
            let mut rng = GodotRng::new(seed);
            rollout::battleborn_recovery_roll(&statics0, &mut st, 0, &mut rng);
            assert!(st.shaken[0], "no rule, no recovery");
        }
    }
}
