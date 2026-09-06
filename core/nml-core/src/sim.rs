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
    shoot_ev, should_test_shooting_morale, shrouded_reach, ANGELIC_BLESSING_BOOST_TARGET_SPELL,
    CURSED_UNDEAD_BOOST_TARGET, HOLD_THE_LINE_BOOST_MORALE_BONUS, SELF_REPAIR_BOOST_TARGET,
};
// NML-1073 M5 D6a-B4 — the per-model sight twin, used only behind `sighting`.
use crate::sight;
use crate::geom::{self, V3};
use crate::acts::{rule_on, EPOCH_3_TABLE_RULES, EPOCH_5_TABLE_RULES, EPOCH_6_TABLE_RULES};
use crate::io::{Action, Seams, SplitShot};
use crate::dice::{Morale, ShootResult, Tray};
use crate::mods;
use crate::rng::GodotRng;
use crate::rules::Spell;
use crate::spell::{cast_success_chance, official_pick_order, spell_damage_ev_of, spell_ev_of};
use crate::state::State;
use crate::mv::reach::{owner_bit, Disc, ReachBuild, ReachIndex, ReachQuery};
use crate::mv::CLEARANCE_EPS_IN;
use crate::terrain::{base_in_terrain, gives_cover, is_dangerous, Terrain};
use crate::unit::{Ctx, PiercingTagEntry, ShieldedAlias, UnitStatic, ShootProfile, StormFacet, UtilityBuff};
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
    /// Developer loopback evaluator refused; never silently substitute hand values.
    LeafValueBridge(&'static str),
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
        tray_morale(next, ut, ti, false, seams.rules_epoch, tray, shot);
    }
}

/// `_solo_apply_storm_attack` main.gd:17226-17293, called at main.gd:1073
/// after Utility Buff in the table's own pre-attack order. Official text:
/// "Once per game, when this model is activated, before attacking, roll 3
/// dice. For each 2+ one enemy unit within 12\" takes 3 hits with <keyword>."
///
/// The payload rides the four ported primitives' own mechanics
/// (`unit::StormFacet`); the once-per-game state is `State.storm_used` (the
/// `limited_used` shape, recorded via `io::PlainLedger.storm_used`). Targets:
/// alive, un-reserved, unattached enemies within the rule's own `range_in` of
/// the ACTING unit's models (`_solo_nearest_model_gap_in` = the base-edge
/// gap, no LOS — the table's own read); an empty pool does NOT spend the
/// burst (main.gd:17257). Per success the best target (largest
/// `combined_alive`) takes the burst, repeatable; a destroyed target drops
/// out. Wave-3 gate: a record stamped 5 never saw these rules in its
/// recorder (`acts::EPOCH_6_TABLE_RULES`).
pub(crate) fn tray_storm_attack(
    statics: &[UnitStatic], next: &mut State, si: usize, seams: Seams,
    tray: &mut Tray, shot: &mut ShootResult,
) {
    if !rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) { return; }
    if next.alive[si] <= 0 { return; }
    let pid = next.player[si];
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach { bearers.extend(next.attached[si].iter().copied()); }
    for b in bearers {
        if next.alive[b] <= 0 { continue; }
        let owner = statics[next.roster.profile[b]].name.clone();
        for spec in &statics[next.roster.profile[b]].storm {
            if next.storm_used[b].iter().any(|n| n == &spec.name) { continue; }
            // The pool is THIS entry's: every alive, un-reserved, unattached
            // enemy within the rule's own range of the ACTING unit's models.
            let mut targets: Vec<usize> = (0..next.units())
                .filter(|&ti| next.player[ti] != pid && next.alive[ti] > 0 && combined_alive(next, ti, seams) > 0 && !next.dormant[ti] && !(seams.hero_attach && next.attached_to[ti].is_some()))
                .filter(|&ti| geom::edge_gap_in(&next.positions[si], &next.radii[si], &next.positions[ti], &next.radii[ti], DEFAULT_BASE_RADIUS_M) <= spec.range_in)
                .collect();
            // no enemy in reach — the once-per-game is NOT spent
            if targets.is_empty() { continue; }
            next.storm_used[b].push(spec.name.clone());
            let faces = tray.roll(spec.dice.max(1) as usize);
            shot.rolls.push(crate::dice::Roll {
                kind: "attack", count: spec.dice, target: spec.trigger,
                faces: faces.clone(), owner: owner.clone(),
            });
            let successes = crate::dice::faces_to_hits(&faces, spec.trigger as u8) as i64;
            shot.log.push(format!("{}: {} unleashes the storm — {} of {} dice hit (once per game)", spec.name, owner, successes, spec.dice));
            for _ in 0..successes {
                targets.retain(|&ti| combined_alive(next, ti, seams) > 0);
                // Best target per success, FIRST on a tie (the table's own
                // descending pick; first-index is this port's declared tie-break).
                let mut best = match targets.first() {
                    Some(&t) => t, None => break,
                };
                for &t in targets.iter().skip(1) {
                    if combined_alive(next, t, seams) > combined_alive(next, best, seams) { best = t; }
                }
                let mut hits = spec.hits;
                if spec.facet == StormFacet::Surge {
                    let s_faces = tray.roll(hits.max(1) as usize);
                    shot.rolls.push(crate::dice::Roll {
                        kind: "attack", count: hits, target: 6,
                        faces: s_faces.clone(), owner: owner.clone(),
                    });
                    hits += s_faces.iter().filter(|&&f| f == 6).count() as i64;
                }
                let ut = &statics[next.roster.profile[best]];
                let def = ctx_of(ut, next, best);
                let (alive_before, wounds_before) = (next.alive[best], wounds_left(next, best));
                let (ap, bane, shred) = match spec.facet {
                    StormFacet::Ap1 => (1, false, false), StormFacet::Bane => (0, true, false),
                    StormFacet::Shred => (0, false, true), StormFacet::Surge => (0, false, false),
                };
                let landed = shot.absorb(crate::dice::resolve_storm_hits_with_tray(hits, ap, bane, shred, &def, &ut.name, tray));
                land_wounds(next, best, landed);
                if shooting_morale_trigger(next, ut, best, alive_before, wounds_before) {
                    tray_morale(next, ut, best, false, seams.rules_epoch, tray, shot);
                }
            }
        }
    }
}

// ------------------------------------ BLOCK B2: UTILITY BUFF (movement) ---

/// "pick one friendly model within 6\" with Artillery" (army-book rule text;
/// mechanics param `range_in: 6.0`, rules_mechanics_gf.json / _aof.json,
/// "Re-Position Artillery").
pub const REPOSITION_PICK_RANGE_IN: f64 = 6.0;
/// "Increased Shooting Range Mark" — the +6" the grant's own name carries
/// (gf/aof/aofr registry entries; the gff variant carries `range_bonus_in`
/// instead, a param this resolver does not read — see the PR's needs-primitive
/// list). Hardcode, not a param read: the grant record carries the NAME only.
pub const INCREASED_SHOOTING_RANGE_MARK_IN: f64 = 6.0;
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

/// Wave 3 — `main._solo_apply_piercing_tag` main.gd:16999-17027, the marker
/// family's PLACEMENT half, in the table's own once-per-activation
/// before-attacking slot right after the Utility Buffs (main.gd:1071; Mind
/// Control sits between them on the table and is a seam this core does not
/// have). Per BEARER — the acting unit, then each attached hero, the table's
/// own members loop (:17005-17007) — every entry of the family the bearer
/// carries fires at its own literal, ONCE PER GAME (the shared
/// `piercing_tag_used` flag :17015/:17021 — one flag for all three names, set
/// only after a successful pick, so a bearer with no legal target may try
/// again next activation): the TOUGHEST enemy within the entry's range and
/// sight (`_solo_utility_target`, the `utility_targets` pick) takes
/// `maxi(rule_rating(raw), 1)` markers onto its `piercing_tag_markers` pool.
/// The SPEND half is the volley seam's, `piercing_tag_spend`.
///
/// The table's `_solo_is_ai_unit` gate (:17003) is NOT ported — this core has
/// no AI-side seam and selfplay stamps BOTH slots AI (main.gd:1790); like the
/// recorder gap below it only matters for a rules_epoch-6 human-vs-AI corpus,
/// and none exists. GATED `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)`: a
/// recording fleet is stamping rules_epoch 5 today, and wave 3's rules do not
/// exist in that recorder — see `acts::EPOCH_6_TABLE_RULES`.
fn tray_piercing_tag(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    seams: Seams,
    shot: &mut ShootResult,
) {
    if !rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
        return;
    }
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach {
        bearers.extend(next.attached[si].iter().copied());
    }
    for &bearer in &bearers {
        if next.alive[bearer] <= 0 {
            continue;
        }
        let pb = next.roster.profile[bearer];
        for t in &statics[pb].piercing_tags {
            if next.piercing_tag_used[bearer] {
                continue;
            }
            let probe = UtilityBuff {
                name: t.name.clone(),
                target: "enemy".into(),
                range_in: t.range_in,
                needs_los: t.needs_los,
                max_targets: 1,
                ..UtilityBuff::default()
            };
            let Some(ti) = utility_targets(statics, next, bearer, &probe, seams).into_iter().next() else {
                continue;
            };
            next.piercing_tag_used[bearer] = true;
            next.piercing_tag_markers[ti] += t.markers;
            // Rules-must-log — the table's own line, main.gd:17025-17027.
            shot.log.push(format!(
                "{}: {} places {} marker{} on {} — friendly attackers may spend them for +AP",
                t.name,
                statics[pb].name,
                t.markers,
                if t.markers == 1 { "" } else { "s" },
                statics[next.roster.profile[ti]].name
            ));
        }
    }
}

/// Wave 3 — `main._solo_spend_piercing_tag` main.gd:17030-17042: the next
/// volley at the marked target spends EVERY marker for +AP(markers) on THIS
/// volley, AI and human volleys alike (main.gd:3123/:9857 — the melee seams
/// never call it), once per group. The pool zeroes and the AP rides the
/// attacker Ctxs (`Ctx::tag_ap_mod`), the same profile-AP merge dice.rs's
/// volley fold gives Piercing Growth's marker delta. GATED
/// `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)` like the placement: below the
/// family's epoch the pool is empty by construction, so this reads 0.
fn piercing_tag_spend(next: &mut State, ti: usize, rules_epoch: u32) -> i64 {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        return 0;
    }
    let markers = next.piercing_tag_markers[ti].max(0);
    next.piercing_tag_markers[ti] = 0;
    markers
}

/// `tray_charge`'s strike-order leg: the static Unwieldy flag, or — wave 2
/// (`acts::rule_on`, frozen at `EPOCH_5_TABLE_RULES`) — a live "Unwieldy"
/// grant on the charger's chain.
fn charger_strikes_last(statics: &[UnitStatic], state: &State, si: usize, seams: Seams) -> bool {
    statics[state.roster.profile[si]].ctx.unwieldy
        || (rule_on(seams.rules_epoch, EPOCH_5_TABLE_RULES) && mods::granted(state, si, "Unwieldy"))
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
    // Wave 4 (rules-wave4-boostbases) — the Boost spellings' own band
    // ("Guerrilla Boost"/"Harassing Boost", the entry's `move_in: 6`);
    // 0.0 (no Boost, or an `rules_epoch: 5` record) keeps the shared base
    // 3" const, byte-exact.
    let band = if us.hit_and_run_move_in > 0.0 { us.hit_and_run_move_in } else { HIT_AND_RUN_MOVE_IN };
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
                (crate::mv::step::MoveRules { rules_epoch: seams.rules_epoch }).plain_move(
                    next,
                    t,
                    si,
                    dest,
                    band as f64,
                    seams.hero_attach,
                    true,
                    crate::mv::FAST_PLANNER_GUARD,
                )
            });
            if let Some(land) = land {
                land.spend_sidestep(next);
                for (i, m) in land.movers.iter().enumerate() {
                    next.positions[m.unit][m.model] = geom::to_f64(land.end[i]);
                }
                next.hit_and_run_round[si] = next.round;
                return true;
            }
        }
    }
    let dist_in = clamp_move_to_board(terrain, &next.positions[si], dir, band);
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
/// The regen fold's 0-means-unset MIN (the `regen_targets` stamp's own rule).
fn fold_min(have: i64, cand: i64) -> i64 {
    if cand > 0 && (cand < have || have == 0) { cand } else { have }
}

pub fn ctx_live(mut c: Ctx, statics: &[UnitStatic], state: &State, i: usize, melee: bool, rules_epoch: u32) -> Ctx {
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
    // WAVE 2 — the family's live-grant legs. Gated on `EPOCH_5_TABLE_RULES`
    // (frozen at 5, the stamping-gap fix): a rules_epoch below 5 replays
    // every pre-wave corpus untouched (spell grants included, Gen-2b's
    // stamping-gap window at rules_epoch 4 included).
    if rule_on(rules_epoch, EPOCH_5_TABLE_RULES) {
        c.slayer_grant = mods::granted(state, i, "Slayer");
        c.surge_grant = mods::granted(state, i, "Primal Boost");
        c.versatile_grant = mods::granted(state, i, "Versatile Attack");
        c.pierce_shooting_grant = mods::granted(state, i, "AP(+1) when shooting");
        c.pierce_melee_grant = mods::granted(state, i, "AP(+1) in melee");
        c.pierce_assault_grant = mods::granted(state, i, "Piercing Assault");
        c.unpredictable_shooting =
            c.unpredictable_shooting || mods::granted(state, i, "Unpredictable Shooter");
        // The Regeneration-primitive boosts: the granted entry's printed
        // targets, folded by the static stamp's own running-MIN rule.
        if mods::granted(state, i, "Self-Repair Boost") {
            c.regeneration = true;
            c.regen_target = fold_min(c.regen_target, SELF_REPAIR_BOOST_TARGET);
            c.regen_target_spell = fold_min(c.regen_target_spell, SELF_REPAIR_BOOST_TARGET);
        }
        if mods::granted(state, i, "Cursed Undead Boost") {
            c.regeneration = true;
            c.regen_target = fold_min(c.regen_target, CURSED_UNDEAD_BOOST_TARGET);
            c.regen_target_spell = fold_min(c.regen_target_spell, CURSED_UNDEAD_BOOST_TARGET);
        }
        // spell_only: the Angelic stamp folds the spell twin ONLY.
        c.regen_target_spell = if mods::granted(state, i, "Angelic Blessing Boost") {
            fold_min(c.regen_target_spell, ANGELIC_BLESSING_BOOST_TARGET_SPELL)
        } else {
            c.regen_target_spell
        };
    }
    // WAVE 3 MARKS (`acts::rule_on`, frozen at `EPOCH_6_TABLE_RULES`): the two
    // enemy-side grant names the pre-attack pick already records on the marked
    // unit (main.gd:16534, `beneficiary: "attackers"`). `indirect_mark` is
    // consumed by the volley's sight seams (`sighted_profiles_of`, the pooled
    // gate), `range_mark_in` by the dice-side reach gate — a record below
    // epoch 6 keeps today's inert reading, and the EV imagination (`ctx_of`)
    // stays blind, the sighting seam's own asymmetry.
    if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        c.indirect_mark = mods::granted_vs(state, i, "Indirect");
        c.range_mark_in = if mods::granted_vs(state, i, "+6\" shooting range") {
            INCREASED_SHOOTING_RANGE_MARK_IN
        } else {
            0.0
        };
    }
    // Wave 3 — the Shielded-family coverage legs (main.gd:5506-5525's
    // save-time read, granted half), gated on `EPOCH_6_TABLE_RULES` (frozen
    // at 6): the Gen-3 recorder stamps `rules_epoch: 5` and never saw these
    // rules. A live grant of an unconditional alias raises the working
    // Defense at once; the terrain-conditional kind folds ONLY on the live
    // majority-in-cover answer (`_solo_majority_in_cover` -> `state.in_cover`,
    // the same live read `ctx_of` writes over the template) — as does the
    // static stamp's terrain-pending alias. EV-only paths never call
    // `ctx_live` and stay blind, exactly like every other grant leg.
    if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        if c.shielded_alias != ShieldedAlias::None && !c.shielded && c.in_cover {
            c.shielded = true;
        }
        for (name, alias, terrain) in [
            ("+1 to Defense", ShieldedAlias::PlusOneToDefense, false),
            ("Sturdy Boost", ShieldedAlias::SturdyBoost, false),
            ("Grounded Reinforcement", ShieldedAlias::GroundedReinforcement, true),
        ] {
            if mods::granted(state, i, name) && (!terrain || c.in_cover) {
                c.shielded = true;
                if c.shielded_alias == ShieldedAlias::None {
                    c.shielded_alias = alias;
                }
            }
        }
    }
    // WAVE 3 — the Fortified family's live-grant leg, gated on the FROZEN
    // `EPOCH_6_TABLE_RULES`: the three Boost names' uniform printed shape
    // (AP(-1), no distance gate) folds as one flag-width stamp, the
    // Self-Repair Boost precedent; epoch-5 records replay untouched.
    if rule_on(rules_epoch, EPOCH_6_TABLE_RULES)
        && (mods::granted(state, i, "Guardian Boost")
            || mods::granted(state, i, "Warden Boost")
            || mods::granted(state, i, "Ossified Boost"))
    {
        c.fortified_boost_ap = c.fortified_boost_ap.max(1);
    }
    let (ap, hit) = growth_bonus_of(statics, state, i);
    c.growth_ap_mod = ap;
    c.growth_hit_mod = hit;
    // rules-wave3-growthmark — the family's DEFENDER-side facets, gated on
    // `EPOCH_6_TABLE_RULES` (frozen at 6, the stamping-gap rule): a record
    // stamping `rules_epoch: 5` (the recording fleet's live epoch) replays
    // byte-exact, exactly like the Lacerate/ambush waves' own gates.
    if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        let (dm, fa) = growth_defense_of(statics, state, i);
        c.growth_def_mod = dm;
        c.growth_fortify_ap = fa;
    }
    // Ambush family (rules-wave2-ambush): "Ambushing Piercing Shot" shoots
    // AP(+1) on the very round the unit arrives — `ambush_arrived_round` is
    // the stamp `arrive_unit`/`_finish_reserve_arrival` writes, and `!melee`
    // is the rule's own shooting-only facet. Zero below `rules_epoch` 4 (the
    // family stamp is epoch-gated) and for every EV-only path: those never
    // call `ctx_live`, the same buff-blindness `growth_ap_mod` keeps.
    if !melee && state.ambush_arrived_round[i] == state.round {
        c.ambush_arrival_ap = statics[state.roster.profile[i]].ambush_family.deploy_round_ap;
    }
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
    rules_epoch: u32,
) -> Ctx {
    c = ctx_live(c, statics, state, i, melee, rules_epoch);
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

/// rules-wave3-growthmark (epoch 6) — `growth_bonus_of`'s DEFENDER-side
/// sister, per `growth_defense_of`'s rule text: Defensive Frenzy/Growth sum
/// `defense_per_marker`/`defense_per_two` (the +X-to-Defense ladder) and
/// Fortified Growth sums `enemy_ap_per_two` (negative, the attacker-AP cut;
/// `min_ap` stays unread — the hard 0 floor is dice::save_batch's own
/// `max(0)`, the only floor every shipped entry prints).
/// One marker counter per unit, folded the same `markers`/`markers / 2` way
/// as the attack half above.
fn growth_defense_of(statics: &[UnitStatic], state: &State, i: usize) -> (i64, i64) {
    let markers = state.growth_markers[i];
    if markers <= 0 {
        return (0, 0);
    }
    let mut dm = 0;
    let mut fa = 0;
    for g in &statics[state.roster.profile[i]].growth {
        dm += g.defense_per_marker * markers + g.defense_per_two * (markers / 2);
        fa += g.enemy_ap_per_two * (markers / 2);
    }
    (dm, fa)
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

/// rules-wave3-growthmark (epoch 6) — the defender-side facets' log lines.
fn growth_log_defender(us: &UnitStatic, def: &Ctx, markers: i64, shot: &mut ShootResult) {
    if def.growth_def_mod != 0 {
        let dn = us.growth.iter().find(|g| g.defense_per_marker != 0 || g.defense_per_two != 0).map(|g| g.name.clone()).unwrap_or_default();
        shot.log.push(format!(
            "{}: {} Defense rolls +{} ({} marker(s))", dn, us.name, def.growth_def_mod, markers));
    }
    if def.growth_fortify_ap != 0 {
        let fn_ = us.growth.iter().find(|g| g.enemy_ap_per_two != 0).map(|g| g.name.clone()).unwrap_or_default();
        shot.log.push(format!(
            "{}: every unit attacking {} rides AP({}) per two markers", fn_, us.name, def.growth_fortify_ap));
    }
}

/// rules-wave3-growthmark (epoch 6) — Regenerative Strength's own trigger
/// (`on_ignore_wound`): +1 marker for every wound this unit IGNORED
/// (Regeneration's ignored count, `caused - landed`), capped at the rule's
/// own `max_markers`. Called with the DEFENDER's index at the volley and the
/// melee-strike tail, after the wounds (and the ignore) landed; a dead bearer
/// banks nothing. The gain is logged once per phase — the LOGGING RULE is
/// "every rule you make applicable emits ONE log line when it fires".
fn growth_on_ignore_wound(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    ignored: i64,
    shot: &mut ShootResult,
) {
    if ignored <= 0 || next.alive[si] <= 0 {
        return;
    }
    let us = &statics[next.roster.profile[si]];
    let Some(cap) = us.growth.iter().find(|g| g.on_ignore_wound).map(|g| g.max_markers) else {
        return;
    };
    let before = next.growth_markers[si];
    let gain = ignored.min((cap - before).max(0));
    if gain <= 0 {
        return;
    }
    next.growth_markers[si] = before + gain;
    shot.log.push(format!(
        "Regenerative Strength: {} banks {} marker(s) for ignoring wounds",
        us.name, gain
    ));
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
    /// The caller's `Seams::rules_epoch`, carried so a member-level profile
    /// read can gate a wave-3 mark consumer (`acts::rule_on` off a struct the
    /// call already passes — no shared signature widened, the wave-3 rule).
    /// 0 (the `Default`) is pre-epoch-6: every existing caller keeps its
    /// reading exactly as it replays today.
    pub rules_epoch: u32,
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
        shrouded_reach(r, def.ranged_shroud_penalty_in, def.ranged_shroud_floor_in)
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
    // WAVE 3 MARK CONSUMERS (`acts::rule_on`, frozen at `EPOCH_6_TABLE_RULES`):
    // the two enemy-side grant names the pre-attack pick already records on
    // the marked unit (main.gd:16534, `beneficiary: "attackers"`) reach the
    // volley here, at the same per-weapon sight/range seam a weapon's own
    // Indirect flag rides. A record stamped below epoch 6 keeps today's
    // inert reading — the grant lands on the ledger but no resolver reads it.
    let epoch6 = rule_on(sc.rules_epoch, EPOCH_6_TABLE_RULES);
    let mark_indirect = epoch6 && mods::granted_vs(state, ti, "Indirect");
    let mark_range = if epoch6 && mods::granted_vs(state, ti, "+6\" shooting range") {
        INCREASED_SHOOTING_RANGE_MARK_IN
    } else {
        0.0
    };
    for (i, p) in us.shoot.iter().enumerate() {
        if (p.range as f64) + mark_range < d {
            continue;
        }
        sc.keep.push(i);
        let reach = sight_reach_in(p.range as f64 + mark_range, state.aircraft[ti], def);
        // Indirect (GF v3.5.1) "may target enemies that are not in line of
        // sight as if in line of sight": the range gate stays, the sight test
        // goes (main.gd:4136-4138).
        let seen = sight::sighted_count(state, zones, &blockers, mi, ti, reach, p.indirect || mark_indirect);
        // Rules-must-log: the mark fires only where it changes the volley.
        if mark_indirect && !p.indirect && seen > 0 {
            trace_rule("volley", "Indirect Mark",
                &format!("{} fires at {} without line of sight", statics[state.roster.profile[mi]].name, statics[state.roster.profile[ti]].name));
        }
        if mark_range > 0.0 && (p.range as f64) < d {
            trace_rule("volley", "Increased Shooting Range Mark",
                &format!("{} gains +{mark_range:.0}\" reach on {}", statics[state.roster.profile[mi]].name, statics[state.roster.profile[ti]].name));
        }
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
        // rules-wave3-growthmark (epoch 6) — Regenerative Strength's melee
        // facet: +X attacks with ONE melee weapon, X = the bearer's own
        // marker count (`scope: "one_melee_weapon"`; the unit's FIRST melee
        // profile is the pick). Gated `EPOCH_6_TABLE_RULES`, so a rules_epoch
        // 5 record replays byte-exact.
        if rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) && state.growth_markers[mi] > 0 {
            let atk = um.growth.iter().map(|g| g.attacks_per_marker).sum::<i64>()
                * state.growth_markers[mi];
            if atk != 0 {
                if let Some(a) = sc.attacks.first_mut() {
                    *a += atk;
                }
            }
        }
        parts.push((
            mi,
            sc,
            ctx_live_vs(ctx_of_melee(um, state, mi), statics, state, mi, ti, true, seams.rules_epoch),
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
/// WAVE 3 — the family's rules-must-log name (B13's shape: the orchestrators
/// own the log, `save_batch` only reports that the arm lowered a target): the
/// static stamp first (gated alias when `over9` met it, else the Boost), then
/// the live grants. None = nothing carried.
fn fortified_log_name(statics: &[UnitStatic], state: &State, ti: usize, over9: bool) -> Option<String> {
    let us = &statics[state.roster.profile[ti]];
    if over9 && !us.fortified_alias_name.is_empty() {
        return Some(us.fortified_alias_name.clone());
    }
    if !us.fortified_boost_name.is_empty() {
        return Some(us.fortified_boost_name.clone());
    }
    ["Guardian Boost", "Warden Boost", "Ossified Boost"]
        .into_iter()
        .find(|n| mods::granted(state, ti, n))
        .map(String::from)
}

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
    let def = ctx_live(ctx_of(ut, next, ti), statics, next, ti, true, seams.rules_epoch);
    // rules-wave3-growthmark (epoch 6) — the LOGGING-RULE lines for the
    // defender-side facets this strike is about to fold.
    if rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
        if def.growth_def_mod != 0 {
            shot.log.push(format!(
                "Defensive Growth: {} Defense rolls +{} ({} marker(s))",
                ut.name, def.growth_def_mod, next.growth_markers[ti]
            ));
        }
        if def.growth_fortify_ap != 0 {
            shot.log.push(format!(
                "Fortified Growth: every unit attacking {} rides AP({}) per two markers",
                ut.name, def.growth_fortify_ap
            ));
        }
    }
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
    let shred_alias_dice = rule_on(seams.rules_epoch, EPOCH_3_TABLE_RULES);
    let r = crate::dice::resolve_melee_with_tray(&members, &def, &ut.name, charging, cond_ap_dice, shred_alias_dice, tray);
    // WAVE 3, rules-must-log — the melee leg's Boost shape fired (no distance
    // here; the gated aliases never reach a melee save batch, exactly the
    // table's own `dist_in: -1.0` read, main.gd:6119).
    if r.fortified_fired {
        if let Some(n) = fortified_log_name(statics, next, ti, false) {
            shot.log.push(format!("{n}: {} takes the hits at AP(-1), min. AP(0) — saves one better", ut.name));
        }
    }
    for (mi, sc, _) in &parts {
        let melee = &statics[next.roster.profile[*mi]].melee;
        mark_spent_limited(melee, &sc.keep, &mut next.limited_used[*mi]);
    }
    let caused = r.caused;
    // rules-wave3-growthmark (epoch 6) — Regenerative Strength: wounds this
    // strike IGNORED (Regeneration's own count) bank the bearer a marker.
    let ignored = r.caused - r.wounds;
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
    // rules-wave3-growthmark (epoch 6) — the ignore-wound marker AFTER the
    // landing: a bearer that ignored some of these wounds banks for them.
    if rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
        growth_on_ignore_wound(statics, next, ti, ignored, shot);
    }
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
    rules_epoch: u32,
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
    // [2,6]-clamped target the table builds (main.gd:8288-8296). Wave 2: a
    // granted "Hold the Line Boost" joins the same net, epoch-gated.
    ctx.morale_bonus = state.morale_bonus[i]
        + mods::sum(state, i, mods::Role::Morale, melee, |r| r.morale_mod)
        + if rule_on(rules_epoch, EPOCH_5_TABLE_RULES) && mods::granted(state, i, "Hold the Line Boost") { HOLD_THE_LINE_BOOST_MORALE_BONUS } else { 0 };
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
    let charger_last = charger_strikes_last(statics, next, si, seams);
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

/// SEAM 1 (Utility Buff, docs/plans/UTILITY_BUFF_SEAMS_2026-09-05.md §1) —
/// the live `casting_mod` net over the caster's own ledger (self plus its
/// host, `mods::sum`'s own chain — Casting Buff/Debuff are never
/// `beneficiary: "attackers"`, so this never needs the wider grant chain).
/// GATED `rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES)`: a record stamped
/// below epoch 6 (every recorded corpus today — MEASURED 2026-09-06 on
/// gen3_bank_v2 + gen4_bank, 120 000 games, rules_epoch 5 throughout: 0
/// casts either way, `hero_attach` off in all of them) must keep seeing
/// exactly zero, so `cast_phase` still folds in the flat
/// `cast_success_chance_base()` behaviour below the gate. Rules-must-log:
/// each contributing record names itself under `NML_TRACE_RULES`.
fn casting_net_of(statics: &[UnitStatic], state: &State, ci: usize, seams: Seams) -> i64 {
    if !rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
        return 0;
    }
    let mut net = 0;
    for u in [Some(ci), state.attached_to[ci]].into_iter().flatten() {
        for r in &state.buffs[u] {
            if mods::matches(r, mods::Role::Casting, false) {
                net += r.casting_mod;
                trace_rule(
                    "cast",
                    "Casting modifier",
                    &format!(
                        "{:+} to {}'s cast target (casting_net now {net})",
                        r.casting_mod, statics[state.roster.profile[ci]].name
                    ),
                );
            }
        }
    }
    net
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
    let p_success = cast_success_chance(casting_net_of(statics, state, ci, seams));
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
/// `pub(crate)` since the Battleborn wave-3 round-start leg (rollout.rs), the
/// unit.rs Royal Legion stamp, and unit.rs's build-time aura expansion AND
/// Boost-aura expansion reads all log their fired grants through the same
/// NML_TRACE_RULES seam — one shape for every rules-must-log line on this
/// core.
pub(crate) fn trace_rule(arm: &str, rule: &str, detail: &str) {
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
    if let Some(land) = (crate::mv::step::MoveRules { rules_epoch: seams.rules_epoch }).plain_move(
        next,
        t,
        winner,
        goal,
        CONSOLIDATE_WIN_IN,
        seams.hero_attach,
        true,
        crate::mv::FAST_PLANNER_GUARD,
    ) {
        land.spend_sidestep(next);
        for (i, m) in land.movers.iter().enumerate() {
            next.positions[m.unit][m.model] = geom::to_f64(land.end[i]);
        }
    }
}

/// The Shred Boost's widened save-fail window (`#678`, merged AFTER the
/// Gen-2b recording fleet closed at `cf8831d1`): `EPOCH_5_TABLE_RULES`, not
/// the literal `4` it shipped gated on — a record stamping `rules_epoch: 4`
/// (Gen-2b included) never saw this rule played, unlike Lacerate
/// (`acts::EPOCH_4_TABLE_RULES`, merged BEFORE the fleet launched).
fn shred_boost_active(rules_epoch: u32) -> bool {
    rule_on(rules_epoch, EPOCH_5_TABLE_RULES)
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
    sc.rules_epoch = seams.rules_epoch; // wave-3 mark consumers read it off Scratch

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
    let mut charge_remaining_in = if seams.movement && rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
        band_in.max(0.0)
    } else { f64::INFINITY };
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
            landing = (crate::mv::step::MoveRules { rules_epoch: seams.rules_epoch }).charge_move(
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
                landing = (crate::mv::step::MoveRules { rules_epoch: seams.rules_epoch }).plain_move(
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
        land.spend_sidestep(&mut next);
        moved = true;
        for (i, m) in land.movers.iter().enumerate() {
            next.positions[m.unit][m.model] = geom::to_f64(land.end[i]);
        }
        // D5-2 review fix: the table's own arc only feeds the D5-1 budget
        // gate when `charge_landing` asks for it — otherwise `movement=
        // "table"` silently forces `charge_landing="table"` on, and the
        // engage snap gate refuses charges D5-1-off never refused.
        if seams.charge_landing || rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
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

    // --- PIERCING TAG (main.gd:1071, the table's pre-attack slot right after
    // the Utility Buffs + Mind Control — Mind Control is a seam this core does
    // not have), tray path only — see `tray_piercing_tag`. Dice-free: no tray
    // draw either way (the marker count comes off the rule's rating).
    if let Some((_, shot)) = dice.as_mut() {
        tray_piercing_tag(statics, &mut next, si, seams, shot);
    }

    // --- STORM ATTACK (main.gd:1073, after Utility Buff in the table's own
    // pre-attack slot order), every action kind, tray path only. See
    // `tray_storm_attack`; no enemy in reach does not spend the burst.
    if let Some((tray, shot)) = dice.as_mut() {
        tray_storm_attack(statics, &mut next, si, seams, tray, shot);
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
            // WAVE 3 MARK (`acts::rule_on`, frozen at `EPOCH_6_TABLE_RULES`):
            // "Indirect Mark" makes the marked unit a LEGAL target without
            // sight (main.gd:4011-4029 runs the same waiver in the table's own
            // per-target validity check), so the pooled gate consults it —
            // a record below epoch 6 never waives anything here.
            let mark_indirect = rule_on(sc.rules_epoch, EPOCH_6_TABLE_RULES)
                && mods::granted_vs(&next, ti, "Indirect");
            let sighted = if moved {
                (match cover {
                    Cover::Board(t) if t.is_valid() => !t.los_blocked(
                        geom::centre(&next.positions[si]),
                        geom::centre(&next.positions[ti]),
                    ),
                    _ => next.los[si].is_none() && next.los_pairs.is_none(),
                }) || mark_indirect
            } else {
                (next.sees(si, &shoot_key) && los_clear(&next, si, ti)) || mark_indirect
            };
            if mark_indirect && !(next.sees(si, &shoot_key) && los_clear(&next, si, ti)) {
                trace_rule("volley", "Indirect Mark",
                    &format!("{} may target {} without line of sight", statics[pi_s].name, statics[next.roster.profile[ti]].name));
            }
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
                            // Wave 3 — Piercing Tag: the marked target's pool
                            // spends EVERY marker on THIS volley (main.gd
                            // :3123 AI / :9857 human, shooting only — the
                            // melee seams never call it), once per group.
                            let tag_ap = piercing_tag_spend(&mut next, g.ti, seams.rules_epoch);
                            if tag_ap > 0 {
                                let s = if tag_ap == 1 { "" } else { "s" };
                                shot.log.push(format!(
                                    "Piercing Tag: {tag_ap} marker{s} spent — +AP({tag_ap}) on this volley"
                                ));
                            }
                            let ut_g = &statics[next.roster.profile[g.ti]];
                            let def = ctx_live(ctx_of(ut_g, &next, g.ti), statics, &next, g.ti, false, seams.rules_epoch);
                            // rules-wave3-growthmark (epoch 6) — the volley's
                            // LOGGING-RULE lines, named after the entry that
                            // carried the facet (the two Defensive names share
                            // one ladder).
                            if rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
                                let usg = &statics[next.roster.profile[g.ti]];
                                growth_log_defender(usg, &def, next.growth_markers[g.ti], shot);
                            }
                            let alive_before_g = next.alive[g.ti];
                            let wounds_before_g = wounds_left(&next, g.ti);
                            let mut parts: Vec<(usize, Scratch, Ctx)> = Vec::new();
                            for &mi in std::iter::once(&si).chain(next.attached[si].iter()) {
                                if next.alive[mi] <= 0 {
                                    continue;
                                }
                                let um = &statics[next.roster.profile[mi]];
                                let mut msc = Scratch::default();
                                msc.rules_epoch = seams.rules_epoch;
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
                                // Wave 3 — Mobile Artillery's stationary gate:
                                // the act-scope `moved` flag is the twin of the
                                // table's `moved_round == current_round` stamp
                                // (main.gd:7650/:5773-5775) — a HOLD act never
                                // moves, an ADVANCE/RUSH did.
                                let mut att = ctx_live_vs(ctx_of(um, &next, mi), statics, &next, mi, g.ti, false, seams.rules_epoch);
                                att.moved_this_round = moved;
                                parts.push((mi, msc, att));
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
                                att.tag_ap_mod = tag_ap;
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
                                rule_on(seams.rules_epoch, EPOCH_3_TABLE_RULES),
                                // The Shred-family alias gate — the same epoch.
                                rule_on(seams.rules_epoch, EPOCH_3_TABLE_RULES),
                                // The Shred Boost's widened save-fail window —
                                // see `shred_boost_active`'s doc above.
                                shred_boost_active(seams.rules_epoch),
                                tray,
                            );
                            // WAVE 3, rules-must-log — the arm lowered a
                            // save target; the volley is the one leg whose
                            // over-9" gate can fire the gated aliases.
                            if r.fortified_fired {
                                let over9 =
                                    def.fortified_alias_over_in > 0.0 && g.mod_d > def.fortified_alias_over_in;
                                if let Some(n) = fortified_log_name(statics, &next, g.ti, over9) {
                                    shot.log.push(format!("{n}: {} takes the hits at AP(-1), min. AP(0) — saves one better", ut_g.name));
                                }
                            }
                            for (mi, msc, _) in &parts {
                                let shoot = &statics[next.roster.profile[*mi]].shoot;
                                mark_spent_limited(shoot, &msc.keep, &mut next.limited_used[*mi]);
                            }
                            // D1-B5a: `absorb`, not `=` — a CHARGE activation
                            // puts several sub-phases into ONE report, and the
                            // replay gate compares the whole activation roll by
                            // roll.
                            // rules-wave3-growthmark (epoch 6) — the wounds
                            // this volley IGNORED, before `absorb` consumes
                            // the result (Regenerative Strength's trigger).
                            let ignored = r.caused - r.wounds;
                            let w = shot.absorb(r);
                            land_wounds(&mut next, g.ti, w);
                            // rules-wave3-growthmark (epoch 6) — the
                            // ignore-wound marker AFTER the landing.
                            if rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
                                growth_on_ignore_wound(statics, &mut next, g.ti, ignored, shot);
                            }
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
                                tray_morale(&mut next, ut_g, g.ti, false, seams.rules_epoch, tray, shot);
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
                if seams.movement {
                    (crate::mv::step::MoveRules { rules_epoch: seams.rules_epoch })
                        .snap_charge_state(&mut next, si, ti, charge_remaining_in, seams.hero_attach);
                }
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
                        tray_morale(&mut next, ul, li, true, seams.rules_epoch, tray, shot);
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
            // log twin of `record_decision`'s "hit-and-run" entry. Wave 4
            // (rules-wave4-boostbases): a Boost carrier names its own spelling
            // and prints its own band; the base line stays byte-exact.
            let pi = next.roster.profile[si];
            let us = &statics[pi];
            let (rule, band) = if us.hit_and_run_rule.is_empty() {
                ("Hit & Run".to_string(), HIT_AND_RUN_MOVE_IN.to_string())
            } else {
                (us.hit_and_run_rule.clone(), us.hit_and_run_move_in.to_string())
            };
            let (_, shot) = dice.as_mut().unwrap();
            shot.log.push(format!("{rule}: {} steps up to {band}\" after its attack", us.name));
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
                    tray_morale(&mut next, us, si, false, seams.rules_epoch, tray, shot);
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
        let shroud = Ctx {
            ranged_shrouding: true,
            ranged_shroud_penalty_in: 6.0,
            ranged_shroud_floor_in: 6.0,
            ..Ctx::default()
        };
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
#[path = "tests/sim/mod.rs"]
mod tests;

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

    /// SEAM 1 (Utility Buff §1) — Casting Buff/Debuff's `casting_mod` net
    /// shifts the landed cast EV only at `EPOCH_6_TABLE_RULES` and above; a
    /// record stamped below it (every recorded corpus today) must keep
    /// seeing the flat chance, buff or no buff. Target is unit 3 (`x=9"`,
    /// the nearer of the two enemies to `si=0` at `x=0"` — `best_spell_
    /// target`'s own tie-break), given a deep wound pool so it never dies
    /// mid-walk and the same target/spell gets picked all three D3 faces.
    #[test]
    fn casting_buff_buffs_the_cast_attempt_at_epoch_6_and_not_below() {
        let (mut st, statics) = host_and_caster_hero();
        st.wounds[3] = vec![1000];
        st.wound_frac[3] = 0.0;
        let los = vec![true; st.units()];
        let epoch6 = Seams { hero_attach: true, cast_fold: true, rules_epoch: EPOCH_6_TABLE_RULES, ..Seams::default() };
        let epoch5 = Seams { hero_attach: true, cast_fold: true, rules_epoch: EPOCH_6_TABLE_RULES - 1, ..Seams::default() };
        let live_mod = |casting_mod: i64| mods::LiveMod {
            hit_mod: 0, casting_mod, morale_mod: 0,
            grants_rule: Rc::from(""), scope: Rc::from(""), attackers: false, once: false,
        };
        let damage = |s: &State| (1000 - s.wounds[3][0]) as f64 + s.wound_frac[3];

        let mut baseline6 = st.clone();
        cast_phase(&statics, &mut baseline6, 0, &los, epoch6, None);

        // Casting Buff: `casting_mod +1` (rules_mechanics_aof.json:8091).
        let mut buffed6 = st.clone();
        buffed6.buffs[1].push(live_mod(1));
        cast_phase(&statics, &mut buffed6, 0, &los, epoch6, None);
        assert!(damage(&buffed6) > damage(&baseline6),
            "epoch 6: Casting Buff raises the landed EV ({} vs baseline {})", damage(&buffed6), damage(&baseline6));

        // Casting Debuff: `casting_mod -1` (rules_mechanics_aof.json:958).
        let mut debuffed6 = st.clone();
        debuffed6.buffs[1].push(live_mod(-1));
        cast_phase(&statics, &mut debuffed6, 0, &los, epoch6, None);
        assert!(damage(&debuffed6) < damage(&baseline6),
            "epoch 6: Casting Debuff lowers the landed EV ({} vs baseline {})", damage(&debuffed6), damage(&baseline6));

        // RED-below-epoch-6: the same buffed ledger, epoch 5 (the Gen-3/
        // Gen-4 fleet's stamped window) — must match the epoch-5 baseline
        // exactly, the buff riding the ledger inert.
        let mut baseline5 = st.clone();
        cast_phase(&statics, &mut baseline5, 0, &los, epoch5, None);
        let mut buffed5 = st.clone();
        buffed5.buffs[1].push(live_mod(1));
        cast_phase(&statics, &mut buffed5, 0, &los, epoch5, None);
        assert_eq!(damage(&buffed5), damage(&baseline5), "epoch 5: the buff must ride the ledger inert");
        assert_eq!(damage(&baseline5), damage(&baseline6), "below the gate the chance is exactly the flat one");
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
        let live = ctx_live(base, &statics, &st, 0, true, 4);
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
        let next_round = ctx_live(base, &statics, &st, 0, true, 4);
        assert!(!next_round.furious, "gone for the round after — no double-dip");
    }
}
