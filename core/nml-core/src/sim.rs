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
use crate::io::{Action, Seams, SplitShot};
use crate::dice::{Morale, ShootResult, Tray};
use crate::rng::GodotRng;
use crate::rules::Spell;
use crate::spell::{cast_success_chance_base, official_pick_order, spell_damage_ev_of, spell_ev_of};
use crate::state::State;
use crate::mv::reach::{owner_bit, Disc, ReachBuild, ReachIndex, ReachQuery};
use crate::mv::CLEARANCE_EPS_IN;
use crate::terrain::{base_in_terrain, gives_cover, is_dangerous, Terrain};
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
/// The rest of the "Utility Buff" family — the friendly hit/casting/morale
/// buffs (Casting Buff, Morale Debuff, Precision Attacks/Fighter Buff,
/// Primal Boost Buff) and the enemy-side Mark (Unstoppable Mark) — is NOT
/// ported here: their table-side consumption (`_solo_record_spell_mod` read
/// back at the hit/cast/morale roll, and the dynamic rule-grant bridge onto
/// a weapon profile, main.gd:3722-3760) has no Rust twin at all yet —
/// `state.mods` is WRITTEN by spell buffs (`apply_cast_effect` above) but
/// read NOWHERE outside JSON serialization (io.rs), so stamping it here
/// would silently do nothing downstream. That consumption wiring is its own
/// ticket (block B2b), not a same-shape continuation of this one.
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
        if next.alive[bearer] > 0 && statics[next.roster.profile[bearer]].reposition_artillery_active {
            reposition_artillery_for(statics, next, bearer, seams, terrain);
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

/// NML-1150 — SPLIT FIRE's plan: the act's `split` aim folded onto THIS state's
/// roster. One entry per target group, in the table's group order
/// (`main.gd:2963-2984`: first-seen order of the per-weapon overlay picks, one
/// `_solo_resolve_ai_volley` per group).
struct SplitGroup {
    /// The group's target, by roster index and by key (`sees` reads keys).
    ti: usize,
    key: String,
    /// The gate and modifier distance: the recorded target's plain centre gap
    /// for the pooled plan; the B11 EDGE gap (both base radii off) for a split
    /// group, which exists because the TABLE's own test fired.
    d: f64,
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
        groups.push(SplitGroup { ti, key: key.clone(), d, weapons: Some(HashMap::new()) });
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
    // --- DANGEROUS TERRAIN (main.gd:1039-1047 -> `_run_ai_dangerous` :7026) ---
    // The table rolls this after EVERY executed move — advance, rush and charge
    // alike — and BEFORE the casts, the buffs and any melee, so it is also the
    // first thing the activation puts on the tray. Six is the tray's success
    // TARGET (:7030) but a **1** is what wounds (:7033): the recorded roll is
    // `attack`, `count` dice, `6`, signed by the moving unit.
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
                    land_wounds(&mut next, si, w);
                    // main.gd:1096-1098 — a NON-charge activation tests morale for
                    // these wounds at its very END, after everything else it did.
                    // Not ported: it would need the whole tail of the activation.
                    if kind != CHARGE {
                        shot.mark("dangerous_end_morale");
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
        cast_phase(statics, &mut next, si, &row, rng.as_deref_mut());
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

    // --- shoot (battle_sim.gd:608-630); HOLD and ADVANCE only ---
    if !shoot_key.is_empty() && (kind == HOLD || kind == ADVANCE) {
        if moved {
            return Err(Unsupported::MovedShootLos);
        }
        if let Some(&ti) = next.roster.index.get(shoot_key.as_str()) {
            // NML-1150: the split plan is decided BEFORE the recorded target's
            // gate — a split act may aim at units the recorded key does not
            // name, and then validity is gated PER GROUP below (main.gd
            // :2963-2984). The EV half keeps the one-target gate.
            let (plan, split_marks) = match dice.as_mut() {
                Some(_) => split_plan(action.split.as_ref(), statics, &next, si, &shoot_key),
                None => (None, Vec::new()),
            };
            if plan.is_some() || (next.sees(si, &shoot_key) && los_clear(&next, si, ti)) {
                let d = geom::dist_in(&next.positions[si], &next.positions[ti]);
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
                        let (sp_ev, sp_cost) =
                            spell_ev_of(us.is_caster, &us.spells, next.casts[si], &def, d_ev);
                        if sp_ev > 0.0 {
                            (shooting + sp_ev, sp_cost)
                        } else {
                            (shooting, 0)
                        }
                    }
                };
                next.casts[si] -= sp_cost; // 0 unless the spell rider fired
                match dice.as_mut() {
                    Some((tray, shot)) => {
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
                            weapons: None,
                        }];
                        let gs: &[SplitGroup] = plan.as_deref().unwrap_or(&pooled);
                        for g in gs {
                            let ut_g = &statics[next.roster.profile[g.ti]];
                            let def = ctx_of(ut_g, &next, g.ti);
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
                                parts.push((mi, msc, ctx_of(um, &next, mi)));
                            }
                            let r = crate::dice::resolve_volley_with_tray(
                                &shooters_of(&parts, statics, &next),
                                &def, &ut_g.name, g.d, tray,
                            );
                            // D1-B5a: `absorb`, not `=` — a CHARGE activation
                            // puts several sub-phases into ONE report, and the
                            // replay gate compares the whole activation roll by
                            // roll.
                            let w = shot.absorb(r);
                            land_wounds(&mut next, g.ti, w);
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
    fn four_unit_line() -> State {
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
        }
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
        Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None }
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
        Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None }
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
        Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None }
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
}
