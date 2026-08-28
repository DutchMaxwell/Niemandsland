//! `BattleSim.resolve` (battle_sim.gd:570-652) for every action kind the
//! rollout policy produces — HOLD, ADVANCE, RUSH, CHARGE — and
//! `BattleSim.reply_threat` (:1003-1024), the expected reply that prices the
//! planner's RICH leaf (ai_planner.gd:508-510).
//!
//! The two A/B seams are read from the corpus header (`Seams`, ai_planner.gd:
//! 483-489), never guessed: `spacing` switches the `_spacing_fraction` clamp
//! (battle_sim.gd:521-563, :590-592) on, `cast` switches the cast sub-phase
//! (:602-607) on. With `cast` off the LEGACY spell rider inside the shoot
//! branch runs instead (:621-628), which is what the shipped rollouts still do.

use std::rc::Rc;

use crate::combat::{
    at_or_below_half, effective_attacks, melee_ev, morale_target, shoot_ev,
    should_test_shooting_morale, shrouded_reach, SHROUD_FLOOR_IN, SHROUD_RANGE_PENALTY_IN,
};
// NML-1073 M5 D6a-B4 — the per-model sight twin, used only behind `sighting`.
use crate::sight;
use crate::geom::{self, V3};
use crate::io::{Action, Seams};
use crate::dice::{Morale, ShootResult, Tray};
use crate::rng::GodotRng;
use crate::rules::Spell;
use crate::spell::{cast_success_chance_base, official_pick_order, spell_damage_ev_of, spell_ev_of};
use crate::state::State;
use crate::mv::reach::{owner_bit, Disc, ReachBuild, ReachIndex, ReachQuery};
use crate::mv::CLEARANCE_EPS_IN;
use crate::terrain::{gives_cover, Terrain};
use crate::unit::{Ctx, UnitStatic, ShootProfile};
use crate::{CONTROL_EPS, IN2M};

/// `BattleSim.CONTACT_IN` battle_sim.gd:725 — the charge's contact ring. No
/// longer the melee trigger (NML-1073 S1b moved that to the base-EDGE gap);
/// kept because the constant itself is unchanged and other GDScript callers
/// still read it.
pub const CONTACT_IN: f64 = 1.0;
/// `SoloController.CHARGE_CONTACT_MARGIN_IN` solo_controller.gd:53 — the
/// table's own contact epsilon. Was the melee trigger between NML-1073 S1b and
/// S1d; kept because the constant itself is unchanged and GDScript still reads
/// it for the charge move's contact hair.
pub const CHARGE_CONTACT_MARGIN_IN: f64 = 0.25;
/// `SoloController.MELEE_ENGAGE_IN` solo_controller.gd:57 — THE table's engage
/// distance (GF/AoF Advanced Rules v3.5.1 p.8/p.9, main.gd:7971-7986): a charge
/// landing within 1" of base edge SNAPS into contact and fights; beyond it the
/// charge falls short. Since NML-1073 S1d this, not the 0.25" epsilon, is the
/// melee trigger — S1b's epsilon left the imagination 0.75" stricter than the
/// table it is supposed to predict.
pub const MELEE_ENGAGE_IN: f64 = 1.0;
/// `SeparationChecker.BASE_CONTACT_EPSILON_INCHES` separation_checker.gd:77 —
/// the hair inside which two bases already count as touching. `snap_charge`
/// returns 0 below it (solo_controller.gd:8639) and measures its budget clamp
/// against it (:8644), so it is the tolerance on BOTH halves of D5-1's gate.
pub const BASE_CONTACT_EPSILON_IN: f64 = 0.05;
/// `SoloController.UNIT_SPACING_IN` solo_controller.gd:70 — the no-go buffer
/// every OTHER unit's models project around themselves.
pub const UNIT_SPACING_IN: f64 = 1.0;
/// `SeparationChecker.DEFAULT_BASE_RADIUS_M` separation_checker.gd:81 — the
/// fallback when a snapshot carries no radius for a model.
pub const DEFAULT_BASE_RADIUS_M: f64 = 0.016;
/// The `_spacing_fraction` binary search runs exactly 8 halvings
/// (battle_sim.gd:552) and the fallback sweep exactly 8 descending samples
/// (:558-561). Both counts are rule data: they set the granularity of the
/// clamp, so a different number is a different game.
pub const SPACING_BISECTIONS: usize = 8;
pub const SPACING_SAMPLES: usize = 8;

/// `AiDecision.Action` ai_decision.gd:16.
pub const HOLD: i64 = 0;
pub const ADVANCE: i64 = 1;
pub const RUSH: i64 = 2;
pub const CHARGE: i64 = 3;

/// Why a node could not be resolved by this port — reported by name with a
/// count, never silently skipped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Unsupported {
    /// An action kind outside HOLD/ADVANCE/RUSH/CHARGE — KITE (4) has no
    /// `resolve` branch of its own in the GDScript either.
    ActionKind(i64),
    /// The action names a unit the state does not carry.
    UnknownUnit,
    /// A MOVED unit that also shoots: `_los_clear` (battle_sim.gd:666-670)
    /// re-probes with the POST-move centre, and the recorded `los_pairs` of the
    /// pre-move state cannot answer that. Never occurs in the recorded corpus
    /// (`_policy_candidates` ai_planner.gd:517-545 pairs a shoot only with HOLD).
    MovedShootLos,
    /// `plan_with_rollout` scored nothing at all — the GDScript answers
    /// `{"used": false}` (ai_planner.gd:141-142), which is not a pick.
    NoCandidate,
    /// `top_k <= 0`: the search degrades to the 1-ply `plan()` (:126), whose
    /// dictionary has neither `waits` nor `rolled_units`. Call `plan::plan`.
    OnePlyDegrade,
    /// `AiPlanner.playout_search` fired on a CLOSE top-2 (:231-265): up to 7
    /// STOCHASTIC `full_playout`s per branch then decide the pick outright.
    /// M2-4 ports it; until then the search declines rather than guesses.
    PlayoutArbitration,
    /// `AiPlanner.playout_net` is non-empty — every imagined activation is
    /// steered by a trained network (`_policy_step_net`, :627-645), which is not
    /// rules code and is declined rather than approximated.
    NetPlayout,
    /// `AiMissionEval.fit_mode` — `score.rs` ports the HAND half only.
    FittedEval,
}

/// `BattleSim._los_clear` battle_sim.gd:666-670, read off the recorded answers.
/// No matrix = no `los_blocked` seam on the state = clear for every pair.
#[inline]
fn los_clear(state: &State, i: usize, j: usize) -> bool {
    match &state.los_pairs {
        None => true,
        Some(m) => m[i * state.units() + j],
    }
}

/// `BattleSim._wounds_left` battle_sim.gd:1057-1061.
#[inline]
fn wounds_left(state: &State, i: usize) -> i64 {
    state.wounds[i].iter().sum()
}

/// `BattleSim._below_half` battle_sim.gd:1066-1072 — a single-model unit
/// measures tough WOUNDS against the model's max, a multi-model unit its alive
/// count against its starting size.
fn below_half(state: &State, us: &UnitStatic, i: usize) -> bool {
    if us.model_count == 1 {
        return at_or_below_half(wounds_left(state, i), us.wounds_max.first().copied().unwrap_or(0));
    }
    at_or_below_half(state.alive[i], us.model_count)
}

/// `BattleSim._morale_fails_expected` battle_sim.gd:1082-1090 — Shaken always
/// fails; otherwise the quality target's fail chance, halved by Fearless, and a
/// fail at 50% or worse.
fn morale_fails_expected(state: &State, us: &UnitStatic, i: usize) -> bool {
    if state.shaken[i] {
        return true;
    }
    let mut fail_p = (morale_target(us.quality, state.morale_bonus[i]) - 1) as f64 / 6.0;
    if us.fearless {
        fail_p *= 0.5;
    }
    fail_p >= 0.5
}

/// `BattleSim._apply_expected_wounds` battle_sim.gd:1131-1155 — expected unsaved
/// wounds fill model by model in ARRAY order.
///
/// TWO rounding rules, one per caller. `rng = None` is `stochastic_rng == null`,
/// the rollout path: the sub-wound remainder stays on the TARGET as `wound_frac`
/// and joins the next volley instead of being floored away. `rng = Some(..)` is
/// `resolve_stochastic`, the PLAYOUT path: the remainder is spent on one
/// mean-preserving coin flip (`randf() < pool - left`) and `wound_frac` is
/// CLEARED, not carried. The draw happens once per call and BEFORE any model is
/// touched — that position in the stream is what the arbitration's sums depend on.
fn apply_expected_wounds(state: &mut State, ti: usize, ev: f64, rng: Option<&mut GodotRng>) {
    let pool = state.wound_frac[ti] + ev;
    let mut left = pool.floor() as i64;
    match rng {
        Some(r) => {
            if r.randf() < pool - (left as f64) {
                left += 1;
            }
            state.wound_frac[ti] = 0.0;
        }
        None => state.wound_frac[ti] = pool - (left as f64),
    }
    land_wounds(state, ti, left);
}

/// The casualty half of `_apply_expected_wounds` battle_sim.gd:1140-1155 — whole
/// wounds fill model by model in ARRAY order. Shared with the D1 dice path, so a
/// real-dice volley kills exactly the models the EV volley would have.
pub fn land_wounds(state: &mut State, ti: usize, mut left: i64) {
    while left > 0 && !state.wounds[ti].is_empty() {
        let take = left.min(state.wounds[ti][0]);
        state.wounds[ti][0] -= take;
        left -= take;
        if state.wounds[ti][0] <= 0 {
            state.wounds[ti].remove(0);
            state.positions[ti].remove(0);
            // radii stay aligned with positions or the base-edge measure lies.
            if !state.radii[ti].is_empty() {
                state.radii[ti].remove(0);
            }
        }
    }
    state.alive[ti] = state.positions[ti].len() as i64;
}

/// `BattleSim._expected_shooting_morale` battle_sim.gd:1096-1105 /
/// `main._solo_shooting_morale` :8232-8250 — WHETHER the volley's target has to
/// test at all.
///
/// D1-B5b splits the trigger from the outcome: the trigger is one truth, but
/// `dice="table"` then rolls a real die for it (`tray_morale`) where the EV path
/// asks `morale_fails_expected`. A shooting fail is SHAKEN, never a Rout — Rout
/// exists only in melee.
fn shooting_morale_trigger(
    state: &State,
    us: &UnitStatic,
    ti: usize,
    alive_before: i64,
    wounds_before: i64,
) -> bool {
    if us.model_count == 1 {
        // A single model measures morale in TOUGH WOUNDS, not models (p.10).
        return state.alive[ti] > 0
            && wounds_left(state, ti) < wounds_before
            && below_half(state, us, ti);
    }
    should_test_shooting_morale(alive_before, state.alive[ti], us.model_count)
}

/// `BattleSim._ctx_of(su)` battle_sim.gd:701-712, SHOOTING half: the static
/// template with the snapshot's live `alive` and `in_cover` written over it.
/// (`melee` only adds the fatigue flag, which no shooting call sets.)
#[inline]
pub fn ctx_of(us: &UnitStatic, state: &State, i: usize) -> Ctx {
    let mut c = us.ctx;
    c.models = state.alive[i];
    c.in_cover = state.in_cover[i];
    c
}

/// `BattleSim._ctx_of(su, true)` battle_sim.gd:701-708, MELEE half: the same
/// context plus the snapshot's fatigue flag, which the EV layer is blind to and
/// which turns the striker's to-hit into a flat unmodified 6 (p.9).
#[inline]
fn ctx_of_melee(us: &UnitStatic, state: &State, i: usize) -> Ctx {
    let mut c = ctx_of(us, state, i);
    c.fatigued = state.fatigued[i];
    c
}

/// Scratch buffers so a threat sweep allocates once per call, not per pair.
#[derive(Default)]
pub struct Scratch {
    pub keep: Vec<usize>,
    pub attacks: Vec<i64>,
}

/// `BattleSim._profiles_of(su, false, d)` battle_sim.gd:714-749 fused with the
/// distance gate of `AiShooting.profiles_in_range` (ai_shooting.gd:16-17): the
/// merged ranged set is precomputed per unit, so all that is left per call is
/// the range filter and the survivor scaling.
pub fn profiles_of(us: &UnitStatic, alive: i64, d: f64, sc: &mut Scratch) {
    sc.keep.clear();
    sc.attacks.clear();
    for (i, p) in us.shoot.iter().enumerate() {
        if (p.range as f64) < d {
            continue;
        }
        sc.keep.push(i);
        sc.attacks.push(effective_attacks(p.attacks, alive, us.model_count));
    }
}

/// `BattleSim._profiles_of(su, true)` battle_sim.gd:714-749, MELEE half: every
/// melee profile strikes (no range gate), each with its survivor-scaled attack
/// count. Fills `sc.attacks` index-parallel to `us.melee`.
pub fn melee_profiles_of(us: &UnitStatic, alive: i64, sc: &mut Scratch) {
    sc.attacks.clear();
    for p in &us.melee {
        sc.attacks.push(effective_attacks(p.attacks, alive, us.model_count));
    }
}

// ------------------------- D6a-B4: the table's own per-weapon die count ---

/// `SoloController.effective_shoot_reach_in` (:5636-5637) — the weapon's reach
/// against THIS target: the Aircraft range penalty first (:5577-5580), then
/// Ranged Shrouding (:5587-5593). `main._run_ai_shooting` :3131-3133 casts the
/// result to `int`, and the cast is part of the answer.
fn sight_reach_in(range_in: f64, def_aircraft: bool, def: &Ctx) -> f64 {
    let r = (range_in - if def_aircraft { sight::AIRCRAFT_TARGET_RANGE_PENALTY_IN } else { 0.0 })
        .max(0.0);
    let r = if def.ranged_shrouding {
        shrouded_reach(r, SHROUD_RANGE_PENALTY_IN, SHROUD_FLOOR_IN)
    } else {
        r
    };
    r.trunc()
}

/// `SoloController.scaled_attacks_report` solo_controller.gd:477-490 — the ONE
/// attack-scaling truth of every table volley. A weapon carried by FEWER models
/// than the unit has fires `per-copy x living bearers`, capped by the sighted
/// count; every other weapon keeps the `sighted/max` ratio.
///
/// THE APPROXIMATION, and it is the largest one on this rung: `alive_bearers_of`
/// (:7720-7739) counts the weapon in LIVING models' hands off the per-model
/// loadout, which the capture does not carry at all. This port assumes the
/// special weapons' bearers are the last to fall — `min(copies, alive)`.
/// Measured on `~/selfplay_out/qbe_ref`: that reproduces the recorded `attacks`
/// on 919 of the 1052 shots that take this path (and the flat path, 1065 shots,
/// needs no bearer count). The remaining 133 need the recorder extension the
/// D6a draft's §3 describes.
fn bearer_scaled_attacks(p: &ShootProfile, alive: i64, model_count: i64, sighted: i64) -> i64 {
    let copies = p.count.max(1);
    if copies < model_count {
        // `bearers == 0` (the GDScript's honesty-alarm branch) cannot be reached
        // here: `alive > 0` on every member this port shoots with, so
        // `min(copies, alive) >= 1`.
        let bearers = copies.min(alive);
        return (p.attacks / copies).max(0) * bearers.min(sighted);
    }
    effective_attacks(p.attacks, sighted, model_count)
}

/// `profiles_of` with the die count the TABLE draws: per weapon, the member's
/// models that have BOTH range and line of sight to the target
/// (`main._solo_sighted_count` :4125-4147, GF Advanced Rules v3.5.1 p.8). The
/// range filter that decides WHICH weapons fire is left exactly as
/// `profiles_of` has it — only the count changes.
fn sighted_profiles_of(
    us: &UnitStatic,
    state: &State,
    statics: &[UnitStatic],
    mi: usize,
    ti: usize,
    zones: &[sight::Zone],
    d: f64,
    sc: &mut Scratch,
) {
    sc.keep.clear();
    sc.attacks.clear();
    let blockers = sight::blockers_of(state, mi, ti);
    let def = &statics[state.roster.profile[ti]].ctx;
    for (i, p) in us.shoot.iter().enumerate() {
        if (p.range as f64) < d {
            continue;
        }
        sc.keep.push(i);
        let reach = sight_reach_in(p.range as f64, state.aircraft[ti], def);
        // Indirect (GF v3.5.1) "may target enemies that are not in line of
        // sight as if in line of sight": the range gate stays, the sight test
        // goes (main.gd:4136-4138).
        let seen = sight::sighted_count(state, zones, &blockers, mi, ti, reach, p.indirect);
        sc.attacks.push(bearer_scaled_attacks(p, state.alive[mi], us.model_count, seen));
    }
}

/// `BattleSim._expected_melee_morale` battle_sim.gd:1111-1125 — the side that
/// dealt FEWER wounds tests (a tie means nobody); a fail at or below half is a
/// ROUT, and the loser leaves the board: wounds, positions and radii cleared,
/// `alive` 0. `wound_frac` is deliberately NOT cleared — the GDScript leaves it
/// standing too.
fn expected_melee_morale(
    state: &mut State,
    statics: &[UnitStatic],
    si: usize,
    su_before: i64,
    ti: usize,
    tu_before: i64,
) {
    let dealt_by_su = tu_before - wounds_left(state, ti);
    let dealt_by_tu = su_before - wounds_left(state, si);
    if dealt_by_su == dealt_by_tu {
        return;
    }
    let li = if dealt_by_su > dealt_by_tu { ti } else { si };
    let ul = &statics[state.roster.profile[li]];
    if state.alive[li] <= 0 || !morale_fails_expected(state, ul, li) {
        return;
    }
    if below_half(state, ul, li) {
        state.wounds[li].clear();
        state.positions[li].clear();
        state.radii[li].clear();
        state.alive[li] = 0;
    } else {
        state.shaken[li] = true;
    }
}

// --------------------------- D1-B5a: the melee sub-phases on the tray ---

/// The MEMBERS of a melee strike phase in the table's build order
/// (`_solo_attack_groups` main.gd:4284-4290): the unit, then each attached hero,
/// each with its OWN melee set, Quality and fatigue flag. Melee has no range
/// gate, so `keep` is every profile — the two `Shooter` arrays stay
/// index-parallel and the shooting resolver's shape is reused, not copied.
fn melee_parts(statics: &[UnitStatic], state: &State, i: usize) -> Vec<(usize, Scratch, Ctx)> {
    let mut parts: Vec<(usize, Scratch, Ctx)> = Vec::new();
    for &mi in std::iter::once(&i).chain(state.attached[i].iter()) {
        if state.alive[mi] <= 0 {
            continue; // main.gd:4290 — a member with no living model never rolls
        }
        let um = &statics[state.roster.profile[mi]];
        let mut sc = Scratch::default();
        melee_profiles_of(um, state.alive[mi], &mut sc);
        sc.keep = (0..um.melee.len()).collect();
        parts.push((mi, sc, ctx_of_melee(um, state, mi)));
    }
    parts
}

/// ONE side's strike phase on the tray, wounds LANDED. The landing is the point:
/// the table resolves Impact, the charger's strikes and the strike-back as
/// separate phases, and each later one is survivor-scaled by what the earlier
/// ones killed (main.gd:8067-8102). Returns the PRE-Regeneration wounds it
/// caused — the melee-winner tally, which is what the table compares.
fn strike_phase(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    ti: usize,
    charging: bool,
    tray: &mut Tray,
    shot: &mut ShootResult,
) -> i64 {
    let parts = melee_parts(statics, next, si);
    let ut = &statics[next.roster.profile[ti]];
    let def = ctx_of(ut, next, ti);
    let members: Vec<crate::dice::Shooter<'_>> = parts
        .iter()
        .map(|(mi, sc, att)| {
            let um = &statics[next.roster.profile[*mi]];
            crate::dice::Shooter {
                profiles: &um.melee,
                keep: &sc.keep,
                attacks: &sc.attacks,
                att,
                owner: &um.name,
            }
        })
        .collect();
    let r = crate::dice::resolve_melee_with_tray(&members, &def, &ut.name, charging, tray);
    let caused = r.caused;
    let w = shot.absorb(r);
    land_wounds(next, ti, w);
    caused
}

/// The charge's Impact, pool by pool — `main._solo_charge_impact` :6292. The
/// pools are resolved SEPARATELY because :6304 re-checks the defender's alive
/// count before each one: an Impact pool that wipes the defender means the Heavy
/// pool never rolls. Returns the pre-Regeneration wounds caused.
fn impact_phase(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    ti: usize,
    tray: &mut Tray,
    shot: &mut ShootResult,
) -> i64 {
    let us = &statics[next.roster.profile[si]];
    let ut = &statics[next.roster.profile[ti]];
    let pools = crate::dice::impact_pools(&ctx_of_melee(us, next, si), &ctx_of(ut, next, ti));
    let mut caused = 0;
    for (dice, ap) in pools {
        if dice <= 0 || next.alive[ti] <= 0 {
            continue; // :6304 — nothing left to hit, no dice
        }
        let def = ctx_of(ut, next, ti);
        let r = crate::dice::resolve_impact_pool_with_tray(
            dice, ap, &us.name, &def, &ut.name, tray,
        );
        caused += r.caused;
        let w = shot.absorb(r);
        land_wounds(next, ti, w);
    }
    caused
}

/// `main._solo_morale_test` :8305 on the played path — the tray twin of
/// `morale_fails_expected`, with No Retreat's self-wounds landed regen-free
/// ("can't be ignored") and the Rout half clearing the unit off the board
/// exactly as `expected_melee_morale` does.
fn tray_morale(
    state: &mut State,
    us: &UnitStatic,
    i: usize,
    melee: bool,
    tray: &mut Tray,
    shot: &mut ShootResult,
) {
    if state.alive[i] <= 0 {
        return;
    }
    let mut ctx = ctx_of(us, state, i);
    // The LIVE Banner/spell bonus, not the static one: `morale_fails_expected`
    // reads `state.morale_bonus[i]` and `_solo_morale_bonus` (main.gd:6632) is
    // the same live read, so the ROLLED target has to be too. Reading the static
    // profile instead is a whole point of target off on every Banner unit.
    ctx.morale_bonus = state.morale_bonus[i];
    let (outcome, r) = crate::dice::resolve_morale_with_tray(
        &ctx,
        &us.name,
        melee,
        below_half(state, us, i),
        state.shaken[i],
        // `SoloController.wounds_to_destroy` :6084 also counts the attached
        // heroes' models; this port counts the unit's own wounds, which is the
        // die COUNT of a No Retreat roll and nothing else.
        wounds_left(state, i),
        tray,
    );
    let self_wounds = shot.absorb(r);
    land_wounds(state, i, self_wounds);
    match outcome {
        Morale::Passed => {}
        Morale::Shaken => state.shaken[i] = true,
        Morale::Routed => {
            state.wounds[i].clear();
            state.positions[i].clear();
            state.radii[i].clear();
            state.alive[i] = 0;
        }
    }
}

/// The whole CHARGE melee on the tray — `main._solo_resolve_ai_charge`
/// :8039-8118 in its own order: Counter's pre-phase (flagged), Impact (:8067),
/// the charger's strikes (:8081), the strike-back (:8100), the melee result
/// (:8110). UNWIELDY swaps the charger BEHIND the strike-back (:8073-8078);
/// Counter and Impact keep their slots either way.
///
/// Returns the loser of the melee — the side that CAUSED fewer wounds, Fear(X)
/// counting as +X dealt for this comparison only and never for the wounds
/// applied (:8110-8112). `None` on a tie, which is what the table means by
/// "nobody tests".
fn tray_charge(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    ti: usize,
    tray: &mut Tray,
    shot: &mut ShootResult,
) -> Option<usize> {
    if statics[next.roster.profile[ti]].melee.iter().any(|p| p.counter) {
        // :8055-8059 — a Counter weapon runs a WHOLE extra strike phase before
        // Impact, and strips Impact dice with it.
        shot.mark("counter_strikes_first");
    }
    let mut by_su = impact_phase(statics, next, si, ti, tray, shot);
    let mut by_tu = 0;
    let charger_last = statics[next.roster.profile[si]].ctx.unwieldy;
    for slot in 0..2 {
        if (slot == 0) != charger_last {
            // :8079 — the charger strikes only while BOTH sides still stand;
            // an Impact pool that wiped the defender ends the melee here.
            if next.alive[si] > 0 && next.alive[ti] > 0 {
                by_su += strike_phase(statics, next, si, ti, true, tray, shot);
                next.fatigued[si] = true;
            }
        } else if next.alive[ti] > 0 && next.alive[si] > 0 {
            // :8100 — and so does the strike-back, in both directions.
            by_tu += strike_phase(statics, next, ti, si, false, tray, shot);
            next.fatigued[ti] = true;
        }
    }
    let a = by_su + statics[next.roster.profile[si]].ctx.fear;
    let b = by_tu + statics[next.roster.profile[ti]].ctx.fear;
    if a == b {
        return None;
    }
    Some(if a > b { ti } else { si })
}

/// `BattleSim._unit_group` battle_sim.gd:528-547 as a membership test — is unit
/// `oi` part of the group `key_i` moves and ends as? That is `key_i` itself plus
/// its attached heroes, plus (only when `include_host`) its host. Only the
/// attached-heroes half mirrors `SoloController._spacing_zones_world`; the host
/// is a SIM-ONLY necessity on the MOVER side, where a joined hero can activate
/// apart from its host. The CHARGE TARGET group always passes false.
///
/// The GDScript builds a key SET and then walks `next["units"]`; a set the port
/// never materialises answers the same question, because the only thing done
/// with it is `group.has(key)` inside that walk.
fn in_unit_group(state: &State, key_i: usize, oi: usize, include_host: bool) -> bool {
    oi == key_i
        || state.attached[key_i].contains(&oi)
        || (include_host && state.attached_to[key_i] == Some(oi))
}

/// `BattleSim._spacing_fraction` battle_sim.gd:550-620 — the largest fraction
/// of `delta` that leaves every mover model clear of every OTHER alive unit's
/// models (horizontal distance only, the `control_gap_in` convention).
///
/// The three-case ladder is load-bearing and reproduced in order: (1) the full
/// move is legal -> 1.0 regardless of the start; (2) the START is legal -> an
/// 8-step binary search, which is monotone only from a clear start; (3) both
/// ends illegal -> 8 descending samples, largest legal wins, else 0.0.
///
/// NML-1073 S1: `ci` is the CHARGE victim's index, if the action names one.
/// The mover's own group is exempt entirely (no obstacle at all), dormant
/// (reserve) and Aircraft units are skipped, and the target's group — the
/// target and ITS heroes, never its host — projects a BODY-ONLY disc (buffer
/// 0.0) so a charge may end in base contact. Everyone else keeps the full
/// `UNIT_SPACING_IN` buffer. GF Advanced Rules v3.5.1 p.7: models may never be
/// within 1" of models from other units unless taking a Charge action, which
/// may ignore that restriction toward base contact with ONE enemy unit.
///
/// Obstacle ORDER differs from the GDScript's (the loader reads the recorder's
/// key-SORTED `units` object, the engine walks capture order) and cannot move
/// the answer: `legal` is a conjunction over independent per-obstacle tests, so
/// only the short-circuit point changes, never the boolean.
fn spacing_fraction(state: &State, mi: usize, delta: geom::V3, ci: Option<usize>) -> f64 {
    // `Vector3.length_squared()` — f32, like every other Vector3 read.
    if delta[0] * delta[0] + delta[1] * delta[1] + delta[2] * delta[2] <= 0.0 {
        return 1.0;
    }
    let buffer_m = UNIT_SPACING_IN * IN2M;
    let mut obstacles: Vec<(geom::V3, f64)> = Vec::new();
    for oi in 0..state.units() {
        if in_unit_group(state, mi, oi, true) {
            continue;
        }
        if state.dormant[oi] || state.aircraft[oi] {
            continue;
        }
        let o_buffer = match ci {
            Some(c) if in_unit_group(state, c, oi, false) => 0.0,
            _ => buffer_m,
        };
        let radii = &state.radii[oi];
        for (k, pos) in state.positions[oi].iter().enumerate() {
            let r = radii.get(k).copied().unwrap_or(DEFAULT_BASE_RADIUS_M);
            obstacles.push((geom::to_f32(*pos), r + o_buffer));
        }
    }
    if obstacles.is_empty() {
        return 1.0;
    }
    let legal = |t: f64| -> bool {
        let step = geom::mul(delta, t);
        for (i, own) in state.positions[mi].iter().enumerate() {
            let own_r = state.radii[mi].get(i).copied().unwrap_or(DEFAULT_BASE_RADIUS_M);
            let q = geom::add(geom::to_f32(*own), step);
            for (oc, r) in &obstacles {
                let flat: geom::V3 = [q[0] - oc[0], 0.0, q[2] - oc[2]];
                if (geom::length(flat) as f64) < r + own_r {
                    return false;
                }
            }
        }
        true
    };
    if legal(1.0) {
        return 1.0;
    }
    if legal(0.0) {
        let (mut lo, mut hi) = (0.0f64, 1.0f64);
        for _ in 0..SPACING_BISECTIONS {
            let mid = (lo + hi) * 0.5;
            if legal(mid) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        return lo;
    }
    for i in 0..SPACING_SAMPLES {
        let t = 1.0 - (i as f64) * 0.125;
        if legal(t) {
            return t;
        }
    }
    0.0
}

/// NML-1073 M4-7 — the STATIC per-round obstacle index the tier-2 `reach_query`
/// answers from: the board rasterised onto a coarse grid plus every unit's
/// models as discs, built ONCE from the root state of one planner call and
/// reused by every imagined activation underneath it.
///
/// The disc set mirrors `spacing_fraction`'s obstacle loop (:328-347) — dormant
/// (reserve) and Aircraft units are skipped, everyone else contributes one disc
/// per model at `radius` and at `radius + UNIT_SPACING_IN`, and the exemptions
/// (the mover's own group; the charge victim's body-only disc) are applied per
/// QUERY through the two owner masks.
///
/// `None` when the header carried no board: `terrain_at.is_valid()` is false,
/// there is nothing to rasterise, and the path seam then stays inert.
///
/// WALLS: the act corpus header carries a terrain grid but NO wall segments
/// (`grep -rn "wall" core/nml-core/src` is empty), so the index is built with
/// an empty wall list and Impassable CELLS are the only hard obstacle the
/// imagination sees. The exact solver's 48 wall segments would need a new
/// header key on the GDScript side — see the M4-7 report.
pub fn reach_index_for_state(state: &State, terrain: &Terrain) -> Option<ReachIndex> {
    let board = terrain.board_in();
    if !terrain.is_valid() || board[0] <= 0.0 || board[1] <= 0.0 {
        return None;
    }
    let mut discs: Vec<Disc> = Vec::new();
    for oi in 0..state.units() {
        if state.dormant[oi] || state.aircraft[oi] {
            continue;
        }
        let bit = owner_bit(oi);
        for (k, pos) in state.positions[oi].iter().enumerate() {
            let r_in = state.radii[oi].get(k).copied().unwrap_or(DEFAULT_BASE_RADIUS_M) / IN2M;
            discs.push(Disc {
                c: terrain.to_inch(geom::to_f32(*pos)),
                r_body: r_in as f32,
                r_buf: (r_in + UNIT_SPACING_IN) as f32,
                bit,
            });
        }
    }
    let mut b = ReachBuild::new(board, &[]);
    b.discs = discs;
    // The stored radii are the OBSTACLE's alone; the mover's own radius is added
    // per query, because it is not known at build time.
    b.add_mover_radius = true;
    Some(ReachIndex::build(b, |p| {
        let t = terrain.type_at(terrain.from_inch(p, 0.0));
        if t == crate::terrain::CONTAINER {
            f32::INFINITY
        } else if t == crate::terrain::DANGEROUS {
            crate::mv::DANGEROUS_COST_MULT as f32
        } else if t == crate::terrain::FOREST {
            crate::mv::DIFFICULT_COST_MULT as f32
        } else {
            1.0
        }
    }))
}

/// `BattleSim._best_spell_target` battle_sim.gd:922-943 — the enemy a
/// damage/debuff spell lands on: alive, on the other side, inside `range_in`
/// with line of sight, best damage EV first and NEAREST on a tie. A debuff
/// prices at 0, so it simply takes the nearest.
fn best_spell_target(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    entry: &Spell,
    los: &[bool],
) -> Option<usize> {
    let player = state.player[si];
    let mut best: Option<usize> = None;
    let mut best_ev = -1.0f64;
    let mut best_d = f64::INFINITY;
    for ti in 0..state.units() {
        if state.player[ti] == player || state.alive[ti] <= 0 {
            continue;
        }
        if !state.sees(si, state.key(ti)) || !los[ti] {
            continue;
        }
        let d = geom::dist_in(&state.positions[si], &state.positions[ti]);
        if d > entry.range_in + CONTROL_EPS {
            continue;
        }
        let ut = &statics[state.roster.profile[ti]];
        let ev = spell_damage_ev_of(entry, &ctx_of(ut, state, ti));
        if ev > best_ev + CONTROL_EPS || ((ev - best_ev).abs() <= CONTROL_EPS && d < best_d) {
            best_ev = ev;
            best_d = d;
            best = Some(ti);
        }
    }
    best
}

/// `BattleSim._pick_cast` battle_sim.gd:903-916 — the official cycle for ONE D3
/// face: the first spell in `official_pick_order` that is modelled, affordable
/// and has a legal target. A buff takes the caster itself.
fn pick_cast(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    spells: &[Spell],
    tokens: i64,
    d3: i64,
    caster_x: i64,
    los: &[bool],
) -> Option<(usize, usize)> {
    for idx in official_pick_order(spells.len(), d3, caster_x) {
        let entry = &spells[idx];
        if entry.status == "unmodeled" || entry.threshold > tokens {
            continue;
        }
        if entry.effect_kind == "buff" {
            return Some((idx, si));
        }
        if entry.effect_kind != "damage" && entry.effect_kind != "debuff" {
            continue; // an effect kind the sim has no arithmetic for
        }
        if let Some(ti) = best_spell_target(statics, state, si, entry, los) {
            return Some((idx, ti));
        }
    }
    None
}

/// `BattleSim._apply_cast_effect` battle_sim.gd:951-982 — damage lands as the
/// scaled expectation, a modifier as a scaled stamp on the target's `mods`.
/// `rng` is handed straight down: a stochastic activation rounds a spell's
/// damage the same way it rounds a volley's, from the same stream.
fn apply_cast_effect(
    statics: &[UnitStatic],
    state: &mut State,
    ti: usize,
    entry: &Spell,
    scale: f64,
    rng: Option<&mut GodotRng>,
) {
    if entry.effect_kind == "damage" {
        let ut = &statics[state.roster.profile[ti]];
        let ev = spell_damage_ev_of(entry, &ctx_of(ut, state, ti));
        apply_expected_wounds(state, ti, scale * ev, rng);
        return;
    }
    let m = entry.modifier;
    if !m.present {
        return; // a grants_rule-only "castable" spell leaves no snapshot trace
    }
    if scale <= 0.0 {
        return;
    }
    let mods = &mut state.mods[ti];
    // "beneficiary: attackers" is the ATTACKER's hit/def modifier against this
    // unit, never part of the bearer's own net — battle_sim.gd:971-975.
    if entry.beneficiary != "attackers" {
        mods.hit += scale * m.hit_mod;
        mods.def += scale * m.def_mod;
    }
    mods.morale += scale * m.morale_mod;
    mods.range_in += scale * m.range_in;
    mods.advance += scale * m.advance_in;
    mods.rush += scale * m.rush_in;
}

/// `BattleSim._cast_phase` battle_sim.gd:856-894 — after the move, before ANY
/// attack, for EVERY activation (which is the whole point of NML-1069: the old
/// site rode inside the shoot branch, so a melee caster never cast).
///
/// The expectation path walks all three D3 faces at weight 1/3 each, so up to
/// three effects land at 1/6 scale; the FIRST face that produced a pick names
/// the attempt and pays for it. `tokens` is read ONCE before the loop, so all
/// three faces shop with the same purse. Later faces see the state the earlier
/// ones already damaged — that order is load-bearing.
fn cast_phase(
    statics: &[UnitStatic],
    state: &mut State,
    si: usize,
    los: &[bool],
    mut rng: Option<&mut GodotRng>,
) {
    // p.10: a Shaken unit spends its activation idle and never casts.
    if state.shaken[si] {
        return;
    }
    let tokens = state.casts[si];
    if tokens <= 0 || state.alive[si] <= 0 {
        return;
    }
    let pi = state.roster.profile[si];
    if !statics[pi].is_caster || statics[pi].spells.is_empty() {
        return;
    }
    let spells = statics[pi].spells.clone();
    let caster_x = state.profile(si).caster_value;
    let weight = 1.0 / 3.0;
    let p_success = cast_success_chance_base();
    let mut cost: Option<i64> = None;
    for d3 in 1..=3i64 {
        let Some((idx, ti)) = pick_cast(statics, state, si, &spells, tokens, d3, caster_x, los) else {
            continue;
        };
        apply_cast_effect(statics, state, ti, &spells[idx], weight * p_success, rng.as_deref_mut());
        if cost.is_none() {
            cost = Some(spells[idx].threshold);
        }
    }
    if let Some(c) = cost {
        state.casts[si] = (tokens - c).max(0);
    }
}

/// The reply-threat volley of `si` onto `ti`: `AiEv.shoot_ev(...) +
/// spell_ev_of(...)["ev"]` — battle_sim.gd:1016-1017, "magic is part of the
/// reply". Returns (ev, spell token cost); `reply_threat` discards the cost,
/// `resolve`'s shoot branch spends it.
fn volley_ev(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    ti: usize,
    d: f64,
    sc: &mut Scratch,
) -> (f64, i64) {
    let us = &statics[state.roster.profile[si]];
    let ut = &statics[state.roster.profile[ti]];
    profiles_of(us, state.alive[si], d, sc);
    let att = ctx_of(us, state, si);
    let def = ctx_of(ut, state, ti);
    let shooting = shoot_ev(&us.shoot, &sc.keep, &sc.attacks, &att, &def, d);
    let (sp_ev, sp_cost) = spell_ev_of(us.is_caster, &us.spells, state.casts[si], &def, d);
    (shooting + sp_ev, sp_cost)
}

/// `BattleSim.melee_threat` battle_sim.gd:852-853 — `si`'s melee EV onto `ti`,
/// valued as a CHARGE and with `si`'s own fatigue state: the magnitude
/// `AiMissionEval.features` reads for `my_melee_in`/`their_melee_in` when the
/// feature wave is on (ai_mission_eval.gd:544).
pub fn melee_threat(statics: &[UnitStatic], state: &State, si: usize, ti: usize) -> f64 {
    let us = &statics[state.roster.profile[si]];
    let ut = &statics[state.roster.profile[ti]];
    let att = ctx_of_melee(us, state, si);
    let def = ctx_of(ut, state, ti);
    let mut sc = Scratch::default();
    melee_profiles_of(us, state.alive[si], &mut sc);
    melee_ev(&us.melee, &sc.attacks, &att, &def, true)
}

/// `BattleSim.reply_threat` battle_sim.gd:1003-1024 — every living enemy
/// activates once and shoots its best-EV visible target. The result is indexed
/// by CAPTURE order; the GDScript keys it by unit key and
/// `AiMissionEval._objective_p` (:413) reads it back the same way.
///
/// V0 simplifications kept verbatim from :999-1002: shooting only (no charge
/// reply), capture-time sight lines, already-activated enemies still count.
/// The strict `>` and the `best_ev = 0.0` start are load-bearing: a pairing
/// worth exactly nothing never becomes the pick, so no entry is written.
pub fn reply_threat(statics: &[UnitStatic], state: &State, player: i64) -> Vec<f64> {
    let n = state.units();
    let mut incoming = vec![0.0f64; n];
    let mut sc = Scratch::default();
    for e in 0..n {
        if state.player[e] == player || state.alive[e] <= 0 {
            continue;
        }
        let mut best_key: Option<usize> = None;
        let mut best_ev = 0.0f64;
        for m in 0..n {
            if state.player[m] != player
                || state.alive[m] <= 0
                || !state.sees(e, state.key(m))
                || !los_clear(state, e, m)
            {
                continue;
            }
            let d = geom::dist_in(&state.positions[e], &state.positions[m]);
            let (ev, _) = volley_ev(statics, state, e, m, d, &mut sc);
            if ev > best_ev {
                best_ev = ev;
                best_key = Some(m);
            }
        }
        if let Some(m) = best_key {
            incoming[m] += best_ev;
        }
    }
    incoming
}

/// Where the mover's post-move cover answer comes from — `battle_sim.gd:598-600`
/// probes the live `terrain_at` Callable at `centre + delta`, and a REPLAY of a
/// recorded node instead reads the answer the recorder wrote down.
///
/// The distinction is not cosmetic: a rollout imagines destinations no recorder
/// ever visited, so `Recorded` cannot serve it and `Board` cannot serve a node
/// corpus (whose header carries no terrain at all).
#[derive(Debug, Clone, Copy)]
pub enum Cover<'a> {
    /// The recorded `cover_dest`. `None` = the node carries no answer, and the
    /// flag is then left exactly as the parent state had it.
    Recorded(Option<bool>),
    /// The live board. An ABSENT board is `terrain_at.is_valid() == false`, and
    /// the GDScript then skips the write altogether (battle_sim.gd:598).
    Board(&'a Terrain),
}

/// `BattleSim.resolve` battle_sim.gd:570-652 — one activation resolved IN
/// EXPECTATION on a clone, for HOLD, ADVANCE, RUSH and CHARGE.
///
/// `cover_dest` is the recorded terrain answer (the mover's cover at its
/// destination): the core carries no terrain grid, so the one boolean the
/// `terrain_at` Callable produces at :595 is supplied, not computed. Everything
/// else — positions, the spacing clamp, wounds, radii, flags, casts, melee and
/// morale — is computed here.
///
/// `seams` comes from the corpus header, so the port takes the same branch the
/// recording did. A corpus with `cast` on is REPORTED as unsupported rather
/// than resolved with the legacy rider, which would silently differ.
///
/// NOTE on the produced state's `los_pairs`: it is the PARENT's matrix, which
/// goes stale the moment a unit moves. Nothing in this port reads it afterwards
/// (the parity gate re-reads the recorded matrix of each state), and a chained
/// `resolve -> reply_threat` in Rust needs the terrain grid, which is M1-5 work.
pub fn resolve(
    statics: &[UnitStatic],
    state: &State,
    action: &Action,
    cover_dest: Option<bool>,
    seams: Seams,
    cast_los: Option<&[bool]>,
) -> Result<State, Unsupported> {
    resolve_with(statics, state, action, Cover::Recorded(cover_dest), seams, cast_los, None, None, None)
}

/// The same activation against the LIVE board — the entry point a rollout uses,
/// because it invents destinations no recorder ever probed. `cast_los` is
/// `None`: with the cast seam on, a moved caster's targeting would need the
/// post-move sight row, which is M1-5 work and is reported, not guessed.
pub fn resolve_on_board(
    statics: &[UnitStatic],
    state: &State,
    action: &Action,
    terrain: &Terrain,
    seams: Seams,
) -> Result<State, Unsupported> {
    resolve_with(statics, state, action, Cover::Board(terrain), seams, None, None, None, None)
}

/// The same, WITH the round's tier-2 obstacle index. `seams.path` alone is not
/// enough: without an index (an absent board) the move step keeps its straight
/// line, which is what makes the seam inert rather than wrong.
pub fn resolve_on_board_reach(
    statics: &[UnitStatic],
    state: &State,
    action: &Action,
    terrain: &Terrain,
    seams: Seams,
    reach: Option<&ReachIndex>,
) -> Result<State, Unsupported> {
    resolve_with(statics, state, action, Cover::Board(terrain), seams, None, None, reach, None)
}

/// `BattleSim.resolve_stochastic` battle_sim.gd:473-478 — the SAME activation
/// with the static `stochastic_rng` set for its duration, which is the only
/// thing that distinguishes it. Every wound-rounding remainder inside this one
/// call is decided by a coin flip from `rng`; the generator is advanced in place,
/// so a playout's draws stay in one unbroken stream across its activations.
///
/// The GDScript sets a class static and clears it after; here the generator is
/// threaded, which is the same scope with the re-entrancy hazard removed.
pub fn resolve_stochastic_on_board(
    statics: &[UnitStatic],
    state: &State,
    action: &Action,
    terrain: &Terrain,
    seams: Seams,
    rng: &mut GodotRng,
) -> Result<State, Unsupported> {
    resolve_with(statics, state, action, Cover::Board(terrain), seams, None, Some(rng), None, None)
}

/// The stochastic playout's activation, WITH the round's tier-2 index.
#[allow(clippy::too_many_arguments)]
pub fn resolve_stochastic_on_board_reach(
    statics: &[UnitStatic],
    state: &State,
    action: &Action,
    terrain: &Terrain,
    seams: Seams,
    rng: &mut GodotRng,
    reach: Option<&ReachIndex>,
) -> Result<State, Unsupported> {
    resolve_with(statics, state, action, Cover::Board(terrain), seams, None, Some(rng), reach, None)
}

/// NML-1073 M5 D1-B4 — the SAME played activation with `dice="table"`: the
/// shooting sub-phase draws from `tray` in the table's own order instead of
/// filling an expected-value pool, and reports what it drew. `rng` still runs
/// the rest of the activation (the melee/spell remainders B5 will take over),
/// so the two streams stay exactly as split as the table's are.
#[allow(clippy::too_many_arguments)]
pub fn resolve_stochastic_tray_on_board(
    statics: &[UnitStatic],
    state: &State,
    action: &Action,
    terrain: &Terrain,
    seams: Seams,
    rng: &mut GodotRng,
    tray: &mut Tray,
) -> Result<(State, ShootResult), Unsupported> {
    let mut shot = ShootResult::default();
    let next = resolve_with(
        statics,
        state,
        action,
        Cover::Board(terrain),
        seams,
        None,
        Some(rng),
        None,
        Some((tray, &mut shot)),
    )?;
    Ok((next, shot))
}

#[allow(clippy::too_many_arguments)]
fn resolve_with(
    statics: &[UnitStatic],
    state: &State,
    action: &Action,
    cover: Cover,
    seams: Seams,
    cast_los: Option<&[bool]>,
    mut rng: Option<&mut GodotRng>,
    reach: Option<&ReachIndex>,
    mut dice: Option<(&mut Tray, &mut ShootResult)>,
) -> Result<State, Unsupported> {
    let kind = action.kind;
    if kind != HOLD && kind != ADVANCE && kind != RUSH && kind != CHARGE {
        return Err(Unsupported::ActionKind(kind));
    }
    let Some(&si) = state.roster.index.get(action.unit.as_str()) else {
        return Err(Unsupported::UnknownUnit);
    };
    let shoot_key = action.shoot.clone().unwrap_or_default();
    // battle_sim.gd:649-650 hands `str(action.get("charge",""))` to the spacing
    // clamp for EVERY move kind, not only CHARGE — resolved once here and
    // reused by the melee branch below. A key the roster does not carry maps to
    // None: the GDScript's key set then holds a name no obstacle can match.
    let charge_key = action.charge.clone().unwrap_or_default();
    let ci = if charge_key.is_empty() {
        None
    } else {
        state.roster.index.get(charge_key.as_str()).copied()
    };
    let pi_s = state.roster.profile[si];
    let mut next = state.clone();
    let was_shaken = next.shaken[si];
    let mut sc = Scratch::default();

    // --- move (battle_sim.gd:575-596) ---
    // `SoloController.sim_move_bands(su["unit"])` is a pure read of the unit's
    // rules (bands + the Musician bonus, solo_controller.gd:4966-4982), flattened
    // into the profile table at capture; RUSH and CHARGE share the rush band.
    let band_in = match kind {
        ADVANCE => next.bands[si].advance,
        RUSH | CHARGE => next.bands[si].rush,
        _ => 0.0,
    };
    let mut moved = false;
    // D5-1 — what the band still has left after the charge move, and so what
    // the melee snap may spend (solo_controller.gd:8659). Infinite while the
    // seam is off: the second engage gate then never refuses anything, which is
    // what every corpus recorded before D5-1 replayed with.
    let mut charge_remaining_in = f64::INFINITY;
    // D5-2, seam-gated: the CHARGE moves per model through the M4 movement port
    // instead of as one rigid delta — the table's own aim (`_charge_move`
    // solo_controller.gd:8582), its own arc budget and its own route. It runs
    // BEFORE the rigid block and, when it answers, replaces it whole: the aim
    // is the contact boundary, not the planner's `dest`, so the band clamp and
    // the spacing clamp below would be measuring a different move.
    let mut landing: Option<crate::mv::step::Landing> = None;
    if seams.movement && kind == CHARGE && band_in > 0.0 {
        if let (Cover::Board(t), Some(ti)) = (cover, ci) {
            landing = crate::mv::step::charge_move(
                &next,
                t,
                si,
                ti,
                band_in,
                seams.hero_attach,
                true,
                crate::mv::FAST_PLANNER_GUARD,
            );
        }
    }
    if let Some(land) = landing {
        moved = true;
        for (i, m) in land.movers.iter().enumerate() {
            next.positions[m.unit][m.model] = geom::to_f64(land.end[i]);
        }
        charge_remaining_in = land.remaining_in();
        // battle_sim.gd:598-600 — the mover's cover follows it, probed at the
        // POST-move unit centre, which is now the solved formation's centre.
        if let Cover::Board(t) = cover {
            if t.is_valid() {
                next.in_cover[si] = gives_cover(t.type_at(geom::centre(&next.positions[si])));
            }
        }
    } else if band_in > 0.0 && action.dest.is_some() && !next.positions[si].is_empty() {
        moved = true;
        let dest = geom::to_f32(action.dest.unwrap());
        let centre = geom::centre(&next.positions[si]);
        let mut delta = geom::sub(dest, centre);
        let reach_m = band_in * IN2M;
        if (geom::length(delta) as f64) > reach_m {
            delta = geom::mul(geom::normalized(delta), reach_m);
        }
        // NML-1073 M4-7, seam-gated: the imagination stops moving in a straight
        // line through walls and Impassable terrain. The tier-2 query answers
        // where the unit CENTRE actually ends after following a coarse route,
        // and the delta becomes that displacement. It sits AFTER the band clamp
        // (the route may only spend the band) and BEFORE the spacing clamp, so
        // the two seams compose: the path decides the route, spacing still
        // trims the resting place.
        if seams.path {
            if let (Cover::Board(t), Some(ix)) = (cover, reach) {
                let mut mover = owner_bit(si);
                for h in state.attached[si].iter() {
                    mover |= owner_bit(*h);
                }
                if let Some(host) = state.attached_to[si] {
                    mover |= owner_bit(host);
                }
                let mut foe = 0u32;
                if let Some(c) = ci {
                    foe = owner_bit(c);
                    for h in state.attached[c].iter() {
                        foe |= owner_bit(*h);
                    }
                }
                let radius_in = next.radii[si]
                    .iter()
                    .copied()
                    .fold(DEFAULT_BASE_RADIUS_M, f64::max)
                    / IN2M
                    + CLEARANCE_EPS_IN;
                let q = ReachQuery {
                    start: t.to_inch(centre),
                    target: t.to_inch(geom::add(centre, delta)),
                    radius: radius_in,
                    band: (geom::length(delta) as f64) / IN2M,
                    // `BattleSim` has no p.11 per-polyline difficult cap today;
                    // the seam does not invent one.
                    cap_in: 0.0,
                    mover,
                    foe,
                };
                let r = ix.query_memo(&q);
                let end = t.from_inch(r.end_centre, centre[1]);
                delta = geom::sub(end, centre);
            }
        }
        // NML-1068: RUSH and CHARGE share this same translation — one clamp
        // covers both (battle_sim.gd:647-650).
        if seams.spacing {
            delta = geom::mul(delta, spacing_fraction(&next, si, delta, ci));
        }
        // D5-1 — what the CHARGE's move budget has left, measured on the
        // displacement that actually happened (after the band clamp AND the
        // spacing clamp, which is what `last_move_remaining_in`
        // solo_controller.gd:8659-8667 measures on the table: the budget minus
        // the LONGEST model arc, and a rigid translation gives every model the
        // same arc). This is a LOWER bound on the table's remainder, because
        // the table walks a bent route and spends more arc than this straight
        // line does — so the gate below under-refuses rather than over-refuses.
        if seams.charge_landing && kind == CHARGE {
            charge_remaining_in = (band_in - geom::length(delta) as f64 / IN2M).max(0.0);
        }
        for p in next.positions[si].iter_mut() {
            *p = geom::to_f64(geom::add(geom::to_f32(*p), delta));
        }
        // D1-B4b: a joined hero's models move WITH the host. The table plans the
        // host's move over ONE model list that already contains them —
        // `SoloController._moving_models` :5319-5321 returns
        // `get_alive_models_with_attached()` — and `_plan_positions` :6084-6086
        // starts every model from the same rigid `delta`. The simplest faithful
        // mirror is that delta, applied AFTER both clamps, so the hero lands
        // inside the unit's footprint instead of being left behind on the board.
        // (Per-model steering is the table's; this port has never had it.)
        if seams.hero_attach {
            for &h in state.attached[si].iter() {
                for p in next.positions[h].iter_mut() {
                    *p = geom::to_f64(geom::add(geom::to_f32(*p), delta));
                }
            }
        }
        // battle_sim.gd:598-600 — T2b: the mover's cover follows it, probed at
        // the POST-move unit centre (`centre + delta`, after both the band clamp
        // and the spacing clamp).
        match cover {
            Cover::Recorded(Some(c)) => next.in_cover[si] = c,
            Cover::Recorded(None) => {}
            Cover::Board(t) => {
                if t.is_valid() {
                    next.in_cover[si] = gives_cover(t.type_at(geom::add(centre, delta)));
                }
            }
        }
    }
    // --- cast sub-phase (battle_sim.gd:602-607), seam-gated ---
    // `_best_spell_target` (:930) probes `_los_clear` with the POST-move
    // centres, which the pre-move `los_pairs` of `state_before` cannot answer —
    // the same shape of missing input `cover_dest` fixed for terrain. The
    // caller supplies the caster's row; without one the pre-move matrix is used
    // and a moved caster's targeting is an approximation.
    if seams.cast {
        let row: Vec<bool> = match cast_los {
            Some(r) => r.to_vec(),
            None => (0..next.units()).map(|j| los_clear(&next, si, j)).collect(),
        };
        cast_phase(statics, &mut next, si, &row, rng.as_deref_mut());
    }

    // --- shoot (battle_sim.gd:608-630); HOLD and ADVANCE only ---
    if !shoot_key.is_empty() && (kind == HOLD || kind == ADVANCE) {
        if moved {
            return Err(Unsupported::MovedShootLos);
        }
        if let Some(&ti) = next.roster.index.get(shoot_key.as_str()) {
            if next.sees(si, &shoot_key) && los_clear(&next, si, ti) {
                let d = geom::dist_in(&next.positions[si], &next.positions[ti]);
                let alive_before = next.alive[ti];
                let wounds_before = wounds_left(&next, ti);
                // Seam ON: a plain volley — the cast sub-phase above already
                // ran. Seam OFF: the LEGACY spell rider (battle_sim.gd:621-628),
                // where the spell's EV joins the volley and the caster pays for
                // it inside the shoot pick.
                let (volley, sp_cost) = {
                    let us = &statics[pi_s];
                    let ut = &statics[next.roster.profile[ti]];
                    profiles_of(us, next.alive[si], d, &mut sc);
                    let att = ctx_of(us, &next, si);
                    let def = ctx_of(ut, &next, ti);
                    let shooting = shoot_ev(&us.shoot, &sc.keep, &sc.attacks, &att, &def, d);
                    if seams.cast {
                        (shooting, 0)
                    } else {
                        let (sp_ev, sp_cost) =
                            spell_ev_of(us.is_caster, &us.spells, next.casts[si], &def, d);
                        if sp_ev > 0.0 {
                            (shooting + sp_ev, sp_cost)
                        } else {
                            (shooting, 0)
                        }
                    }
                };
                next.casts[si] -= sp_cost; // 0 unless the spell rider fired
                match dice.as_mut() {
                    // D1-B4: the table's dice, in the table's draw order. The
                    // wounds then land through the SAME casualty machinery the
                    // EV path uses — kill order stays the trainer's.
                    Some((tray, shot)) => {
                        let ut = &statics[next.roster.profile[ti]];
                        let def = ctx_of(ut, &next, ti);
                        // D1-B4b: the volley's MEMBERS, in the table's build
                        // order — the host, then its attached heroes in
                        // capture order (`main._run_ai_shooting` :2954-2958,
                        // `State::attached` state.rs:361-362). Each brings its
                        // OWN ranged set, Quality and survivor scaling
                        // (:2985-2990); a member with no living model is
                        // skipped exactly as the table skips it (:2959).
                        // D6a-B4: with `sighting="model"` the die count is the
                        // table's own, per member and per WEAPON — the board's
                        // sight volumes are built once for the whole volley.
                        let zones = match (seams.sighting, cover) {
                            (true, Cover::Board(t)) => sight::zones_of(t),
                            _ => Vec::new(),
                        };
                        let mut parts: Vec<(usize, Scratch, Ctx)> = Vec::new();
                        for &mi in std::iter::once(&si).chain(next.attached[si].iter()) {
                            if next.alive[mi] <= 0 {
                                continue;
                            }
                            let um = &statics[next.roster.profile[mi]];
                            let mut msc = Scratch::default();
                            if seams.sighting {
                                sighted_profiles_of(um, &next, statics, mi, ti, &zones, d, &mut msc);
                            } else {
                                profiles_of(um, next.alive[mi], d, &mut msc);
                            }
                            parts.push((mi, msc, ctx_of(um, &next, mi)));
                        }
                        let members: Vec<crate::dice::Shooter<'_>> = parts
                            .iter()
                            .map(|(mi, msc, att)| {
                                let um = &statics[next.roster.profile[*mi]];
                                crate::dice::Shooter {
                                    profiles: &um.shoot,
                                    keep: &msc.keep,
                                    attacks: &msc.attacks,
                                    att,
                                    owner: &um.name,
                                }
                            })
                            .collect();
                        let r = crate::dice::resolve_volley_with_tray(
                            &members, &def, &ut.name, d, tray,
                        );
                        // D1-B5a: `absorb`, not `=` — a CHARGE activation puts
                        // several sub-phases into ONE report, and the replay
                        // gate compares the whole activation roll by roll.
                        let w = shot.absorb(r);
                        land_wounds(&mut next, ti, w);
                    }
                    None => apply_expected_wounds(&mut next, ti, volley, rng.as_deref_mut()),
                }
                // D1-B5b: the volley's morale test is the NEXT thing on the
                // table's tray (main.gd:8248-8251). Leaving it undrawn is what
                // put every later activation of a `dice="table"` game on a
                // different stream than the recording.
                let ut = &statics[next.roster.profile[ti]];
                if shooting_morale_trigger(&next, ut, ti, alive_before, wounds_before) {
                    match dice.as_mut() {
                        Some((tray, shot)) => tray_morale(&mut next, ut, ti, false, tray, shot),
                        None => {
                            if morale_fails_expected(&next, ut, ti) {
                                next.shaken[ti] = true;
                            }
                        }
                    }
                }
            }
        }
    }

    // --- charge (battle_sim.gd:698-714) ---
    // No sight check here, only BASE CONTACT measured AFTER the move. The
    // trigger is the base-EDGE gap, not the centre distance against CONTACT_IN
    // — two 32 mm bases (radius 0.016 m) meet at a 1.26" centre distance, past
    // the old 1.0" gate, so a landed 32 mm+ charge never fought (NML-1073 S1b).
    // NML-1073 S1d: it is measured against MELEE_ENGAGE_IN (1"), the TABLE's own
    // engage-and-snap distance, not the 0.25" contact epsilon. Unconditional,
    // not seam-gated: this is the landing rule itself, not a research seam.
    if kind == CHARGE {
        if let Some(ti) = ci {
            let engage_gap_in = geom::edge_gap_in(
                &next.positions[si],
                &next.radii[si],
                &next.positions[ti],
                &next.radii[ti],
                DEFAULT_BASE_RADIUS_M,
            );
            // D5-1: the table asks TWICE before it fights. First the engage
            // distance (main.gd:8005-8006, the line above). Then whether the
            // snap that closes the residual base gap still FITS the move budget
            // the charge left over — `snap_charge(unit, target,
            // last_move_remaining_in())` returning negative is a falls-short
            // and no fight (main.gd:8015-8022, solo_controller.gd:8639/8644).
            // A gap already inside the contact epsilon snaps for free.
            if engage_gap_in <= MELEE_ENGAGE_IN
                && (engage_gap_in <= BASE_CONTACT_EPSILON_IN
                    || engage_gap_in <= charge_remaining_in + BASE_CONTACT_EPSILON_IN)
            {
                let tu_before = wounds_left(&next, ti);
                let su_before = wounds_left(&next, si);
                // D1-B5a: with `dice="table"` the whole melee is resolved on the
                // tray instead, phase by phase in the table's own order. The
                // loser then takes the SAME expected-value morale outcome the EV
                // path gives it — the morale DIE is D1-B5b's, deliberately left
                // undrawn so this PR changes the melee and nothing else.
                if let Some((tray, shot)) = dice.as_mut() {
                    if let Some(li) = tray_charge(statics, &mut next, si, ti, tray, shot) {
                        // D1-B5b: the melee loser's test is a REAL die now
                        // (:8116-8118), where D1-B5a still asked the
                        // expected-value oracle for the outcome.
                        let ul = &statics[next.roster.profile[li]];
                        tray_morale(&mut next, ul, li, true, tray, shot);
                    }
                } else {
                    // The charger strikes: charging profiles, its OWN fatigue state
                    // (still the pre-charge one), the defender's plain context.
                    let ev = {
                        let us = &statics[pi_s];
                        let ut = &statics[next.roster.profile[ti]];
                        let att = ctx_of_melee(us, &next, si);
                        let def = ctx_of(ut, &next, ti);
                        melee_profiles_of(us, next.alive[si], &mut sc);
                        melee_ev(&us.melee, &sc.attacks, &att, &def, true)
                    };
                    apply_expected_wounds(&mut next, ti, ev, rng.as_deref_mut());
                    next.fatigued[si] = true;
                    if next.alive[ti] > 0 {
                        // Survivors strike back, already survivor-scaled by the
                        // updated `alive`. W-P1 parity (p.9): the strike-back
                        // fatigues the DEFENDER too.
                        let ev_back = {
                            let ut = &statics[next.roster.profile[ti]];
                            let us = &statics[pi_s];
                            let att = ctx_of_melee(ut, &next, ti);
                            let def = ctx_of(us, &next, si);
                            melee_profiles_of(ut, next.alive[ti], &mut sc);
                            melee_ev(&ut.melee, &sc.attacks, &att, &def, false)
                        };
                        apply_expected_wounds(&mut next, si, ev_back, rng.as_deref_mut());
                        next.fatigued[ti] = true;
                    }
                    expected_melee_morale(&mut next, statics, si, su_before, ti, tu_before);
                }
            }
        }
    }

    // --- shaken recovery (battle_sim.gd:648-650) ---
    if was_shaken && kind == HOLD && shoot_key.is_empty() {
        next.shaken[si] = false;
    }
    next.activated[si] = true;
    // D1-B4b: a joined hero spends the HOST's activation, never one of its own
    // (`SoloController.can_activate` solo_controller.gd:411). Marking it here is
    // what keeps `MY_UNACTIVATED` (rows.rs:491) and `moves_left` (score.rs:96)
    // honest once the host has gone, and it is the second half of the pool
    // filter: `can_activate` stops the hero being offered BEFORE the host moves,
    // this stops it being offered after.
    if seams.hero_attach {
        for &h in state.attached[si].iter() {
            next.activated[h] = true;
        }
    }
    // NML-1073 M3-5: the sight matrix follows the MODELS. `BattleSim._los_clear`
    // (battle_sim.gd:792-796) calls `state["los_blocked"]` with the CURRENT
    // centres on every probe, so a unit that just rushed — or one that just lost
    // models, or routed off the table — is seen from its NEW centre by the very
    // next reply-threat read. The parent's matrix answers for where it stood.
    // Refreshed only on the LIVE board (`Cover::Board`) and only when the parent
    // carried a matrix at all: a `Cover::Recorded` replay reads each node's own
    // recorded rows, and a state with no matrix had no `los_blocked` seam.
    if let Cover::Board(terrain) = cover {
        refresh_los_pairs(&mut next, state, terrain);
    }
    Ok(next)
}

/// Rewrites the `los_pairs` row AND column of every unit whose model positions
/// changed in this activation — the mover, its casualties, a routed unit whose
/// positions were cleared. Untouched units keep the parent's answers, which are
/// still the ones `SchoolTerrain.los_blocked` would give for the same two
/// centres. Both directions are recomputed rather than mirrored: the GDScript
/// samples `a.lerp(b, t)`, and the two orders are only equal in exact
/// arithmetic.
fn refresh_los_pairs(next: &mut State, parent: &State, terrain: &Terrain) {
    if !terrain.is_valid() {
        return;
    }
    let Some(old) = next.los_pairs.as_ref() else { return };
    let n = next.units();
    let moved: Vec<usize> =
        (0..n).filter(|&i| next.positions[i] != parent.positions[i]).collect();
    if moved.is_empty() {
        return;
    }
    let mut m = (**old).clone();
    let centres: Vec<V3> = (0..n).map(|i| geom::centre(&next.positions[i])).collect();
    for &i in &moved {
        for j in 0..n {
            m[i * n + j] = !terrain.los_blocked(centres[i], centres[j]);
            m[j * n + i] = !terrain.los_blocked(centres[j], centres[i]);
        }
    }
    next.los_pairs = Some(Rc::new(m));
}

#[cfg(test)]
mod d6a_tests {
    use super::*;

    fn weapon(attacks: i64, count: i64, range: i64) -> ShootProfile {
        ShootProfile { attacks, count, range, ..Default::default() }
    }

    /// `SoloController.effective_shoot_reach_in` — the Aircraft penalty first,
    /// Ranged Shrouding after it, and the `int()` the caller applies.
    #[test]
    fn the_sight_reach_follows_the_targets_two_range_rules() {
        let plain = Ctx::default();
        let shroud = Ctx { ranged_shrouding: true, ..Ctx::default() };
        assert_eq!(sight_reach_in(24.0, false, &plain), 24.0);
        // Aircraft: -12" (SoloController.AIRCRAFT_TARGET_RANGE_PENALTY_IN).
        assert_eq!(sight_reach_in(24.0, true, &plain), 12.0);
        // Never below zero — a 9" pistol against an Aircraft simply cannot reach.
        assert_eq!(sight_reach_in(9.0, true, &plain), 0.0);
        // Ranged Shrouding: -6" to a floor of 6".
        assert_eq!(sight_reach_in(24.0, false, &shroud), 18.0);
        assert_eq!(sight_reach_in(9.0, false, &shroud), 6.0);
        // Both, in the table's order: 30 - 12 = 18, then -6 = 12.
        assert_eq!(sight_reach_in(30.0, true, &shroud), 12.0);
    }

    /// `SoloController.scaled_attacks_report` — the FLAT ratio for a weapon every
    /// model carries, the BEARER CAP for a weapon only some do.
    #[test]
    fn the_die_count_takes_the_ratio_or_the_bearer_cap() {
        // 5 models, a rifle each (count == model_count): the ratio path, and it
        // is `round(base * sighted / max)` — 3 of 5 sighted of 10 attacks is 6.
        let rifle = weapon(10, 5, 24);
        assert_eq!(bearer_scaled_attacks(&rifle, 5, 5, 5), 10);
        assert_eq!(bearer_scaled_attacks(&rifle, 5, 5, 3), 6);
        assert_eq!(bearer_scaled_attacks(&rifle, 5, 5, 0), 0);
        // 2 special weapons in a unit of 5, 2 attacks each (merged base 4): the
        // bearer path caps at the copies, so a wide sightline adds nothing...
        let special = weapon(4, 2, 24);
        assert_eq!(bearer_scaled_attacks(&special, 5, 5, 5), 4);
        // ...and a narrow one binds instead of the copies.
        assert_eq!(bearer_scaled_attacks(&special, 5, 5, 1), 2);
        // Casualties take bearers with them: 1 model left carries at most 1 copy.
        assert_eq!(bearer_scaled_attacks(&special, 1, 5, 5), 2);
        // RED for the whole rung: answering `alive` instead of `sighted` gives
        // the count this port drew before D6a, and it is a different number.
        assert_ne!(bearer_scaled_attacks(&rifle, 5, 5, 3), bearer_scaled_attacks(&rifle, 5, 5, 5));
    }
}
