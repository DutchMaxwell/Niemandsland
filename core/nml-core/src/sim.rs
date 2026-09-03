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

use std::collections::HashMap;
use std::rc::Rc;

use crate::combat::{
    at_or_below_half, block_chance, effective_attacks, melee_ev, morale_target, shielded_defense,
    shoot_ev, should_test_shooting_morale, shrouded_reach, SHROUD_FLOOR_IN, SHROUD_RANGE_PENALTY_IN,
};
// NML-1073 M5 D6a-B4 — the per-model sight twin, used only behind `sighting`.
use crate::sight;
use crate::geom::{self, V3};
use crate::acts::{rule_on, CURRENT_RULES_EPOCH};
use crate::io::{Action, Seams, SplitShot};
use crate::dice::{Morale, ShootResult, Tray};
use crate::mods;
use crate::rng::GodotRng;
use crate::rules::Spell;
use crate::spell::{cast_success_chance_base, official_pick_order, spell_damage_ev_of, spell_ev_of};
use crate::state::State;
use crate::mv::reach::{owner_bit, Disc, ReachBuild, ReachIndex, ReachQuery};
use crate::mv::CLEARANCE_EPS_IN;
use crate::terrain::{base_in_terrain, gives_cover, is_dangerous, Terrain};
use crate::unit::{Ctx, UnitStatic, ShootProfile, UtilityBuff};
#[cfg(test)]
use crate::unit::GrowthRule;
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
    /// NML-1158b step 5 — `ActStatics.policy_mode == Order` but the caller
    /// wired no policy net: same contract as `FittedEval`, a mode an act
    /// asked for and the search cannot honour is a decline, not a silent
    /// fall-back to the hand order.
    PolicyOrder,
    /// NML-1164 — `Search::cand_logits` carried a different number of logits
    /// than the prefilter built rows. A vector that does not line up with the
    /// menu names the WRONG candidates, so it declines outright rather than
    /// re-rank part of the order. `(given, built)`.
    CandLogits(usize, usize),
    /// NML-1165 R4 (DESIGN_value_net §7) — the LEAF VALUE hook answered with a
    /// different number of values than the search handed it leaves. `(given,
    /// handed)`. Same contract as `CandLogits`: a vector that does not line up
    /// prices the WRONG leaves, so the search declines outright rather than
    /// blend part of the backup.
    LeafValue(usize, usize),
    /// NML-1165 R4 — `leaf_value_w != 0.0` with no hook wired. Mirrors
    /// `FittedEval` / `PolicyOrder`: a blend that was asked for and cannot be
    /// honoured is a decline, never a silent fall-back to the hand leaf.
    LeafValueMissing,
    /// NML-1073 M3-6b — `tokens::build` refuses a state whose live roster,
    /// marker count or menu width exceeds the padding budget (`N_UNITS`,
    /// `N_OBJ`, `N_CAND`) rather than truncate a row: a truncated board is a
    /// silently wrong board (the `verify-the-instrument` rule). The `usize` is
    /// the count actually seen.
    TooManyUnits(usize),
    TooManyObjectives(usize),
    TooManyCandidates(usize),
}

/// `BattleSim._los_clear` battle_sim.gd:666-670, read off the recorded answers.
/// No matrix = no `los_blocked` seam on the state = clear for every pair.
#[inline]
fn los_clear(state: &State, i: usize, j: usize) -> bool {
    state.los_clear(i, j)
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

/// `_solo_tray_roll(model_count, 6, ...)` main.gd:7030 — the tray's SUCCESS
/// target for a dangerous-terrain test, which the recording stamps on the roll.
/// It is not the wound threshold: `_run_ai_dangerous` :7033 counts the **1s**.
pub const DANGEROUS_TARGET: i64 = 6;

/// `_run_ai_dangerous` main.gd:7032-7035 — a face of **1** is a wound to the
/// unit. Named rather than inlined because the roll's recorded TARGET is 6 and
/// the two numbers are easy to read as one.
#[inline]
pub(crate) fn dangerous_wounds(faces: &[u8]) -> i64 {
    faces.iter().filter(|&&f| f == 1).count() as i64
}

/// `main._solo_apply_mend`'s D3, counted off ONE tray face (:5247 maps
/// 1-2→1, 3-4→2, 5-6→3 — `(face + 1) / 2` in integer arithmetic).
#[inline]
pub(crate) fn mend_d3(face: u8) -> i64 {
    (i64::from(face) + 1) / 2
}

/// The heal primitive's reach — "pick one friendly model within 3\"" (army-book
/// rule text; mechanics param `range_in: 3.0`, rules_mechanics_gf.json:1350).
pub const MEND_RANGE_IN: f64 = 3.0;
/// `_solo_tray_roll(1, 1, ...)` main.gd:5244 — the D3 value roll records the
/// tray's default `roll_kind` "attack" (main.gd:7107) with success target 1.
pub const MEND_TARGET: i64 = 1;

/// BLOCK B1 — the heal primitive on the tray path's pre-attack slot:
/// `_solo_apply_mend` main.gd:5227-5259 and `_solo_mend_pick` :5329-5365.
/// Official text: "Once per activation, before attacking, pick one friendly
/// model within 3\" with Tough, and remove D3 wounds from it."
///
/// Runs for EVERY action kind, right where main.gd:1056-1058 sits: after the
/// casts, before attacking. When the acting unit or an alive attached hero
/// bears Mend (registry-gated, `unit_rule_active` :5234-5238), the most-wounded
/// alive Tough model (per-model `wounds_max > 1`) of the bearer's player within
/// 3" of any bearer model heals D3 off ONE tray die. Ties prefer heroes
/// (`key = lost * 2 + hero`, strict `>` :5361-5364). No bearer, no patient —
/// or an actor that just died to terrain (:1054) — draws NOTHING, and that
/// matters: every later face of the activation sits behind this draw. The tray
/// path only: the EV imagination stays Mend-blind, exactly like the table's
/// own planner (BattleSim has no Mend).
pub(crate) fn tray_mend(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
) {
    // main.gd:1054 — an actor killed by its own dangerous-terrain test skips
    // the whole pre-attack block, Mend included (host-alive only,
    // game_unit.gd:112-113, NOT the combined count).
    if next.alive[si] <= 0 {
        return;
    }
    // The bearers: the acting unit plus its attached heroes, each needing at
    // least one alive model and the rule registry-active (:5230-5240). The
    // heroes half rides the same seam `dangerous_dice`'s heroes half does —
    // parity unaffected (the replay gates force `hero_attach=table`).
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach {
        bearers.extend(next.attached[si].iter().copied());
    }
    if !bearers
        .iter()
        .any(|&b| next.alive[b] > 0 && statics[next.roster.profile[b]].mend_active)
    {
        return;
    }
    // The bearer models' positions (:5330-5340) — the reach any patient must
    // fall into. Model-centre distance, planar on the table
    // (MoveIntent.distance_inches zeroes Y); the corpus records y = 0.
    let mut bearer_pos: Vec<[f64; 3]> = Vec::new();
    for &b in &bearers {
        bearer_pos.extend(next.positions[b].iter().copied());
    }
    // The patient scan (:5344-5365): every friendly unit in capture order,
    // every alive model in array order, first best wins the strict `>`.
    let pid = next.player[si];
    let mut patient: Option<(usize, usize, i64)> = None; // (unit, model, wounds_max)
    let mut best_key: i64 = -1;
    for u in 0..next.units() {
        if next.player[u] != pid || next.alive[u] == 0 {
            continue;
        }
        let um = &statics[next.roster.profile[u]];
        // `wounds_max` is the FULL model list and the wounds array only the
        // survivors; this port's casualties come off the FRONT (`land_wounds`),
        // so the living models are that list's tail — the same mapping
        // `dangerous_dice` ships. (The TABLE removes casualties
        // defender-optimally, solo_controller.gd:8060-8110; the tail-mapping is
        // exact for uniform-Tough units and front-eaten casualties alike.)
        let w = &um.wounds_max;
        let off = w.len().saturating_sub(next.positions[u].len());
        for m in 0..next.wounds[u].len() {
            let Some(&wmax) = w.get(off + m) else { continue };
            let cur = next.wounds[u][m];
            if wmax <= 1 || cur >= wmax {
                continue;
            }
            if geom::dist_in(&bearer_pos, &[next.positions[u][m]]) > MEND_RANGE_IN {
                continue;
            }
            let key = (wmax - cur) * 2 + i64::from(um.is_hero);
            if key > best_key {
                best_key = key;
                patient = Some((u, m, wmax));
            }
        }
    }
    let Some((pu, pm, wmax)) = patient else { return };
    // One D3 die, recorded exactly as the table records it (:5244, the tap at
    // :7152-7162): kind "attack", target 1, one face, the ACTING unit's name.
    let faces = tray.roll(1);
    let Some(&f0) = faces.first() else { return };
    let d3 = mend_d3(f0);
    shot.rolls.push(crate::dice::Roll {
        kind: "attack",
        count: 1,
        target: MEND_TARGET,
        faces,
        owner: statics[next.roster.profile[si]].name.clone(),
    });
    let healed = d3.min(wmax - next.wounds[pu][pm]);
    if healed > 0 {
        next.wounds[pu][pm] += healed;
    }
}

/// The breath primitive's shape, uniform across all 17 AoF carriers
/// (rules_mechanics_aof.json `primitive: "Breath Attack"` — one params block:
/// `{trigger_target: 2, range_in: 6.0, blast: 3, ap: 1}`). Consts, not a
/// per-unit registry read, the `MEND_RANGE_IN`/`MEND_TARGET` precedent.
pub const BREATH_RANGE_IN: f64 = 6.0;
pub const BREATH_BLAST: i64 = 3;
pub const BREATH_AP: i64 = 1;
pub const BREATH_TRIGGER: i64 = 2;

/// `SoloController.combined_alive` (NML-966) — host + attached heroes' alive
/// model counts, seam-gated exactly like `tray_mend`'s own hero fold.
fn combined_alive(state: &State, i: usize, seams: Seams) -> i64 {
    state.alive[i]
        + if seams.hero_attach {
            state.attached[i].iter().map(|&h| state.alive[h]).sum::<i64>()
        } else {
            0
        }
}

/// BLOCK B3 — the breath-weapon primitive on the tray path's pre-attack slot,
/// right after Mend: `_solo_apply_breath_attack` main.gd:5262-5330. Official
/// text: "Once per activation, before attacking, pick one enemy unit within
/// 6\" and roll one die; on a 2+ it takes 3 hits with Blast(3) and AP(1)."
/// One breath PER AI UNIT ACTIVATION however many bearers carry it (main.gd's
/// own doc comment, :5263-5264) — the bearer check only asks whether ANY
/// bearer is active, exactly like `tray_mend`'s.
///
/// Range/LOS are read off the ACTING unit's OWN models only (main.gd:5279-
/// 5286 — `_solo_nearest_model_gap_in(unit, hu, ...)`/`_solo_has_los(unit,
/// hu)` name `unit`, not the bearer set Mend folds in): the base-EDGE gap
/// (`edge_gap_in`, the "profile range gate" B11 truth) and the captured LOS
/// matrix (`los_clear`, the same gate the shoot branch above reads). The
/// target is the best-scoring living, UNattached enemy unit — `min(Blast,
/// combined alive) * (1 - block chance)` at the target's Armor+Shielded
/// Defense. Cover and the Guarded/over-9 family are OUT OF SCOPE by the
/// table's own wording (main.gd:5390-5397 — `_solo_defense_vs` never calls
/// `_solo_cover_defense`/`_solo_over9_defense_rule` here).
///
/// One trigger die at `BREATH_TRIGGER`; a target found is what earns the draw
/// (no target, no die, matching Mend's no-patient rule) and a miss still lands
/// on the tray. Blast already decided the hit count on a 2+ — no to-hit roll
/// of its own — so `resolve_breath_attack_with_tray` runs straight to the
/// save + Regeneration leg, and the landed wounds feed the same post-shooting
/// morale trigger the shoot branch above uses.
pub(crate) fn tray_breath_attack(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
) {
    if next.alive[si] <= 0 {
        return;
    }
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach {
        bearers.extend(next.attached[si].iter().copied());
    }
    if !bearers
        .iter()
        .any(|&b| next.alive[b] > 0 && statics[next.roster.profile[b]].breath_attack_active)
    {
        return;
    }
    let pid = next.player[si];
    let mut target: Option<usize> = None;
    let mut best = 0.0f64;
    for ti in 0..next.units() {
        if next.player[ti] == pid || next.alive[ti] <= 0 {
            continue;
        }
        if seams.hero_attach && next.attached_to[ti].is_some() {
            continue;
        }
        let gap = geom::edge_gap_in(
            &next.positions[si], &next.radii[si], &next.positions[ti], &next.radii[ti],
            DEFAULT_BASE_RADIUS_M,
        );
        if gap > BREATH_RANGE_IN || !los_clear(next, si, ti) {
            continue;
        }
        let ut = &statics[next.roster.profile[ti]];
        let def = ctx_of(ut, next, ti);
        let sdef = shielded_defense(def.defense, def.shielded);
        let alive_t = combined_alive(next, ti, seams);
        let score = (BREATH_BLAST.min(alive_t) as f64) * (1.0 - block_chance(sdef, BREATH_AP, false));
        if score > best {
            best = score;
            target = Some(ti);
        }
    }
    let Some(ti) = target else { return };
    let faces = tray.roll(1);
    let Some(&f0) = faces.first() else { return };
    shot.rolls.push(crate::dice::Roll {
        kind: "attack",
        count: 1,
        target: BREATH_TRIGGER,
        faces,
        owner: statics[next.roster.profile[si]].name.clone(),
    });
    if crate::dice::faces_to_hits(&[f0], BREATH_TRIGGER as u8) == 0 {
        return;
    }
    let hits = BREATH_BLAST.min(combined_alive(next, ti, seams)).max(1);
    let ut = &statics[next.roster.profile[ti]];
    let def = ctx_of(ut, next, ti);
    let alive_before = next.alive[ti];
    let wounds_before = wounds_left(next, ti);
    let out = crate::dice::resolve_breath_attack_with_tray(hits, BREATH_AP, &def, &ut.name, tray);
    let landed = shot.absorb(out);
    land_wounds(next, ti, landed);
    if shooting_morale_trigger(next, ut, ti, alive_before, wounds_before) {
        tray_morale(next, ut, ti, false, tray, shot);
    }
}

// ------------------------------------ BLOCK B2: UTILITY BUFF (movement) ---

/// "pick one friendly model within 6\" with Artillery" (army-book rule text;
/// mechanics param `range_in: 6.0`, rules_mechanics_gf.json / _aof.json,
/// "Re-Position Artillery").
pub const REPOSITION_PICK_RANGE_IN: f64 = 6.0;
/// "...which may immediately move by up to 9\"" (mechanics param
/// `reposition_in: 9.0`).
pub const REPOSITION_MOVE_IN: f32 = 9.0;

/// BLOCK B2 — the movement half of the "Utility Buff" registry primitive:
/// Re-Position Artillery, `_solo_apply_utility_buffs` main.gd:16499-16507,
/// picked by `_solo_utility_target`/`_solo_utility_targets` main.gd:16295-
/// 16296, :16317-16359. Official text: "Once per activation, pick one
/// friendly model within 6\" with Artillery, which may immediately move by
/// up to 9\"."
///
/// Runs right after Mend, in the same pre-attack slot `_solo_apply_utility_
/// buffs` occupies on the table (main.gd:1062, after Mend + the unported
/// Breath Attack). Per BEARER — the acting unit, then each attached hero in
/// turn, the table's own `for m in members` loop (main.gd:16481-16483), not
/// a combined bearer set like Mend's: when a bearer carries the rule, the
/// highest-VALUE (alive models + Tough, main.gd:16358) friendly Artillery
/// unit within 6" of THAT bearer's own centre is picked; if it has no legal
/// shoot target right now (`best_shoot_target_now`, replicated existence-
/// only below — which target it would pick never matters, only whether one
/// exists), it is forced straight toward the nearest enemy
/// (`nearest_human_unit`'s primary key, see `nearest_enemy_reposition`) up
/// to 9", clamped so no model leaves the table (`_axis_scale` :8911-8915).
/// Dice-free start to finish, matching the table exactly.
///
/// The rest of the family — the friendly/enemy modifier buffs (Casting Buff,
/// Morale Debuff, Precision Attacks Buff, Precision Fighter Buff, Primal Boost
/// Buff) — lands as a RECORD on the picked unit's `State.buffs` ledger, which
/// `ctx_live` folds into the to-hit and morale targets of every later tray roll
/// (block B2b). The enemy-side Marks (`vs_target`) are skipped here on purpose:
/// they belong to the ATTACK seam, `tray_vs_marks`.
pub(crate) fn tray_utility_buff(statics: &[UnitStatic], next: &mut State, si: usize, seams: Seams, cover: Cover) {
    if next.alive[si] <= 0 {
        return;
    }
    let terrain = match cover {
        Cover::Board(t) => Some(t),
        Cover::Recorded(_) => None,
    };
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach {
        bearers.extend(next.attached[si].iter().copied());
    }
    for &bearer in &bearers {
        if next.alive[bearer] <= 0 {
            continue;
        }
        let pb = next.roster.profile[bearer];
        if statics[pb].reposition_artillery_active {
            reposition_artillery_for(statics, next, bearer, seams, terrain);
        }
        for b in &statics[pb].utility_buffs {
            // :16495 the Mark arm and :16497 the movement arm both `continue`
            // out of the table's own loop before the pick below.
            if b.vs_target || b.reposition_in > 0.0 {
                continue;
            }
            for ti in utility_targets(statics, next, bearer, b, seams) {
                record_buff(next, ti, b);
            }
        }
    }
}

/// `main._solo_record_spell_mod` :3649-3670 — one record onto the picked
/// unit's ledger, with the GDScript's own two guards: a record with neither a
/// modifier nor a grant never lands (:3653/:3663). `beneficiary` is hard-coded
/// "" at the Utility-Buff call site (:16541), so these are always the bearer's
/// own net, never an attackers-side one.
fn record_buff(state: &mut State, ti: usize, b: &UtilityBuff) {
    if b.hit_mod == 0 && b.casting_mod == 0 && b.morale_mod == 0 && b.grants_rule.is_empty() {
        return;
    }
    state.buffs[ti].push(mods::LiveMod {
        hit_mod: b.hit_mod,
        casting_mod: b.casting_mod,
        morale_mod: b.morale_mod,
        grants_rule: Rc::from(b.grants_rule.as_str()),
        scope: Rc::from(b.scope.as_str()),
        attackers: b.beneficiary == "attackers",
        once: b.once,
    });
}

/// `RadialMenu._caster_member_of` radial_menu.gd:489-499 — the unit itself or
/// one of its alive attached heroes is a Caster. Hero-fold seam-gated like
/// every other chain read in this file.
fn caster_member(statics: &[UnitStatic], state: &State, u: usize, seams: Seams) -> bool {
    if statics[state.roster.profile[u]].is_caster {
        return true;
    }
    seams.hero_attach
        && state.attached[u].iter().any(|&h| state.alive[h] > 0 && statics[state.roster.profile[h]].is_caster)
}

/// `main._solo_utility_targets` :16317-16359 — up to `max_targets` legal picks
/// for one buff, best VALUE first (`alive_count + Tough`, :16358). Alive,
/// non-reserve, never an ATTACHED unit (a joined hero is bought through its
/// host), the kind's own filter, the printed range measured centre to centre
/// (`MoveIntent.distance_inches` :16344) and sight when the params ask for it.
///
/// NOT PORTED — Extended Buff Range (wave 4, :16326-16337): a candidate beyond
/// the printed range that the relay clause would still make legal. That is its
/// own rule with its own registry entry (`SoloController.ebr_relay_ok`), it is
/// gated on the buffing hero carrying it, and no carrier of the six names in
/// this block also carries it. A relayed pick this port refuses is the table
/// buffing someone this twin does not.
///
/// The sort is STABLE, so a value tie keeps roster order; the GDScript's
/// `sort_custom` is an introsort and leaves ties unspecified — the same call
/// `reposition_artillery_for` already makes with its strict `>` (first wins).
fn utility_targets(
    statics: &[UnitStatic],
    state: &State,
    bearer: usize,
    b: &UtilityBuff,
    seams: Seams,
) -> Vec<usize> {
    let own = state.player[bearer];
    let enemy = b.target == "enemy";
    let from = geom::centre(&state.positions[bearer]);
    let mut scored: Vec<(f64, usize)> = Vec::new();
    for u in 0..state.units() {
        if (state.player[u] == own) == enemy || state.alive[u] <= 0 || state.dormant[u] {
            continue;
        }
        if seams.hero_attach && state.attached_to[u].is_some() {
            continue;
        }
        if b.target == "friendly_caster" && !caster_member(statics, state, u, seams) {
            continue;
        }
        let uc = ctx_of(&statics[state.roster.profile[u]], state, u);
        if b.target == "friendly_artillery" && !uc.artillery {
            continue;
        }
        let d = (geom::length(geom::sub(from, geom::centre(&state.positions[u]))) / IN2M as f32) as f64;
        if d > b.range_in {
            continue;
        }
        if b.needs_los && !los_clear(state, bearer, u) {
            continue;
        }
        scored.push((state.alive[u] as f64 + uc.tough as f64, u));
    }
    scored.sort_by(|a, c| c.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    scored.truncate(b.max_targets.max(1) as usize);
    scored.into_iter().map(|(_, u)| u).collect()
}

/// `main._solo_consume_once_mods` :3823-3841 — one resolved exchange spends
/// every `once` record that was AVAILABLE to it: the attacker's own hit mods
/// and rule grants, the defender's attackers-beneficiary mods and grants. The
/// two roles this port has no seam for — the defender's "defense" and the
/// shooter's "range" — are simply not in the ledger yet, so they cannot be
/// spent either; that is the same gap, not a second one.
fn spend_exchange(state: &mut State, att: usize, def: usize, melee: bool) {
    mods::spend_once(state, att, &[mods::Role::AttackerOwn, mods::Role::Grant], melee);
    mods::spend_once(state, def, &[mods::Role::VsTarget, mods::Role::Grant, mods::Role::GrantVs], melee);
}

/// `main._solo_apply_vs_marks` :16738-16771 — the ENEMY-side half of the
/// Utility-Buff family (Unstoppable Mark). It does not run at the pre-attack
/// slot: the pick IS the attack's committed target, so the table calls it at
/// the attack seam itself (:3042 inside a volley group, :8035 in a charge —
/// after Impact, before the strikes). Every bearer of the attacker's joined
/// chain may mark once per round; the rule's base name (the entry minus
/// " Mark") lands on the ATTACKER as a once-grant, and `ctx_live` carries it
/// into the very rolls this seam precedes.
fn tray_vs_marks(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    ti: usize,
    dist_in: f64,
    seams: Seams,
) {
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach {
        bearers.extend(next.attached[si].iter().copied());
        if let Some(h) = next.attached_to[si] {
            bearers.push(h);
        }
    }
    for bearer in bearers {
        if next.alive[bearer] <= 0 {
            continue;
        }
        let pb = next.roster.profile[bearer];
        for b in &statics[pb].utility_buffs {
            if !b.vs_target || next.vs_mark_round[bearer] == next.round || dist_in > b.range_in {
                continue;
            }
            // NML-936 (:16758): the printed rule picks "within 18\" IN LINE OF
            // SIGHT", and `needs_los` may waive it from the data.
            if b.needs_los && !los_clear(next, bearer, ti) {
                continue;
            }
            next.vs_mark_round[bearer] = next.round;
            let base = b.name.strip_suffix(" Mark").unwrap_or(b.name.as_str());
            next.buffs[si].push(mods::LiveMod {
                hit_mod: 0,
                casting_mod: 0,
                morale_mod: 0,
                grants_rule: Rc::from(base),
                scope: Rc::from(""),
                attackers: false,
                once: true,
            });
        }
    }
}

/// One bearer's pick + move — see `tray_utility_buff`.
fn reposition_artillery_for(
    statics: &[UnitStatic],
    next: &mut State,
    bearer: usize,
    seams: Seams,
    terrain: Option<&Terrain>,
) {
    let pid = next.player[bearer];
    let from = geom::centre(&next.positions[bearer]);
    let mut arty: Option<usize> = None;
    let mut best_v = f64::NEG_INFINITY;
    for u in 0..next.units() {
        if next.player[u] != pid || next.alive[u] <= 0 || next.dormant[u] {
            continue;
        }
        if seams.hero_attach && next.attached_to[u].is_some() {
            continue;
        }
        let uc = ctx_of(&statics[next.roster.profile[u]], next, u);
        if !uc.artillery {
            continue;
        }
        let d = (geom::length(geom::sub(from, geom::centre(&next.positions[u]))) / IN2M as f32) as f64;
        if d > REPOSITION_PICK_RANGE_IN {
            continue;
        }
        let v = next.alive[u] as f64 + uc.tough as f64;
        if v > best_v {
            best_v = v;
            arty = Some(u);
        }
    }
    let Some(arty) = arty else { return };
    if has_shoot_target(statics, next, arty) {
        return;
    }
    let Some(enemy) = nearest_enemy_reposition(statics, next, arty) else { return };
    let delta = geom::sub(geom::centre(&next.positions[enemy]), geom::centre(&next.positions[arty]));
    let len = (delta[0] * delta[0] + delta[2] * delta[2]).sqrt();
    if len < 1e-6 {
        return;
    }
    let dir = [delta[0] / len, delta[2] / len];
    let dist_in = clamp_move_to_board(terrain, &next.positions[arty], dir, REPOSITION_MOVE_IN);
    if dist_in <= 0.0 {
        return;
    }
    let step_m = dist_in * IN2M as f32;
    for p in next.positions[arty].iter_mut() {
        p[0] += (dir[0] * step_m) as f64;
        p[2] += (dir[1] * step_m) as f64;
    }
}

/// `SoloController.best_shoot_target_now` :1141-1171, EXISTENCE-only: the
/// table ranks candidates by EV to pick the BEST one, but Re-Position
/// Artillery only ever asks whether ONE exists (`== null`), so the ranking
/// is not replicated here — a scan over max weapon range + LOS (or
/// Indirect) answers the same boolean. `shooting_range_bonus` (a flat
/// per-unit add, e.g. Royal Legion +4") is unmodelled everywhere in this
/// port (io.rs) and stays unmodelled here too.
fn has_shoot_target(statics: &[UnitStatic], state: &State, arty: usize) -> bool {
    let us = &statics[state.roster.profile[arty]];
    let max_range = us.shoot.iter().map(|p| p.range).max().unwrap_or(0) as f64;
    if max_range <= 0.0 {
        return false;
    }
    let indirect = us.shoot.iter().any(|p| p.indirect);
    let pid = state.player[arty];
    for e in 0..state.units() {
        if state.player[e] == pid || state.alive[e] <= 0 || state.dormant[e] {
            continue;
        }
        let ectx = ctx_of(&statics[state.roster.profile[e]], state, e);
        let reach = sight_reach_in(max_range, state.aircraft[e], &ectx);
        if reach <= 0.0 || geom::dist_in(&state.positions[arty], &state.positions[e]) > reach {
            continue;
        }
        if indirect || los_clear(state, arty, e) {
            return true;
        }
    }
    false
}

/// `SoloController.nearest_human_unit` :1183-1210 — the primary key only
/// (not-yet-activated first, then nearest centre-to-centre); a melee-only
/// bearer (no ranged profile) skips Aircraft, same as the table. A genuine
/// tie inside the table's 1" band (`TARGET_TIE_BAND_IN`) is broken there by
/// a melee EV score (:1218-1235) this port does not replicate — an exact
/// tie falls back to the lowest roster index, a documented gap rather than
/// a silent wrong answer (the fresh gate corpus for this rule has none).
fn nearest_enemy_reposition(statics: &[UnitStatic], state: &State, arty: usize) -> Option<usize> {
    let melee_only = statics[state.roster.profile[arty]].shoot.is_empty();
    let pid = state.player[arty];
    let from = geom::centre(&state.positions[arty]);
    let (mut best, mut best_activated, mut best_d) = (None, true, f32::INFINITY);
    for e in 0..state.units() {
        if state.player[e] == pid || state.alive[e] <= 0 || state.dormant[e] {
            continue;
        }
        if melee_only && state.aircraft[e] {
            continue;
        }
        let d = geom::length(geom::sub(from, geom::centre(&state.positions[e])));
        let activated = state.activated[e];
        let better = match best {
            None => true,
            Some(_) if activated != best_activated => !activated,
            Some(_) => d < best_d,
        };
        if better {
            (best, best_activated, best_d) = (Some(e), activated, d);
        }
    }
    best
}

/// `SoloController.forced_straight_move`'s board clamp :10367-10386 (the
/// shared `_axis_scale` step, every model's own position, the smallest
/// per-model per-axis scale wins). No board (`Terrain::absent()`, or a
/// `Cover::Recorded` node with none) leaves the move unclamped.
fn clamp_move_to_board(terrain: Option<&Terrain>, positions: &[[f64; 3]], dir: [f32; 2], dist_in: f32) -> f32 {
    let Some(t) = terrain.filter(|t| t.is_valid()) else { return dist_in };
    let board = t.board_in();
    if board[0] <= 0.0 || board[1] <= 0.0 {
        return dist_in;
    }
    let half = [board[0] as f32 * 0.5, board[1] as f32 * 0.5];
    let step_in = [dir[0] * dist_in, dir[1] * dist_in];
    let mut scale = 1.0f32;
    for p in positions {
        scale = scale.min(axis_scale((p[0] / IN2M) as f32, step_in[0], half[0]));
        scale = scale.min(axis_scale((p[2] / IN2M) as f32, step_in[1], half[1]));
    }
    dist_in * scale.clamp(0.0, 1.0)
}

/// `SoloController._axis_scale` solo_controller.gd:8911-8915, verbatim.
fn axis_scale(start: f32, d: f32, limit: f32) -> f32 {
    let dest = start + d;
    if dest.abs() <= limit || d.abs() < 1e-6 {
        return 1.0;
    }
    let bound = if dest > 0.0 { limit } else { -limit };
    ((bound - start) / d).clamp(0.0, 1.0)
}

// ------------------------------------------- BLOCK B5: HIT & RUN (move) ---

/// "...units where all models have this rule may move by up to 3\" after
/// shooting or being in melee" (army-book text; mechanics param `move_in:
/// 3.0`, identical on every occurrence of the three carriers this block
/// ports — a const stands in for a per-unit registry read, the
/// `MEND_RANGE_IN`/`BREATH_RANGE_IN` precedent).
pub const HIT_AND_RUN_MOVE_IN: f32 = 3.0;

/// BLOCK B5 — `SoloController.hit_and_run_move` solo_controller.gd:9649-9713,
/// called main.gd:1083-1089 right after the ACTING unit's own shoot/melee
/// resolves (`resolve_with`'s call site, right after the charge block). Ported
/// carriers: the literal "Hit & Run" name and its two data aliases sharing its
/// primitive, "Guerrilla" and "Harassing" (`hit_and_run_active`) — the two
/// half-primitives "Hit & Run Fighter"/"Hit & Run Shooter" were out of that
/// 11-unit/2-list block's scope and port in BLOCK C1 on top of the same gate
/// (see `after_shoot` below); neither carries an `after` param on any of the
/// three ported names, so the table's own shoot-vs-melee half-scoping never
/// applies to them (verified over every `rules_mechanics_*.json` occurrence).
///
/// FIRE GATE: the ACTING unit's OWN rule only — unlike Mend/Breath Attack, the
/// table's function body never reads an attached hero's rules (it moves the
/// WHOLE joined formation, not one member of it). Once per ROUND
/// (`unit_properties["hit_and_run_round"]`, :9685), consumed only on an actual
/// move — no bearer, no living enemy, or a board-clamped zero step all leave
/// it unspent.
///
/// NOT PORTED — the EV-scored placement branch (`_position_solver_active()` +
/// `_solve_position`, :9691-9696): a cover/objective/threat-aware spot this
/// core has no position-solver infrastructure for. This port always takes the
/// table's own documented FALLBACK instead (:9653, "the fallback steps
/// straight away from the nearest enemy (kiting)") — a step directly AWAY from
/// `nearest_enemy_reposition`'s pick (#485, reused rather than duplicating
/// `_nearest_enemy_of`'s own slightly different not-yet-activated tie-break).
///
/// S11 — HOW the fallback step lands, seam-gated: the table's fallback runs
/// `_move_away` :4761 -> `_execute_move` :4784, the per-model solver — the
/// same chain S3 (`mv::step::plain_move`) already ports for ADVANCE/RUSH.
/// Under `movement=table` the kiting goal is the table's own mirror (`centre
/// + (centre - enemy centre)`, `_move_away` :4767, anchored on the
/// `_nearest_enemy_of` pick :9669 — `plain_move` clamps it to the board
/// itself, its `clamp_to_bounds` being the ported `_clamp_to_bounds`), handed
/// to `plain_move` with the 3" band; the solver routes the formation around
/// difficult/dangerous terrain and spends the band per model.
///
/// `None` (the port declines) or `movement=rigid`/`--red-move-rigid`: the
/// pre-S11 rigid translation below, byte-identical —
/// `clamp_move_to_board`/`axis_scale` (#485's `forced_straight_move` port,
/// reused rather than porting a second clamp shape for `_execute_move`'s own
/// `_clamp_to_bounds`). Dangerous terrain is NOT rolled for this step even
/// when it crosses some: the table's own `_execute_move` return value is
/// discarded uncalled at both call sites (:9694/:9698) — a faithful mirror of
/// a table gap, not a new one.
///
/// `SoloController._nearest_enemy_of` solo_controller.gd:4738-4757 — the
/// nearest living enemy by centre distance, attached heroes skipped
/// (`is_attached`), reserves skipped, no activated preference. Hit & Run's
/// own kiting anchor (:9669), unlike #485's reposition pick.
fn nearest_enemy_of(state: &State, si: usize) -> Option<usize> {
    let pid = state.player[si];
    let from = geom::centre(&state.positions[si]);
    let (mut best, mut best_d) = (None, f32::INFINITY);
    for e in 0..state.units() {
        if state.player[e] == pid
            || state.alive[e] <= 0
            || state.attached_to[e].is_some()
            || state.dormant[e]
        {
            continue;
        }
        let d = geom::length(geom::sub(from, geom::centre(&state.positions[e])));
        if d < best_d {
            best_d = d;
            best = Some(e);
        }
    }
    best
}

/// Block C5 — Instinctive's closest-target gate (`_solo_instinctive_mod`
/// main.gd:5774-5799, read by BOTH branches of `_solo_hit_mod_info`): the
/// bonus stands exactly while the attacked unit IS the closest enemy —
/// forfeited when ANY other living, non-reserve, non-attached enemy is
/// closer than `distance(shooter, target) - 0.5` (the half-inch tie band,
/// centre to centre). NOT a legality rule: the pick stands, only the +1 is
/// lost (main.gd:5792-5793). The scan mirrors `nearest_enemy_of`'s skip
/// list (own side, dead, attached, dormant/reserve) plus the target itself,
/// in METRES with the band converted by the file's own `IN2M`.
fn instinctive_applies(state: &State, from: usize, ti: usize) -> bool {
    let d = geom::length(geom::sub(
        geom::centre(&state.positions[from]),
        geom::centre(&state.positions[ti]),
    ));
    let band = (0.5 * IN2M) as f32;
    for e in 0..state.units() {
        if e == ti
            || state.player[e] == state.player[from]
            || state.alive[e] <= 0
            || state.attached_to[e].is_some()
            || state.dormant[e]
        {
            continue;
        }
        let de = geom::length(geom::sub(
            geom::centre(&state.positions[from]),
            geom::centre(&state.positions[e]),
        ));
        if de < d - band {
            return false;
        }
    }
    true
}

/// Returns whether the unit actually moved — the caller logs the battle-log
/// line on it (main.gd:1089).
///
/// BLOCK C1 — `after_shoot` is the table's caller flag (main.gd:1083-1089:
/// true after a shot, false after melee): the rule pick solo_controller.gd:
/// 9663-9670 fires the FULL rule on either trigger, but each half ONLY on its
/// own — `var half := "Hit & Run Shooter" if after_shoot else "Hit & Run
/// Fighter"`, an EXACT name match (`AiEv.has_exact_rule`). The shared
/// per-round stamp (:9685) and `move_in` (:9687) are unchanged.
fn tray_hit_and_run(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    seams: Seams,
    cover: Cover,
    after_shoot: bool,
) -> bool {
    let us = &statics[next.roster.profile[si]];
    if next.alive[si] <= 0
        || !(us.hit_and_run_active
            || (after_shoot && us.hit_and_run_shooter_active)
            || (!after_shoot && us.hit_and_run_fighter_active))
    {
        return false;
    }
    if next.hit_and_run_round[si] == next.round {
        return false;
    }
    let Some(enemy) = nearest_enemy_reposition(statics, next, si) else { return false };
    let delta = geom::sub(geom::centre(&next.positions[si]), geom::centre(&next.positions[enemy]));
    let len = (delta[0] * delta[0] + delta[2] * delta[2]).sqrt();
    if len < 1e-6 {
        return false;
    }
    let dir = [delta[0] / len, delta[2] / len];
    let terrain = match cover {
        Cover::Board(t) => Some(t),
        Cover::Recorded(_) => None,
    };
    if seams.movement && !seams.move_rigid {
        if let Cover::Board(t) = cover {
            let land = nearest_enemy_of(next, si).and_then(|foe| {
                // `_move_away` :4767 — the table's own `_nearest_enemy_of`
                // anchor (:9669), mirrored through the bearer's own centre;
                // `plain_move` does the `_clamp_to_bounds(goal)`.
                let centre = geom::centre(&next.positions[si]);
                let foe = geom::centre(&next.positions[foe]);
                let dest = [
                    centre[0] + (centre[0] - foe[0]),
                    centre[1],
                    centre[2] + (centre[2] - foe[2]),
                ];
                crate::mv::step::plain_move(
                    next,
                    t,
                    si,
                    dest,
                    HIT_AND_RUN_MOVE_IN as f64,
                    seams.hero_attach,
                    true,
                    crate::mv::FAST_PLANNER_GUARD,
                )
            });
            if let Some(land) = land {
                for (i, m) in land.movers.iter().enumerate() {
                    next.positions[m.unit][m.model] = geom::to_f64(land.end[i]);
                }
                next.hit_and_run_round[si] = next.round;
                return true;
            }
        }
    }
    let dist_in = clamp_move_to_board(terrain, &next.positions[si], dir, HIT_AND_RUN_MOVE_IN);
    if dist_in <= 0.0 {
        return false;
    }
    let step_m = dist_in * IN2M as f32;
    for p in next.positions[si].iter_mut() {
        p[0] += (dir[0] * step_m) as f64;
        p[2] += (dir[1] * step_m) as f64;
    }
    // The whole joined formation moves as one (`_moving_models`), the same
    // hero-fold every other rigid move in `resolve_with` applies.
    if seams.hero_attach {
        let heroes = next.attached[si].clone();
        for h in heroes {
            for p in next.positions[h].iter_mut() {
                p[0] += (dir[0] * step_m) as f64;
                p[2] += (dir[1] * step_m) as f64;
            }
        }
    }
    next.hit_and_run_round[si] = next.round;
    true
}

/// BLOCK B8 — `SoloController.second_wind_candidate`/`spend_second_wind`
/// (solo_controller.gd:10429-10479), called from `_solo_after_activation`
/// (main.gd:1762) right before a round would otherwise close: once per GAME,
/// a full carrier unit that has ALREADY activated this round (`is_activated`)
/// may activate a SECOND time (fatigue clears), capped at `ceil(carriers /
/// army_cap_fraction)` grants per round, army-wide. Every registry occurrence
/// of the primitive ("Inquisitorial Agent", "Martial Prowess") sets
/// `uses_per_game: 1, army_cap_fraction: 3` (verified) — a const stands in for
/// both, the `HIT_AND_RUN_MOVE_IN` precedent. Picked by `_plan_ev_of(gu) +
/// alive*0.1` on the table; this port picks by `alive` alone — `_plan_ev_of`
/// runs the AI's own search tree, which this bookkeeping layer does not carry
/// (a declared simplification, not a silent one: with ≤6 carriers and a cap
/// of ≤2 per round, the tie-break rarely changes the outcome).
///
/// FIRE GATE — the table's check is scoped to a SINGLE fixed `ai_slot` (the
/// SoloController's one configured AI opponent, a UI-layer restriction, not a
/// rule one). This core has no `ai_slot`/`human_slot` split — both players
/// share the same symmetric `resolve_with` seam — so the port applies the
/// identical carrier/cap/pick logic to the ACTING side (`next.player[si]`)
/// once NEITHER side has a unit left that can still activate.
///
/// KNOWN GAP, stated plainly: the table's OWN native both-AI arena driver
/// (`_solo_run_both_ai_round`/`_solo_run_both_ai_game`, main.gd:1828-1922 —
/// what generates this project's training corpus) never calls
/// `_solo_after_activation` at all; that seam is reachable only from the
/// single-player human-vs-AI pump (main.gd:917, :1621). Second Wind (and its
/// sibling Coordinate, main.gd:1276) have not yet had the "wave 5" that added
/// Delayed Action to that same round loop (main.gd:1849-1850's own docstring
/// names exactly this class of gap). So no arena game — recorded before or
/// after this port — can show a real table-side "Second Wind" firing; see the
/// PR body for the empirical confirmation. The Rust fixture tests below are
/// this port's correctness proof.
const SECOND_WIND_CAP_FRACTION: i64 = 3;

fn second_wind_candidate(statics: &[UnitStatic], state: &State, player: i64) -> Option<usize> {
    let mut carriers = 0i64;
    let mut best: Option<(usize, i64)> = None;
    for i in 0..state.units() {
        if state.player[i] != player || state.alive[i] <= 0 || state.attached_to[i].is_some() {
            continue;
        }
        if !statics[state.roster.profile[i]].second_wind_active {
            continue;
        }
        carriers += 1;
        if state.second_wind_used[i] || !state.activated[i] {
            continue;
        }
        if best.map_or(true, |(_, v)| state.alive[i] > v) {
            best = Some((i, state.alive[i]));
        }
    }
    let cap = (carriers + SECOND_WIND_CAP_FRACTION - 1) / SECOND_WIND_CAP_FRACTION;
    let uses = if state.second_wind_round == state.round { state.second_wind_uses } else { 0 };
    if uses >= cap {
        return None;
    }
    best.map(|(i, _)| i)
}

fn spend_second_wind(next: &mut State, i: usize) {
    if next.second_wind_round != next.round {
        next.second_wind_round = next.round;
        next.second_wind_uses = 0;
    }
    next.second_wind_uses += 1;
    next.second_wind_used[i] = true;
    next.activated[i] = false;
    next.fatigued[i] = false;
}

/// `SoloController._execute_move` :5033-5047 (GF/AoF v3.5.1 p.12, "Bug 23") —
/// how many dice the move's dangerous-terrain test rolls.
///
/// THE RULE, verbatim from the table. Flying ignores terrain effects while
/// moving (p.13) and tests for nothing. Every other MOVING model — the host's
/// and its attached heroes' alike (`_moving_models` :5375) — is affected when
/// its ROUTE crossed a Dangerous cell OR it was ACTIVATED standing in one, both
/// measured edge-aware on the base (`TerrainRules.base_in_terrain`). One test
/// per affected model, and that test rolls the model's TOUGH value in dice
/// (`maxi(1, wounds_max)`), summed — the count `report["dangerous_dice"]` :2228
/// carries and `_run_ai_dangerous` draws.
///
/// THE CROSSING HALF IS ONLY EXACT WITH `movement="table"`, where D5-2's
/// `Landing::dangerous` carries the solver's own per-model trails. A rigid move
/// has no route at all, so the END cell stands in for it and the activation is
/// marked `dangerous_rigid_end_only`: a model that walked THROUGH a minefield
/// and stopped past it is missed there. The activated-in-it half is exact
/// either way.
#[allow(clippy::too_many_arguments)]
pub(crate) fn dangerous_dice(
    statics: &[UnitStatic],
    state: &State,
    next: &State,
    si: usize,
    seams: Seams,
    landing: Option<&crate::mv::step::Landing>,
    cover: Cover,
    shot: &mut ShootResult,
) -> i64 {
    let Cover::Board(t) = cover else { return 0 };
    if !t.is_valid() || state.profile(si).special_rules.iter().any(|r| r == "Flying") {
        return 0;
    }
    // `base_in_terrain` on this board — both halves of the trigger use it.
    let in_dang = |p: &[f64; 3], r: f64| base_in_terrain(geom::to_f32(*p), r, t, is_dangerous);
    let radius = |st: &State, u: usize, m: usize| {
        st.radii[u].get(m).copied().unwrap_or(DEFAULT_BASE_RADIUS_M)
    };
    // (unit, model, did the model's route cross a Dangerous cell)
    let mut movers: Vec<(usize, usize, bool)> = Vec::new();
    match landing {
        Some(l) => movers.extend((0..l.movers.len()).map(|i| {
            (l.movers[i].unit, l.movers[i].model, l.dangerous.get(i).copied().unwrap_or(false))
        })),
        None => {
            shot.mark("dangerous_rigid_end_only");
            let mut units = vec![si];
            if seams.hero_attach {
                units.extend(state.attached[si].iter().copied());
            }
            for u in units {
                let ends = (0..next.positions[u].len())
                    .map(|m| (u, m, in_dang(&next.positions[u][m], radius(next, u, m))));
                movers.extend(ends);
            }
        }
    }
    let mut dice = 0;
    for (u, m, crossed) in movers {
        let Some(p0) = state.positions[u].get(m) else { continue };
        if !crossed && !in_dang(p0, radius(state, u, m)) {
            continue;
        }
        // `wounds_max` is the FULL model list and `positions` only the survivors;
        // this port's casualties come off the FRONT (`land_wounds`), so the living
        // models are that list's tail.
        let w = &statics[state.roster.profile[u]].wounds_max;
        let off = w.len().saturating_sub(state.positions[u].len());
        dice += w.get(off + m).copied().unwrap_or(1).max(1);
    }
    dice
}

/// `SoloController.nearest_melee_gap_in` solo_controller.gd:8526 — the gap the
/// table measures before it lets a charge fight, and it measures it over
/// `_moving_models` (:5375) on BOTH sides: each unit's own alive models PLUS
/// its attached heroes'. D5-1 asked the same question over the HOSTS alone, so
/// a hero standing at the front of its host — or on the target — was invisible
/// to the engage test while the very same models had just been moved by it
/// (:1123 / `mv::step::movers_of`). The D5-2 review measured 14 charge acts the
/// table fought and this port refused for exactly that reason.
///
/// `geom::edge_gap_in` is itself a minimum over model pairs, so the minimum
/// over the (host + heroes) x (host + heroes) cross product IS the one number
/// `nearest_melee_gap_in` returns. A hero with no models left contributes
/// `INFINITY` and changes nothing, the same way an empty `b_shapes` does there.
///
/// SEAM-GATED, and on `hero_attach` alone — no new seam: without it the state
/// is not folded anywhere else either (the pool, the volley, the move), so
/// folding it HERE would measure a unit the rest of the resolver does not
/// believe in. With the seam off the two lists are the hosts alone and this
/// collapses to the single `edge_gap_in` call D5-1 wrote, byte for byte.
/// `no_engage_fold` is the RED switch and nothing else — see `io::Seams`.
fn engage_gap_in(state: &State, si: usize, ti: usize, seams: Seams) -> f64 {
    let fold = seams.hero_attach && !seams.no_engage_fold;
    let side = |u: usize| -> Vec<usize> {
        let mut v = vec![u];
        if fold {
            v.extend(state.attached[u].iter().copied());
        }
        v
    };
    // D5-2b: WHICH of the table's two edge measures this is. With both charge
    // seams off the resolver is imitating `BattleSim`, whose own
    // `edge_gap_in` (battle_sim.gd:869) knows nothing but a radius — so the
    // circumscribing circle IS the parity target and every rollout digest
    // holds. With `charge_landing` or `movement` on it is imitating the LIVE
    // table (`main._run_ai_melee` -> `nearest_melee_gap_in` :8536 ->
    // `SeparationChecker.edge_distance`), which walks the exact support extent
    // of an oval base. Same seam split `hero_attach` already draws for the fold.
    let shaped = seams.charge_landing || seams.movement;
    let shape = |u: usize| if shaped { state.base_shape(u) } else { geom::BaseShape::Round };
    let mut best = f64::INFINITY;
    for a in side(si) {
        for b in side(ti) {
            let g = geom::edge_gap_shaped_in(
                &state.positions[a],
                &state.radii[a],
                shape(a),
                &state.positions[b],
                &state.radii[b],
                shape(b),
                DEFAULT_BASE_RADIUS_M,
            );
            if g < best {
                best = g;
            }
        }
    }
    best
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

/// NML block B2b — the live-buff fold on top of an already-built context. It
/// is a SEPARATE step, not part of `ctx_of`, so the EV imagination keeps
/// reading the same buff-blind numbers `BattleSim._ctx_of` gives it and only
/// the tray path sees the ledger. `melee` is the scope filter of
/// `AiSpell.mods_for` (ai_spell.gd:390-393), not a fatigue switch.
#[inline]
pub fn ctx_live(mut c: Ctx, statics: &[UnitStatic], state: &State, i: usize, melee: bool) -> Ctx {
    c.hit_mod = mods::sum(state, i, mods::Role::AttackerOwn, melee, |r| r.hit_mod);
    c.vs_hit_mod = mods::sum(state, i, mods::Role::VsTarget, melee, |r| r.hit_mod);
    c.unstoppable_grant = mods::granted(state, i, "Unstoppable");
    // DEFECT_LEDGER #33 — a live "Furious" grant (a spell cast, same shape as
    // any other rule grant) reaches this round's melee exactly where the
    // static special-rule scan (`unit::ctx_for`) already sets it, and stays
    // out of the EV-only imagination, which never calls `ctx_live` at all.
    c.furious = c.furious || mods::granted(state, i, "Furious");
    // The rending/thrust legs of the same grant bridge (main.gd:16576-16589),
    // and the Ctx-flag grants the rung E buffs hand out — each lands exactly
    // where the static has-rule test already stamped its flag.
    c.rending_grant = mods::granted(state, i, "Rending");
    c.thrust_grant = mods::granted(state, i, "Thrust");
    c.relentless_grant = mods::granted(state, i, "Relentless");
    c.shred_grant = mods::granted(state, i, "Shred");
    c.unpredictable = c.unpredictable || mods::granted(state, i, "Unpredictable Fighter");
    c.guarded = c.guarded || mods::granted(state, i, "Guarded");
    c.melee_evasion = c.melee_evasion || mods::granted(state, i, "Melee Evasion");
    // No Retreat folds HERE for every ctx_live caller; the rolled morale test
    // is not one (tray_morale builds on ctx_of), so it carries its own fold
    // next to the same read below.
    c.no_retreat = c.no_retreat || mods::granted(state, i, "No Retreat");
    let (ap, hit) = growth_bonus_of(statics, state, i);
    c.growth_ap_mod = ap;
    c.growth_hit_mod = hit;
    c
}

/// `_solo_bridge_granted_flags`' target half (main.gd:16676-16685): the
/// `beneficiary == "attackers"` records on the TARGET's ledger belong to
/// whoever attacks it (`AiSpell.attacker_grants_from_target` ai_spell.gd:
/// 454-465), so the BRIDGEABLE flag legs (AiSpell.BRIDGE_FLAGS ai_spell.gd:
/// 415) fold into the STRIKER's ctx here, at the exchange seams where the
/// target is known — a mark landed on the bearer empowers its attackers, and
/// never the bearer itself. Tray-only, like `ctx_live`.
pub fn ctx_live_vs(
    mut c: Ctx,
    statics: &[UnitStatic],
    state: &State,
    i: usize,
    target: usize,
    melee: bool,
) -> Ctx {
    c = ctx_live(c, statics, state, i, melee);
    c.rending_grant = c.rending_grant || mods::granted_vs(state, target, "Rending");
    c.furious = c.furious || mods::granted_vs(state, target, "Furious");
    c.relentless_grant = c.relentless_grant || mods::granted_vs(state, target, "Relentless");
    c.shred_grant = c.shred_grant || mods::granted_vs(state, target, "Shred");
    c
}

/// Block B7 — `_solo_growth_attack_bonus` main.gd:17069, folded per
/// `_growth_facet_bonus` (:17060): this unit's own marker COUNT times its
/// carried "Growth Markers" rule's `*_per_marker`/`*_per_two` rates, AP and
/// hit summed separately. `state.growth_markers` is a single counter (see
/// `unit::growth_of`), so a unit carrying two such rules would double-count —
/// out of the training pool's scope.
fn growth_bonus_of(statics: &[UnitStatic], state: &State, i: usize) -> (i64, i64) {
    let markers = state.growth_markers[i];
    if markers <= 0 {
        return (0, 0);
    }
    let mut ap = 0;
    let mut hit = 0;
    for g in &statics[state.roster.profile[i]].growth {
        ap += g.ap_per_marker * markers + g.ap_per_two * (markers / 2);
        hit += g.hit_per_marker * markers + g.hit_per_two * (markers / 2);
    }
    (ap, hit)
}

/// `_solo_growth_round_start` main.gd:16984 — the per-round marker for a
/// `per_round` Growth Markers rule, ticked once per ROUND (`growth_round`
/// gate, the `hit_and_run_round` shape) and blocked while Shaken. This core
/// has no whole-board round-start phase, so it ticks lazily at this unit's
/// own next activation — the only point its OWN marker count is ever read.
/// Dice-free, tray path only (`resolve_with`'s `dice.is_some()` gate).
fn growth_round_start(statics: &[UnitStatic], next: &mut State, si: usize, shaken: bool) {
    if next.growth_round[si] == next.round {
        return;
    }
    let us = &statics[next.roster.profile[si]];
    let Some(cap) = us.growth.iter().find(|g| g.per_round).map(|g| g.max_markers) else {
        return;
    };
    next.growth_round[si] = next.round;
    if !shaken && next.growth_markers[si] < cap {
        next.growth_markers[si] += 1;
    }
}

/// `_solo_growth_on_kill` main.gd:17021 — Piercing/Precision Frenzy: +1
/// marker when this action just fully destroyed the target, capped at the
/// rule's own `max_markers`. Called with the WIPING side's own index, never a
/// per-member split (main.gd credits the acting `attacker`/`charger` GameUnit,
/// not the individual model or weapon that landed the last wound).
fn growth_on_kill(statics: &[UnitStatic], next: &mut State, si: usize) {
    let us = &statics[next.roster.profile[si]];
    let Some(cap) = us.growth.iter().find(|g| g.on_kill).map(|g| g.max_markers) else {
        return;
    };
    if next.growth_markers[si] < cap {
        next.growth_markers[si] += 1;
    }
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
    /// NML-1132: the FOLDED member profile list — the host's weapons followed by
    /// every alive attached hero's, filled only by `member_profiles_of` and only
    /// when the fold ran. EMPTY means "the unit's own slice is the answer", which
    /// is what `folded_slice` reads; every other filler clears it.
    pub fold: Vec<ShootProfile>,
}

/// `BattleSim._profiles_of(su, false, d)` battle_sim.gd:714-749 fused with the
/// distance gate of `AiShooting.profiles_in_range` (ai_shooting.gd:16-17): the
/// merged ranged set is precomputed per unit, so all that is left per call is
/// the range filter and the survivor scaling.
pub fn profiles_of(us: &UnitStatic, alive: i64, d: f64, sc: &mut Scratch) {
    sc.keep.clear();
    sc.attacks.clear();
    sc.fold.clear();
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
    sc.fold.clear();
    for p in &us.melee {
        sc.attacks.push(effective_attacks(p.attacks, alive, us.model_count));
    }
}

/// GF v3.5.1 "Limited" — `SoloController.filter_limited` (solo_controller.gd:
/// 7715-7723): drop an already-fired Limited profile from `sc.keep`/
/// `sc.attacks` (index-parallel). Resolution only, ranged and melee alike.
fn drop_spent_limited(profiles: &[ShootProfile], used: &[String], sc: &mut Scratch) {
    let mut i = 0;
    while i < sc.keep.len() {
        if profiles[sc.keep[i]].limited && used.iter().any(|n| n == &profiles[sc.keep[i]].name) {
            sc.keep.remove(i);
            sc.attacks.remove(i);
        } else {
            i += 1;
        }
    }
}

/// `SoloController.mark_limited_used` (solo_controller.gd:7700-7708,
/// main.gd:3207-3208): called AFTER the dice actually rolled, win or lose —
/// every Limited profile that fired is spent for the rest of the game.
fn mark_spent_limited(profiles: &[ShootProfile], keep: &[usize], used: &mut Vec<String>) {
    for &i in keep {
        let p = &profiles[i];
        if p.limited && !used.iter().any(|n| n == &p.name) {
            used.push(p.name.clone());
        }
    }
}

/// NML-1132 — `profiles_of`/`melee_profiles_of` over the TABLE's own MEMBER list:
/// the host, then every ALIVE attached hero, each with its own weapons and its own
/// survivor scaling. The live table has always built a volley that way
/// (`main._run_ai_shooting` :2910-2941, "a shot per ranged weapon of the unit +
/// attached heroes") and a melee strike phase too (`_solo_attack_groups`
/// main.gd:4284-4290) — but the IMAGINATION read the host's weapons alone on both
/// sides of the port, so the two agreed with each other and disagreed with the table:
/// a rifle squad carrying a fusion-pistol hero was valued, targeted and charged as if
/// the pistol did not exist. Mirrors `BattleSim._profiles_of(su, melee, d, state)`.
///
/// SEAM-GATED on `hero_attach` AND the vintage pin, exactly like `engage_gap_in`
/// and `BattleSim._fold_hero_profiles` (battle_sim.gd:1055-1057): a corpus recorded
/// BEFORE the engage/weapon folds (`no_engage_fold`, the RED switch) must fold
/// nothing, or its charge-melee and shoot volleys price weapons the recording
/// never carried (measured: qbg_ref s27 act 22, 3 vs 4 expected wounds).
///
/// THE APPROXIMATION, named rather than hidden: `shoot_ev`/`melee_ev` price a volley
/// with ONE attacker context, so a hero's weapons roll at the HOST's Quality here.
/// The TRAY resolver does carry the per-member context already (`melee_parts`, the
/// volley members in `resolve`) — only the expected-value layer does not.
pub fn member_profiles_of(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    melee: bool,
    d: f64,
    seams: Seams,
    sc: &mut Scratch,
) {
    let us = &statics[state.roster.profile[si]];
    if !(seams.hero_attach
        && !seams.no_engage_fold
        && state.attached[si].iter().any(|&h| state.alive[h] > 0))
    {
        if melee {
            melee_profiles_of(us, state.alive[si], sc);
        } else {
            profiles_of(us, state.alive[si], d, sc);
        }
        return;
    }
    sc.keep.clear();
    sc.attacks.clear();
    sc.fold.clear();
    for &mi in std::iter::once(&si).chain(state.attached[si].iter()) {
        if state.alive[mi] <= 0 {
            continue; // main.gd:2915 — a member with no living model brings no shot
        }
        let um = &statics[state.roster.profile[mi]];
        let set = if melee { &um.melee } else { &um.shoot };
        for p in set {
            let a = effective_attacks(p.attacks, state.alive[mi], um.model_count);
            // MELEE has no range gate and `melee_ev` no `keep`, so its `attacks` must
            // stay parallel to the whole list; SHOOTING keeps `profiles_of`'s filter
            // and indexes the folded list through `keep`.
            if melee {
                sc.attacks.push(a);
            } else if (p.range as f64) >= d {
                let idx = sc.fold.len();
                sc.keep.push(idx);
                sc.attacks.push(a);
            }
            sc.fold.push(p.clone());
        }
    }
}

/// The profile slice a `member_profiles_of` fill belongs to: the unit's own set when
/// the fold did not run, `sc.fold` when it did.
pub fn folded_slice<'a>(own: &'a [ShootProfile], sc: &'a Scratch) -> &'a [ShootProfile] {
    if sc.fold.is_empty() {
        own
    } else {
        &sc.fold
    }
}

/// NML-1132 — `geom::dist_in` over the TABLE's two model sets: host plus every
/// attached hero, on BOTH sides. The table measures a shot's reach from the FIRING
/// member's models (`main._solo_sighted_count` :4103) to the target unit AND its
/// attached heroes (:4086-4092), so the host-to-host distance the imagination used
/// is neither end of that. `dist_in` is itself a minimum over model pairs, so the
/// minimum over the cross product IS the number the table would measure; a hero with
/// no models left has an empty array and contributes INF, exactly as an empty side does.
/// Fold off = the single `dist_in` call, byte for byte.
pub fn fold_dist_in(state: &State, si: usize, ti: usize, seams: Seams) -> f64 {
    if !seams.hero_attach {
        return geom::dist_in(&state.positions[si], &state.positions[ti]);
    }
    let mut best = f64::INFINITY;
    for &a in std::iter::once(&si).chain(state.attached[si].iter()) {
        for &b in std::iter::once(&ti).chain(state.attached[ti].iter()) {
            best = best.min(geom::dist_in(&state.positions[a], &state.positions[b]));
        }
    }
    best
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
///
/// Fear(X) (GF/AoF Advanced Rules v3.5.1): "This model counts as having dealt
/// +X wounds when checking who won melee." The GDScript this ports left that
/// as "a v0 gap, noted" (battle_sim.gd:1449) and so did this port, but the
/// RESOLVED dice path (`tray_charge`) already adds it — the table itself
/// (`AiCombatMath.fear_adjusted_wounds`, main.gd:8106-8109/:10035-10038)
/// always has. Bug fix, not a new knob: each side's own Fear rating lifts
/// only ITS dealt tally for this comparison, never a wound actually applied.
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
    let score_su = dealt_by_su + statics[state.roster.profile[si]].ctx.fear;
    let score_tu = dealt_by_tu + statics[state.roster.profile[ti]].ctx.fear;
    if score_su == score_tu {
        return;
    }
    let li = if score_su > score_tu { ti } else { si };
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
///
/// `seams.melee_reach` (W2 S0) is `_solo_attack_groups`' own
/// `melee_count = solo_controller.striking_models_for(member, enemy)`
/// (main.gd:4314-4317): each member scales by ITS OWN models within 2" of `ti`
/// instead of its whole `alive` count. Off (the default) is today's behaviour.
fn melee_parts(statics: &[UnitStatic], state: &State, i: usize, ti: usize, seams: Seams) -> Vec<(usize, Scratch, Ctx)> {
    let mut parts: Vec<(usize, Scratch, Ctx)> = Vec::new();
    for &mi in std::iter::once(&i).chain(state.attached[i].iter()) {
        if state.alive[mi] <= 0 {
            continue; // main.gd:4290 — a member with no living model never rolls
        }
        let um = &statics[state.roster.profile[mi]];
        let mut sc = Scratch::default();
        let count = if seams.melee_reach {
            crate::combat::striking_models(&state.positions[mi], &state.positions[ti])
        } else {
            state.alive[mi]
        };
        melee_profiles_of(um, count, &mut sc);
        sc.keep = (0..um.melee.len()).collect();
        drop_spent_limited(&um.melee, &state.limited_used[mi], &mut sc);
        parts.push((
            mi,
            sc,
            ctx_live_vs(ctx_of_melee(um, state, mi), statics, state, mi, ti, true),
        ));
    }
    parts
}

/// ONE side's strike phase on the tray, wounds LANDED. The landing is the point:
/// the table resolves Impact, the charger's strikes and the strike-back as
/// separate phases, and each later one is survivor-scaled by what the earlier
/// ones killed (main.gd:8067-8102). Returns the PRE-Regeneration wounds it
/// caused — the melee-winner tally, which is what the table compares — plus
/// block B13's Retaliate credit (the unsaved lash-back hits, credited to the
/// DEFENDER's tally by the caller, main.gd:8056/:8079/:8099).
///
/// Block B13 — Retaliate(X), main.gd:6146-6171. Measured like the table
/// measures it: the trigger is what ACTUALLY LANDED on the defender
/// (`landed_on_defender`, the post-Regeneration return of the pooled
/// `_solo_land_wounds` :6148-6149 — here `absorb`'s wound count, the same
/// wound-pool difference), not what the strikes rolled. `X` is the
/// per-unit `retaliate_hits_per_wound` (`unit.rs::ctx_for`), so hits =
/// per-wound x wounds TAKEN. The saves roll at the STRIKER's own
/// Shielded-adjusted Defense with no AP (`dice::retaliate_saves_with_tray`),
/// the wounds land on the striker, and the TALLY credit goes to the
/// DEFENDER — `_solo_retaliate_credit += rw` (main.gd:6171), taken by the
/// defender's side at the melee comparison. NON-CHAINING by construction:
/// the lash lands through `land_wounds` alone, never through a strike
/// phase, so retaliation wounds never re-trigger anyone's Retaliate.
#[allow(clippy::too_many_arguments)]
fn strike_phase(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    ti: usize,
    charging: bool,
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
) -> (i64, i64) {
    let mut parts = melee_parts(statics, next, si, ti, seams);
    // Block C5 — Instinctive: the +1 reaches the melee fold ONLY when the
    // attacked unit IS the closest enemy (main.gd:5670-5673), per member
    // carrying it — the pick itself is never constrained.
    for (mi, _, att) in parts.iter_mut() {
        if att.instinctive_hit_bonus > 0 && instinctive_applies(next, *mi, ti) {
            att.hit_mod += att.instinctive_hit_bonus;
        }
    }
    let ut = &statics[next.roster.profile[ti]];
    let def = ctx_live(ctx_of(ut, next, ti), statics, next, ti, true);
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
    // CLASS FIX (external review 03.09. item 3 / F9, `acts::rule_on`): a
    // pre-epoch record with the boolean legacy-OFF (or absent) stays
    // unaffected; `rules_epoch >= 1` (fresh games from this build on) turns
    // this rule on regardless of the boolean.
    let cond_ap_dice = seams.cond_ap_dice || rule_on(seams.rules_epoch, 1);
    // Shred data-alias FAMILY (unit.rs::stamp's arm) — no boolean knob of its
    // own: on from the current rules epoch onward, pre-port corpora replay
    // byte-exact (dice.rs::save_batch's gate).
    let shred_alias_dice = rule_on(seams.rules_epoch, crate::acts::CURRENT_RULES_EPOCH);
    let r = crate::dice::resolve_melee_with_tray(&members, &def, &ut.name, charging, cond_ap_dice, shred_alias_dice, tray);
    for (mi, sc, _) in &parts {
        let melee = &statics[next.roster.profile[*mi]].melee;
        mark_spent_limited(melee, &sc.keep, &mut next.limited_used[*mi]);
    }
    let caused = r.caused;
    let w = shot.absorb(r);
    // B13: the table measures the lash-back on wounds actually TAKEN — the
    // wound-POOL difference (`_solo_retaliate_hits` :4570, NML-937), snapshotted
    // BEFORE the landing like the table's `pools_before` (:6146) — overkill
    // wounds past the last model are lost and lash nothing back.
    let pool_before = wounds_left(next, ti);
    // Block C4 — the death-half snapshots its own count next to the pool: the
    // table snapshots every chain member's alive count BEFORE the phase's
    // casualties (main.gd:5968-5970), and the twin's equivalent is the
    // defender unit's own alive count — nothing else moves `alive[ti]` inside
    // this phase.
    let alive_before = next.alive[ti];
    land_wounds(next, ti, w);
    // Block B13 — the lash-back: ONLY wounds that LANDED post-Regeneration
    // count (the table's `landed_on_defender`, :6147-6149), only a striker
    // that still has models, and NON-CHAINING by construction: the wounds
    // land through `land_wounds` alone, never through another strike phase,
    // so retaliation wounds can never re-trigger anyone's Retaliate.
    let mut retaliated = 0i64;
    let taken = pool_before - wounds_left(next, ti);
    if w > 0 && taken > 0 && def.retaliate_hits_per_wound > 0 && next.alive[si] > 0 {
        let hits = def.retaliate_hits_per_wound * taken;
        shot.log.push(format!("Retaliate: {} lashes back — {} hits", ut.name, hits));
        let su = &statics[next.roster.profile[si]];
        let sctx = ctx_of(su, next, si);
        let (unsaved, landed) = crate::dice::retaliate_saves_with_tray(
            hits, &sctx, &su.name, tray, &mut shot.rolls,
        );
        if unsaved > 0 {
            land_wounds(next, si, landed);
            retaliated = unsaved; // _solo_retaliate_credit += rw (main.gd:6171)
        }
    }
    // Block C4 — Deathstrike / Self-Destruct death-half (`_solo_deathstrike_hits`
    // main.gd:16698-16731, called at :6174 immediately after the Retaliate
    // block): models KILLED by this phase's strikes lash out at the striker,
    // X hits per killed model with X = `death_hits_per_kill` (the two
    // literals' summed rating, `maxi(rating, 1)` each). The hits save at the
    // STRIKER's Shielded-adjusted melee Defense with ap 0 — the same
    // `retaliate_saves_with_tray` — the wounds land on the striker, and,
    // unlike Retaliate, there is NO tally credit: main.gd:6174 never touches
    // `_solo_retaliate_credit`. NON-CHAINING: the wounds land through
    // `land_wounds` alone, never through a new strike phase.
    let killed = alive_before - next.alive[ti];
    if killed > 0 && def.death_hits_per_kill > 0 && next.alive[si] > 0 {
        let su = &statics[next.roster.profile[si]];
        let hits = def.death_hits_per_kill * killed;
        shot.log.push(format!(
            "Deathstrike/Self-Destruct: {}'s dying models lash out — {} takes {} hits",
            ut.name, su.name, hits
        ));
        let sctx = ctx_of(su, next, si);
        let (_, landed) = crate::dice::retaliate_saves_with_tray(
            hits, &sctx, &su.name, tray, &mut shot.rolls,
        );
        land_wounds(next, si, landed);
    }
    spend_exchange(next, si, ti, true); // main.gd:6152, per strike phase
    (caused, retaliated)
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
    // B2b: the live morale records join the Banner bonus in the SAME
    // [2,6]-clamped target the table builds (main.gd:8288-8296).
    ctx.morale_bonus = state.morale_bonus[i]
        + mods::sum(state, i, mods::Role::Morale, melee, |r| r.morale_mod);
    ctx.no_retreat = ctx.no_retreat || mods::granted(state, i, "No Retreat");
    // main.gd:8303 — the test die spends the morale once-mods it just used.
    // Placed after the call because `ctx` already carries the target it built.
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
    mods::spend_once(state, i, &[mods::Role::Morale], melee);
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
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
) -> Option<usize> {
    if statics[next.roster.profile[ti]].melee.iter().any(|p| p.counter) {
        // :8055-8059 — a Counter weapon runs a WHOLE extra strike phase before
        // Impact, and strips Impact dice with it.
        shot.mark("counter_strikes_first");
    }
    let mut by_su = impact_phase(statics, next, si, ti, tray, shot);
    // main.gd:8035 — the charger's Mark lands after Impact and before the
    // strikes, measured at 0" (the two units are in base contact).
    tray_vs_marks(statics, next, si, ti, 0.0, seams);
    let mut by_tu = 0;
    let charger_last = statics[next.roster.profile[si]].ctx.unwieldy;
    for slot in 0..2 {
        if (slot == 0) != charger_last {
            // :8079 — the charger strikes only while BOTH sides still stand;
            // an Impact pool that wiped the defender ends the melee here.
            if next.alive[si] > 0 && next.alive[ti] > 0 {
                // B13: the defender's lash-back credits ITS OWN tally (by_tu).
                let (c, rc) = strike_phase(statics, next, si, ti, true, seams, tray, shot);
                by_su += c;
                by_tu += rc;
                next.fatigued[si] = true;
            }
        } else if next.alive[ti] > 0 && next.alive[si] > 0 {
            // :8100 — and so does the strike-back, in both directions.
            // B13: the strike-back's lash-back credits the charger's tally.
            let (c, rc) = strike_phase(statics, next, ti, si, false, seams, tray, shot);
            by_tu += c;
            by_su += rc;
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

/// NML-1157 — `main._solo_combat_unit` main.gd:8452-8458, the table's own line:
/// "combat intents from an attached hero resolve to its HOST — the joined unit
/// fights as ONE (GF v3.5.1 'Hero')". `main._solo_pick_unit_at` (:9166) does the
/// same for a click, and `solo_controller.gd:1197` keeps attached heroes out of
/// the AI's target list entirely — "a joined hero is PART of its host unit — you
/// target the unit, never the hero alone".
///
/// GF Advanced Rules v3.5.1 p.14 (Hero): a Hero that joins a unit counts as part
/// of that unit; Tough(X): heroes are assigned wounds LAST. This port had
/// neither — `strike_phase` and the volley apply to the NAMED index alone, so a
/// 1-model Tough(3) hero can be killed inside a living 20-model host.
///
/// MEASURED. `~/selfplay_out/gen0_teacher`, 796 replayed activations: 42 of 63
/// chosen charges name a joined hero (25 of 36 in games 11-20), and 544 of 787
/// menu offers do. On the recorded reference bundles `qbg_ref` + `qag_ref` (336
/// games, 16 043 acts) the TABLE ITSELF did it **352 times** — 221 volleys and
/// 131 charges — which is why this is seam-gated OFF: those recordings are the
/// dice oracle, and an oracle that plays an illegal target still has to replay.
///
/// WHAT THIS DOES NOT DO, stated so the seam is not read as more than it is:
/// there is no per-model SPILL. Wounds fill the host and stop there; the hero
/// starts taking them only once its host has no living models, which is p.14's
/// "fights on alone" reached an activation later than the table's own
/// allocation (`main.gd:10823` -> `_solo_wound_models`) reaches it.
///
/// Seam-gated on `hero_last` AND `hero_attach`, like every other chain read in
/// this file: without the fold the resolver does not believe in the chain at all.
fn combat_unit(state: &State, ti: usize, seams: Seams) -> usize {
    if !(seams.hero_last && seams.hero_attach) {
        return ti;
    }
    match state.attached_to[ti] {
        Some(h) if state.alive[h] > 0 => h,
        _ => ti,
    }
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
    if scale <= 0.0 {
        return;
    }
    // DEFECT_LEDGER #33: a `grants_rule` cast lands the same "once" record the
    // utility-buff family already writes (`record_buff`) — `ctx_live` folds it
    // into THIS round's dice, `spend_once` clears it at the first exchange
    // that could have used it, so it never survives into the next round.
    if !entry.grants_rule.is_empty() {
        state.buffs[ti].push(mods::LiveMod {
            hit_mod: 0,
            casting_mod: 0,
            morale_mod: 0,
            grants_rule: Rc::from(entry.grants_rule.as_str()),
            scope: Rc::from(""),
            attackers: entry.beneficiary == "attackers",
            once: true,
        });
    }
    let m = entry.modifier;
    if !m.present {
        return; // no scalar modifier fields — the grant above already landed
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
    seams: Seams,
    mut rng: Option<&mut GodotRng>,
) {
    // p.10: a Shaken unit spends its activation idle and never casts.
    if state.shaken[si] {
        return;
    }
    if state.alive[si] <= 0 {
        return;
    }
    // NML-1157: WHICH member of the chain casts. With `cast_fold` off this is
    // `si` under exactly the old four conditions, so nothing moves.
    let Some(ci) = caster_of(statics, state, si, seams) else {
        return;
    };
    let tokens = state.casts[ci];
    let pi = state.roster.profile[ci];
    let spells = statics[pi].spells.clone();
    // The PICK still starts from the host: `si` carries the models the buff
    // lands on and the `los` row the caller built, and p.14 makes the joined
    // hero part of that unit, so "buff myself" is the unit, not the hero.
    let caster_x = state.profile(ci).caster_value;
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
        state.casts[ci] = (tokens - c).max(0);
    }
}

/// NML-1157 — WHICH member of the activating chain actually casts.
///
/// `Caster(X)` is a HERO rule in every faction book this corpus plays, and a
/// joined hero never activates on its own (`State::can_activate`,
/// `solo_controller.gd:423`), so `si` is always the HOST — and the host is not
/// the caster. `cast_phase` and the legacy spell rider (`resolve`'s shoot
/// branch) both read `statics[profile[si]].is_caster` and `state.casts[si]`,
/// and both therefore answer "no caster, no tokens" for every joined caster
/// there is. Turning `seam_cast` on does not fix it: the sub-phase runs and
/// returns immediately.
///
/// MEASURED on `~/selfplay_out/gen0_teacher`, 20 replayed games: 13 caster
/// units — `Vradhez` Caster(2) and `Echo-3G01` Caster(1), 110 and 100 points —
/// EVERY ONE an attached hero; 52 activations by a chain holding cast tokens;
/// **0 casts and 0 tokens spent**, matching the recordings' own `magic`
/// telemetry (`granted` 4-6 per game, `casts` 0).
///
/// The chain walk is the one `tray_mend` (`:270`), `tray_breath_attack`
/// (`:396`) and the utility buffs (`:504`) already write, and `caster_member`
/// (`:550`) already asks this exact question for buff TARGETING. Seam-gated on
/// `cast_fold` AND `hero_attach`, for the same reason `engage_gap_in` is: with
/// the fold off the rest of the resolver does not believe in the chain either.
fn caster_of(statics: &[UnitStatic], state: &State, si: usize, seams: Seams) -> Option<usize> {
    let armed = |u: usize| {
        let s = &statics[state.roster.profile[u]];
        state.alive[u] > 0 && state.casts[u] > 0 && s.is_caster && !s.spells.is_empty()
    };
    if armed(si) {
        return Some(si);
    }
    if !(seams.cast_fold && seams.hero_attach) {
        return None;
    }
    state.attached[si].iter().copied().find(|&h| armed(h))
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

/// NML-1150 — SPLIT FIRE's plan: the act's `split` aim folded onto THIS state's
/// roster. One entry per target group, in the table's group order
/// (`main.gd:2963-2984`: first-seen order of the per-weapon overlay picks, one
/// `_solo_resolve_ai_volley` per group).
struct SplitGroup {
    /// The group's target, by roster index and by key (`sees` reads keys).
    ti: usize,
    key: String,
    /// The RANGE-VALIDITY gate distance only: the recorded target's plain
    /// nearest-model gap for the pooled plan; the B11 EDGE gap (both base
    /// radii off) for a split group, which exists because the TABLE's own
    /// test fired.
    d: f64,
    /// NML-1152: the over-9" MODIFIER distance (`geom::centre_dist_in` — unit
    /// centre to unit centre, main.gd:3029), kept apart from `d` — the table
    /// gates Stealth/Artillery/Versatile Attack/Relentless/Guarded Defense on
    /// THIS distance, never on the range-validity gap.
    mod_d: f64,
    /// Per member index, the weapon indices of that member's `shoot` list the
    /// table aimed at THIS group, in build order. `None` = the pooled plan:
    /// every kept weapon fires, no narrowing.
    weapons: Option<HashMap<usize, Vec<usize>>>,
}

/// Folds `action.split` onto the state, or answers `None` when the activation
/// stays on the one-recorded-target path: no aim recorded, every entry aimed at
/// the recorded target anyway (the pre-1150 path, byte-identical), a target key
/// absent from the roster, or one member naming one weapon twice (the pooled
/// path is the honest fallback then). `marks` names every dropped divergence,
/// never silent: a port weapon the aim does not list is a shot the table did
/// not fire (a spent Limited, an overlay that refused) and is dropped with
/// `split_dropped`.
fn split_plan(
    split: Option<&Vec<SplitShot>>,
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    shoot_key: &str,
) -> (Option<Vec<SplitGroup>>, Vec<&'static str>) {
    let mut marks: Vec<&'static str> = Vec::new();
    let Some(list) = split.filter(|l| !l.is_empty()) else { return (None, marks) };
    let mut order: Vec<String> = Vec::new();
    for s in list {
        if !order.contains(&s.target) {
            order.push(s.target.clone());
        }
    }
    if order.len() == 1 && order[0] == shoot_key {
        return (None, marks); // aligned with the recorded target — no split
    }
    let mut groups: Vec<SplitGroup> = Vec::new();
    for key in &order {
        let Some(&ti) = state.roster.index.get(key.as_str()) else {
            marks.push("split_unknown_target");
            continue;
        };
        // B11 (main.gd:4098-4104): the table measures shooting range base-EDGE
        // to base-edge — the centre-space equivalent subtracts BOTH base radii
        // from every pair distance. The group exists because the TABLE's own
        // test fired, so every gate below runs on that EDGE gap.
        let d = (geom::dist_in(&state.positions[si], &state.positions[ti])
            - (state.radii[si].first().copied().unwrap_or(DEFAULT_BASE_RADIUS_M)
                + state.radii[ti].first().copied().unwrap_or(DEFAULT_BASE_RADIUS_M))
                / IN2M)
            .max(0.0);
        // NML-1152: the modifier gate is unit-centre to unit-centre
        // (`main.gd:3029`/solo_controller.gd:8525-8533), not this group's
        // EDGE gap — a split group's own weapons can still land Stealth or
        // Versatile Attack on the table's terms even where B11 sees a closer
        // edge.
        let mod_d = geom::centre_dist_in(&state.positions[si], &state.positions[ti]);
        groups.push(SplitGroup { ti, key: key.clone(), d, mod_d, weapons: Some(HashMap::new()) });
    }
    // The member lookup by name: one host plus its own attached heroes, alive
    // only, so the names are unique here exactly as the table's are.
    let member = |name: &str| {
        std::iter::once(&si).chain(state.attached[si].iter()).copied().find(|&mi| {
            state.alive[mi] > 0 && statics[state.roster.profile[mi]].name == name
        })
    };
    // Claim each aim entry's (member, weapon) for ITS group; one member naming
    // one weapon twice (or for two groups) would double-fire it — pooled
    // fallback, named. A pair naming no port weapon is a shot the port cannot
    // build (profile drift): it draws nothing, visible by construction.
    let mut claimed: HashMap<(usize, usize), usize> = HashMap::new();
    for s in list {
        let Some(mi) = member(&s.member) else { continue };
        let Some(pi) = statics[state.roster.profile[mi]].shoot.iter()
            .position(|p| p.name == s.weapon)
        else {
            continue;
        };
        let Some(gi) = groups.iter().position(|g| g.key == s.target) else { continue };
        match claimed.insert((mi, pi), gi) {
            Some(prev) if prev != gi => {
                marks.push("split_weapon_reaimed");
                return (None, marks);
            }
            Some(_) => continue,
            None => {
                if let Some(w) = groups[gi].weapons.as_mut() {
                    w.entry(mi).or_default().push(pi);
                }
            }
        }
    }
    // A port weapon no entry names is a shot the table never fired — dropped,
    // named once.
    let dropped = std::iter::once(si)
        .chain(state.attached[si].iter().copied())
        .filter(|&mi| state.alive[mi] > 0)
        .any(|mi| {
            (0..statics[state.roster.profile[mi]].shoot.len())
                .any(|pi| !claimed.contains_key(&(mi, pi)))
        });
    if dropped {
        marks.push("split_dropped");
    }
    if groups.is_empty() {
        return (None, marks);
    }
    (Some(groups), marks)
}

/// NML-1073 M5 D1-B4 — the SAME played activation with `dice="table"`: the
/// shooting sub-phase draws from `tray` in the table's own order instead of
/// filling an expected-value pool, and reports what it drew. `rng` still runs
/// the rest of the activation (the melee/spell remainders B5 will take over),
/// so the two streams stay exactly as split as the table's are.
///
/// The volley's Shooters over a built `parts` list — the table's build order,
/// each member signing its own dice (main.gd:3199-3200).
fn shooters_of<'a>(
    parts: &'a [(usize, Scratch, Ctx)],
    statics: &'a [UnitStatic],
    state: &State,
) -> Vec<crate::dice::Shooter<'a>> {
    parts
        .iter()
        .map(|(mi, msc, att)| {
            let um = &statics[state.roster.profile[*mi]];
            crate::dice::Shooter {
                profiles: &um.shoot,
                keep: &msc.keep,
                attacks: &msc.attacks,
                att,
                owner: &um.name,
            }
        })
        .collect()
}
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

/// NML-1152 B14 step 1 — the RECORDED Bounding placement's per-activation band
/// bonus: table records the die (`act_recorder.gd`'s `AiActRecorder.traced`,
/// joined onto `Action::traced`), twin replays it here instead of rolling its
/// own (a roll here would desync from the table). 0.0 when the act carries no
/// `bounding_d3` trace — every corpus recorded before this, and every
/// self-play game (no table die to record), so the caller's `band_in` stays
/// byte-identical.
fn bounding_bonus_in(action: &Action) -> f64 {
    action
        .traced
        .as_ref()
        .and_then(|rolls| rolls.iter().find(|t| t.tag == "bounding_d3"))
        .map(|t| t.plus as f64 + t.faces.iter().sum::<i64>() as f64)
        .unwrap_or(0.0)
}

/// Versatile Reach (solo_controller.gd:1781-1827) — the CHARGE half of the
/// per-activation "pick one". The ACTION is the witness: at the table the
/// charge execution (:2213) is reachable with a gap in the unlock ring only if
/// `charge_reach += vr_charge_in` fired at :1819, i.e. only if the table's own
/// EV judge (:1796-1809) chose the charge. A gap inside the plain band means
/// the table took the `elif` (the +4" range half) and the band was NOT bumped.
/// The range half has no consumer in this core — see state.rs:172-176 and
/// sim.rs:727-730 — and is deliberately not ported here.
///
/// `versatile_reach` (`Knobs`/`Seams::versatile_reach`, PR #582 shipped no
/// legacy gate at all): OFF unconditionally returns 0.0, the pre-#582
/// reading — 2.25 % of the Gen-0 corpus was recorded before this rule existed
/// (INVESTIGATION_gen0_replay_drift_2026-09-03.md) and no longer replays
/// byte-identical without this gate.
fn versatile_reach_charge_in(
    statics: &[UnitStatic], state: &State, si: usize, kind: i64,
    ci: Option<usize>, bounding_in: f64, versatile_reach: bool,
) -> f64 {
    if kind != CHARGE || !versatile_reach { return 0.0; }
    let us = &statics[state.roster.profile[si]];
    let (Some(bonus), Some(ti)) = (us.versatile_reach_charge_in, ci) else { return 0.0 };
    if us.melee.is_empty() { return 0.0; } // solo_controller.gd:1791
    let band = state.bands[si].rush + bounding_in; // = the table's `charge_reach`
    let gap = geom::edge_gap_in(
        &state.positions[si], &state.radii[si],
        &state.positions[ti], &state.radii[ti],
        crate::menu::DEFAULT_BASE_RADIUS_M,
    )
    .max(0.0);
    if gap > band && gap <= band + bonus { bonus } else { 0.0 }
}


// ------------------------- S10: destination-side leftovers ------------------

/// S10-a — `AiPlanner.RETREAT_GOAL_IN` ai_planner.gd:11. The retreat
/// candidate's dest sits EXACTLY this far from its mover, which is what makes a
/// recorded kite act recognisable in replay: no other dest on a 6x4' board is
/// 100" from its unit (the diagonal is 86.7").
const RETREAT_GOAL_IN: f64 = 100.0;
/// S10-a — `SoloController.KITE_RANGE_MARGIN_IN` :61 — the kite holds a
/// measuring hair INSIDE range so the post-move shot never flips on floats.
const KITE_RANGE_MARGIN_IN: f64 = 0.25;

/// Rules-must-log: each S10 arm names its rule on stderr when NML_TRACE_RULES=1.
/// Off by default — the fast core stays silent in gates and rollouts.
fn trace_rule(arm: &str, rule: &str, detail: &str) {
    if std::env::var("NML_TRACE_RULES").as_deref() == Ok("1") {
        eprintln!("[{arm}] {rule} — {detail}");
    }
}

/// S10-a/b — rewrite the (dest, band) the plain arm is aimed with, per the
/// table's own body: (a) the in-range shooter's KITE step
/// (solo_controller.gd:2218-2222 via `_move_away` :4761), (b) the goal stop —
/// objective moves are granted min(band, goal_dist) (:2207/:2216) and so end
/// AT the marker instead of spending the band past it. `*hold` = the table
/// moves nothing at all (the kite's zero step).
fn s10_dest_arms(
    statics: &[UnitStatic],
    next: &State,
    si: usize,
    kind: i64,
    dest: [f64; 3],
    band_in: f64,
    hold: &mut bool,
) -> ([f64; 3], f64) {
    let centre = geom::centre(&next.positions[si]);
    // The retreat candidate's dest is exactly 100" out (ai_planner.gd:1077) —
    // no other dest on a 6x4' board (86.7" diagonal) can match that distance.
    let retreat = kind == ADVANCE
        && (geom::length(geom::sub(geom::to_f32(dest), centre)) as f64 - RETREAT_GOAL_IN * IN2M)
            .abs()
            < 1e-3;
    if retreat {
        if let Some(en) = nearest_enemy_reposition(statics, next, si) {
            let ec = geom::centre(&next.positions[en]);
            let enemy_dist = geom::length(geom::sub(centre, ec)) as f64 / IN2M;
            let range = statics[next.roster.profile[si]]
                .shoot
                .iter()
                .map(|w| w.range as f64)
                .fold(0.0_f64, f64::max);
            return s10_kite(next, statics, si, en, centre, ec, enemy_dist, range, band_in, hold);
        }
    }
    s10_goal_stop(next, kind, dest, band_in, centre)
}

/// S10-a — the kite: move AWAY from the target, at most
/// min(band, range - dist - 0.25) (`_move_away` solo_controller.gd:4761); a
/// floored step moves nothing (`is_zero_approx`, :4762) -> *hold.
#[allow(clippy::too_many_arguments)]
fn s10_kite(
    next: &State,
    statics: &[UnitStatic],
    si: usize,
    en: usize,
    centre: V3,
    ec: V3,
    enemy_dist: f64,
    range: f64,
    band_in: f64,
    hold: &mut bool,
) -> ([f64; 3], f64) {
    let goal = geom::to_f64(geom::add(centre, geom::sub(centre, ec)));
    let step = (range - enemy_dist - KITE_RANGE_MARGIN_IN).max(0.0).min(band_in);
    *hold = step <= 0.0;
    trace_rule(
        "S10-a",
        "in-range shooter kites back toward the range edge (p.58)",
        &format!(
            "{} steps {:.2}\" from {}",
            statics[next.roster.profile[si]].name,
            if *hold { 0.0 } else { step },
            statics[next.roster.profile[en]].name
        ),
    );
    (goal, if *hold { 0.0 } else { step })
}

/// S10-b — the goal stop: objective moves are granted min(band, goal_dist)
/// (solo_controller.gd:2207/:2216) and end AT the marker — the distance-truth
/// trim and the p.11 re-plan budget both read the granted reach. A dest that
/// is not a marker keeps the full band.
fn s10_goal_stop(
    next: &State,
    kind: i64,
    dest: [f64; 3],
    band_in: f64,
    centre: V3,
) -> ([f64; 3], f64) {
    if !matches!(kind, ADVANCE | RUSH) {
        return (dest, band_in);
    }
    for o in &next.objectives {
        if (o.pos[0] - dest[0]).abs() < 1e-6
            && (o.pos[1] - dest[1]).abs() < 1e-6
            && (o.pos[2] - dest[2]).abs() < 1e-6
        {
            let goal_dist = geom::length(geom::sub(geom::to_f32(dest), centre)) as f64 / IN2M;
            if goal_dist < band_in {
                trace_rule(
                    "S10-b",
                    "objective move stops at the goal (p.57 band)",
                    &format!("band {:.2}\" -> {:.2}\"", band_in, goal_dist),
                );
                return (dest, goal_dist);
            }
            break;
        }
    }
    (dest, band_in)
}

/// GF v3.5.1 p.9: the survivor's consolidation band.
const CONSOLIDATE_WIN_IN: f64 = 3.0;

/// The winner consolidation's goal — `SoloController.
/// consolidate_after_melee_win` solo_controller.gd:4607-4628: the nearest
/// objective the winner's own side does not already control, else the
/// nearest living enemy. `None` (no goal at all) is the honest "may": the
/// table stays put too.
fn consolidation_goal(next: &State, winner: usize) -> Option<V3> {
    let centre = geom::centre(&next.positions[winner]);
    let pid = next.player[winner];
    let mut best: Option<(f32, V3)> = None;
    for o in &next.objectives {
        if o.owner == pid {
            continue;
        }
        let pos = geom::to_f32(o.pos);
        let d = geom::length(geom::sub(pos, centre));
        if best.is_none_or(|(bd, _)| d < bd) {
            best = Some((d, pos));
        }
    }
    best.map(|(_, pos)| pos).or_else(|| {
        nearest_enemy_of(next, winner).map(|e| geom::centre(&next.positions[e]))
    })
}

/// Consolidation Moves (GF v3.5.1 p.9), seam-gated by `consolidate`. Only the
/// "one side destroyed" half is ported: the survivor may move up to 3" via
/// the SAME routed chain `plain_move` gives ADVANCE/RUSH. Neither destroyed
/// (or a mutual wipe) is not this port's rung — no rule fires, no move, and
/// `consolidate="off"` (default) never reaches this function at all.
fn consolidate_after_melee(next: &mut State, cover: Cover, seams: Seams, si: usize, ti: usize) {
    let winner = if next.alive[ti] <= 0 && next.alive[si] > 0 {
        si
    } else if next.alive[si] <= 0 && next.alive[ti] > 0 {
        ti
    } else {
        return;
    };
    let Cover::Board(t) = cover else { return };
    let Some(goal) = consolidation_goal(next, winner) else { return };
    if let Some(land) = crate::mv::step::plain_move(
        next,
        t,
        winner,
        goal,
        CONSOLIDATE_WIN_IN,
        seams.hero_attach,
        true,
        crate::mv::FAST_PLANNER_GUARD,
    ) {
        for (i, m) in land.movers.iter().enumerate() {
            next.positions[m.unit][m.model] = geom::to_f64(land.end[i]);
        }
    }
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
    // NML-1157: a charge NAMED at a joined hero fights its HOST — see
    // `combat_unit`. Off by default, so a recorded act resolves where it always
    // resolved. It rides here rather than at the melee branch because `ci` is
    // also the spacing clamp's body-only group (`spacing_fraction`), and GF
    // v3.5.1 p.7 exempts the enemy UNIT, which p.14 says includes its hero.
    let ci = if charge_key.is_empty() {
        None
    } else {
        state
            .roster
            .index
            .get(charge_key.as_str())
            .copied()
            .map(|c| combat_unit(state, c, seams))
    };
    let pi_s = state.roster.profile[si];
    let mut next = state.clone();
    let was_shaken = next.shaken[si];
    let mut sc = Scratch::default();

    // --- move (battle_sim.gd:575-596) ---
    // `SoloController.sim_move_bands(su["unit"])` is a pure read of the unit's
    // rules (bands + the Musician bonus, solo_controller.gd:4966-4982), flattened
    // into the profile table at capture; RUSH and CHARGE share the rush band.
    let bounding_in = bounding_bonus_in(action);
    // Versatile Reach — the witness policy evaluated at the resolve seam, the
    // same seam Bounding rides (`sim::versatile_reach_charge_in`). CLASS FIX
    // (external review 03.09. item 3 / F9, `acts::rule_on`): a pre-epoch
    // record with the boolean legacy-OFF (or absent) stays unaffected;
    // `rules_epoch >= 1` turns this rule on regardless of the boolean.
    let vr_in = versatile_reach_charge_in(
        statics, &next, si, kind, ci, bounding_in,
        seams.versatile_reach || rule_on(seams.rules_epoch, 1),
    );
    let band_in = match kind {
        ADVANCE => next.bands[si].advance,
        RUSH | CHARGE => next.bands[si].rush,
        _ => 0.0,
    } + bounding_in
        + vr_in;
    // NML-1152 B14 step 1 — rules-must-log: the ONLY table die this port does
    // not draw itself, named here (dice.rs's `ShootResult.log` precedent) the
    // one time it changes the band.
    if bounding_in != 0.0 {
        if let Some((_, shot)) = dice.as_mut() {
            shot.log.push(format!(
                "Bounding: {} — +{bounding_in:.0}\" every move band this activation",
                statics[pi_s].name
            ));
        }
    }
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
    // S10-a: a kite whose cap floors at zero moves NOTHING on the table (the
    // `_move_away` is_zero_approx guard) — neither the plain arm nor rigid.
    let mut hold = false;
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
    // D5-3, seam-gated: every NON-charge move with a destination goes through
    // the SAME ported chain. `_move_toward` :4575 -> `_execute_move` :4784 is
    // what the table runs for ADVANCE and RUSH too — routed around difficult
    // and dangerous terrain, capped by p.11, solved per model — where the rigid
    // block below walks one straight delta through walls and forests and then
    // trims it by `spacing_fraction`. It runs BEFORE that block and, when it
    // answers, replaces it whole: `plain_move` has already spent the band and
    // placed every model, so both clamps would be measuring a move that is no
    // longer a translation. `--red-move-rigid` (`move_rigid`) forces the old
    // arm back for the gate's RED. `None` = the port declines and the rigid
    // translation still stands.
    if seams.movement && !seams.move_rigid && kind != CHARGE && band_in > 0.0 {
        if let (Cover::Board(t), Some(dest)) = (cover, action.dest) {
            let (dest, band) =
                s10_dest_arms(statics, &next, si, kind, dest, band_in, &mut hold);
            if !hold {
                landing = crate::mv::step::plain_move(
                    &next,
                    t,
                    si,
                    geom::to_f32(dest),
                    band,
                    seams.hero_attach,
                    true,
                    crate::mv::FAST_PLANNER_GUARD,
                );
            }
        }
    }
    if let Some(land) = landing.as_ref() {
        moved = true;
        for (i, m) in land.movers.iter().enumerate() {
            next.positions[m.unit][m.model] = geom::to_f64(land.end[i]);
        }
        // D5-2 review fix: the table's own arc only feeds the D5-1 budget
        // gate when `charge_landing` asks for it — otherwise `movement=
        // "table"` silently forces `charge_landing="table"` on, and the
        // engage snap gate refuses charges D5-1-off never refused.
        if seams.charge_landing {
            charge_remaining_in = land.remaining_in();
        }
        // battle_sim.gd:598-600 — the mover's cover follows it, probed at the
        // POST-move unit centre, which is now the solved formation's centre.
        if let Cover::Board(t) = cover {
            if t.is_valid() {
                next.in_cover[si] = gives_cover(t.type_at(geom::centre(&next.positions[si])));
            }
        }
    } else if band_in > 0.0
        && !hold
        && action.dest.is_some()
        && !next.positions[si].is_empty()
    {
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
    // --- DANGEROUS TERRAIN (main.gd:1039-1047 -> `_run_ai_dangerous` :7026) ---
    // The table rolls this after EVERY executed move — advance, rush and charge
    // alike — and BEFORE the casts, the buffs and any melee, so it is also the
    // first thing the activation puts on the tray. Six is the tray's success
    // TARGET (:7030) but a **1** is what wounds (:7033): the recorded roll is
    // `attack`, `count` dice, `6`, signed by the moving unit.
    // `dangerous_morale_due` carries the pre-wound (alive, wounds) snapshot past
    // the cast/shoot/melee/hit-and-run tail below, to where main.gd:1092-1098
    // actually rolls the END-of-activation test — not here.
    let mut dangerous_morale_due: Option<(i64, i64)> = None;
    if moved && !seams.no_dangerous {
        if let Some((tray, shot)) = dice.as_mut() {
            let n = dangerous_dice(statics, state, &next, si, seams, landing.as_ref(), cover, shot);
            if n > 0 {
                let faces = tray.roll(n as usize);
                let w = dangerous_wounds(&faces);
                shot.rolls.push(crate::dice::Roll {
                    kind: "attack",
                    count: n,
                    target: DANGEROUS_TARGET,
                    faces,
                    owner: statics[pi_s].name.clone(),
                });
                if w > 0 {
                    // main.gd:1042-1043 — the snapshot for that later test, taken
                    // BEFORE these wounds land.
                    let alive_before = next.alive[si];
                    let wounds_before = wounds_left(&next, si);
                    land_wounds(&mut next, si, w);
                    // main.gd:1096-1098 — a NON-charge activation tests morale for
                    // these wounds at its very END ("units in melee don't take
                    // morale tests from wounds at the end of an activation").
                    // Knob-gated (DEFECT_LEDGER #12): OFF replays a corpus
                    // recorded before this rule unchanged.
                    if kind != CHARGE && seams.dangerous_end_morale {
                        shot.mark("dangerous_end_morale");
                        dangerous_morale_due = Some((alive_before, wounds_before));
                    }
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
        cast_phase(statics, &mut next, si, &row, seams, rng.as_deref_mut());
    }

    // --- MEND (main.gd:1056-1058), the pre-attack slot — every action kind,
    // tray path only. See `tray_mend`; no bearer, no patient, no draw.
    if let Some((tray, shot)) = dice.as_mut() {
        tray_mend(statics, &mut next, si, seams, tray, shot);
    }

    // --- BREATH ATTACK (main.gd:1059), right after Mend in the table's own
    // pre-attack slot order — every action kind, tray path only. See
    // `tray_breath_attack`; no bearer, no target, no draw.
    if let Some((tray, shot)) = dice.as_mut() {
        tray_breath_attack(statics, &mut next, si, seams, tray, shot);
    }

    // --- Utility Buff / Re-Position Artillery (main.gd:1062, right after
    // Mend + Breath Attack), tray path only — see `tray_utility_buff`.
    // Dice-free: no tray draw either way.
    if dice.is_some() {
        tray_utility_buff(statics, &mut next, si, seams, cover);
    }

    // --- GROWTH MARKERS (main.gd:16984), the per-round tick lazily anchored
    // to this unit's own next activation — tray path only. See
    // `growth_round_start`; dice-free, `was_shaken` is the round-start
    // reading (captured before this activation's own moves/tests run it).
    if dice.is_some() {
        growth_round_start(statics, &mut next, si, was_shaken);
    }

    // --- shoot (battle_sim.gd:608-630); HOLD and ADVANCE only, plus RUSH for
    // a Quick Shot carrier (block B11, solo_controller.gd:1846/:2257/:4033 —
    // "may shoot after using Rush actions": its move-and-shoot band becomes
    // its RUSH distance). The `moved` decline right below still applies to a
    // Quick Shot RUSH exactly as it already does to a moved ADVANCE.
    let quick_shot_active =
        statics[pi_s].quick_shot_active || mods::granted(&next, si, "Quick Shot");
    if !shoot_key.is_empty() && (kind == HOLD || kind == ADVANCE || (kind == RUSH && quick_shot_active)) {
        // W1: the decline stands unless the caller has asked for the moving
        // shot, which is the other half of `Knobs::menu_wide` — the menu may
        // now offer ADVANCE+shoot, so the resolve has to be able to answer it.
        if moved && !seams.moved_shoot {
            return Err(Unsupported::MovedShootLos);
        }
        // NML-1157: a volley NAMED at a joined hero hits its HOST — the same
        // `combat_unit` redirect the charge takes above. `shoot_key` itself is
        // left alone: it is the recorded act's own field and `sees`/`los_clear`
        // are the table's per-KEY reads.
        let named = next.roster.index.get(shoot_key.as_str()).copied();
        if let Some(ti) = named.map(|t| combat_unit(&next, t, seams)) {
            // NML-1150: the split plan is decided BEFORE the recorded target's
            // gate — a split act may aim at units the recorded key does not
            // name, and then validity is gated PER GROUP below (main.gd
            // :2963-2984). The EV half keeps the one-target gate.
            let (plan, split_marks) = match dice.as_mut() {
                Some(_) => split_plan(action.split.as_ref(), statics, &next, si, &shoot_key),
                None => (None, Vec::new()),
            };
            // W1: a MOVED shooter's sight is not in the recorded rows — `sees`
            // and `los_clear` both answer for the PRE-move centre. With the
            // board in hand it is a question the terrain answers directly, and
            // from the same source `tools/core_selfplay.gd:675` builds
            // `los_pairs` from (`menu::safe_advance` already probes it that
            // way). Without a board the rows are all there is, and only a state
            // that stamps no sight seam at all can still be trusted: both reads
            // are then `true` for every pair, wherever the unit stands.
            let sighted = if moved {
                match cover {
                    Cover::Board(t) if t.is_valid() => !t.los_blocked(
                        geom::centre(&next.positions[si]),
                        geom::centre(&next.positions[ti]),
                    ),
                    _ => next.los[si].is_none() && next.los_pairs.is_none(),
                }
            } else {
                next.sees(si, &shoot_key) && los_clear(&next, si, ti)
            };
            if plan.is_some() || sighted {
                let d = geom::dist_in(&next.positions[si], &next.positions[ti]);
                // NML-1152: the pooled plan's own modifier distance — unit
                // centre to unit centre (main.gd:3029) — kept apart from `d`
                // for the SAME reason the split groups above are (below,
                // :2453-2460's `pooled` literal).
                let mod_d = geom::centre_dist_in(&next.positions[si], &next.positions[ti]);
                // NML-1132: the EXPECTED-VALUE half measures over the table's folded
                // model set (`fold_dist_in`); the TRAY half below keeps the plain
                // host-to-host `d`, because it already measures per FIRING MEMBER
                // (`sighted_profiles_of`, `main._solo_sighted_count` :4103) and a
                // folded reach there would let a host weapon fire from a hero's model.
                let d_ev = if seams.hero_attach { fold_dist_in(&next, si, ti, seams) } else { d };
                let alive_before = next.alive[ti];
                let wounds_before = wounds_left(&next, ti);
                // Seam ON: a plain volley — the cast sub-phase above already
                // ran. Seam OFF: the LEGACY spell rider (battle_sim.gd:621-628),
                // where the spell's EV joins the volley and the caster pays for
                // it inside the shoot pick.
                // NML-1157: the rider's caster is the CHAIN's, not the host's —
                // see `caster_of`. With `cast_fold` off this is `Some(si)` under
                // exactly the conditions `spell_ev_of` already tested, or `None`
                // where it already returned `(0.0, 0)`.
                let caster = caster_of(statics, &next, si, seams);
                let (volley, sp_cost) = {
                    let us = &statics[pi_s];
                    let ut = &statics[next.roster.profile[ti]];
                    member_profiles_of(statics, &next, si, false, d_ev, seams, &mut sc);
                    let att = ctx_of(us, &next, si);
                    let def = ctx_of(ut, &next, ti);
                    let shooting = shoot_ev(
                        folded_slice(&us.shoot, &sc), &sc.keep, &sc.attacks, &att, &def, d_ev,
                    );
                    if seams.cast {
                        (shooting, 0)
                    } else {
                        let (sp_ev, sp_cost) = match caster {
                            Some(ci) => {
                                let cs = &statics[next.roster.profile[ci]];
                                spell_ev_of(true, &cs.spells, next.casts[ci], &def, d_ev)
                            }
                            None => (0.0, 0),
                        };
                        if sp_ev > 0.0 {
                            (shooting + sp_ev, sp_cost)
                        } else {
                            (shooting, 0)
                        }
                    }
                };
                if let Some(ci) = caster {
                    next.casts[ci] -= sp_cost; // 0 unless the spell rider fired
                }
                match dice.as_mut() {
                    Some((tray, shot)) => {
                        // Block B11, rules-must-log: names the otherwise-
                        // impossible shot (solo_controller.gd:2260-2261's own
                        // "shoots after its Rush action" note).
                        if kind == RUSH && quick_shot_active {
                            shot.log.push(format!(
                                "Quick Shot: {} shoots after its Rush action",
                                statics[pi_s].name
                            ));
                        }
                        for m in split_marks {
                            shot.mark(m);
                        }
                        // D6a-B4: with `sighting="model"` the die count is the
                        // table's own, per member and per WEAPON — the board's
                        // sight volumes are built once for the whole volley.
                        let zones = match (seams.sighting, cover) {
                            (true, Cover::Board(t)) => sight::zones_of(t),
                            _ => Vec::new(),
                        };
                        // D1-B4: the table's dice, in the table's draw order —
                        // ONE tray volley per target group, in the table's
                        // group order, on the SAME tray. The pooled plan is the
                        // act's one recorded target with every weapon (the
                        // pre-1150 path, byte-identical); a split plan comes
                        // from the act's `split` aim (NML-1150, main.gd
                        // :2963-2984, one `_solo_resolve_ai_volley` per group).
                        //
                        // NO sees/los gate on a split group: it exists because
                        // the table fired it — the table's own per-target
                        // validity check (main.gd:4011-4029, Indirect waiving
                        // LOS included) already ran at record time, and the
                        // port's los_pairs matrix is the PLANNER's strict test,
                        // which would reject exactly those legal indirect
                        // shots. B11 (main.gd:4098-4104) instead gates split
                        // groups on the base-EDGE gap — both base radii off
                        // every pair distance; the pooled plan keeps its
                        // corpus-anchored centre-space gate.
                        let pooled = [SplitGroup {
                            ti,
                            key: shoot_key.clone(),
                            d,
                            mod_d,
                            weapons: None,
                        }];
                        let gs: &[SplitGroup] = plan.as_deref().unwrap_or(&pooled);
                        for g in gs {
                            // main.gd:3042 — the Mark is picked and recorded
                            // BEFORE this group's profiles and contexts are
                            // read (:3082), so the grant reaches this volley.
                            tray_vs_marks(statics, &mut next, si, g.ti, g.d, seams);
                            let ut_g = &statics[next.roster.profile[g.ti]];
                            let def = ctx_live(ctx_of(ut_g, &next, g.ti), statics, &next, g.ti, false);
                            let alive_before_g = next.alive[g.ti];
                            let wounds_before_g = wounds_left(&next, g.ti);
                            let mut parts: Vec<(usize, Scratch, Ctx)> = Vec::new();
                            for &mi in std::iter::once(&si).chain(next.attached[si].iter()) {
                                if next.alive[mi] <= 0 {
                                    continue;
                                }
                                let um = &statics[next.roster.profile[mi]];
                                let mut msc = Scratch::default();
                                if seams.sighting {
                                    sighted_profiles_of(
                                        um, &next, statics, mi, g.ti, &zones, g.d, &mut msc,
                                    );
                                } else {
                                    profiles_of(um, next.alive[mi], g.d, &mut msc);
                                }
                                drop_spent_limited(&um.shoot, &next.limited_used[mi], &mut msc);
                                if let Some(aims) = &g.weapons {
                                    // The table gates and scales per TARGET
                                    // (main.gd:3088-3095); a member the group
                                    // does not aim brings no shot, a member it
                                    // aims keeps only ITS OWN weapon indices,
                                    // index-parallel throughout.
                                    let Some(want) = aims.get(&mi) else { continue };
                                    let (keep, attacks): (Vec<usize>, Vec<i64>) = msc
                                        .keep
                                        .iter()
                                        .zip(msc.attacks.iter())
                                        .filter(|(pi, _)| want.contains(pi))
                                        .map(|(&pi, &n)| (pi, n))
                                        .unzip();
                                    msc.keep = keep;
                                    msc.attacks = attacks;
                                }
                                parts.push((
                                    mi,
                                    msc,
                                    ctx_live_vs(ctx_of(um, &next, mi), statics, &next, mi, g.ti, false),
                                ));
                            }
                            // Block C5 — Instinctive: the +1 reaches the
                            // shooting fold ONLY when THIS group's target is
                            // the closest enemy (main.gd:5745-5748), per
                            // member carrying it.
                            for (mi, _, att) in parts.iter_mut() {
                                if att.instinctive_hit_bonus > 0
                                    && instinctive_applies(&next, *mi, g.ti)
                                {
                                    att.hit_mod += att.instinctive_hit_bonus;
                                }
                            }
                            // CLASS FIX (external review 03.09. item 3 / F9,
                            // `acts::rule_on`) — same gate as `strike_phase`'s
                            // melee half above.
                            let r = crate::dice::resolve_volley_with_tray(
                                &shooters_of(&parts, statics, &next),
                                &def, &ut_g.name, g.d, g.mod_d,
                                seams.cond_ap_dice || rule_on(seams.rules_epoch, 1),
                                // Surge's own gates: the CLASS FIX
                                // (`acts::rule_on`), same seam as `cond_ap_dice`.
                                rule_on(seams.rules_epoch, CURRENT_RULES_EPOCH),
                                // The Shred-family alias gate — the same epoch.
                                rule_on(seams.rules_epoch, CURRENT_RULES_EPOCH),
                                tray,
                            );
                            for (mi, msc, _) in &parts {
                                let shoot = &statics[next.roster.profile[*mi]].shoot;
                                mark_spent_limited(shoot, &msc.keep, &mut next.limited_used[*mi]);
                            }
                            // D1-B5a: `absorb`, not `=` — a CHARGE activation
                            // puts several sub-phases into ONE report, and the
                            // replay gate compares the whole activation roll by
                            // roll.
                            let w = shot.absorb(r);
                            land_wounds(&mut next, g.ti, w);
                            // Coverage wave — growth markers (Precision
                            // Frenzy): main.gd:3228/9934 credit the shooter's
                            // own kill marker when this volley just fully
                            // destroyed its target.
                            if alive_before_g > 0 && next.alive[g.ti] <= 0 {
                                growth_on_kill(statics, &mut next, si);
                            }
                            // main.gd:3244 — the exchange spends its own
                            // once-mods BEFORE the post-volley morale test.
                            spend_exchange(&mut next, si, g.ti, false);
                            // D1-B5b: the volley's morale test is the NEXT
                            // thing on the table's tray (main.gd:8248-8251),
                            // per group — inside the per-group
                            // `_solo_resolve_ai_volley` (:3249-3255). Leaving
                            // it undrawn is what put every later activation of
                            // a `dice="table"` game on a different stream than
                            // the recording.
                            if shooting_morale_trigger(
                                &next, ut_g, g.ti, alive_before_g, wounds_before_g,
                            ) {
                                tray_morale(&mut next, ut_g, g.ti, false, tray, shot);
                            }
                        }
                    }
                    None => {
                        apply_expected_wounds(&mut next, ti, volley, rng.as_deref_mut());
                        let ut = &statics[next.roster.profile[ti]];
                        if shooting_morale_trigger(&next, ut, ti, alive_before, wounds_before)
                            && morale_fails_expected(&next, ut, ti)
                        {
                            next.shaken[ti] = true;
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
            // D5-4: over `_moving_models` on BOTH sides once `hero_attach`
            // is on — the table's own list, not the two hosts'.
            let engage_gap_in = engage_gap_in(&next, si, ti, seams);
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
                // loser's morale test began as the expected-value outcome the EV
                // path gives; D1-B5b now draws it as a REAL die right below
                // (`tray_morale`) — no morale draw is left standing, verified by
                // replay.
                if let Some((tray, shot)) = dice.as_mut() {
                    if let Some(li) = tray_charge(statics, &mut next, si, ti, seams, tray, shot) {
                        // D1-B5b: the melee loser's test is a REAL die now
                        // (:8116-8118), where D1-B5a still asked the
                        // expected-value oracle for the outcome.
                        let ul = &statics[next.roster.profile[li]];
                        tray_morale(&mut next, ul, li, true, tray, shot);
                    }
                    // Coverage wave — growth markers (Defensive Frenzy):
                    // main.gd:8137-8140 credits the WIPING side's own kill
                    // marker, win-by-wipe only — a mutual wipe or a fight
                    // that leaves both sides standing earns nothing.
                    if next.alive[ti] <= 0 && next.alive[si] > 0 {
                        growth_on_kill(statics, &mut next, si);
                    } else if next.alive[si] <= 0 && next.alive[ti] > 0 {
                        growth_on_kill(statics, &mut next, ti);
                    }
                } else {
                    // The charger strikes: charging profiles, its OWN fatigue state
                    // (still the pre-charge one), the defender's plain context.
                    let ev = {
                        let us = &statics[pi_s];
                        let ut = &statics[next.roster.profile[ti]];
                        let att = ctx_of_melee(us, &next, si);
                        let def = ctx_of(ut, &next, ti);
                        // NML-1132: the charger's strike phase is the host's melee set
                        // PLUS every alive attached hero's, the way the table builds it.
                        member_profiles_of(statics, &next, si, true, 0.0, seams, &mut sc);
                        melee_ev(folded_slice(&us.melee, &sc), &sc.attacks, &att, &def, true)
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
                            // The strike-back folds too (`_solo_attack_groups` is built
                            // for the DEFENDER the same way, main.gd:4284-4290).
                            member_profiles_of(statics, &next, ti, true, 0.0, seams, &mut sc);
                            melee_ev(folded_slice(&ut.melee, &sc), &sc.attacks, &att, &def, false)
                        };
                        apply_expected_wounds(&mut next, si, ev_back, rng.as_deref_mut());
                        next.fatigued[ti] = true;
                    }
                    expected_melee_morale(&mut next, statics, si, su_before, ti, tu_before);
                }
                // Consolidation Moves (GF v3.5.1 p.9), seam-gated: one side
                // wiped by the melee just resolved above (wounds or the
                // morale rout), win or EV path alike — the survivor may move.
                if seams.consolidate {
                    consolidate_after_melee(&mut next, cover, seams, si, ti);
                }
            }
        }
    }

    // --- HIT & RUN (main.gd:1075-1089), the once-per-round post-attack free
    // move, tray path only. `hnr_attacked` mirrors main.gd's own local var
    // exactly: computed from the DECIDED action, before it is known whether
    // the melee actually connected — a declared CHARGE that fell short of
    // MELEE_ENGAGE_IN still counts (main.gd never resets `report["action"]`
    // on the early-return "falls short" branches of `_run_ai_melee`), so this
    // port fires on `kind == CHARGE` alone, not on a landed fight. See
    // `tray_hit_and_run`.
    if dice.is_some() {
        // BLOCK C1 — `after_shoot` is the table's own shoot leg (main.gd:
        // 1083-1089): the SAME two terms that build `hnr_attacked`, with the
        // melee leg (kind == CHARGE) leaving it false. No third condition.
        let shot_leg = !shoot_key.is_empty()
            && (kind == HOLD || kind == ADVANCE || (kind == RUSH && quick_shot_active));
        let hnr_attacked = shot_leg || kind == CHARGE;
        if hnr_attacked && tray_hit_and_run(statics, &mut next, si, seams, cover, shot_leg) {
            // The table's own battle-log line, main.gd:1089 — the rules-must-
            // log twin of `record_decision`'s "hit-and-run" entry.
            let (_, shot) = dice.as_mut().unwrap();
            shot.log.push(format!(
                "Hit & Run: {} steps up to 3\" after its attack",
                statics[next.roster.profile[si]].name
            ));
        }
    }

    // --- DANGEROUS-TERRAIN END MORALE (main.gd:1092-1098, GF v3.5.1 p.10
    // General Morale Tests) --- the test for the wounds landed by the
    // DANGEROUS TERRAIN block above, held back until now so the wounds never
    // stopped this activation's own cast/shoot/melee/hit-and-run. Single-model
    // vs multi-model and the alive-count trigger are the exact same
    // `shooting_morale_trigger` the volley morale test above already uses; a
    // failure here is always Shaken, never a Rout (Rout exists only in melee).
    if let Some((alive_before, wounds_before)) = dangerous_morale_due {
        if next.alive[si] > 0 {
            if let Some((tray, shot)) = dice.as_mut() {
                let us = &statics[pi_s];
                if shooting_morale_trigger(&next, us, si, alive_before, wounds_before) {
                    tray_morale(&mut next, us, si, false, tray, shot);
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
    // Block B8 — Second Wind: only once NEITHER side has a unit left that can
    // still activate (the round would otherwise close now); see
    // `second_wind_candidate`'s own doc comment for the "acting side" and
    // "arena-driver-unreachable" caveats.
    let round_open = (0..next.units()).any(|i| next.can_activate(i, next.player[i], seams.hero_attach));
    if !round_open {
        if let Some(bi) = second_wind_candidate(statics, &next, next.player[si]) {
            spend_second_wind(&mut next, bi);
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
        refresh_los_pairs(&mut next, state, terrain, seams);
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
fn refresh_los_pairs(next: &mut State, parent: &State, terrain: &Terrain, seams: Seams) {
    // NML-1160: under `los_model` the matrix is the table's PER-MODEL sight,
    // which the caller re-stamps between two played activations exactly as
    // `BattleSim.capture` re-runs `_has_los`. A clone inherits it untouched
    // there (`clone_state` copies `su["los"]`, battle_sim.gd:1644-1651), so
    // rewriting a moved row here with the centre probe would swap the answer
    // back to the coarse one halfway through a search.
    if seams.los_model {
        return;
    }
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::{Bands, Mods, MoveBands, Profile, Profiles, Roster};
    use std::collections::HashMap;

    /// Four 1"-radius single-model units on one line: a charger host (unit 0)
    /// with a joined hero (unit 1) two inches in front of it, and a target host
    /// (unit 2) with a joined hero (unit 3) three inches in front of IT. The
    /// four base-edge gaps the engage test can pick from are therefore
    /// 10" (host to host), 8" and 7" (one hero folded) and 5" (both) — one
    /// number per fold, so a single assertion says which lists were measured.
    pub(super) fn four_unit_line() -> State {
        let profile = Profile {
            unit_id: "u".into(),
            name: "u".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![],
            model_count: 1,
            weapons: vec![],
            special_rules: vec![],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: String::new(),
            faction_folder: String::new(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let xs = [0.0, 2.0, 12.0, 9.0];
        State {
            roster: Rc::new(Roster {
                keys: vec!["a".into(), "ah".into(), "b".into(), "bh".into()],
                index: HashMap::new(),
                profile: vec![0, 0, 0, 0],
            }),
            profiles: Rc::new(Profiles { list: vec![profile], index: HashMap::new() }),
            round: 0,
            rounds_total: 1,
            scoring: Rc::from(""),
            objectives: vec![],
            markers_meta: vec![],
            destroy_seq: vec![],
            vp: None,
            vp_flavour: None,
            vp_memo: None,
            cast_events: vec![],
            player: vec![0, 0, 1, 1],
            alive: vec![1; 4],
            activated: vec![false; 4],
            shaken: vec![false; 4],
            fatigued: vec![false; 4],
            in_cover: vec![false; 4],
            aircraft: vec![false; 4],
            dormant: vec![false; 4],
            dormant_models: vec![0; 4],
            dormant_wounds: vec![Vec::new(); 4],
            casts: vec![0; 4],
            morale_bonus: vec![0; 4],
            ambush_arrived_round: vec![-1; 4],
            earliest_arrival_round: vec![-1; 4],
            wound_frac: vec![1.0; 4],
            positions: xs.iter().map(|x| vec![[x * IN2M, 0.0, 0.0]]).collect(),
            wounds: vec![vec![1]; 4],
            radii: vec![vec![IN2M]; 4],
            mods: vec![Mods::default(); 4],
            mods_base: (0..4).map(|_| Rc::new(Mods::default())).collect(),
            attached: Rc::new(vec![vec![1], vec![], vec![3], vec![]]),
            attached_to: Rc::new(vec![None, Some(0), None, Some(2)]),
            los: vec![None, None, None, None],
            los_pairs: None,
            bands: vec![Bands::default(); 4],
            shroud: vec![None; 4],
            charge_no_difficult: vec![false; 4],
            charge_probe_r: vec![0.0; 4],
            buffs: vec![Vec::new(); 4],
            vs_mark_round: vec![-1; 4],
            hit_and_run_round: vec![-1; 4],
            growth_markers: vec![0; 4],
            growth_round: vec![-1; 4],
            second_wind_used: vec![false; 4],
            second_wind_round: -1,
            second_wind_uses: 0,
            limited_used: vec![Vec::new(); 4],
        }
    }

    /// Fear(X) (GF/AoF v3.5.1): "counts as having dealt +X wounds when
    /// checking who won melee." Unit 0 (host, Fear(2)) deals 1 wound and
    /// takes 2 from unit 2 (host, no Fear) — raw tallies say unit 0 loses
    /// (1 < 2), but 1+2 > 2 means Fear(2) should flip the result. Both units'
    /// quality is set to fail morale for certain, so `alive == 0` after the
    /// call marks exactly which side was made to test — and lose.
    #[test]
    fn fear_x_lifts_its_own_side_s_tally_in_the_ev_melee_comparison() {
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: st.roster.keys.clone(),
            index: HashMap::new(),
            profile: vec![0, 0, 1, 0],
        });
        st.wounds[0] = vec![8]; // su_before(10) - 8 = 2 dealt BY the target
        st.wounds[2] = vec![9]; // tu_before(10) - 9 = 1 dealt BY the Fear unit
        let statics = vec![
            UnitStatic { ctx: Ctx { fear: 2, ..Ctx::default() }, quality: 6, ..UnitStatic::default() },
            UnitStatic { quality: 6, ..UnitStatic::default() },
        ];
        expected_melee_morale(&mut st, &statics, 0, 10, 2, 10);
        assert_eq!(st.alive[0], 1, "the Fear(2) unit dealt 1+2=3 > 2, it must not test morale");
        assert_eq!(st.alive[2], 0, "the plain unit lost the comparison and must rout");
    }

    /// D5-4. `nearest_melee_gap_in` (:8526) measures `_moving_models` on BOTH
    /// sides, so the joined heroes' bases are the ones that decide this charge:
    /// 5", not the hosts' 10". Folding only one side would read 8" or 7", which
    /// is why the assertion is on the exact number and not on "smaller".
    #[test]
    fn the_engage_test_measures_from_a_joined_heros_base_on_both_sides() {
        let st = four_unit_line();
        let on = Seams { hero_attach: true, ..Seams::default() };
        assert!((engage_gap_in(&st, 0, 2, on) - 5.0).abs() < 1e-6);
    }

    /// The seam OFF is the D5-1 reading, hosts alone — the identity that keeps
    /// every recorded corpus replaying. The RED knob (`engage_fold=false` in the
    /// header) has to return exactly that number while `hero_attach` stays on,
    /// or it is not a red for this rung but for the whole seam.
    #[test]
    fn the_hosts_alone_answer_with_the_seam_off_and_under_the_red_knob() {
        let st = four_unit_line();
        let off = Seams::default();
        let red = Seams { hero_attach: true, no_engage_fold: true, ..Seams::default() };
        assert!((engage_gap_in(&st, 0, 2, off) - 10.0).abs() < 1e-6);
        assert_eq!(engage_gap_in(&st, 0, 2, red), engage_gap_in(&st, 0, 2, off));
    }

    /// D5-2b — the target is a 92 x 120 mm OVAL whose recorded (circumscribing)
    /// radius is still 1". Across its short axis the table measures 0.6084" of
    /// base, not 1", so the engage gap opens from 10" to 10.3916" — but ONLY
    /// while the resolver is imitating the live table. With both charge seams
    /// off it is imitating `BattleSim`, whose own `edge_gap_in`
    /// (battle_sim.gd:869) knows nothing but the radius, and the answer must
    /// stay the D5-1 number to the digit.
    #[test]
    fn an_oval_target_is_measured_by_its_support_extent_under_the_charge_seams() {
        let mut st = four_unit_line();
        let mut oval = st.profiles.list[0].clone();
        oval.base_shape = "oval".into();
        oval.base_w_mm = 92.0;
        oval.base_d_mm = 120.0;
        st.profiles = Rc::new(Profiles {
            list: vec![st.profiles.list[0].clone(), oval],
            index: HashMap::new(),
        });
        st.roster = Rc::new(Roster {
            keys: st.roster.keys.clone(),
            index: HashMap::new(),
            profile: vec![0, 0, 1, 0],
        });
        let short_semi_in = 92.0 / (92.0f64 * 92.0 + 120.0 * 120.0).sqrt();
        let want = 12.0 - 1.0 - short_semi_in;
        for seams in [
            Seams { charge_landing: true, ..Seams::default() },
            Seams { movement: true, ..Seams::default() },
        ] {
            let got = engage_gap_in(&st, 0, 2, seams);
            assert!((got - want).abs() < 1e-6, "shaped engage gap {got}, want {want}");
        }
        assert!((engage_gap_in(&st, 0, 2, Seams::default()) - 10.0).abs() < 1e-6);
    }

    /// A hero with no models left is `_moving_models`' empty list: it drops out
    /// of the minimum instead of dragging it to `INFINITY`, the same way an
    /// empty `b_shapes` does on the table.
    #[test]
    fn a_dead_joined_hero_does_not_move_the_engage_gap() {
        let mut st = four_unit_line();
        st.positions[3].clear();
        st.positions[1].clear();
        let on = Seams { hero_attach: true, ..Seams::default() };
        assert!((engage_gap_in(&st, 0, 2, on) - 10.0).abs() < 1e-6);
    }

    // ------------------------------------------------- NML-1132: the WEAPONS ---

    fn gun(name: &str, attacks: i64, range: i64) -> ShootProfile {
        ShootProfile { name: name.into(), attacks, count: 1, range, ..Default::default() }
    }

    /// One static per unit of `four_unit_line` (whose roster shares profile 0, so
    /// the roster is rebuilt alongside): the charger host carries a 24" RIFLE and a
    /// CCW, its joined hero a 36" HEAVY GUN and a FIST, the two enemies nothing.
    fn hero_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.index.clone(),
            profile: vec![0, 1, 2, 3],
        });
        let host = UnitStatic {
            name: "host".into(),
            model_count: 1,
            shoot: vec![gun("Rifle", 1, 24)],
            melee: vec![gun("CCW", 2, 0)],
            ..Default::default()
        };
        let hero = UnitStatic {
            name: "hero".into(),
            model_count: 1,
            shoot: vec![gun("Heavy Gun", 3, 36)],
            melee: vec![gun("Fist", 4, 0)],
            ..Default::default()
        };
        (st, vec![host, hero, UnitStatic::default(), UnitStatic::default()])
    }

    fn kept(statics: &[UnitStatic], melee: bool, sc: &Scratch) -> Vec<String> {
        let own = if melee { &statics[0].melee } else { &statics[0].shoot };
        let all = folded_slice(own, sc);
        if melee {
            all.iter().map(|p| p.name.clone()).collect()
        } else {
            sc.keep.iter().map(|&i| all[i].name.clone()).collect()
        }
    }

    /// The imagined VOLLEY is the table's member list: the host's weapons and its
    /// joined hero's. At 30" the host's own 24" rifle is out of reach, so the fold
    /// is the only thing that can put a die on the table at all — and it puts the
    /// HERO's 36" gun there, with the hero's own survivor scaling.
    #[test]
    fn the_imagined_volley_carries_a_joined_heros_ranged_weapon() {
        let (st, statics) = hero_line();
        let on = Seams { hero_attach: true, ..Seams::default() };
        let mut sc = Scratch::default();
        member_profiles_of(&statics, &st, 0, false, 30.0, on, &mut sc);
        assert_eq!(kept(&statics, false, &sc), vec!["Heavy Gun".to_string()]);
        assert_eq!(sc.attacks, vec![3]);
        // Closer in, BOTH members fire, host first — the table's build order.
        member_profiles_of(&statics, &st, 0, false, 20.0, on, &mut sc);
        assert_eq!(kept(&statics, false, &sc), vec!["Rifle".to_string(), "Heavy Gun".into()]);
        assert_eq!(sc.attacks, vec![1, 3]);
    }

    /// The MELEE half, and the RED for both: with the seam off `member_profiles_of`
    /// is the plain `profiles_of`/`melee_profiles_of` — the host alone, which is the
    /// imagination this ticket found and the identity every recorded corpus replays on.
    #[test]
    fn the_seam_off_leaves_the_host_alone_in_both_halves() {
        let (st, statics) = hero_line();
        let on = Seams { hero_attach: true, ..Seams::default() };
        let off = Seams::default();
        let mut sc = Scratch::default();
        member_profiles_of(&statics, &st, 0, true, 0.0, on, &mut sc);
        assert_eq!(kept(&statics, true, &sc), vec!["CCW".to_string(), "Fist".into()]);
        assert_eq!(sc.attacks, vec![2, 4]);
        member_profiles_of(&statics, &st, 0, true, 0.0, off, &mut sc);
        assert_eq!(kept(&statics, true, &sc), vec!["CCW".to_string()]);
        assert_eq!(sc.attacks, vec![2]);
        // The RED knob (vintage corpus, `engage_fold=false`): the weapons fold is
        // one of the LATE halves, so it must read the pin exactly like the
        // engage half does — host alone even with `hero_attach` on.
        let red = Seams { hero_attach: true, no_engage_fold: true, ..Seams::default() };
        member_profiles_of(&statics, &st, 0, true, 0.0, red, &mut sc);
        assert_eq!(kept(&statics, true, &sc), vec!["CCW".to_string()]);
        assert_eq!(sc.attacks, vec![2]);
        member_profiles_of(&statics, &st, 0, false, 30.0, off, &mut sc);
        assert!(kept(&statics, false, &sc).is_empty());   // the 24" rifle cannot reach
    }

    /// A hero with no living model brings no shot — `main._run_ai_shooting` :2915
    /// skips exactly that member, and so does the fold.
    #[test]
    fn a_dead_joined_hero_brings_no_weapon() {
        let (mut st, statics) = hero_line();
        st.alive[1] = 0;
        let on = Seams { hero_attach: true, ..Seams::default() };
        let mut sc = Scratch::default();
        member_profiles_of(&statics, &st, 0, true, 0.0, on, &mut sc);
        assert_eq!(kept(&statics, true, &sc), vec!["CCW".to_string()]);
    }

    /// The RANGE half: the reach is measured over the table's two model sets, so the
    /// two joined heroes (2" and 9") decide it at 7" — not the hosts' 12". Folding
    /// one side alone would read 9" or 10", which is why the number is exact.
    #[test]
    fn the_imagined_reach_is_measured_from_the_joined_heros_model() {
        let st = four_unit_line();
        let on = Seams { hero_attach: true, ..Seams::default() };
        assert!((fold_dist_in(&st, 0, 2, on) - 7.0).abs() < 1e-4);
        assert!((fold_dist_in(&st, 0, 2, Seams::default()) - 12.0).abs() < 1e-4);
    }

    // ----------------------------------------------- NML-1150: SPLIT FIRE ---

    use crate::faces_to_hits;
    use crate::io::SplitShot;

    /// `hero_line` with the roster INDEX filled and the two ENEMY statics
    /// named like their roster keys, so the save batches sign a real unit's
    /// name.
    fn split_line() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = hero_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r
                .keys
                .iter()
                .enumerate()
                .map(|(i, k)| (k.clone(), i))
                .collect::<HashMap<_, _>>(),
            profile: r.profile.clone(),
        });
        statics[2] = UnitStatic { name: "b".into(), ..Default::default() };
        statics[3] = UnitStatic { name: "bh".into(), ..Default::default() };
        (st, statics)
    }

    fn split_shot(member: &str, weapon: &str, target: &str) -> SplitShot {
        SplitShot {
            member: member.into(),
            weapon: weapon.into(),
            target: target.into(),
        }
    }

    /// NML-1150: an act whose two members fire at TWO different units resolves
    /// as the table resolves it — one tray volley per target group, in the
    /// act's group order, on ONE tray. The host's rifle opens at `b`, the
    /// joined hero's heavy gun answers at `bh`; each defender eats only its
    /// own group's wounds, and the tray stands exactly where the drawn faces
    /// put it. RED for the whole rung: swapping the act's group order moves
    /// the draw order with it (proven red once by the same assertions under
    /// the swapped list).
    #[test]
    fn the_volley_resolves_per_target_group_in_the_acts_order() {
        let (st, statics) = split_line();
        let action = Action {
            kind: HOLD,
            unit: "a".into(),
            dest: None,
            shoot: Some("b".into()),
            charge: None,
            patient: false,
            split: Some(vec![
                split_shot("host", "Rifle", "b"),
                split_shot("hero", "Heavy Gun", "bh"),
            ]),
            traced: None,
        };
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = crate::sim::resolve_stochastic_tray_on_board(
            &statics, &st, &action, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        // The draw order: the FIRST group's volley, then the second's — the
        // host's 1 rifle die at `b`, its save batch, then the hero's 3 heavy
        // gun dice at `bh` with THAT defender's own save batch. Per-model
        // sighting off, so the counts are the survivor-scaled attacks.
        let kinds: Vec<&str> = shot.rolls.iter().map(|r| r.kind).collect();
        let owners: Vec<&str> = shot.rolls.iter().map(|r| r.owner.as_str()).collect();
        assert_eq!(kinds, vec!["attack", "defense", "attack", "defense"]);
        assert_eq!(owners, vec!["host", "b", "hero", "bh"]);
        assert_eq!(shot.rolls[0].count, 1);
        assert_eq!(shot.rolls[2].count, 3);
        // The per-group HIT count: each save batch is exactly the hits its own
        // hit roll drew (faces recomputed off the port's OWN roll, dice_rules
        // style), signed by ITS group's defender.
        for (hit, save) in [(0usize, 1usize), (2, 3)] {
            let hits = faces_to_hits(&shot.rolls[hit].faces, shot.rolls[hit].target as u8) as i64;
            assert_eq!(shot.rolls[save].count, hits.max(0));
            assert_eq!(shot.rolls[save].owner, if hit == 0 { "b" } else { "bh" });
        }
        // The per-group WOUNDS: each defender eats ONLY its own group's
        // unsaved wounds — `b` stands (its save blocks everything at Defense
        // 0 in this fixture), `bh` falls to its group's one landed wound.
        assert_eq!(next.alive[2], 1);
        assert_eq!(next.wounds[2].iter().sum::<i64>(), 1);
        assert_eq!(next.alive[3], 0);
        assert!(next.wounds[3].is_empty());
        assert_eq!(shot.caused, 1);
        // The tray position: exactly the faces the report drew, no more.
        let mut probe = Tray::seeded(11);
        let total: usize = shot.rolls.iter().map(|r| r.count as usize).sum();
        probe.roll(total);
        assert_eq!(tray.state_i64(), probe.state_i64());
    }

    /// NML-1152 — `split_line` with `host` and `b` each on a 2" base, 12"
    /// centre to centre: the RANGE-VALIDITY edge gap (B11, both radii off) is
    /// 12 - 2 - 2 = 8" (under 9"), while the MODIFIER distance stays the raw
    /// 12" centre gap (over 9") — the exact edge-under/centre-over split the
    /// corpus audit found (qag_ref act 24: edge 7.95" vs centre 14.30").
    fn stealth_split_line() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = split_line();
        st.radii[0] = vec![2.0 * IN2M];
        st.radii[2] = vec![2.0 * IN2M];
        statics[0].ctx.quality = 4;
        statics[2].ctx = Ctx { defense: 4, stealth: true, ..Default::default() };
        (st, statics)
    }

    /// RED PROOF, split vs pooled: `b`'s Stealth must fire off the 12" CENTRE
    /// gap on both the pooled plan (no split aim) and a split group forced
    /// onto the very same (host, b) pair (recorded target `bh`, but the one
    /// aim entry names `b`) — even though the two paths disagree on `d`
    /// itself (pooled keeps the raw 12" nearest-model gap; split subtracts
    /// both radii to 8"). Quality 4, Stealth -1: to-hit 5+, not 4+ — a bug
    /// that read the RANGE gap for the modifier would give 4+ on the split
    /// leg (8" <= 9") while the pooled leg still read 5+, disagreeing.
    #[test]
    fn the_modifier_gate_reads_centre_distance_on_both_the_pooled_and_split_paths() {
        let (st, statics) = stealth_split_line();
        let terrain = crate::terrain::Terrain::default();

        let pooled = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()),
            charge: None, patient: false, split: None, traced: None,
        };
        let mut tray_a = Tray::seeded(11);
        let mut rng_a = crate::rng::GodotRng::new(0);
        let (_, shot_a) = resolve_stochastic_tray_on_board(
            &statics, &st, &pooled, &terrain, Seams::default(), &mut rng_a, &mut tray_a,
        )
        .unwrap();

        let split = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("bh".into()),
            charge: None, patient: false,
            split: Some(vec![split_shot("host", "Rifle", "b")]),
            traced: None,
        };
        let mut tray_b = Tray::seeded(11);
        let mut rng_b = crate::rng::GodotRng::new(0);
        let (_, shot_b) = resolve_stochastic_tray_on_board(
            &statics, &st, &split, &terrain, Seams::default(), &mut rng_b, &mut tray_b,
        )
        .unwrap();

        assert_eq!(shot_a.rolls[0].target, 5, "pooled: Stealth fires off the 12\" centre gap");
        assert_eq!(shot_b.rolls[0].target, 5, "split: must agree with the pooled path");
    }

    // -------------------------------------------------- BLOCK B1: MEND ---

    /// A Mend bearer line: actor `a` (bears Mend, unwounded Tough(2)) with the
    /// joined hero `ah` (Tough(4), two wounds down) 2" ahead, the wounded
    /// Tough(3) regiment `t` (model 0 two wounds down) 4" from `a` — 2" from
    /// `ah`, so the hero's base puts it in reach — and an enemy far out.
    fn mend_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        // Players 0/0/1/1 in the base fixture — `t` must be FRIENDLY.
        st.player = vec![0, 0, 0, 1];
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: vec!["a".into(), "ah".into(), "t".into(), "f".into()],
            index: ["a", "ah", "t", "f"]
                .iter()
                .enumerate()
                .map(|(i, k)| (k.to_string(), i))
                .collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![[2.0 * IN2M, 0.0, 0.0]],
            vec![[4.0 * IN2M, 0.0, 0.0], [4.2 * IN2M, 0.0, 0.0]],
            vec![[30.0 * IN2M, 0.0, 0.0]],
        ];
        st.wounds = vec![vec![2], vec![2], vec![1, 3], vec![1]];
        let mut a = UnitStatic { name: "a".into(), ..Default::default() };
        a.model_count = 1;
        a.wounds_max = vec![2];
        a.mend_active = true;
        let mut ah = UnitStatic { name: "ah".into(), ..Default::default() };
        ah.model_count = 1;
        ah.wounds_max = vec![4];
        ah.is_hero = true;
        let mut t = UnitStatic { name: "t".into(), ..Default::default() };
        t.model_count = 2;
        t.wounds_max = vec![3, 3];
        (st, vec![a, ah, t, UnitStatic { name: "f".into(), ..Default::default() }])
    }

    fn mend_action() -> Action {
        Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None }
    }

    /// BLOCK B1 — one fixture act through the tray: the pre-attack Mend slot
    /// draws exactly ONE die (kind "attack", target 1, signed by the ACTING
    /// unit), the tie prefers the hero on equal lost wounds, and the heal is
    /// the D3 capped at the model's own missing wounds.
    #[test]
    fn mend_heals_the_tied_hero_d3_capped_and_draws_one_die() {
        let (st, statics) = mend_line();
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &mend_action(), &terrain, Seams { hero_attach: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        // Exactly one pre-attack die, the table's own record shape.
        assert_eq!(shot.rolls.len(), 1);
        let r = &shot.rolls[0];
        assert_eq!((r.kind, r.count, r.target, r.owner.as_str()),
            ("attack", 1, MEND_TARGET, "a"));
        // The hero won the tie (lost 2 each; key 2*2+1 beats the regiment's 4)
        // and healed exactly min(D3, its own 2 missing wounds) — never capped
        // WRONG: a D3 face of 4+ cannot exist, and the cap is the model's own.
        let d3 = mend_d3(r.faces[0]);
        assert!((1..=3).contains(&d3));
        assert_eq!(next.wounds[1][0], 2 + d3.min(2));
        assert_eq!(next.wounds[1][0], 2 + mend_d3(r.faces[0]).min(2));
        // The tray stands exactly one draw on.
        let mut probe = Tray::seeded(7);
        probe.roll(1);
        assert_eq!(tray.state_i64(), probe.state_i64());
    }

    /// RED for the whole rung: with the hero unwounded the regiment's model
    /// takes the heal; out of the 3" ring of BOTH bearers nothing qualifies and
    /// the slot draws NOTHING; and without the rule the bearer line stays mute.
    #[test]
    fn mend_picks_the_most_wounded_in_range_and_draws_nothing_without_a_patient() {
        let terrain = crate::terrain::Terrain::default();
        // The hero at full wounds: the regiment's wounded model is the patient.
        let (st, statics) = mend_line();
        let mut st = st;
        st.wounds[1] = vec![4];
        let (next, shot) = {
            let mut tray = Tray::seeded(7);
            let mut rng = crate::rng::GodotRng::new(0);
            resolve_stochastic_tray_on_board(
                &statics, &st, &mend_action(), &terrain, Seams { hero_attach: true, ..Seams::default() }, &mut rng, &mut tray,
            )
            .unwrap()
        };
        let d3 = mend_d3(shot.rolls[0].faces[0]);
        assert_eq!(next.wounds[2][0], 1 + d3.min(2));
        // The regiment walked out of the 3" ring AND the hero sits at full
        // wounds: no patient anywhere, NO draw at all.
        let (st, statics) = mend_line();
        let mut st = st;
        st.positions[2] = vec![[10.0 * IN2M, 0.0, 0.0], [10.2 * IN2M, 0.0, 0.0]];
        st.wounds[1] = vec![4];
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &mend_action(), &terrain, Seams { hero_attach: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert!(shot.rolls.is_empty());
        let probe = Tray::seeded(7);
        assert_eq!(tray.state_i64(), probe.state_i64());
        assert_eq!(next.wounds[2][0], 1);
        // No Mend, no die — even with a wounded Tough model standing next door.
        let (st, mut statics) = mend_line();
        statics[0].mend_active = false;
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &mend_action(), &terrain, Seams { hero_attach: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert!(shot.rolls.is_empty());
    }

    /// The D3 mapping itself: 1-2→1, 3-4→2, 5-6→3 — main.gd:5247's
    /// `(face + 1) / 2`.
    #[test]
    fn the_mend_d3_maps_the_faces_main_gd_way() {
        for (face, want) in [(1u8, 1i64), (2, 1), (3, 2), (4, 2), (5, 3), (6, 3)] {
            assert_eq!(mend_d3(face), want);
        }
    }

    // ------------------------------- BLOCK B2b: THE BUFF-CONSUMPTION BRIDGE ---

    /// `a` — two models at 0", Quality 4, one Rifle — is the bearer AND the
    /// best-value friendly unit in range (2 alive + Tough 1 = 3 against `ah`'s
    /// 2), so a "friendly" buff lands on itself and the very next roll of the
    /// same activation has to read it. `b` is three enemy models at 12".
    fn buff_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0], [0.02 * IN2M, 0.0, 0.0]],
            vec![[2.0 * IN2M, 0.0, 0.0]],
            vec![[12.0 * IN2M, 0.0, 0.0], [12.02 * IN2M, 0.0, 0.0], [12.04 * IN2M, 0.0, 0.0]],
            vec![],
        ];
        st.radii = vec![vec![IN2M; 2], vec![IN2M], vec![IN2M; 3], vec![]];
        st.wounds = vec![vec![1; 2], vec![1], vec![1; 3], vec![]];
        st.alive = vec![2, 1, 3, 0];
        let mut a = UnitStatic {
            name: "a".into(),
            model_count: 2,
            shoot: vec![gun("Rifle", 1, 24)],
            melee: vec![gun("CCW", 1, 0)],
            ..Default::default()
        };
        a.wounds_max = vec![1, 1];
        a.ctx.quality = 4;
        a.ctx.tough = 1;
        let mut ah = UnitStatic { name: "ah".into(), model_count: 1, ..Default::default() };
        ah.ctx.tough = 1;
        let mut b = UnitStatic { name: "b".into(), model_count: 3, ..Default::default() };
        b.wounds_max = vec![1, 1, 1];
        b.ctx.defense = 4;
        b.ctx.quality = 4;
        b.ctx.tough = 1;
        (st, vec![a, ah, b, UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    /// One "Utility Buff" registry entry, at the family's printed defaults.
    fn ub(name: &str) -> UtilityBuff {
        UtilityBuff {
            name: name.into(),
            range_in: 12.0,
            target: "friendly".into(),
            max_targets: 1,
            once: true,
            ..Default::default()
        }
    }

    fn buff_action(shoot: Option<&str>) -> Action {
        Action {
            kind: HOLD,
            unit: "a".into(),
            dest: None,
            shoot: shoot.map(|s| s.to_string()),
            charge: None,
            patient: false,
            split: None,
            traced: None,
        }
    }

    /// Runs one fixture activation on a fresh tray and hands back the state and
    /// the report.
    fn run_buff(st: &State, statics: &[UnitStatic], action: &Action, seed: i64) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, action, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap()
    }

    /// B2b — Precision Attacks Buff (`hit_mod: 1`, no scope): the bearer buffs
    /// itself at the pre-attack slot and the volley that follows in the SAME
    /// activation rolls at 3+ instead of the unit's plain Quality 4+. The
    /// control (no rule) and the scope negative (the same +1 printed
    /// `scope: "melee"`, which is Precision Fighter Buff) both stay at 4+ —
    /// so the number moves for the rule and for nothing else.
    #[test]
    fn precision_attacks_buff_improves_the_bearers_own_to_hit_target_by_one() {
        let (st, mut statics) = buff_line();
        let (_, plain) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!((plain.rolls[0].kind, plain.rolls[0].count, plain.rolls[0].target), ("attack", 1, 4));

        statics[0].utility_buffs = vec![UtilityBuff { hit_mod: 1, ..ub("Precision Attacks Buff") }];
        let (next, buffed) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!((buffed.rolls[0].kind, buffed.rolls[0].count, buffed.rolls[0].target), ("attack", 1, 3));
        // "once": the exchange that used it spends it (main.gd:3244).
        assert!(next.buffs.iter().all(|v| v.is_empty()));

        statics[0].utility_buffs =
            vec![UtilityBuff { hit_mod: 1, scope: "melee".into(), ..ub("Precision Fighter Buff") }];
        let (next, melee_only) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!(melee_only.rolls[0].target, 4, "a melee-scoped record is not a shooting bonus");
        // It was recorded, it just did not apply — and a shooting exchange does
        // not spend a melee record either (`mods_for`'s scope filter runs in
        // `spend_once` too).
        assert_eq!(next.buffs[0].len(), 1);
    }

    /// B2b — the stacking precedence: several live records SUM, and the sum
    /// meets the situational modifier in ONE `modified_hit_target`. Two +1s
    /// give 2+; a +1 against an Evasive defender nets 0 and leaves 4+, which
    /// clamping twice could never produce.
    #[test]
    fn two_live_hit_mods_sum_before_the_single_to_hit_clamp() {
        let (st, mut statics) = buff_line();
        statics[0].utility_buffs = vec![
            UtilityBuff { hit_mod: 1, ..ub("Precision Attacks Buff") },
            UtilityBuff { hit_mod: 1, ..ub("Precision Fighter Buff") },
        ];
        let (_, r) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!(r.rolls[0].target, 2);

        statics[0].utility_buffs = vec![UtilityBuff { hit_mod: 1, ..ub("Precision Attacks Buff") }];
        statics[2].ctx.evasive = true;
        let (_, r) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!(r.rolls[0].target, 4, "Evasive -1 and the buff +1 net to zero");
    }

    /// B2b — Precision Fighter Buff (`hit_mod: 1`, `scope: "melee"`) reaches the
    /// MELEE to-hit target of the charge it precedes: 3+ where the bare fixture
    /// strikes at 4+.
    #[test]
    fn precision_fighter_buff_reaches_the_melee_to_hit_target() {
        let (mut st, mut statics) = buff_line();
        st.positions[2] = vec![[2.5 * IN2M, 0.0, 0.0]];
        st.radii[2] = vec![IN2M];
        st.wounds[2] = vec![1];
        st.alive[2] = 1;
        statics[2].model_count = 1;
        statics[2].wounds_max = vec![1];
        let charge = Action {
            kind: CHARGE,
            unit: "a".into(),
            dest: None,
            shoot: None,
            charge: Some("b".into()),
            patient: false,
            split: None,
            traced: None,
        };
        let (_, plain) = run_buff(&st, &statics, &charge, 11);
        assert_eq!(plain.rolls[0].target, 4);

        statics[0].utility_buffs =
            vec![UtilityBuff { hit_mod: 1, scope: "melee".into(), ..ub("Precision Fighter Buff") }];
        let (_, buffed) = run_buff(&st, &statics, &charge, 11);
        assert_eq!(buffed.rolls[0].target, 3);
    }

    /// B2b — Morale Debuff (`morale_mod: -1`, `target: "enemy"`, 18",
    /// `needs_los`): the record lands on the enemy pick and worsens ITS morale
    /// target by one (`morale_target(4, -1)` = 5+), then the test spends it.
    /// Out of the printed range, and with sight blocked, nothing is recorded.
    #[test]
    fn morale_debuff_worsens_the_enemys_morale_target_and_is_spent_by_that_test() {
        let (st, mut statics) = buff_line();
        let debuff = UtilityBuff {
            morale_mod: -1,
            range_in: 18.0,
            target: "enemy".into(),
            needs_los: true,
            ..ub("Morale Debuff")
        };
        statics[0].utility_buffs = vec![debuff.clone()];
        let (mut next, shot) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(shot.rolls.is_empty(), "the buff arm is dice-free");
        assert_eq!(next.buffs[2].len(), 1);
        assert_eq!(next.buffs[2][0].morale_mod, -1);

        let mut tray = Tray::seeded(5);
        let mut mshot = ShootResult::default();
        tray_morale(&mut next, &statics[2], 2, false, &mut tray, &mut mshot);
        assert_eq!(mshot.rolls[0].target, 5, "Quality 4+ tested at 5+ under the debuff");
        assert!(next.buffs[2].is_empty(), "main.gd:8303 — the test die spends it");

        // Out of the printed 18" range: no pick, no record.
        let mut far = st.clone();
        far.positions[2] = vec![[30.0 * IN2M, 0.0, 0.0]];
        far.alive[2] = 1;
        far.wounds[2] = vec![1];
        far.radii[2] = vec![IN2M];
        let (next, _) = run_buff(&far, &statics, &buff_action(None), 11);
        assert!(next.buffs.iter().all(|v| v.is_empty()));

        // In range, sight blocked: `needs_los` refuses the pick.
        let mut dark = st.clone();
        let mut m = vec![true; 16];
        m[2] = false; // los_pairs[0 * 4 + 2] — a to b
        dark.los_pairs = Some(Rc::new(m));
        let (next, _) = run_buff(&dark, &statics, &buff_action(None), 11);
        assert!(next.buffs.iter().all(|v| v.is_empty()));
    }

    /// B2b — Unstoppable Mark: at the ATTACK seam the bearer marks the volley's
    /// committed target and the base rule lands on itself as a once-grant, so
    /// this volley's wounds cut through the defender's Regeneration — no
    /// regeneration die is drawn at all. A bearer that already marked this
    /// round draws one.
    #[test]
    fn unstoppable_mark_grants_the_regeneration_bypass_for_one_exchange() {
        let (st, mut statics) = buff_line();
        statics[0].shoot = vec![gun("Rifle", 4, 24)]; // enough dice to land a wound
        statics[2].ctx.defense = 6;
        statics[2].ctx.regeneration = true;
        statics[2].ctx.regen_target = 5;
        statics[0].utility_buffs =
            vec![UtilityBuff { vs_target: true, needs_los: true, range_in: 18.0, ..ub("Unstoppable Mark") }];

        // Seed 13: 4 hit dice at 4+ draw [4,3,6,6], the three saves at 6+ all
        // fail — three wounds, which is exactly what a Regeneration roll would
        // otherwise be handed.
        let (next, marked) = run_buff(&st, &statics, &buff_action(Some("b")), 13);
        let landed: i64 = 3 - next.wounds[2].iter().sum::<i64>();
        assert!(landed > 0, "the fixture has to land a wound for the bypass to be visible");
        assert_eq!(regen_rolls(&marked), 0, "Unstoppable ignores Regeneration");
        assert!(next.buffs.iter().all(|v| v.is_empty()), "the exchange spends the grant");
        assert_eq!(next.vs_mark_round[0], st.round);

        // Already marked this round (main.gd:16752): no grant, and the wounds
        // go through the Regeneration roll like anyone else's.
        let mut used = st.clone();
        used.vs_mark_round[0] = used.round;
        let (_, plain) = run_buff(&used, &statics, &buff_action(Some("b")), 13);
        assert_eq!(regen_rolls(&plain), 1);
    }

    /// The defender's Regeneration batch — `regen_batch` signs it with the
    /// DEFENDER's name and stamps it "attack".
    fn regen_rolls(r: &ShootResult) -> usize {
        // Filtered on the Regeneration TARGET so `b`'s own post-volley morale
        // die — same kind, same owner — is never counted as one.
        r.rolls.iter().filter(|x| x.kind == "attack" && x.owner == "b" && x.target == 5).count()
    }

    /// B2b — the two write-half names. Casting Buff picks by the
    /// `friendly_caster` filter (`a` is no caster, `ah` is) and records
    /// `casting_mod`; Primal Boost Buff records the rule GRANT on the
    /// best-value friendly. Neither has a consumer on this core's tray path —
    /// there is no cast die here at all, and a granted Surge cannot re-stamp a
    /// baked weapon profile — so the proof is the record, not a number.
    /// Without the rule on the bearer nothing is written at all.
    #[test]
    fn casting_and_primal_boost_buffs_land_their_records_on_the_right_pick() {
        let (st, mut statics) = buff_line();
        statics[1].is_caster = true;
        statics[0].utility_buffs = vec![UtilityBuff {
            casting_mod: 1,
            target: "friendly_caster".into(),
            ..ub("Casting Buff")
        }];
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(next.buffs[0].is_empty(), "the bearer is no caster — the filter refuses it");
        assert_eq!(next.buffs[1].len(), 1);
        assert_eq!(next.buffs[1][0].casting_mod, 1);

        statics[0].utility_buffs = vec![UtilityBuff {
            grants_rule: "Primal Boost".into(),
            ..ub("Primal Boost Buff")
        }];
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert_eq!(&*next.buffs[0][0].grants_rule, "Primal Boost");
        assert!(!crate::mods::granted(&next, 0, "Unstoppable"));

        // No rule on the bearer, no record — the ledger stays empty.
        statics[0].utility_buffs = vec![];
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(next.buffs.iter().all(|v| v.is_empty()));
    }

    // ------------------------------------------------- BLOCK B11: Quick Shot ---

    /// A RUSH action with a shoot target. `dest: None` keeps the activation
    /// stationary — the same way every OTHER shoot fixture in this file
    /// sidesteps `Unsupported::MovedShootLos` (the port declines a MOVED
    /// unit's shot rather than re-probe LOS off a stale pre-move matrix; that
    /// decline is pre-existing and shared with ADVANCE, untouched by B11).
    fn rush_shoot(target: &str) -> Action {
        Action {
            kind: RUSH,
            unit: "a".into(),
            dest: None,
            shoot: Some(target.to_string()),
            charge: None,
            patient: false,
            split: None,
            traced: None,
        }
    }

    fn advance_shoot(target: &str) -> Action {
        Action { kind: ADVANCE, ..rush_shoot(target) }
    }

    /// A Quick Shot carrier's RUSH still rolls its volley, and the activation
    /// names the rule (rules-must-log).
    #[test]
    fn quick_shot_lets_a_rush_action_fire_its_volley() {
        let (st, mut statics) = buff_line();
        statics[0].quick_shot_active = true;
        let (_, shot) = run_buff(&st, &statics, &rush_shoot("b"), 11);
        assert!(!shot.rolls.is_empty());
        assert!(shot.log.iter().any(|l| l.starts_with("Quick Shot:")));
    }

    /// The same RUSH, no rule: no volley, no log line — RUSH stays a move-only
    /// action for every carrier that does not have Quick Shot.
    #[test]
    fn without_quick_shot_a_rush_action_never_shoots() {
        let (st, statics) = buff_line();
        let (_, shot) = run_buff(&st, &statics, &rush_shoot("b"), 11);
        assert!(shot.rolls.is_empty());
        assert!(shot.log.is_empty());
    }

    /// ADVANCE already shoots regardless of Quick Shot — B11 only widens the
    /// predicate to include RUSH, it must not touch ADVANCE's own gate.
    #[test]
    fn advance_shoots_with_or_without_quick_shot() {
        let (st, mut statics) = buff_line();
        let (_, without) = run_buff(&st, &statics, &advance_shoot("b"), 11);
        assert!(!without.rolls.is_empty());
        statics[0].quick_shot_active = true;
        let (_, with_rule) = run_buff(&st, &statics, &advance_shoot("b"), 11);
        assert!(!with_rule.rolls.is_empty());
    }

    // ------------------------------------------- GF v3.5.1: Limited weapons ---

    /// GF v3.5.1 weapon rule Limited — "may only be used once per game": the
    /// Limited Cannon fires alongside the plain Rifle in round 1, then draws
    /// no dice at all in round 2, while the Rifle keeps firing.
    #[test]
    fn a_limited_weapon_fires_once_then_draws_no_dice_the_next_round() {
        let (st, mut statics) = buff_line();
        statics[0].shoot = vec![ShootProfile { limited: true, ..gun("Cannon", 1, 24) }, gun("Rifle", 1, 24)];
        let (round1, shot1) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!(
            shot1.rolls.iter().filter(|r| r.kind == "attack").count(), 2,
            "round 1: Cannon and Rifle both fire"
        );
        assert!(round1.limited_used[0].iter().any(|n| n == "Cannon"));

        let (_, shot2) = run_buff(&round1, &statics, &buff_action(Some("b")), 12);
        assert_eq!(
            shot2.rolls.iter().filter(|r| r.kind == "attack").count(), 1,
            "round 2: the spent Cannon draws no dice, the Rifle still fires"
        );
    }

    // ------------------------------ BLOCK B2: RE-POSITION ARTILLERY ---

    /// Bearer `a` (carries Re-Position Artillery, NOT attached to anyone —
    /// `Seams::default()` keeps hero_attach off, so the base fixture's own
    /// attachment wiring never applies) with a friendly Artillery model `g`
    /// 4" ahead (inside the 6" pick range) that starts with NO weapons at
    /// all (so it never has a shoot target on its own); two enemies on the
    /// same line past `g` — `e1` 26" out and never activated, `e2` only 6"
    /// out but ALREADY activated — so the table's "not-yet-activated first"
    /// key must send `g` toward the FARTHER `e1`.
    fn reposition_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.player = vec![0, 0, 1, 1];
        st.activated = vec![false, false, false, true];
        st.roster = Rc::new(crate::state::Roster {
            keys: vec!["a".into(), "g".into(), "e1".into(), "e2".into()],
            index: ["a", "g", "e1", "e2"].iter().enumerate().map(|(i, k)| (k.to_string(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![[4.0 * IN2M, 0.0, 0.0]],
            vec![[30.0 * IN2M, 0.0, 0.0]],
            vec![[10.0 * IN2M, 0.0, 0.0]],
        ];
        let a = UnitStatic { name: "a".into(), model_count: 1, reposition_artillery_active: true, ..Default::default() };
        let mut g = UnitStatic { name: "g".into(), model_count: 1, ..Default::default() };
        g.ctx.artillery = true;
        g.ctx.tough = 1;
        let e1 = UnitStatic { name: "e1".into(), model_count: 1, ..Default::default() };
        let e2 = UnitStatic { name: "e2".into(), model_count: 1, ..Default::default() };
        (st, vec![a, g, e1, e2])
    }

    fn reposition_action() -> Action {
        Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None }
    }

    /// BLOCK B2 — no dice ride Re-Position Artillery at all, and the picked
    /// artillery is forced 9" straight toward `e1`, the FARTHER but
    /// not-yet-activated enemy, never toward the nearer `e2` who already
    /// acted this round.
    #[test]
    fn reposition_moves_the_undefended_artillery_toward_the_not_yet_activated_enemy() {
        let (st, statics) = reposition_line();
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &reposition_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert!(shot.rolls.is_empty(), "Re-Position Artillery is dice-free");
        let probe = Tray::seeded(7);
        assert_eq!(tray.state_i64(), probe.state_i64());
        let g_pos = next.positions[1][0];
        assert!((g_pos[0] - 13.0 * IN2M).abs() < 1e-6, "g at {g_pos:?}");
        assert_eq!(g_pos[2], 0.0);
    }

    /// RED for the pick: a shoot target already in range skips the move
    /// entirely; out of the 6" pick range there is no artillery to move at
    /// all; without the rule the bearer stays mute.
    #[test]
    fn reposition_skips_with_a_shoot_target_out_of_range_or_without_the_rule() {
        let terrain = crate::terrain::Terrain::default();
        let (st, mut statics) = reposition_line();
        statics[1].shoot = vec![ShootProfile { range: 30, ..Default::default() }];
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &reposition_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[1][0], st.positions[1][0]);

        let (mut st, statics) = reposition_line();
        st.positions[1] = vec![[20.0 * IN2M, 0.0, 0.0]]; // g walked out of the 6" pick ring
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &reposition_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[1][0], st.positions[1][0]);

        let (st, mut statics) = reposition_line();
        statics[0].reposition_artillery_active = false;
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &reposition_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[1][0], st.positions[1][0]);
    }

    /// `SoloController._axis_scale` solo_controller.gd:8911-8915, the pure
    /// board-edge clamp: inside the limit (or a zero step) the scale stays
    /// 1.0; stepping past it scales back to land EXACTLY on the edge.
    #[test]
    fn the_reposition_axis_scale_clamps_to_the_board_edge() {
        assert_eq!(axis_scale(0.0, 5.0, 10.0), 1.0);
        assert_eq!(axis_scale(0.0, 0.0, 10.0), 1.0);
        let s = axis_scale(8.0, 9.0, 10.0);
        assert!((8.0 + 9.0 * s - 10.0).abs() < 1e-4, "scale {s} overshoots the edge");
    }

    // ------------------------------------------------- BLOCK B3: Breath Attack ---

    /// BLOCK B3 — a(idx0, the bearer) vs b(idx2, the target), 3" apart
    /// edge-to-edge (inside the 6" range); ah/bh (idx1/3) field no models, so
    /// neither the bearer fold nor the target pick can ever reach them — a
    /// deliberately clean one-bearer-one-target case. b fields 3 alive
    /// Tough(1) models at Defense 4, so Blast(3) caps its hit count at 3 and
    /// the save target is `save_target(4, 1) == 5` (AP(1)).
    fn breath_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![],
            vec![[5.0 * IN2M, 0.0, 0.0], [5.02 * IN2M, 0.0, 0.0], [5.04 * IN2M, 0.0, 0.0]],
            vec![],
        ];
        st.radii = vec![vec![IN2M], vec![], vec![IN2M; 3], vec![]];
        st.wounds = vec![vec![1], vec![], vec![1, 1, 1], vec![]];
        st.alive = vec![1, 0, 3, 0];
        let mut a = UnitStatic { name: "a".into(), ..Default::default() };
        a.model_count = 1;
        a.breath_attack_active = true;
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.model_count = 3;
        b.wounds_max = vec![1, 1, 1];
        b.ctx.defense = 4;
        (
            st,
            vec![
                a,
                UnitStatic { name: "ah".into(), ..Default::default() },
                b,
                UnitStatic { name: "bh".into(), ..Default::default() },
            ],
        )
    }

    fn breath_action() -> Action {
        Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None, traced: None }
    }

    /// One fixture act through the tray: the pre-attack Breath Attack slot
    /// draws the trigger die (kind "attack", target `BREATH_TRIGGER`, signed
    /// by the ACTING unit) and, on a hit, the table's own save batch — Blast(3)
    /// capped at the target's 3 alive models, at AP(1)'s worsened save target.
    #[test]
    fn breath_attack_fires_the_trigger_die_then_the_tables_save_batch_on_a_hit() {
        let (st, statics) = breath_line();
        let terrain = crate::terrain::Terrain::default();
        // Seed 7's first face is an unmodified 6 — an automatic trigger success.
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &breath_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot.rolls.len(), 2);
        let trig = &shot.rolls[0];
        assert_eq!(
            (trig.kind, trig.count, trig.target, trig.owner.as_str()),
            ("attack", 1, BREATH_TRIGGER, "a")
        );
        let save = &shot.rolls[1];
        assert_eq!((save.kind, save.count, save.target, save.owner.as_str()), ("defense", 3, 5, "b"));
        let blocks = crate::dice::faces_to_hits(&save.faces, 5) as i64;
        let unsaved = (3 - blocks).max(0);
        let removed: i64 = 3 - next.wounds[2].iter().sum::<i64>();
        assert_eq!(removed, unsaved);
        assert_eq!(next.alive[2], 3 - unsaved);
        let mut probe = Tray::seeded(7);
        probe.roll(1);
        probe.roll(3);
        assert_eq!(tray.state_i64(), probe.state_i64());
    }

    /// RED for the pre-attack slot: a trigger face of 1 always fails and
    /// draws NOTHING else; a target beyond the 6" range, or the rule inactive
    /// on the only bearer, draws not even the trigger die.
    #[test]
    fn breath_attack_fizzles_on_a_1_and_draws_nothing_out_of_range_or_without_the_rule() {
        let terrain = crate::terrain::Terrain::default();
        // Seed 3's first face is a 1 — an automatic trigger failure.
        let (st, statics) = breath_line();
        let mut tray = Tray::seeded(3);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &breath_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot.rolls.len(), 1);
        assert_eq!(shot.rolls[0].faces, vec![1]);
        assert_eq!(next.wounds[2].iter().sum::<i64>(), 3);
        let mut probe = Tray::seeded(3);
        probe.roll(1);
        assert_eq!(tray.state_i64(), probe.state_i64());

        // Out of range: b pushed 20" out (edge gap 18" > the 6" reach).
        let (mut st2, statics2) = breath_line();
        st2.positions[2] =
            vec![[20.0 * IN2M, 0.0, 0.0], [20.02 * IN2M, 0.0, 0.0], [20.04 * IN2M, 0.0, 0.0]];
        let mut tray2 = Tray::seeded(7);
        let mut rng2 = crate::rng::GodotRng::new(0);
        let (_, shot2) = resolve_stochastic_tray_on_board(
            &statics2, &st2, &breath_action(), &terrain, Seams::default(), &mut rng2, &mut tray2,
        )
        .unwrap();
        assert!(shot2.rolls.is_empty());
        let probe2 = Tray::seeded(7);
        assert_eq!(tray2.state_i64(), probe2.state_i64());

        // No bearer: the rule inactive on the only candidate.
        let (st3, mut statics3) = breath_line();
        statics3[0].breath_attack_active = false;
        let mut tray3 = Tray::seeded(7);
        let mut rng3 = crate::rng::GodotRng::new(0);
        let (_, shot3) = resolve_stochastic_tray_on_board(
            &statics3, &st3, &breath_action(), &terrain, Seams::default(), &mut rng3, &mut tray3,
        )
        .unwrap();
        assert!(shot3.rolls.is_empty());
    }

    /// Blast(3) scales DOWN to the target's own alive count when it fields
    /// fewer than 3 models — never floors below the models actually there —
    /// and AP(1) worsens the save target the same way whatever the count.
    #[test]
    fn breath_attack_scales_blast_to_the_targets_alive_count() {
        let (mut st, statics) = breath_line();
        st.wounds[2] = vec![1]; // b down to 1 alive model
        st.positions[2] = vec![[5.0 * IN2M, 0.0, 0.0]];
        st.radii[2] = vec![IN2M];
        st.alive[2] = 1;
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &breath_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot.rolls.len(), 2);
        let save = &shot.rolls[1];
        assert_eq!((save.count, save.target), (1, 5));
    }

    // --------------------------------------------- NML-1152 S3: plain moves ---

    /// `small_board()`'s 72" x 48" school board with a FOREST bar across
    /// x in [3", 6"), z in [-3", 3") —
    /// a 3"-thick difficult block sitting squarely on the straight line from the
    /// unit to its destination, and NOT on the rigid landing spot, which is what
    /// makes `_targets_in_difficult` (:5159) answer "route around it".
    fn forest_bar_board() -> crate::terrain::Terrain {
        // `type_at` indexes cells as `floor(inches / 3 + 15)` on this 72" x 48"
        // grid, so cell 16 is x in [3", 6") and cells 14/15 are z in [-3", 3").
        let cells = vec![[16.0, 14.0, crate::terrain::FOREST as f64],
                         [16.0, 15.0, crate::terrain::FOREST as f64]];
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells,
            sandbox: vec![],
            pieces: vec![],
            walls: vec![],
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    fn advance_to(x_in: f64) -> Action {
        Action {
            kind: ADVANCE,
            unit: "a".into(),
            dest: Some([x_in * IN2M as f64, 0.0, 0.0]),
            shoot: None,
            charge: None,
            patient: false,
            split: None,
            traced: None,
        }
    }

    /// A lone 4-model unit (Tough 1, Quality 4+) — row 12 (`dangerous_end_morale`,
    /// DEFECT_LEDGER): GF v3.5.1 p.10/p.12, main.gd:1092-1098.
    fn dangerous_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions[0] = vec![
            [0.0, 0.0, 0.0],
            [0.02 * IN2M, 0.0, 0.0],
            [0.04 * IN2M, 0.0, 0.0],
            [0.06 * IN2M, 0.0, 0.0],
        ];
        st.radii[0] = vec![IN2M; 4];
        st.wounds[0] = vec![1; 4];
        st.alive[0] = 4;
        let mut a = UnitStatic { name: "a".into(), model_count: 4, ..Default::default() };
        a.wounds_max = vec![1; 4];
        a.ctx.quality = 4;
        a.ctx.tough = 1;
        (st, vec![a, UnitStatic::default(), UnitStatic::default(), UnitStatic::default()])
    }

    /// Marks BOTH cell-index neighbours on x AND z DANGEROUS (`forest_bar_board`'s
    /// own straddling trick): a rigid ADVANCE band always lands `dangerous_line`'s
    /// unit exactly on x=6"/z=0", both of them cell-index boundaries.
    fn dangerous_bar_board() -> crate::terrain::Terrain {
        let cells = vec![
            [16.0, 14.0, crate::terrain::DANGEROUS as f64],
            [16.0, 15.0, crate::terrain::DANGEROUS as f64],
            [17.0, 14.0, crate::terrain::DANGEROUS as f64],
            [17.0, 15.0, crate::terrain::DANGEROUS as f64],
        ];
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells,
            sandbox: vec![],
            walls: vec![],
            pieces: vec![],
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    /// RED for DEFECT_LEDGER row 12: a plain ADVANCE through DANGEROUS terrain
    /// that kills half or more of the unit must draw a REAL morale die from the
    /// tray at the END of the activation (GF v3.5.1 p.10 General Morale Tests) —
    /// before this port, the wound landed and `shot.mark("dangerous_end_morale")`
    /// fired, but main.gd:1092-1098's actual test was "not ported": no die was
    /// ever drawn and `next.shaken` never moved.
    #[test]
    fn dangerous_terrain_losses_at_half_or_more_draw_a_morale_die() {
        let (st, statics) = dangerous_line();
        let t = dangerous_bar_board();
        // Seeds are searched, not guessed (same convention as the RED in
        // `the_die_count_takes_the_ratio_or_the_bearer_cap` above): the
        // dangerous roll is 4 dice, and a face of 1 is what wounds — this seed's
        // first 4 faces give >= 2 ones, so >= half of the 4 models die.
        let seed = (1i64..)
            .find(|&s| Tray::seeded(s).roll(4).iter().filter(|&&f| f == 1).count() >= 2)
            .unwrap();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(100.0), &t,
            Seams { dangerous_end_morale: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert!(next.alive[0] > 0 && next.alive[0] <= 2, "setup didn't kill >= half: {}", next.alive[0]);
        // Two "a"-owned rolls on the tray: the dangerous test (4 dice), THEN
        // the morale test (1 die) — RED without the port, which draws only
        // the first and never touches `next.shaken`.
        let a_rolls: Vec<&crate::dice::Roll> = shot.rolls.iter().filter(|r| r.owner == "a").collect();
        assert_eq!(a_rolls.len(), 2, "{:?}", shot.rolls);
        assert_eq!((a_rolls[0].count, a_rolls[1].count), (4, 1));
    }

    /// The same crossing with losses BELOW half: no morale die is drawn, and
    /// only the dangerous roll appears on the tray.
    #[test]
    fn dangerous_terrain_losses_below_half_draw_no_morale_die() {
        let (st, statics) = dangerous_line();
        let t = dangerous_bar_board();
        let seed = (1i64..)
            .find(|&s| Tray::seeded(s).roll(4).iter().filter(|&&f| f == 1).count() == 1)
            .unwrap();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(100.0), &t,
            Seams { dangerous_end_morale: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.alive[0], 3, "setup didn't kill exactly one of four: {}", next.alive[0]);
        let a_rolls: Vec<&crate::dice::Roll> = shot.rolls.iter().filter(|r| r.owner == "a").collect();
        assert_eq!(a_rolls.len(), 1, "no morale die below half: {:?}", shot.rolls);
    }

    /// DEFECT_LEDGER #12 knob: `Seams::default()` — every corpus recorded
    /// before this rule shipped, `dangerous_end_morale` absent and false —
    /// replays with the OLD (bug-present) behaviour: the wound lands, the
    /// mark fires, no die is drawn, even at >= half losses. This is what
    /// keeps the frozen gen0 self-play snapshot byte-exact.
    #[test]
    fn dangerous_terrain_losses_draw_no_morale_die_with_the_knob_off() {
        let (st, statics) = dangerous_line();
        let t = dangerous_bar_board();
        let seed = (1i64..)
            .find(|&s| Tray::seeded(s).roll(4).iter().filter(|&&f| f == 1).count() >= 2)
            .unwrap();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(100.0), &t, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert!(next.alive[0] > 0 && next.alive[0] <= 2, "setup didn't kill >= half: {}", next.alive[0]);
        let a_rolls: Vec<&crate::dice::Roll> = shot.rolls.iter().filter(|r| r.owner == "a").collect();
        assert_eq!(a_rolls.len(), 1, "knob off must not draw the morale die: {:?}", shot.rolls);
    }

    /// S3 — a NON-charge move goes through `mv::step::plain_move` once
    /// `movement` is on: the unit routes AROUND the forest instead of walking
    /// its whole 6" band straight through it, so the models rest somewhere the
    /// rigid translation never puts them.
    #[test]
    fn a_plain_advance_lands_through_the_solver_under_the_movement_seam() {
        let (st, statics) = buff_line();
        let t = forest_bar_board();
        let rigid = resolve_on_board(&statics, &st, &advance_to(8.0), &t, Seams::default())
            .unwrap();
        let solved = resolve_on_board(
            &statics, &st, &advance_to(8.0), &t, Seams { movement: true, ..Seams::default() },
        )
        .unwrap();
        // The rigid arm spends the full band on the straight line, every model
        // the same delta — through the forest.
        for (got, before) in rigid.positions[0].iter().zip(st.positions[0].iter()) {
            assert!((got[0] - (before[0] + 6.0 * IN2M)).abs() < 1e-6, "rigid {got:?}");
        }
        let gap_in = solved.positions[0]
            .iter()
            .zip(rigid.positions[0].iter())
            .map(|(a, b)| ((a[0] - b[0]).powi(2) + (a[2] - b[2]).powi(2)).sqrt() / IN2M as f64)
            .fold(0.0f64, f64::max);
        assert!(gap_in > 0.5, "the solver landed on the rigid answer, gap {gap_in}\"");
    }

    /// The RED for that routing: `move_rigid` puts ADVANCE and RUSH back on the
    /// rigid arm with `movement` still on, and every model must return to the
    /// straight-line answer to the digit. Without it the assertion above could
    /// be reading any other difference the seam makes.
    #[test]
    fn the_move_rigid_red_returns_a_plain_advance_to_the_straight_line() {
        let (st, statics) = buff_line();
        let t = forest_bar_board();
        let rigid = resolve_on_board(&statics, &st, &advance_to(8.0), &t, Seams::default())
            .unwrap();
        let red = resolve_on_board(
            &statics,
            &st,
            &advance_to(8.0),
            &t,
            Seams { movement: true, move_rigid: true, ..Seams::default() },
        )
        .unwrap();
        assert_eq!(red.positions, rigid.positions);
    }

    /// NML-1152 B14 step 1 — the table RECORDS the Bounding die, the twin
    /// REPLAYS it: a `traced` draw of `faces:[2], plus:1` grows the 6" band by
    /// exactly 2+1 = 3" for THIS act (RED for the arm: comment out the
    /// `bounding_bonus_in` addend in `resolve_with` and this falls to 6"),
    /// and the resolver names it in the log. Every act with no `traced` entry
    /// (every corpus recorded before this) reads the plain 6" band, unchanged.
    #[test]
    fn a_recorded_bounding_trace_grows_the_band_by_its_faces_plus_the_flat_and_logs_it() {
        use crate::io::TracedRoll;
        let (st, statics) = buff_line();
        let terrain = crate::terrain::Terrain::default();
        let traced_advance = Action {
            traced: Some(vec![TracedRoll { tag: "bounding_d3".into(), faces: vec![2], plus: 1 }]),
            ..advance_to(20.0)
        };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &traced_advance, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert!((next.positions[0][0][0] - (st.positions[0][0][0] + 9.0 * IN2M as f64)).abs() < 1e-6);
        assert!(shot.log.iter().any(|l| l.contains("Bounding") && l.contains("+3")), "{:?}", shot.log);

        // No trace on the act: the plain 6" band, no log line — every pre-B14 corpus's own reading.
        let mut tray2 = Tray::seeded(11);
        let mut rng2 = crate::rng::GodotRng::new(0);
        let (plain_next, plain_shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(20.0), &terrain, Seams::default(), &mut rng2, &mut tray2,
        )
        .unwrap();
        assert!((plain_next.positions[0][0][0] - (st.positions[0][0][0] + 6.0 * IN2M as f64)).abs() < 1e-6);
        assert!(plain_shot.log.is_empty());
    }

    // ------------------------------------------- BLOCK C: Versatile Reach ---

    /// Block C fixture (the `duel` shape) — a single-model carrier "a" with
    /// one melee profile facing a single-model target "b" whose base-edge gap
    /// (inches) the caller picks. Bands are the state defaults (rush 12").
    fn vr_charge_line(gap_in: f64) -> (State, Vec<UnitStatic>) {
        let blade = ShootProfile { name: "Blade".into(), attacks: 8, count: 1, range: 0, ..Default::default() };
        let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "b".into()],
            index: ["a".to_string(), "b".to_string()]
                .iter()
                .enumerate()
                .map(|(i, k)| (k.clone(), i))
                .collect(),
            profile: vec![0, 1],
        });
        st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
        st.player = vec![0, 1];
        st.alive = vec![1, 1];
        st.attached = Rc::new(vec![vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None]);
        st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[(gap_in + 2.0) * IN2M, 0.0, 0.0]]];
        st.wounds = vec![vec![1], vec![1]];
        st.radii = vec![vec![IN2M], vec![IN2M]];
        (st, vec![
            UnitStatic {
                ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
                name: "Charger".into(),
                melee: vec![blade],
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
                name: "Target".into(),
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
        ])
    }

    fn vr_charge() -> Action {
        Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None,
        }
    }

    /// The seam-armed resolver run every VR charge test replays: the M4
    /// movement port is what the table's `_charge_move` (:2213) feeds, so the
    /// +2" must reach its band argument exactly there. `versatile_reach: true`
    /// because every existing caller of this helper is proving the RULE
    /// itself (the on-by-default `play_game` reading) — the knob's own
    /// off/on behaviour has its dedicated test below.
    fn vr_resolve(st: &State, statics: &[UnitStatic], action: &Action) -> State {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, action, &small_board(),
            Seams { movement: true, versatile_reach: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap()
        .0
    }

    /// The post-move base-edge gap of the charger vs its target, in inches.
    fn vr_gap(next: &State) -> f64 {
        geom::edge_gap_in(
            &next.positions[0], &next.radii[0], &next.positions[1], &next.radii[1],
            DEFAULT_BASE_RADIUS_M,
        )
    }

    /// GF v3.5.1 p.9 "Consolidation Moves": a melee that wipes the enemy
    /// (`vr_charge_line`'s "a" vs the melee-less "b", already in contact) lets
    /// the survivor move up to 3" toward the nearest objective, stamped 10"
    /// due z of "a" so the whole band is spent and the delta is exact. RED
    /// without the seam: `consolidate="off"` (the default) never moves it.
    #[test]
    fn consolidate_table_moves_the_winner_three_inches_toward_the_nearest_marker() {
        let (mut st, statics) = vr_charge_line(0.0);
        st.objectives = vec![crate::state::Objective { pos: [0.0, 0.0, 10.0 * IN2M], owner: 1 }];
        let terrain = small_board();
        let action = vr_charge();

        let off = resolve_on_board(&statics, &st, &action, &terrain, Seams::default()).unwrap();
        assert_eq!(off.alive[1], 0, "the melee must wipe the target for this test to prove anything");
        assert_eq!(
            off.positions[0][0], [0.0, 0.0, 0.0],
            "consolidate=\"off\" (default): the winner never moves"
        );

        let on = resolve_on_board(
            &statics, &st, &action, &terrain, Seams { consolidate: true, ..Seams::default() },
        )
        .unwrap();
        assert_eq!(on.alive[1], 0);
        let moved_in = on.positions[0][0][2] / IN2M;
        assert!(
            (moved_in - 3.0).abs() < 1e-6,
            "consolidate=\"table\": the winner spends the whole 3\" band toward the marker, got {:.4}\"",
            moved_in
        );
    }

    /// (a) THE WITNESS POLICY — a CHARGE whose base-edge gap sits in the
    /// unlock ring `(band, band + 2"]` lands in contact: the action itself is
    /// the evidence the table's own judge took the charge half. RED without
    /// the port (the plain 12" band falls 1.5" short of the boundary).
    #[test]
    fn a_vr_charge_in_the_unlock_ring_lands_in_contact() {
        let (st, mut statics) = vr_charge_line(13.5);
        statics[0].versatile_reach_charge_in = Some(2.0);
        let next = vr_resolve(&st, &statics, &vr_charge());
        assert!(
            vr_gap(&next) < 0.3,
            "in the ring, the +2\" must land contact: gap {:.3}\"",
            vr_gap(&next)
        );
    }

    /// (b) THE UPPER BOUND — a gap of `band + 2.5"` is outside the closed
    /// ring: the band stays byte-identical to a non-carrier's and the charge
    /// falls 2.5" short. RED the moment the upper bound is loosened or lost.
    #[test]
    fn a_vr_charge_outside_the_ring_gets_no_bonus() {
        let (st, mut statics) = vr_charge_line(14.5);
        statics[0].versatile_reach_charge_in = Some(2.0);
        let next = vr_resolve(&st, &statics, &vr_charge());
        assert!(
            vr_gap(&next) > 2.0,
            "outside the ring the plain band stands: gap {:.3}\"",
            vr_gap(&next)
        );
    }

    /// (c) THE LOWER BOUND — a charge that is already legal (`gap <= band`)
    /// gets NOTHING: on the rigid arm the carrier's translation is
    /// byte-identical to a non-carrier's, which is what keeps the port from
    /// over-granting on ordinary charges. RED the moment the `gap > band`
    /// guard is dropped — the band then reaches the target CENTRE one inch
    /// further on.
    #[test]
    fn an_ordinary_vr_charge_lands_exactly_like_a_non_carriers() {
        let (st, statics) = vr_charge_line(11.0);
        let action = Action { dest: Some(st.positions[1][0]), ..vr_charge() };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (plain, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &small_board(), Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        let (st2, mut statics2) = vr_charge_line(11.0);
        statics2[0].versatile_reach_charge_in = Some(2.0);
        let mut tray2 = Tray::seeded(11);
        let mut rng2 = crate::rng::GodotRng::new(0);
        let (carrier, _) = resolve_stochastic_tray_on_board(
            &statics2, &st2, &action, &small_board(), Seams::default(), &mut rng2, &mut tray2,
        )
        .unwrap();
        assert_eq!(
            carrier.positions[0], plain.positions[0],
            "inside the plain band the landing is byte-identical"
        );
    }

    /// (d) THE KIND GATE — the same carrier RUSHing at the same point draws no
    /// band. The act mirrors battle_sim.gd:649-650, which reads the charge key
    /// for EVERY move kind, so a recorded RUSH can carry one: without the
    /// `kind != CHARGE` gate the helper would grant the +2" here too and the
    /// rigid arm would spend 14". RED the moment the gate falls.
    #[test]
    fn a_vr_rush_draws_no_band_bonus() {
        let (st, mut statics) = vr_charge_line(13.5);
        statics[0].versatile_reach_charge_in = Some(2.0);
        let rush = Action {
            kind: RUSH, unit: "a".into(), dest: Some(st.positions[1][0]), shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None,
        };
        let next = vr_resolve(&st, &statics, &rush);
        let moved = (next.positions[0][0][0] - st.positions[0][0][0]).abs() / IN2M as f64;
        assert!(
            (moved - 12.0).abs() < 1e-6,
            "the plain rush band, nothing more: moved {:.3}\"",
            moved
        );
    }

    /// The `versatile_reach` knob itself (`Knobs`/`Seams::versatile_reach`,
    /// INVESTIGATION_gen0_replay_drift_2026-09-03.md): PR #582 shipped this
    /// bonus with no legacy gate at all, so 45/2000 sampled Gen-0 games
    /// (recorded before #582) no longer replay byte-identical. OFF (the
    /// `Default`, every corpus recorded before #582) must replay the same gap
    /// a non-carrier gets — no bonus, band unchanged; ON (the shipped current
    /// engine) applies the same +2" ring bonus test (a) above proves. RED if
    /// the `!versatile_reach` guard in `versatile_reach_charge_in` is
    /// dropped: the "off" row would land in contact like the "on" row.
    #[test]
    fn the_versatile_reach_knob_off_replays_legacy_and_on_applies_the_bonus() {
        let (st, mut statics) = vr_charge_line(13.5);
        statics[0].versatile_reach_charge_in = Some(2.0);
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (legacy, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &vr_charge(), &small_board(),
            Seams { movement: true, versatile_reach: false, ..Seams::default() },
            &mut rng, &mut tray,
        )
        .unwrap();
        assert!(
            (vr_gap(&legacy) - 1.5).abs() < 1e-6,
            "knob OFF: the plain 12\" rush band alone, 1.5\" short of the 13.5\" gap, got {:.3}\"",
            vr_gap(&legacy)
        );

        let on = vr_resolve(&st, &statics, &vr_charge());
        assert!(
            vr_gap(&on) < 0.3,
            "knob ON: the +2\" ring bonus lands in contact, gap {:.3}\"",
            vr_gap(&on)
        );
    }

    /// The CLASS FIX (external review 03.09. item 3 / F9, `acts::rule_on`):
    /// the boolean's own OFF row above is `rules_epoch: 0`, the reading every
    /// pre-epoch corpus (including this test's own default) carries and must
    /// keep replaying unaffected. `rules_epoch: CURRENT_RULES_EPOCH` — what a
    /// fresh `play_game()` stamps — turns the SAME rule on even with the
    /// boolean left at its legacy `false`, exactly like a fresh recording
    /// that never sets `versatile_reach` itself. RED if `rule_on` is dropped
    /// from the `versatile_reach_charge_in` call site in `resolve_with`: the
    /// epoch row would land short like the legacy row.
    #[test]
    fn the_versatile_reach_epoch_gate_turns_the_bonus_on_without_the_knob() {
        let (st, mut statics) = vr_charge_line(13.5);
        statics[0].versatile_reach_charge_in = Some(2.0);

        let mut off_tray = Tray::seeded(11);
        let mut off_rng = crate::rng::GodotRng::new(0);
        let (epoch_0, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &vr_charge(), &small_board(),
            Seams { movement: true, versatile_reach: false, rules_epoch: 0, ..Seams::default() },
            &mut off_rng, &mut off_tray,
        )
        .unwrap();
        assert!(
            (vr_gap(&epoch_0) - 1.5).abs() < 1e-6,
            "epoch 0, knob false: still the plain 12\" rush band, got {:.3}\"",
            vr_gap(&epoch_0)
        );

        let mut on_tray = Tray::seeded(11);
        let mut on_rng = crate::rng::GodotRng::new(0);
        let (epoch_current, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &vr_charge(), &small_board(),
            Seams {
                movement: true, versatile_reach: false,
                rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Seams::default()
            },
            &mut on_rng, &mut on_tray,
        )
        .unwrap();
        assert!(
            vr_gap(&epoch_current) < 0.3,
            "rules_epoch: CURRENT_RULES_EPOCH, knob false: the +2\" bonus still lands in contact, gap {:.3}\"",
            vr_gap(&epoch_current)
        );
    }

    // ------------------------------------------------- BLOCK B5: Hit & Run ---

    /// A 6x4 ft school board (72" x 48"), the `terrain.rs` `school()` fixture's
    /// own shape, empty of cells — only `board_in` matters to `clamp_move_to_board`.
    fn small_board() -> crate::terrain::Terrain {
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells: vec![],
            sandbox: vec![],
            pieces: vec![],
            walls: vec![],
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    /// BLOCK B5 — a shot lands (`buff_line()`'s "a" vs "b" at 12"), and the
    /// bearer steps EXACTLY 3" directly AWAY from "b" (the only living enemy)
    /// on the SAME activation. Dice-free: the tray ends in the identical state
    /// whether the bearer carries the rule or not.
    #[test]
    fn hit_and_run_steps_three_inches_directly_away_from_the_nearest_enemy_after_a_shot_lands() {
        let (st, mut statics) = buff_line();
        let terrain = crate::terrain::Terrain::default();
        let action = buff_action(Some("b"));

        let mut base_tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            &statics, &st, &action, &terrain, Seams::default(), &mut rng, &mut base_tray,
        )
        .unwrap();

        statics[0].hit_and_run_active = true;
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(tray.state_i64(), base_tray.state_i64(), "Hit & Run draws no die");
        assert_eq!(next.hit_and_run_round[0], next.round);
        for (got, before) in next.positions[0].iter().zip(st.positions[0].iter()) {
            assert!((got[0] - (before[0] - 3.0 * IN2M as f64)).abs() < 1e-9, "got {got:?}");
            assert_eq!(got[2], before[2]);
        }
        // hero_attach is OFF by default: the attached "ah" is left behind.
        assert_eq!(next.positions[1], st.positions[1]);
    }

    /// The whole joined formation steps together when `hero_attach` is on —
    /// the same fold `resolve_with`'s own rigid move applies.
    #[test]
    fn hit_and_run_moves_the_joined_heros_formation_together_under_hero_attach() {
        let (st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        let terrain = crate::terrain::Terrain::default();
        let on = Seams { hero_attach: true, ..Seams::default() };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain, on, &mut rng, &mut tray,
        )
        .unwrap();
        assert!((next.positions[1][0][0] - (st.positions[1][0][0] - 3.0 * IN2M as f64)).abs() < 1e-9);
    }

    /// A DECLARED charge that falls short of contact (`buff_line`'s "b" stays
    /// 12" away, band 0) still fires Hit & Run: main.gd's own `hnr_attacked`
    /// is computed from `report["action"] == CHARGE` BEFORE `_run_ai_melee`
    /// runs, and never reset when the charge falls short — a table quirk,
    /// ported as found rather than silently tightened to "actually fought".
    #[test]
    fn hit_and_run_fires_after_a_declared_charge_that_falls_short_of_contact() {
        let (st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        let terrain = crate::terrain::Terrain::default();
        let charge = Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None,
        };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert!(shot.rolls.is_empty(), "the charge fell short — no melee, no dice at all");
        assert!((next.positions[0][0][0] - (st.positions[0][0][0] - 3.0 * IN2M as f64)).abs() < 1e-9);
        assert_eq!(next.hit_and_run_round[0], next.round);
    }

    /// RED for the fire gate, all built on the falls-short charge above (so
    /// `hnr_attacked` is true throughout and only the gate under test differs):
    /// without the rule, already spent this round, or no living enemy at all —
    /// every one leaves the bearer exactly where it started.
    #[test]
    fn hit_and_run_negative_cases() {
        let terrain = crate::terrain::Terrain::default();
        let charge = Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None,
        };

        // No bearer.
        let (st, statics) = buff_line();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[0], st.positions[0]);

        // Already spent this round.
        let (mut st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        st.hit_and_run_round[0] = st.round;
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[0], st.positions[0]);

        // No living enemy: "b" and "bh" both down.
        let (mut st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        st.alive[2] = 0;
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[0], st.positions[0]);

        // HOLD with no shoot key: `hnr_attacked` is false, the function is
        // never even called (unlike the cases above, which reach it and bail).
        let (st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(None), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[0], st.positions[0]);
    }

    /// The board clamp, wired end-to-end (not just `axis_scale`'s own pure-math
    /// proof, `the_reposition_axis_scale_clamps_to_the_board_edge`): a bearer
    /// 1" short of the board's left edge, kiting further left, lands EXACTLY on
    /// the edge instead of running 2" off it.
    #[test]
    fn hit_and_run_clamps_the_kiting_step_to_the_board_edge() {
        let (mut st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        st.positions[0] = vec![[-35.0 * IN2M, 0.0, 0.0], [-35.0 * IN2M, 0.0, 0.0]];
        st.positions[1] = vec![[-35.0 * IN2M, 0.0, 0.0]];
        st.positions[2] = vec![[0.0, 0.0, 0.0], [0.02 * IN2M, 0.0, 0.0], [0.04 * IN2M, 0.0, 0.0]];
        let board = small_board();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Board(&board), false);
        assert!((st.positions[0][0][0] - (-36.0 * IN2M)).abs() < 1e-6, "got {:?}", st.positions[0]);
        assert_eq!(st.hit_and_run_round[0], st.round);
    }

    /// S11 — the `forest_bar_board` forest mirrored onto the kiting side: unit
    /// 0's Hit & Run step runs from x≈0 straight to x≈-3" (away from "b" at
    /// x=12"), and cells (13,14)/(13,15) cover x in [-6",-3") — the corridor's
    /// far edge, the same near-landing relationship the S3 fixture has.
    fn kiting_forest_board() -> crate::terrain::Terrain {
        let cells = vec![[13.0, 14.0, crate::terrain::FOREST as f64],
                         [13.0, 15.0, crate::terrain::FOREST as f64]];
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells,
            sandbox: vec![],
            pieces: vec![],
            walls: vec![],
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    /// S11 — under `movement=table` the Hit & Run carrier lands through the
    /// SOLVER: on the mirrored forest the routed detour rests the models
    /// somewhere the rigid 3" translation never puts them, and the move names
    /// itself in the rules-must-log lines.
    #[test]
    fn hit_and_run_lands_through_the_solver_under_the_movement_seam() {
        let (st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        let t = kiting_forest_board();
        let action = buff_action(Some("b"));

        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (rigid, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &t, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (solved, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &t,
            Seams { movement: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert!(shot.log.iter().any(|l| l.contains("Hit & Run")), "rules-must-log: {:?}", shot.log);

        let gap_in = solved.positions[0]
            .iter()
            .zip(rigid.positions[0].iter())
            .map(|(a, b)| ((a[0] - b[0]).powi(2) + (a[2] - b[2]).powi(2)).sqrt() / IN2M as f64)
            .fold(0.0f64, f64::max);
        assert!(gap_in > 0.5, "the solver landed on the rigid answer, gap {gap_in}\"");
    }

    /// The RED for that routing: `move_rigid` puts the Hit & Run step back on
    /// the rigid arm with `movement` still on — the straight 3" translation to
    /// the digit, byte-identical to the seam-off run.
    #[test]
    fn the_move_rigid_red_returns_a_hit_and_run_step_to_the_straight_line() {
        let (st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        let t = kiting_forest_board();
        let action = buff_action(Some("b"));
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (rigid, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &t, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (red, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &t,
            Seams { movement: true, move_rigid: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(red.positions, rigid.positions);
    }

    /// The kiting anchor under the seam is the table's `_nearest_enemy_of`
    /// pick — plain nearest, NO activated preference: with an ACTIVATED enemy
    /// at 6" and an un-activated one at 12" the carrier steps away from the
    /// near one (the rigid arm keeps #485's pick and steps the other way).
    #[test]
    fn hit_and_run_kites_away_from_the_plain_nearest_enemy_under_the_seam() {
        let (mut st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        st.alive[3] = 1;
        st.positions[2] =
            vec![[6.0 * IN2M, 0.0, 0.0], [6.02 * IN2M, 0.0, 0.0], [6.04 * IN2M, 0.0, 0.0]];
        st.positions[3] = vec![[-12.0 * IN2M, 0.0, 0.0]];
        st.activated[2] = true;
        let board = small_board();
        let action = buff_action(Some("b"));
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (rigid, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &board, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (solved, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &board,
            Seams { movement: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        // Rigid: away from the un-activated "bh" at -12" -> +3" along +x.
        // Solved: away from the plain-nearest "b" at +6" -> 3" along -x.
        assert!((rigid.positions[0][0][0] - (st.positions[0][0][0] + 3.0 * IN2M as f64)).abs()
            < 1e-6, "rigid {:?}", rigid.positions[0]);
        assert!((solved.positions[0][0][0] - (st.positions[0][0][0] - 3.0 * IN2M as f64)).abs()
            < 1e-6, "solved {:?}", solved.positions[0]);
        assert_eq!(solved.hit_and_run_round[0], solved.round);
    }

    // -------------------------------------- block B7: Growth Markers ---

    /// `_solo_growth_round_start` main.gd:16984: +1 marker at this unit's own
    /// next activation, once per ROUND (a second call the same round is a
    /// no-op), blocked while Shaken (main.gd:17005-17009 — the round is still
    /// consumed, only the marker is not), capped at `max_markers`.
    #[test]
    fn growth_round_start_ticks_once_per_round_caps_and_blocks_while_shaken() {
        let mut st = four_unit_line();
        let mut statics = vec![UnitStatic::default()];
        statics[0].growth =
            vec![GrowthRule { per_round: true, max_markers: 2, ap_per_two: 1, ..Default::default() }];
        st.round = 1;
        growth_round_start(&statics, &mut st, 0, false);
        assert_eq!((st.growth_markers[0], st.growth_round[0]), (1, 1));

        growth_round_start(&statics, &mut st, 0, false); // same round: no-op
        assert_eq!(st.growth_markers[0], 1);

        st.round = 2;
        growth_round_start(&statics, &mut st, 0, true); // Shaken: round consumed, no marker
        assert_eq!((st.growth_markers[0], st.growth_round[0]), (1, 2));

        st.round = 3;
        growth_round_start(&statics, &mut st, 0, false);
        assert_eq!(st.growth_markers[0], 2, "cap reached");
        st.round = 4;
        growth_round_start(&statics, &mut st, 0, false);
        assert_eq!(st.growth_markers[0], 2, "capped: a further round earns nothing more");
    }

    /// `_solo_growth_on_kill` main.gd:17021: +1 marker per call, capped; a
    /// unit with no "on_kill" Growth Markers rule at all is untouched — the
    /// no-bearer negative.
    #[test]
    fn growth_on_kill_caps_and_ignores_a_non_carrier() {
        let mut st = four_unit_line();
        let mut statics = vec![UnitStatic::default()];
        statics[0].growth =
            vec![GrowthRule { on_kill: true, max_markers: 2, hit_per_marker: 1, ..Default::default() }];
        growth_on_kill(&statics, &mut st, 0);
        growth_on_kill(&statics, &mut st, 0);
        growth_on_kill(&statics, &mut st, 0);
        assert_eq!(st.growth_markers[0], 2, "capped at max_markers");

        let mut st2 = four_unit_line();
        let bare = vec![UnitStatic::default()];
        growth_on_kill(&bare, &mut st2, 0);
        assert_eq!(st2.growth_markers[0], 0, "no Growth Markers rule at all: untouched");
    }

    /// Integration, end to end through `resolve_with`/`resolve_stochastic_
    /// tray_on_board`: two HOLD activations bank a marker each (the per-round
    /// tick fires on the bearer's OWN activation, `growth_round` proving each
    /// round only ticked once), and the THIRD round's real shot already
    /// carries the AP those two rounds banked — the round/ledger replay proof.
    #[test]
    fn growth_ticks_through_resolve_with_and_then_shifts_the_next_shots_save() {
        let (mut st, mut statics) = buff_line();
        statics[0].growth =
            vec![GrowthRule { per_round: true, max_markers: 4, ap_per_two: 1, ..Default::default() }];
        let terrain = crate::terrain::Terrain::default();
        let mut rng = crate::rng::GodotRng::new(0);
        st.round = 1;
        let mut tray = Tray::seeded(11);
        let (next1, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(None), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!((next1.growth_markers[0], next1.growth_round[0]), (1, 1));

        let mut st2 = next1;
        st2.round = 2;
        let mut tray = Tray::seeded(12);
        let (next2, _) = resolve_stochastic_tray_on_board(
            &statics, &st2, &buff_action(None), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next2.growth_markers[0], 2, "each round ticks once — growth_round gates a repeat");

        let mut st3 = next2;
        st3.round = 3;
        // More attacks than `buff_line`'s plain 1 — guarantees at least one
        // hit lands (matching `a_volley_draws_hit_dice_then_one_save_batch_
        // of_exactly_the_hits`'s own seed-27/6-attack pairing), so the save
        // roll this assertion reads actually gets drawn.
        statics[0].shoot = vec![gun("Rifle", 20, 24)];
        let mut tray = Tray::seeded(27);
        let (_, shot) = resolve_stochastic_tray_on_board(
            &statics, &st3, &buff_action(Some("b")), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot.rolls[1].target, 5,
            "2 markers banked over 2 rounds -> AP(+1) on this round's shot (Defense 4+ becomes 5+)");
    }

    // ------------------------------------------------- block B8: Second Wind ---

    /// The table's own moment: the round would otherwise CLOSE right after
    /// this activation (`ah`/`b`/`bh` are all already spent), and the bearer
    /// carries the rule — it re-opens its OWN activation and clears fatigue,
    /// exactly `spend_second_wind` solo_controller.gd:10471-10479.
    #[test]
    fn second_wind_grants_a_second_activation_when_the_round_closes() {
        let (mut st, mut statics) = buff_line();
        statics[0].second_wind_active = true;
        st.activated = vec![false, true, true, true];
        st.fatigued[0] = true;
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(!next.activated[0], "Second Wind re-opens the bearer's own activation");
        assert!(!next.fatigued[0], "stops being fatigued when activated for the second time");
        assert!(next.second_wind_used[0]);
        assert_eq!((next.second_wind_round, next.second_wind_uses), (next.round, 1));
    }

    /// Negative: the round is NOT over yet ("b", alive, still un-activated) —
    /// no grant, even though the bearer would otherwise qualify.
    #[test]
    fn second_wind_does_not_fire_while_any_unit_can_still_activate() {
        let (mut st, mut statics) = buff_line();
        statics[0].second_wind_active = true;
        st.activated = vec![false, true, false, true]; // "b" (alive) still open
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(next.activated[0], "no second wind: 'a' stays activated from its own move alone");
        assert!(!next.second_wind_used[0]);
    }

    /// Negative: nobody on the table carries the rule — the round closes but
    /// nothing is granted.
    #[test]
    fn second_wind_no_candidate_without_the_rule() {
        let (mut st, statics) = buff_line();
        st.activated = vec![false, true, true, true];
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(next.activated[0]);
        assert!(!next.second_wind_used.iter().any(|&u| u));
    }

    /// Negative: ONCE PER GAME, not once per round — a bearer that already
    /// spent its Second Wind earlier is skipped even when it is the only
    /// carrier and the round genuinely closes.
    #[test]
    fn second_wind_is_once_per_game_not_once_per_round() {
        let (mut st, mut statics) = buff_line();
        statics[0].second_wind_active = true;
        st.second_wind_used[0] = true;
        st.activated = vec![false, true, true, true];
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(next.activated[0], "already spent — no second grant");
    }

    /// The army cap (`ceil(carriers / army_cap_fraction)`, solo_controller.gd:
    /// 10464): 2 unattached carriers on one side, `army_cap_fraction: 3` ->
    /// cap 1. The higher-`alive` carrier is picked first (the `_plan_ev_of +
    /// alive*0.1` stand-in), and a SECOND grant the same round is refused even
    /// though the other carrier is still eligible and unused.
    #[test]
    fn second_wind_caps_grants_per_round_at_ceil_carriers_over_the_fraction() {
        let (mut st, mut statics) = buff_line();
        st.player[2] = st.player[0]; // "b" joins "a"'s side for this fixture
        statics[0].second_wind_active = true;
        statics[2].second_wind_active = true;
        st.activated[0] = true;
        st.activated[2] = true;
        let picked = second_wind_candidate(&statics, &st, st.player[0]).expect("a candidate exists");
        assert_eq!(picked, 2, "\"b\" (alive 3) outranks \"a\" (alive 2)");
        spend_second_wind(&mut st, picked);
        assert!(
            second_wind_candidate(&statics, &st, st.player[0]).is_none(),
            "cap reached this round — \"a\" is still eligible and unused, but capped"
        );
    }

    /// The army cap resets on a NEW round: the same two carriers as above,
    /// "a" already spent in round 0 — round 1 opens a fresh cap and finds
    /// "b" (still unused).
    #[test]
    fn second_wind_round_cap_resets_on_a_new_round() {
        let (mut st, mut statics) = buff_line();
        st.player[2] = st.player[0];
        statics[0].second_wind_active = true;
        statics[2].second_wind_active = true;
        st.activated[0] = true;
        spend_second_wind(&mut st, 0); // round 0's one grant (cap = ceil(2/3) = 1)
        st.round += 1;
        st.activated[2] = true; // "b" enters round 1 already-activated, unused
        assert_eq!(second_wind_candidate(&statics, &st, st.player[0]), Some(2));
    }

    // -------------------------------------------- block B13: Retaliate(X) ---

    /// Block B13 fixture — unit 0 a 3x1-wound striker (Quality 4, one melee
    /// profile), unit 1 the defender (3x1 wounds, Defense 4) carrying
    /// `def_retaliate` as its `retaliate_hits_per_wound` (0 = rule absent).
    fn duel(def_retaliate: i64) -> (State, Vec<UnitStatic>) {
        let blade = ShootProfile { name: "Blade".into(), attacks: 8, count: 1, range: 0, ..Default::default() };
        let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
        let statics = vec![
            UnitStatic {
                ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 3, ..Default::default() },
                name: "Striker".into(),
                melee: vec![blade],
                model_count: 3,
                wounds_max: vec![1, 1, 1],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { defense: 4, tough: 1, models: 3, retaliate_hits_per_wound: def_retaliate, ..Default::default() },
                name: "Target".into(),
                model_count: 3,
                wounds_max: vec![1, 1, 1],
                ..Default::default()
            },
        ];
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "b".into()],
            index: HashMap::new(),
            profile: vec![0, 1],
        });
        st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
        st.player = vec![0, 1];
        st.alive = vec![3, 3];
        st.attached = Rc::new(vec![vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None]);
        st.positions[0] = vec![[0.0, 0.0, 0.0], [0.8, 0.0, 0.0], [1.2, 0.0, 0.0]];
        st.wounds[0] = vec![1, 1, 1];
        st.radii[0] = vec![IN2M, IN2M, IN2M];
        st.positions[1] = vec![[2.0, 0.0, 0.0], [3.0, 0.0, 0.0], [4.0, 0.0, 0.0]];
        st.wounds[1] = vec![1, 1, 1];
        st.radii[1] = vec![IN2M, IN2M, IN2M];
        (st, statics)
    }

    // -------------------------------------------- W2 S0: melee_reach="table" ---

    /// A 10-model line, one inch apart, striking a single enemy model planted
    /// at the head of the line: only the first three sit within the p.9 2"
    /// reach (+1" base contact = 3" centre-space, `combat::MELEE_REACH_IN`/
    /// `BASE_CONTACT_IN`). `melee_reach` OFF (the default) is unaffected —
    /// today's behaviour scales by the whole unit's `alive` count.
    #[test]
    fn melee_reach_table_scales_by_the_models_within_2in_of_the_enemy() {
        let blade = ShootProfile { name: "Blade".into(), attacks: 10, count: 1, range: 0, ..Default::default() };
        let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
        let statics = vec![
            UnitStatic {
                ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 10, ..Default::default() },
                name: "Line".into(),
                melee: vec![blade],
                model_count: 10,
                wounds_max: vec![1; 10],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
                name: "Target".into(),
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
        ];
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
        st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
        st.player = vec![0, 1];
        st.alive = vec![10, 1];
        st.attached = Rc::new(vec![vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None]);
        st.positions[0] = (1..=10).map(|i| [i as f64 * IN2M, 0.0, 0.0]).collect();
        st.wounds[0] = vec![1; 10];
        st.radii[0] = vec![IN2M; 10];
        st.positions[1] = vec![[0.0, 0.0, 0.0]];
        st.wounds[1] = vec![1];
        st.radii[1] = vec![IN2M];

        let all = melee_parts(&statics, &st, 0, 1, Seams::default());
        assert_eq!(all[0].1.attacks[0], 10, "melee_reach=all (default): every model strikes");

        let table = Seams { melee_reach: true, ..Seams::default() };
        let reached = melee_parts(&statics, &st, 0, 1, table);
        assert_eq!(reached[0].1.attacks[0], 3, "melee_reach=table: only the 3 models within 2\" strike");
    }

    /// Retaliate(2) against 3 wounds LANDED = the striker faces a 6-die save
    /// batch at its own Defense, AP 0; the wounds land on the striker, the
    /// credit is the UNSAVED count, and the caller hands it to the defender's
    /// tally (main.gd:6146-6171).
    #[test]
    fn retaliate_throws_two_hits_per_wound_landed_at_the_striker() {
        let (mut st, statics) = duel(2);
        let def_pool = wounds_left(&st, 1);
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        let (caused, credit) = strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        let landed = def_pool - wounds_left(&st, 1);
        assert_eq!(landed, 3, "fixture: seed 9 lands exactly 3 wounds (got {landed})");
        assert!(caused >= landed, "the tally is the PRE-Regeneration count");
        let lash = shot.rolls.last().expect("the lash-back save batch");
        assert_eq!((lash.kind, lash.count, lash.owner.as_str()), ("defense", 6, "Striker"));
        assert_eq!(lash.target, 4, "the striker's own Defense 4+, AP 0");
        assert_eq!(credit, lash.faces.iter().filter(|&&f| f < 4).count() as i64,
            "the credit is the unsaved count the caller gives the defender's tally");
        assert!(wounds_left(&st, 0) < 3, "the retaliation wounds LAND on the striker");
        assert_eq!(shot.log.last().map(String::as_str),
            Some("Retaliate: Target lashes back — 6 hits"), "the rules-must-log line");
    }

    /// The same strike WITHOUT the rule: no lash-back batch, no log line —
    /// the tray stands exactly where the phase's own draws left it.
    #[test]
    fn without_the_rule_no_extra_rolls_and_no_log() {
        let (mut st, statics) = duel(0);
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        let (_, credit) = strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        assert_eq!(credit, 0, "nothing to credit");
        assert!(shot.log.iter().all(|l| !l.contains("Retaliate")), "nothing logged");
        assert!(shot.rolls.iter().all(|r| !(r.kind == "defense" && r.owner == "Striker")),
            "the striker never rolls a save when the defender carries no Retaliate");
    }

    /// NON-CHAINING (main.gd:6155): the lash lands through `land_wounds`
    /// alone, never through another strike phase — a striker that ITSELF
    /// carries Retaliate(2) does not answer the defender's lash-back.
    #[test]
    fn retaliation_wounds_never_trigger_the_strikers_own_retaliate() {
        let (mut st, mut statics) = duel(2);
        statics[0].ctx.retaliate_hits_per_wound = 2;
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        let striker_saves = shot.rolls.iter().filter(|r| r.kind == "defense" && r.owner == "Striker").count();
        let defender_saves = shot.rolls.iter().filter(|r| r.kind == "defense" && r.owner == "Target").count();
        assert_eq!(striker_saves, 1, "exactly the defender's lash-back batch");
        assert_eq!(defender_saves, 1, "the strike's own save batch — no chained counter-lash");
    }

    // ------------------- block C4: Deathstrike / Self-Destruct, death-half ---

    /// (a) Deathstrike(2) on the defender, the phase lands 4 wounds into
    /// pools [1,3,1]: the two outer models die, the middle survives on 1
    /// wound left — the striker faces a 4-die save batch at its own Defense,
    /// AP 0, the lash lands on the striker, and the returned TALLY credit
    /// stays 0 (main.gd:6174 touches no `_solo_retaliate_credit`).
    #[test]
    fn deathstrike_throws_two_hits_per_killed_model_at_the_striker() {
        let (mut st, mut statics) = duel(0);
        statics[1].ctx.death_hits_per_kill = 2;
        st.wounds[1] = vec![1, 3, 1]; // seed 9 lands 4: exactly the outer two die
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        let (_, credit) = strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        assert_eq!(st.alive[1], 1, "fixture: exactly the two outer models die");
        let lash = shot.rolls.last().expect("the dying-models save batch");
        assert_eq!((lash.kind, lash.count, lash.owner.as_str()), ("defense", 4, "Striker"));
        assert_eq!(lash.target, 4, "the striker's own Defense 4+, AP 0");
        assert!(wounds_left(&st, 0) < 3, "the lash lands on the striker");
        assert_eq!(credit, 0, "no tally credit — :6174 never touches _solo_retaliate_credit");
        assert_eq!(shot.log.last().map(String::as_str),
            Some("Deathstrike/Self-Destruct: Target's dying models lash out — Striker takes 4 hits"),
            "the rules-must-log line");
    }

    /// (b) Deathstrike(2) but NO model dies: the 4 landed wounds soak into
    /// pools [5,1,1] and every model survives — nothing lashes back, no log
    /// line. RED when the `killed > 0` guard goes: the block would fire for
    /// `death_hits_per_kill * 0` and push a "…— 0 hits" line.
    #[test]
    fn deathstrike_lashes_nothing_when_no_model_is_lost() {
        let (mut st, mut statics) = duel(0);
        statics[1].ctx.death_hits_per_kill = 2;
        st.wounds[1] = vec![5, 1, 1]; // 4 wounds soak into the first model
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        let (_, credit) = strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        assert_eq!(st.alive[1], 3, "fixture: 3 wounds soak, no model dies");
        assert_eq!(credit, 0, "nothing to credit");
        assert!(shot.log.iter().all(|l| !l.contains("dying models")), "nothing logged");
        assert!(shot.rolls.iter().all(|r| !(r.kind == "defense" && r.owner == "Striker")),
            "the striker never rolls a save when no model is lost");
    }

    /// (c) The dying lash is NOT a Retaliate: even with the lash landing on
    /// the striker, the returned tally credit stays exactly what the Retaliate
    /// block left it (0 here) — main.gd:6174 runs `_solo_deathstrike_hits`
    /// without touching `_solo_retaliate_credit`. RED the moment the credit
    /// line is copied over from the Retaliate block.
    #[test]
    fn deathstrike_lash_never_touches_the_retaliate_credit() {
        let (mut st, mut statics) = duel(0);
        statics[1].ctx.death_hits_per_kill = 2;
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        let (_, credit) = strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        assert!(shot.rolls.iter().any(|r| r.kind == "defense" && r.owner == "Striker"),
            "fixture: the lash DID fire (pools [1,1,1] lose all three models)");
        assert!(wounds_left(&st, 0) < 3, "the lash landed on the striker");
        assert_eq!(credit, 0, "the tally is the Retaliate credit — untouched by Deathstrike");
    }

    // ---------------------------------------------- block C5: Instinctive ---

    /// Block C5 fixture — unit 0 the 1-model Instinctive carrier (Quality 4,
    /// one 8-dice melee profile), unit 1 the target 10" away, unit 2 a SECOND
    /// enemy at `third_at` (9" = the forfeit case, 9.5" = the half-inch band's
    /// own boundary), unit 3 a far bystander so no per-unit vector moves.
    fn instinctive_line(third_at: f64) -> (State, Vec<UnitStatic>) {
        let blade = ShootProfile {
            name: "Blade".into(),
            attacks: 8,
            count: 1,
            range: 0,
            ..Default::default()
        };
        let profile: Profile =
            serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
        let statics = vec![
            UnitStatic {
                ctx: Ctx {
                    quality: 4,
                    defense: 4,
                    tough: 1,
                    models: 1,
                    instinctive_hit_bonus: 1,
                    ..Default::default()
                },
                name: "Striker".into(),
                melee: vec![blade],
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
                name: "Target".into(),
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
                name: "Rival".into(),
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
        ];
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "b".into(), "c".into(), "d".into()],
            index: HashMap::new(),
            profile: vec![0, 1, 2, 2],
        });
        st.profiles = Rc::new(Profiles {
            list: vec![profile.clone(), profile.clone(), profile.clone(), profile],
            index: HashMap::new(),
        });
        st.player = vec![0, 1, 1, 1];
        st.alive = vec![1, 1, 1, 1];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.positions[0] = vec![[0.0, 0.0, 0.0]];
        st.positions[1] = vec![[10.0 * IN2M, 0.0, 0.0]];
        st.positions[2] = vec![[third_at, 0.0, 0.0]];
        st.positions[3] = vec![[20.0 * IN2M, 0.0, 0.0]];
        (st, statics)
    }

    /// The striker's first "attack" batch after one strike phase — the melee
    /// hit roll's modified target is the number the rule moves.
    fn striker_hit_target(third_at: f64) -> i64 {
        let (mut st, statics) = instinctive_line(third_at);
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        shot.rolls
            .iter()
            .find(|r| r.kind == "attack" && r.owner == "Striker")
            .expect("the striker's hit batch")
            .target
    }

    /// (a) A carrier attacking the CLOSEST enemy hits on one better — the +1
    /// rides the strike phase's `hit_mod` fold to the melee hit target.
    #[test]
    fn instinctive_hits_one_better_when_the_target_is_the_closest_enemy() {
        assert_eq!(striker_hit_target(12.0 * IN2M), 3, "Quality 4 + Instinctive's +1");
    }

    /// (b) A second enemy 1" closer forfeits the +1 — the pick stands, the
    /// hit target falls back to the plain Quality (main.gd:5792-5793).
    #[test]
    fn instinctive_is_forfeited_when_a_second_enemy_is_closer() {
        assert_eq!(striker_hit_target(9.0 * IN2M), 4, "a rival 1\" inside the target");
    }

    /// (c) The half-inch band's own boundary: a rival at EXACTLY d - 0.5" is
    /// a tie, not closer — the bonus stands. RED when the band is written
    /// `<=` instead of `<`, or the half inch is dropped.
    #[test]
    fn instinctive_survives_a_rival_on_the_half_inch_band_boundary() {
        assert_eq!(striker_hit_target(9.5 * IN2M), 3, "9.5\" ties inside the band");
    }

    // ================================================ mutant-killing tests ====

    // ------------------------------------------ block B3: the breath score ---

    /// One bearer (unit 0, Breath Attack) facing two enemies on the x axis:
    /// "Alpha" (unit 1: 3 alive, Defense 3) and "Bravo" (unit 2: 2 alive,
    /// Defense 5); unit 3 is a dead bystander. Base-edge gaps 3" and 4", both
    /// inside the 6" breath range, LOS clear (`los_pairs` carries no matrix).
    /// Scores: Alpha `3 · 1/2 = 1.5`, Bravo `2 · 5/6 ≈ 1.67` — Bravo wins.
    fn breath_scorer_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.player = vec![0, 1, 1, 1];
        st.alive = vec![1, 3, 2, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.positions[1] = vec![[5.0 * IN2M, 0.0, 0.0]];
        st.positions[2] = vec![[6.0 * IN2M, 0.0, 0.0]];
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: HashMap::new(),
            profile: vec![0, 1, 2, 2],
        });
        let bearer = UnitStatic {
            name: "Bearer".into(),
            breath_attack_active: true,
            ..Default::default()
        };
        let alpha = UnitStatic {
            name: "Alpha".into(),
            ctx: Ctx { defense: 3, ..Default::default() },
            ..Default::default()
        };
        let bravo = UnitStatic {
            name: "Bravo".into(),
            ctx: Ctx { defense: 5, ..Default::default() },
            ..Default::default()
        };
        (st, vec![bearer, alpha, bravo])
    }

    /// Fires one breath activation at seed 5 (whose first face, the trigger
    /// die, is a 6) and reports who ate the save batch — the signature of the
    /// unit the scorer picked.
    fn breath_save_owner(statics: &[UnitStatic], st: &mut State) -> String {
        let mut shot = ShootResult::default();
        let mut tray = Tray::seeded(5);
        tray_breath_attack(statics, st, 0, Seams::default(), &mut tray, &mut shot);
        shot.rolls.iter().find(|r| r.kind == "defense")
            .map(|r| r.owner.clone())
            .unwrap_or_default()
    }

    /// The score is `min(Blast, alive) * (1 - block)`: a PRODUCT, so Alpha's
    /// 1.5 loses to Bravo's 1.67. Turning the multiply into a plus gives
    /// Alpha 3.5 against 2.83 — the pick flips and the save batch is signed
    /// "Alpha". Seed 5: the trigger die passes.
    #[test]
    fn the_breath_score_is_a_product_never_a_sum() {
        let (mut st, statics) = breath_scorer_line();
        assert_eq!(breath_save_owner(&statics, &mut st), "Bravo");
    }

    /// Same identity, quotient form: `min(Blast, alive) / (1 - block)` scores
    /// Alpha 6 against Bravo 2.4 — again the wrong unit signs the saves.
    #[test]
    fn the_breath_score_is_a_product_never_a_quotient() {
        let (mut st, statics) = breath_scorer_line();
        assert_eq!(breath_save_owner(&statics, &mut st), "Bravo");
    }

    /// The block chance is SUBTRACTED from one: `1 - block` discounts Alpha
    /// by half. `1 + block` inflates it to 1.5 and Alpha's 4.5 beats Bravo's
    /// 2.33 — the pick flips, the owner betrays it.
    #[test]
    fn the_breath_score_subtracts_the_block_chance_never_adds() {
        let (mut st, statics) = breath_scorer_line();
        assert_eq!(breath_save_owner(&statics, &mut st), "Bravo");
    }

    /// And never divides: `1 / block` AMPLIFIES the low-block unit — Alpha
    /// (2 alive, Defense 3: `2·1/2 = 1.0`, mutant `2·2 = 4`) must keep the
    /// pick against Bravo (1 alive, Defense 5: `1·5/6 ≈ 0.83`, mutant
    /// `1·6 = 6`), whose save batch then signs the wrong name.
    #[test]
    fn the_breath_score_uses_one_minus_block_never_one_over_block() {
        let (mut st, mut statics) = breath_scorer_line();
        st.alive[1] = 2;
        st.alive[2] = 1;
        assert_eq!(breath_save_owner(&statics, &mut st), "Alpha");
    }

    /// Two EQUAL scores (2 alive, Defense 3 each → 1.0 both) must keep the
    /// FIRST unit the scan met. A `>=` lets the later twin overwrite it.
    #[test]
    fn the_breath_pick_takes_the_first_of_equal_scores() {
        let (mut st, mut statics) = breath_scorer_line();
        st.alive[1] = 2;
        statics[2].ctx.defense = 3;
        assert_eq!(breath_save_owner(&statics, &mut st), "Alpha");
    }

    /// One breath PER ACTIVATION needs a LIVING bearer: a joined hero that
    /// carries the rule but is dead (alive 0) must not earn the trigger die
    /// for the flagless host. A `>=` on the bearer's alive check lets the
    /// corpse speak — a die lands on the tray anyway.
    #[test]
    fn a_dead_joined_bearer_earns_no_breath_die() {
        let (mut st, mut statics) = breath_scorer_line();
        statics[0].breath_attack_active = false;
        statics.push(UnitStatic {
            name: "Dead Hero".into(),
            breath_attack_active: true,
            ..Default::default()
        });
        st.player[1] = 0;
        st.alive[1] = 0;
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: HashMap::new(),
            profile: vec![0, 3, 2, 2],
        });
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        let mut shot = ShootResult::default();
        let mut tray = Tray::seeded(5);
        tray_breath_attack(
            &statics, &mut st, 0,
            Seams { hero_attach: true, ..Seams::default() },
            &mut tray, &mut shot,
        );
        assert!(shot.rolls.is_empty(), "no living bearer, no breath die: {:?}", shot.rolls);
    }

    /// With the hero fold OFF, the target scan must still consider an enemy
    /// that is somebody's attached hero — `hero_attach && attached` only
    /// skips them under the seam. An `||` skips them always, and with Bravo
    /// dead the scan finds no target at all: no die is ever drawn.
    #[test]
    fn with_the_seam_off_an_attached_enemy_is_still_a_breath_target() {
        let (mut st, statics) = breath_scorer_line();
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        st.alive[2] = 0;
        let mut shot = ShootResult::default();
        let mut tray = Tray::seeded(5);
        tray_breath_attack(&statics, &mut st, 0, Seams::default(), &mut tray, &mut shot);
        assert!(
            shot.rolls.iter().any(|r| r.kind == "attack"),
            "the trigger die is drawn at the attached enemy: {:?}", shot.rolls
        );
    }

    // ------------------------------------------- block B5: hit & run ---

    /// A Hit & Run host (unit 0) with an enemy due south (unit 3, 9" centre
    /// to centre on the z axis) — the only live enemy, so the flee direction
    /// is exactly [0, -1] and the 3" step lands at z = -3" in metres.
    fn har_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.positions[3] = vec![[0.0, 0.0, 9.0 * IN2M]];
        let host = UnitStatic {
            name: "Fleer".into(),
            hit_and_run_active: true,
            ..Default::default()
        };
        (st, vec![host])
    }

    /// `len` is the pythagorean SUM `dx² + dz²`: with dx = 0 it is |dz|, so
    /// the normalized direction is exactly [0, -1] and the unit ends 3" from
    /// where it started. `dx² - dz²` is negative here — NaN poisons every
    /// later step and the unit never arrives.
    #[test]
    fn the_flee_length_is_a_pythagorean_sum_never_a_difference() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// Each delta is SQUARED, not doubled: `dz + dz` over a negative dz is
    /// negative, sqrt gives NaN — no 3" step ever lands.
    #[test]
    fn the_flee_length_squares_each_delta_never_doubles_one() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// The zero-length guard at EXACTLY the boundary: a 1e-6 m gap measures
    /// as len == 1e-6 (f32), which is NOT less than the 1e-6 threshold — the
    /// unit must still flee. An `==` guard returns on the boundary value.
    #[test]
    fn a_hair_gap_is_measured_not_guarded_away() {
        let (mut st, statics) = har_line();
        st.positions[3] = vec![[0.0, 0.0, 1e-6f32 as f64]];
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// Same boundary, `<=` form: 1e-6 <= 1e-6 returns too. The original
    /// strictly-below guard lets the hair-gap through and the step lands.
    #[test]
    fn a_gap_at_the_guard_boundary_still_flees() {
        let (mut st, statics) = har_line();
        st.positions[3] = vec![[0.0, 0.0, 1e-6f32 as f64]];
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// The direction DIVIDES dz by len: -9a/9a = -1, a unit vector. A
    /// remainder `-9a % 9a` is -0 — the unit stands still instead of fleeing.
    #[test]
    fn the_flee_direction_divides_the_delta_never_takes_a_remainder() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
        assert_eq!(st.positions[0][0][0], 0.0, "no sideways drift");
    }

    /// And never multiplies: dz·len ≈ -0.0522 m of "direction" drags the
    /// step to a crawl (≈ 4 mm) instead of the full 3".
    #[test]
    fn the_flee_direction_normalizes_to_a_unit_vector() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// The step is ADDED to the position, moving AWAY from the enemy (dir z
    /// is -1): `p[2] += -step`. A `-=` walks TOWARD the enemy (+step).
    #[test]
    fn the_flee_step_moves_away_from_the_enemy() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// `+=` never becomes `*=`: 0 · step is still 0 and the host never moves.
    #[test]
    fn the_flee_step_is_added_never_multiplied_in() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// dir · step_m is the metres-per-inch conversion: (-1)·3" = -0.0762 m.
    /// A division (-1)/0.0762 ≈ -13.1 hurls the unit 13 metres south.
    #[test]
    fn the_flee_step_scales_the_direction_by_the_inches() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// The hero fold moves the joined hero by the SAME away-step: the hero
    /// sits 2" east on the x line, so its z (0) ends at -3". A `-=` walks
    /// the hero INTO the enemy (+step).
    #[test]
    fn the_joined_hero_flees_away_with_the_host() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(
            &statics, &mut st, 0,
            Seams { hero_attach: true, ..Seams::default() },
            Cover::Recorded(None),
            false,
        );
        assert_eq!(st.positions[1][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// `*=` on the hero's position scales its z (0) by step — 0 stays 0 and
    /// the hero never moves, instead of taking the fold's away-step.
    #[test]
    fn the_heros_flee_step_is_added_never_multiplied_in() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(
            &statics, &mut st, 0,
            Seams { hero_attach: true, ..Seams::default() },
            Cover::Recorded(None),
            false,
        );
        assert_eq!(st.positions[1][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// dir·step in the hero loop too: dir + step ≈ -0.92 m of step.
    #[test]
    fn the_heros_flee_step_scales_the_direction_by_the_inches() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(
            &statics, &mut st, 0,
            Seams { hero_attach: true, ..Seams::default() },
            Cover::Recorded(None),
            false,
        );
        assert_eq!(st.positions[1][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    /// And dir/step ≈ -13.1 m — the hero teleports instead of fleeing 3".
    #[test]
    fn the_heros_flee_direction_stays_a_unit_vector() {
        let (mut st, statics) = har_line();
        tray_hit_and_run(
            &statics, &mut st, 0,
            Seams { hero_attach: true, ..Seams::default() },
            Cover::Recorded(None),
            false,
        );
        assert_eq!(st.positions[1][0][2], -(3.0f32 * (IN2M as f32)) as f64);
    }

    // -------------------------------- block C1: the two half-primitives ---

    /// A carrier with NEITHER the full "Hit & Run" gate NOR a half set yet —
    /// enemy 9" due south (the flee anchor), same geometry as `har_line` — so
    /// each test turns on exactly one flag and one trigger side.
    fn hnr_half_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.positions[3] = vec![[0.0, 0.0, 9.0 * IN2M]];
        (st, vec![UnitStatic { name: "Kiter".into(), ..Default::default() }])
    }

    /// (a) solo_controller.gd:9667 — a "Hit & Run Shooter" carrier that SHOT
    /// (`after_shoot = true`) kites 3" away from the nearest enemy and takes
    /// the shared per-round stamp (:9685), though the full "Hit & Run" gate
    /// would refuse it (no full-rule name on the profile).
    #[test]
    fn a_shooter_carrier_that_shot_steps_3_inches_and_stamps_the_round() {
        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_shooter_active = true;
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), true);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);
        assert_eq!(st.hit_and_run_round[0], st.round);
    }

    /// (b) THE RED — the same Shooter carrier after a CHARGE is on the WRONG
    /// half (the table's pick is `"Hit & Run Shooter" if after_shoot else
    /// "Hit & Run Fighter"`, :9667): no step, no stamp. This is the test that
    /// fails the moment the `after_shoot` gate is dropped.
    #[test]
    fn a_shooter_carrier_after_a_charge_is_on_the_wrong_half() {
        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_shooter_active = true;
        let before = st.positions[0].clone();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0], before);
        assert_eq!(st.hit_and_run_round[0], -1);
    }

    /// (c) the mirror: a "Hit & Run Fighter" carrier moves after a CHARGE
    /// (the melee leg, `after_shoot = false`) and does NOT after a shot —
    /// each half fires on its own trigger and its own EXACT name only.
    #[test]
    fn a_fighter_carrier_moves_after_a_charge_never_after_a_shot() {
        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_fighter_active = true;
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), false);
        assert_eq!(st.positions[0][0][2], -(3.0f32 * (IN2M as f32)) as f64);

        let (mut st, mut statics) = hnr_half_line();
        statics[0].hit_and_run_fighter_active = true;
        let before = st.positions[0].clone();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Recorded(None), true);
        assert_eq!(st.positions[0], before);
        assert_eq!(st.hit_and_run_round[0], -1);
    }

    // ---------------------------------------- block B8: second wind ---

    /// The candidate scan's SKIPS: an attached hero of the acting side is
    /// never a candidate even when activated and unused — the `||` chain at
    /// the gate must not collapse into an `&&` that lets the hero through.
    #[test]
    fn an_attached_hero_is_never_the_second_wind_candidate() {
        let (mut st, mut statics) = buff_line();
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        statics[1].second_wind_active = true;
        st.activated[1] = true;
        assert_eq!(second_wind_candidate(&statics, &st, 0), None);
    }

    /// Nor is an ENEMY unit, however eligible it looks: the player mismatch
    /// alone skips it. An `&&` there lets a fresh enemy carrier be picked.
    #[test]
    fn an_enemy_unit_is_never_the_second_wind_candidate() {
        let (mut st, mut statics) = buff_line();
        statics[2].second_wind_active = true;
        st.activated[2] = true;
        assert_eq!(second_wind_candidate(&statics, &st, 0), None);
    }

    /// The pick is strictly-greater: two carriers at 2 alive each, the FIRST
    /// wins. A `>=` lets the later equal twin overwrite the pick.
    #[test]
    fn two_equal_carriers_pick_the_first_not_the_last() {
        let (mut st, mut statics) = buff_line();
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        statics[0].second_wind_active = true;
        statics[1].second_wind_active = true;
        st.alive[1] = st.alive[0];
        st.activated[0] = true;
        st.activated[1] = true;
        assert_eq!(second_wind_candidate(&statics, &st, 0), Some(0));
    }

    /// The round cap: ceil(3 carriers / 3) = 1 grant, so one spent use
    /// exhausts the round. Turning the `- 1` into a `/ 1` inflates the cap
    /// to 2 and hands out a second activation.
    #[test]
    fn one_spent_grant_exhausts_a_three_carrier_round() {
        let (mut st, mut statics) = buff_line();
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.player[2] = 0; // a third carrier joins the acting side
        statics[0].second_wind_active = true;
        statics[1].second_wind_active = true;
        statics[2].second_wind_active = true;
        st.activated[0] = true;
        st.activated[1] = true;
        st.second_wind_used[1] = true; // spent, but still a carrier for the cap
        st.second_wind_round = st.round;
        st.second_wind_uses = 1;
        assert_eq!(second_wind_candidate(&statics, &st, 0), None);
    }

    // ------------------------------------ block B7: the growth bonus ---

    /// One four-unit line whose profile 0 carries a Growth Markers rule at
    /// the registry's two-rate shape and unit 0 holding `markers` markers.
    /// At 4 markers the exact bonus is ap `2·4 + 5·(4/2) = 18`, hit
    /// `1·4 + 3·(4/2) = 10`.
    fn growth_line(markers: i64) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.growth_markers = vec![markers, 0, 0, 0];
        let rule = GrowthRule {
            name: "Test Growth".into(),
            ap_per_marker: 2,
            ap_per_two: 5,
            hit_per_marker: 1,
            hit_per_two: 3,
            ..Default::default()
        };
        (st, vec![UnitStatic { growth: vec![rule], ..Default::default() }])
    }

    /// The bonus is COMPUTED from the markers: zero markers, zero bonus —
    /// and four markers is the exact (18, 10), not a constant (1, 0).
    #[test]
    fn the_growth_bonus_is_computed_never_constant() {
        let (st, statics) = growth_line(0);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (0, 0), "no markers, no bonus");
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The AP per-marker rate MULTIPLIES the marker count: 2 · 4, not 2 / 4.
    #[test]
    fn the_ap_rate_multiplies_the_markers() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The AP per-two rate MULTIPLIES the pair count: 5 · 2, not 5 / 2.
    #[test]
    fn the_ap_pair_rate_multiplies_the_pairs() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The pair count HALVES the markers: 4 / 2 = 2 pairs, not 4 % 2 = 0.
    #[test]
    fn the_ap_pair_count_halves_the_markers() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The AP term ACCUMULATES by addition from zero: `-=` would leave -18.
    #[test]
    fn the_ap_bonus_accumulates_by_addition() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// And addition, not multiplication: 0 · 18 stays 0 — no bonus at all.
    #[test]
    fn the_ap_bonus_starts_at_zero_and_adds() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The two hit facets ADD together: 4 + 6 = 10, not 4 - 6 = -2.
    #[test]
    fn the_hit_facets_add_together() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// Addition, not multiplication: 4 · 6 = 24 is not the hit bonus.
    #[test]
    fn the_hit_facets_add_never_multiply() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The hit per-marker rate MULTIPLIES the markers: 1 · 4, not 1 + 4.
    #[test]
    fn the_hit_rate_multiplies_the_markers() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// Nor divides: 1 / 4 = 0 — the markers would count for nothing.
    #[test]
    fn the_hit_rate_divides_nothing() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The hit per-two rate MULTIPLIES the pairs: 3 · 2, not 3 + 2.
    #[test]
    fn the_hit_pair_rate_multiplies_the_pairs() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// Nor divides: 3 / 2 = 1 pair's worth instead of 2.
    #[test]
    fn the_hit_pair_count_halves_the_markers() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// The hit pair count HALVES the markers: 4 / 2, not 4 % 2 (zero).
    #[test]
    fn the_hit_pair_count_is_a_half_never_a_remainder() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    /// And never doubles: 4 · 2 = 8 pairs would hand out 24 hit, not 6.
    #[test]
    fn the_hit_pair_count_is_a_half_never_a_double() {
        let (st, statics) = growth_line(4);
        assert_eq!(growth_bonus_of(&statics, &st, 0), (18, 10));
    }

    // ---------------------------------------------- S10: dest-side arms ----

    /// S10 fixture on the four-unit line: unit 0 "a" (player 0, one 24" gun)
    /// at (30", 24") on the 72x48 board, unit 2 "b" (player 1) 20" east, unit
    /// 3 out of the way, one neutral marker 5" east of "a".
    fn s10_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "ah".into(), "b".into(), "bh".into()],
            index: ["a", "ah", "b", "bh"]
                .iter()
                .enumerate()
                .map(|(i, k)| (k.to_string(), i))
                .collect(),
            profile: vec![0, 0, 0, 0],
        });
        st.positions[0] = vec![[30.0 * IN2M, 0.0, 24.0 * IN2M]];
        st.positions[1] = vec![[30.0 * IN2M, 0.0, 30.0 * IN2M]];
        st.positions[2] = vec![[50.0 * IN2M, 0.0, 24.0 * IN2M]];
        st.positions[3] = vec![[2.0 * IN2M, 0.0, 46.0 * IN2M]];
        st.objectives =
            vec![crate::state::Objective { pos: [35.0 * IN2M, 0.0, 24.0 * IN2M], owner: -1 }];
        let mut shooter = UnitStatic { name: "a".into(), ..Default::default() };
        shooter.shoot =
            vec![ShootProfile { name: "gun".into(), range: 24, ..Default::default() }];
        (st, vec![shooter])
    }

    /// S10-a — the in-range shooter's kite: 20" from a 24" gun with a 6"
    /// Advance grants exactly min(6, 24 - 20 - 0.25) = 3.75", aimed at the
    /// enemy centre MIRRORED through the mover; an enemy inside the 0.25"
    /// range-edge margin floors the step and the table stands still.
    #[test]
    fn s10_kite_grants_the_tables_distance_and_aims_away() {
        let (st, statics) = s10_line();
        let centre = geom::centre(&st.positions[0]);
        // 100" due west OF THE UNIT: the retreat candidate's own dest shape
        let dest = [(30.0 - RETREAT_GOAL_IN) * IN2M, 0.0, 24.0 * IN2M];
        let mut hold = false;
        let (goal, band) = s10_dest_arms(&statics, &st, 0, ADVANCE, dest, 6.0, &mut hold);
        assert!(!hold);
        assert!((band - 3.75).abs() < 1e-4);
        assert!((goal[0] - (centre[0] as f64 - 20.0 * IN2M)).abs() < 1e-5);
        let mut st2 = st.clone();
        st2.positions[2] = vec![[(30.0 + 23.9) * IN2M, 0.0, 24.0 * IN2M]];
        let mut hold2 = false;
        let (_, band2) = s10_dest_arms(&statics, &st2, 0, ADVANCE, dest, 6.0, &mut hold2);
        assert!(hold2 && band2 == 0.0);
    }

    /// S10-b — the goal stop: a RUSH whose dest IS a marker is granted
    /// min(band, goal_dist) (12" band, marker 5" away -> 5"); a dest that is
    /// no marker (the toward-enemy else-branch) keeps the full band.
    #[test]
    fn s10_goal_stop_ends_the_move_at_the_marker() {
        let (st, statics) = s10_line();
        let marker = st.objectives[0].pos;
        let mut hold = false;
        let (dest, band) = s10_dest_arms(&statics, &st, 0, RUSH, marker, 12.0, &mut hold);
        assert!(!hold);
        assert!((band - 5.0).abs() < 1e-4);
        assert_eq!(dest, marker);
        let enemy_centre = [(30.0 + 20.0) * IN2M, 0.0, 24.0 * IN2M];
        let (_, band_far) = s10_dest_arms(&statics, &st, 0, RUSH, enemy_centre, 12.0, &mut hold);
        assert!((band_far - 12.0).abs() < 1e-4);
    }

    /// S10-a through the routing (movement=table): the in-range shooter's
    /// ADVANCE with the 100" retreat dest moves exactly the table's 3.75"
    /// kite step, not the full band.
    #[test]
    fn s10_kite_routing_moves_the_shooter_the_tables_distance() {
        let (st, statics) = s10_line();
        let board = crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells: vec![],
            sandbox: Vec::<crate::terrain::Obb>::new(),
            pieces: vec![],
            walls: vec![],
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        });
        let dest = [(30.0 - RETREAT_GOAL_IN) * IN2M, 0.0, 24.0 * IN2M];
        let action = Action {
            kind: ADVANCE,
            unit: "a".into(),
            dest: Some(dest),
            shoot: None,
            charge: None,
            patient: false,
            split: None,
            traced: None,
        };
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { movement: true, ..Seams::default() };
        let next = resolve_stochastic_on_board(
            &statics, &st, &action, &board, seams, &mut rng,
        )
        .unwrap();
        let dx = st.positions[0][0][0] - next.positions[0][0][0];
        assert!((dx / IN2M - 3.75).abs() < 0.05, "moved {} in", dx / IN2M);
    }

    #[cfg(test)]
    mod los_model_tests {
        use super::*;
        use crate::terrain::{self, CellParams, Obb, PlainTerrain};

        fn at(x_in: f64, z_in: f64) -> [f64; 3] {
            [x_in * IN2M, 0.0, z_in * IN2M]
        }

        /// NML-1160's fixture, and the whole defect in one picture: a CONTAINER wall
        /// two cells tall (world cells (0,0) and (0,1), i.e. x in [0,3)" and z in
        /// [0,6)") with a two-model unit on each side. Both unit CENTRES sit at
        /// z = 5.25", behind the wall; the NORTH model of each sits at z = 9.0",
        /// with a clear lane past the wall's end. `SchoolTerrain.los_blocked` — the
        /// centre-to-centre probe self-play stamps into `los_pairs` — says blocked;
        /// `SoloController._has_los`, which is the ONLY sight test the table itself
        /// applies, says the shot is on.
        fn los_line() -> (State, Vec<UnitStatic>, Terrain) {
            let (mut st, mut statics) = buff_line();
            st.positions = vec![
                vec![at(-3.0, 1.5), at(-3.0, 9.0)],
                vec![],
                vec![at(6.0, 1.5), at(6.0, 9.0)],
                vec![],
            ];
            st.radii = vec![vec![0.016; 2], vec![], vec![0.016; 2], vec![]];
            st.wounds = vec![vec![1; 2], vec![], vec![1; 2], vec![]];
            st.alive = vec![2, 0, 2, 0];
            statics[2].model_count = 2;
            statics[2].wounds_max = vec![1, 1];
            statics[2].ctx.defense = 6; // the fixture has to LAND wounds to show one
            statics[0].shoot = vec![gun("Rifle", 20, 24)];
            let terrain = Terrain::build(&PlainTerrain {
                cells: vec![
                    [15.0, 15.0, terrain::CONTAINER as f64],
                    [15.0, 16.0, terrain::CONTAINER as f64],
                ],
                sandbox: Vec::<Obb>::new(),
                pieces: vec![],
                walls: vec![],
                cell_params: CellParams {
                    table_size_feet: [6.0, 4.0],
                    grid_rotation_degrees: 0.0,
                    grid_size_inches: 3.0,
                    inches_to_meters: IN2M,
                },
            });
            (st, statics, terrain)
        }

        fn shoot_at_b() -> Action {
            Action {
                kind: HOLD,
                unit: "a".into(),
                dest: None,
                shoot: Some("b".into()),
                charge: None,
                patient: false,
                split: None,
                traced: None,
            }
        }

        fn centre_matrix(st: &State, terrain: &Terrain) -> Vec<bool> {
            let n = st.units();
            let centres: Vec<V3> = (0..n).map(|i| geom::centre(&st.positions[i])).collect();
            let mut m = vec![true; n * n];
            for i in 0..n {
                for j in 0..n {
                    m[i * n + j] = !terrain.los_blocked(centres[i], centres[j]);
                }
            }
            m
        }

        fn run(st: &State, statics: &[UnitStatic], terrain: &Terrain, seams: Seams) -> State {
            let mut tray = Tray::seeded(11);
            let mut rng = GodotRng::new(0);
            resolve_stochastic_tray_on_board(statics, st, &shoot_at_b(), terrain, seams, &mut rng, &mut tray)
                .unwrap()
                .0
        }

        /// RED for the rung: the shot the table would take, refused by the coarse
        /// matrix and taken by the per-model one — on ONE state, with one knob
        /// between the two runs.
        #[test]
        fn a_model_lane_past_a_wall_is_a_shot_the_centre_probe_refuses() {
            let (st, statics, terrain) = los_line();
            let n = st.units();
            let coarse = centre_matrix(&st, &terrain);
            assert!(!coarse[2], "the fixture's wall has to block the centre line a -> b");
            let model = sight::sight_matrix(&st, &terrain);
            assert!(model[2] && model[2 * n], "one model on each side has a clear lane");

            // Knob OFF — `los_pairs` is the centre probe. `_los_clear` refuses and
            // the resolve leaves the target untouched: bit-identical to a HOLD.
            let mut dark = st.clone();
            dark.los_pairs = Some(Rc::new(coarse));
            let off = run(&dark, &statics, &terrain, Seams::default());
            assert_eq!(wounds_left(&off, 2), wounds_left(&dark, 2), "today the volley is dropped");

            // Knob ON — the same state, the same seed, the per-model matrix.
            let mut lit = st.clone();
            lit.los_pairs = Some(Rc::new(model));
            let on = run(&lit, &statics, &terrain, Seams { los_model: true, ..Seams::default() });
            assert!(wounds_left(&on, 2) < wounds_left(&lit, 2), "the lane the models have is a volley");
        }

        /// The guard on `refresh_los_pairs`: with `los_model` the per-model matrix
        /// survives a unit moving, because a clone inherits `su["los"]` untouched on
        /// the table too (`clone_state`, battle_sim.gd:1644-1651). Without the seam
        /// the mover's row and column are rewritten with the CENTRE probe — which on
        /// this fixture puts the coarse answer back one activation later.
        #[test]
        fn the_seam_stops_a_move_rewriting_the_matrix_with_the_centre_probe() {
            let (st, _statics, terrain) = los_line();
            let n = st.units();
            let mut parent = st.clone();
            parent.los_pairs = Some(Rc::new(sight::sight_matrix(&st, &terrain)));
            // One inch east, still behind the wall and still with the same lane.
            let mut moved = parent.clone();
            moved.positions[0] = vec![at(-2.0, 1.5), at(-2.0, 9.0)];

            let mut kept = moved.clone();
            refresh_los_pairs(&mut kept, &parent, &terrain, Seams { los_model: true, ..Seams::default() });
            assert!(kept.los_pairs.as_ref().unwrap()[2], "the per-model answer survives the move");
            assert!(kept.los_pairs.as_ref().unwrap()[2 * n], "and so does the reverse row");

            let mut coarse = moved.clone();
            refresh_los_pairs(&mut coarse, &parent, &terrain, Seams::default());
            assert!(!coarse.los_pairs.as_ref().unwrap()[2], "RED: without the seam it goes coarse");
            assert!(!coarse.los_pairs.as_ref().unwrap()[2 * n]);
        }
    }
}

/// NML-1157 — HERO-LAST: a combat intent aimed at a JOINED HERO resolves to its
/// HOST (`main._solo_combat_unit` :8452, GF v3.5.1 p.14). The port aimed at the
/// named index alone, so a 1-model Tough(3) hero could be killed inside a living
/// 20-model host — 42 of 63 chosen charges over 20 replayed teacher games, and
/// 352 of `qbg_ref`+`qag_ref`'s 16 043 recorded acts on the TABLE itself.
#[cfg(test)]
mod hero_last_tests {
    use super::*;

    /// `..Seams::default()` rather than an exhaustive literal on purpose: the
    /// next seam added to `io::Seams` must not redden a test that never
    /// mentions it.
    fn hero_only() -> Seams {
        Seams { hero_attach: true, ..Seams::default() }
    }

    fn hero_last() -> Seams {
        Seams { hero_attach: true, hero_last: true, ..Seams::default() }
    }

    /// `four_unit_line`: unit 0 hosts hero 1, unit 2 hosts hero 3.
    fn line() -> State {
        super::tests::four_unit_line()
    }

    #[test]
    fn red_a_named_hero_is_its_own_target_today() {
        let st = line();
        assert_eq!(combat_unit(&st, 3, Seams::default()), 3, "the port aims at the hero itself");
        assert_eq!(combat_unit(&st, 3, hero_only()), 3, "hero_attach alone does not redirect");
    }

    #[test]
    fn green_hero_last_resolves_the_intent_to_the_host() {
        let st = line();
        assert_eq!(combat_unit(&st, 3, hero_last()), 2, "p.14: you fight the unit, not the hero");
        assert_eq!(combat_unit(&st, 2, hero_last()), 2, "a host is already the unit");
        assert_eq!(combat_unit(&st, 0, hero_last()), 0);
    }

    #[test]
    fn a_hero_whose_host_is_dead_fights_on_alone() {
        // GF v3.5.1 p.14 — the host wiped, the hero IS the unit now and becomes
        // a target in its own right again. Same reading `menu::enemy_keys_tuned`
        // and `State::can_activate` take.
        let mut st = line();
        st.alive[2] = 0;
        assert_eq!(combat_unit(&st, 3, hero_last()), 3);
    }

    #[test]
    fn the_redirect_is_idempotent_and_never_loops() {
        // A hero attached to a hero is not a shape the capture builds, but the
        // helper must terminate on any input: one hop, never a walk.
        let mut st = line();
        st.attached_to = Rc::new(vec![Some(1), Some(0), None, Some(2)]);
        assert_eq!(combat_unit(&st, 0, hero_last()), 1);
        assert_eq!(combat_unit(&st, 1, hero_last()), 0);
    }
}

/// NML-1157 — the CASTER FOLD: `Caster(X)` is a hero rule, a joined hero never
/// activates on its own, and both cast paths read the HOST's profile and token
/// pool. Measured on `~/selfplay_out/gen0_teacher` (20 replayed games): 13
/// caster units, every one an attached hero, 52 chain activations, **0 casts**
/// and 0 tokens spent — with `seam_cast` on OR off.
#[cfg(test)]
mod cast_fold_tests {
    use super::*;
    use crate::rules::{Spell, SpellModifier};

    fn spell() -> Spell {
        Spell {
            name: "bolt".into(),
            status: "modeled".into(),
            threshold: 1,
            range_in: 18.0,
            target_count: 1,
            effect_kind: "damage".into(),
            effect_hits: 3,
            weapon_rules: vec![],
            beneficiary: String::new(),
            modifier: SpellModifier::default(),
            grants_rule: String::new(),
        }
    }

    /// Host (profile 0, no Caster) with a joined hero (profile 1, Caster(2))
    /// holding both cast tokens — the shape EVERY caster in the corpus has.
    fn host_and_caster_hero() -> (State, Vec<UnitStatic>) {
        let mut st = super::tests::four_unit_line();
        // Two profile slots: the plain host and the Caster(2) hero, so
        // `State::profile` can answer a `caster_value` per unit.
        let mut list = st.profiles.list.clone();
        let mut hero = list[0].clone();
        hero.caster_value = 2;
        list.push(hero);
        st.profiles = Rc::new(crate::state::Profiles { list, index: Default::default() });
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.index.clone(),
            profile: vec![0, 1, 0, 0],
        });
        st.casts = vec![0, 2, 0, 0];
        let plain = UnitStatic::default();
        let caster = UnitStatic { is_caster: true, spells: vec![spell()], ..UnitStatic::default() };
        (st, vec![plain, caster])
    }

    /// `..Seams::default()` rather than an exhaustive literal on purpose: the
    /// next seam added to `io::Seams` must not redden a test that never
    /// mentions it.
    fn fold() -> Seams {
        Seams { hero_attach: true, cast_fold: true, ..Seams::default() }
    }

    fn hero_only() -> Seams {
        Seams { hero_attach: true, ..Seams::default() }
    }

    #[test]
    fn red_the_host_alone_is_never_the_caster() {
        let (st, statics) = host_and_caster_hero();
        // The bug, stated: with the fold OFF — every corpus recorded so far —
        // the activating host answers "no caster", so `cast_phase` and the
        // legacy spell rider both do nothing, whatever `seam_cast` says.
        assert_eq!(caster_of(&statics, &st, 0, Seams::default()), None);
        assert_eq!(caster_of(&statics, &st, 0, hero_only()), None, "hero_attach alone is not enough");
    }

    #[test]
    fn green_the_fold_finds_the_joined_caster() {
        let (st, statics) = host_and_caster_hero();
        assert_eq!(caster_of(&statics, &st, 0, fold()), Some(1), "the hero is the caster of the chain");
    }

    #[test]
    fn the_fold_still_refuses_a_hero_with_no_tokens_and_a_dead_one() {
        let (mut st, statics) = host_and_caster_hero();
        st.casts[1] = 0;
        assert_eq!(caster_of(&statics, &st, 0, fold()), None, "no tokens, no cast");
        st.casts[1] = 2;
        st.alive[1] = 0;
        assert_eq!(caster_of(&statics, &st, 0, fold()), None, "a dead hero casts nothing");
    }

    #[test]
    fn a_caster_host_is_still_its_own_caster_with_the_fold_off() {
        // The other half of "nothing moves": a unit that carries Caster itself
        // answers exactly what it answered before, seam or no seam.
        let (mut st, mut statics) = host_and_caster_hero();
        st.roster = Rc::new(crate::state::Roster {
            keys: st.roster.keys.clone(),
            index: st.roster.index.clone(),
            profile: vec![1, 0, 0, 0],
        });
        st.casts = vec![2, 0, 0, 0];
        statics[1].spells = vec![spell()];
        assert_eq!(caster_of(&statics, &st, 0, Seams::default()), Some(0));
        assert_eq!(caster_of(&statics, &st, 0, fold()), Some(0));
    }

    #[test]
    fn the_cast_sub_phase_spends_the_heros_tokens_and_only_with_the_fold() {
        let (st, statics) = host_and_caster_hero();
        let los = vec![true; st.units()];

        let mut off = st.clone();
        cast_phase(&statics, &mut off, 0, &los, hero_only(), None);
        assert_eq!(off.casts, st.casts, "RED: with the fold off nothing is spent — 0 of 52");

        let mut on = st.clone();
        cast_phase(&statics, &mut on, 0, &los, fold(), None);
        assert!(on.casts[1] < st.casts[1], "the hero paid for its own spell: {:?}", on.casts);
        assert_eq!(on.casts[0], 0, "the host's empty pool is untouched");
    }

    /// DEFECT_LEDGER #33 — Animate Spirit and 4 siblings grant a rule and
    /// nothing else; before this PR `Spell` had no field to carry that, so the
    /// "castable" cast burned its pick and its tokens for no effect at all.
    /// RED: a Furious grant reaches THIS round's melee context and is spent —
    /// gone — by the time the round after asks the same question.
    #[test]
    fn a_furious_grant_reaches_this_rounds_melee_and_is_spent_by_it() {
        let (mut st, statics) = host_and_caster_hero();
        let grant = Spell { effect_kind: "buff".into(), grants_rule: "Furious".into(), ..spell() };
        apply_cast_effect(&statics, &mut st, 0, &grant, 1.0, None);
        assert!(crate::mods::granted(&st, 0, "Furious"), "the cast lands the grant on its target");

        let base = ctx_of(&statics[st.roster.profile[0]], &st, 0);
        assert!(!base.furious, "the static profile carries no Furious of its own");
        let live = ctx_live(base, &statics, &st, 0, true);
        assert!(live.furious, "THIS round's melee context sees the grant");

        let p = ShootProfile { range: 0, ..Default::default() };
        let def = Ctx::default();
        let plain = crate::combat::profile_ev(&p, 4, &base, &def, 0.0, true);
        let buffed = crate::combat::profile_ev(&p, 4, &live, &def, 0.0, true);
        assert!(buffed > plain, "the grant adds Furious's extra-6s hits to THIS charge: {plain} -> {buffed}");

        // One melee exchange spends the "once" grant, the same call a real
        // strike makes (`spend_exchange`) — nothing survives into round 2.
        crate::mods::spend_once(&mut st, 0, &[crate::mods::Role::Grant], true);
        assert!(!crate::mods::granted(&st, 0, "Furious"), "the exchange consumed the grant");
        let next_round = ctx_live(base, &statics, &st, 0, true);
        assert!(!next_round.furious, "gone for the round after — no double-dip");
    }
}
