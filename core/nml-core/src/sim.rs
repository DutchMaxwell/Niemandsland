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

use std::borrow::Cow;
use std::collections::HashMap;
use std::rc::Rc;

use crate::combat::{
    at_or_below_half, block_chance, charge_estimate_gap_in, effective_attacks, melee_ev, morale_target,
    shielded_defense,
    shoot_ev, should_test_shooting_morale, shrouded_reach, RAVAGE_WOUND_TARGET,
    ANGELIC_BLESSING_BOOST_TARGET_SPELL, BEST_HIT_TARGET, CURSED_UNDEAD_BOOST_TARGET,
    BANNER_MORALE_BONUS, HOLD_THE_LINE_BOOST_MORALE_BONUS, REGENERATION_TARGET, SELF_REPAIR_BOOST_TARGET, UNMODIFIED_SIX,
};
// NML-1073 M5 D6a-B4 — the per-model sight twin, used only behind `sighting`.
use crate::sight;
use crate::geom::{self, V3};
use crate::acts::{
    rule_on, CURRENT_RULES_EPOCH, EPOCH_94_PARITY_BATCH, EPOCH_3_TABLE_RULES, EPOCH_5_TABLE_RULES,
    EPOCH_6_TABLE_RULES, EPOCH_7_TABLE_RULES, EPOCH_8_PLANNER_MENU,
    EPOCH_9_MARK_FAMILY, EPOCH_10_CHARGE_BAND, EPOCH_12_MOVE_BUFF,
    EPOCH_13_WHO_WINS, EPOCH_14_DEADLY_LANDING, EPOCH_19_MOVE_GRANTS_FOLD,
    EPOCH_22_SCREENED_MELEE, EPOCH_23_INERT_MARKS, EPOCH_32_STRAFING,
    EPOCH_34_UNSTOPPABLE_MARK, EPOCH_37_UNSTOPPABLE_AURA, EPOCH_38_WATCHBORN_LATCH,
    EPOCH_41_SELF_DESTRUCT_SURVIVORS, EPOCH_44_SURGE_MARK, EPOCH_48_CASTER_BOOST,
    EPOCH_51_CASTER_INTERFERENCE, EPOCH_52_UTILITY_SPELLS, EPOCH_56_GROUNDED_PROTECTION,
    EPOCH_61_PRECISION_MARKERS, EPOCH_62_CASTING_MOD, EPOCH_65_MELEE_TRUTH,
    EPOCH_66_DISTANCE_TRUTH, EPOCH_67_MARKERS_BURSTS, EPOCH_68_MODIFIER_SUM,
    EPOCH_71_RAPID_CHARGE_MARK, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36, EPOCH_75_TABLE_FIXES,
    EPOCH_76_MOVE_FIXES, EPOCH_77_CHARGE_CAP, EPOCH_79_EV_MOVED_ROUND, EPOCH_83_LONE_HERO_TARGET, EPOCH_88_SPLIT_LONE_HERO,
    EPOCH_89_SHARED_BEARERS, EPOCH_91_JOINED_HERO_FATIGUE, EPOCH_92_MELEE_CAUSES,
};
use crate::io::{Action, Seams, SplitShot};
use crate::landing::{LandedModel, Landing};
use crate::logline::{Category, LogLine};
use crate::dice::{say_rule, Morale, ShootResult, Tray};
use crate::mods;
use crate::mission::{drop_carried, sync_carried_positions};
use crate::rng::GodotRng;
use crate::activation::{CastInput, ConsolidatePlan};
use crate::rules::Spell;
use crate::spell::{
    boost_value_of, cast_success_chance_vs, official_pick_order, plan_boost, plan_interference,
    spell_damage_ev_of, spell_ev_of, CASTER_BOOST_AURA_IN, CAST_BASE_TARGET,
};
use crate::menu::nearest_enemy;
use crate::cast_move_ev::movement_cast_gain;
use crate::state::State;
use crate::mv::reach::{owner_bit, Disc, ReachBuild, ReachIndex, ReachQuery};
use crate::mv::CLEARANCE_EPS_IN;
use crate::terrain::{base_in_terrain, gives_cover, is_dangerous, Terrain};
use crate::unit::{Ctx, ShieldedAlias, UnitStatic, ShootProfile, StormFacet, UtilityBuff};
#[cfg(test)]
use crate::unit::{GrowthRule, PiercingTagEntry};
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
/// Wave 5 (#816 PR 2): the menu's Reposition kind — dice-free, no recorded
/// corpus carries it (replay keys on `Action::teleport`); 5 stays clear of
/// the GDScript `AiDecision.Action` block (0-4, KITE = 4) and the one-hot.
pub const REPOSITION: i64 = 5;
pub const TELEPORT_EV_MARGIN: f64 = 0.5; // the fixed "may" margin (design §5-2)

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
    /// Tree search, `tree_dice: tray` — a chance edge whose activation the
    /// tray path flags `unported` (`ShootResult::unported`): the tree
    /// declines by the flag's name rather than sample a branch this port
    /// does not reproduce.
    TreeUnported(&'static str),
    /// Tree search, `tree_dice: tray` with no stream seed (the playout
    /// signature): declined, never invented.
    TreeDiceSeed,
    /// Tree search asked for an act outside its scope (the playout
    /// arbitration, the ORDER re-rank): declined by name, never half-applied.
    TreeOutOfScope(&'static str),
    /// grid-search step 9 — `grid_k > 0` with no leaf hook wired: the grid rows must be priced by the
    /// pool's own leaf, so a hookless search declines rather than price them by the hand alone.
    GridNeedsOpenerLeaf,
    /// grid-search step 9 — `grid_proposer == 1` (the learned prior) is declined until step 16.
    GridPriorMissing,
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
///
/// Inventory C12 (`Seams::hero_counts_in_size`, default off): a joined hero counts in the unit's size
/// (GF/AoF v3.5.1 p.14), so a host with an attached hero measures the COMBINED living models against the
/// combined starting size, the same basis as `main._solo_below_half_strength`.
fn below_half(state: &State, statics: &[UnitStatic], us: &UnitStatic, i: usize, seams: Seams) -> bool {
    if hero_size_on(state, i, seams) {
        return at_or_below_half(combined_alive(state, i, seams), combined_total(statics, state, i, us));
    }
    if us.model_count == 1 {
        return at_or_below_half(wounds_left(state, i), us.wounds_max.first().copied().unwrap_or(0));
    }
    at_or_below_half(state.alive[i], us.model_count)
}

/// Rules 3.6 (SHO-09s): stamp the two TARGET-STATE facts the conditional-AP arms read.
/// `below_half` needs `statics` and `seams`, so this runs at the volley/melee seams that already
/// hold both; passing `seams` to every `ctx_of` caller would touch the whole lane for a knob only
/// this stamp reads. Every field defaults to false, so an unstamped ctx keeps the old answer.
pub(crate) fn with_cond_ap_state(mut c: Ctx, statics: &[UnitStatic], state: &State, i: usize, seams: Seams) -> Ctx {
    c.above_half_strength = !below_half(state, statics, &statics[state.roster.profile[i]], i, seams);
    c.shaken_or_fatigued = state.shaken[i] || state.fatigued[i];
    c
}

/// Inventory C12 — the hero-in-size reading applies: knob on, attachment seam on, a hero joined to `i`.
#[inline]
fn hero_size_on(state: &State, i: usize, seams: Seams) -> bool {
    seams.hero_counts_in_size && seams.hero_attach && !state.attached[i].is_empty()
}

/// `SoloController.combined_total` — the host's starting size plus every joined hero's starting size.
fn combined_total(statics: &[UnitStatic], state: &State, i: usize, us: &UnitStatic) -> i64 {
    us.model_count
        + state.attached[i].iter().map(|&h| statics[state.roster.profile[h]].model_count).sum::<i64>()
}

/// The living count a morale snapshot is taken on: host + joined heroes with C12 on, the host alone otherwise.
#[inline]
fn morale_alive(state: &State, i: usize, seams: Seams) -> i64 {
    let i = morale_root(state, i, seams);
    if hero_size_on(state, i, seams) { combined_alive(state, i, seams) } else { state.alive[i] }
}

/// G4R3 F-MORALE-CHAIN (`EPOCH_73_V36`): the unit a shooting-morale test is about. A joined hero named as the
/// target (host dead) is the table's unit's last model, so its test reads the CHAIN — host plus every joined
/// hero (`combined_*`, `_solo_unit_wounds_now`) — not the hero as a unit of its own. Else `i`; below 73 always `i`.
fn morale_root(state: &State, i: usize, seams: Seams) -> usize {
    match state.attached_to[i] {
        Some(h) if seams.hero_attach && rule_on(seams.rules_epoch, EPOCH_73_V36) => h,
        _ => i,
    }
}

/// G4R4 C-GRANTED-RANGE (`EPOCH_73_V36`, empty `reach_grants` below it) + CC-8b (`LiveMod.range_in`): the shooting reach
/// bonus a LIVE grant ("Lust Boon" hands out Enhanced Lustbound, +8") or range spell ("Battle Rune" +6") adds on member
/// `mi`, with the rule/spell name. A `range_in` spell stacks on top of the Royal Legion bonus (table: `spell_in + alias_in`).
fn granted_reach<'a>(us: &'a UnitStatic, state: &'a State, mi: usize) -> (f64, &'a str) {
    let live = us.reach_grants.iter().filter(|(n, _)| mods::granted(state, mi, n));
    let (grant, grant_name) = live.fold((0.0, ""), |best, (n, b)| if *b > best.0 { (*b, n.as_str()) } else { best });
    let (mut spell_in, mut spell_name) = (0.0, "");
    for u in std::iter::once(mi).chain(state.attached_to[mi]).chain(state.attached[mi].iter().copied()) {
        for r in &state.buffs[u] {
            if mods::matches(r, mods::Role::Range, false) {
                spell_in += r.range_in as f64;
                if spell_name.is_empty() {
                    spell_name = &r.name;
                }
            }
        }
    }
    if spell_in > 0.0 {
        (us.royal_legion_range_in.max(grant) + spell_in, if grant > us.royal_legion_range_in { grant_name } else { spell_name })
    } else {
        (grant, grant_name)
    }
}

/// G4R4 C-LONEHERO-SHAKEN (`EPOCH_73_V36`): the Shaken a morale test reads. A lone joined hero (its host has no models
/// left) is the host's unit and the table keeps the flag on that unit, so the dead host's Shaken is the hero's; every
/// other unit reads its own flag, and below 73 every unit does.
///
/// From `EPOCH_94_PARITY_BATCH` only the unit's OWN flag counts (lead rule call 20.11.): a dead host's flag is stale once the hero
/// recovered alone, so the lone hero rolls its die; the table's `_solo_test_unit_shaken` reads the same.
fn unit_shaken(state: &State, i: usize, seams: Seams) -> bool {
    if rule_on(seams.rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) {
        return state.shaken[i];
    }
    let root = morale_root(state, i, seams);
    state.shaken[i] || (root != i && state.alive[root] <= 0 && state.shaken[root])
}

/// `main._solo_unit_wounds_now`: from 73 the chain's wounds (host plus joined heroes), below 73 the unit's own.
fn morale_wounds_left(state: &State, i: usize, seams: Seams) -> i64 {
    let r = morale_root(state, i, seams);
    let heroes: i64 = if seams.hero_attach && rule_on(seams.rules_epoch, EPOCH_73_V36) {
        state.attached[r].iter().map(|&h| wounds_left(state, h)).sum()
    } else {
        0
    };
    wounds_left(state, r) + heroes
}

/// The best living model's Quality in a joined unit from the melee-truth epoch.
/// Earlier records and records without the attachment seam keep host Quality.
fn morale_quality(statics: &[UnitStatic], state: &State, i: usize, seams: Seams) -> i64 {
    let own = statics[state.roster.profile[i]].quality;
    if !rule_on(seams.rules_epoch, EPOCH_65_MELEE_TRUTH) || !seams.hero_attach {
        return own;
    }
    let mut best = if state.alive[i] > 0 { Some(own) } else { None };
    for &h in &state.attached[i] {
        if state.alive[h] > 0 {
            let quality = statics[state.roster.profile[h]].quality;
            best = Some(best.map_or(quality, |q: i64| q.min(quality)));
        }
    }
    best.unwrap_or(own)
}

/// The joined Hero whose Quality a morale test uses (the table's `_solo_morale_quality`): the first living attached Hero that beats the
/// unit's own Quality, or the first living one while the host is dead. `None` when the unit tests with its own.
fn morale_hero(statics: &[UnitStatic], state: &State, i: usize, seams: Seams) -> Option<(usize, i64)> {
    if !rule_on(seams.rules_epoch, EPOCH_65_MELEE_TRUTH) || !seams.hero_attach {
        return None;
    }
    let mut best: Option<(usize, i64)> = None;
    let mut quality = statics[state.roster.profile[i]].quality;
    for &h in state.attached[i].iter().filter(|&&h| state.alive[h] > 0) {
        let q = statics[state.roster.profile[h]].quality;
        if (state.alive[i] <= 0 && best.is_none()) || q < quality {
            (quality, best) = (q, Some((h, q)));
        }
    }
    best
}

fn morale_side_alive(state: &State, i: usize, seams: Seams) -> bool {
    if rule_on(seams.rules_epoch, EPOCH_65_MELEE_TRUTH) && seams.hero_attach {
        combined_alive(state, i, seams) > 0
    } else {
        state.alive[i] > 0
    }
}

/// Fearless checks the models still in the joined unit when morale is tested.
fn morale_fearless(statics: &[UnitStatic], state: &State, i: usize, seams: Seams) -> bool {
    let own = &statics[state.roster.profile[i]];
    if !rule_on(seams.rules_epoch, EPOCH_65_MELEE_TRUTH) {
        return own.fearless;
    }
    if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
        let (with, total) = fearless_models(statics, state, i, seams);
        return crate::unit::most_models_of(with, total);
    }
    let mut found = false;
    if state.alive[i] > 0 {
        found = true;
        if !own.fearless_own { return false; }
    }
    if seams.hero_attach {
        for &h in &state.attached[i] {
            if state.alive[h] > 0 {
                found = true;
                if !statics[state.roster.profile[h]].fearless_own { return false; }
            }
        }
    }
    found
}

/// Rules 3.6 (ruling D-MOST): (living models of the joined unit that carry Fearless, all living models). Every
/// living host model shares the host's rules; every living joined hero is one model however Tough.
fn fearless_models(statics: &[UnitStatic], state: &State, i: usize, seams: Seams) -> (i64, i64) {
    let alive = state.alive[i].max(0);
    let mut counts = (if statics[state.roster.profile[i]].fearless_own { alive } else { 0 }, alive);
    if seams.hero_attach {
        for &h in state.attached[i].iter().filter(|&&h| state.alive[h] > 0) {
            counts.0 += i64::from(statics[state.roster.profile[h]].fearless_own);
            counts.1 += 1;
        }
    }
    counts
}

/// `BattleSim._morale_fails_expected` battle_sim.gd:1082-1090 — Shaken always
/// fails; otherwise the quality target's fail chance, halved by Fearless, and a
/// fail at 50% or worse.
///
/// aifix D1 — `seams.morale_by_probability` (default off) trades that 50 %
/// cliff (Q4+ always breaks, Q3+ never does) for a deterministic dither: the
/// unit fails when `fail_p` exceeds a low-discrepancy threshold of its roster
/// slot and the round, so over many units and rounds it breaks `fail_p` of the
/// time — the table's die — while one state still answers one way.
fn morale_fails_expected(state: &State, statics: &[UnitStatic], i: usize, seams: Seams) -> bool {
    if state.shaken[i] {
        // Inventory C08: an automatic fail is still a failed test; Fearless (all models) rolls its 4+ on it
        // (`dice::resolve_morale_with_tray`), so the Shaken Fearless unit breaks half the time, the dither standing in for the die.
        if seams.fearless_roll_when_shaken && morale_fearless(statics, state, i, seams) {
            return 0.5 > morale_dither(i, state.round);
        }
        return true;
    }
    let fail_p = morale_fail_chance(state, statics, i, seams);
    if seams.morale_by_probability {
        return fail_p > morale_dither(i, state.round);
    }
    fail_p >= 0.5
}

/// The fail CHANCE behind `morale_fails_expected` — the same Quality,
/// `morale_bonus`, `hero_aura_quality` and `morale_fearless` folds, returned
/// as a probability so an expectation seam (MOR-16a's token drain) never
/// re-derives the number. A Fearless unit is NOT an auto-pass in rules 3.6:
/// on a failed test it rolls one die and a 4+ counts as passed, so its fail
/// chance is exactly halved — one reading for the AI estimate and the forced
/// test alike.
fn morale_fail_chance(
    state: &State, statics: &[UnitStatic], i: usize, seams: Seams,
) -> f64 {
    if state.shaken[i] {
        let noisy = seams.fearless_roll_when_shaken && morale_fearless(statics, state, i, seams);
        return if noisy { 0.5 } else { 1.0 };
    }
    let mut quality = morale_quality(statics, state, i, seams);
    if let Some((_, aura)) = hero_aura_quality(statics, state, i, quality, seams) {
        quality = aura;
    }
    let fail_p = (morale_target(quality, state.morale_bonus[i]) - 1) as f64 / 6.0;
    if morale_fearless(statics, state, i, seams) {
        return fail_p * 0.5;
    }
    fail_p
}

/// A deterministic stand-in for the die in [0, 1): the golden-ratio sequence
/// over the roster slot, shifted per round by a second irrational step.
fn morale_dither(i: usize, round: i64) -> f64 {
    ((i as f64 + 1.0) * 0.618_033_988_749_894_9 + round as f64 * 0.754_877_666_246_692_7).fract()
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
/// B8 (stage-0 freeze 02.10.) — how often a casualty found a WOUND slot with no
/// POSITION behind it. Every writer in this core keeps `wounds` and `positions`
/// one model list; a state that arrives desynced (the trainer's arena fold
/// below `EPOCH_69_HERO_FOLD` built one) used to panic the whole process on
/// `positions.remove`. The wound slot still goes; the missing position is
/// LOGGED on stderr — the 1st hit and every power of two after it, so a
/// rollout storm cannot flood stderr while the count stays visible.
pub static DESYNC_HITS: std::sync::atomic::AtomicUsize = std::sync::atomic::AtomicUsize::new(0);

fn remove_position_or_log(state: &mut State, u: usize, i: usize, site: &str) {
    if i < state.positions[u].len() {
        state.positions[u].remove(i);
        return;
    }
    let n = DESYNC_HITS.fetch_add(1, std::sync::atomic::Ordering::Relaxed) + 1;
    if n.is_power_of_two() {
        eprintln!(
            "[core-desync] {site}: {} has {} wound slots left but {} positions, no position {i} to remove (hit #{n})",
            state.key(u), state.wounds[u].len(), state.positions[u].len()
        );
    }
}

pub fn land_wounds(state: &mut State, ti: usize, left: i64) {
    land_wounds_with(state, ti, left, false, 0);
}

/// `land_wounds` with the casualty order chosen: `exact` (`Seams::tray_exact`, tray-exact S6) is the
/// table's `apply_wounds_to_models` — `chain_casualty_order(unit, wounds)` computed ONCE, each model
/// soaking wounds until it dies, the next one after it. Without kits, or without `exact`, slot 0
/// goes first exactly as before.
pub fn land_wounds_with(state: &mut State, ti: usize, left: i64, exact: bool, rules_epoch: u32) -> i64 {
    let order = if exact {
        crate::casualty::chain_casualty_order(state, ti, Some(left.max(0) as usize), rules_epoch).unwrap_or_default()
    } else {
        Vec::new()
    };
    land_wounds_in_order(state, ti, left, order)
}

/// `land_wounds_with`'s landing loop over an explicit removal `order` (empty = slot 0 first).
fn land_wounds_in_order(state: &mut State, ti: usize, mut left: i64, mut order: Vec<usize>) -> i64 {
    while left > 0 && !state.wounds[ti].is_empty() {
        let s = order.first().copied().unwrap_or(0);
        let take = left.min(state.wounds[ti][s]);
        state.wounds[ti][s] -= take;
        left -= take;
        if state.wounds[ti][s] <= 0 {
            if state.positions[ti].len() == 1 { drop_carried(state, ti); }
            state.wounds[ti].remove(s);
            remove_position_or_log(state, ti, s, "land_wounds");
            state.kit_remove(ti, s);
            // radii stay aligned with positions or the base-edge measure lies.
            if s < state.radii[ti].len() {
                Rc::make_mut(&mut state.radii)[ti].remove(s);
            }
            if !order.is_empty() {
                order.remove(0);
                order.iter_mut().filter(|o| **o > s).for_each(|o| *o -= 1);
            }
        }
    }
    state.alive[ti] = state.positions[ti].len() as i64;
    left
}

/// The owner's answer to a target group's wound-allocation choice, as the group's landings consume
/// it: ordered capture slots, first the Deadly wounds' picks, then the pool's. `at` = the models' positions when the
/// choice opened (a landing never moves a survivor), so a slot's model is found again after any inline landing.
struct AllocPicks {
    picks: std::vec::IntoIter<usize>,
    slots: Vec<usize>,
    at: Vec<[f64; 3]>,
    used: usize,
}

impl AllocPicks {
    /// The current index of the next picked model that still stands (a pick on a dead model is skipped, as a click on one is).
    fn next(&mut self, state: &State, ti: usize) -> Option<usize> {
        let found = self.picks.find_map(|s| {
            let i = self.slots.iter().position(|x| *x == s)?;
            state.positions[ti].iter().position(|p| *p == self.at[i])
        });
        self.used += found.is_some() as usize;
        found
    }
}

/// Group `gi`'s wound-allocation choice (`_solo_wound_choice_matters`, main.gd:16939, over the host's
/// own models), opened where the group's landing starts: `deadly` Deadly wounds and `w` pool wounds land on `ti`, which has 2+
/// living models and a mixed loadout or a Tough model, and either a Deadly wound or a pool smaller than its wounds is
/// there to place. `None` = automatic: no choice named by the transcript (every seeded tray), or nothing to choose.
/// Slots are capture slots: `tray.dead_slots` skips the models earlier landings removed.
fn open_alloc(state: &State, si: usize, ti: usize, gi: usize, counts: (i64, i64), tray: &mut Tray) -> Option<AllocPicks> {
    open_alloc_id(state, ti, &format!("wound_alloc:{}:{}:{gi}", state.key(si), state.key(ti)), counts, tray)
}

/// Wound-allocation choice for an explicit `id` (volley group or cast `seq`).
fn open_alloc_id(state: &State, ti: usize, id: &str, (w, deadly): (i64, i64), tray: &mut Tray) -> Option<AllocPicks> {
    tray.feed()?;
    let kits = state.kits.get(ti).filter(|k| k.len() == state.wounds[ti].len())?;
    let matters = kits.iter().any(|x| x.wounds_max > 1 || (&x.weapons, x.equipment) != (&kits[0].weapons, kits[0].equipment));
    let alive = state.wounds[ti].len();
    if !matters || alive < 2 || !(deadly > 0 || (w > 0 && w < state.wounds[ti].iter().sum::<i64>())) {
        return None;
    }
    let dead = tray.dead_slots(ti);
    let slots: Vec<usize> = (0..).filter(|s| !dead.contains(s)).take(alive).collect();
    let picks = tray.wound_alloc(id, slots.clone(), state.key(ti))?;
    Some(AllocPicks { picks: picks.into_iter(), slots, at: state.positions[ti].clone(), used: 0 })
}

/// `land_deadly_wounds` for the wounds the owner places (`SoloController.deadly_pick`, main.gd:10661): a
/// wound goes to the next pick and deals X capped at that model; a wound the auto pick FORCES onto an already-wounded Tough
/// model, or one with no pick left, lands by `land_deadly_wounds`. Returns the wounds dealt.
fn land_deadly_picked(state: &mut State, ti: usize, unsaved: i64, x: i64, seams: Seams, alloc: &mut AllocPicks, forced_n: &mut i64) -> i64 {
    let mut dealt = 0;
    for _ in 0..unsaved.max(0) {
        let lead = crate::casualty::chain_casualty_order(state, ti, Some(1), seams.rules_epoch).and_then(|o| o.first().copied());
        let forced = lead.is_some_and(|j| state.kits[ti].get(j).is_some_and(|k| k.wounds_max > 1 && state.wounds[ti][j] < k.wounds_max));
        if x <= 0 {
            // an all-ignored wound: the pick is made (a forced one is counted), nothing lands
            if forced {
                *forced_n += 1;
            } else {
                let _ = alloc.next(state, ti);
            }
            continue;
        }
        dealt += match if forced { None } else { alloc.next(state, ti) } {
            Some(i) => {
                let take = x.max(1).min(state.wounds[ti][i]);
                land_wounds_in_order(state, ti, take, vec![i]);
                take
            }
            None => land_deadly_counted(state, ti, 1, x, seams, forced_n),
        };
    }
    dealt
}

/// One Deadly group on `ti`: the owner's picks when the group has an allocation open, else the automatic landing.
fn land_deadly_group(state: &mut State, ti: usize, unsaved: i64, x: i64, seams: Seams, alloc: &mut Option<AllocPicks>, forced_n: &mut i64) -> i64 {
    match alloc.as_mut() {
        Some(a) => land_deadly_picked(state, ti, unsaved, x, seams, a, forced_n),
        None => land_deadly_counted(state, ti, unsaved, x, seams, forced_n),
    }
}

/// The pool's `w` wounds, one per remaining pick (landed first); the caller lands the rest by `casualty_order`
/// and gets the count left. Says the group's one allocation line.
fn land_pool_picked(state: &mut State, ti: usize, w: i64, alloc: &mut AllocPicks, tray: &mut Tray) -> i64 {
    let mut left = w;
    while left > 0 {
        let Some(i) = alloc.next(state, ti) else { break };
        left -= 1 - land_wounds_in_order(state, ti, 1, vec![i]);
    }
    tray.say(|| LogLine { rule: "wound_alloc", category: Category::Combat, side: state.player[ti],
        text: format!("{}: the owner allocates {} wound{}", state.key(ti), alloc.used, if alloc.used == 1 { "" } else { "s" }), detail: None });
    left
}

/// Rules 3.6 (`EPOCH_73_V36`, ruling D1) — a joined hero is part of the unit: the pool wounds the host's models
/// cannot soak go on to its living joined heroes in `State::attached` order, heroes LAST (the table's
/// `_solo_land_wounds` over the chain). Below 73, or without the attachment seam, the surplus is dropped.
fn land_pool_wounds(state: &mut State, ti: usize, w: i64, exact: bool, seams: Seams, log: &mut Vec<String>) {
    let mut left = land_wounds_with(state, ti, w, exact, seams.rules_epoch);
    if left <= 0 || !seams.hero_attach || !rule_on(seams.rules_epoch, EPOCH_73_V36) {
        return;
    }
    for h in state.attached[ti].clone() {
        if left <= 0 || state.alive[h] <= 0 {
            continue;
        }
        let taken = left - land_wounds_with(state, h, left, exact, seams.rules_epoch);
        left -= taken;
        log.push(format!("Hero: {taken} wound{} beyond the unit's models go on to {}", if taken == 1 { "" } else { "s" }, state.key(h)));
    }
}

/// One-core P3 step 7 — what a landing did to unit `u` against its snapshot `at`/`wounds`: every
/// model whose wounds fell, and every model that vanished (matched by its exact position before; a
/// landing never moves a survivor). `None` when nothing changed. P4.0-1: each model carries its capture-order
/// `slot`: the snapshot's i-th model is the i-th slot not in `gone` (the slots earlier landings on `u` removed).
fn landing_of(state: &State, u: usize, at: &[[f64; 3]], wounds: &[i64], gone: &[usize]) -> Option<Landing> {
    let mut now: Vec<Option<([f64; 3], i64)>> =
        state.positions[u].iter().copied().zip(state.wounds[u].iter().copied()).map(Some).collect();
    let slots = (0..).filter(|s| !gone.contains(s));
    let models: Vec<LandedModel> = at.iter().zip(wounds).zip(slots).filter_map(|((p, &w), slot)| {
        match now.iter_mut().find(|m| m.is_some_and(|(q, _)| q == *p)).and_then(Option::take) {
            Some((_, n)) if n >= w => None,
            Some((_, n)) => Some(LandedModel { at: *p, slot, wounds_left: n, dead: false }),
            None => Some(LandedModel { at: *p, slot, wounds_left: 0, dead: true }),
        }
    }).collect();
    (!models.is_empty()).then_some(Landing { unit: u, models, loss_line: false, moved_to: Vec::new() })
}

/// The table AI's Takedown pick (`attacker_pick_target`): the host's most valuable living model,
/// `casualty_order(..).last()`; without kits the core's last slot. Call with a living model.
fn takedown_pick(state: &State, ti: usize) -> usize {
    crate::casualty::casualty_order(state, ti).and_then(|o| o.last().copied()).unwrap_or(state.positions[ti].len() - 1)
}

/// Table's `_solo_model_label` (main.gd:11009-11021): Tough(X) model, else last weapon name when >1 weapons, else "trooper".
fn takedown_model_label(kits: &[crate::state::Kit], names: &[String], fallback_wounds: i64, slot: usize) -> String {
    if let Some(k) = kits.get(slot) {
        if k.wounds_max > 1 {
            return format!("Tough({}) model", k.wounds_max);
        }
        if k.weapons.len() > 1 {
            return k.weapons.last()
                .and_then(|&id| names.get(id as usize))
                .filter(|s| !s.is_empty())
                .cloned()
                .unwrap_or_else(|| "special weapon".into());
        }
    } else if fallback_wounds > 1 {
        return format!("Tough({fallback_wounds}) model");
    }
    "trooper".into()
}

#[cfg(test)]
fn takedown_pick_cover_after(state: &State, ti: usize, cover: Cover, unit_flag: bool, groups: &[i64], picked: Option<usize>) -> bool {
    takedown_pick_info_after(&[], state, ti, cover, unit_flag, None, groups, picked).0
}

/// Tray-exact S8 — `_solo_model_in_cover` and `_solo_model_label` for the Takedown pick: the centre probe of ITS square
/// and the model's label. The table picks per profile (main.gd:4171), after the earlier Takedown groups of the volley landed
/// inline, so this replays `land_takedown_groups` on a scratch copy of the target's slots: a killed pick is gone, a wounded
/// one ranks first for removal and so never last for the sniper. A recorded node carries no board, so it keeps the unit's flag.
/// `hidden` (the volley's `sight::Screen::hidden`, from 95 only) is the target's models behind a sight blocker,
/// in slot order; the pick is in cover when its square gives cover OR it is hidden.
#[allow(clippy::too_many_arguments)]
fn takedown_pick_info_after(
    statics: &[UnitStatic], state: &State, ti: usize, cover: Cover, unit_flag: bool, hidden: Option<&[bool]>, groups: &[i64],
    picked: Option<usize>,
) -> (bool, String, i64) {
    let names: &[String] = state.kit_names.get(ti).map_or(&[], |v| v.as_slice());
    let n0 = state.positions[ti].len() as i64;
    let fallback_w = state.roster.profile.get(ti)
        .and_then(|&pi| statics.get(pi))
        .and_then(|u| u.wounds_max.first().copied())
        .unwrap_or(1);
    let (mut pos, mut wounds) = (state.positions[ti].clone(), state.wounds[ti].clone());
    let mut hid: Vec<bool> = hidden.map(|h| h.to_vec()).unwrap_or_default();
    let mut picked = picked;
    let mut kits: Vec<crate::state::Kit> = state.kits.get(ti).map(|k| k.to_vec()).unwrap_or_default();
    let pick = |kits: &[crate::state::Kit], pos: &[[f64; 3]], wounds: &[i64]| -> usize {
        if !kits.is_empty() && kits.len() == pos.len() {
            crate::casualty::casualty_order_of(kits, pos, wounds, state.casualty_f32).last().copied().unwrap_or(pos.len() - 1)
        } else {
            pos.len() - 1
        }
    };
    for &g in groups.iter().filter(|&&g| g > 0) {
        if pos.is_empty() || wounds.len() != pos.len() {
            return (unit_flag, "trooper".into(), n0 - pos.len() as i64);
        }
        // P4.0-5: the step API's answer names the first group's model; later groups keep the auto pick.
        let p = picked.take().filter(|&p| p < pos.len()).unwrap_or_else(|| pick(&kits, &pos, &wounds));
        wounds[p] -= g.min(wounds[p]);
        if wounds[p] <= 0 {
            pos.remove(p);
            wounds.remove(p);
            if p < kits.len() {
                kits.remove(p);
            }
            if p < hid.len() {
                hid.remove(p);
            }
        }
    }
    if pos.is_empty() || wounds.len() != pos.len() {
        return (unit_flag, "trooper".into(), n0 - pos.len() as i64);
    }
    let idx = picked.take().filter(|&p| p < pos.len()).unwrap_or_else(|| pick(&kits, &pos, &wounds));
    let in_cover = match cover {
        Cover::Board(t) => crate::terrain::gives_cover(t.type_at([pos[idx][0] as f32, pos[idx][1] as f32, pos[idx][2] as f32])),
        _ => unit_flag,
    } || hid.get(idx).copied().unwrap_or(false);
    (in_cover, takedown_model_label(&kits, names, fallback_w, idx), n0 - pos.len() as i64)
}

/// Tray-exact S7 — `_solo_land_takedown_wounds` (main.gd, Bug 25 / TC-023): each Takedown group
/// lands on ONE model, the attacker's pick `attacker_pick_target` = the target's most valuable
/// living model (`casualty_order(..).last()`; the table's AI never snipes a joined hero), and the
/// overkill is lost (a unit of [1] has nowhere to spill). Without kits the pick is the core's own
/// inverse slot order, the last living slot. Each landing names itself (rules-must-log).
/// P4.0-5: `pick` is the step API's answer for the FIRST group (a slot at the choice, `None` = auto).
fn land_takedown_groups(
    state: &mut State, ti: usize, shot: &mut ShootResult, pick: Option<usize>,
    mut tray: Option<(&mut Tray, &str, i64)>, mut inline: Option<&mut InlineAt<'_>>,
) -> i64 {
    let mut pick = pick;
    let mut dealt = 0;
    let mut lines = std::mem::take(&mut shot.takedown_lines).into_iter();
    let marks = std::mem::take(&mut shot.takedown_marks);
    let groups = std::mem::take(&mut shot.takedown_groups);
    if marks.len() != groups.len() {
        inline = None;
    }
    for (gi, w) in groups.into_iter().enumerate() {
        let line_info = lines.next();
        let n = state.wounds[ti].len();
        if w <= 0 || n == 0 {
            continue;
        }
        // One-core P4.0-5: the step API's answer names the first group's model by its slot; a slot the
        // group has already removed (or a caller that supplied no choice) falls back to the automatic pick.
        let chosen = pick.take().filter(|&p| state.wounds[ti].get(p).is_some_and(|&x| x > 0));
        let pick = chosen.unwrap_or_else(|| takedown_pick(state, ti));
        let take = w.min(state.wounds[ti][pick]);
        dealt += take;
        state.wounds[ti][pick] -= take;
        let killed = state.wounds[ti][pick] <= 0;
        if killed {
            if state.positions[ti].len() == 1 { drop_carried(state, ti); }
            state.wounds[ti].remove(pick);
            remove_position_or_log(state, ti, pick, "land_takedown_groups");
            state.kit_remove(ti, pick);
            if pick < state.radii[ti].len() {
                Rc::make_mut(&mut state.radii)[ti].remove(pick);
            }
        }
        state.alive[ti] = state.positions[ti].len() as i64;
        let what = if killed { "killed" } else { "wounded" };
        shot.log.push(format!("Takedown: {take} of {w} wounds on the picked model of {} - {what}", state.key(ti)));
        if let (Some((t, def_name, side)), Some((weapon, label))) = (tray.as_mut(), line_info) {
            let lbl = if label.is_empty() { "trooper" } else { label.as_str() };
            let text = format!("Takedown ({weapon}): the {lbl} of {def_name} is {what}");
            match inline.as_deref_mut() {
                None => crate::dice::say_rule(t, "takedown", *side, || text),
                // H-17 lines: at the fold's mark, the casualty first, then the Takedown line (the table's inline landing).
                Some(ia) => {
                    let mut at = Some((marks[gi].0 + ia.shift, marks[gi].1));
                    let lost: Vec<i64> = ia.members.iter().map(|&u| i64::from(killed && u == ti)).collect();
                    for l in chain_loss_lines(ia.statics, state, ia.rep, &ia.members, &lost) {
                        say_at_mark(t, &mut at, l);
                    }
                    ia.said.iter_mut().zip(&lost).for_each(|(s, l)| *s += l);
                    say_at_mark(t, &mut at, LogLine { rule: "takedown", category: Category::Combat, side: *side, text, detail: None });
                    ia.shift = at.map_or(ia.shift, |a| a.0 - marks[gi].0);
                }
            }
        }
    }
    dealt
}

/// Deadly(X) landing PER MODEL — the table's `SoloController.apply_deadly_wounds`
/// / `deadly_pick` (solo_controller.gd:9191-9233, GF v3.5.1 p.13 "no carry-over"
/// and p.15 Tough "continue to put wounds on the tough model with most wounds
/// … until it is killed" and "heroes must be assigned wounds last, even if
/// already wounded"). Below `EPOCH_67_MARKERS_BURSTS` (D17): the OLD reading —
/// whichever alive model has the MOST remaining wounds (ties keep array order,
/// strict `>`, so a FRESH Tough model always wins over a damaged one), host
/// only, surplus wasted once the host is wiped. From the gate: host slots
/// first, the attached hero's models only once the host is fully wiped
/// (`state.attached[ti]`); within a member, an ALREADY-WOUNDED Tough slot
/// (current < that slot's own max) goes first — finish it off before starting
/// a fresh one; with none wounded, `land_wounds`'s own slot order (index 0)
/// decides, the same casualty-order convention the plain wound path already
/// uses. `x` capped at that model's remaining wounds each hit, no carry-over
/// either way. Returns the wounds actually dealt (the table's `dealt`).
/// `EPOCH_95_PARITY_BATCH`: do a volley's finished Deadly groups, landed on a scratch copy, leave the target's chain dead?
fn deadly_wiped(state: &State, ti: usize, r: &ShootResult, seams: Seams) -> bool {
    let mut scratch = state.clone();
    r.deadly_groups.iter().for_each(|&(post, dx)| { land_deadly_wounds(&mut scratch, ti, post, dx, seams); });
    combined_alive(&scratch, ti, seams) == 0
}

pub fn land_deadly_wounds(state: &mut State, ti: usize, unsaved: i64, deadly_x: i64, seams: Seams) -> i64 {
    land_deadly_counted(state, ti, unsaved, deadly_x, seams, &mut 0)
}

/// `land_deadly_wounds`, plus the picks that FINISHED an already-wounded Tough model (the table's `deadly_pick` "forced"
/// flag, counted into `forced_n`): the volley line names them.
fn land_deadly_counted(state: &mut State, ti: usize, unsaved: i64, deadly_x: i64, seams: Seams, forced_n: &mut i64) -> i64 {
    let ignored = deadly_x <= 0; // an all-ignored wound (dice.rs `push_deadly_groups`): the pick happens, nothing lands
    let x = deadly_x.max(1);
    let mut dealt = 0i64;
    let epoch67 = rule_on(seams.rules_epoch, EPOCH_67_MARKERS_BURSTS);
    let chain: Vec<usize> = if epoch67 && seams.hero_attach {
        std::iter::once(ti).chain(state.attached[ti].iter().copied()).collect()
    } else {
        vec![ti]
    };
    // A local mirror of each chain member's per-slot max, aligned to
    // `state.wounds[member]` at the START of this call and kept aligned by
    // removing the same index on both sides as models die within the loop
    // below (State only carries the CURRENT wounds; the max lives on the
    // static Profile and never shrinks on its own). Read ONLY on the new
    // leg — a below-gate call must not touch `Profile` at all, so a fixture
    // with fewer profiles than roster entries (every pre-batch-D test) keeps
    // replaying exactly as it did.
    let mut max_of: Vec<Vec<i64>> = if epoch67 {
        chain.iter().map(|&m| state.profile(m).wounds_max.clone()).collect()
    } else {
        Vec::new()
    };
    for _ in 0..unsaved.max(0) {
        let Some(ci) = chain.iter().position(|&m| !state.wounds[m].is_empty()) else {
            break; // everything in the chain is dead — the remaining wounds are wasted
        };
        let m = chain[ci];
        // Tray-exact S6: the table's `deadly_pick` — the member's chain_casualty_order(.., 1)[0].
        let exact = if seams.tray_exact {
            crate::casualty::chain_casualty_order(state, m, Some(1), seams.rules_epoch).and_then(|o| o.first().copied())
        } else {
            None
        };
        let best = if let Some(b) = exact {
            b
        } else if epoch67 {
            (0..state.wounds[m].len())
                .find(|&i| {
                    max_of[ci].get(i).copied().unwrap_or(1) > 1
                        && state.wounds[m][i] < max_of[ci][i]
                })
                .unwrap_or(0)
        } else {
            let mut b = 0usize;
            for (i, w) in state.wounds[m].iter().enumerate() {
                if *w > state.wounds[m][b] {
                    b = i;
                }
            }
            b
        };
        let take = if ignored { 0 } else { x.min(state.wounds[m][best]) };
        if epoch67 && max_of[ci].get(best).is_some_and(|&mx| mx > 1 && state.wounds[m][best] < mx) {
            *forced_n += 1;
        }
        dealt += take;
        state.wounds[m][best] -= take;
        if state.wounds[m][best] <= 0 {
            if state.positions[m].len() == 1 { drop_carried(state, m); }
            state.wounds[m].remove(best);
            remove_position_or_log(state, m, best, "land_deadly_wounds");
            state.kit_remove(m, best);
            // radii stay aligned with positions or the base-edge measure lies.
            if !state.radii[m].is_empty() {
                Rc::make_mut(&mut state.radii)[m].remove(best);
            }
            if epoch67 && best < max_of[ci].len() {
                max_of[ci].remove(best);
            }
        }
    }
    for &m in &chain {
        state.alive[m] = state.positions[m].len() as i64;
    }
    dealt
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
        // H-5a (Plan H): the heal reaches the table as a landing on the patient's capture slot (`wounds_left` above the
        // model's own count = a heal, `CoreActivation.land_step`), and the table's own line (`_solo_apply_mend`) is said.
        // Lines and landings only: the die and the state are untouched, a seeded tray keeps neither.
        let gone = tray.dead_slots(pu);
        let slot = (0..).filter(|s| !gone.contains(s)).nth(pm).unwrap_or(pm);
        let (at, now) = (next.positions[pu][pm], next.wounds[pu][pm]);
        tray.land(|| Landing { unit: pu, models: vec![LandedModel { at, slot, wounds_left: now, dead: false }], loss_line: false, moved_to: Vec::new() });
        let name = statics[next.roster.profile[si]].name.clone();
        tray.say(|| LogLine { rule: "mend", category: Category::Combat, side: next.player[si], detail: None,
            text: format!("Mend: {name} heals {healed} wound{} (D3 rolled {f0}) — patient now {now}/{wmax}",
                if healed == 1 { "" } else { "s" }) });
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

/// A melee tires unit `i` (the charger after its strike phase, the defender after its strike-back). From
/// `EPOCH_91_JOINED_HERO_FATIGUE` the tiredness reaches every hero joined to it as well — the hero is part of the unit and
/// carries no state of its own (the table's `_solo_set_fatigued` loops the attached heroes; `ctx_of_melee` reads each
/// member's own flag, so a hero left fresh would keep striking at full Quality). Before 91, or without the hero fold,
/// only the host index is set, byte for byte as before. It writes no log line: the table's own mirror is silent too.
fn set_melee_fatigue(next: &mut State, i: usize, seams: Seams) {
    next.fatigued[i] = true;
    if seams.hero_attach && rule_on(seams.rules_epoch, EPOCH_91_JOINED_HERO_FATIGUE) {
        for &h in &next.attached[i] {
            next.fatigued[h] = true;
        }
    }
}

/// Rules 3.6 (`EPOCH_73_V36`, the Hero rule) — a melee side still STANDS while its host has a model OR a joined hero
/// lives (the table's `_solo_combined_alive`); below 73 only the host's own models count.
fn side_up(state: &State, i: usize, seams: Seams) -> bool {
    if rule_on(seams.rules_epoch, EPOCH_73_V36) { combined_alive(state, i, seams) > 0 } else { state.alive[i] > 0 }
}

/// Rules 3.6 (`EPOCH_73_V36`) — Blast(X) caps by the target's living model count: host plus any
/// living joined heroes when the book allows joining (`book.hero_aura.joins`). Books with
/// `blast_spread_in` split across neighbouring units separately (Phase 2); while `None`, the cap is
/// the target unit alone, byte-identical to `_solo_combined_alive(target)`.
fn blast_cap_models(state: &State, ti: usize, seams: Seams, book: &crate::rules::Book) -> i64 {
    if book.hero_aura_at(seams.rules_epoch).joins {
        combined_alive(state, ti, seams)
    } else {
        state.alive[ti]
    }
}

/// The units a Blast on `ti` spreads to, with their living models, in `blast_neighbours`' order, when the target's book
/// spreads Blast at this epoch (`Book::blast_spread_in_at`); empty otherwise, which keeps the shot's plain multiply.
fn blast_spread_units(state: &State, ti: usize, seams: Seams) -> Vec<(usize, i64)> {
    match state.book(ti).blast_spread_in_at(seams.rules_epoch) {
        Some(d) => blast_neighbours(state, ti, d),
        None => Vec::new(),
    }
}

/// The skirmish Pushing rule (3.6 p.15, ruling D15): a push holds against an enemy unit this activation's attack hit
/// (`attacked`: the target, a Blast bystander, a damage spell's target) and left Shaken - not Shaken at the activation's
/// start (`before`), Shaken and standing now. The attacker's own side never, nor a unit Shaken by anything but the attack.
fn push_holds(before: &State, now: &State, si: usize, ti: usize, attacked: &[usize]) -> bool {
    now.player[ti] != now.player[si] && attacked.contains(&ti) && !before.shaken[ti] && now.shaken[ti] && now.alive[ti] > 0
}

/// The pushed model's new spot (3.6 p.15: "move one model from the target by up to 2 in in any direction"): `Ok` with the
/// inches it moves and, when the spot lies 2 in or more below it, the inches it falls ("pushed off an elevated position at
/// least 2 in tall"); or why not - no such model, over 2 in, up a ledge, inside a building, or overlapping another model.
fn push_spot(state: &State, ti: usize, p: &crate::activation::PushInput, cover: Cover) -> Result<(f64, Option<f64>), String> {
    let Some(from) = state.positions[ti].get(p.model).copied() else { return Err(format!("model {} is no model of it", p.model + 1)) };
    let moved_in = (p.to[0] - from[0]).hypot(p.to[2] - from[2]) / IN2M;
    if moved_in > 2.0 + 1e-6 {
        return Err(format!("{moved_in:.1} in is over the 2 in"));
    }
    let mut fall = None;
    if let Cover::Board(t) = cover {
        let lvl = |q: [f64; 3]| t.tier_in_at(q[0] / IN2M, q[2] / IN2M);
        let drop = lvl(from) - lvl(p.to);
        if drop < -1e-6 {
            return Err("a push never goes up a ledge".to_string());
        }
        fall = (drop >= 2.0 - 1e-6).then_some(drop);
        if t.solid_at(p.to[0] / IN2M, p.to[2] / IN2M) {
            return Err("a building is in the way".to_string());
        }
    }
    let r = state.radii[ti].get(p.model).copied().unwrap_or(0.0);
    let overlaps = (0..state.positions.len()).filter(|&u| state.alive[u] > 0).any(|u| state.positions[u].iter().zip(state.radii[u].iter())
        .enumerate().any(|(k, (q, &rq))| !(u == ti && k == p.model) && (p.to[0] - q[0]).hypot(p.to[2] - q[2]) < r + rq - 1e-6));
    if overlaps {
        return Err("another model stands there".to_string());
    }
    Ok((moved_in, fall))
}

/// Ruling D14: after a push the pushed unit's other models stand within 1 in of the moved model `m` (base edge to base edge;
/// 3.6 p.15 lets the opponent place them, PUSH-REPLACE): a model already within 1 in stays; else it goes to the legal spot
/// 1 in from the moved model's base nearest to where it stood (24 bearings around it, the straight line first) - not solid,
/// overlapping no model; none -> it stays. Returns the line's tail naming the models that moved or stayed.
fn push_regroup(state: &mut State, ti: usize, m: usize, cover: Cover) -> String {
    let (c, rm) = (state.positions[ti][m], state.radii[ti].get(m).copied().unwrap_or(0.0));
    let (mut moved, mut stuck) = (Vec::new(), Vec::new());
    for k in (0..state.positions[ti].len()).filter(|&k| k != m) {
        let (q, rk) = (state.positions[ti][k], state.radii[ti].get(k).copied().unwrap_or(0.0));
        if !beyond_1in(state, ti, m, k, 1e-9) {
            continue;
        }
        let base = (q[2] - c[2]).atan2(q[0] - c[0]);
        let reach = rm + rk + IN2M;
        let free = |p: [f64; 3], state: &State| {
            !matches!(cover, Cover::Board(t) if t.solid_at(p[0] / IN2M, p[2] / IN2M))
                && (0..state.positions.len()).filter(|&u| state.alive[u] > 0).all(|u| state.positions[u].iter().zip(state.radii[u].iter()).enumerate()
                    .all(|(j, (o, &ro))| (u == ti && j == k) || (p[0] - o[0]).hypot(p[2] - o[2]) >= rk + ro - 1e-9))
        };
        let spot = (0..24).map(|i| base + std::f64::consts::PI * f64::from((i + 1) / 2) / 12.0 * if i % 2 == 0 { 1.0 } else { -1.0 })
            .map(|a| [c[0] + reach * a.cos(), q[1], c[2] + reach * a.sin()]).find(|&p| free(p, state));
        match spot {
            Some(p) => {
                state.positions[ti][k] = p;
                moved.push(k + 1);
            }
            None => stuck.push(k + 1),
        }
    }
    let list = |v: &[usize]| v.iter().map(|k| format!("model {k}")).collect::<Vec<_>>().join(", ");
    let mut tail = String::new();
    if !moved.is_empty() {
        tail += &format!("; {} placed within 1 in of it", list(&moved));
    }
    if !stuck.is_empty() {
        tail += &format!("; {} found no room within 1 in and stays", list(&stuck));
    }
    tail
}

/// Does model `k` of unit `ti` stand more than 1 in (+ `eps` m), base to base, from its model `m`? The one test
/// `push_regroup` and `fall_replace_needed` read.
fn beyond_1in(state: &State, ti: usize, m: usize, k: usize, eps: f64) -> bool {
    let (c, q) = (state.positions[ti][m], state.positions[ti][k]);
    let r = |j: usize| state.radii[ti].get(j).copied().unwrap_or(0.0);
    (q[0] - c[0]).hypot(q[2] - c[2]) - r(m) - r(k) > IN2M + eps
}

/// The table hands positions back as f32 vectors: a model `regroup_around` set exactly 1 in off reads back a few 1e-8 m
/// further. 10 micrometres absorbs that and no player can see it.
const TRANSPORT_EPS_M: f64 = 1e-5;

/// FALL-REPLACE (3.6 p.15, D-27c): after model `m` of unit `ti` fell, does another model of the unit stand more than 1 in
/// from it? Then its owner re-places them (or takes [`regroup_around`]). False for an unknown unit or slot.
pub fn fall_replace_needed(state: &State, ti: usize, m: usize) -> bool {
    state.positions.get(ti).is_some_and(|ps| m < ps.len() && (0..ps.len()).any(|k| k != m && beyond_1in(state, ti, m, k, TRANSPORT_EPS_M)))
}

/// The core's 1 in placer for a fall ("Place for me"): `push_regroup` (ruling D14) on a copy of `state`, nothing written
/// back. The unit's positions after it and the line naming who moved (empty when nobody had to).
pub fn regroup_around(state: &State, ti: usize, m: usize, terrain: &Terrain) -> (Vec<[f64; 3]>, String) {
    let mut next = state.clone();
    let tail = push_regroup(&mut next, ti, m, Cover::Board(terrain));
    let line = tail.strip_prefix("; ").map(|t| format!("Fall: model {} fell; {t}", m + 1)).unwrap_or_default();
    (next.positions[ti].clone(), line)
}

/// The skirmish Blast spread's morale: each neighbour `land_blast_spill` wounded tests like a shot target - the same
/// half-strength trigger and line, then the test.
fn blast_spill_morale(
    statics: &[UnitStatic], next: &mut State, spilled: &[(usize, i64, i64)], over_in: Option<f64>, seams: Seams, tray: &mut Tray, shot: &mut ShootResult,
) {
    for &(nj, alive_before, wounds_before) in spilled {
        let un = &statics[next.roster.profile[nj]];
        if !shooting_morale_trigger(next, statics, seams, un, nj, alive_before, wounds_before) {
            continue;
        }
        if let Some(line) = shooting_morale_line(next, statics, seams, un, nj, alive_before, wounds_before) {
            say_rule(tray, "morale", next.player[nj], || line);
        }
        tray_morale(next, statics, nj, false, seams, tray, shot, over_in, None);
    }
}

/// The skirmish Blast spread's neighbour leg: each weapon's spilled hits on each neighbour resolve as a fixed-hits copy of
/// that weapon (no Blast, Takedown, Hazardous or extra attack) against the neighbour's live context, through the same
/// volley resolver, then land - the pool, then the Deadly groups. One line per neighbour and weapon. Returns each
/// neighbour that took wounds, once, in order, with its living models and wounds left BEFORE its first landing (the
/// shooting morale trigger's inputs).
#[allow(clippy::too_many_arguments)]
fn land_blast_spill(
    statics: &[UnitStatic], next: &mut State, parts: &[(usize, Scratch, Ctx)], spill: &[crate::dice::BlastSpill],
    neighbours: &[usize], (d, mod_d): (f64, f64), melee: bool, seams: Seams, tray: &mut Tray, shot: &mut ShootResult,
) -> Vec<(usize, i64, i64)> {
    let mut hit: Vec<(usize, i64, i64)> = Vec::new();
    for (j, &nj) in neighbours.iter().enumerate() {
        for s in spill {
            let h = s.hits.get(j).copied().unwrap_or(0);
            let Some((mi, _, att)) = parts.get(s.shooter) else { continue };
            if h <= 0 || next.alive[nj] <= 0 {
                continue;
            }
            shot.attacked.push(nj);
            let us = &statics[next.roster.profile[*mi]];
            let mut p = if melee { us.melee[s.profile].clone() } else { us.shoot[s.profile].clone() };
            // A melee weapon's copy reaches the neighbour it spilled onto (range 0 would read as out of reach).
            if melee {
                p.range = p.range.max(1);
            }
            (p.fixed_hits, p.blast, p.takedown, p.extra_attack_q, p.hazardous, p.sergeant_attacks) = (Some(h), 0, false, 0, false, 0);
            // Blast ignores cover, and so does every hit it spills; the skip says itself once, naming Blast.
            (p.ignores_cover, p.cover_rule) = (true, "Blast".into());
            let un = &statics[next.roster.profile[nj]];
            let mut def = with_modifier_sum(with_cond_ap_state(ctx_live(ctx_of(un, next, nj), statics, next, nj, false, seams.rules_epoch), statics, next, nj, seams), seams.rules_epoch);
            stamp_blast_models(&mut def, next, nj, seams);
            def.side = next.player[nj];
            let owner = statics[next.roster.profile[*mi]].name.as_str();
            let sh = [crate::dice::Shooter { profiles: std::slice::from_ref(&p), keep: &[0], attacks: &[1], att, owner }];
            let r = crate::dice::resolve_volley_with_pick_label(
                &sh, &def, &un.name, d, mod_d,
                seams.cond_ap_dice || rule_on(seams.rules_epoch, 1),
                rule_on(seams.rules_epoch, EPOCH_3_TABLE_RULES),
                rule_on(seams.rules_epoch, EPOCH_3_TABLE_RULES),
                shred_boost_active(seams.rules_epoch),
                rule_on(seams.rules_epoch, EPOCH_14_DEADLY_LANDING),
                seams.tray_exact,
                &|_| (false, "trooper".into(), 0), &|_, _| None, None, None, &[], tray,
            );
            let before = (morale_alive(next, nj, seams), morale_wounds_left(next, nj, seams));
            land_pool_wounds(next, nj, r.wounds, seams.tray_exact, seams, &mut shot.log);
            for &(post, gx) in &r.deadly_groups {
                land_deadly_group(next, nj, post, gx, seams, &mut None, &mut 0);
            }
            let took = before != (morale_alive(next, nj, seams), morale_wounds_left(next, nj, seams));
            let line = format!("Blast: {} takes {h} hit{} from {owner}'s {} - {} unsaved", un.name, if h == 1 { "" } else { "s" }, p.name, r.wounds + r.deadly_groups.iter().map(|g| g.0).sum::<i64>());
            shot.log.push(line.clone());
            say_rule(tray, "blast", att.side, || line);
            shot.rolls.extend(r.rolls);
            shot.log.extend(r.log);
            if took && !hit.iter().any(|h| h.0 == nj) {
                hit.push((nj, before.0, before.1));
            }
        }
    }
    hit
}

/// The skirmish Blast(X) spread's neighbours (`dice::blast_split`): every other unit of the target's side on the table
/// with a model whose base edge is within `spread_in` of a target model's base edge, as `(unit, living models)` in unit
/// order. Read by `blast_spread_models` for the shooting leg.
pub fn blast_neighbours(state: &State, ti: usize, spread_in: f64) -> Vec<(usize, i64)> {
    let gap_in = |u: usize, k: usize, v: usize, j: usize| {
        let (p, q) = (state.positions[u][k], state.positions[v][j]);
        geom::pair_gap_m([p[0] as f32, p[1] as f32, p[2] as f32], state.radii[u][k], state.base_shape(u),
            [q[0] as f32, q[1] as f32, q[2] as f32], state.radii[v][j], state.base_shape(v)) / IN2M
    };
    (0..state.units())
        .filter(|&v| v != ti && state.player[v] == state.player[ti] && state.alive[v] > 0 && !state.positions[v].is_empty())
        .filter(|&v| (0..state.positions[ti].len()).any(|k| (0..state.positions[v].len()).any(|j| gap_in(ti, k, v, j) <= spread_in)))
        .map(|v| (v, state.alive[v]))
        .collect()
}

/// Rules 3.6 (`EPOCH_73_V36`) — Blast(X) caps by the table's `_solo_combined_alive(target)`: the host's living
/// models PLUS every living joined hero. Stamped beside `models`, which stays the host's own count.
fn stamp_blast_models(def: &mut Ctx, state: &State, ti: usize, seams: Seams) {
    if rule_on(seams.rules_epoch, EPOCH_73_V36) {
        def.blast_models = Some(blast_cap_models(state, ti, seams, state.book(ti)));
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
        let sdef = shielded_defense(def.defense, def.shielded_bonus(), def.def_floor());
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
    // H-6 (Plan H): the table's own lines (`_solo_apply_breath_attack`) and the landing the step API hands the table.
    let name = statics[next.roster.profile[si]].name.clone();
    if crate::dice::faces_to_hits(&[f0], BREATH_TRIGGER as u8) == 0 {
        tray.say(|| LogLine { rule: "breath_attack", category: Category::Combat, side: pid, detail: None,
            text: format!("Breath Attack: {name} rolls {f0} — fizzles (needs {BREATH_TRIGGER}+)") });
        return;
    }
    let hits = BREATH_BLAST.min(blast_cap_models(next, ti, seams, next.book(ti))).max(1);
    let ut = &statics[next.roster.profile[ti]];
    tray.say(|| LogLine { rule: "breath_attack", category: Category::Combat, side: pid, detail: None,
        text: format!("Breath Attack: {name} breathes on {} — {hits} hit{} (Blast({BREATH_BLAST}), AP({BREATH_AP}))", ut.name,
            if hits == 1 { "" } else { "s" }) });
    let def = ctx_of(ut, next, ti);
    let alive_before = morale_alive(next, ti, seams);
    let wounds_before = morale_wounds_left(next, ti, seams);
    let out = crate::dice::resolve_breath_attack_with_tray(hits, BREATH_AP, &def, &ut.name, tray);
    let landed = shot.absorb(out);
    let before = chain_snapshot(next, ti, tray);
    land_wounds_with(next, ti, landed, seams.tray_exact, seams.rules_epoch);
    land_chain_report(statics, next, tray, ti, before);
    if shooting_morale_trigger(next, statics, seams, ut, ti, alive_before, wounds_before) {
        tray_morale_for(next, statics, ti, false, true, Some("Breath Attack"), seams, tray, shot, None, None);
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
/// `_solo_apply_crossing_attack` main.gd:17086-17130 (call site main.gd:1081,
/// the pre-attack slot after Utility Buff/Storm): once per activation, when
/// the executed move trails pass through enemy units, roll the rule's own
/// rating against the NEAREST crossed enemy — each `wound_target`+ face is
/// one direct wound (`land_wounds`, no save), exactly the table's
/// `_solo_land_wounds(target, wounds, 0)`. The trails are the mover's own
/// legs, `state` -> `next` per alive model (rigid translation or movement
/// port alike), matched against alive enemy base discs the way
/// `SoloController.trails_cross_unit_bases` (solo_controller.gd:8844-8863)
/// does — pure segment-vs-disc geometry, no terrain input. Gate: the FROZEN
/// `EPOCH_7_TABLE_RULES`; a record below 7 never rolls.
/// `_solo_try_reanimation` main.gd:4710-4757 + `_solo_resolve_reanimation`
/// main.gd:4758-4830 + the automatic v1 spend (solo_controller.gd:5862-5918),
/// fired at the TOP of `resolve_with` — the table's own trigger point
/// (main.gd:953-957: activation-trigger rules run BEFORE the action).
/// WOUND CURRENCY (main.gd:4683-4691): a dead casualty is its full
/// wounds_max (land_wounds removed them from the FRONT of the arrays, so the
/// first profile.wounds_max entries are the dead ones), a living wounded
/// model its missing wounds; SHAKEN DOES NOT REANIMATE. Spend: living
/// wounded first (heroes first, biggest gap), then casualties cheapest-first
/// at one wound; a revive with no legal spot EXPIRES the success (v1) — one
/// candidate spot, bases touching the nearest standing model away from the
/// unit centre, clear of every other unit's bases. Chain: host + attached
/// heroes. Gate: FROZEN `EPOCH_7_TABLE_RULES`.
pub(crate) fn tray_reanimation(
    statics: &[UnitStatic], next: &mut State, si: usize, seams: Seams,
    tray: &mut Tray, shot: &mut ShootResult, board: Option<&Terrain>,
) {
    let Some(spec) = statics[next.roster.profile[si]].reanimation.clone() else { return };
    let spot_rule = rule_on(seams.rules_epoch, crate::acts::EPOCH_96_PARITY_BATCH);
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) || next.shaken[si] {
        return; // below-7 replays byte-exact; the Shaken activation stays idle (main.gd:4731)
    }
    let owner = statics[next.roster.profile[si]].name.clone();
    let side = next.player[si];
    // The step path's lines are the tray's: every Reanimation sentence is said there too, in the same words.
    let say = |tray: &mut Tray, shot: &mut ShootResult, line: String| {
        say_rule(tray, "reanimation", side, || line.clone());
        shot.log.push(line);
    };
    let mut members: Vec<usize> = vec![si];
    if seams.hero_attach {
        members.extend(next.attached[si].iter().copied());
    }
    if spot_rule {
        // EPOCH_96_PARITY_BATCH (REVIVE-MEMBERS, lead ruling): the rule fires only for a unit where ALL models carry it, and a
        // joined hero is part of the unit - a standing joined hero without it means no roll for the whole chain.
        let (has, standing) = (|u: usize| statics[next.roster.profile[u]].reanimation.is_some(), |u: usize| !next.positions[u].is_empty());
        if !members.iter().any(|&u| next.profile(u).wounds_max.iter().sum::<i64>() > next.wounds[u].iter().sum::<i64>()) {
            return; // nothing to restore: no roll and no line, on both sides
        }
        if members.iter().any(|&u| standing(u) && !has(u)) {
            say(tray, shot, format!("Reanimation: {owner} does not reanimate — a joined model lacks the rule"));
            return;
        }
        // Lead ruling "Aura bearer dead": the Aura gives Reanimation to "this model and its unit" - with every bearer fallen the
        // chain no longer has it (the table's `reanimation_members` ends the Aura the same way).
        let aura = |u: usize| next.profile(u).special_rules.iter().chain(&next.profile(u).item_grants).any(|r| r.trim() == "Reanimation Aura");
        if members.iter().any(|&u| aura(u)) && !members.iter().any(|&u| aura(u) && standing(u)) {
            say(tray, shot, format!("Reanimation: {owner} does not reanimate — the Reanimation Aura bearer has fallen"));
            return;
        }
        members.retain(|&u| has(u)); // a fallen joined hero without the rule is not in the pool
    }
    // The pool — WOUND CURRENCY, per member of the carrying chain.
    let (mut gaps, mut dead) = (Vec::new(), Vec::new());
    for &u in &members {
        let (wm, w) = (&next.profile(u).wounds_max, &next.wounds[u]);
        for (m, &cur) in w.iter().enumerate() {
            if let Some(gap) = wm.get(m).map(|mx| mx - cur).filter(|g| *g > 0) {
                gaps.push((u, m, gap));
            }
        }
        for &cost in wm.iter().take(wm.len() - w.len()) {
            dead.push((u, cost.max(1)));
        }
    }
    let pool: i64 = gaps.iter().map(|g| g.2).sum::<i64>() + dead.iter().map(|d| d.1).sum::<i64>();
    if pool <= 0 {
        return;
    }
    let faces = tray.roll(pool as usize);
    shot.rolls.push(crate::dice::Roll {
        kind: "attack", count: pool, target: spec.target,
        faces: faces.clone(), owner: owner.clone(),
    });
    let mut left = faces.iter().filter(|&&f| f as i64 >= spec.target).count() as i64;
    say(tray, shot, format!("Reanimation: {owner} rolls {pool} dice ({}) — {left} success(es)", spec.target));
    // Phase A — living wounded: heroes first, biggest gap, index tie-break.
    gaps.sort_by(|a, b| {
        let h = |u: usize| statics[next.roster.profile[u]].is_hero as i8;
        h(b.0).cmp(&h(a.0)).then(b.2.cmp(&a.2)).then(a.0.cmp(&b.0)).then(a.1.cmp(&b.1))
    });
    for &(u, m, gap) in &gaps {
        if left <= 0 {
            break;
        }
        let take = gap.min(left);
        next.wounds[u][m] += take;
        left -= take;
    }
    // Phase B — casualties back cheapest-first; a revive with no legal spot
    // EXPIRES the success (v1, main.gd:4843). ONE candidate spot: bases
    // touching the nearest standing model, away from the unit centre, clear
    // of every other unit's bases.
    dead.sort_by(|a, b| a.1.cmp(&b.1).then(a.0.cmp(&b.0)));
    // EPOCH_96_PARITY_BATCH: the anchors are the chain's models standing BEFORE the first restore (host slot order, then
    // the joined heroes that carry the rule themselves - `SoloController.reanimation_members`), captured once - a model
    // restored a moment ago is no anchor.
    let anchors: Vec<([f64; 3], f64)> = if spot_rule {
        members.iter().filter(|&&u| statics[next.roster.profile[u]].reanimation.is_some()).flat_map(|&u| next.positions[u].iter().enumerate()
            .map(|(k, p)| (*p, next.radii[u].get(k).copied().unwrap_or(DEFAULT_BASE_RADIUS_M))).collect::<Vec<_>>()).collect()
    } else {
        Vec::new()
    };
    // EPOCH_96_PARITY_BATCH: the table's spend (`SoloController.reanimation_plan`), fixed BEFORE placing: each casualty
    // stands up at ONE wound, cheapest first, then the top-ups in the same order; an entry with no legal spot expires whole.
    let mut plan: Vec<(usize, i64, i64)> = dead.iter().map(|&(u, cost)| (u, cost, 0)).collect();
    if spot_rule {
        plan.truncate(left.max(0) as usize);
        left -= plan.len() as i64;
        for e in plan.iter_mut() {
            let top = (e.1 - 1).min(left);
            e.2 = 1 + top;
            left -= top;
        }
    }
    for &(u, cost, planned) in &plan {
        if !spot_rule && left <= 0 {
            break;
        }
        // EPOCH_96_PARITY_BATCH: the returning model keeps its unit's own base (metres; 0 = not set).
        let own_r = statics[next.roster.profile[u]].base_radius;
        let r = if spot_rule && own_r > 0.0 { own_r } else { DEFAULT_BASE_RADIUS_M };
        let spot = if spot_rule {
            revive_ring(board, next, &anchors, r)
        } else {
            if next.positions[u].is_empty() {
                continue; // nothing stands to anchor a revive
            }
            let c = geom::centre(&next.positions[u]);
            let (cx, cz) = (c[0] as f64, c[2] as f64);
            let (mut ai, mut best) = (0usize, f64::INFINITY);
            for (i, p) in next.positions[u].iter().enumerate() {
                let d = (p[0] - cx).hypot(p[2] - cz);
                if d < best {
                    best = d;
                    ai = i;
                }
            }
            let a = next.positions[u][ai];
            let a_r = next.radii[u].get(ai).copied().unwrap_or(DEFAULT_BASE_RADIUS_M);
            let (dx, dz) = (a[0] - cx, a[2] - cz);
            let n = (dx * dx + dz * dz).sqrt();
            let (ux, uz) = if n <= f64::EPSILON { (0.0, 0.0) } else { (dx / n, dz / n) };
            let dist = a_r + r + 0.002;
            let spot = [a[0] + ux * dist, a[1], a[2] + uz * dist];
            let clear = (0..next.units()).all(|ti| {
                members.contains(&ti)
                    || next.positions[ti].iter().all(|p| {
                        (p[0] - spot[0]).hypot(p[2] - spot[2]) > DEFAULT_BASE_RADIUS_M * 2.0 + 0.002
                    })
            });
            clear.then_some(spot)
        };
        let Some(spot) = spot else {
            say(tray, shot, "Reanimation: 1 success but no placeable spot — coherency missing".into());
            continue;
        };
        let back = if spot_rule { planned } else { cost.min(left).max(1) };
        next.wounds[u].insert(0, back);
        next.positions[u].insert(0, spot);
        Rc::make_mut(&mut next.radii)[u].insert(0, r);
        next.kits_drop(u); // the revived body's kit is unknown: this unit falls back to slot order
        next.alive[u] = next.positions[u].len() as i64;
        left -= if spot_rule { 0 } else { back };
        say(tray, shot, format!("Reanimation: 1 model restored ({back} wound(s) back)"));
    }
}

/// REVIVE SPOT (`EPOCH_96_PARITY_BATCH`), the table's ring (`_solo_reanimation_spot` without the "where it fell" spot): per
/// anchor in chain order, the base gap 2 mm then 0.5 in + 2 mm (both inside the 1 in coherency), 16 headings each from +X toward
/// +Z; the first legal spot wins, at the anchor's height. `None`: nowhere legal, the model is not restored. Draws no die.
fn revive_ring(board: Option<&Terrain>, next: &State, anchors: &[([f64; 3], f64)], r: f64) -> Option<[f64; 3]> {
    for &(a, a_r) in anchors {
        for gap in [0.002, 0.5 * IN2M + 0.002] {
            for k in 0..16 {
                let (sin, cos) = (std::f64::consts::TAU * f64::from(k) / 16.0).sin_cos();
                let c = [a[0] + cos * (a_r + r + gap), a[1], a[2] + sin * (a_r + r + gap)];
                if !revive_line_blocked(board, a, c) && revive_spot_legal(board, next, [c[0], c[2]], r) {
                    return Some(c);
                }
            }
        }
    }
    None
}

/// REVIVE SPOT (`EPOCH_96_PARITY_BATCH`): does the straight line from the anchor to a ring candidate cross a ruin / container wall,
/// a cliff or a house wall, or end on another tier level? Then the model would come back behind a thin wall or across a tier step
/// (the outer ring reaches past the wall band `rest_forbidden` keeps clear). Always `false` without a board.
fn revive_line_blocked(board: Option<&Terrain>, a: [f64; 3], c: [f64; 3]) -> bool {
    let Some(t) = board else { return false };
    let (ia, ic) = (t.to_inch([a[0] as f32, 0.0, a[2] as f32]), t.to_inch([c[0] as f32, 0.0, c[2] as f32]));
    let level = |p: [f64; 3]| t.tier_in_at(p[0] / t.in2m(), p[2] / t.in2m());
    crate::mv::geom2::path_crosses_wall(ia, ic, t.walls_in_tiered())
        || crate::mv::geom2::path_crosses_wall([a[0] as f32, a[2] as f32], [c[0] as f32, c[2] as f32], &t.solid_walls_world_m())
        || level(a) != level(c)
}

/// REVIVE SPOT (`EPOCH_96_PARITY_BATCH`): may a restored model of base radius `r` (metres) stand at world `c` (x, z metres)?
/// The whole base on the table, no rest where `mv::gate::rest_forbidden` refuses one (impassable terrain, a wall or cliff within
/// r + 2 mm), not over an intact house nor within r + 1 mm of its wall (`lands_in_house`), and clear (r + r_other + 1 mm) of every
/// standing base, its own unit's included. The terrain clauses run only on a real board (`board` is `Some`).
fn revive_spot_legal(board: Option<&Terrain>, next: &State, c: [f64; 2], r: f64) -> bool {
    if let Some(t) = board {
        let half = [t.board_in()[0] * t.in2m() * 0.5, t.board_in()[1] * t.in2m() * 0.5];
        if half[0] > 0.0 && (c[0].abs() + r > half[0] || c[1].abs() + r > half[1]) {
            return false;
        }
        let p = t.to_inch([c[0] as f32, 0.0, c[1] as f32]);
        let w = [c[0] as f32, c[1] as f32];
        if crate::mv::gate::rest_forbidden([f64::from(p[0]), f64::from(p[1])], r / IN2M, t)
            || t.solid_at(c[0] / t.in2m(), c[1] / t.in2m())
            || t.solid_walls_world_m().iter().any(|s| crate::mv::geom2::point_seg_distance(w, s[0], s[1]) < r + 0.001)
        {
            return false;
        }
    }
    (0..next.units()).all(|u| next.positions[u].iter().enumerate().all(|(k, p)| {
        (p[0] - c[0]).hypot(p[2] - c[1]) >= r + next.radii[u].get(k).copied().unwrap_or(DEFAULT_BASE_RADIUS_M) + 0.001
    }))
}

/// "The first time this unit is activated, pick one enemy unit within 6\" in
/// line of sight, and roll X dice. For each 2+ it takes one hit with AP(1)"
/// (army-book Surprise Attack; the gf/aof registry entry's own params).
/// Fires at the activation trigger BEFORE the action, next to Reanimation.
/// Below `EPOCH_67_MARKERS_BURSTS` (D19 a): FIRST-ACTIVATION latch, replay-
/// stable form — no recorded per-unit activation counter exists and the
/// table's burst arm was the audit-B open question, so the port fires only
/// on a ROUND-1 activation — one act per unit per round makes that the
/// first activation for every unit on the board at round start.
/// From `EPOCH_67_MARKERS_BURSTS`: `State.surprise_attack_used` (folded from
/// the ledger, main.gd stamps it the same way) is the real per-bearer
/// latch — a spent bearer never fires again in ANY round, and a round-2+
/// FIRST activation (e.g. an Infiltrate/Ambush arrival) fires it, which the
/// old `round != 1` gate could never reach. Gate: FROZEN `EPOCH_7_TABLE_RULES`
/// for the family itself, `EPOCH_67_MARKERS_BURSTS` for which latch reads.
pub(crate) fn tray_surprise_attack(
    statics: &[UnitStatic], state: &State, next: &mut State, si: usize, seams: Seams,
    tray: &mut Tray, shot: &mut ShootResult,
) {
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) { return; }
    if next.alive[si] <= 0 { return; }
    let epoch67 = rule_on(seams.rules_epoch, EPOCH_67_MARKERS_BURSTS);
    if !epoch67 && next.round != 1 { return; }
    let pid = next.player[si];
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach { bearers.extend(next.attached[si].iter().copied()); }
    for b in bearers {
        if next.alive[b] <= 0 { continue; }
        let Some(spec) = statics[next.roster.profile[b]].surprise_attack.clone() else { continue; };
        if epoch67 {
            if next.surprise_attack_used[b] { continue; }
            next.surprise_attack_used[b] = true;
        }
        let owner = statics[next.roster.profile[b]].name.clone();
        surprise_strike(statics, state, next, b, seams, tray, shot, spec, owner, pid);
    }
}

/// The burst body: pick one enemy (alive, un-reserved, unattached, within the
/// rule's own range, in line of sight when the entry asks), roll the rating at
/// `trigger_target`, each success one AP(1) hit — the Storm Attack port's
/// descending pick (largest `combined_alive`, first-index tie-break).
fn surprise_strike(
    statics: &[UnitStatic], state: &State, next: &mut State, b: usize, seams: Seams,
    tray: &mut Tray, shot: &mut ShootResult, spec: crate::unit::SurpriseAttackSpec, owner: String,
    pid: i64,
) {
    let targets: Vec<usize> = (0..next.units())
        .filter(|&ti| next.player[ti] != pid && next.alive[ti] > 0 && combined_alive(next, ti, seams) > 0 && !next.dormant[ti] && !(seams.hero_attach && next.attached_to[ti].is_some()))
        .filter(|&ti| geom::edge_gap_in(&next.positions[b], &next.radii[b], &next.positions[ti], &next.radii[ti], DEFAULT_BASE_RADIUS_M) <= spec.range_in)
        .filter(|&ti| !spec.needs_los || los_clear(state, b, ti))
        .collect();
    if targets.is_empty() { return; }
    let mut best = targets[0];
    for &t in targets.iter().skip(1) {
        if combined_alive(next, t, seams) > combined_alive(next, best, seams) { best = t; }
    }
    let faces = tray.roll(spec.dice.max(1) as usize);
    shot.rolls.push(crate::dice::Roll {
        kind: "attack", count: spec.dice, target: spec.trigger,
        faces: faces.clone(), owner: owner.clone(),
    });
    let successes = crate::dice::faces_to_hits(&faces, spec.trigger as u8) as i64;
    shot.log.push(format!("Surprise Attack: {owner} strikes unawares — {successes} of {} dice hit", spec.dice));
    let ut = &statics[next.roster.profile[best]];
    let def = ctx_of(ut, next, best);
    let (ab, wb) = (morale_alive(next, best, seams), morale_wounds_left(next, best, seams));
    let landed = shot.absorb(crate::dice::resolve_storm_hits_with_tray(successes, spec.ap, false, false, &def, &ut.name, tray));
    land_wounds_with(next, best, landed, seams.tray_exact, seams.rules_epoch);
    if shooting_morale_trigger(next, statics, seams, ut, best, ab, wb) {
        tray_morale_for(next, statics, best, false, true, Some("Surprise Attack"), seams, tray, shot, None, None);
    }
}

/// The move-through seam's shared pick — the shape `tray_crossing_attack` and
/// `tray_strafing` both need: the ACTING unit's executed trails (one straight
/// leg per alive model, `state` -> `next`; `last_move_paths` is the activated
/// unit's own move, a leg that moves nothing crosses nothing) matched against
/// alive, un-reserved, UNATTACHED enemies — `trails_cross_unit_bases`'
/// segment-vs-disc test (solo_controller.gd:8844-8863) in the WORLD-METRE frame
/// the state already carries (radii are metres too) — then the table's own
/// pick: the crossed unit NEAREST the acting unit's centre (main.gd:17115-17118
/// for the Crossing Attack, main.gd:3000-3004 for Strafing), first index on a
/// tie. `None` = nothing crossed (or nothing moved). `bidx` is whose OWN legs
/// are tested (D20 a, `EPOCH_67_MARKERS_BURSTS`: an attached hero's own
/// trail, not always the activating unit's); `si` still centres the
/// nearest-pick — the table sorts by `MoveIntent.distance_inches(unit_centre
/// (unit), …)`, the ACTIVATING unit, not each bearer's own centre.
fn crossed_enemy_of(
    statics: &[UnitStatic], state: &State, next: &State, si: usize, bidx: usize, seams: Seams,
) -> Option<(usize, String)> {
    let pid = next.player[bidx];
    let legs = bearer_legs(state, next, bidx);
    let crossed: Vec<usize> = (0..next.units())
        .filter(|&ti| {
            next.player[ti] != pid && next.alive[ti] > 0 && !next.dormant[ti]
                && !(seams.hero_attach && next.attached_to[ti].is_some())
                && legs_cross_unit(next, &legs, ti)
        })
        .collect();
    let centre = geom::centre(&next.positions[si]);
    let dist = |ti: usize| geom::length(geom::sub(geom::centre(&next.positions[ti]), centre));
    let target = crossed.iter().copied().min_by(|&x, &y| dist(x).total_cmp(&dist(y)))?;
    Some((target, statics[next.roster.profile[target]].name.clone()))
}

/// One straight leg per alive model of `bidx`, `state` -> `next` (a leg that
/// moves nothing crosses nothing) — the shared trail read `crossed_enemy_of`
/// and the per-model crossing count both build on.
fn bearer_legs(state: &State, next: &State, bidx: usize) -> Vec<([f64; 2], [f64; 2])> {
    (0..next.positions[bidx].len())
        .filter_map(|m| {
            let a = state.positions.get(bidx)?.get(m)?;
            let b = next.positions.get(bidx)?.get(m)?;
            Some(([a[0], a[2]], [b[0], b[2]]))
        })
        .filter(|(a, b)| (b[0] - a[0]).hypot(b[1] - a[1]) > f64::EPSILON)
        .collect()
}

/// Whether any leg in `legs` crosses an alive model's base disc of `ti`.
fn legs_cross_unit(next: &State, legs: &[([f64; 2], [f64; 2])], ti: usize) -> bool {
    (0..next.positions[ti].len()).any(|m| {
        if next.wounds[ti].get(m).map(|&w| w <= 0).unwrap_or(false) {
            return false;
        }
        let c = &next.positions[ti][m];
        let r = next.radii[ti].get(m).copied().unwrap_or(DEFAULT_BASE_RADIUS_M);
        legs.iter().any(|&(a, b)| {
            let seg = [b[0] - a[0], b[1] - a[1]];
            let t = (((c[0] - a[0]) * seg[0] + (c[2] - a[1]) * seg[1])
                / (seg[0] * seg[0] + seg[1] * seg[1])).clamp(0.0, 1.0);
            let (dx, dy) = (a[0] + seg[0] * t - c[0], a[1] + seg[1] * t - c[2]);
            dx * dx + dy * dy <= r * r
        })
    })
}

/// D20 (a): the number of `bidx`'s OWN models whose individual leg crosses
/// `ti`'s base (GF p.4 "this model" = a model rule, not a unit-wide one) —
/// floored at 1 so a caller that already knows `legs_cross_unit` is true
/// never reads a zero-dice roll.
fn crossing_models_against(next: &State, legs: &[([f64; 2], [f64; 2])], ti: usize) -> i64 {
    legs.iter().filter(|&&leg| legs_cross_unit(next, std::slice::from_ref(&leg), ti)).count().max(1) as i64
}

/// A chain's members before a landing: (unit, positions, wounds).
type ChainBefore = Vec<(usize, Vec<[f64; 3]>, Vec<i64>)>;

/// `ti`'s chain (host, then its joined heroes) before a landing. Only a supplied tray takes it (a seeded
/// one clones nothing); `land_chain_report` reads it after the landing.
fn chain_snapshot(next: &State, ti: usize, tray: &Tray) -> Option<ChainBefore> {
    tray.feed().is_some().then(|| std::iter::once(ti).chain(next.attached[ti].iter().copied())
        .map(|u| (u, next.positions[u].clone(), next.wounds[u].clone())).collect())
}

/// One-core P3 steps 7/25/27, shared by the volley and the move-through attacks: at the landing's stamp `_solo_apply_wounds`'s
/// lines (main.gd:16582-16600): the wounds that landed on the chain, then per member the models it lost (main.gd:18376-18395,
/// :25123); then one landing per changed member, its loss line said here. A seeded tray (`None`) says and records nothing.
fn land_chain_report(statics: &[UnitStatic], next: &State, tray: &mut Tray, ti: usize, before: Option<ChainBefore>) {
    land_chain_report_inline(statics, next, tray, ti, before, 0);
}

/// The lines of a landing's casualties: per chain member that lost models (`lost`, parallel to `members`), "loses a model", "loses N
/// models" or "destroyed", the counter read from `next` as it stands (host and joined heroes counted together for the host).
fn chain_loss_lines(statics: &[UnitStatic], next: &State, ti: usize, members: &[usize], lost: &[i64]) -> Vec<LogLine> {
    let size = |u: usize| statics[next.roster.profile[u]].model_count;
    let (alive, total) = members.iter().fold((0, 0), |(a, t), &u| (a + next.alive[u], t + size(u)));
    members.iter().zip(lost).filter_map(|(&u, &lost)| {
        let (a, t) = if u == ti { (alive, total) } else { (next.alive[u], size(u)) };
        let name = &statics[next.roster.profile[u]].name;
        let text = match (lost, a) {
            (..=0, _) => return None,
            (_, 0) => format!("{name} destroyed"),
            (1, _) => format!("{name} loses a model ({a}/{t})"),
            _ => format!("{name} loses {lost} models ({a}/{t})"),
        };
        Some(LogLine { rule: "shoot", category: Category::Combat, side: next.player[u], text, detail: None })
    }).collect()
}

/// One line of a Deadly weapon's landing: at its mark among the strike's lines when it has one (`at` moves past it), else at the end.
fn say_at_mark(tray: &mut Tray, at: &mut Option<(usize, usize)>, line: LogLine) {
    match at {
        Some(a) => { tray.say_at(*a, || line); a.0 += 1; }
        None => tray.say(|| line),
    }
}

/// How many models each member of a chain holds now.
fn model_counts(next: &State, members: &[usize]) -> Vec<usize> {
    members.iter().map(|&u| next.positions[u].len()).collect()
}

/// What the table's wound line counts when part of the event landed inline (a melee's Deadly / Takedown): `said[i]` the
/// models member `i` of the chain already lost under the Deadly landing's own line, `pool` the pool wounds that got past the ignore rolls.
/// The table says "takes N wounds" only when some reach the pool, and N then counts the inline wounds too (`_solo_apply_wounds`'s
/// `taken_before`, #2826); the casualty line after it names the pool's own.
struct InlineSaid { said: Vec<i64>, pool: i64 }

/// Plan H (H-17 lines): where a volley's inline landings (Takedown, Deadly) say their lines: the target chain (`members`, reported as
/// `rep`), how far the lines said so far moved the fold's marks (`shift`), and the models each member lost under them (`said`).
struct InlineAt<'a> { statics: &'a [UnitStatic], members: Vec<usize>, rep: usize, shift: usize, said: Vec<i64> }

/// `land_chain_report`, less the wounds the table lands model by model with their own line (the volley's Deadly): `inline`.
fn land_chain_report_inline(statics: &[UnitStatic], next: &State, tray: &mut Tray, ti: usize, before: Option<ChainBefore>, inline: i64) {
    land_chain_report_said(statics, next, tray, ti, before, inline, None);
}

fn land_chain_report_said(statics: &[UnitStatic], next: &State, tray: &mut Tray, ti: usize, before: Option<ChainBefore>, inline: i64, said: Option<&InlineSaid>) {
    let Some(ch) = before else { return };
    let ut = &statics[next.roster.profile[ti]];
    let size = |u: usize| statics[next.roster.profile[u]].model_count;
    let (alive, total) = ch.iter().fold((0, 0), |(a, t), (u, ..)| (a + next.alive[*u], t + size(*u)));
    let took_all: i64 = ch.iter().map(|(u, _, w)| w.iter().sum::<i64>() - next.wounds[*u].iter().sum::<i64>()).sum();
    let took = match said { Some(s) => if s.pool > 0 { took_all } else { 0 }, None => took_all - inline };
    // NML-1091: a unit that IS one multi-wound model counts that model's wounds instead.
    let (n, of, unit) = match ut.wounds_max.first() {
        Some(&m) if total == 1 && m > 1 => (next.wounds[ti].first().copied().unwrap_or(0).max(0), m, " wounds"),
        _ => (alive, total, ""),
    };
    if took > 0 {
        tray.say_wounds(|| LogLine { rule: "shoot", category: Category::Combat, side: next.player[ti],
            text: format!("{} takes {took} wound{} ({n}/{of}{unit})", ut.name, if took == 1 { "" } else { "s" }), detail: None });
    }
    let members: Vec<usize> = ch.iter().map(|(u, ..)| *u).collect();
    let lost: Vec<i64> = ch.iter().enumerate().map(|(i, (u, at, _))| at.len() as i64 - next.positions[*u].len() as i64 - said.map_or(0, |s| s.said[i])).collect();
    for line in chain_loss_lines(statics, next, ti, &members, &lost) {
        tray.say_wounds(|| line);
    }
    // The table's `_solo_hero_carries_on` (the end of `_solo_apply_wounds`): the host has no model left, so each living joined hero that
    // carries the unit's Shaken / Fatigue says so.
    if took > 0 && next.alive[ti] <= 0 {
        for &h in next.attached[ti].iter().filter(|&&h| next.alive[h] > 0 && (next.shaken[h] || next.fatigued[h])) {
            let state = match (next.shaken[h], next.fatigued[h]) { (true, true) => "Shaken + Fatigue", (true, false) => "Shaken", _ => "Fatigue" };
            let text = format!("{} fights on alone — carries the unit's {state} ({CITE})", statics[next.roster.profile[h]].name);
            tray.say_wounds(|| LogLine { rule: "shoot", category: Category::Combat, side: next.player[h], text, detail: None });
        }
    }
    tray.release_outcome();
    for (u, at, wounds) in ch {
        if let Some(l) = landing_of(next, u, &at, &wounds, &tray.dead_slots(u)) {
            tray.land(|| Landing { loss_line: true, ..l });
        }
    }
}

pub(crate) fn tray_crossing_attack(
    statics: &[UnitStatic], state: &State, next: &mut State, si: usize, seams: Seams,
    tray: &mut Tray, shot: &mut ShootResult,
) {
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) {
        return;
    }
    // D20 (a): below the gate every bearer still reads the ACTIVATING unit's
    // own legs (byte-identical to the pre-batch-D reading); from the gate
    // each bearer reads its OWN legs and the dice count scales by how many
    // of ITS models actually crossed (GF p.4 "this model").
    let epoch67 = rule_on(seams.rules_epoch, EPOCH_67_MARKERS_BURSTS);
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach {
        bearers.extend(state.attached[si].iter().copied());
    }
    for b in bearers {
        if next.alive[b] <= 0 {
            continue;
        }
        let Some(spec) = statics[next.roster.profile[b]].crossing_attack.clone() else { continue };
        let owner = statics[next.roster.profile[b]].name.clone();
        let legs_of = if epoch67 { b } else { si };
        // Alive, un-reserved, UNATTACHED enemies whose bases an executed trail
        // touches, then the table's own pick — the shared
        // `crossed_enemy_of` read above (main.gd:17115-17118).
        let Some((target, tname)) = crossed_enemy_of(statics, state, next, si, legs_of, seams) else {
            continue;
        };
        let crossing_models = if epoch67 {
            crossing_models_against(next, &bearer_legs(state, next, b), target)
        } else {
            1
        };
        let n = (spec.dice.max(1) * crossing_models) as usize;
        let faces = tray.roll(n);
        shot.rolls.push(crate::dice::Roll {
            kind: "attack", count: n as i64, target: spec.wound_target,
            faces: faces.clone(), owner: owner.clone(),
        });
        let wounds = faces.iter().filter(|&&f| f as i64 >= spec.wound_target).count() as i64;
        shot.log.push(format!(
            "Crossing Attack: {owner} crosses {tname} — {wounds} of {n} dice wound"
        ));
        // The step API shows the table's own sentence (`_solo_apply_crossing_attack`).
        tray.say(|| LogLine { rule: "crossing_attack", category: Category::Combat, side: next.player[b], detail: None,
            text: format!("Crossing Attack: {crossing_models} model{} of {owner} cross {tname} — {wounds} of {n} dice wound (no save)",
                if crossing_models == 1 { "" } else { "s" }) });
        if wounds > 0 {
            let before = chain_snapshot(next, target, tray);   // the landing the step API hands the table
            land_wounds_with(next, target, wounds, seams.tray_exact, seams.rules_epoch);
            land_chain_report(statics, next, tray, target, before);
        }
    }
}

/// NML-002 STRAFING (14.09., sweep row `Strafing`, TABLE-ONLY): "Once per
/// activation, when this model moves through enemy units, pick one of them and
/// attack it with this weapon as if it was shooting. This weapon may only be
/// used in this way." The table resolves it at main.gd:1092-1096
/// (`_solo_apply_strafing` main.gd:2964-3007), AFTER Teleport and BEFORE the
/// Crossing Attack in the pre-attack slot order; the registry carries
/// `Strafing {move_through_attack: true, weapon_only: true}`. The core only
/// ever stamped the flag (unit.rs:1130) and marked the fold (dice.rs:945-946)
/// — no move-through seam existed, so a strafing aircraft flew past in silence.
/// The port mirrors the table beat by beat:
///   * TRIGGER — the EXECUTED move's trails (`last_move_paths`): one straight
///     leg per alive model of the acting unit, `state` -> `next`, exactly
///     `tray_crossing_attack`'s legs; a leg that moves nothing crosses nothing
///     (the table's own empty-path early-out, main.gd:2965).
///   * CROSSING TEST — `SoloController.trails_cross_unit_bases`
///     (solo_controller.gd:8844-8863): segment-vs-disc per ALIVE enemy model,
///     the same test `tray_crossing_attack` mirrors, in the state's
///     world-metre frame.
///   * PICK — the crossed enemy NEAREST the acting unit's centre
///     (main.gd:3000-3004), first index on a tie.
///   * ATTACK — ONE shooting exchange with ONLY the Strafing profiles
///     (`UnitStatic::strafe_shoot`, the unit + its joined heroes at their own
///     Quality/alive scaling), through the shared volley resolver
///     `resolve_volley_leg` — the same fold the normal volley runs, the same
///     tail (spent Limited marks, absorb, land, Deadly's per-model leg, the
///     post-volley morale die). `moved_this_round = true`: the table passes
///     `moved` (main.gd:3007). Once per activation by construction — the slot
///     runs once per resolve. `weapon_only` needs no seam of its own: the
///     import's Strafing filter (unit.rs::profiles_in_range) already keeps the
///     weapon out of every normal volley.
///   * REPLAY — io.rs's act record carries no strafe field of its own (the
///     act's `shoot` key is the planner's pick); the strafe is DERIVED here at
///     the table's own slot, so a `dice="table"` replay consumes the same tray
///     faces at the same point of the stream — the recorded outcome is
///     honoured by the seam itself. Gate: the FROZEN `EPOCH_32_STRAFING`.
pub(crate) fn tray_strafing(
    statics: &[UnitStatic], state: &State, next: &mut State, si: usize, seams: Seams,
    tray: &mut Tray, shot: &mut ShootResult, cover: Cover,
) {
    if !rule_on(seams.rules_epoch, EPOCH_32_STRAFING) || next.alive[si] <= 0 { return; }
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach { bearers.extend(state.attached[si].iter().copied()); }
    // The chain's carriers (main.gd:2967-2985): the unit + its joined heroes,
    // each firing its OWN Strafing profiles at its own Quality. No carrier, no
    // strafe — the table's `shots.is_empty()` early-out (main.gd:2986-2987).
    if !bearers.iter().any(|&b| next.alive[b] > 0
        && !statics[next.roster.profile[b]].strafe_shoot.is_empty()) { return; }
    // The crossing test and the table's pick — the shared `crossed_enemy_of`
    // read (the table's `trails_cross_unit_bases` test, main.gd:3000-3004).
    // Strafing is untouched by D20 (a): always the ACTIVATING unit's own legs.
    let Some((target, tname)) = crossed_enemy_of(statics, state, next, si, si, seams) else { return; };
    // Rules-must-log — ONE line per strafe, the table's own log line
    // (main.gd:3005-3006).
    // The line names the rule the weapon carries: Crossing Strike (3.6) or Strafing (3.5).
    let rule = crate::unit::strafing_rule_name(bearers.iter().filter(|&&b| next.alive[b] > 0)
        .flat_map(|&b| statics[next.roster.profile[b]].strafe_shoot.iter()));
    let said = format!("{rule}: {} passes over {tname} — attacks it as if shooting (once per activation)",
        statics[next.roster.profile[si]].name);
    shot.log.push(said.clone());
    tray.say(|| LogLine { rule: "strafing", category: Category::Combat, side: next.player[si], text: said, detail: None });   // the step API shows it
    // ONE shooting exchange, ONLY the Strafing profiles, through the shared
    // volley resolver — main.gd:3007's `_solo_resolve_ai_volley(unit, target,
    // shots, true)`: the activation's modifier distance, the
    // defender's live context, the members at their own Quality.
    let d = volley_distance_in(next, si, target, seams);
    let ut = &statics[next.roster.profile[target]];
    let mut def = with_modifier_sum(with_cond_ap_state(ctx_live(ctx_of(ut, next, target), statics, next, target, false, seams.rules_epoch), statics, next, target, seams), seams.rules_epoch);
    stamp_blast_models(&mut def, next, target, seams);
    def.side = next.player[target]; // One-core P3 step 25: the save line's seat
    // D-STEALTH — the strafe volley reads the defender's live context the
    // same way the table's `_solo_resolve_ai_volley` does (main.gd:3007), so
    // the def build carries the same terrain gate.
    stealth_alias_terrain_gate(statics, next, target, cover, &mut def);
    let (alive_before, wounds_before) = (morale_alive(next, target, seams), morale_wounds_left(next, target, seams));
    // Per member (host first, then each alive attached hero): the Strafing
    // profiles in range, survivor-scaled — `profiles_of`'s shape over
    // `strafe_shoot`.
    let parts: Vec<(usize, Vec<usize>, Vec<i64>, Ctx)> = bearers.iter().filter_map(|&b| {
        if next.alive[b] <= 0 { return None; }
        let um = &statics[next.roster.profile[b]];
        // Per member (host first, then each alive attached hero): the Strafing
        // profiles in range, survivor-scaled — `profiles_of`'s shape over
        // `strafe_shoot`.
        // AIG-G2 R3 (`EPOCH_73_V36`): the target is the crossed unit, so the printed range (0 on Drop Bombs) gates nothing.
        let reach_gate = !rule_on(seams.rules_epoch, EPOCH_73_V36);
        let (keep, attacks): (Vec<usize>, Vec<i64>) = um.strafe_shoot.iter().enumerate()
            .filter(|(_, p)| !reach_gate || (p.range as f64) >= d)
            .map(|(i, p)| (i, effective_attacks(p.attacks, next.alive[b], um.model_count)))
            .unzip();
        if keep.is_empty() { return None; }
        // The table passes `moved=true` for the strafe volley (main.gd:3007) —
        // the Indirect moved-penalty fold reads it.
        let mut att = ctx_live_vs(ctx_of(um, next, b), statics, next, b, target, false, seams.rules_epoch);
        att.moved_this_round = true;
        att.strafe_volley = !reach_gate;
        att.side = next.player[b];
        Some((b, keep, attacks, att))
    }).collect();
    let shooters: Vec<crate::dice::Shooter> = parts.iter()
        .map(|(b, keep, attacks, att)| crate::dice::Shooter {
            profiles: &statics[next.roster.profile[*b]].strafe_shoot, keep, attacks, att,
            owner: &statics[next.roster.profile[*b]].name,
        }).collect();
    // The SAME gate pack the normal volley's `resolve_volley_leg` call passes
    // (sim.rs's shoot branch) — the strafe is "as if shooting".
    let r = crate::dice::resolve_volley_with_pick_label(
        &shooters, &def, &ut.name, d, d,
        seams.cond_ap_dice || rule_on(seams.rules_epoch, 1),
        rule_on(seams.rules_epoch, EPOCH_3_TABLE_RULES),
        rule_on(seams.rules_epoch, EPOCH_3_TABLE_RULES),
        shred_boost_active(seams.rules_epoch),
        rule_on(seams.rules_epoch, EPOCH_14_DEADLY_LANDING),
        seams.tray_exact,
        &|gr: &[i64]| takedown_pick_info_after(statics, next, target, cover, def.in_cover, None, gr, seams.takedown_pick),
        &|_, _| None,
        None,
        rule_on(seams.rules_epoch, crate::acts::EPOCH_95_PARITY_BATCH).then_some(&|r: &ShootResult| deadly_wiped(next, target, r, seams)),
        // Deny (skirmish Blast spread): the 3.6 Firefight and AoF: Skirmish books have no Aircraft and no Strafing, so no
        // skirmish game ever strafes; the strafe's Blast stays on the unit it crossed in every book.
        &[],
        tray,
    );
    // The volley tail, the shoot branch's own shape: spent Limited marks,
    // absorb, land, Deadly's per-model leg, the post-volley morale die — so
    // the tray stream stays the table's own order.
    for (b, keep, _, _) in &parts {
        mark_spent_limited(&statics[next.roster.profile[*b]].strafe_shoot, keep, &mut next.limited_used, *b);
    }
    // EPOCH_96_PARITY_BATCH: the strafe has no exchange spend, so the Bane Mark it read is spent here (once, never twice).
    if parts.iter().any(|(_, _, _, att)| att.bane_mark_grant) {
        mods::spend_mark_vs(next, target, "Bane Mark");
    }
    let phantom = r.scourge_wounds;
    let w = shot.absorb(r);
    let members: Vec<usize> = parts.iter().map(|(b, _, _, _)| *b).collect();
    land_hazardous_self(statics, next, &members, seams, tray, shot);
    let before = chain_snapshot(next, target, tray);   // the landing the step API hands the table
    if !seams.tray_exact {
        land_pool_wounds(next, target, w, false, seams, &mut shot.log);
    }
    let side = next.player[si];
    let td_dealt = land_takedown_groups(next, target, shot, seams.takedown_pick, Some((tray, &ut.name, side)), None);
    shot.deadly_lines.clear(); // the volley's per-weapon lines are said at the AI volley's own landing only
    for &(post, dx) in std::mem::take(&mut shot.deadly_groups).iter() {
        let dl = land_deadly_wounds(next, target, post, dx, seams);
        shot.log.push(format!("Deadly({dx}): {post} unsaved ×{dx}, no carry-over → {dl} wounds dealt"));
    }
    if seams.tray_exact {
        land_pool_wounds(next, target, w, true, seams, &mut shot.log); // the table's order: Takedown, Deadly, then the pool
    }
    land_chain_report_inline(statics, next, tray, target, before, td_dealt);
    let log_from = shot.log.len();
    let trigger = scourge_morale_trigger(next, statics, seams, ut, target, alive_before, wounds_before, phantom, &mut shot.log);
    say_scourge(tray, next.player[target], &shot.log[log_from..]);
    if trigger {
        tray_morale(next, statics, target, false, seams, tray, shot, Some(d), None);
    }
}

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
            Rc::make_mut(&mut next.storm_used)[b].push(spec.name.clone());
            let faces = tray.roll(spec.dice.max(1) as usize);
            shot.rolls.push(crate::dice::Roll {
                kind: "attack", count: spec.dice, target: spec.trigger,
                faces: faces.clone(), owner: owner.clone(),
            });
            let successes = crate::dice::faces_to_hits(&faces, spec.trigger as u8) as i64;
            shot.log.push(format!("{}: {} unleashes the storm — {} of {} dice hit (once per game)", spec.name, owner, successes, spec.dice));
            // H-7 (Plan H): the table's own line (`_solo_apply_storm_attack`) and, per success, the landing the step API hands the table.
            tray.say(|| LogLine { rule: "storm_attack", category: Category::Combat, side: next.player[b], detail: None,
                text: format!("{}: {} unleashes the storm — {} of {} dice hit (once per game)", spec.name, owner, successes, spec.dice) });
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
                let (alive_before, wounds_before) = (morale_alive(next, best, seams), morale_wounds_left(next, best, seams));
                let (ap, bane, shred) = match spec.facet {
                    StormFacet::Ap1 => (1, false, false), StormFacet::Bane => (0, true, false),
                    StormFacet::Shred => (0, false, true), StormFacet::Surge => (0, false, false),
                };
                let landed = shot.absorb(crate::dice::resolve_storm_hits_with_tray(hits, ap, bane, shred, &def, &ut.name, tray));
                let before = chain_snapshot(next, best, tray);
                land_wounds_with(next, best, landed, seams.tray_exact, seams.rules_epoch);
                land_chain_report(statics, next, tray, best, before);
                if shooting_morale_trigger(next, statics, seams, ut, best, alive_before, wounds_before) {
                    tray_morale_for(next, statics, best, false, true, Some(&spec.name), seams, tray, shot, None, None);
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
            let speed_debuff = b.target == "enemy" && crate::rules::base_rule_name(&b.grants_rule) == "Slow";
            let e73 = rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36);
            for ti in utility_targets(statics, next, bearer, b, seams) {
                // Rules 3.6 Speed Debuff: an ordinary model of a multi-model
                // unit is no legal pick; a single-model unit or a joined hero
                // keeps the unit-level Slow grant.
                let blocked = speed_debuff && e73 && next.alive[ti] > 1 && next.attached[ti].is_empty();
                if speed_debuff && e73 {
                    trace_rule("utility-buff", &b.name, &format!("{}: picks {} — {}", statics[pb].name,
                        statics[next.roster.profile[ti]].name,
                        if blocked { "no effect (ordinary model of a multi-model unit)" } else { "Slow on the whole unit (single model or joined hero)" }));
                }
                if blocked { continue; }
                record_buff(next, ti, b, seams.rules_epoch);
                // EPOCH_58_PRECISION_DEBUFF — the fold's rules-must-log line
                // (`trace_rule`, the ap/def + move-row shape): the debuff
                // rides the victim's own net, so the line names the -1, the
                // victim and the lifetime the book prints. The row can only
                // exist from the stamp gate (`unit.rs::utility_buffs_of`),
                // so the trace needs no epoch check of its own.
                if b.name == "Precision Debuff" && b.hit_mod != 0 {
                    trace_rule("utility-buff", &b.name, &format!(
                        "{:+} to hit on {} until end of round",
                        b.hit_mod, statics[next.roster.profile[ti]].name));
                }
            }
        }
    }
}

/// `main._solo_record_spell_mod` :3649-3670 — one record onto the picked
/// unit's ledger, with the GDScript's own two guards: a record with neither a
/// modifier nor a grant never lands (:3653/:3663). `beneficiary` is hard-coded
/// "" at the Utility-Buff call site (:16541), so these are always the bearer's
/// own net, never an attackers-side one.
///
/// SEAM 4 step 1 (design §4(c), the FROZEN `EPOCH_7_TABLE_RULES`): from epoch
/// 7 the guard also accepts a row whose only knob is one of the three ap/def
/// knobs — below 7 the row keeps being dropped, so the core's own serialized
/// states replay byte-identical. Rules-must-log: a widened row names itself.
/// The MOVE-BUFF knob (`EPOCH_12_MOVE_BUFF`) widens the guard the same way:
/// from epoch 12 a row whose only knob is `move_mod` lands — and the knob is
/// carried ONLY on such a row, which is what `mods::LiveMod::move_mod`'s
/// non-zero contract rests on.
fn record_buff(state: &mut State, ti: usize, b: &UtilityBuff, rules_epoch: u32) {
    let widened = rule_on(rules_epoch, EPOCH_7_TABLE_RULES)
        && (b.ap_mod, b.def_mod, b.defense_mod) != (0, 0, 0);
    let move_row = rule_on(rules_epoch, EPOCH_12_MOVE_BUFF) && b.move_mod != 0;
    if b.hit_mod == 0 && b.casting_mod == 0 && b.morale_mod == 0 && b.grants_rule.is_empty()
        && !widened && !move_row
    {
        return;
    }
    state.buffs[ti].push(mods::LiveMod {
        hit_mod: b.hit_mod,
        casting_mod: b.casting_mod,
        morale_mod: b.morale_mod,
        ap_mod: b.ap_mod,
        def_mod: b.def_mod,
        defense_mod: b.defense_mod,
        move_mod: b.move_mod,
        range_in: 0,
        grants_rule: Rc::from(b.grants_rule.as_str()),
        scope: Rc::from(b.scope.as_str()),
        attackers: b.beneficiary == "attackers",
        once: b.once,
        name: Rc::from(b.name.as_str()),
    });
    if widened {
        trace_rule("utility-buff", &b.name, "ap/def row recorded (epoch 7)");
    }
    if move_row {
        trace_rule("utility-buff", &b.name, &format!("move row recorded: +{}\" on move actions (epoch 12)", b.move_mod));
    }
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

/// The INDEX of the chain member that pays for a cast: the unit itself when it
/// is a Caster, else the first living joined caster hero (`caster_member`'s
/// rule, resolved to a member so Spell Drain can spend from the right pool).
fn caster_member_of(statics: &[UnitStatic], state: &State, u: usize, seams: Seams) -> Option<usize> {
    if statics[state.roster.profile[u]].is_caster {
        return Some(u);
    }
    if !seams.hero_attach {
        return None;
    }
    state.attached[u]
        .iter()
        .copied()
        .find(|&h| state.alive[h] > 0 && statics[state.roster.profile[h]].is_caster)
}


/// `main._solo_utility_targets` :16317-16359 — up to `max_targets` legal picks
/// for one buff, best VALUE first (`alive_count + Tough`, :16358). Alive,
/// non-reserve, never an ATTACHED unit (a joined hero is bought through its
/// host), the kind's own filter, the printed range measured centre to centre
/// (`MoveIntent.distance_inches` :16344) and sight when the params ask for it.
///
/// WAVE 4 FOLLOW-UP, Extended Buff Range (was NOT PORTED here through wave 4):
/// a friendly candidate beyond the printed 12" pick range is still legal when
/// the relay clause holds (:16473-16520, `SoloController.ebr_relay_ok`
/// :892-895) — BOTH ends carry the rule, the relay unit has its Hero, and the
/// base-edge link between relay and candidate is within the TARGET's own
/// `relay_range_in`. Exactly ONE hop (the relay is the BUFFING hero's own
/// unit, `_solo_combat_unit`); enemy-side picks and non-12" ranges are
/// excluded by the same `ebr_open` bound the table prints. LOS is checked for
/// relayed candidates too (:16489, the check sits AFTER the range gate). GATED
/// `rule_on(rules_epoch, EPOCH_7_TABLE_RULES)` via the stamp.
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
    // The relay unit is the BUFFING hero's OWN unit (:16467, a joined hero
    // relays through its host); the waiver opens only for friendly picks at
    // the printed 12" pick range (:16469).
    let relay = if seams.hero_attach { state.attached_to[bearer].unwrap_or(bearer) } else { bearer };
    let ebr_open = rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES)
        && b.target == "friendly"
        && (b.range_in - EBR_PICK_RANGE_IN).abs() < 1e-6;
    // Rules 3.6 Speed Debuff (MOR-19): one enemy MODEL is picked, so prefer a
    // single-model unit or one whose joined hero keeps the Slow on the unit.
    let speed_debuff = rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36)
        && b.target == "enemy" && crate::rules::base_rule_name(&b.grants_rule) == "Slow";
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
            // Extended Buff Range: the only way past the printed range is the
            // relay clause (:16474-16484) — the relay itself is never its own
            // extended target.
            if !ebr_open || u == relay || !ebr_relay_ok(statics, state, relay, u, seams) {
                continue;
            }
        }
        if b.needs_los && !los_clear(state, bearer, u) {
            continue;
        }
        let mut v = state.alive[u] as f64 + uc.tough as f64;
        if speed_debuff && (state.alive[u] == 1 || !state.attached[u].is_empty()) { v += 100.0; }
        scored.push((v, u));
    }
    scored.sort_by(|a, c| c.0.partial_cmp(&a.0).unwrap_or(std::cmp::Ordering::Equal));
    scored.truncate(b.max_targets.max(1) as usize);
    scored.into_iter().map(|(_, u)| u).collect()
}

/// `SoloController.EBR_PICK_RANGE_IN` :886 — the printed friendly pick range
/// the waiver is bound to ("special rules that allow it to pick friendly
/// units within 12\"").
pub const EBR_PICK_RANGE_IN: f64 = 12.0;

/// `SoloController.ebr_relay_ok` :892-895 + `_solo_ebr_relay_gap`
/// main.gd:16527-16537 — the whole relay clause: the TARGET carries the rule
/// itself (its own stamp), the relay unit carries it through any LIVING
/// member (`unit_carries_ebr` :904-912), the relay satisfies the Hero clause
/// (`ebr_relay_has_hero` :936-954), and the base-edge gap between the relay
/// and the candidate is within the TARGET's own `relay_range_in`.
fn ebr_relay_ok(
    statics: &[UnitStatic],
    state: &State,
    relay: usize,
    ti: usize,
    seams: Seams,
) -> bool {
    let Some(params) = statics[state.roster.profile[ti]].ebr.as_ref() else { return false; };
    let relay_carries = statics[state.roster.profile[relay]].ebr.is_some()
        || (seams.hero_attach
            && state.attached[relay].iter().any(|&h| {
                state.alive[h] > 0 && statics[state.roster.profile[h]].ebr.is_some()
            }));
    if !relay_carries || !ebr_relay_has_hero(statics, state, relay, params.hero_link_in, seams) {
        return false;
    }
    let gap = geom::edge_gap_in(
        &state.positions[relay], &state.radii[relay], &state.positions[ti], &state.radii[ti],
        DEFAULT_BASE_RADIUS_M,
    );
    gap <= params.relay_range_in
}

/// `SoloController.ebr_relay_has_hero` :936-954 — with `hero_link_in == 0`
/// (the shipped GF/AoF entries) a living Hero must be IN the relay unit's own
/// chain; a positive link (skirmish wording) accepts any friendly living Hero
/// within that gap of the relay.
fn ebr_relay_has_hero(
    statics: &[UnitStatic],
    state: &State,
    relay: usize,
    hero_link_in: f64,
    seams: Seams,
) -> bool {
    let in_unit = statics[state.roster.profile[relay]].is_hero
        || (seams.hero_attach
            && state.attached[relay].iter().any(|&h| {
                state.alive[h] > 0 && statics[state.roster.profile[h]].is_hero
            }));
    if in_unit || hero_link_in <= 0.0 {
        return in_unit;
    }
    let pid = state.player[relay];
    for u in 0..state.units() {
        if u == relay || state.player[u] != pid || state.alive[u] <= 0 || state.dormant[u] {
            continue;
        }
        if !statics[state.roster.profile[u]].is_hero {
            continue;
        }
        let gap = geom::edge_gap_in(
            &state.positions[relay], &state.radii[relay], &state.positions[u], &state.radii[u],
            DEFAULT_BASE_RADIUS_M,
        );
        if gap <= hero_link_in {
            return true;
        }
    }
    false
}

/// `main._solo_consume_once_mods` :3823-3841 — one resolved exchange spends
/// every `once` record that was AVAILABLE to it: the attacker's own hit mods
/// and rule grants, the defender's attackers-beneficiary mods and grants.
/// SEAM 4 step 2 adds the two knobs whose seams now exist: the shooter-side
/// `ap_mod` (Piercing Debuff's "loses AP(+1) when attacking") and the
/// defender's "defense" role (ai_spell.gd:352 — the `def_mod`/`defense_mod`
/// roll-bonus pair). The "range"/"speed" roles stay absent — their seams do
/// not exist yet, the same gap, not a second one.
/// Test-only wrapper: the precision-debuff unit test spends a plain exchange.
#[cfg(test)]
fn spend_exchange(state: &mut State, att: usize, def: usize, melee: bool) {
    let att_roles: &[mods::Role] = if melee {
        &[mods::Role::AttackerOwn, mods::Role::Ap, mods::Role::Grant]
    } else {
        &[mods::Role::AttackerOwn, mods::Role::Ap, mods::Role::Grant, mods::Role::Range]
    };
    mods::spend_once(state, att, att_roles, melee);
    mods::spend_once(state, def, &[mods::Role::VsTarget, mods::Role::Defense, mods::Role::Grant, mods::Role::GrantVs], melee);
}

const PROTECTION_FEAT: &str = "Protection Feat";

/// #2613 (EPOCH_75_TABLE_FIXES) — the once-per-game Protection Feat is spent by its first REAL ignore roll: a
/// wound reached the roll and the Feat's 5+ is the target that binds (a better plain Regeneration rolls alone).
pub(crate) fn spend_protection_feat(statics: &[UnitStatic], state: &mut State, def: usize, def_incoming: bool, rules_epoch: u32) {
    let c = &statics[state.roster.profile[def]].ctx;
    if !rule_on(rules_epoch, EPOCH_75_TABLE_FIXES) || !def_incoming || c.regen_feat <= 0
        || state.feats_used[def].iter().any(|n| n == PROTECTION_FEAT)
        || (c.regen_target > 0 && c.regen_target < c.regen_feat)
    {
        return;
    }
    Rc::make_mut(&mut state.feats_used)[def].push(PROTECTION_FEAT.to_string());
    trace_rule("protection-feat", &statics[state.roster.profile[def]].name, "spends its once-per-game ignore roll");
}

/// DAT-17a — the exchange spend with the Regeneration grant's epoch gate.
fn spend_exchange_wounded(
    state: &mut State, att: usize, def: usize, melee: bool, att_wounded: bool, def_incoming: bool,
    rules_epoch: u32,
) {
    let att_roles: &[mods::Role] = if melee {
        &[mods::Role::AttackerOwn, mods::Role::Ap, mods::Role::Grant]
    } else {
        &[mods::Role::AttackerOwn, mods::Role::Ap, mods::Role::Grant, mods::Role::Range]
    };
    let def_roles = [mods::Role::VsTarget, mods::Role::Defense, mods::Role::Grant, mods::Role::GrantVs];
    // EPOCH 73: the grant is spent by the FIRST exchange that brings a wound in
    // to its holder — an all-ignored roll still spends it, a zero-wound exchange
    // does not. The holder's own attack still keeps it. Below 73 the old
    // unconditional spend answers for both sides (replay-exact).
    let v36 = rule_on(rules_epoch, EPOCH_73_V36);
    let att_had = [Some(att), state.attached_to[att]].into_iter().flatten()
        .any(|u| state.buffs[u].iter().any(mods::is_regen_grant));
    let def_had = [Some(def), state.attached_to[def]].into_iter().flatten()
        .any(|u| state.buffs[u].iter().any(mods::is_regen_grant));
    mods::spend_once_except(state, att, att_roles, melee, |r| v36 && (mods::keep_regen(r, att_wounded) || mods::attacked_only_grant(r)));
    mods::spend_once_except(state, def, &def_roles, melee, |r| v36 && mods::keep_regen(r, def_incoming));
    if v36 && att_wounded && att_had {
        trace_rule("regen-grant", "Regeneration Buff", &format!("spent by a wounding exchange (unit {att})"));
    }
    if v36 && def_incoming && def_had {
        trace_rule("regen-grant", "Regeneration Buff", &format!("spent by a wounding exchange (unit {def})"));
    }
}

/// `main._solo_apply_vs_marks` :16738-16771 — the ENEMY-side half of the
/// Utility-Buff family (Unstoppable Mark). It does not run at the pre-attack
/// slot: the pick IS the attack's committed target, so the table calls it at
/// the attack seam itself (:3042 inside a volley group, :8035 in a charge —
/// after Impact, before the strikes). Every bearer of the attacker's joined
/// chain may mark once per round; the rule's base name (the entry minus
/// " Mark") lands on the ATTACKER as a once-grant, and `ctx_live` carries it
/// into the very rolls this seam precedes.
#[allow(clippy::too_many_arguments)] // the tray and report join the seam's parity args
fn tray_vs_marks(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    ti: usize,
    dist_in: f64,
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
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
        // MOR-16a (EPOCH_73_V36): "Spell Drain" replaces these carriers'
        // "Casting Debuff"; its pick is the committed target at this seam,
        // once per bearer and round on the Mark latch, range/sight as a Mark.
        if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36)
            && next.vs_mark_round[bearer] != next.round
        {
            if let Some(b) = statics[pb].utility_buffs.iter().find(|b| {
                b.spell_token_drain > 0 && dist_in <= b.range_in
                    && (!b.needs_los || los_clear(next, bearer, ti))
            }) {
                next.vs_mark_round[bearer] = next.round;
                let owner = statics[pb].name.clone();
                let target_name = statics[next.roster.profile[ti]].name.clone();
                // FAB-B3: the Morale test (and the Shaken it may leave) always
                // lands on the drained unit. The TOKEN loss needs a caster
                // member of that chain — the unit itself or its joined caster
                // hero; with none, the target simply has no pool to lose.
                let passed = control_morale_passed(statics, next, ti,
                    ControlMoraleSource { owner: &owner, rule: "Spell Drain", on_target: false }, seams, tray, shot);
                if passed {
                    shot.log.push(format!("Spell Drain: {} passes the Morale test, no tokens lost", target_name));
                    trace_rule("cast", "Spell Drain", &format!("{} drains {}: no tokens (test passed)",
                        owner, target_name));
                } else if let Some(cm) = caster_member_of(statics, next, ti, seams) {
                    let before = next.casts[cm];
                    let spent = b.spell_token_drain;
                    let after = (before - spent).max(0);
                    next.casts[cm] = after;
                    let member_name = statics[next.roster.profile[cm]].name.clone();
                    shot.log.push(format!("Spell Drain: {} loses {} spell tokens", member_name, before - after));
                    trace_rule("cast", "Spell Drain", &format!("{} drains {} via {}: two tokens {} -> {}",
                        owner, target_name, member_name, before, after));
                } else {
                    shot.log.push(format!("Spell Drain: {} has no spell tokens to lose", target_name));
                    trace_rule("cast", "Spell Drain", &format!("{} drains {}: no caster in its chain",
                        owner, target_name));
                }
            }
        }
        for b in &statics[pb].utility_buffs {
            if !b.vs_target || next.vs_mark_round[bearer] == next.round || dist_in > b.range_in {
                continue;
            }
            // EPOCH 9 MARK FAMILY (#870, 11.09.): the five names #870 flipped
            // from `vs_marked` to `vs_target` (Rapid Charge, Piercing Fighting,
            // Slayer, Piercing Shooting, Unpredictable Shooter) are NEW grants —
            // a record stamped before epoch 9 (every pre-fix corpus) must
            // replay as it was recorded, so it fires only at `EPOCH_9_MARK_FAMILY`
            // and above. Every other Mark is untouched.
            if (b.name == "Rapid Charge Mark"
                || b.name == "Piercing Fighting Mark"
                || b.name == "Slayer Mark"
                || b.name == "Piercing Shooting Mark"
                || b.name == "Unpredictable Shooter Mark")
                && !rule_on(seams.rules_epoch, EPOCH_9_MARK_FAMILY)
            {
                continue;
            }
            // NML-936 (:16758): the printed rule picks "within 18\" IN LINE OF
            // SIGHT", and `needs_los` may waive it from the data.
            if b.needs_los && !los_clear(next, bearer, ti) {
                continue;
            }
            next.vs_mark_round[bearer] = next.round;
            let base = b.name.strip_suffix(" Mark").unwrap_or(b.name.as_str());
            // EPOCH 23 INERT MARKS (MARK_FAMILY_SWEEP_2026-09-14 finding 1):
            // the grant the mark hands the attacker is the entry's own
            // `grants_rule` ("AP(+1) in melee" / "AP(+1) when shooting"), not
            // the base name — the base name is read by nobody, so the mark was
            // stamped and spent for nothing. Below 23 the base name rides and
            // every corpus replays the recorded inert mark.
            let grant = if rule_on(seams.rules_epoch, EPOCH_23_INERT_MARKS)
                && !b.grants_rule.is_empty()
            {
                b.grants_rule.clone()
            } else {
                base.to_string()
            };
            // EPOCH 44 SURGE MARK — rules-must-log, the placement half: the
            // pick names itself the one time the mark lands (the consumption
            // half logs at the dice folds). Trace-gated like every other
            // core-side seam line.
            // Rules-must-log (Plan H): the table says the pick and the record's activation (`_solo_apply_vs_marks`, then the
            // record's own `... is ACTIVE` line), both naming the MARKED unit, which holds the record there; the core keeps the
            // legacy attacker-side grant below EPOCH_71 for the Rapid Charge Mark and for every other Mark, so the lines carry the target.
            let (bearer_name, target_name) = (&statics[pb].name, &statics[next.roster.profile[ti]].name);
            say_rule(tray, "mark", next.player[bearer], || format!(
                "{}: {} marks {} — friendly units attacking it gain {} (once)", b.name, bearer_name, target_name, grant));
            say_rule(tray, "mark", next.player[bearer], || format!(
                "{} on {} is ACTIVE: grants {}{} — applies ONCE", b.name, target_name, grant,
                if b.scope.is_empty() { String::new() } else { format!(" ({} only)", b.scope) }));
            if b.name == "Surge Mark" {
                trace_rule("mark", &b.name, &format!(
                    "{} marks {} — friendly units attacking it gain {} (once)",
                    statics[pb].name, statics[next.roster.profile[ti]].name, grant));
            }
            // #845 option (b) — the core half of the table fix (#870/#1204):
            // the Rapid Charge Mark is an ATTACKERS-side grant on the MARKED
            // ENEMY (`_solo_apply_vs_marks` :19544 records the entry's own
            // scope/beneficiary there), and `rapid_charge_mark_bonus_in`
            // reads exactly that record off the target. From
            // `EPOCH_71_RAPID_CHARGE_MARK` the Mark lands on the TARGET; below it
            // the legacy once-grant stays on the bearer so older corpora
            // replay byte-exact. Rules-must-log: the placement names itself.
            let on_target = (grant == "Rapid Charge" && rule_on(seams.rules_epoch, EPOCH_71_RAPID_CHARGE_MARK))
                || (grant == "AP(+1) in melee" && b.scope == "melee" && rule_on(seams.rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH));
            if on_target {
                trace_rule("mark", &b.name, &format!(
                    "{} marks {} — friendly units attacking it gain {} (once)",
                    statics[pb].name, statics[next.roster.profile[ti]].name, grant));
                shot.marks_open.push((b.name.clone(), ti, ti));
                next.buffs[ti].push(mods::LiveMod {
                    hit_mod: 0,
                    casting_mod: 0,
                    morale_mod: 0,
                    ap_mod: 0,
                    def_mod: 0,
                    defense_mod: 0,
                    move_mod: 0,
                    range_in: 0,
                    grants_rule: Rc::from(grant.as_str()),
                    scope: Rc::from(b.scope.as_str()),
                    attackers: b.beneficiary == "attackers",
                    once: b.once,
                    name: Rc::from(b.name.as_str()),
                });
            } else {
                shot.marks_open.push((b.name.clone(), si, ti));
                next.buffs[si].push(mods::LiveMod {
                    hit_mod: 0,
                    casting_mod: 0,
                    morale_mod: 0,
                    ap_mod: 0,
                    def_mod: 0,
                    defense_mod: 0,
                    move_mod: 0,
                    range_in: 0,
                    grants_rule: Rc::from(grant),
                    scope: Rc::from(""),
                    attackers: false,
                    once: true,
                    name: Rc::from(b.name.as_str()),
                });
            }
        }
    }
}

/// The table's consumption line for a Mark (`_solo_spend_records`): the exchange spent the record `tray_vs_marks` placed, said once, naming the
/// MARKED unit. A record still on its holder (an exchange its role does not match) stays open for the next exchange of the activation.
fn say_marks_consumed(statics: &[UnitStatic], next: &State, tray: &mut Tray, shot: &mut ShootResult) {
    for (name, holder, ti) in std::mem::take(&mut shot.marks_open) {
        if next.buffs[holder].iter().any(|r| r.once && &*r.name == name.as_str()) {
            shot.marks_open.push((name, holder, ti));
            continue;
        }
        say_rule(tray, "mark", next.player[holder], || format!(
            "\"{name}\" on {} is consumed (applies once)", statics[next.roster.profile[ti]].name));
    }
}

/// The Mind Control family uses the shared morale resolver from epoch 65;
/// earlier records keep the bare Quality die and its original draw count.
struct ControlMoraleSource<'a> {
    owner: &'a str,
    rule: &'a str,
    /// H-8: the test is rolled on the target's tray and its outcome said (Mind Control / Fatigue Debuff, the table's
    /// `_solo_morale_test(tgt, _roller_label(tgt))`); false keeps the bearer-signed die (Spell Drain).
    on_target: bool,
}

fn control_morale_passed(
    statics: &[UnitStatic], next: &mut State, ti: usize, source: ControlMoraleSource<'_>,
    seams: Seams, tray: &mut Tray, shot: &mut ShootResult,
) -> bool {
    if !rule_on(seams.rules_epoch, EPOCH_65_MELEE_TRUTH) {
        let quality = statics[next.roster.profile[ti]].ctx.quality;
        let faces = tray.roll(1);
        shot.rolls.push(crate::dice::Roll {
            kind: "attack", count: 1, target: quality, faces: faces.clone(), owner: source.owner.into(),
        });
        return faces.first().map(|f| *f as i64 >= quality).unwrap_or(true);
    }
    let us = &statics[next.roster.profile[ti]];
    let mut ctx = live_morale_ctx(statics, next, ti, false, seams, shot, tray);
    ctx.side = next.player[ti]; // the seat the morale dice lines (Fearless, No Retreat) are said for
    let banner_dropped = drop_banner_for_cause(statics, next, ti, false, true, Some(source.rule), None, None, seams, &mut ctx, shot, tray);
    say_morale_bonus(statics, next, ti, false, Some(source.rule), seams, &ctx, banner_dropped, tray);
    if next.shaken[ti] {
        say_rule(tray, "morale", next.player[ti], || format!("{} is already Shaken — automatically fails morale ({CITE})", us.name));
    }
    // H-8 (Plan H): Mind Control's test is rolled on the TARGET's tray (`_solo_morale_test(tgt, _roller_label(tgt))`): the die's
    // owner and the Fearless line name the target, and the outcome line follows (`tray_morale_for`'s). Labels and lines only.
    let (roller, roller_unit) = if source.on_target { (us.name.as_str(), Some(ti)) } else { (source.owner, None) };
    let (outcome, rolled) = crate::dice::resolve_morale_with_tray(
        &ctx, roller, roller_unit, false, false, next.shaken[ti], wounds_left(next, ti), tray,
    );
    let shown = &statics[next.roster.profile[morale_root(next, ti, seams)]].name;
    if source.on_target { tray.say(|| LogLine { rule: "morale", category: Category::Combat, side: next.player[ti], detail: None,
        text: if outcome == Morale::Passed { format!("{shown} passes morale") } else { format!("{shown} fails morale — Shaken") } }); }
    // EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF: an auto-failed test (no die) spends no once morale buff (table `_solo_morale_test`, #2804).
    if !(next.shaken[ti] && rule_on(seams.rules_epoch, crate::acts::EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF)) {
        mods::spend_once_except(next, ti, &[mods::Role::Morale], false, |r| {
            rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) && &*r.name == "Great Banner"
        });
    }
    let self_wounds = shot.absorb(rolled);
    land_wounds_with(next, ti, self_wounds, seams.tray_exact, seams.rules_epoch);
    if outcome == Morale::Passed { return true; }
    next.shaken[ti] = true;
    if seams.hero_attach {
        for &h in &next.attached[ti] { next.shaken[h] = true; }
    }
    shot.log.push(format!("{}: {} fails the morale test — Shaken", source.rule, us.name));
    false
}

/// `main._solo_apply_mind_control` :16997-17037, called at main.gd:1070 in
/// the table's own pre-attack order (right after Utility Buffs, before the
/// Piercing Tag). Per BEARER — the acting unit, then each attached hero, the
/// table's members loop (:16979-16983) — the ONE stamped Mind Control entry
/// ("Fatigue Debuff", `fatigue_debuff_of`) picks the best enemy within its
/// range via the SAME `utility_targets` scoring the table's
/// `_solo_utility_target(member, "enemy", ..)` makes, then rolls ONE die
/// against the target's Quality on the real tray (:17012-17016).
///
/// The DISPLACEMENT arm (an entry with no `effect` param) is its own tray
/// function, `tray_mind_control` below. The `_solo_is_ai_unit` gate
/// (:16999) is not ported for the same reason `tray_piercing_tag`'s is not:
/// selfplay stamps both slots AI. GATED `rule_on(rules_epoch,
/// EPOCH_7_TABLE_RULES)`.
pub(crate) fn tray_fatigue_debuff(
    statics: &[UnitStatic], next: &mut State, si: usize, seams: Seams,
    tray: &mut Tray, shot: &mut ShootResult,
) {
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) { return; }
    if next.alive[si] <= 0 { return; }
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach { bearers.extend(next.attached[si].iter().copied()); }
    for bearer in bearers {
        if next.alive[bearer] <= 0 { continue; }
        let owner = statics[next.roster.profile[bearer]].name.clone();
        for spec in &statics[next.roster.profile[bearer]].fatigue_debuff {
            if spec.effect != "fatigue" { continue; }
            let pick = spec.as_pick();
            let Some(&ti) = utility_targets(statics, next, bearer, &pick, seams).first() else { continue; };
            let passed = control_morale_passed(statics, next, ti, ControlMoraleSource { owner: &owner, rule: &spec.name, on_target: true }, seams, tray, shot);
            say_control_test(next.player[bearer], &spec.name, &owner, &statics[next.roster.profile[ti]].name, passed, tray);
            if passed { continue; }
            // Fatigue Debuff (:17022-17025): the failed test fatigues the
            // target AND its joined chain instead of displacing it.
            let mut chain = vec![ti];
            if seams.hero_attach { chain.extend(next.attached[ti].iter().copied()); }
            for cm in chain { next.fatigued[cm] = true; }
            let tname = &statics[next.roster.profile[ti]].name;
            tray.say(|| LogLine { rule: "mind_control", category: Category::Combat, side: next.player[bearer], detail: None,
                text: format!("{}: {tname} is FATIGUED (melee hits only on unmodified 6s)", spec.name) });
            shot.log.push(format!(
                "{}: {} is FATIGUED (melee hits only on unmodified 6s)",
                spec.name, statics[next.roster.profile[ti]].name));
        }
    }
}

/// H-8 (Plan H): the table's line after a Mind Control / Fatigue Debuff test (`_solo_apply_mind_control`).
fn say_control_test(side: i64, rule: &str, owner: &str, tname: &str, passed: bool, tray: &mut Tray) {
    tray.say(|| LogLine { rule: "mind_control", category: Category::Combat, side, detail: None,
        text: format!("{rule}: {owner} forces a morale test on {tname} — {}", if passed { "passed" } else { "FAILED" }) });
}

/// `main._solo_apply_mind_control` :17031-17038, the DISPLACEMENT arm of the
/// same pre-attack slot the `tray_fatigue_debuff` stamp shares: a "Mind
/// Control" entry with no `effect` param whose failed morale test moves the
/// target up to `move_in` in a straight line. The direction is the table's
/// denial pick (:17031-17036) — away from the nearest objective the bearer's
/// side does NOT control, measured from the target's centre (the AI pulls
/// the holder off the marker it defends) — else away from the bearer. The
/// shift is the shared board-clamped straight move (`clamp_move_to_board`)
/// as ONE rigid translate, the target's joined chain folded with it
/// (`_moving_models` :5442). GATED `rule_on(rules_epoch,
/// EPOCH_7_TABLE_RULES)`.
///
/// MOR-18 (`EPOCH_73_V36`): a unit is MOVED by Mind Control only once per
/// round (`mind_control_moved_round`). A second bearer still forces the test
/// and its Shaken stands; only the displacement is skipped, with its own line.
pub(crate) fn tray_mind_control(
    statics: &[UnitStatic], next: &mut State, si: usize, seams: Seams,
    tray: &mut Tray, shot: &mut ShootResult, cover: Cover,
) {
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) || next.alive[si] <= 0 { return; }
    let terrain = match cover {
        Cover::Board(t) => Some(t),
        Cover::Recorded(_) => None,
    };
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach { bearers.extend(next.attached[si].iter().copied()); }
    for bearer in bearers {
        if next.alive[bearer] <= 0 { continue; }
        for spec in &statics[next.roster.profile[bearer]].mind_control {
            let pick = spec.as_pick();
            let Some(&ti) = utility_targets(statics, next, bearer, &pick, seams).first() else { continue; };
            let owner = &statics[next.roster.profile[bearer]].name;
            let passed = control_morale_passed(statics, next, ti, ControlMoraleSource { owner, rule: &spec.name, on_target: true }, seams, tray, shot);
            say_control_test(next.player[bearer], &spec.name, owner, &statics[next.roster.profile[ti]].name, passed, tray);
            if passed { continue; }
            let tname = &statics[next.roster.profile[ti]].name;
            let side = next.player[bearer];
            // MOR-18, rules 3.6: the same unit is MOVED by Mind Control only
            // once per round — the test above still ran and its Shaken stands.
            if rule_on(seams.rules_epoch, EPOCH_73_V36) && next.mind_control_moved_round[ti] == next.round {
                tray.say(|| LogLine { rule: "mind_control", category: Category::Movement, side, detail: None,
                    text: format!("{}: {tname} was already moved by Mind Control this round — it stays put", spec.name) });
                shot.log.push(format!(
                    "{}: {} was already moved by Mind Control this round — it stays put",
                    spec.name, statics[next.roster.profile[ti]].name));
                continue;
            }
            let from = geom::centre(&next.positions[ti]);
            let goal = nearest_uncontrolled_objective(next, next.player[bearer], next.player[ti], from)
                .unwrap_or(geom::centre(&next.positions[bearer]));
            let away = geom::sub(from, goal);
            let len = (away[0] * away[0] + away[2] * away[2]).sqrt();
            if len < 1e-3 { continue; }
            let dir = [away[0] / len, away[2] / len];
            let dist_in = clamp_move_to_board(terrain, &next.positions[ti], dir, spec.move_in as f32);
            // H-8 (Plan H): the table's movement line (`_solo_apply_mind_control`), said for a zero move too, as the table does.
            tray.say(|| LogLine { rule: "mind_control", category: Category::Movement, side, detail: None,
                text: format!("{}: {tname} fails the morale test — Shaken, moved {:.0}\" in a straight line (away from the marker)",
                    spec.name, dist_in.max(0.0)) });
            if dist_in <= 0.0 { continue; }
            let step_m = dist_in * IN2M as f32;
            let mut chain = vec![ti];
            if seams.hero_attach { chain.extend(next.attached[ti].iter().copied()); }
            for cm in chain {
                for p in next.positions[cm].iter_mut() {
                    *p = [p[0] + (dir[0] * step_m) as f64, p[1], p[2] + (dir[1] * step_m) as f64];
                }
                // H-8 (Plan H): the push is its own step event, in the order it happened: the table moves the unit before
                // the volley's landings, whose `at` is the pushed position.
                let moved_to = next.positions[cm].clone();
                tray.land(|| Landing { unit: cm, models: Vec::new(), loss_line: false, moved_to });
            }
            if rule_on(seams.rules_epoch, EPOCH_73_V36) { next.mind_control_moved_round[ti] = next.round; }
            if rule_on(seams.rules_epoch, EPOCH_65_MELEE_TRUTH) {
                shot.log.push(format!("{}: {} fails the morale test — Shaken, moved {:.0}\" in a straight line (away from the marker)",
                    spec.name, statics[next.roster.profile[ti]].name, dist_in));
            } else {
                shot.log.push(format!("{}: {} is moved {:.0}\" in a straight line (away from the marker)",
                    spec.name, statics[next.roster.profile[ti]].name, dist_in));
            }
        }
    }
}


/// #816 PR 2 — the Teleport/Ethereal beat; REPLAY byte-exact, LIVE 3 probes.
/// Gated on `EPOCH_8_PLANNER_MENU` (#831's epoch-8 move): the epoch-7 corpus
/// was recorded without the Reposition act, so below 8 the beat is a no-op.
pub(crate) fn teleport_beat(
    statics: &[UnitStatic], next: &mut State, si: usize, action: &Action, seams: Seams,
    dice: Option<&mut (&mut Tray, &mut ShootResult)>, cover: Cover,
) -> bool {
    let mut shot = dice.map(|(_, sh)| &mut **sh);
    if !rule_on(seams.rules_epoch, EPOCH_8_PLANNER_MENU) || next.alive[si] <= 0 { return false; }
    let Some(spec) = statics[next.roster.profile[si]].teleport.as_ref() else { return false; };
    if spec.name == "Teleport" && rule_on(seams.rules_epoch, EPOCH_66_DISTANCE_TRUTH)
        && action.kind == HOLD { return false; }
    let rush_cap = rule_on(seams.rules_epoch, EPOCH_66_DISTANCE_TRUTH) && action.kind == RUSH;
    let cap_in = crate::unit::teleport_cap_in(&spec.name, rush_cap);
    // REPLAY: the record's centroid, no clamp; LIVE: the probe set (the
    // ADVANCE band — a standalone Reposition act has no Rush context).
    let to = match action.teleport {
        Some(to) => Some(to),
        None if action.kind == REPOSITION => teleport_probe(
            next, si, cap_in,
            match cover { Cover::Board(t) if t.is_valid() => Some(t), _ => None }, seams.hero_attach),
        None => None,
    };
    let Some(to) = to else { return false; };
    let from = geom::centre(&next.positions[si]);
    let (dx, dz) = (to[0] as f32 - from[0], to[1] as f32 - from[2]);
    let chain = teleport_chain(next, si, seams.hero_attach);
    // L-RF1 F7: a placement never ends on a building (the rule text is silent on terrain; lead call: refuse)
    if let Cover::Board(t) = cover {
        if lands_in_house(t, next, &chain, [dx, dz]) {
            if let Some(shot) = shot.as_deref_mut() {
                shot.log.push(format!("{}: {} keeps its position - a building is impassable", statics[next.roster.profile[si]].name, spec.name));
            }
            return false;
        }
    }
    for u in chain {
        for p in next.positions[u].iter_mut() {
            *p = [p[0] + dx as f64, p[1], p[2] + dz as f64];
        }
    }
    next.teleport_used[si] = true;
    if let Some(shot) = shot {
        shot.log.push(format!(
            "{}: {} repositions within {:.0}\" — landing centroid ({:.2}, {:.2}) m",
            spec.name, statics[next.roster.profile[si]].name, cap_in, to[0], to[1]));
    }
    true
}

/// The bounded probe set (design §3): objective clamp, away-from-threat,
/// first cover bearing, self-carried EV heuristic; best landing past margin.
pub(crate) fn teleport_probe(
    next: &State, si: usize, cap_in: f64, terrain: Option<&Terrain>, hero_attach: bool,
) -> Option<[f64; 2]> {
    let from = geom::centre(&next.positions[si]);
    let chain = teleport_chain(next, si, hero_attach); // L-RF1 F7: the models the beat moves
    let cap_m = cap_in * IN2M;
    let side = next.player[si];
    let foe = if side == 1 { 2 } else { 1 };
    let obj_at = |p: V3| nearest_uncontrolled_objective(next, side, foe, p);
    let mut probes: Vec<V3> = vec![from];
    if let Some(obj) = obj_at(from) {
        let d = geom::sub(obj, from);
        if geom::length(d) > 0.001 {
            probes.push(geom::add(from, geom::mul(geom::normalized(d), (geom::length(d) as f64).min(cap_m))));
        }
    }
    if let Some(t) = nearest_enemy(next, si) {
        let away = geom::sub(from, geom::centre(&next.positions[t]));
        if geom::length(away) > 0.001 {
            probes.push(geom::add(from, geom::mul(geom::normalized(away), cap_m)));
        }
    }
    if let Some(t) = terrain {
        for k in 0..8 {
            let a = std::f32::consts::TAU * (k as f32) / 8.0;
            let p = geom::add(from, [a.cos() * cap_m as f32, 0.0, a.sin() * cap_m as f32]);
            if gives_cover(t.type_at(p)) { probes.push(p); break; }
        }
    }
    // Self-carried EV: objective pull, threat escape, cover (the table's
    // `AiPosition._evaluate` is not ported).
    let ev_at = |p: V3| -> f64 {
        let obj = obj_at(p).map(|o| -(geom::length(geom::sub(o, p)) as f64) / IN2M).unwrap_or(0.0);
        let thr = nearest_enemy(next, si)
            .map(|t| geom::length(geom::sub(geom::centre(&next.positions[t]), p)) as f64 / IN2M)
            .map(|d| if d < 6.0 { -(6.0 - d) * 2.0 } else { 0.0 }).unwrap_or(0.0);
        obj + thr + terrain.map(|t| gives_cover(t.type_at(p)) as i64 as f64 * 2.0).unwrap_or(0.0)
    };
    let stay = ev_at(from);
    probes.iter().copied()
        .filter(|&p| p != from && geom::length(geom::sub(p, from)) as f64 / IN2M <= cap_in + 1e-3)
        .filter(|&p| !terrain.is_some_and(|t| lands_in_house(t, next, &chain, [p[0] - from[0], p[2] - from[2]])))
        .map(|p| (ev_at(p), p))
        .max_by(|a, b| a.0.partial_cmp(&b.0).unwrap_or(std::cmp::Ordering::Equal))
        .filter(|(v, _)| *v > stay + TELEPORT_EV_MARGIN)
        .map(|(_, p)| [p[0] as f64, p[2] as f64])
}

/// The models a Teleport moves: the unit, plus its joined heroes when `hero_attach` (`_moving_models`).
fn teleport_chain(next: &State, si: usize, hero_attach: bool) -> Vec<usize> {
    let mut chain = vec![si];
    if hero_attach { chain.extend(next.attached[si].iter().copied()); }
    chain
}

/// L-RF1 F7: would any model of `chain`, shifted by `d` (world XZ metres), stand over a solid tier cell (an intact house)
/// or within its base radius of a house wall? Always `false` on a board without `solid_cells`.
fn lands_in_house(t: &Terrain, next: &State, chain: &[usize], d: [f32; 2]) -> bool {
    let houses = t.solid_walls_world_m();
    chain.iter().any(|&u| next.positions[u].iter().enumerate().any(|(k, p)| {
        let c = [p[0] as f32 + d[0], p[2] as f32 + d[1]];
        let r = next.radii[u].get(k).copied().unwrap_or(DEFAULT_BASE_RADIUS_M);
        t.solid_at(f64::from(c[0]) / t.in2m(), f64::from(c[1]) / t.in2m())
            || houses.iter().any(|w| crate::mv::geom2::point_seg_distance(c, w[0], w[1]) < r + 0.001)
    }))
}


/// `SoloController._nearest_uncontrolled_objective` :7117-7178, the path the
/// displacement arm takes (activating_unit=null: no round plan, no garrison;
/// `spread` false — the core has no difficulty): among the markers the
/// bearer's side does NOT control, a HOLDABLE one (no enemy within 3") ranks
/// before a contested one, the nearer one wins within a tier. Control is the
/// owner OR the strict majority of non-shaken, non-reserve, non-attached,
/// non-aircraft units within 3" (`_units_controlling` :7288,
/// OBJECTIVE_CONTROL_IN = 3.0). Owner 0 is the table's NEUTRAL (slots 1/2),
/// never "side 0's own".
fn nearest_uncontrolled_objective(next: &State, side: i64, foe: i64, from: V3) -> Option<V3> {
    let mut best: Option<(i64, f32, V3)> = None;
    for o in &next.objectives {
        let pos = geom::to_f32(o.pos);
        let own = units_controlling(next, side, pos);
        let enemy = units_controlling(next, foe, pos);
        if (o.owner != 0 && o.owner == side) || own > enemy { continue; }
        let d = geom::length(geom::sub(pos, from));
        let tier = (enemy == 0) as i64 * 2;
        if best.is_none_or(|(bt, bd, _)| tier > bt || (tier == bt && d < bd)) {
            best = Some((tier, d, pos));
        }
    }
    best.map(|(_, _, pos)| pos)
}

/// `SoloController._units_controlling` :7288-7305 — the strict headcount at
/// one marker: the side's own alive, non-shaken, non-reserve, non-attached,
/// non-aircraft units with ANY alive model within the 3" control radius.
fn units_controlling(next: &State, side: i64, obj: V3) -> i64 {
    (0..next.units())
        .filter(|&u| {
            next.player[u] == side
                && next.alive[u] > 0
                && !next.shaken[u]
                && !next.dormant[u]
                && next.attached_to[u].is_none()
                && !next.aircraft[u]
                && next
                    .positions[u]
                    .iter()
                    .any(|p| geom::length(geom::sub(geom::to_f32(*p), obj)) / IN2M as f32 <= 3.001)
        })
        .count() as i64
}

/// `main._solo_apply_reckless_piercing` main.gd:16937-16971, called at
/// main.gd:1072 in the table's pre-attack order (between the Piercing Tag
/// and the Storm Attack). ONE tray die per unit per ROUND (the
/// `reckless_rolled_round` gate): at or over `roll_target` the bearer's
/// chain gets `reckless_ap_round` (its weapons +AP until round end), on a
/// 1 the chain gets `reckless_backfire_round` (enemies +AP against it).
/// The table's `_solo_is_ai_unit` opt-in is not ported — the AI always
/// rolls and so does this twin (selfplay stamps both slots AI, the
/// `tray_piercing_tag` precedent). GATED `rule_on(rules_epoch,
/// EPOCH_7_TABLE_RULES)`. The stamps are read by the attack seams below
/// (`strike_phase` and the volley loop) through `Ctx::reckless_ap`.
pub(crate) fn tray_reckless_piercing(
    statics: &[UnitStatic], next: &mut State, si: usize, seams: Seams,
    tray: &mut Tray, shot: &mut ShootResult,
) {
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) { return; }
    if next.alive[si] <= 0 || next.reckless_rolled_round[si] == next.round { return; }
    let Some(spec) = statics[next.roster.profile[si]].reckless_piercing.first() else { return; };
    next.reckless_rolled_round[si] = next.round;
    let owner = statics[next.roster.profile[si]].name.clone();
    let faces = tray.roll(1);
    shot.rolls.push(crate::dice::Roll {
        kind: "attack", count: 1, target: spec.roll_target,
        faces: faces.clone(), owner,
    });
    let face = faces.first().map(|f| *f as i64).unwrap_or(1);
    let buff = face >= spec.roll_target;
    let mut chain = vec![si];
    if seams.hero_attach { chain.extend(next.attached[si].iter().copied()); }
    for cm in chain {
        if buff { next.reckless_ap_round[cm] = next.round; }
        else { next.reckless_backfire_round[cm] = next.round; }
    }
    if buff {
        shot.log.push(format!(
            "{}: {} rolls {} — weapons get AP(+1) until the end of the round",
            spec.name, statics[next.roster.profile[si]].name, face));
    } else {
        shot.log.push(format!(
            "{}: {} rolls a {} — enemies get AP(+1) against it until the end of the round",
            spec.name, statics[next.roster.profile[si]].name, face));
    }
}

/// Wave 3 — `main._solo_apply_piercing_tag` main.gd:16999-17027, the marker
/// family's PLACEMENT half, in the table's own once-per-activation
/// before-attacking slot right after the Utility Buffs (main.gd:1071; Mind
/// Control sits between them on the table). Per BEARER — the acting unit, then each attached hero, the table's
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
///
/// W3-4 (a), `EPOCH_67_MARKERS_BURSTS`: an entry with `place_roll > 0`
/// ("Piercing Spotter") no longer shares the once-per-GAME `piercing_tag_used`
/// latch — it rolls the printed die (the Precision Spotter shape,
/// `tray_precision_markers`) and gates on `State.piercing_spot_round`
/// (once per ACTIVATION ROUND) instead. Below the gate `place_roll` stays
/// dead data and every entry, Spotter included, keeps the old once-per-game
/// reading.
fn tray_piercing_tag(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
) {
    if !rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
        return;
    }
    let epoch67 = rule_on(seams.rules_epoch, EPOCH_67_MARKERS_BURSTS);
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
            let spotter = epoch67 && t.place_roll > 0;
            if spotter {
                if next.piercing_spot_round[bearer] == next.round {
                    continue;
                }
            } else if next.piercing_tag_used[bearer] {
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
            if spotter {
                next.piercing_spot_round[bearer] = next.round;
                let record = rule_on(seams.rules_epoch, crate::acts::EPOCH_96_PARITY_BATCH);
                if record {
                    tray.owner_next(Some(bearer));
                }
                let faces = tray.roll(1);
                if record {
                    shot.rolls.push(crate::dice::Roll { kind: "attack", count: 1, target: t.place_roll, faces: faces.clone(), owner: statics[pb].name.clone() });
                }
                let face = faces.first().copied().unwrap_or(1) as i64;
                if face < t.place_roll {
                    let line = format!(
                        "{}: {} misses the mark on {} (needed {}+)",
                        t.name,
                        statics[pb].name,
                        statics[next.roster.profile[ti]].name,
                        t.place_roll
                    );
                    shot.log.push(line.clone());
                    say_rule(tray, "marker_place", next.player[bearer], || line);
                    continue;
                }
            } else {
                next.piercing_tag_used[bearer] = true;
            }
            let v36 = rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36);
            if v36 && t.name == "Piercing Target" {
                let (hit, _per) = tag_picks(statics, next, bearer, &probe, t.markers, true, seams);
                for &u in &hit {
                    next.piercing_tag_markers[u] += 1;
                    next.piercing_tag_persistent[u] = true;
                }
                let line = target_place_line("Piercing Target", &statics[pb].name, statics, next, &hit, "+1 AP");
                shot.log.push(line.clone());
                say_rule(tray, "marker_place", next.player[bearer], || line);
                continue;
            }
            let v36_tag = v36 && t.name == "Piercing Tag";
            let (hit, per) = tag_picks(statics, next, bearer, &probe, t.markers, v36_tag, seams);
            for &u in &hit {
                next.piercing_tag_markers[u] += per;
            }
            if v36_tag {
                let line = tag_place_line("Piercing Tag", &statics[pb].name, statics, next, &hit, per, "+1 AP");
                shot.log.push(line.clone());
                say_rule(tray, "marker_place", next.player[bearer], || line);
                continue;
            }
            // D42 (a), EPOCH_67_MARKERS_BURSTS: "Piercing Target" has no removal
            // clause — the spend half (`piercing_tag_spend`) reads this flag and
            // stands the pool instead of zeroing it. Every other family name
            // still spends whole, so the flag is per-NAME, not per-pool.
            if t.name == "Piercing Target" && epoch67 {
                next.piercing_tag_persistent[ti] = true;
            }
            // Rules-must-log — the table's own line, main.gd:17025-17027.
            let line = format!(
                "{}: {} places {} marker{} on {} — friendly attackers may spend them for +AP",
                t.name,
                statics[pb].name,
                t.markers,
                if t.markers == 1 { "" } else { "s" },
                statics[next.roster.profile[ti]].name
            );
            shot.log.push(line.clone());
            say_rule(tray, "marker_place", next.player[bearer], || line);
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
///
/// D42 (a), `EPOCH_67_MARKERS_BURSTS`: when the placement set
/// `piercing_tag_persistent[ti]` (the "Piercing Target" name only), the pool
/// is READ, never zeroed — the book text has no removal clause. Every other
/// family name keeps spending whole.
fn piercing_tag_spend(next: &mut State, ti: usize, rules_epoch: u32) -> i64 {
    if !rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        return 0;
    }
    let markers = next.piercing_tag_markers[ti].max(0);
    if rule_on(rules_epoch, EPOCH_67_MARKERS_BURSTS) && next.piercing_tag_persistent[ti] {
        // Rules 3.6: the Target's standing token is a flat +1, never +markers.
        return if rule_on(rules_epoch, crate::acts::EPOCH_73_V36) { markers.min(1) } else { markers };
    }
    // Rules 3.6 (`EPOCH_73_V36`): a friendly attack spends ONE token for +1.
    let spent = if rule_on(rules_epoch, crate::acts::EPOCH_73_V36) { markers.min(1) } else { markers };
    next.piercing_tag_markers[ti] = markers - spent;
    spent
}

/// Rules 3.6 (`EPOCH_73_V36`) Tag placement: X tokens stacked on the toughest pick, or, when two or more enemy
/// units are in reach, one token on each of up to X units. Below the gate only the toughest pick is asked for, so
/// the stack is the whole answer. Returns the units and the tokens each one gets.
fn tag_picks(statics: &[UnitStatic], next: &State, bearer: usize, probe: &UtilityBuff, markers: i64, v36: bool, seams: Seams) -> (Vec<usize>, i64) {
    let picks = utility_targets(statics, next, bearer, &UtilityBuff { max_targets: if v36 { markers } else { 1 }, ..probe.clone() }, seams);
    let per = if picks.len() >= 2 { 1 } else { markers };
    (picks, per)
}

/// The rules-must-log placement line of a rules 3.6 Tag: names the tag, the stack/spread choice and the one-token spend.
fn tag_place_line(name: &str, owner: &str, statics: &[UnitStatic], next: &State, hit: &[usize], per: i64, effect: &str) -> String {
    let placed = match hit {
        [_, _, ..] => format!("1 token each, spread over {} units", hit.len()),
        _ => format!(
            "{per} token{}, stacked on {}",
            if per == 1 { "" } else { "s" },
            statics[next.roster.profile[hit[0]]].name
        ),
    };
    format!("{name}: {owner} places {placed} — a friendly attack may spend one token for {effect}")
}

/// One persistent Precision Target record on `u` (the rules 3.6 Target: flat +1 per marked unit).
fn push_precision_target(next: &mut State, u: usize, hit_mod: i64, name: &str) {
    next.buffs[u].push(mods::LiveMod {
        hit_mod,
        casting_mod: 0,
        morale_mod: 0,
        ap_mod: 0,
        def_mod: 0,
        defense_mod: 0,
        move_mod: 0,
        range_in: 0,
        grants_rule: Rc::from(""),
        scope: Rc::from(""),
        attackers: true,
        once: false,
        name: Rc::from(name),
    });
}

/// The rules 3.6 Target placement line: ONE standing token on each of up to X units, every tagged unit named.
fn target_place_line(name: &str, owner: &str, statics: &[UnitStatic], next: &State, hit: &[usize], effect: &str) -> String {
    let names: Vec<&str> = hit.iter().map(|&u| statics[next.roster.profile[u]].name.as_str()).collect();
    format!("{name}: {owner} places 1 token on each of {} — a friendly attack gets {effect}", names.join(", "))
}

/// Wave 6 — the PRECISION MARKERS family's PLACEMENT half
/// (`EPOCH_61_PRECISION_MARKERS`), the `_solo_apply_piercing_tag` twin for the
/// to-hit markers. Spotter (main.gd:1127, END of activation): NEAREST enemy in
/// 30"/LOS, one tray roll, 4+ places a marker on `State::spot_markers`, once
/// per activation (`State::spot_round`). Tag (TOUGHEST pick, 24"): `markers`
/// (the rule string's rating, default 1) onto `State::tag_markers`, once per
/// game (`State::precision_used`). Target: the same pick at 18", the bonus
/// rides ONE PERSISTENT attackers-beneficiary record (hit_mod = markers,
/// `once: false`) — EVERY friendly attack folds it on BOTH legs via
/// `vs_hit_mod`, nothing is ever spent (the book text has no removal clause).
/// Rules-must-log on every placement. GATED on the FROZEN constant.
fn tray_precision_markers(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
    spot: bool,
) {
    if !rule_on(seams.rules_epoch, EPOCH_61_PRECISION_MARKERS) {
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
        for b in &statics[pb].utility_buffs {
            if b.bonus.is_empty() {
                continue;
            }
            // TWO table slots: the Spotter fires at the END of the activation
            // (main.gd:1127, `spot == true`), Tag/Target in the pre-attack
            // slot right after the Piercing Tag (main.gd:1089-1090, `spot ==
            // false`) — the tag's own activation's volley may spend it.
            if (b.place_roll > 0) != spot {
                continue;
            }
            if b.uses_per_game > 0 {
                if next.precision_used[bearer].contains(&b.name) {
                    continue;
                }
            } else if next.spot_round[bearer] == next.round {
                continue;
            }
            let owner = statics[pb].name.clone();
            if b.place_roll > 0 {
                // SPOTTER — the table's own auto-spot pick (main.gd:10043-10052):
                // the NEAREST enemy within the entry's range in sight.
                let Some(ti) = nearest_precision_target(next, bearer, b, seams) else { continue; };
                next.spot_round[bearer] = next.round;
                // NML-980, EPOCH_67_MARKERS_BURSTS: "roll one die" is per MODEL
                // (GF p.4) — this bearer's own alive model count, one laser
                // each; below the gate the old single-die reading stands.
                let dice = if rule_on(seams.rules_epoch, EPOCH_67_MARKERS_BURSTS) {
                    next.alive[bearer].max(1) as usize
                } else {
                    1
                };
                if rule_on(seams.rules_epoch, crate::acts::EPOCH_96_PARITY_BATCH) {
                    tray.owner_next(Some(bearer));
                }
                let faces = tray.roll(dice);
                if rule_on(seams.rules_epoch, crate::acts::EPOCH_96_PARITY_BATCH) {
                    shot.rolls.push(crate::dice::Roll { kind: "attack", count: dice as i64, target: b.place_roll, faces: faces.clone(), owner: owner.clone() });
                }
                let hits = faces.iter().filter(|&&f| f as i64 >= b.place_roll).count() as i64;
                let tn = statics[next.roster.profile[ti]].name.clone();
                if hits <= 0 {
                    shot.log.push(format!(
                        "Precision Spotter: {} misses the mark on {} (needed {}+, {} di{})",
                        owner, tn, b.place_roll, dice, if dice == 1 { "e" } else { "ce" }));
                    // The table's wording (`_solo_ai_spot`): "die" / "dies".
                    say_rule(tray, "marker_place", next.player[bearer], || format!(
                        "Precision Spotter: {owner} misses the mark on {tn} (needed {}+, {dice} die{})", b.place_roll, if dice == 1 { "" } else { "s" }));
                    continue;
                }
                let before = next.spot_markers[ti];
                let placed = b.markers * hits;
                next.spot_markers[ti] += placed;
                shot.log.push(format!(
                    "Precision Spotter: {} marks {} ({} marker{} — attackers may remove markers for +1 to hit each)",
                    owner, tn, placed, if placed == 1 { "" } else { "s" }));
                // The table places one marker per hit and says each (`_solo_place_spot_marker`, the running count).
                for k in 1..=hits {
                    let n = before + b.markers * k;
                    say_rule(tray, "marker_place", next.player[bearer], || format!(
                        "Precision Spotter: {owner} marks {tn} ({n} marker{} — attackers may remove markers for +1 to hit each)", if n == 1 { "" } else { "s" }));
                }
            } else {
                // TAG / TARGET — the piercing twins' TOUGHEST-enemy pick.
                let probe = UtilityBuff {
                    name: b.name.clone(),
                    target: "enemy".into(),
                    range_in: b.range_in,
                    needs_los: b.needs_los,
                    max_targets: 1,
                    ..UtilityBuff::default()
                };
                let Some(ti) = utility_targets(statics, next, bearer, &probe, seams).into_iter().next() else { continue; };
                Rc::make_mut(&mut next.precision_used)[bearer].push(b.name.clone());
                let tn = statics[next.roster.profile[ti]].name.clone();
                if b.bonus == "per_placed_marker" {
                    // TARGET — the +X is a PERSISTENT record: every friendly
                    // attack against the marked unit folds it (both legs,
                    // `vs_hit_mod`), nothing is ever spent.
                    let v36 = rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36);
                    let picks = if v36 { tag_picks(statics, next, bearer, &probe, b.markers, true, seams).0 } else { vec![ti] };
                    let hit_mod = if v36 { 1 } else { b.markers };
                    for &u in &picks {
                        push_precision_target(next, u, hit_mod, &b.name);
                    }
                    let line = if v36 {
                        target_place_line("Precision Target", &owner, statics, next, &picks, "+1 to hit")
                    } else {
                        format!("Precision Target: {} places {} marker{} on {} — friendly units get +{} to hit against it",
                            owner, b.markers, if b.markers == 1 { "" } else { "s" }, tn, b.bonus)
                    };
                    shot.log.push(line.clone());
                    // The table says the Target's placement from 73 only (`_solo_apply_precision_target`).
                    if v36 {
                        say_rule(tray, "marker_place", next.player[bearer], || line);
                    }
                } else {
                    let v36 = rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36);
                    let (hit, per) = tag_picks(statics, next, bearer, &probe, b.markers, v36, seams);
                    for &u in &hit {
                        next.tag_markers[u] += per;
                    }
                    if v36 {
                        let line = tag_place_line("Precision Tag", &owner, statics, next, &hit, per, "+1 to hit");
                        shot.log.push(line.clone());
                        say_rule(tray, "marker_place", next.player[bearer], || line);
                        continue;
                    }
                    let line = format!(
                        "Precision Tag: {} places {} marker{} on {} — friendly attackers may remove markers for +1 to hit each",
                        owner, b.markers, if b.markers == 1 { "" } else { "s" }, tn);
                    shot.log.push(line.clone());
                    say_rule(tray, "marker_place", next.player[bearer], || line);
                }
            }
        }
    }
}

/// The Spotter arm's own pick (main.gd:10043-10052): the NEAREST living enemy
/// within the entry's range, sight-gated by the entry's `needs_los` — the
/// exclusions are `utility_targets`'s own (dormant, joined).
fn nearest_precision_target(
    next: &State,
    bearer: usize,
    b: &crate::unit::UtilityBuff,
    seams: Seams,
) -> Option<usize> {
    let own = next.player[bearer];
    let from = geom::centre(&next.positions[bearer]);
    let mut best: Option<(f64, usize)> = None;
    for u in 0..next.units() {
        if next.player[u] == own || next.alive[u] <= 0 || next.dormant[u] {
            continue;
        }
        if seams.hero_attach && next.attached_to[u].is_some() {
            continue;
        }
        let d = (geom::length(geom::sub(from, geom::centre(&next.positions[u]))) / IN2M as f32) as f64;
        if d > b.range_in {
            continue;
        }
        if b.needs_los && !los_clear(next, bearer, u) {
            continue;
        }
        if best.is_none_or(|(bd, _)| d < bd) {
            best = Some((d, u));
        }
    }
    best.map(|(_, u)| u)
}

/// The PRECISION family's consumption half, the volley seam's — the twin of
/// `piercing_tag_spend` above: the marked target's pools spend EVERY marker on
/// THIS volley for +1 to hit per marker (main.gd:3119 AI / :10429 human,
/// shooting only — the melee seams never call it), once per group. The
/// Precision TARGET record is NOT here: it is persistent (`once: false`),
/// folds through `vs_hit_mod` on both legs, and the book text has no removal
/// clause. GATED on the FROZEN constant; below it both pools read empty.
fn precision_markers_spend(
    next: &mut State,
    si: usize,
    ti: usize,
    rules_epoch: u32,
    log: &mut Vec<String>,
    tray: &mut Tray,
    side: i64,
) -> (i64, i64) {
    if !rule_on(rules_epoch, EPOCH_61_PRECISION_MARKERS) {
        return (0, 0);
    }
    let pool = next.spot_markers[ti].max(0);
    // The attacker's own count (`spot_markers:<shooter>:<target>`, 0..=pool, the table's offer `_solo_offer_spot_markers`); no answer
    // takes all of them, the AI's rule (an interference-shaped count choice on the step path).
    let id = format!("spot_markers:{}:{}", next.key(si), next.key(ti));
    let spot = if pool > 0 { tray.interference(&id, pool, next.key(si)).unwrap_or(pool) } else { 0 };
    if spot > 0 {
        next.spot_markers[ti] = pool - spot;
        let left = pool - spot;
        log.push(format!(
            "Precision Spotter: {spot} marker{} removed — +{spot} to hit this volley{}",
            if spot == 1 { "" } else { "s" }, if left > 0 { format!(" ({left} remain{})", if left == 1 { "s" } else { "" }) } else { String::new() }));
        // The table's line (`_solo_consume_spot_markers`, the AI takes them all): the same words on the tray.
        say_rule(tray, "marker_spend", side, || log.last().cloned().unwrap_or_default());
    }
    let tag = next.tag_markers[ti].max(0);
    let mut tag_spent = 0;
    if tag > 0 {
        // Rules 3.6 (`EPOCH_73_V36`): a friendly attack spends ONE token for +1.
        let v36 = rule_on(rules_epoch, crate::acts::EPOCH_73_V36);
        tag_spent = if v36 { 1 } else { tag };
        next.tag_markers[ti] = tag - tag_spent;
        log.push(if v36 {
            format!("Precision Tag: one token spent — +1 to hit this volley ({} left)", tag - 1)
        } else {
            format!(
                "Precision Tag: {tag} marker{} removed — +{tag} to hit this volley",
                if tag == 1 { "" } else { "s" })
        });
        say_rule(tray, "marker_spend", side, || log.last().cloned().unwrap_or_default());
    }
    (spot, tag_spent)
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
/// Indirect) answers the same boolean. `shooting_range_bonus`'s Royal Legion
/// half rides each profile's `reach_bonus_in` (rules 3.6); spell tokens stay
/// unmodelled here (io.rs).
fn has_shoot_target(statics: &[UnitStatic], state: &State, arty: usize) -> bool {
    let us = &statics[state.roster.profile[arty]];
    let max_range = us.shoot.iter().map(|p| p.range as f64 + p.reach_bonus_in).fold(0.0_f64, f64::max);
    if max_range <= 0.0 {
        return false;
    }
    let indirect = us.shoot.iter().any(|p| p.indirect && p.indirect_ignores_los.unwrap_or(true));
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

/// `EPOCH_85_INDIRECT_GATE` (table twin `_solo_pick_overlay_target`, whose per-shot sight count ignores LOS for a weapon's own Indirect;
/// rules 3.6 SHO-01a: a Hold not kept loses the waiver where the entry says so): a living chain member's Indirect weapon that waives the
/// sight test and reaches the target (base-edge gap against its reach) makes the target a legal pick, seen or not. `sighted_profiles_of`
/// still counts the sighted models per weapon, so only what the table would shoot is shot.
fn indirect_waives_gate(statics: &[UnitStatic], state: &State, si: usize, ti: usize, held: bool, seams: Seams) -> bool {
    let def = &statics[state.roster.profile[ti]].ctx;
    let chain = std::iter::once(si).chain(state.attached[si].iter().copied().filter(|_| seams.hero_attach));
    chain.filter(|&m| state.alive[m] > 0).any(|m| {
        let um = &statics[state.roster.profile[m]];
        let gap = chain_gap_in(state, ti, seams, |t| range_gap_in(state, &state.positions[m], m, t));
        um.shoot.iter().any(|p| {
            p.indirect && p.indirect_ignores_los.unwrap_or(true) && !(p.indirect_los_needs_hold && !held)
                && gap <= sight_reach_in(p.range as f64 + p.reach_bonus_in.max(granted_reach(um, state, m).0), state.aircraft[ti], def)
        })
    })
}

/// `EPOCH_96_PARITY_BATCH`: the target's own range cut (Aircraft -12", the Ranged Shrouding family) leaves no living
/// chain member a weapon whose cut reach (plus a live +6" Mark) covers the gap its weapons are gated by (`gap`, the volley's own `dm`);
/// the Mark adds after the cut (the larger of the two reads), so a volley the dice would fire is never dropped. The Aircraft cut counts
/// only where the volley reads it (the sighting seam); a Strafing run is its own volley (`tray_strafing`) and never reaches this.
fn cut_out_of_reach(statics: &[UnitStatic], state: &State, si: usize, ti: usize, seams: Seams, gap: impl Fn(usize) -> f64) -> bool {
    let def = &statics[state.roster.profile[ti]].ctx;
    let air = state.aircraft[ti] && seams.sighting;
    if !(air || def.ranged_shrouding) {
        return false;
    }
    let mark = if mods::granted_vs(state, ti, "+6\" shooting range") { INCREASED_SHOOTING_RANGE_MARK_IN } else { 0.0 };
    let chain = std::iter::once(si).chain(state.attached[si].iter().copied().filter(|_| seams.hero_attach));
    !chain.filter(|&m| state.alive[m] > 0).any(|m| {
        let um = &statics[state.roster.profile[m]];
        let gap = gap(m);
        um.shoot.iter().any(|p| p.range > 0
            && sight_reach_in(p.range as f64 + p.reach_bonus_in.max(granted_reach(um, state, m).0), air, def) + mark >= gap)
    })
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

/// `Retreating Strike`'s reach: "within 3\" of enemy units" (main.gd:5864,
/// the melee gap read) -- the same 3" as the Hit & Run step it rides.
pub const RETREATING_STRIKE_REACH_IN: f64 = 3.0;

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
/// WHOLE joined formation, not one member of it); from `EPOCH_73_V36` every
/// joined hero must carry it too (`hit_and_run_mixed`). Once per ROUND
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
///   difficult/dangerous terrain and spends the band per model.
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

/// `main._solo_retreating_strike` main.gd:5849-5877, called at main.gd:1097
/// INSIDE the post-MELEE Hit & Run success branch (:1095-1097): once per
/// round per bearer (the acting unit, then each attached hero -- the
/// table's `_solo_joined_chain` loop with the per-member
/// `retreating_strike_round` stamp), the nearest enemy within the 3" MELEE
/// gap of the formation takes `maxi(rating,1) x alive` direct-wound dice at
/// the shared Ravage 6+ (`AiCombatMath.RAVAGE_WOUND_TARGET`), rolled with
/// the table's own "ravage" roll kind; wounds land with no save beyond the
/// Regeneration batch the melee Ravage leg already applies.
///
/// NOT PORTED -- the table's second call site (main.gd:9494, the AI
/// DEFENDER's post-melee step after the human's melee): this core has no
/// defender-side Hit & Run seam (its HnR is the acting unit's own, above),
/// so the defender's strike has nowhere to hang. The human's manual
/// post-melee drag is untracked on the TABLE too -- the Versatile precedent.
/// GATED `rule_on(rules_epoch, EPOCH_7_TABLE_RULES)`.
pub(crate) fn tray_retreating_strike(
    statics: &[UnitStatic], next: &mut State, si: usize, seams: Seams,
    tray: &mut Tray, shot: &mut ShootResult,
) {
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) { return; }
    if next.alive[si] <= 0 { return; }
    // The pick is the FORMATION's (main.gd:5863-5865 measure `unit` to the
    // target), the dice are per MEMBER -- so the target is found once here.
    let Some(ti) = nearest_enemy_of(next, si) else { return; };
    let gap = geom::edge_gap_in(
        &next.positions[si], &next.radii[si], &next.positions[ti], &next.radii[ti],
        DEFAULT_BASE_RADIUS_M,
    );
    if gap > RETREATING_STRIKE_REACH_IN { return; }
    let def_owner = statics[next.roster.profile[ti]].name.clone();
    let def = with_modifier_sum(with_cond_ap_state(ctx_live(ctx_of(&statics[next.roster.profile[ti]], next, ti), statics, next, ti, true, seams.rules_epoch), statics, next, ti, seams), seams.rules_epoch);
    let mut bearers: Vec<usize> = vec![si];
    if seams.hero_attach { bearers.extend(next.attached[si].iter().copied()); }
    for bearer in bearers {
        if next.alive[bearer] <= 0 || next.retreating_strike_round[bearer] == next.round {
            continue;
        }
        let Some(spec) = statics[next.roster.profile[bearer]].retreating_strikes.first() else { continue; };
        next.retreating_strike_round[bearer] = next.round;
        let dice = spec.rating.max(1) * next.alive[bearer];
        if dice <= 0 { continue; }
        let faces = tray.roll(dice as usize);
        let w = faces.iter().filter(|&&f| f as i64 >= RAVAGE_WOUND_TARGET).count() as i64;
        shot.rolls.push(crate::dice::Roll {
            kind: "ravage", count: dice, target: RAVAGE_WOUND_TARGET,
            faces: faces.clone(), owner: statics[next.roster.profile[bearer]].name.clone(),
        });
        let landed = crate::dice::regen_batch(w, 0, &def, &def_owner, tray, &mut shot.rolls);
        land_wounds_with(next, ti, landed, seams.tray_exact, seams.rules_epoch);
        shot.log.push(format!(
            "{}: {} strikes while retreating -- {} dice -> {} wound(s) on {} (no save)",
            spec.name, statics[next.roster.profile[bearer]].name, dice, w, def_owner));
        // The table's words (`_solo_apply_retreating_strike`): an em dash, an arrow, `wound`/`wounds`.
        say_rule(tray, "retreating_strike", next.player[bearer], || format!(
            "{}: {} strikes while retreating — {} dice → {} wound{} on {} (no save)",
            spec.name, statics[next.roster.profile[bearer]].name, dice, w, if w == 1 { "" } else { "s" }, def_owner));
    }
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
        || hit_and_run_mixed(statics, next, si, after_shoot, seams.rules_epoch)
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
    // EPOCH_96_PARITY_BATCH: the anchor is the table's `_nearest_enemy_of` pick (`nearest_enemy_of`: plain nearest, joined
    // heroes skipped) for the early outs and the board-less rigid kite too, not the not-activated-first reposition pick.
    let anchor = if rule_on(seams.rules_epoch, crate::acts::EPOCH_96_PARITY_BATCH) {
        nearest_enemy_of(next, si)
    } else {
        nearest_enemy_reposition(statics, next, si)
    };
    let Some(enemy) = anchor else { return false };
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
    // EPOCH_96_PARITY_BATCH: on a real board the step is the ported fallback below whatever `seams.movement` says
    // (the shadow and the door run without it and took the rigid kite, which checks the board edge only).
    let ported = (seams.movement && !seams.move_rigid) || rule_on(seams.rules_epoch, crate::acts::EPOCH_96_PARITY_BATCH);
    if ported && !seams.plain_only {
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
                next.moved_round[si] = next.round;
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
    next.moved_round[si] = next.round;
    true
}

/// UX-19 (F10, ruling D-PERMODEL) — the table's `hit_and_run_move` gate: from
/// `EPOCH_73_V36` EVERY model must carry the family for this trigger, living
/// joined heroes included (`State::attached`, read whatever `hero_attach` says:
/// the table always moves the whole formation). True = some but not all carry
/// it, so no step and the caller logs the refusal. Below the epoch: false, so
/// the host-only gate stays byte-identical.
fn hit_and_run_mixed(statics: &[UnitStatic], st: &State, si: usize, after_shoot: bool, rules_epoch: u32) -> bool {
    if !rule_on(rules_epoch, crate::acts::EPOCH_73_V36) || st.alive[si] <= 0 {
        return false;
    }
    let carries = |u: usize| {
        let s = &statics[st.roster.profile[u]];
        s.hit_and_run_active
            || (after_shoot && s.hit_and_run_shooter_active)
            || (!after_shoot && s.hit_and_run_fighter_active)
    };
    let heroes: Vec<usize> =
        st.attached.get(si).into_iter().flatten().copied().filter(|&h| st.alive[h] > 0).collect();
    let carriers = usize::from(carries(si)) + heroes.iter().filter(|&&h| carries(h)).count();
    carriers > 0 && carriers < 1 + heroes.len()
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
        if best.is_none_or(|(_, v)| state.alive[i] > v) {
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
    models_only: bool,
) -> i64 {
    let Cover::Board(t) = cover else { return 0 };
    if !t.is_valid() || state.profile(si).special_rules.iter().any(|r| r == "Flying") {
        return 0;
    }
    // `base_in_terrain` on this board — both halves of the trigger use it.
    let in_dang = |p: &[f64; 3], r: f64| base_in_terrain(geom::to_f32(*p), r, t, is_dangerous);
    // STANDALONE_SWEEP_A_2026-09-14, row `Dangerous Terrain Debuff` — the
    // FROZEN `EPOCH_27_TERRAIN_DEBUFF`: the granted "Dangerous Terrain" the
    // unit CARRIES is a hazard the cell consults never see. It rides the same
    // trigger and the same flying guard a crossing does; below 27 the grant
    // reads nothing, so every recorded game replays.
    let debuffed = |st: &State, u: usize| {
        mods::granted_terrain_debuff(st, u, "Dangerous Terrain", seams.rules_epoch)
    };
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
            let mut units = vec![si];
            if seams.hero_attach {
                units.extend(state.attached[si].iter().copied());
            }
            // Tray-exact (`Seams::tray_exact`, dormant until the series' one
            // EPOCH_70 bump): the rigid move's own route IS each model's straight
            // segment, so the table's predicate on it (`leg_crosses`,
            // `_path_crosses_terrain`) is exact and nothing is flagged. Without
            // it — tree plan step 5b — this end-only reading can part from the
            // table's per-model trail ONLY where a model's straight route meets a
            // Dangerous cell, so the flag names exactly those moves. Samples one
            // base radius apart overlap; the dice never read the flag.
            let route = seams.tray_exact;
            let mut meets = false;
            for u in units {
                for m in 0..next.positions[u].len() {
                    let (b, r) = (next.positions[u][m], radius(next, u, m));
                    let crossed = in_dang(&b, r)
                        || (route && state.positions[u].get(m).is_some_and(|a| {
                            let leg = [t.to_inch(geom::to_f32(*a)), t.to_inch(geom::to_f32(b))];
                            crate::mv::step::leg_crosses(&leg, r, t, is_dangerous)
                        }));
                    movers.push((u, m, crossed));
                    if route {
                        continue;
                    }
                    let Some(a) = state.positions[u].get(m).filter(|_| !meets) else { continue };
                    let steps = (geom::length(geom::sub(geom::to_f32(b), geom::to_f32(*a))) as f64 / r.max(1e-3)).ceil().max(1.0) as usize;
                    meets = (0..=steps).any(|k| {
                        let f = k as f64 / steps as f64;
                        in_dang(&[a[0] + f * (b[0] - a[0]), a[1] + f * (b[1] - a[1]), a[2] + f * (b[2] - a[2])], r)
                    });
                }
            }
            if meets {
                shot.mark("dangerous_rigid_end_only");
            }
        }
    }
    // `wounds_max` is the FULL model list and `positions` only the survivors;
    // this port's casualties come off the FRONT (`land_wounds`), so the living
    // models are that list's tail.
    let tough = |u: usize, m: usize| {
        let w = &statics[state.roster.profile[u]].wounds_max;
        let off = w.len().saturating_sub(state.positions[u].len());
        w.get(off + m).copied().unwrap_or(1).max(1)
    };
    let mut dice = 0;
    for (u, m, crossed) in movers {
        let Some(p0) = state.positions[u].get(m) else { continue };
        if !crossed && !in_dang(p0, radius(state, u, m)) && !debuffed(state, u) {
            continue;
        }
        dice += if models_only { 1 } else { tough(u, m) };
    }
    // UX-20 (`EPOCH_73_V36`, rules 3.6): one affected model is enough, and then
    // the WHOLE joined unit (host + attached heroes, every living model) takes
    // ONE test, and the test rolls one die per WOUND THE UNIT HAS LEFT (UX-21).
    // Below 73 only the affected models roll their Tough value. `models_only`: the
    // consolidation's own count, one die per affected model - the table hands
    // `_run_ai_dangerous` that model count after a consolidation move (main.gd).
    if dice > 0 && !models_only && rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
        let mut chain = vec![si];
        if seams.hero_attach {
            chain.extend(state.attached[si].iter().copied());
        }
        dice = chain.iter().map(|&u| wounds_left(state, u)).sum();
        shot.log.push(format!(
            "Dangerous terrain: {} takes one test for the whole unit ({dice} dice)",
            statics[state.roster.profile[si]].name
        ));
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
    let shaped = seams.charge_landing || (seams.movement && !seams.plain_only);
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

/// Inventory C01/C27 — the nearest BASE-EDGE gap (inches) from `a_pos` (unit `si`'s models, or a moved copy
/// of them) to unit `ti`'s models, through the recorded base shapes: the table's shooting-range and over-9"
/// measure, and (Inventory T05) the charge-distance measure of the by-speed reply. Empty side = INFINITY like
/// `geom::dist_in`.
pub fn range_gap_in(state: &State, a_pos: &[[f64; 3]], si: usize, ti: usize) -> f64 {
    let shape = |u: usize| state.roster.profile.get(u)
        .and_then(|&p| state.profiles.list.get(p))
        .map_or(geom::BaseShape::Round, crate::state::Profile::shape);
    geom::edge_gap_shaped_in(
        a_pos, &state.radii[si], shape(si),
        &state.positions[ti], &state.radii[ti], shape(ti),
        DEFAULT_BASE_RADIUS_M,
    )
}

/// G4R5 F-TARGET-CHAIN-GAP (`EPOCH_73_V36`, `hero_attach`): the range gap to a target is measured to the nearest
/// model of its whole chain, the host and its LIVING joined heroes (`gap(t)` measures one chain unit; the table's
/// `_note_nearest_model_reach`). Older records and a lone host keep `gap(ti)`, byte for byte.
fn chain_gap_in(state: &State, ti: usize, seams: Seams, gap: impl Fn(usize) -> f64) -> f64 {
    let mut best = gap(ti);
    if seams.hero_attach && rule_on(seams.rules_epoch, EPOCH_73_V36) {
        for &h in state.attached[ti].iter().filter(|&&h| state.alive[h] > 0) {
            best = best.min(gap(h));
        }
    }
    best
}

/// Live table modifier distance: nearest alive model bases, including joined
/// heroes when that seam is active. Older recordings keep the centre measure.
fn modifier_distance_in(state: &State, si: usize, ti: usize, seams: Seams) -> f64 {
    distance_in(state, si, ti, seams, None)
}

/// `EPOCH_86_VOLLEY_HEIGHT_REACH` (table twin `_solo_ai_volley_distance_in` over `nearest_melee_gap_in`): the played volley's modifier distance
/// counts only the model pairs within the vertical reach (3" from `EPOCH_73_V36`, `melee_vertical_in`), and a unit with no pair in reach keeps
/// the HORIZONTAL unit-centre distance. Before, a unit on a platform measured as close as the ground beside it, so the Valiant gate and the
/// over-9" modifiers read "inside 9"" in the core and "beyond" on the table. Step path only (`sighting`), like the sight gate.
fn volley_distance_in(state: &State, si: usize, ti: usize, seams: Seams) -> f64 {
    let reach = (seams.sighting && rule_on(seams.rules_epoch, crate::acts::EPOCH_86_VOLLEY_HEIGHT_REACH)).then_some(3.0 * IN2M);
    distance_in(state, si, ti, seams, reach)
}

/// The nearest-base gap of two units' chains; `reach_m` = the vertical reach that pairs must be within (see `volley_distance_in`).
fn distance_in(state: &State, si: usize, ti: usize, seams: Seams, reach_m: Option<f64>) -> f64 {
    let centre = || geom::centre_dist_in(&state.positions[si], &state.positions[ti]);
    if !rule_on(seams.rules_epoch, EPOCH_66_DISTANCE_TRUTH) {
        return centre();
    }
    let side = |u: usize| -> Vec<usize> {
        let mut units = vec![u];
        if seams.hero_attach {
            units.extend(state.attached[u].iter().copied());
        }
        units
    };
    // Some synthetic state fixtures carry only the static unit contexts; a
    // missing profile has the same round footprint as an unstamped base.
    let shape = |u: usize| state.roster.profile.get(u)
        .and_then(|&p| state.profiles.list.get(p))
        .map_or(geom::BaseShape::Round, crate::state::Profile::shape);
    let mut gap = f64::INFINITY;
    for a in side(si) {
        if state.alive[a] <= 0 { continue; }
        for b in side(ti) {
            if state.alive[b] <= 0 { continue; }
            let Some(reach) = reach_m else {
                gap = gap.min(geom::edge_gap_shaped_in(
                    &state.positions[a], &state.radii[a], shape(a),
                    &state.positions[b], &state.radii[b], shape(b),
                    DEFAULT_BASE_RADIUS_M,
                ));
                continue;
            };
            for (i, pa) in state.positions[a].iter().enumerate() {
                for (j, pb) in state.positions[b].iter().enumerate().filter(|(_, pb)| (pa[1] - pb[1]).abs() <= reach) {
                    gap = gap.min(geom::edge_gap_shaped_in(
                        std::slice::from_ref(pa), state.radii[a].get(i..=i).unwrap_or(&[]), shape(a),
                        std::slice::from_ref(pb), state.radii[b].get(j..=j).unwrap_or(&[]), shape(b),
                        DEFAULT_BASE_RADIUS_M,
                    ));
                }
            }
        }
    }
    if gap.is_finite() { return gap; }
    match reach_m {
        None => centre(),
        Some(_) => {
            let flat = |ps: &[[f64; 3]]| { let c = geom::centre(ps); [c[0], 0.0, c[2]] };
            (geom::length(geom::sub(flat(&state.positions[si]), flat(&state.positions[ti]))) / IN2M as f32) as f64
        }
    }
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
    statics: &[UnitStatic],
    seams: Seams,
    us: &UnitStatic,
    ti: usize,
    alive_before: i64,
    wounds_before: i64,
) -> bool {
    let root = morale_root(state, ti, seams);
    let (ti, us) = if root == ti { (ti, us) } else { (root, &statics[state.roster.profile[root]]) };
    // A2 (`EPOCH_72_PLAYTEST_RULES`, main.gd `_solo_shooting_morale` since #1912): WOUNDS that leave a
    // multi-model unit at half or less test too, without a lost model (p.10). `wounds_before` is the
    // host's own count, so a hit that lands only on a joined hero is not seen here.
    let wounded = |alive: i64, total: i64| {
        rule_on(seams.rules_epoch, EPOCH_72_PLAYTEST_RULES)
            && alive > 0
            && morale_wounds_left(state, ti, seams) < wounds_before
            && at_or_below_half(alive, total)
    };
    if hero_size_on(state, ti, seams) {
        // C12: `alive_before` is the combined snapshot (`morale_alive`).
        let (alive, total) = (combined_alive(state, ti, seams), combined_total(statics, state, ti, us));
        return should_test_shooting_morale(alive_before, alive, total) || wounded(alive, total);
    }
    if us.model_count == 1 {
        // A single model measures morale in TOUGH WOUNDS, not models (p.10).
        return state.alive[ti] > 0
            && morale_wounds_left(state, ti, seams) < wounds_before
            && below_half(state, statics, us, ti, seams);
    }
    should_test_shooting_morale(alive_before, state.alive[ti], us.model_count)
        || wounded(state.alive[ti], us.model_count)
}

/// The table's line when WOUNDS, not a lost model, call the shooting morale test (`_solo_shooting_morale`): a single model at half
/// its Tough value, or a multi-model unit at half strength or less. `None` when a lost model called it (the table says nothing).
#[allow(clippy::too_many_arguments)]
fn shooting_morale_line(
    state: &State, statics: &[UnitStatic], seams: Seams, us: &UnitStatic, ti: usize, alive_before: i64, wounds_before: i64,
) -> Option<String> {
    let root = morale_root(state, ti, seams);
    let (ti, us) = if root == ti { (ti, us) } else { (root, &statics[state.roster.profile[root]]) };
    let now = morale_wounds_left(state, ti, seams);
    if wounds_before < 0 || now >= wounds_before {
        return None;
    }
    let (alive, total) = if hero_size_on(state, ti, seams) {
        (combined_alive(state, ti, seams), combined_total(statics, state, ti, us))
    } else {
        (state.alive[ti], us.model_count)
    };
    if total == 1 {
        let start = us.wounds_max.first().copied().unwrap_or(0);
        return (alive > 0 && at_or_below_half(now, start))
            .then(|| format!("{} is at half its tough value ({now}/{start}) — morale test ({CITE})", us.name));
    }
    (rule_on(seams.rules_epoch, EPOCH_72_PLAYTEST_RULES) && alive > 0 && at_or_below_half(alive, total)
        && !should_test_shooting_morale(alive_before, alive, total))
        .then(|| format!("{} takes wounds at half strength or less ({alive}/{total} models) — morale test ({CITE})", us.name))
}

/// The Scourge note `scourge_morale_trigger` pushed to the recorded log, on the tray (the table's `_solo_scourge_decides` words are the same).
fn say_scourge(tray: &mut Tray, side: i64, lines: &[String]) {
    for l in lines.iter().filter(|l| l.starts_with("Scourge:")) {
        say_rule(tray, "scourge", side, || l.clone());
    }
}

/// SHO-15a Scourge (`EPOCH_73_V36`): the phantom wounds count toward this trigger only, read as landed on a
/// scratch copy (nothing is removed). Table twin: main.gd `_solo_scourge_decides`.
#[allow(clippy::too_many_arguments)]
fn scourge_morale_trigger(
    state: &State, statics: &[UnitStatic], seams: Seams, us: &UnitStatic, ti: usize,
    alive_before: i64, wounds_before: i64, phantom: i64, log: &mut Vec<String>,
) -> bool {
    let real = shooting_morale_trigger(state, statics, seams, us, ti, alive_before, wounds_before);
    if real && rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) && morale_alive(state, ti, seams) == alive_before {
        // Rules-must-log (G4R3 F-MORALE-CHAIN): no model fell, so the unit's wounds called the test (A2).
        let unit = &statics[state.roster.profile[morale_root(state, ti, seams)]].name;
        log.push(format!("Morale: {unit} takes wounds at half strength or less — morale test"));
    }
    if phantom <= 0 || state.alive[ti] <= 0 || !rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
        return real;
    }
    let mut v = state.clone();
    land_wounds_with(&mut v, ti, phantom, seams.tray_exact, seams.rules_epoch);
    let tips = !real && (v.alive[ti] <= 0 || below_half(&v, statics, us, ti, seams));
    let verdict = if tips { "they decide its morale test" } else { "they do not decide its morale test" };
    // tray twin: scourge
    log.push(format!("Scourge: {phantom} phantom wounds count against {} — {verdict}", us.name));
    real || tips
}

/// `BattleSim._ctx_of(su)` battle_sim.gd:701-712, SHOOTING half: the static
/// template with the snapshot's live `alive` and `in_cover` written over it.
/// (`melee` only adds the fatigue flag, which no shooting call sets.)
#[inline]
pub fn ctx_of(us: &UnitStatic, state: &State, i: usize) -> Ctx {
    let mut c = us.ctx;
    c.unit = Some(i);
    c.models = state.alive[i];
    // Audit 2026-09-13 §2.2 — the Impact cut counts the ALIVE Counter
    // bearers (`counter_models_of`'s `mini(bearers, alive)`): the static
    // stamp carries the full-strength bearer count, this fold trims it as
    // models die. Pre-port records carry 0 and stay 0.
    c.counter_models = c.counter_models.min(state.alive[i].max(0));
    // Rules 3.6 — Brace's own bearer count follows the same living-model trim.
    c.brace_models = c.brace_models.min(state.alive[i].max(0));
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

/// D21 (`EPOCH_68_MODIFIER_SUM`) — the record's epoch (Amendment B1). `ctx_for` already stamps the
/// same value at static build; this re-stamp on the dice defs is a harmless duplicate.
pub(crate) fn with_modifier_sum(mut c: Ctx, rules_epoch: u32) -> Ctx {
    c.modifier_sum = rule_on(rules_epoch, EPOCH_68_MODIFIER_SUM);
    c
}

pub fn ctx_live(mut c: Ctx, statics: &[UnitStatic], state: &State, i: usize, melee: bool, rules_epoch: u32) -> Ctx {
    // Exact shortcut: every grant read below needs a live record with a `grants_rule` somewhere on i's joined chain;
    // with none, all of them answer false — walk the chain once instead of 33 times (aifix training-speed lane).
    let grants = mods::chain_has_grants(state, i);
    // Wave 4 (port-entrenched) — the volley's def build is `ctx_live` (5168).
    c.moved_round = state.moved_round[i];
    c.round = state.round;
    // SHO-17 — the Guarded charge leg's shared 6" gate; 0.0 below the epoch keeps the old read.
    if melee && rule_on(rules_epoch, EPOCH_73_V36) {
        c.guarded_charge_over_in = crate::combat::CHARGE_LONG_RANGE_IN;
    }
    // Rules 3.6 (row W1.4b) — the Evasive and Dodge stamps read their
    // most-models majority from the LIVE living models: the static stamp was
    // built from the profile's full model count, so a unit that loses carriers
    // kept the rule. From `EPOCH_73_V36` a live majority that says OFF clears
    // the stamp; a live majority that still holds leaves the static value
    // untouched, and the Boost alias leg keeps Evasive on by itself. Below the
    // gate the helper answers None and nothing changes.
    if rule_on(rules_epoch, EPOCH_73_V36) {
        // A synthetic fixture may carry a shorter profile table than the roster
        // (no Profile to read): keep the static stamp there.
        let host = state.roster.profile.get(i).and_then(|&pi| state.profiles.list.get(pi));
        let heroes: Vec<(&crate::state::Profile, i64)> = state.attached[i]
            .iter()
            .filter(|&&h| state.alive[h] > 0)
            .filter_map(|&h| {
                let pi = *state.roster.profile.get(h)?;
                state.profiles.list.get(pi).map(|p| (p, state.alive[h]))
            })
            .collect();
        if let Some(host) = host {
            // Only a stamp the profile's own rules produced is cleared: a
            // synthetic fixture may force the flag on a profile that carries
            // no such rule, and that stamp is not ours to touch.
            if crate::rules::has_special_rule(&host.special_rules, "Dodge")
                && crate::unit::evasion_rule_live(
                    host, state.alive[i], &heroes, "Dodge", rules_epoch,
                ) == Some(false)
            {
                c.dodge = false;
            }
            if crate::rules::has_special_rule(&host.special_rules, "Evasive")
                && !c.evasive_alias
                && crate::unit::evasion_rule_live(
                    host, state.alive[i], &heroes, "Evasive", rules_epoch,
                ) == Some(false)
            {
                c.evasive = false;
            }
            if crate::rules::has_special_rule(&host.special_rules, "Ranged Shrouding")
                && crate::unit::most_models_family_live(
                    host, state.alive[i], &heroes, "Ranged Shrouding", rules_epoch,
                ) == Some(false)
            {
                c.ranged_shrouding = false;
            }
        }
    }
    // Rules 3.6 (row W1.4b) — the Stealth family's most-models read follows the
    // LIVE living models: the stamp was built from the profile's full model
    // count, so a unit that loses carriers kept the rule. From `EPOCH_73_V36`
    // the host and every living attached hero decide; the penalty numbers and
    // the alias stamps stay on the static profile. Below the gate the helper
    // answers None and the stamp is untouched.
    if rule_on(rules_epoch, EPOCH_73_V36) {
        // A synthetic fixture may carry a shorter profile table than the roster
        // (no Profile to read): keep the static stamp there.
        let host = state.roster.profile.get(i).and_then(|&pi| state.profiles.list.get(pi));
        let heroes: Vec<(&crate::state::Profile, i64)> = state.attached[i]
            .iter()
            .filter(|&&h| state.alive[h] > 0)
            .filter_map(|&h| {
                let pi = *state.roster.profile.get(h)?;
                state.profiles.list.get(pi).map(|p| (p, state.alive[h]))
            })
            .collect();
        if let Some(host) = host {
            // Only a stamp the profile's own rules produced is read live: a
            // stamp set by the core's aura fold carries none of the names on
            // the profile itself, and that stamp is not ours to touch.
            let carries = |name: &str| {
                crate::rules::has_special_rule(&host.special_rules, name)
                    || crate::rules::has_special_rule(&host.item_grants, name)
            };
            if carries("Stealth") {
                if let Some(on) = crate::unit::stealth_family_live(
                    host, state.alive[i], &heroes, "Stealth", rules_epoch,
                ) {
                    let (carriers, total) = crate::unit::stealth_live_counts(
                        host, state.alive[i], &heroes, "Stealth",
                    );
                    c.stealth = on;
                    c.stealth_most_models = on && carriers < total;
                }
            }
        }
    }
    // Row W1.4b-defence (rules 3.6) — the defence family's "most models" answer
    // is read from the LIVING joined unit at use time, not the profile-build
    // count: a squad that loses carriers can lose the stamp. SAFE DIRECTION
    // only: a live majority leaves the static value untouched (a static "on"
    // may come from an aura bearer or an unconditional alias leg the live tally
    // cannot see), so only `Some(false)` clears.
    if rule_on(rules_epoch, EPOCH_73_V36) {
        // Synthetic states in the existing sim tests carry a short profile table
        // and no attached rows, so read both leniently instead of indexing.
        let host = state.roster.profile.get(i).and_then(|&p| state.profiles.list.get(p));
        let heroes: Vec<(&crate::state::Profile, i64)> = state.attached.get(i)
            .map(|a| a.iter()
                .filter(|&&h| state.alive.get(h).copied().unwrap_or(0) > 0)
                .filter_map(|&h| {
                    let hp = *state.roster.profile.get(h)?;
                    Some((state.profiles.list.get(hp)?, state.alive.get(h).copied().unwrap_or(0)))
                })
                .collect())
            .unwrap_or_default();
        if let (Some(host), Some(&alive)) = (host, state.alive.get(i)) {
            // Only a stamp the profile's own rules produced is cleared: a
            // stamp the core's aura fold set carries none of the names on the
            // profile itself, and that stamp is not ours to touch.
            let carries = |names: &[&str]| names.iter().any(|name| {
                crate::rules::has_special_rule(&host.special_rules, name)
                    || crate::rules::has_special_rule(&host.item_grants, name)
            });
            let fortified_live = crate::unit::defence_family_live(
                host, alive, &heroes, &["Fortified"], rules_epoch,
            );
            if carries(&["Fortified"]) && fortified_live == Some(false) {
                c.fortified = false;
            }
            if carries(&["Guarded", "Versatile Defense", "Sturdy", "Safety Gear", "Tenacious"])
                && crate::unit::defence_family_live(
                    host, alive, &heroes,
                    &["Guarded", "Versatile Defense", "Sturdy", "Safety Gear", "Tenacious"],
                    rules_epoch,
                ) == Some(false)
            {
                c.guarded = false;
            }
            if carries(&["Shielded"])
                && crate::unit::defence_family_live(
                    host, alive, &heroes, &["Shielded"], rules_epoch,
                ) == Some(false)
            {
                c.shielded = false;
            }
        }
    }
    // Rules 3.6 (row W1.TRACE) — the utility-buff family's live hit grant
    // names itself (arm `utility-grant-live`), one line per firing record.
    let mut hit_mod = 0;
    for u in [Some(i), state.attached_to[i]].into_iter().flatten() {
        for r in &state.buffs[u] {
            if mods::matches(r, mods::Role::AttackerOwn, melee) {
                hit_mod += r.hit_mod;
                if rule_on(rules_epoch, EPOCH_73_V36) {
                    trace_rule("utility-grant-live", &r.name, &format!(
                        "{:+} to hit on {}", r.hit_mod, statics[state.roster.profile[i]].name));
                }
            }
        }
    }
    c.hit_mod = hit_mod;
    c.vs_hit_mod = mods::sum(state, i, mods::Role::VsTarget, melee, |r| r.hit_mod);
    // Wave 4 follow-up (port-vengeance) — "friendly units get +X to hit rolls
    // when attacking that unit" (main.gd:5806-5817): the markers sit ON the
    // unit its attackers hit, so this is the `vs_hit_mod` role itself, and
    // both tray legs (dice.rs's volley fold and `melee_hit_target`'s single
    // sum) already consume the field. The markers land on the chain HOST only
    // (main.gd:5897's `chain[0]`), and `attached_to` answers the host. Gated
    // on the FROZEN `EPOCH_7_TABLE_RULES`: a record below 7 keeps the sum
    // byte-exact.
    if rule_on(rules_epoch, EPOCH_7_TABLE_RULES) {
        c.vs_hit_mod += state.vengeance_markers[state.attached_to[i].unwrap_or(i)];
    }
    // SEAM 4 step 2 (design §4 step 2, the FROZEN `EPOCH_7_TABLE_RULES`) —
    // the ledger's two new knobs, summed the way `hit_mod` is:
    //   ap_mod — "loses AP(+1) when attacking" (Piercing Debuff): the
    //     DEBUFFED unit's own attacks ride AP one lower, floored by the
    //     existing `max(0)` at the dice save target.
    //   defense_mod — the "+/-X to defense rolls" pair (Defense Buff's
    //     `def_mod`, Defense Debuff's `defense_mod`, same axis): a ROLL
    //     bonus, so the stamp carries the NEGATED sum and the save rung
    //     folds `defense + defense_mod` — the covered/Shielded shape
    //     (cover's own "+1 to Defense rolls" is `defense - 1`), floored at
    //     `BEST_HIT_TARGET` in dice::save_batch. EV-only paths never call
    //     ctx_live and stay blind; a record below 7 carries no knobs (the
    //     PR 1 reader gate) and this fold is gated here as well.
    if rule_on(rules_epoch, EPOCH_7_TABLE_RULES) {
        let un = &statics[state.roster.profile[i]].name;
        c.ap_mod = mods::sum_logged(state, i, mods::Role::Ap, melee, un, "AP", |r| r.ap_mod);
        c.defense_mod = -mods::sum_logged(state, i, mods::Role::Defense, melee, un, "defense", |r| r.def_mod + r.defense_mod);
        c.defense_mod_parts = defense_mod_parts_of(state, i, melee);
    }
    c.unstoppable_grant = grants && mods::granted(state, i, "Unstoppable");
    // EPOCH 34 UNSTOPPABLE MARK — the mark's CLAMP half rides the SAME
    // once-grant ("Unstoppable", the mark's base name, spent with the
    // exchange like the Regeneration half — one record, never twice), but
    // gated: below 34 the to-hit clamps stay `p.unstoppable`-only and every
    // recorded corpus replays its own clamp-blind rolls.
    // EPOCH 37 UNSTOPPABLE AURA — from 37 the mark's stamp reads the MELEE
    // half of the grant (`""`/`"melee"` scopes): the shooting-scoped aura
    // record stops feeding the mark stamp, so it can no longer arm the MELEE
    // clamp (or log the mark's "(once)" line) through the scope-blind union.
    c.unstoppable_mark = if rule_on(rules_epoch, EPOCH_37_UNSTOPPABLE_AURA) {
        grants && mods::granted_in_scope(state, i, "Unstoppable", false)
    } else {
        c.unstoppable_grant && rule_on(rules_epoch, EPOCH_34_UNSTOPPABLE_MARK)
    };
    // EPOCH 37 UNSTOPPABLE AURA — the aura's own two stamps, both gated so a
    // pre-37 record replays byte-exact: `unstoppable_aura` is the
    // SHOOTING-scoped part (arms the SHOOTING clamp, names the SHOOTING
    // Regeneration line), `unstoppable_regen_melee` is the melee Regeneration
    // read's final answer (the scope-blind union below 37, the melee half from
    // 37 — the shooting-scoped aura stops bypassing melee Regeneration).
    c.unstoppable_aura = rule_on(rules_epoch, EPOCH_37_UNSTOPPABLE_AURA)
        && (grants && mods::granted_shooting_scoped(state, i, "Unstoppable"));
    c.unstoppable_regen_melee = if rule_on(rules_epoch, EPOCH_37_UNSTOPPABLE_AURA) {
        grants && mods::granted_in_scope(state, i, "Unstoppable", false)
    } else {
        c.unstoppable_grant
    };
    // DEFECT_LEDGER #33 — a live "Furious" grant (a spell cast, same shape as
    // any other rule grant) reaches this round's melee exactly where the
    // static special-rule scan (`unit::ctx_for`) already sets it, and stays
    // out of the EV-only imagination, which never calls `ctx_live` at all.
    c.furious = c.furious || (grants && mods::granted(state, i, "Furious"));
    // The rending/thrust legs of the same grant bridge (main.gd:16576-16589),
    // and the Ctx-flag grants the rung E buffs hand out — each lands exactly
    // where the static has-rule test already stamped its flag.
    c.rending_grant = grants && mods::granted(state, i, "Rending");
    c.thrust_grant = grants && mods::granted(state, i, "Thrust");
    c.relentless_grant = grants && mods::granted(state, i, "Relentless");
    c.shred_grant = grants && mods::granted(state, i, "Shred");
    c.bane_grant = rule_on(rules_epoch, EPOCH_73_V36) && grants && mods::granted(state, i, "Bane when Shooting");
    c.unpredictable = c.unpredictable || (grants && mods::granted(state, i, "Unpredictable Fighter"));
    c.guarded = c.guarded || (grants && mods::granted(state, i, "Guarded"));
    c.melee_evasion = c.melee_evasion || (grants && mods::granted(state, i, "Melee Evasion"));
    // No Retreat folds HERE for every ctx_live caller; the rolled morale test
    // is not one (tray_morale builds on ctx_of), so it carries its own fold
    // next to the same read below.
    c.no_retreat = c.no_retreat || (grants && mods::granted(state, i, "No Retreat"));
    // Wave 4 (port-entrenched) — the GRANT leg: a recorded "Entrenched Buff"
    // (`_solo_apply_grant` overlay) feeds the SAME stationary read. Rules 3.6
    // (row MOR-04) reads -1 over 12" from `EPOCH_73_V36`; below it the old
    // magnitudes (2 / 9) replay byte-exact. FROZEN `EPOCH_7_TABLE_RULES` below.
    let (ent_pen, ent_over) = if rule_on(rules_epoch, EPOCH_73_V36) {
        (1, 12.0)
    } else {
        (2, 9.0)
    };
    if rule_on(rules_epoch, EPOCH_7_TABLE_RULES) && (grants && mods::granted(state, i, "Entrenched"))
        && c.stationary_alias_penalty < ent_pen
    {
        c.stationary_alias_penalty = ent_pen;
        c.stationary_alias_over_in = ent_over;
        c.stationary_alias_name = "Entrenched";
    }
    // FAB-C15 — the "Stealth Buff" 3.6 once-grant hands the literal Stealth
    // name to a picked friendly (`_solo_apply_grant` overlay). Read it where
    // the profile's own Stealth stamp lands; the grant is 3.6 data only.
    if rule_on(rules_epoch, EPOCH_73_V36) {
        c.stealth_grant = grants && mods::granted(state, i, "Stealth");
        c.stealth = c.stealth || c.stealth_grant;
    }
    // CENSUS rows 1-5 (evidence-only, non-folding — semantics §11.2/§12):
    // exercise the recorded grant ledger and log; the recorded band carries
    // the effect, so this must never fold. From `EPOCH_19_MOVE_GRANTS_FOLD`
    // the family folds for real at the move spend (`solo_move_grant_delta_in`),
    // so the "recorded band carries it" line would lie there — the fold's own
    // trace names every firing grant instead.
    if !rule_on(rules_epoch, EPOCH_19_MOVE_GRANTS_FOLD) {
        for name in mods::solo_move_grants(state, i, rules_epoch) {
            trace_rule("solo-grant", name, &format!("recorded band carries it (evidence-only), unit {i}"));
        }
    }
    // WAVE 2 — the family's live-grant legs. Gated on `EPOCH_5_TABLE_RULES`
    // (frozen at 5, the stamping-gap fix): a rules_epoch below 5 replays
    // every pre-wave corpus untouched (spell grants included, Gen-2b's
    // stamping-gap window at rules_epoch 4 included).
    if rule_on(rules_epoch, EPOCH_5_TABLE_RULES) {
        c.slayer_grant = grants && mods::granted(state, i, "Slayer");
        c.surge_grant = grants && mods::granted(state, i, "Enhanced Primal");
        c.versatile_grant = grants && mods::granted(state, i, "Versatile Attack");
        // The live grant only ADDS to the static Expert flag (`unit::ctx_for`); assigning would drop it.
        c.versatile_no_gate = c.versatile_no_gate
            || (rule_on(rules_epoch, EPOCH_73_V36) && grants && mods::granted(state, i, "Enhanced Watchborn"));
        c.pierce_shooting_grant = grants && mods::granted(state, i, "AP(+1) when shooting");
        c.pierce_melee_grant = grants && mods::granted(state, i, "AP(+1) in melee");
        // EPOCH 23 INERT MARKS (MARK_FAMILY_SWEEP_2026-09-14 finding 1): the
        // two Piercing marks' once-grants ride `tray_vs_marks` with the
        // entry's own `grants_rule` string — which the base-name reads above
        // can never match (`base_rule_name` splits at the '('). Below 23 the
        // grant keeps the base name and stays inert: every corpus replays the
        // recorded no-op.
        if rule_on(rules_epoch, EPOCH_23_INERT_MARKS) {
            c.pierce_shooting_grant = c.pierce_shooting_grant
                || (grants && mods::granted_exact(state, i, "AP(+1) when shooting"));
            c.pierce_melee_grant =
                c.pierce_melee_grant || (grants && mods::granted_exact(state, i, "AP(+1) in melee"));
        }
        // DAT-06 — the AoF "Piercing Charge Buff" hands its bearer the granted
        // rule "Piercing Charge"; from `EPOCH_73_V36` that grant reads as the
        // same primitive. Below 73 the ledger stays blind.
        c.pierce_assault_grant = grants
            && (mods::granted(state, i, "Piercing Assault")
                || (rule_on(rules_epoch, EPOCH_73_V36)
                    && mods::granted(state, i, "Piercing Charge")));
        // EPOCH 44 SURGE MARK — the mark's once-grant ("Surge", placed by
        // `tray_vs_marks` at the attack seam, spent with the exchange) rides
        // the same attacker-side read the Primal Boost grant uses; the spell
        // casts' "Surge" grants sit in the ATTACKERS-side net (`granted_vs`),
        // so they stay unread exactly as before. Gated: below 38 no such
        // record can exist (the entry replays the recorded self-Surge stamp).
        c.surge_mark_grant =
            rule_on(rules_epoch, EPOCH_44_SURGE_MARK) && (grants && mods::granted(state, i, "Surge"));
        c.unpredictable_shooting =
            c.unpredictable_shooting || (grants && mods::granted(state, i, "Unpredictable Shooter"));
        if c.unpredictable_shooting && c.unpredictable_name.is_empty() {
            c.unpredictable_name = "Unpredictable Shooter"; // a spell-granted die (the table's `granted_rules_of` branch)
        }
        // The Regeneration-primitive boosts: the granted entry's printed
        // targets, folded by the static stamp's own running-MIN rule.
        if grants && mods::granted(state, i, "Enhanced Self-Repair") {
            if rule_on(rules_epoch, EPOCH_73_V36) {
                trace_rule("regen-boost-live", "Enhanced Self-Repair", &format!(
                    "live Boost leg on {}", statics[state.roster.profile[i]].name));
            }
            c.regeneration = true;
            c.regen_target = fold_min(c.regen_target, SELF_REPAIR_BOOST_TARGET);
            c.regen_target_spell = fold_min(c.regen_target_spell, SELF_REPAIR_BOOST_TARGET);
        }
        if grants && mods::granted(state, i, "Enhanced Cursed Undead") {
            c.regeneration = true;
            c.regen_target = fold_min(c.regen_target, CURSED_UNDEAD_BOOST_TARGET);
            c.regen_target_spell = fold_min(c.regen_target_spell, CURSED_UNDEAD_BOOST_TARGET);
        }
        // DAT-17a — a granted "Regeneration" (the "Regeneration Buff" once-grant)
        // reads as the family's primitive from `EPOCH_73_V36` on; below 73 the
        // ledger stays blind and the static stamp alone decides.
        if rule_on(rules_epoch, EPOCH_73_V36) && grants && mods::granted(state, i, "Regeneration") {
            c.regeneration = true;
            c.regen_named = true;
            c.regen_target = fold_min(c.regen_target, REGENERATION_TARGET);
            c.regen_target_spell = fold_min(c.regen_target_spell, REGENERATION_TARGET);
        }
        // spell_only: the Angelic stamp folds the spell twin ONLY.
        c.regen_target_spell = if grants && mods::granted(state, i, "Enhanced Angelic Blessing") {
            fold_min(c.regen_target_spell, ANGELIC_BLESSING_BOOST_TARGET_SPELL)
        } else {
            c.regen_target_spell
        };
    }
    // Row W1.4b — the family's "most models" majority reads the LIVING models; below 73 unchanged.
    if rule_on(rules_epoch, EPOCH_73_V36) {
        if let Some(host) = state.profiles.list.get(state.roster.profile[i]) {
            let heroes: Vec<_> = state.attached[i].iter().filter(|&&h| state.alive[h] > 0)
                .filter_map(|&h| {
                    let hpi = state.roster.profile[h];
                    let hc = &statics[hpi].ctx;
                    Some((state.profiles.list.get(hpi)?, state.alive[h], (hc.regen_target, hc.regen_target_spell)))
                }).collect();
            match crate::unit::regen_family_live(host, state.alive[i],
                (c.regen_target, c.regen_target_spell), &heroes, rules_epoch) {
                Some((target, spell, regen_named)) => {
                    c.regeneration = true;
                    c.regen_named = c.regen_named || regen_named;
                    c.regen_target = fold_min(c.regen_target, target);
                    c.regen_target_spell = fold_min(c.regen_target_spell, spell);
                }
                None if !grants || !(mods::granted(state, i, "Regeneration")
                    || mods::granted(state, i, "Enhanced Self-Repair")
                    || mods::granted(state, i, "Enhanced Cursed Undead")) => {
                    // "Resistance" is a REGEN_MOST_MODELS name at 73 (MOR-07), so the
                    // live majority owns it; the boosts and Medical Training stay static.
                    let own = ["Medical Training", "Regeneration Buff",
                        "Self-Repair Boost", "Cursed Undead Boost", "Plaguebound Boost",
                        "Angelic Blessing Boost"].iter().any(|r| {
                        crate::rules::has_special_rule(&host.special_rules, r)
                            || host.item_grants.iter().any(|g| crate::rules::base_rule_name(g) == *r)
                    });
                    if !own && crate::unit::REGEN_MOST_MODELS.iter()
                        .any(|n| crate::unit::regen_family_on(host, n, rules_epoch)) {
                        c.regeneration = false;
                        c.regen_named = false;
                    }
                }
                None => {}
            }
        }
    }
    // WAVE 3 MARKS (`acts::rule_on`, frozen at `EPOCH_6_TABLE_RULES`): the two
    // enemy-side grant names the pre-attack pick already records on the marked
    // unit (main.gd:16534, `beneficiary: "attackers"`). `indirect_mark` is
    // consumed by the volley's sight seams (`sighted_profiles_of`, the pooled
    // gate), `range_mark_in` by the dice-side reach gate — a record below
    // epoch 6 keeps today's inert reading, and the EV imagination (`ctx_of`)
    // stays blind, the sighting seam's own asymmetry.
    if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        c.indirect_mark = grants && mods::granted_vs(state, i, "Indirect");
        c.indirect_own = grants && rule_on(rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) && mods::granted_own_indirect(state, i);
        c.range_mark_in = if grants && mods::granted_vs(state, i, "+6\" shooting range") {
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
            ("Enhanced Sturdy", ShieldedAlias::SturdyBoost, false),
            ("Grounded Defense", ShieldedAlias::GroundedReinforcement, true),
        ] {
            if (grants && mods::granted(state, i, name)) && (!terrain || c.in_cover) {
                c.shielded = true;
                if c.shielded_alias == ShieldedAlias::None {
                    c.shielded_alias = alias;
                }
                // Rules 3.6 (row W1.TRACE) — the live Shielded grant names
                // itself (arm `shielded-grant-live`), one line per record.
                if rule_on(rules_epoch, EPOCH_73_V36) {
                    trace_rule("shielded-grant-live", "Shielded", &format!(
                        "{name} grants Shielded (unit {i})"));
                }
            }
        }
    }
    // EPOCH 56 GROUNDED PROTECTION (sweep F 2026-09-14, row `Grounded
    // Protection`): the Regeneration family's terrain-conditional kind. The
    // alias wave holds the entry's target aside (unit.rs `regen_targets`'s
    // pending tail); THIS is the resolution — per save moment, on the
    // snapshot's own `in_cover`, the same live read the Shielded family's
    // terrain-pending kind answers in the block above. In the open there is
    // no fold and no roll. Rules-must-log: both verdicts trace, the regen
    // trace names the rule and its verdict. Gated on the FROZEN constant,
    // never `CURRENT_RULES_EPOCH`.
    if rule_on(rules_epoch, EPOCH_56_GROUNDED_PROTECTION) && c.regen_pending > 0 {
        let unit = &statics[state.roster.profile[i]].name;
        if c.in_cover {
            // the table says the verdict only when the held-aside rule is the best ignore (strictly below every other target)
            if c.regen_target == 0 || c.regen_pending < c.regen_target {
                c.regen_note = c.regen_pending_notes[0];
            }
            c.regeneration = true;
            c.regen_target = fold_min(c.regen_target, c.regen_pending);
            c.regen_target_spell = fold_min(c.regen_target_spell, c.regen_pending_spell);
            trace_rule("grounded-protection", unit, "within 1\" of terrain -> Regeneration (the held-aside fold resolves)");
        } else {
            c.regen_note = c.regen_pending_notes[1];
            trace_rule("grounded-protection", unit, "in the open -> no Regeneration (the fold holds)");
        }
    }
    // #2613 (EPOCH_75_TABLE_FIXES): Protection Feat is once per game — its held-aside target folds only
    // while the bearer's `feats_used` latch is open (`spend_protection_feat` closes it).
    if rule_on(rules_epoch, EPOCH_75_TABLE_FIXES) && c.regen_feat > 0 {
        let unit = &statics[state.roster.profile[i]].name;
        if state.feats_used[i].iter().any(|n| n == PROTECTION_FEAT) {
            trace_rule("protection-feat", unit, "already used it this game -> no ignore roll");
            c.regen_feat_spent = if c.regen_pending_notes[3].is_empty() { PROTECTION_FEAT } else { c.regen_pending_notes[3] };
        } else {
            c.regeneration = true;
            c.regen_target = fold_min(c.regen_target, c.regen_feat);
            c.regen_target_spell = fold_min(c.regen_target_spell, c.regen_feat);
        }
    }
    // WAVE 3 — the Fortified family's live-grant leg, gated on the FROZEN
    // `EPOCH_6_TABLE_RULES`: the three Boost names' uniform printed shape
    // (AP(-1), no distance gate) folds as one flag-width stamp, the
    // Self-Repair Boost precedent; epoch-5 records replay untouched.
    if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        let fortified_grant = ["Enhanced Guardian", "Enhanced Warden", "Enhanced Ossified"]
            .into_iter()
            .find(|name| grants && mods::granted(state, i, name));
        if let Some(name) = fortified_grant {
            // AI-G2 R7c (EPOCH_73_V36): the granted enhanced form's cut (2) replaces the base's 1 — the book text of
            // all three names; the printed rows carry the same number (`fortified_alias_of`).
            c.fortified_boost_ap = c.fortified_boost_ap.max(if rule_on(rules_epoch, EPOCH_73_V36) { 2 } else { 1 });
            // Rules 3.6 (row W1.TRACE) — this live Boost grant raises the
            // Fortified stamp, so it is the branch that names itself (arm
            // `fortified-grant-live`), never the majority read.
            if rule_on(rules_epoch, EPOCH_73_V36) {
                trace_rule("fortified-grant-live", name, &format!(
                    "live Fortified Boost grant (unit {i})"));
            }
        }
    }
    let (ap, hit) = growth_bonus_of(statics, state, i);
    c.growth_ap_mod = ap;
    c.growth_hit_mod = hit;
    c.growth_ap_name = growth_ap_name_of(statics, state, i);
    // rules-wave3-growthmark — the family's DEFENDER-side facets, gated on
    // `EPOCH_6_TABLE_RULES` (frozen at 6, the stamping-gap rule): a record
    // stamping `rules_epoch: 5` (the recording fleet's live epoch) replays
    // byte-exact, exactly like the Lacerate/ambush waves' own gates.
    if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        let (dm, fa) = growth_defense_of(statics, state, i);
        c.growth_def_mod = dm;
        c.growth_fortify_ap = fa;
        if dm != 0 {
            c.growth_def_parts = growth_def_parts_of(statics, state, i);
        }
        if fa != 0 {
            c.growth_fortify_name = growth_fortify_name_of(statics, state, i);
        }
    }
    // Issue #854 (wave 4) — the defence facet's SAVE-RUNG direction flips to
    // the table's at the FROZEN `EPOCH_7_TABLE_RULES`: `dice::save_batch` then
    // folds `clampi(defense - growth_def_mod, 2, 6)` like main.gd:5510. Below
    // 7 the flag stays false and the wave-3 (inverted) reading replays
    // byte-exact. Gated on `growth_def_mod != 0` exactly like the table's own
    // `if bonus != 0` (main.gd:5509) — a bearerless defence stat is never
    // clamped.
    if rule_on(rules_epoch, EPOCH_7_TABLE_RULES) && c.growth_def_mod != 0 {
        c.growth_def_lowers = true;
    }
    // Ambush family (rules-wave2-ambush): "Ambushing Piercing Shot" shoots
    // AP(+1) on the very round the unit arrives — `ambush_arrived_round` is
    // the stamp `arrive_unit`/`_finish_reserve_arrival` writes, and `!melee`
    // is the rule's own shooting-only facet. Zero below `rules_epoch` 4 (the
    // family stamp is epoch-gated) and for every EV-only path: those never
    // call `ctx_live`, the same buff-blindness `growth_ap_mod` keeps. The table folds it from `EPOCH_73_V36` only (G4R5
    // F-AMBUSH-ARRIVAL-AP, `_solo_ambush_arrival_ap`): below 73 its records say AP 1, so the core's fold waits for 73 too.
    if !melee && rule_on(rules_epoch, EPOCH_73_V36) && state.ambush_arrived_round[i] == state.round {
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
    if c.relentless_grant {
        c.relentless_from = mods::grant_source(state, i, target, "Relentless");
    }
    c.shred_grant = c.shred_grant || mods::granted_vs(state, target, "Shred");
    c.bane_mark_grant = rule_on(rules_epoch, crate::acts::EPOCH_96_PARITY_BATCH) && mods::marked_vs(state, target, "Bane Mark");
    if rule_on(rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) {
        c.slayer_grant = c.slayer_grant || mods::granted_vs(state, target, "Slayer");
    }
    // The melee-scoped Piercing Fighting Mark waits on the marked unit for its charger (`EPOCH_94_PARITY_BATCH`); a volley never reads it.
    if melee && rule_on(rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) {
        c.pierce_melee_grant = c.pierce_melee_grant || mods::granted_vs_exact(state, target, "AP(+1) in melee");
    }
    // G4R3 F-SURGE-GRANT (EPOCH_73_V36): a spell's once-grant of Surge to the target's attackers (the table's
    // `_solo_bridge_granted_flags`) pays like the Surge mark; the exchange spends the record.
    c.surge_mark_grant = c.surge_mark_grant
        || (rule_on(rules_epoch, EPOCH_73_V36) && mods::granted_vs(state, target, "Surge"));
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

/// Door lines: the names of the rules that gave `i` its marker AP (Piercing Growth / Frenzy), joined with ", " like the table's
/// `_solo_growth_attack_bonus` `ap_names`; "" when none did.
fn growth_ap_name_of(statics: &[UnitStatic], state: &State, i: usize) -> &'static str {
    let markers = state.growth_markers[i];
    let names: Vec<&str> = statics[state.roster.profile[i]].growth.iter()
        .filter(|g| markers > 0 && g.ap_per_marker * markers + g.ap_per_two * (markers / 2) > 0)
        .map(|g| g.name.as_str()).collect();
    if names.is_empty() { "" } else { crate::rules::intern(&names.join(", ")) }
}

/// Door lines: one `(rule name, Defense bonus)` per Defensive Growth / Frenzy rule that earned a bonus at the unit's marker count, in the
/// table's order (`_solo_growth_defense_parts`); empty when none did.
fn growth_defense_parts(statics: &[UnitStatic], state: &State, i: usize) -> Vec<(String, i64)> {
    let markers = state.growth_markers[i];
    statics[state.roster.profile[i]].growth.iter()
        .map(|g| (g.name.clone(), g.defense_per_marker * markers + g.defense_per_two * (markers / 2)))
        .filter(|(_, b)| markers > 0 && *b > 0).collect()
}

/// Door lines: the growth ladder's Defense parts as the table's Pierce line lists what it ignores (`<rule> +<bonus>`, ", "-joined).
fn growth_def_parts_of(statics: &[UnitStatic], state: &State, i: usize) -> &'static str {
    crate::rules::intern(&growth_defense_parts(statics, state, i).iter().map(|(n, b)| format!("{n} +{b}")).collect::<Vec<_>>().join(", "))
}

/// Door lines: the records behind `defense_mod`, in `mods::sum_logged`'s order, as `<name>\t<signed X>` per line (a +1 ward reads
/// `+1`, a hex `-1`). Interned, so `Ctx` stays `Copy`.
fn defense_mod_parts_of(state: &State, i: usize, melee: bool) -> &'static str {
    let mut parts = Vec::new();
    for u in [Some(i), state.attached_to[i]].into_iter().flatten() {
        for r in state.buffs[u].iter().filter(|r| mods::matches(r, mods::Role::Defense, melee)) {
            let v = r.def_mod + r.defense_mod;
            if v != 0 {
                parts.push(format!("{}\t{v:+}", r.name));
            }
        }
    }
    crate::rules::intern(&parts.join("\n"))
}

/// Door lines: the Fortified Growth rule's name (the first `enemy_ap_per_two` rule the unit carries).
fn growth_fortify_name_of(statics: &[UnitStatic], state: &State, i: usize) -> &'static str {
    statics[state.roster.profile[i]].growth.iter().find(|g| g.enemy_ap_per_two != 0).map_or("", |g| crate::rules::intern(&g.name))
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
fn growth_on_kill(statics: &[UnitStatic], next: &mut State, si: usize, tray: &mut Tray) {
    let us = &statics[next.roster.profile[si]];
    let Some((cap, rule)) = us.growth.iter().find(|g| g.on_kill).map(|g| (g.max_markers, g.name.as_str())) else {
        return;
    };
    if next.growth_markers[si] < cap {
        next.growth_markers[si] += 1;
        // The table's line (`_solo_growth_on_kill`), said where the marker is placed.
        let n = next.growth_markers[si];
        crate::dice::say_rule(tray, "growth_kill", next.player[si], || format!("{rule}: {} gains a marker for the kill ({n}/{cap})", us.name));
    }
}

/// AIG-G2 R2 (`EPOCH_73_V36`, hero seam on): the HOST's activation also ticks each living attached hero's own
/// per-round marker, under the host's Shaken reading — a joined hero's row never activates on its own. Table twin:
/// `_solo_growth_round_start` ticking a living attached hero. Below 73 nothing happens, exactly as before.
fn growth_round_start_heroes(statics: &[UnitStatic], next: &mut State, si: usize, shaken: bool, seams: Seams) {
    if !seams.hero_attach || !rule_on(seams.rules_epoch, EPOCH_73_V36) {
        return;
    }
    for h in next.attached[si].clone() {
        if next.alive[h] > 0 {
            growth_round_start(statics, next, h, shaken);
        }
    }
}

/// The kill credit of `growth_on_kill`, plus (AIG-G2 R2, `EPOCH_73_V36`, hero seam on) one per living attached hero
/// of the wiping side who carries an on_kill rule himself. Table twin: `_solo_growth_on_kill` over the chain.
fn growth_credit_kill(statics: &[UnitStatic], next: &mut State, wiper: usize, seams: Seams, tray: &mut Tray) {
    growth_on_kill(statics, next, wiper, tray);
    if !seams.hero_attach || !rule_on(seams.rules_epoch, EPOCH_73_V36) {
        return;
    }
    for h in next.attached[wiper].clone() {
        if next.alive[h] > 0 {
            growth_on_kill(statics, next, h, tray);
        }
    }
}

/// Wave 4 follow-up (port-vengeance) — `_solo_vengeance_on_destroyed`
/// main.gd:5884-5902: when a unit FULLY dies, the DESTROYER banks one marker
/// per START model of every Vengeance-carrying chain member of the dead
/// (main.gd:5893's `maxi(member.get_size(), 1)`; the static `model_count` is
/// that start count). The markers sit on the destroyer's chain HOST
/// (main.gd:5897's `chain[0]`), no cap — the book text has none, and the
/// table caps nothing either. The bonus half is `ctx_live`'s vs-side fold
/// above. The LOGGING RULE line rides the caller's `shot` (one line per
/// placement, like the table's `_log_rule_event`).
fn vengeance_on_kill(
    statics: &[UnitStatic],
    next: &mut State,
    dead: usize,
    killer: usize,
    shot: &mut ShootResult,
    tray: &mut Tray,
) {
    let dead_host = next.attached_to[dead].unwrap_or(dead);
    let mut markers = 0i64;
    for m in std::iter::once(&dead_host).chain(next.attached[dead_host].iter()) {
        let us = &statics[next.roster.profile[*m]];
        if us.vengeance_active {
            markers += us.model_count.max(1);
        }
    }
    if markers <= 0 {
        return;
    }
    let host = next.attached_to[killer].unwrap_or(killer);
    next.vengeance_markers[host] += markers;
    shot.log.push(format!(
        "Vengeance: {} falls — {} marker(s) on {} (its enemies get +1 to hit per marker)",
        statics[next.roster.profile[dead_host]].name, markers,
        statics[next.roster.profile[host]].name
    ));
    // The table's words (`_solo_vengeance_on_destroyed`): the fallen unit and the destroyer by their own names, `Vengeance marker(s)`.
    say_rule(tray, "vengeance", next.player[killer], || format!(
        "Vengeance: {} falls — {markers} Vengeance marker{} on {} (its enemies get +1 to hit per marker)",
        statics[next.roster.profile[dead]].name, if markers == 1 { "" } else { "s" }, statics[next.roster.profile[killer]].name));
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
/// Wave 4 follow-up (port-spell-accumulator) — the EMPTY-POOL fallback half
/// of the cast-phase read: at `EPOCH_7_TABLE_RULES` a chain caster that
/// carries spells but holds NO tokens still counts as the acting caster, so
/// the battery pool can pay for its spell; every earlier epoch keeps
/// `caster_of`'s "no tokens, no cast" answer untouched.
fn battery_chain_caster(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    seams: Seams,
) -> Option<usize> {
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) {
        return None;
    }
    // The fold gate is `caster_of`'s own: with the fold off the rest of the
    // resolver does not believe in the chain either (the cast_fold knob test
    // pins "seam_cast alone still casts nothing").
    if !(seams.cast_fold && seams.hero_attach) {
        return None;
    }
    std::iter::once(si)
        .chain(state.attached[si].iter().copied())
        .find(|&u| {
            let s = &statics[state.roster.profile[u]];
            state.alive[u] > 0 && s.is_caster && !s.spells.is_empty()
        })
}

/// The rule's own lend radius ("within 12\"", solo_controller.gd:4503).
const SPELL_ACCUMULATOR_REACH_IN: f64 = 12.0;

/// Wave 4 follow-up (port-spell-accumulator) — the battery pool, gated on
/// the frozen `EPOCH_7_TABLE_RULES` (see the call site's note).
fn battery_pool(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    ci: usize,
    seams: Seams,
) -> Vec<(usize, i64)> {
    if !rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) {
        return Vec::new();
    }
    let pid = state.player[si];
    let mut found: Vec<(usize, f64, i64)> = Vec::new();
    for u in 0..state.units() {
        let s = &statics[state.roster.profile[u]];
        if !s.spell_accumulator || s.is_caster {
            continue;
        }
        if u == ci || state.attached[si].contains(&u) {
            continue; // the caster's own chain is `caster_of`'s business
        }
        if state.player[u] != pid || state.alive[u] <= 0 || state.shaken[u] || state.casts[u] <= 0 {
            continue;
        }
        let d = geom::dist_in(&state.positions[ci], &state.positions[u]);
        if d <= SPELL_ACCUMULATOR_REACH_IN {
            found.push((u, d, state.casts[u]));
        }
    }
    found.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));
    found.into_iter().map(|(u, _, t)| (u, t)).collect()
}

/// Wave 6 (port-caster-boost) — the BOOST pool's helper half: every friendly
/// caster and `Spell Accumulator` battery holding tokens within the Caster
/// rule's `aura_in` (18", registry read solo_controller.gd:4568, fallback
/// ai_spell.gd:33) in line of sight of the caster's unit (:4606) — the
/// battery on its OWN 12" reach (:4565, :4604), a Shaken battery refused
/// (NML-936, :4596-4601; a Shaken real caster still lends, the walk mirrors
/// the table exactly there). Nearest-first, the table's own sort (:4609).
/// The caster's OWN leftover tokens are the FIRST boost source and are NOT
/// collected here (solo_controller.gd:4336-4342, the plan site's business).
/// Gated on the frozen `EPOCH_48_CASTER_BOOST`.
fn caster_boost_pool(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    ci: usize,
    los: &[bool],
    seams: Seams,
) -> Vec<(usize, i64)> {
    if !rule_on(seams.rules_epoch, EPOCH_48_CASTER_BOOST) { return Vec::new(); }
    let pid = state.player[si];
    let mut found: Vec<(usize, f64, i64)> = Vec::new();
    for u in 0..state.units() {
        let s = &statics[state.roster.profile[u]];
        if u == ci || state.player[u] != pid || state.alive[u] <= 0 || state.casts[u] <= 0 {
            continue;
        }
        // casters and batteries only (:4594); NML-936 (:4596-4601) refuses
        // only the BATTERY's lending — a Shaken real caster still lends.
        if !s.is_caster && !s.spell_accumulator { continue; }
        if !s.is_caster && state.shaken[u] { continue; }
        let d = geom::dist_in(&state.positions[ci], &state.positions[u]);
        let reach = if s.is_caster { CASTER_BOOST_AURA_IN } else { SPELL_ACCUMULATOR_REACH_IN };
        if d > reach {
            continue;
        }
        // "in line of sight of the caster's unit" (:4606): the caster's own
        // unit needs no check (the table's `cu != caster_unit` guard). Rules
        // 3.6 (D-SPELL-LOS) drops the sight line: the reach alone decides.
        if !rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36)
            && u != si && !state.attached[si].contains(&u) && !los[u] { continue; }
        found.push((u, d, state.casts[u]));
    }
    found.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));
    found.into_iter().map(|(u, _, t)| (u, t)).collect()
}

/// Rules-must-log for the boost/resist pool's reach from rules 3.6 on
/// (D-SPELL-LOS): the pool's token line names it; empty below the gate.
fn aura_pool_note(rules_epoch: u32) -> &'static str {
    if rule_on(rules_epoch, crate::acts::EPOCH_73_V36) { " (casters within 18\", no line of sight needed)" } else { "" }
}


/// The cast's own EV — the damage EV the core can compute for a damage
/// spell, the P3 modifier delta for a buff/debuff, 0.0 for everything else:
/// the table's `chosen_ev` (solo_controller.gd:4345), the one number BOTH
/// token economies price the attempt at (the boost values LANDING it through
/// `boost_value_of`, the interference PREVENTING it raw — the table hands
/// the same `chosen_ev` to both planners).
///
/// D-MAGIC step 2 — the modifier spells now have a term. The pairing
/// decision (the ONE deviation from the table, PR body in full): the
/// table's own buff pairing (`_modifier_value_on_attack(cand, effect,
/// false)`, solo_controller.gd:4530-4556) folds def_mod onto the NEAREST
/// ENEMY's defense, pricing a friendly def buff NEGATIVE — boost 0 by
/// construction. The core prices def_mod in its DEFENSE ROLE
/// (ai_spell.gd:353 "defense: the bearer defends"): the nearest opposing
/// unit's attack INTO the bearer, delta from the attacker's perspective,
/// negated for a buff — the brief's "EV delta of the modifier for the
/// caster's own side". The fold arithmetic itself is the byte-faithful
/// `spell_modifier_delta` port (clamp [2,6], int() truncation, the EV
/// chain, morale_mod -> 0).
pub(crate) fn cast_ev_of(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    entry: &Spell,
    ti: usize,
    rules_epoch: u32,
) -> f64 {
    if entry.effect_kind == "damage" {
        spell_damage_ev_of(entry, &ctx_of(&statics[state.roster.profile[ti]], state, ti), rules_epoch)
    } else {
        modifier_cast_ev_of(statics, state, si, entry, ti)
    }
}

/// D-MAGIC step 2 — the buff/debuff cast's EV, the table's `_spell_ev_for`
/// non-damage arms (solo_controller.gd:4496-4527) over the P3 primitive
/// `modifier_delta_of` (ai_spell.gd:255-304). Both ctxs ride
/// `ctx_live(..., CURRENT_RULES_EPOCH)` (the `volley_ev` pattern): the
/// search's EV is not replayed and a captured ledger is always empty, so
/// landed live buffs compose into the imagined fold.
fn modifier_cast_ev_of(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    entry: &Spell,
    ti: usize,
) -> f64 {
    let m = &entry.modifier;
    if !m.present {
        return 0.0;
    }
    // `int()` truncation (ai_spell.gd:269, :272); morale_mod has NO term in
    // the chain (ai_spell.gd:250-252) — a morale-only modifier prices 0.0.
    let hit = m.hit_mod as i64;
    let dm = m.def_mod as i64;
    // D-MAGIC step 4 — the MOVEMENT fields price the usage they move: the
    // absolute charge/shoot usage value of the unit that receives the
    // modifier (the bearer for a buff, the target for a debuff), with
    // minus without the spell's fields. A buff ADDS usage, a debuff
    // REMOVES it — both help the caster's side, so both legs price the
    // same absolute gain. `beneficiary == "attackers"` folds the whole
    // modifier onto the ACTIVATING unit's one attack (the table's
    // `_modifier_delta` verbatim) — no movement term there.
    let move_gain = if m.advance_in != 0.0 || m.rush_in != 0.0 || m.range_in != 0.0 {
        movement_cast_gain(statics, state, ti, m)
    } else {
        0.0
    };
    if hit == 0 && dm == 0 {
        return move_gain;
    }
    match entry.effect_kind.as_str() {
        "buff" => {
            // Buff value = the delta on the BEARER's own side (the table's
            // max-of-shooting-and-melee shape, `_modifier_value_on_attack`
            // :4530-4556): the hit_mod leg on the bearer's own next attack
            // (max of the two mode deltas, the table's maxf verbatim), the
            // def_mod leg in its DEFENSE ROLE (see `cast_ev_of`) — the max
            // runs over the BEARER'S GAIN there (the damage reduction per
            // enemy mode): maxf over the ATTACKER's deltas would pick the
            // empty melee leg's 0.0 and price every def buff 0.
            let bearer = ti;
            let Some(ne) = nearest_enemy(state, bearer) else { return 0.0; };
            let d = geom::dist_in(&state.positions[bearer], &state.positions[ne]);
            let hit_leg = if hit != 0 {
                let sh = modifier_delta_of(statics, state, bearer, ne, hit, 0, true, d, false);
                let ml = modifier_delta_of(statics, state, bearer, ne, hit, 0, false, 0.0, true);
                sh.max(ml)
            } else {
                0.0
            };
            let def_leg = if dm != 0 {
                let sh = modifier_delta_of(statics, state, ne, bearer, 0, dm, true, d, false);
                let ml = modifier_delta_of(statics, state, ne, bearer, 0, dm, false, 0.0, true);
                (-sh).max(-ml)
            } else {
                0.0
            };
            hit_leg + def_leg + move_gain
        }
        "debuff" => {
            if entry.beneficiary == "attackers" {
                // The table's `_modifier_delta(unit, cand, effect)` VERBATIM
                // (solo_controller.gd:4518-4527): the activating unit's own
                // attack into the target, the WHOLE modifier folded on ONE
                // pairing, ranged-if-in-range-else-melee (charging) — no max.
                let d = geom::dist_in(&state.positions[si], &state.positions[ti]);
                modifier_delta_auto(statics, state, si, ti, hit, dm, d)
            } else {
                // The penalty lands on the target's OWN attacks. D-MAGIC step
                // 2d = the table's step 2c (solo_controller.gd:4529-4552,
                // PR #1020) number for number. The HIT leg picks the mode by
                // BASELINE: max over the USABLE modes of (baseline EV into
                // our nearest unit minus the same-mode malus) — the old
                // `-(sh.max(ml))` was #1012's buff fold verbatim, and for a
                // debuff's negative deltas the maxf picks the mode that LOSES
                // LEAST while an unusable ranged mode's 0.0 masked the melee
                // leg. A def_mod debuff lands on the DEFENDER of that attack
                // (= our unit), so folding it into the target's attack priced
                // a good debuff NEGATIVE (the #1014 bug class) — it is priced
                // from OUR side (our nearest unit's attack INTO the target,
                // the target's defense worsened, sign = caster gain) and
                // SUMMED with the hit leg; the legs split the modifier.
                let Some(our) = nearest_enemy(state, ti) else { return 0.0; };
                let d = geom::dist_in(&state.positions[ti], &state.positions[our]);
                let hit_leg = if hit != 0 {
                    let sh = modifier_delta_usable_of(statics, state, ti, our, hit, 0, true, d)
                        .map(|v| -v);
                    let ml =
                        modifier_delta_usable_of(statics, state, ti, our, hit, 0, false, 0.0)
                            .map(|v| -v);
                    max_usable_delta([sh, ml])
                } else {
                    0.0
                };
                let def_leg = if dm != 0 {
                    let sh = modifier_delta_usable_of(statics, state, our, ti, 0, dm, true, d);
                    let ml = modifier_delta_usable_of(statics, state, our, ti, 0, dm, false, 0.0);
                    max_usable_delta([sh, ml])
                } else {
                    0.0
                };
                hit_leg + def_leg + move_gain
            }
        }
        _ => 0.0,
    }
}

/// The P3 fold primitive — `AiSpell.spell_modifier_delta` (ai_spell.gd:
/// 255-304) over the core's own EV chain: EV(with the ±hit / ±def fold) −
/// EV(without) over the SAME pairing, the ranged side at `dist_in` or the
/// melee side charging. The fold: `att.hit_mod += hit` (ai_ev.gd's
/// net-modifier composition, combat.rs `profile_ev`) and
/// `def2.defense = clamp(defense - dm, BEST_HIT_TARGET, UNMODIFIED_SIX)`
/// — the shielded_defense arithmetic, clamped [2,6], BASE ctx UNCLAMPED
/// (:272-275 clamps only the modified copy).
#[allow(clippy::too_many_arguments)]
fn modifier_delta_of(
    statics: &[UnitStatic],
    state: &State,
    att_i: usize,
    def_i: usize,
    hit: i64,
    dm: i64,
    ranged: bool,
    dist_in: f64,
    charging: bool,
) -> f64 {
    if hit == 0 && dm == 0 {
        return 0.0;
    }
    let us = &statics[state.roster.profile[att_i]];
    let ut = &statics[state.roster.profile[def_i]];
    let melee = !ranged;
    let att_base =
        ctx_live(ctx_of(us, state, att_i), statics, state, att_i, melee, CURRENT_RULES_EPOCH);
    let def_base =
        ctx_live(ctx_of(ut, state, def_i), statics, state, def_i, melee, CURRENT_RULES_EPOCH);
    let mut att2 = att_base;
    let mut def2 = def_base;
    if hit != 0 {
        att2.hit_mod += hit;
    }
    if dm != 0 {
        def2.defense = (def2.defense - dm).clamp(BEST_HIT_TARGET, UNMODIFIED_SIX);
    }
    let mut sc = Scratch::default();
    if ranged {
        profiles_of(us, state.alive[att_i], dist_in, &mut sc);
        shoot_ev(&us.shoot, &sc.keep, &sc.attacks, &att2, &def2, dist_in)
            - shoot_ev(&us.shoot, &sc.keep, &sc.attacks, &att_base, &def_base, dist_in)
    } else {
        melee_profiles_of(us, state.alive[att_i], &mut sc);
        // No pre-charge gap here (`dist_in` is the ranged side's, and the table's `_side_ev` hands none): blind.
        melee_ev(&us.melee, &sc.attacks, &att2, &def2, charging, 0.0)
            - melee_ev(&us.melee, &sc.attacks, &att_base, &def_base, charging, 0.0)
    }
}

/// `_modifier_delta`'s own side choice (:4522-4527): the ranged delta when
/// the attacker holds a profile in range at `dist_in`, else its melee swing
/// (charging). ONE call, not a max.
fn modifier_delta_auto(
    statics: &[UnitStatic],
    state: &State,
    att_i: usize,
    def_i: usize,
    hit: i64,
    dm: i64,
    dist_in: f64,
) -> f64 {
    let us = &statics[state.roster.profile[att_i]];
    let mut sc = Scratch::default();
    profiles_of(us, state.alive[att_i], dist_in, &mut sc);
    if !sc.keep.is_empty() {
        modifier_delta_of(statics, state, att_i, def_i, hit, dm, true, dist_in, false)
    } else {
        modifier_delta_of(statics, state, att_i, def_i, hit, dm, false, 0.0, true)
    }
}

/// The debuff legs' usable-mode gate (D-MAGIC step 2d = the table's step 2c,
/// solo_controller.gd:4630-4649): the mode's delta when the mode is USABLE —
/// a ranged mode holds a profile in range at `dist_in`, a melee mode has
/// strike reach ("Who Can Strike", `striking_models`) — `None` when it does
/// not. An unusable mode is not a mode: it must not enter the max (its 0.0
/// masked the melee leg on main, the CCW-only target priced -0.0).
#[allow(clippy::too_many_arguments)]
fn modifier_delta_usable_of(
    statics: &[UnitStatic],
    state: &State,
    att_i: usize,
    def_i: usize,
    hit: i64,
    dm: i64,
    ranged: bool,
    dist_in: f64,
) -> Option<f64> {
    let us = &statics[state.roster.profile[att_i]];
    let mut sc = Scratch::default();
    if ranged {
        profiles_of(us, state.alive[att_i], dist_in, &mut sc);
        if sc.keep.is_empty() {
            return None;
        }
    } else if crate::combat::striking_models(
        &state.positions[att_i],
        &state.positions[def_i],
        crate::acts::CURRENT_RULES_EPOCH,
    ) <= 0
    {
        // This AI spell-EV heuristic has no per-game `seams` in its call chain (unlike
        // `melee_parts` below); every recorded corpus has y = 0, so the height gate is a
        // no-op here regardless of which epoch is passed.
        return None;
    }
    Some(modifier_delta_of(statics, state, att_i, def_i, hit, dm, ranged, dist_in, !ranged))
}

/// The max over the legs' usable deltas (the table's `value == -INF` guard
/// verbatim, solo_controller.gd:4646); BOTH unusable is legitimately 0.0 — a
/// target that cannot attack us cannot be made worse.
fn max_usable_delta(legs: [Option<f64>; 2]) -> f64 {
    match legs {
        [None, None] => 0.0,
        [Some(a), None] | [None, Some(a)] => a,
        [Some(a), Some(b)] => a.max(b),
    }
}

/// Wave 6 (port-caster-boost) — the boost plan, pure (the spend happens in
/// the payment block): own leftover FIRST (solo_controller.gd:4336-4342),
/// then the helper pool; `plan_boost`'s marginal-EV calculus prices the
/// attempt (ai_spell.gd:328-339) at the table's `boost_value_of` value
/// (:4345-4349) — the damage EV the core can compute, the unpriced stand-in
/// for everything else. The draw mirrors `_draw_aura_tokens`' own-front
/// order. Returns (boost, own draw, helper draw); the caller folds the final
/// roll target and owns the frozen `EPOCH_48_CASTER_BOOST` gate.
// The rules epoch is threaded from the frozen seams, not held globally; the
// extra `casting_net` argument mirrors the table's own call shape
// (`plan_boost(..., priced_target)` from `_plan_member_cast`).
#[allow(clippy::too_many_arguments)]
pub(crate) fn plan_caster_boost(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    entry: &Spell,
    ti: usize,
    own: i64,
    helpers: &[(usize, i64)],
    rules_epoch: u32,
    casting_net: i64,
) -> (i64, i64, i64) {
    let own_left = (own - entry.threshold).max(0);
    let ev = cast_ev_of(statics, state, si, entry, ti, rules_epoch);
    let boost = plan_boost(
        boost_value_of(ev),
        own_left + helpers.iter().map(|(_, t)| *t).sum::<i64>(),
        casting_net,
    );
    let own_draw = boost.min(own_left);
    (boost, own_draw, boost - own_draw)
}

/// Wave 6 (port-caster-interference) — the INTERFERENCE pool, the boost
/// pool's opposing-side mirror (`_aura_casters(human_slot, unit, null)`,
/// solo_controller.gd:4378): every caster and `Spell Accumulator` battery of
/// the OPPOSING player holding tokens within the `Caster` rule's `aura_in`
/// (18") in line of sight of the caster's unit (:4606) — the battery on its
/// OWN 12" reach (:4565, :4604), a Shaken battery refused (NML-936,
/// :4596-4601), nearest-first (the table's own sort, :4609). No own-front
/// entry here: a caster never sits in the OPPOSING pool (the flipped player
/// check excludes its whole side). Gated on the frozen
/// `EPOCH_51_CASTER_INTERFERENCE`.
fn interference_pool(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    ci: usize,
    los: &[bool],
    seams: Seams,
) -> Vec<(usize, i64)> {
    if !rule_on(seams.rules_epoch, EPOCH_51_CASTER_INTERFERENCE) { return Vec::new(); }
    let pid = state.player[si];
    let mut found: Vec<(usize, f64, i64)> = Vec::new();
    for u in 0..state.units() {
        let s = &statics[state.roster.profile[u]];
        if u == ci || state.player[u] == pid || state.alive[u] <= 0 || state.casts[u] <= 0 {
            continue;
        }
        // casters and batteries only (:4594); NML-936 (:4596-4601) refuses
        // only the BATTERY's spending — a Shaken real caster still spends
        // its own tokens, the walk mirrors the table exactly there.
        if !s.is_caster && !s.spell_accumulator { continue; }
        if !s.is_caster && state.shaken[u] { continue; }
        let d = geom::dist_in(&state.positions[ci], &state.positions[u]);
        let reach = if s.is_caster { CASTER_BOOST_AURA_IN } else { SPELL_ACCUMULATOR_REACH_IN };
        if d > reach {
            continue;
        }
        // "in line of sight of the caster's unit" (:4606): the caster's own
        // unit needs no check (the table's `cu != caster_unit` guard). Rules
        // 3.6 (D-SPELL-LOS) drops the sight line: the reach alone decides.
        if !rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36)
            && u != si && !state.attached[si].contains(&u) && !los[u] { continue; }
        found.push((u, d, state.casts[u]));
    }
    found.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap_or(std::cmp::Ordering::Equal));
    found.into_iter().map(|(u, _, t)| (u, t)).collect()
}

/// S1-02 (GF/AoF v3.5.1 p.10): "Shaken units must stay idle, but may strike
/// back counting as fatigued" — from `EPOCH_65_MELEE_TRUTH` a Shaken unit's
/// melee ctx carries `fatigued` (unmodified 6s to hit). A Shaken unit never
/// charges, so on the charger's side the flag stays its own fatigue.
fn ctx_of_melee(us: &UnitStatic, state: &State, i: usize, rules_epoch: u32) -> Ctx {
    let mut c = ctx_of(us, state, i);
    // SHO-17 — the Guarded charge leg's shared 6" gate; 0.0 below the epoch keeps the old read.
    if rule_on(rules_epoch, EPOCH_73_V36) {
        c.guarded_charge_over_in = crate::combat::CHARGE_LONG_RANGE_IN;
    }
    c.fatigued = state.fatigued[i] || (rule_on(rules_epoch, EPOCH_65_MELEE_TRUTH) && state.shaken[i]);
    // MEL-11 (`EPOCH_73_V36`): a Fatigued unit rolls no Ravage. The tray and
    // the EV both read the rating off this ctx, so one zero gates both.
    if c.fatigued && rule_on(rules_epoch, crate::acts::EPOCH_73_V36) {
        c.ravage = 0;
    }
    c
}

/// Scratch buffers so a threat sweep allocates once per call, not per pair.
#[derive(Default, Clone)]
pub struct Scratch {
    pub keep: Vec<usize>,
    pub attacks: Vec<i64>,
    /// NML-1132: the FOLDED member profile list — the host's weapons followed by
    /// every alive attached hero's, filled only by `member_profiles_of` and only
    /// when the fold ran. EMPTY means "the unit's own slice is the answer", which
    /// is what `folded_slice` reads; every other filler clears it.
    pub fold: Vec<ShootProfile>,
    /// MEL-02e: `fold` is authoritative even when EMPTY (every melee profile was a spent
    /// Limited one), so `folded_slice` must not fall back to the unit's own set.
    pub fold_set: bool,
    /// Inventory C03 (`Seams::casualties_bearers_last`): `profiles_of` scales a special weapon's attacks by the
    /// living BEARERS (the table's order) instead of the whole unit's survivors. Carried here so no shared
    /// signature widens; the default (false) is today's pro-rata scaling for every caller that never sets it.
    pub bearers_last: bool,
    /// The caller's `Seams::rules_epoch`, carried so a member-level profile
    /// read can gate a wave-3 mark consumer (`acts::rule_on` off a struct the
    /// call already passes — no shared signature widened, the wave-3 rule).
    /// 0 (the `Default`) is pre-epoch-6: every existing caller keeps its
    /// reading exactly as it replays today.
    pub rules_epoch: u32,
    /// G4-C8a: the models that strike, set by `melee_parts` so `strike_phase` logs the count
    /// without measuring twice. Read only off a `melee_parts` product.
    pub strikers: i64,
    /// One-core P3 step 27: per profile index, the member's models with range and sight (`sighted_profiles_of`) for
    /// the hit line's "(n/m models sighted)" part. Filled only when `say_sight` is set (a tray with a feed), so the
    /// seeded path allocates nothing new.
    pub sighted: Vec<i64>,
    pub say_sight: bool,
    /// Step 42d: per profile index (with `sighted`), why a weapon its models see would fire nothing - the table's
    /// silent line (`scaled_attacks_report`'s "no living bearers" / "no attacks").
    pub silent: Vec<&'static str>,
    /// A moved shooter lost its Indirect sight waiver (SHO-01a): the table's "did not Hold" note, said once before the activation's volley.
    pub indirect_lost: bool,
}

/// `BattleSim._profiles_of(su, false, d)` battle_sim.gd:714-749 fused with the
/// distance gate of `AiShooting.profiles_in_range` (ai_shooting.gd:16-17): the
/// merged ranged set is precomputed per unit, so all that is left per call is
/// the range filter and the survivor scaling.
pub fn profiles_of(us: &UnitStatic, alive: i64, d: f64, sc: &mut Scratch) {
    sc.keep.clear();
    sc.attacks.clear();
    sc.fold.clear();
    sc.fold_set = false;
    for (i, p) in us.shoot.iter().enumerate() {
        if (p.range as f64) + p.reach_bonus_in < d {
            continue;
        }
        sc.keep.push(i);
        // FEAT PR 2 — the once-per-game bonus shot is its OWN single attack
        // that "never scales with the unit" (the melee fold's shape,
        // `melee_profiles_of`'s extra_attack_q leg): it skips the survivor
        // scaling.
        sc.attacks.push(if p.extra_attack_q > 0 {
            p.attacks
        } else {
            survivor_attacks(p, alive, us.model_count, sc.bearers_last, None)
        });
    }
}

/// Inventory C03 — one weapon's imagined attacks after casualties. Off: the pro-rata `effective_attacks`. On: the
/// table's own order (`bearer_scaled_attacks`, the special-weapon bearers fall LAST): a weapon carried by fewer
/// models than the unit fires `per-copy x min(copies, alive)`, the common weapon keeps the pro-rata ratio. Any
/// reach filter (`fire_in_range_only`) is applied AFTER this, on the bearers that are alive.
#[inline]
fn survivor_attacks(p: &ShootProfile, alive: i64, model_count: i64, bearers_last: bool, living: Option<i64>) -> i64 {
    if bearers_last {
        bearer_scaled_attacks(p, alive, model_count, alive, living)
    } else {
        effective_attacks(p.attacks, alive, model_count)
    }
}

/// Inventory C02 (GF/AoF v3.5.1 p.8: "All models in a unit with line of sight to the target, and that have a
/// weapon that is within range of it, may fire at it") — rescale the attacks `profiles_of` just filled so a
/// weapon counts only the models of `a_pos` whose OWN nearest distance to `b_pos` (centre measure, the same as
/// `geom::dist_in`; `shave` is the inches an advance closes first) is within that weapon's range. A bonus shot
/// (`extra_attack_q`) never scales with the unit. Callers reach this only with `fire_in_range_only` on.
/// `g` is finite (`max(0.0)` of a distance, never NaN), so `g <= range` equals `!(range < g)`. The
/// result is never above what `profiles_of` wrote (`models_in_reach <= alive`).
pub fn reach_rescale(us: &UnitStatic, alive: i64, a_pos: &[[f64; 3]], b_pos: &[[f64; 3]], shave: f64, sc: &mut Scratch) {
    let gaps: Vec<f64> = a_pos
        .iter()
        .map(|p| (geom::dist_in(std::slice::from_ref(p), b_pos) - shave).max(0.0))
        .collect();
    for (k, &i) in sc.keep.iter().enumerate() {
        let p = &us.shoot[i];
        if p.extra_attack_q > 0 {
            continue;
        }
        let n = (gaps.iter().filter(|&&g| g <= p.range as f64 + p.reach_bonus_in).count() as i64).min(alive);
        sc.attacks[k] = effective_attacks(p.attacks, n, us.model_count);
    }
}

/// `member_profiles_of` plus the C02 reach rescale, per FIRING member (host and joined heroes each count their
/// own models) against the target host and, with `hero_attach`, its joined heroes. Knob off = `member_profiles_of`
/// byte for byte.
#[allow(clippy::too_many_arguments)]
pub fn member_profiles_reach(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    ti: usize,
    d: f64,
    seams: Seams,
    sc: &mut Scratch,
) {
    member_profiles_of(statics, state, si, false, d, seams, sc);
    if !seams.fire_in_range_only {
        return;
    }
    let mut b_pos: Vec<[f64; 3]> = state.positions[ti].clone();
    if seams.hero_attach {
        for &h in &state.attached[ti] {
            b_pos.extend(state.positions[h].iter().copied());
        }
    }
    if sc.fold.is_empty() {
        let us = &statics[state.roster.profile[si]];
        reach_rescale(us, state.alive[si], &state.positions[si], &b_pos, 0.0, sc);
        return;
    }
    // Folded list: one entry per (living member, weapon) in member order, `keep` indexes into it.
    let mut idx = 0usize;
    for &mi in std::iter::once(&si).chain(state.attached[si].iter()) {
        if state.alive[mi] <= 0 {
            continue;
        }
        let um = &statics[state.roster.profile[mi]];
        let mut one = Scratch {
            keep: (0..um.shoot.len()).collect(),
            attacks: vec![0; um.shoot.len()],
            ..Default::default()
        };
        reach_rescale(um, state.alive[mi], &state.positions[mi], &b_pos, 0.0, &mut one);
        for (w, p) in um.shoot.iter().enumerate() {
            if let Some(k) = sc.keep.iter().position(|&x| x == idx) {
                if p.extra_attack_q <= 0 {
                    sc.attacks[k] = one.attacks[w];
                }
            }
            idx += 1;
        }
    }
}

/// `BattleSim._profiles_of(su, true)` battle_sim.gd:714-749, MELEE half: every
/// melee profile strikes (no range gate), each with its survivor-scaled attack
/// count. Fills `sc.attacks` index-parallel to `us.melee`.
pub fn melee_profiles_of(us: &UnitStatic, alive: i64, sc: &mut Scratch) {
    sc.attacks.clear();
    sc.fold.clear();
    sc.fold_set = false;
    for p in &us.melee {
        // Wave 4 follow-up (port-takedown-strike) — the once-per-game bonus
        // group is its OWN single attack that "never scales with the unit"
        // (main.gd:16760-16761), so it skips the survivor scaling.
        if p.extra_attack_q > 0 {
            sc.attacks.push(p.attacks);
            continue;
        }
        sc.attacks.push(effective_attacks(p.attacks, alive, us.model_count));
    }
}

/// MEL-PAR-F5 — the table's `SoloController.alive_bearers_of`: how many entries naming `weapon_name` the
/// LIVING models' kits of `unit` hold (duplicates count, like the table's array). None when the state carries
/// no kits aligned one per living model (no record key, a hand-built fixture, `kits_drop`): the caller keeps
/// its pro-rata path. Shared with the shooting twin. 42d: Some(-1), the table's own -1, when no living kit names
/// any weapon - the unit carries no per-model loadout, and the table keeps the unit's ratio (not zero bearers).
pub(crate) fn living_bearers(state: &State, unit: usize, weapon_name: &str) -> Option<i64> {
    let kits = state.kits.get(unit).filter(|k| !k.is_empty() && k.len() as i64 == state.alive[unit])?;
    if kits.iter().all(|k| k.weapons.is_empty()) {
        return Some(-1);
    }
    let names = state.kit_names.get(unit)?;
    let named = |w: &&u16| names.get(**w as usize).is_some_and(|n| n == weapon_name);
    Some(kits.iter().flat_map(|k| k.weapons.iter()).filter(named).count() as i64)
}

/// Rules 3.6 (`EPOCH_73_V36`) — the first living model of `unit` whose kit carries `weapon`,
/// the table's `_solo_hazardous_bearer`; None when the state carries no aligned kits (the
/// unit-level fallback the table takes for a pooled regiment or an older save).
fn hazardous_bearer(state: &State, unit: usize, weapon: &str) -> Option<usize> {
    let kits = state.kits.get(unit).filter(|k| !k.is_empty() && k.len() as i64 == state.alive[unit])?;
    let names = state.kit_names.get(unit)?;
    (0..kits.len()).find(|&i| kits[i].weapons.iter().any(|&w| names.get(w as usize).is_some_and(|n| n == weapon)))
}

/// Rules 3.6 (`EPOCH_73_V36`) — Hazardous self-wounds land on the BEARER model, X
/// (`max(Blast, Deadly, 1)`) per unmodified 1, capped at the model (no carry-over); the next
/// 1 goes to the next living bearer. Without kits the unit takes them, as the table's fallback
/// does. Returns the tally the table keeps (`ones * X`) for the melee-loser comparison, and
/// writes the rule's own battle-log line (main.gd `_solo_hazardous_bearer_wounds`).
#[allow(clippy::too_many_arguments)]
fn hazardous_self_wounds(
    statics: &[UnitStatic], state: &mut State, unit: usize,
    weapon: &str, ones: i64, x: i64, seams: Seams, tray: &mut Tray, shot: &mut ShootResult, mark: &mut Option<(usize, usize)>,
) -> i64 {
    if ones <= 0 { return 0; }
    let name = statics[state.roster.profile[unit]].name.clone();
    for _ in 0..ones {
        match hazardous_bearer(state, unit, weapon) {
            Some(i) => {
                let slot = if tray.feed().is_some() {
                    let dead = tray.dead_slots(unit);
                    (0..).filter(|s| !dead.contains(s)).nth(i).unwrap_or(i)
                } else {
                    i
                };
                let at = state.positions[unit][i];
                let take = x.min(state.wounds[unit][i]);
                state.wounds[unit][i] -= take;
                let killed = state.wounds[unit][i] <= 0;
                let wounds_left = state.wounds[unit][i].max(0);
                shot.log.push(format!(
                    "Hazardous: {} model {} takes {} wound{} ({})",
                    name, i + 1, take, if take == 1 { "" } else { "s" }, weapon));
                let bd = if x > 1 { format!("Blast/Deadly {x}, ") } else { String::new() };
                say_hazard(tray, mark, shot, LogLine {
                    rule: "hazardous", category: Category::Combat, side: state.player[unit], detail: None,
                    text: format!("Hazardous: {name} model {} takes {take} wound{} ({bd}{weapon})", slot + 1, if take == 1 { "" } else { "s" }),
                });
                if killed {
                    if state.positions[unit].len() == 1 { drop_carried(state, unit); }
                    state.wounds[unit].remove(i);
                    remove_position_or_log(state, unit, i, "hazardous_self");
                    state.kit_remove(unit, i);
                    if i < state.radii[unit].len() { Rc::make_mut(&mut state.radii)[unit].remove(i); }
                    state.alive[unit] = state.positions[unit].len() as i64;
                    let (alive, total) = std::iter::once(unit).chain(state.attached[unit].iter().copied())
                        .fold((0, 0), |(a, t), u| (a + state.alive[u], t + statics[state.roster.profile[u]].model_count));
                    let loss = if alive == 0 {
                        format!("{name} destroyed")
                    } else {
                        format!("{name} loses a model ({alive}/{total})")
                    };
                    let line = LogLine { rule: "hazardous", category: Category::Combat, side: state.player[unit], text: loss, detail: None };
                    if mark.is_some() { say_hazard(tray, mark, shot, line); } else { tray.say_wounds(|| line); }
                }
                tray.land(|| Landing {
                    unit,
                    models: vec![LandedModel { at, slot, wounds_left, dead: killed }],
                    loss_line: true,
                    moved_to: Vec::new(),
                });
            }
            None => {
                let line = format!(
                    "Hazardous: {} has no bearer on record — the unit takes {} wound{} ({})",
                    name, x, if x == 1 { "" } else { "s" }, weapon);
                shot.log.push(line.clone());
                tray.say(|| LogLine {
                    rule: "hazardous", category: Category::Combat, side: state.player[unit], text: line, detail: None,
                });
                let before = chain_snapshot(state, unit, tray);
                land_wounds_with(state, unit, x, seams.tray_exact, seams.rules_epoch);
                land_chain_report(statics, state, tray, unit, before);
            }
        }
    }
    ones * x
}

/// One Hazardous line at the weapon's mark (the table wounds the firer right after the hit roll, ahead of the "fires" line), else at the end.
/// The marks behind it (the later weapons' Hazardous and the inline Takedown / Deadly landings) move down by the line.
fn say_hazard(tray: &mut Tray, at: &mut Option<(usize, usize)>, shot: &mut ShootResult, line: LogLine) {
    let Some(a) = at.as_mut() else { return tray.say(|| line) };
    tray.say_at(*a, || line);
    let later = shot.hazardous_self.iter_mut().filter_map(|e| e.4.as_mut()).chain(shot.takedown_marks.iter_mut()).chain(shot.deadly_marks.iter_mut());
    later.filter(|m| m.0 >= a.0).for_each(|m| m.0 += 1);
    a.0 += 1;
}

/// Land a result's Hazardous entries on the member that rolled them (matched by its name, the
/// dice `Roll::owner`) and drop the `hazardous` divergence flag: from `EPOCH_73_V36` the branch
/// IS ported, so the tray tree must no longer decline the activation for it.
fn land_hazardous_self(
    statics: &[UnitStatic], state: &mut State, members: &[usize],
    seams: Seams, tray: &mut Tray, shot: &mut ShootResult,
) -> i64 {
    if !rule_on(seams.rules_epoch, EPOCH_73_V36) { return 0; }
    let mut tally = 0;
    for i in 0..shot.hazardous_self.len() {
        let (owner, weapon, ones, x, mut at) = shot.hazardous_self[i].clone();
        if let Some(&unit) = members.iter().find(|&&m| statics[state.roster.profile[m]].name == owner) {
            tally += hazardous_self_wounds(statics, state, unit, &weapon, ones, x, seams, tray, shot, &mut at);
        }
    }
    shot.hazardous_self.clear();
    shot.unported.retain(|u| *u != "hazardous");
    tally
}

/// MEL-PAR-F5 (`EPOCH_73_V36`) — a dead model's melee weapon is gone. The table (`_solo_attack_groups`) rolls a
/// weapon carried by fewer models than the unit holds as `per-copy x min(living bearers, strikers)`, also with
/// partial contact (G4-C8a: it never learns WHICH models touch either, and `count` is a real count since the
/// base-edge measure). None = keep the pro-rata number (gate off, a bonus attack, a weapon every model
/// carries, or no aligned kits).
fn melee_bearer_attacks(p: &ShootProfile, model_count: i64, state: &State, unit: usize, count: i64, rules_epoch: u32) -> Option<i64> {
    let copies = p.count.max(1);
    if !rule_on(rules_epoch, crate::acts::EPOCH_73_V36) || p.extra_attack_q > 0 || copies >= model_count {
        return None;
    }
    living_bearers(state, unit, &p.name).filter(|&b| b >= 0).map(|b| (p.attacks / copies).max(0) * b.min(count))
}

/// `melee_bearer_attacks` over a `melee_profiles_of` fill (`sc.attacks` still index-parallel to `us.melee`).
fn melee_bearers_rescale(us: &UnitStatic, state: &State, unit: usize, count: i64, rules_epoch: u32, sc: &mut Scratch) {
    for (a, p) in sc.attacks.iter_mut().zip(&us.melee) {
        if let Some(n) = melee_bearer_attacks(p, us.model_count, state, unit, count, rules_epoch) {
            *a = n;
        }
    }
}

/// SHO-PAR-F4 (`EPOCH_73_V36`) — a dead model's ranged weapon is gone. The table (`scaled_attacks_report`) counts a
/// weapon carried by fewer models than the unit holds off the LIVING models' kits; the core guessed that the
/// bearers fall last. None = keep that guess (gate off, a weapon every model carries, or no aligned kits).
fn shot_bearers(p: &ShootProfile, model_count: i64, state: &State, unit: usize, rules_epoch: u32) -> Option<i64> {
    if !rule_on(rules_epoch, crate::acts::EPOCH_73_V36) || p.count.max(1) >= model_count {
        return None;
    }
    living_bearers(state, unit, &p.name)
}

/// `shot_bearers` over a `profiles_of` fill (`sc.keep` indexes `us.shoot`, `sc.attacks` parallel to it): the plain
/// legs call `profiles_of` with no state, so the living bearers are applied here. Knob off (`bearers_last`) = pro rata.
fn shoot_bearers_rescale(us: &UnitStatic, state: &State, unit: usize, rules_epoch: u32, sc: &mut Scratch) {
    let mut share = BearerShare::new(&us.shoot, &sc.keep, rules_epoch);
    for (a, &i) in sc.attacks.iter_mut().zip(&sc.keep) {
        let p = &us.shoot[i];
        let living = if sc.bearers_last && p.extra_attack_q <= 0 { shot_bearers(p, us.model_count, state, unit, rules_epoch) } else { None };
        if living.is_some() {
            *a = bearer_scaled_attacks(p, state.alive[unit], us.model_count, state.alive[unit], living);
        }
        if let Some(s) = &mut share {
            *a = s.dice(p, *a, living, state.alive[unit], &us.name);
        }
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

/// MEL-02e — the TABLE's `filter_limited` on an EV set (solo_controller.gd:9284): a
/// Limited profile the unit already spent brings no strikes, so it is dropped before
/// pricing. Gated at `EPOCH_73_V36`; before it Limited never spanned melee, so the 72
/// leg is byte-exact. Borrows the caller's slices when nothing is spent.
pub(crate) fn ev_melee_set<'a>(
    profiles: &'a [ShootProfile],
    attacks: &'a [i64],
    used: &[String],
    rules_epoch: u32,
) -> (Cow<'a, [ShootProfile]>, Cow<'a, [i64]>) {
    let spent = |p: &ShootProfile| p.limited && used.iter().any(|n| n == &p.name);
    if !rule_on(rules_epoch, EPOCH_73_V36) || !profiles.iter().any(spent) {
        return (Cow::Borrowed(profiles), Cow::Borrowed(attacks));
    }
    let keep: Vec<usize> = profiles.iter().enumerate().filter(|(_, p)| !spent(p)).map(|(i, _)| i).collect();
    (
        Cow::Owned(keep.iter().map(|&k| profiles[k].clone()).collect()),
        Cow::Owned(keep.iter().map(|&k| attacks[k]).collect()),
    )
}

/// `SoloController.mark_limited_used` (solo_controller.gd:7700-7708,
/// main.gd:3207-3208): called AFTER the dice actually rolled, win or lose —
/// every Limited profile that fired is spent for the rest of the game.
fn mark_spent_limited(profiles: &[ShootProfile], keep: &[usize], ledger: &mut Rc<Vec<Vec<String>>>, unit: usize) {
    for &i in keep {
        let p = &profiles[i];
        if p.limited && !ledger[unit].iter().any(|n| n == &p.name) {
            Rc::make_mut(ledger)[unit].push(p.name.clone());
        }
    }
}

/// FEAT PR 2 — the Takedown Shot latch at the volley's parts seam, the
/// #827 latch's second reader: a bearer whose `feats_used` already names
/// the rule brings no synthetic shot (the replayed spend — the io fold's
/// key closes the latch across acts); an unspent bearer spends it on the
/// FIRST volley while unspent — policy (a) auto, exactly the table's group
/// build (main.gd:17021-17024). The dice fold logs the fired shot (the
/// `extra_attack_q` leg); this seam only moves the ledger. Frozen-gated —
/// a record below `EPOCH_7_TABLE_RULES` never reaches the latch here.
/// The stamp is DEFERRED: the caller collects the spenders and stamps them
/// after the parts loop (the member iterator holds the state's borrow).
fn takedown_shot_gate(
    statics: &[UnitStatic],
    state: &State,
    mi: usize,
    msc: &mut Scratch,
    rules_epoch: u32,
    spent: &mut Vec<usize>,
) {
    if !rule_on(rules_epoch, EPOCH_7_TABLE_RULES) {
        return;
    }
    let shoot = &statics[state.roster.profile[mi]].shoot;
    let Some(pi) = shoot
        .iter()
        .position(|p| p.extra_attack_q > 0 && p.name == "Takedown Shot")
    else {
        return;
    };
    let Some(k) = msc.keep.iter().position(|&i| i == pi) else {
        return;
    };
    if state.feats_used[mi].iter().any(|n| n == "Takedown Shot") {
        msc.keep.remove(k);
        msc.attacks.remove(k);
    } else {
        // EPOCH_96_PARITY_BATCH: each living model of the bearer makes its own extra attack.
        if rule_on(rules_epoch, crate::acts::EPOCH_96_PARITY_BATCH) {
            msc.attacks[k] = shoot[pi].attacks * state.alive[mi].max(1);
        }
        spent.push(mi);
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
            melee_bearers_rescale(us, state, si, state.alive[si], seams.rules_epoch, sc);
            let (profiles, attacks) = ev_melee_set(&us.melee, &sc.attacks, &state.limited_used[si], seams.rules_epoch);
            if let Cow::Owned(profiles) = profiles {
                sc.fold = profiles;
                sc.attacks = attacks.into_owned();
                sc.fold_set = true;
            }
        } else {
            sc.bearers_last = seams.casualties_bearers_last;
            profiles_of(us, state.alive[si], d, sc);
            shoot_bearers_rescale(us, state, si, seams.rules_epoch, sc);
            // Limited: the table's `filter_limited` on the EV set — a spent weapon is priced no more than it is rolled.
            if rule_on(seams.rules_epoch, EPOCH_73_V36) {
                drop_spent_limited(&us.shoot, &state.limited_used[si], sc);
            }
        }
        return;
    }
    sc.keep.clear();
    sc.attacks.clear();
    sc.fold.clear();
    sc.fold_set = melee;
    for &mi in std::iter::once(&si).chain(state.attached[si].iter()) {
        if state.alive[mi] <= 0 {
            continue; // main.gd:2915 — a member with no living model brings no shot
        }
        let um = &statics[state.roster.profile[mi]];
        let set = if melee { &um.melee } else { &um.shoot };
        for p in set {
            // MEL-02e: a Limited profile the member already spent brings no strikes, so it
            // leaves the EV set from `EPOCH_73_V36` (the table's `filter_limited`). G4-H-LIM: a
            // spent SHOOTING profile stays in the folded list (the reach rescale indexes it) but
            // is never kept, so it is priced no more than it is rolled.
            let spent = rule_on(seams.rules_epoch, EPOCH_73_V36)
                && p.limited && state.limited_used[mi].iter().any(|n| n == &p.name);
            if melee && spent {
                continue;
            }
            // FEAT PR 2 — the ranged bonus shot never scales with the unit
            // (`profiles_of`'s extra_attack_q leg); the EV layer prices the
            // same single die the tray fires (the spent latch stays priced —
            // this row is about Limited, not the Takedown latch).
            let a = if !melee && p.extra_attack_q > 0 {
                p.attacks
            } else if !melee {
                survivor_attacks(p, state.alive[mi], um.model_count, seams.casualties_bearers_last, shot_bearers(p, um.model_count, state, mi, seams.rules_epoch))
            } else {
                melee_bearer_attacks(p, um.model_count, state, mi, state.alive[mi], seams.rules_epoch)
                    .unwrap_or_else(|| effective_attacks(p.attacks, state.alive[mi], um.model_count))
            };
            // MELEE has no range gate and `melee_ev` no `keep`, so its `attacks` must
            // stay parallel to the whole list; SHOOTING keeps `profiles_of`'s filter
            // and indexes the folded list through `keep`.
            if melee {
                sc.attacks.push(a);
            } else if (p.range as f64) + p.reach_bonus_in.max(granted_reach(um, state, mi).0) >= d && !spent {
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
    if sc.fold.is_empty() && !sc.fold_set {
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
    if seams.range_by_base_edge {
        let mut best = f64::INFINITY;
        let hosts = |u: usize| -> Vec<usize> {
            let mut v = vec![u];
            if seams.hero_attach {
                v.extend(state.attached[u].iter().copied());
            }
            v
        };
        for a in hosts(si) {
            for b in hosts(ti) {
                best = best.min(range_gap_in(state, &state.positions[a], a, b));
            }
        }
        return best;
    }
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
/// loadout. Without `living` this port assumes the special weapons' bearers are
/// the last to fall — `min(copies, alive)`. Measured on `~/selfplay_out/qbe_ref`:
/// that reproduces the recorded `attacks` on 919 of the 1052 shots that take this
/// path (and the flat path, 1065 shots, needs no bearer count). SHO-PAR-F4: from
/// `EPOCH_73_V36` the caller passes `living`, the count off the recorded kits
/// (`shot_bearers`); zero living bearers fire nothing, like the table's silent
/// "no living bearers" branch.
fn bearer_scaled_attacks(p: &ShootProfile, alive: i64, model_count: i64, sighted: i64, living: Option<i64>) -> i64 {
    let copies = p.count.max(1);
    if copies < model_count && living != Some(-1) {   // 42d: -1 = no per-model loadout, the table's ratio below
        let bearers = living.unwrap_or_else(|| copies.min(alive));
        return (p.attacks / copies).max(0) * bearers.min(sighted);
    }
    effective_attacks(p.attacks, sighted, model_count)
}

/// T-DUP-WEAPON-BEARERS (`EPOCH_89_SHARED_BEARERS`) — a unit that lists one weapon twice (two profiles of one
/// name, same attacks per copy: the Jesters' Atom Pistol x8 plain + x2 AP(1)) fires ONE die per sighted living
/// bearer in total, not per entry. `living_bearers` keys the kits by NAME, so both entries read every bearer; the
/// table splits them in order (main.gd:5262-5274, the key at main.gd:5091-5094): each entry rolls for its own
/// copies out of what the earlier entries of the same name and per-copy attacks left. Below the epoch the by-name
/// count stays, so recorded games replay unchanged.
#[allow(clippy::type_complexity)]
struct BearerShare<'a>(Vec<(&'a str, i64, i64, i64)>); // name, per-copy attacks, entries, guns taken

impl<'a> BearerShare<'a> {
    /// None when the gate is off or no weapon is listed twice among the kept entries.
    fn new(profiles: &'a [ShootProfile], keep: &[usize], epoch: u32) -> Option<Self> {
        if !rule_on(epoch, EPOCH_89_SHARED_BEARERS) {
            return None;
        }
        let mut v: Vec<(&str, i64, i64, i64)> = Vec::new();
        for &i in keep {
            let p = &profiles[i];
            if p.extra_attack_q > 0 {
                continue;
            }
            let k = (p.name.as_str(), (p.attacks / p.count.max(1)).max(0));
            match v.iter_mut().find(|c| (c.0, c.1) == k) {
                Some(c) => c.2 += 1,
                None => v.push((k.0, k.1, 1, 0)),
            }
        }
        v.iter().any(|c| c.2 > 1).then_some(Self(v))
    }

    /// The entry's dice after the share: `base` is its by-name count, `seen` its sighted models.
    fn dice(&mut self, p: &'a ShootProfile, base: i64, living: Option<i64>, seen: i64, owner: &str) -> i64 {
        let Some(b) = living.filter(|&b| b >= 0) else { return base };
        if base <= 0 || p.extra_attack_q > 0 {
            return base;
        }
        let pc = (p.attacks / p.count.max(1)).max(0);
        let Some(c) = self.0.iter_mut().find(|c| c.0 == p.name.as_str() && c.1 == pc && c.2 > 1) else { return base };
        let guns = (b.min(seen) - c.3).min(p.count.max(1)).max(0);
        c.3 += guns;
        let n = guns * pc.max(1);
        if n != base {
            trace_rule("volley", "Shared Bearers", &format!(
                "{owner}: {} is listed {} times — its {b} bearers fire once, this entry rolls for {guns} of them",
                p.name, c.2));
        }
        n
    }
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
    held: bool,
    sc: &mut Scratch,
) {
    sc.keep.clear();
    sc.attacks.clear();
    sc.sighted.clear();
    sc.silent.clear();
    if sc.say_sight {
        sc.sighted.resize(us.shoot.len(), state.alive[mi]);
        sc.silent.resize(us.shoot.len(), "");
    }
    let blockers = sight::blockers_of(state, mi, ti, sc.rules_epoch);
    let def = &statics[state.roster.profile[ti]].ctx;
    // WAVE 3 MARK CONSUMERS (`acts::rule_on`, frozen at `EPOCH_6_TABLE_RULES`):
    // the two enemy-side grant names the pre-attack pick already records on
    // the marked unit (main.gd:16534, `beneficiary: "attackers"`) reach the
    // volley here, at the same per-weapon sight/range seam a weapon's own
    // Indirect flag rides. A record stamped below epoch 6 keeps today's
    // inert reading — the grant lands on the ledger but no resolver reads it.
    let epoch6 = rule_on(sc.rules_epoch, EPOCH_6_TABLE_RULES);
    let mark_indirect = epoch6 && mods::granted_vs(state, ti, "Indirect");
    // EPOCH_94_PARITY_BATCH: an Indirect in the shooter's own store waives the sight test of every weapon (`_solo_shot_eligibility`).
    let own_indirect = rule_on(sc.rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) && mods::granted_own_indirect(state, mi);
    let mark_range = if epoch6 && mods::granted_vs(state, ti, "+6\" shooting range") {
        INCREASED_SHOOTING_RANGE_MARK_IN
    } else {
        0.0
    };
    let granted = granted_reach(us, state, mi).0;
    let mut share = None;
    if rule_on(sc.rules_epoch, EPOCH_89_SHARED_BEARERS) {
        let keep_pre: Vec<usize> = us.shoot.iter().enumerate()
            .filter(|(_, p)| (p.range as f64) + p.reach_bonus_in.max(granted) + mark_range >= d)
            .map(|(i, _)| i).collect();
        share = BearerShare::new(&us.shoot, &keep_pre, sc.rules_epoch);
    }
    for (i, p) in us.shoot.iter().enumerate() {
        let bonus = p.reach_bonus_in.max(granted);
        if (p.range as f64) + bonus + mark_range < d {
            continue;
        }
        sc.keep.push(i);
        let reach = sight_reach_in(p.range as f64 + bonus + mark_range, state.aircraft[ti], def);
        // Indirect (GF v3.5.1) "may target enemies that are not in line of
        // sight as if in line of sight": the range gate stays, the sight test
        // goes (main.gd:4136-4138).
        let lost = p.indirect_los_needs_hold && !held; // Rules 3.6 (SHO-01a): the waiver needs Hold
        let seen = sight::sighted_count(state, zones, &blockers, mi, ti, reach,
            (p.indirect && p.indirect_ignores_los.unwrap_or(true) && !lost) || mark_indirect || own_indirect,
            rule_on(sc.rules_epoch, EPOCH_66_DISTANCE_TRUTH), sc.rules_epoch);
        if let Some(n) = sc.sighted.get_mut(i) {
            *n = seen;
        }
        if lost && !mark_indirect && !own_indirect {
            sc.indirect_lost |= !p.indirect_alias; // the table's note asks the weapons' own Indirect, not the unit-level rule's stamp
            trace_rule("volley", "Indirect",
                &format!("{} did not Hold: {} needs line of sight", statics[state.roster.profile[mi]].name, p.name));
        }
        // Rules-must-log: the mark fires only where it changes the volley.
        if mark_indirect && !p.indirect && seen > 0 {
            trace_rule("volley", "Indirect Mark",
                &format!("{} fires at {} without line of sight", statics[state.roster.profile[mi]].name, statics[state.roster.profile[ti]].name));
        }
        if p.reach_bonus_in > 0.0 && (p.range as f64) < d {
            trace_rule("volley", &p.reach_bonus_rule,
                &format!("{} gains +{:.0}\" reach on {}", statics[state.roster.profile[mi]].name, p.reach_bonus_in, statics[state.roster.profile[ti]].name));
        }
        if mark_range > 0.0 && (p.range as f64) < d {
            trace_rule("volley", "Increased Shooting Range Mark",
                &format!("{} gains +{mark_range:.0}\" reach on {}", statics[state.roster.profile[mi]].name, statics[state.roster.profile[ti]].name));
        }
        let living = if p.extra_attack_q > 0 { None } else { shot_bearers(p, us.model_count, state, mi, sc.rules_epoch) };
        if let Some(why) = sc.silent.get_mut(i) {
            *why = if living == Some(0) { "no living bearers" } else { "no attacks" };
        }
        let base = if p.extra_attack_q > 0 { p.attacks } else { bearer_scaled_attacks(p, state.alive[mi], us.model_count, seen, living) };
        let n = match &mut share {
            Some(s) => s.dice(p, base, living, seen, &statics[state.roster.profile[mi]].name),
            None => base,
        };
        if n <= 0 && base > 0 {
            if let Some(why) = sc.silent.get_mut(i) { *why = "its bearers already fire another entry of it"; }
        }
        sc.attacks.push(n);
    }
}

/// The destroyed side loses from melee-truth epoch 65, regardless of Fear or
/// wound score. A mutual wipe leaves nobody to test. Earlier records keep the
/// score-only verdict they were played under.
fn melee_loser(state: &State, si: usize, ti: usize, score_su: i64, score_tu: i64, seams: Seams) -> Option<usize> {
    if rule_on(seams.rules_epoch, EPOCH_65_MELEE_TRUTH) {
        match (morale_side_alive(state, si, seams), morale_side_alive(state, ti, seams)) {
            (false, false) => return None,
            (false, true) => return Some(si),
            (true, false) => return Some(ti),
            (true, true) => {}
        }
    }
    if score_su == score_tu { None } else { Some(if score_su > score_tu { ti } else { si }) }
}

/// AI-06 (SHO-15b, `EPOCH_73_V36`): a Scourge striker's expected phantom wounds — the
/// Shred-vs-plain EV gap is `hits * SIX_P`, each such 1 worth `SCOURGE_PHANTOM_WOUNDS`.
#[allow(clippy::too_many_arguments)]
fn scourge_phantom_ev(
    profiles: &[ShootProfile], keep: Option<&[usize]>, attacks: &[i64], att: &Ctx,
    def: &Ctx, dist_in: f64, charging: bool, rules_epoch: u32,
) -> f64 {
    if !rule_on(rules_epoch, EPOCH_73_V36) {
        return 0.0;
    }
    let def = Ctx { regeneration: false, ..*def };
    let mut total = 0.0;
    let add = |pi: usize, a: i64, total: &mut f64| {
        let p = &profiles[pi];
        if !p.rules.iter().any(|r| r.trim() == "Scourge") {
            return;
        }
        let (mut plain, mut probe) = (p.clone(), p.clone());
        plain.shred = false;
        probe.shred = true;
        *total += crate::combat::profile_ev(&probe, a, att, &def, dist_in, charging)
            - crate::combat::profile_ev(&plain, a, att, &def, dist_in, charging);
    };
    match keep {
        Some(k) => k.iter().enumerate().for_each(|(j, &pi)| add(pi, attacks[j], &mut total)),
        None => (0..profiles.len()).for_each(|j| add(j, attacks[j], &mut total)),
    }
    total * crate::dice::SCOURGE_PHANTOM_WOUNDS as f64
}

/// `BattleSim._expected_melee_morale` battle_sim.gd:1111-1125 — the loser
/// tests only while alive; a fail at or below half is a
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
///
/// MEL-10e (`EPOCH_73_V36`) — the estimate reads the same TAKEN tally the table
/// does: each side's score is what its ENEMY took (the enemy's strikes plus the
/// enemy's Fear), and `self_wounds` is what the charger's own move cost it. A tie
/// tests nobody; below 73 the side that dealt fewer still loses and self-wounds
/// are ignored. `self_wounds` is 0 on the expected-value path today (it rolls no
/// Dangerous test); the term keeps the estimate and the table's twin in step.
#[allow(clippy::too_many_arguments)]
fn expected_melee_morale(
    state: &mut State,
    statics: &[UnitStatic],
    si: usize,
    su_before: i64,
    ti: usize,
    tu_before: i64,
    self_wounds: i64,
    phantom_on_su: f64,
    phantom_on_tu: f64,
    seams: Seams,
) {
    let taken_by_su = su_before - wounds_left(state, si) + (phantom_on_su.round() as i64);
    let taken_by_tu = tu_before - wounds_left(state, ti) + (phantom_on_tu.round() as i64);
    let (score_su, score_tu) = if rule_on(seams.rules_epoch, EPOCH_73_V36) {
        // 73: the loser TOOK more. Fear(X) rides the ENEMY's tally, and the
        // charger's own charge-move wounds count as taken by it.
        let su_taken = taken_by_su + self_wounds.max(0);
        (
            taken_by_tu + chain_fear(statics, state, si, seams),
            su_taken + chain_fear(statics, state, ti, seams),
        )
    } else {
        // Below 73: the side that dealt fewer loses; self-wounds never count.
        (
            taken_by_tu + chain_fear(statics, state, si, seams),
            taken_by_su + chain_fear(statics, state, ti, seams),
        )
    };
    let Some(li) = melee_loser(state, si, ti, score_su, score_tu, seams) else { return };
    let ul = &statics[state.roster.profile[li]];
    if !morale_side_alive(state, li, seams) || !morale_fails_expected(state, statics, li, seams) {
        return;
    }
    if below_half(state, statics, ul, li, seams) {
        drop_carried(state, li);
        state.wounds[li].clear();
        state.positions[li].clear();
        Rc::make_mut(&mut state.radii)[li].clear();
        state.kits_drop(li);
        state.alive[li] = 0;
    } else {
        state.shaken[li] = true;
        drop_carried(state, li);
    }
}

// --------------------------- D1-B5a: the melee sub-phases on the tray ---

/// "Who Can Strike" at `EPOCH_73_V36`, the twin of `SoloController.striking_models_for`
/// (solo_controller.gd:10484): the member's models whose base EDGE lies within the epoch's reach
/// (3" across, 3" up) of ANY base edge of the target host or its joined heroes, measured through the
/// recorded radii and base shapes. No enemy model on hand: every model strikes, like the table.
fn striking_models_edge(state: &State, mi: usize, ti: usize, rules_epoch: u32) -> i64 {
    let (reach_in, vertical_in) = crate::combat::melee_reach_in(rules_epoch);
    let foes = || std::iter::once(ti).chain(state.attached[ti].iter().copied()).filter(|&e| state.alive[e] > 0);
    if foes().next().is_none() {
        return state.positions[mi].len() as i64;
    }
    // A hand-built roster may map a unit to no profile: round then, like an unrecorded base.
    let shape = |u: usize| state.profiles.list.get(state.roster.profile[u]).map_or(geom::BaseShape::Round, |p| p.shape());
    let (sh, r_of) = (shape(mi), |u: usize, k: usize| state.radii[u].get(k).copied().unwrap_or(DEFAULT_BASE_RADIUS_M));
    (0..state.positions[mi].len())
        .filter(|&k| {
            let p = state.positions[mi][k];
            foes().any(|e| {
                let eh = shape(e);
                state.positions[e].iter().enumerate().any(|(j, &q)| {
                    (p[1] - q[1]).abs() <= vertical_in * IN2M
                        && geom::pair_gap_m(geom::to_f32(p), r_of(mi, k), sh, geom::to_f32(q), r_of(e, j), eh) / IN2M <= reach_in
                })
            })
        })
        .count() as i64
}

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
///
/// G4-C8a (`EPOCH_73_V36`): the count is `striking_models_edge` whatever the knob says, as the table's
/// `striking_models_for` always runs in the live game; the knob keeps its centre measure below 73.
fn melee_parts(statics: &[UnitStatic], state: &State, i: usize, ti: usize, seams: Seams) -> Vec<(usize, Scratch, Ctx)> {
    let mut parts: Vec<(usize, Scratch, Ctx)> = Vec::new();
    for &mi in std::iter::once(&i).chain(state.attached[i].iter()) {
        if state.alive[mi] <= 0 {
            continue; // main.gd:4290 — a member with no living model never rolls
        }
        let um = &statics[state.roster.profile[mi]];
        let mut sc = Scratch::default();
        let count = if rule_on(seams.rules_epoch, EPOCH_73_V36) {
            striking_models_edge(state, mi, ti, seams.rules_epoch)
        } else if seams.melee_reach {
            crate::combat::striking_models(&state.positions[mi], &state.positions[ti], seams.rules_epoch)
        } else {
            state.alive[mi]
        };
        sc.strikers = count;
        melee_profiles_of(um, count, &mut sc);
        melee_bearers_rescale(um, state, mi, count, seams.rules_epoch, &mut sc);
        sc.keep = (0..um.melee.len()).collect();
        drop_spent_limited(&um.melee, &state.limited_used[mi], &mut sc);
        let mut ctx = ctx_live_vs(ctx_of_melee(um, state, mi, seams.rules_epoch), statics, state, mi, ti, true, seams.rules_epoch);
        // rules-wave3-growthmark (epoch 6) — Regenerative Strength's melee
        // facet: +X attacks with ONE melee weapon, X = the bearer's own
        // marker count (`scope: "one_melee_weapon"`; the unit's FIRST melee
        // profile is the pick). Gated `EPOCH_6_TABLE_RULES`, so a rules_epoch
        // 5 record replays byte-exact. MEL-12 (`EPOCH_73_V36`): the SAME rule
        // name pays in token dice instead (rolled in `dice::resolve_melee_leg`),
        // so its attack share is subtracted and every other Growth Markers
        // rule keeps its own payout.
        if rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) && state.growth_markers[mi] > 0 {
            let markers = state.growth_markers[mi];
            let mut atk = um.growth.iter().map(|g| g.attacks_per_marker).sum::<i64>() * markers;
            if ctx.growth_wounds_not_attacks {
                atk -= um.growth.iter()
                    .filter(|g| g.name == "Regenerative Strength")
                    .map(|g| g.attacks_per_marker)
                    .sum::<i64>() * markers;
                ctx.growth_wound_dice = markers;
            }
            if atk != 0 {
                if let Some(a) = sc.attacks.first_mut() {
                    *a += atk;
                }
            }
        }
        parts.push((mi, sc, ctx));
    }
    parts
}

/// MEL-PAR-B14 (`EPOCH_73_V36`, table twin `_run_ai_melee`/`_run_human_melee`): a defender whose
/// living chain (host plus joined heroes) carries no melee profile at all — an Assault weapon's melee
/// copy counts, `unit::melee_profiles_at` builds it at this epoch — cannot strike back and is not
/// made Fatigued by the fight. FAB-B4 (MEL-02b, the table's `_solo_strike_back_block` "spent" read): a
/// Limited melee profile the member already spent counts as absent, so an all-spent chain is "no melee".
fn chain_has_no_melee(statics: &[UnitStatic], state: &State, i: usize) -> bool {
    std::iter::once(i)
        .chain(state.attached[i].iter().copied())
        .filter(|&mi| state.alive[mi] > 0)
        .all(|mi| {
            statics[state.roster.profile[mi]].melee.iter().all(|p| p.limited && state.limited_used[mi].iter().any(|n| n == &p.name))
        })
}

/// FAB-B7 — a joined chain's Fear(X): the host's own rating PLUS every LIVING attached
/// hero's, behind the same hero-attach seam every other chain read in this file uses. Below
/// `EPOCH_73_V36` the host-only read stands, so every recorded corpus replays byte-exact.
fn chain_fear(statics: &[UnitStatic], state: &State, i: usize, seams: Seams) -> i64 {
    let mut f = statics[state.roster.profile[i]].ctx.fear;
    if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) && seams.hero_attach {
        for &h in &state.attached[i] {
            if state.alive[h] > 0 {
                f += statics[state.roster.profile[h]].ctx.fear;
            }
        }
    }
    f
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
    ["Enhanced Guardian", "Enhanced Warden", "Enhanced Ossified"]
        .into_iter()
        .find(|n| mods::granted(state, ti, n))
        .map(String::from)
}

/// Audit 2026-09-13 §2.2 — the strike phase's weapon set, the table's
/// `SoloStrike` filter (main.gd:4683): the COUNTER_ONLY pre-phase strikes
/// the Counter weapons alone, the strike-back that follows it only the
/// NON-counter rest (:8315), and every other slot stays ALL.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum StrikeSet {
    All,
    CounterOnly,
    NonCounter,
}

#[allow(clippy::too_many_arguments)]
fn strike_phase(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    ti: usize,
    charging: bool,
    charge_from_in: f64,
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
    set: StrikeSet,
    cover: Cover,
) -> (i64, i64, i64, i64) {
    let mut parts = melee_parts(statics, next, si, ti, seams);
    if set != StrikeSet::All {
        let want_counter = set == StrikeSet::CounterOnly;
        for (mi, sc, _) in parts.iter_mut() {
            let melee = &statics[next.roster.profile[*mi]].melee;
            let mut k = 0;
            while k < sc.keep.len() {
                if melee[sc.keep[k]].counter != want_counter {
                    sc.keep.remove(k);
                    sc.attacks.remove(k);
                } else {
                    k += 1;
                }
            }
        }
    }
    // R3-X1b (`EPOCH_73_V36`, lead ruling 1): Precision Feat is ONE latch per game shared by shooting and melee. The bearer's
    // first attack of any kind - a strike-back included - gets +1 to hit on this whole phase, then the latch is spent.
    if rule_on(seams.rules_epoch, EPOCH_73_V36) {
        for (mi, _, att) in parts.iter_mut().filter(|(_, sc, _)| !sc.keep.is_empty()) {
            let um = &statics[next.roster.profile[*mi]];
            if um.precision_feat_hit > 0 && !next.feats_used[*mi].iter().any(|n| n == "Precision Feat") {
                att.feat_hit_bonus += um.precision_feat_hit;
                Rc::make_mut(&mut next.feats_used)[*mi].push("Precision Feat".to_string());
                shot.log.push(format!("[feat] Precision Feat spent by {}", um.name));
            }
        }
    }
    // MEL-01 (D-ASSAULT) rules-must-log: an Assault weapon's melee copy (the
    // profile carrying its printed range) names itself when it strikes.
    for (mi, sc, _) in parts.iter() {
        let melee = &statics[next.roster.profile[*mi]].melee;
        for &k in &sc.keep {
            if melee[k].printed_range > 0 {
                shot.log.push(format!("Assault: {} also strikes in melee", melee[k].name));
                say_melee(tray, next.player[*mi], format!("Assault: {} also strikes in melee", melee[k].name));
            }
        }
    }
    // G4-C8a rules-must-log: "Who Can Strike" names itself when fewer models strike than live (the table's
    // MEL-02 line, main.gd `_solo_attack_groups`, which prints the same text without the rule name).
    let who_can_strike: Vec<(i64, String)> = if rule_on(seams.rules_epoch, EPOCH_73_V36) {
        parts.iter().filter(|(mi, sc, _)| sc.strikers < next.alive[*mi]).map(|(mi, sc, _)| {
            let line = format!("{}: {} of {} models are within {}\" and strike", statics[next.roster.profile[*mi]].name,
                sc.strikers, next.alive[*mi], crate::combat::melee_reach_in(seams.rules_epoch).0 as i64);
            shot.log.push(format!("Who Can Strike: {line}"));
            (next.player[*mi], line)
        }).collect()
    } else {
        Vec::new()
    };
    // MEL-11 (`EPOCH_73_V36`) — Ravage once per round, never while Fatigued.
    // The table fatigues a host's joined heroes with it, so a tired host stops
    // theirs too; the Counter-only pre-phase leaves the one roll to the
    // strike-back that follows (the table's slot). Every skip is logged once.
    if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
        let host_tired = next.fatigued[si] || next.shaken[si];
        for (mi, _, att) in parts.iter_mut() {
            let um = &statics[next.roster.profile[*mi]];
            if host_tired || set == StrikeSet::CounterOnly {
                att.ravage = 0;
            }
            if set != StrikeSet::CounterOnly && um.ctx.ravage > 0 && att.ravage == 0 {
                shot.log.push(format!("Ravage: {} is Fatigued - no Ravage", um.name));
            }
            if att.growth_wound_dice > 0 {
                if host_tired || set == StrikeSet::CounterOnly {
                    att.growth_wound_dice = 0;
                    if set != StrikeSet::CounterOnly {
                        let line = format!("Regenerative Strength: {} is Fatigued - no token dice", um.name);
                        shot.log.push(line.clone());
                        say_melee(tray, next.player[*mi], line);
                    }
                } else if next.growth_strike_round[*mi] == next.round {
                    att.growth_wound_dice = 0;
                    let line = format!("Regenerative Strength: {} already rolled its dice this round", um.name);
                    shot.log.push(line.clone());
                    say_melee(tray, next.player[*mi], line);
                } else {
                    next.growth_strike_round[*mi] = next.round;
                }
            }
        }
    }
    // Block C5 — Instinctive: the +1 reaches the melee fold ONLY when the
    // attacked unit IS the closest enemy (main.gd:5670-5673), per member
    // carrying it — the pick itself is never constrained.
    for (mi, _, att) in parts.iter_mut() {
        if att.instinctive_hit_bonus > 0 && instinctive_applies(next, *mi, ti) {
            att.hit_mod += att.instinctive_hit_bonus;
        }
        // Rules 3.6 (`EPOCH_73_V36`) — Infiltrating Precision Strike: +1 to hit on the round the carrier arrived
        // (`ambush_arrived_round`, the stamp the arrival writes). A fatigued striker rolls a flat 6, so it
        // never gets the bonus (and no line). Every strike phase of the round applies and logs it.
        let ips = &statics[next.roster.profile[*mi]];
        if ips.infiltrating_precision_strike && next.ambush_arrived_round[*mi] == next.round && !att.fatigued {
            att.hit_mod += 1;
            shot.log.push(format!("Infiltrating Precision Strike: {} gets +1 to hit in melee this round", ips.name));
            trace_rule("infiltrating-precision-strike", &ips.name, "+1 to hit in melee (arrived this round)");
        }
        // Reckless Piercing (epoch 7, main.gd:6017): the chain's buff stamp
        // and the TARGET's backfire stamp both ride the +AP fold —
        // `_solo_reckless_ap(attacker, target)`'s net read.
        att.reckless_ap = (next.reckless_ap_round[*mi] == next.round) as i64
            + (next.reckless_backfire_round[ti] == next.round) as i64;
        // FEAT PR 3 — the latch's melee read: "Piercing Feat" is
        // `any_attack`, so a strike spends it exactly like a volley does
        // (the strike-back's own call re-runs this seam per side).
        if rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) {
            let uf = &statics[next.roster.profile[*mi]];
            if uf.piercing_feat_ap > 0
                && !next.feats_used[*mi].iter().any(|n| n == "Piercing Feat")
            {
                att.feat_ap_bonus += uf.piercing_feat_ap;
                Rc::make_mut(&mut next.feats_used)[*mi].push("Piercing Feat".to_string());
                shot.log.push(format!("[feat] Piercing Feat spent by {}", uf.name));
            }
        }
    }
    let ut = &statics[next.roster.profile[ti]];
    let mut def = with_modifier_sum(with_cond_ap_state(ctx_live(ctx_of(ut, next, ti), statics, next, ti, true, seams.rules_epoch), statics, next, ti, seams), seams.rules_epoch);
    def.side = next.player[ti];
    // The table's `_solo_log_defense_parts` lines, the first thing `_solo_melee_strike_phase` says: the Shielded family, then the growth ladder.
    crate::dice::say_shielded(tray, &def, &ut.name);
    crate::dice::say_growth_defense(tray, &def, &ut.name, &growth_defense_parts(statics, next, ti));
    crate::dice::say_sturdy_replaces(tray, &def);
    // The Guarded family's line, the next one the table says (`_solo_melee_strike_phase`): a charge from over the gate gives the defender +1 Defense.
    let gate = if def.guarded_charge_over_in > 0.0 { def.guarded_charge_over_in } else { crate::combat::LONG_RANGE_IN };
    if charging && def.guarded && charge_from_in > gate && !def.sturdy_boost_gates_guarded && (seams.tray_exact || def.guarded_charge_over_in > 0.0) {
        let saves = crate::combat::guarded_defense(shielded_defense(def.defense, def.shielded_bonus(), def.def_floor()), true, def.def_floor());
        say_rule(tray, "guarded", def.side, || format!("{} ({}): charged from over {}\" — +1 Defense (saves on {}+)",
            ut.name, def.guarded_name, gate as i64, saves.clamp(BEST_HIT_TARGET, 6)));
    }
    // MEL-07c-fix (`EPOCH_73_V36`) — the strike Parry counts the host AND its
    // joined heroes, the same sum the Impact event reads (`parry_dice_total`).
    if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
        def.parry_dice_total = Some(parry_dice_total(statics, next, ti));
    }
    stamp_blast_models(&mut def, next, ti, seams);
    // D-STEALTH — the def build's terrain gate (the melee leg consumes the
    // same closed alias the shooting fold does).
    stealth_alias_terrain_gate(statics, next, ti, cover, &mut def);
    // D-GATE6 (`EPOCH_73_V36`): the Screened family's charge leg reads the shared 6" charge gate;
    // the entry's own `over_in` (9") stays the shooting leg's. This def feeds the melee fold only,
    // and an ungated alias (`over_in` 0) keeps firing on any measured charge.
    if rule_on(seams.rules_epoch, EPOCH_73_V36) && def.stealth_alias_over_in > 0.0 {
        def.stealth_alias_over_in = crate::combat::CHARGE_LONG_RANGE_IN;
    }
    // MEL-13 (rules 3.6 Dodge, `EPOCH_73_V36`): the Melee Evasion -1 while the unit is not Fatigued (the plain
    // flag: Shaken does not switch it off for a defender). Both outcomes are named (rules-must-log).
    if def.dodge && rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
        if next.fatigued[ti] {
            shot.log.push(format!("Dodge: no effect, {} is Fatigued", ut.name));
        } else {
            def.melee_evasion = true;
            shot.log.push(format!("Dodge: enemies get -1 to hit {} in melee", ut.name));
        }
    }
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
    // EPOCH_38_WATCHBORN_LATCH — the melee half: a charge from over 9" is an
    // eligible attack, so the latch decides here when the activation has not
    // picked yet, and a pick made by an earlier volley reaches the dice fold.
    if charging
        && rule_on(seams.rules_epoch, EPOCH_38_WATCHBORN_LATCH)
    {
        for (mi, _, att) in parts.iter_mut() {
            let over = charge_from_in > crate::combat::charge_gate_in(seams.rules_epoch);
            if !att.versatile_no_gate && !over {
                continue;
            }
            let prof36 = statics[next.roster.profile[*mi]].melee.iter().find(|p| p.versatile_attack);
            if prof36.is_none() && !att.versatile_grant {
                continue;
            }
            let (vh, va, vl) = versatile_latch(next, statics, *mi,
                crate::combat::thrust_to_hit(
                    crate::combat::reliable_quality(att.quality,
                        prof36.map(|p| p.reliable).unwrap_or(false)),
                    (prof36.is_some() && prof36.unwrap().thrust) || att.thrust_grant,
                    crate::combat::BEST_HIT_TARGET,
                ),
                &def, guarded_folds(&def, charge_from_in, if def.guarded_charge_over_in > 0.0 { def.guarded_charge_over_in } else { crate::combat::LONG_RANGE_IN }, seams.rules_epoch),
                prof36, &mut shot.log, Some(&mut *tray), seams.rules_epoch);
            att.versatile_pick_hit = vh;
            att.versatile_pick_ap = va;
            att.versatile_latched = vl;
        }
    }
    // Snapshot defender alive before pre-strike direct wounds (Regenerative Strength) so
    // Deathstrike/Self-Destruct counts every model killed during this phase (main.gd:9395).
    let alive_before = next.alive[ti];
    // MEL-12 (`EPOCH_73_V36`): Regenerative Strength token wounds land immediately BEFORE weapon
    // strikes (main.gd:9461-9472), keeping their own casualty-order step and tray landing.
    let (mut gs_caused, mut gs_taken, mut gs_ignored) = (0i64, 0i64, 0i64);
    // DS-GMC1 (`EPOCH_92_MELEE_CAUSES`): the separate landing moves the Retaliate pool snapshot (the token wounds no longer
    // count as "taken") and the casualty order, so it applies on every path (seeded and step) from 92; below 92 the
    // pooled landing inside `resolve_melee_leg_wipe` is kept.
    if rule_on(seams.rules_epoch, EPOCH_92_MELEE_CAUSES)
        && !parts.iter().any(|(_, _, a)| a.unpredictable || a.ravage > 0)
        && parts.iter().any(|(_, _, a)| a.growth_wound_dice > 0)
    {
        let regen_def = Ctx {
            regen_target: if def.regen_gate_charge_in > 0.0 && charge_from_in <= def.regen_gate_charge_in {
                0
            } else {
                def.regen_target
            },
            ..def
        };
        for (mi, _, att) in parts.iter_mut() {
            let n = att.growth_wound_dice;
            if n <= 0 {
                continue;
            }
            att.growth_wound_dice = 0;
            let owner = statics[next.roster.profile[*mi]].name.clone();
            tray.owner_next(att.unit);
            let faces = tray.roll(n as usize);
            let w = faces.iter().filter(|&&f| f as i64 >= 4).count() as i64;
            shot.rolls.push(crate::dice::Roll { kind: "attack", count: n, target: 4, faces, owner: owner.clone() });
            shot.log.push(format!("Regenerative Strength: {owner} rolls {n} dice, {w} wounds"));
            say_melee(tray, next.player[*mi], format!(
                "Regenerative Strength: {owner} rolls {n} dice, {w} wound{}",
                if w == 1 { "" } else { "s" },
            ));
            if w > 0 {
                let landed = crate::dice::regen_batch(w, 0, &regen_def, &ut.name, tray, &mut shot.rolls);
                gs_caused += w;
                gs_taken += landed;
                gs_ignored += w - landed;
                let before = chain_snapshot(next, ti, tray);
                land_pool_wounds(next, ti, landed, seams.tray_exact, seams, &mut shot.log);
                land_chain_report(statics, next, tray, ti, before);
            }
        }
    }
    for (side, line) in who_can_strike {
        say_melee(tray, side, line);
    }
    // S1-02 rules-must-log (the table's `_solo_melee_strike_phase`, once per member group before its first weapon): a Shaken unit strikes back counting as
    // Fatigued. The Counter-only pre-phase says nothing; the main phase names each Shaken member (the host's Shaken covers its joined heroes).
    if rule_on(seams.rules_epoch, EPOCH_73_V36) && set != StrikeSet::CounterOnly {
        for (mi, _, _) in &parts {
            if next.shaken[si] || next.shaken[*mi] {
                say_melee(tray, next.player[*mi], format!("Shaken: {} strikes back counting as fatigued (6+)", statics[next.roster.profile[*mi]].name));
            }
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
    // R3-C2 (`EPOCH_73_V36`): do the finished Deadly groups already destroy the defender chain? Landed on a scratch copy,
    // so the answer is exact (casualty order, no carry-over, joined heroes); the dice leg then skips the pool's ignore die.
    let deadly_wipes = |r: &ShootResult| {
        let mut scratch = (*next).clone();
        r.deadly_groups.iter().for_each(|&(post, dx)| { land_deadly_wounds(&mut scratch, ti, post, dx, seams); });
        combined_alive(&scratch, ti, seams) == 0
    };
    let wipes: Option<&dyn Fn(&ShootResult) -> bool> = rule_on(seams.rules_epoch, EPOCH_73_V36).then_some(&deadly_wipes);
    let spread = blast_spread_units(next, ti, seams);
    let spread_models: Vec<i64> = spread.iter().map(|n| n.1).collect();
    let mut r = crate::dice::resolve_melee_leg_wipe(&members, &def, &ut.name, charging, cond_ap_dice, shred_alias_dice, rule_on(seams.rules_epoch, EPOCH_14_DEADLY_LANDING), charge_from_in, rule_on(seams.rules_epoch, EPOCH_22_SCREENED_MELEE), seams.tray_exact, rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36), rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36), rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36), wipes, &spread_models, tray);
    // WAVE 3, rules-must-log — the melee leg's Boost shape fired (no distance
    // here; the gated aliases never reach a melee save batch, exactly the
    // table's own `dist_in: -1.0` read, main.gd:6119).
    if r.fortified_fired {
        if let Some(n) = fortified_log_name(statics, next, ti, false) {
            shot.log.push(format!("{n}: {} takes the hits at AP(-{}), min. AP(0) — saves one better", ut.name, def.fortified_boost_ap.max(1)));
        }
    }
    for (mi, sc, _) in &parts {
        let melee = &statics[next.roster.profile[*mi]].melee;
        // MEL-02 (rules-must-log): the melee spend names the weapon, like the table's line.
        for &k in &sc.keep {
            if melee[k].limited {
                shot.log.push(format!("{} (Limited) is used up in melee", melee[k].name));
            }
        }
        mark_spent_limited(melee, &sc.keep, &mut next.limited_used, *mi);
    }
    let mut caused = r.caused + gs_caused;
    // MEL-10r (`EPOCH_73_V36`) — the melee-winner tally is wounds TAKEN: Regeneration-cancelled
    // wounds do not count. `r.caused` stays pre-Regeneration for the Regenerative Strength trigger.
    if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
        caused = r.taken + gs_taken;
    }
    // SHO-15b Scourge: the phantom wounds this strike's blocks earned, read
    // before `absorb` folds the sub-phase (which never carries them forward).
    let scourge_taken = r.scourge_wounds;
    // rules-wave3-growthmark (epoch 6) — Regenerative Strength: wounds this
    // strike IGNORED (Regeneration's own count) bank the bearer a marker. The
    // Deadly groups' raw tally rides `caused` but lands separately below, so
    // it is not an ignored wound.
    let ignored = (r.caused - r.wounds - r.deadly_tally) + gs_ignored;
    shot.regen_ignored += ignored;
    // DAT-17a: the grant is spent by wounds coming IN, not by wounds landing
    // after Regeneration. `caused` is the pre-Regeneration tally, so an
    // all-ignored roll still reads as wounding and a zero-wound exchange not.
    let def_incoming = r.caused > 0 || gs_caused > 0;
    let raw_deadly = r.deadly_tally;
    shot.attacked.push(ti);
    let spill = std::mem::take(&mut r.blast_spill);
    let w = shot.absorb(r);
    let members: Vec<usize> = parts.iter().map(|(mi, _, _)| *mi).collect();
    let hazard_self = land_hazardous_self(statics, next, &members, seams, tray, shot);
    // B13: the table measures the lash-back on wounds actually TAKEN — the
    // wound-POOL difference (`_solo_retaliate_hits` :4570, NML-937), snapshotted
    // BEFORE the landing like the table's `pools_before` (:6146) — overkill
    // wounds past the last model are lost and lash nothing back.
    let pool_before = wounds_left(next, ti);
    // A supplied tray (the step path) keeps the phase's landing and says the table's wound and loss lines
    // (`land_chain_report`, shared with the volley); a seeded tray snapshots nothing, so no draw or outcome moves.
    let landed = chain_snapshot(next, ti, tray);
    if !seams.tray_exact {
        land_pool_wounds(next, ti, w, false, seams, &mut shot.log);
    }
    // Audit 2026-09-13 §2.1 — Deadly lands PER MODEL with no carry-over (the
    // table's `apply_deadly_wounds`, solo_controller.gd:8333), and the melee
    // tally is the DEALT count so the multiply still decides who wins
    // (main.gd:6190-6191). Tray-exact S9: a Takedown group counts what it
    // LANDED, overkill included (`caused += td_dealt`, main.gd:7284), and the
    // table's order holds: Takedown, Deadly, then the pool.
    let mut dealt: i64 = shot.takedown_groups.iter().sum();
    let td_dealt = land_takedown_groups(next, ti, shot, seams.takedown_pick, None, None);
    // The table lands Deadly inline per weapon and says one line per weapon (`_solo_land_deadly_wounds`), then the report of the pool
    // wounds, whose "takes N wounds" count includes the inline ones (`land_chain_report_said`).
    let side = next.player[si];
    let mut deadly_dealt = 0;
    let mut groups = std::mem::take(&mut shot.deadly_groups).into_iter();
    // The table lands each Deadly weapon right after that weapon's own saves, ahead of the next weapon's rolls: its line, then the casualties
    // that landing removed. `marks` (the fold's line counts) say where; a supplied tray only (`landed`), the others say nothing.
    let marks = std::mem::take(&mut shot.deadly_marks);
    let deadly_lines = std::mem::take(&mut shot.deadly_lines);
    let marks = if marks.len() == deadly_lines.len() { marks } else { Vec::new() };
    let inline_on = seams.tray_exact && landed.is_some();
    let members: Vec<usize> = landed.iter().flatten().map(|(u, ..)| *u).collect();
    let (mut said, mut shift) = (vec![0i64; members.len()], 0);
    for (i, (weapon, unsaved, dx, n)) in deadly_lines.into_iter().enumerate() {
        let (mut wdealt, mut forced) = (0, 0);
        let lens0 = if inline_on { model_counts(next, &members) } else { Vec::new() };
        for (post, gx) in groups.by_ref().take(n) {
            let d = land_deadly_group(next, ti, post, gx, seams, &mut None, &mut forced);
            shot.log.push(format!("Deadly({gx}): {post} unsaved ×{gx}, no carry-over → {d} wounds dealt"));
            wdealt += d;
        }
        deadly_dealt += wdealt;
        let s = |n: i64| if n == 1 { "" } else { "s" };
        if wdealt > 0 {
            let mut at = if inline_on { marks.get(i).map(|m| (m.0 + shift, m.1)) } else { None };
            let at0 = at;
            let line = |text: String| LogLine { rule: "deadly", category: Category::Combat, side, text, detail: None };
            say_at_mark(tray, &mut at, line(format!("Deadly({dx}): {unsaved} unsaved ×{dx}, no carry-over → {wdealt} wound{} dealt ({weapon})", s(wdealt))));
            if forced > 0 {
                say_at_mark(tray, &mut at, line(format!("Deadly({dx}): {forced} wound{} finish the already-wounded Tough model first ({CITE})", s(forced))));
            }
            if inline_on {
                let lost: Vec<i64> = lens0.iter().zip(model_counts(next, &members)).map(|(&a, b)| a as i64 - b as i64).collect();
                for l in chain_loss_lines(statics, next, ti, &members, &lost) {
                    say_at_mark(tray, &mut at, l);
                }
                lost.iter().zip(said.iter_mut()).for_each(|(l, sd)| *sd += l);
            }
            shift += at.zip(at0).map_or(0, |(a, b)| a.0 - b.0);
        }
    }
    for (post, gx) in groups {
        let d = land_deadly_wounds(next, ti, post, gx, seams);
        deadly_dealt += d;
        shot.log.push(format!("Deadly({gx}): {post} unsaved ×{gx}, no carry-over → {d} wounds dealt"));
    }
    dealt += deadly_dealt;
    if seams.tray_exact {
        land_pool_wounds(next, ti, w, true, seams, &mut shot.log);
    }
    let inline_said = (inline_on && deadly_dealt + td_dealt > 0).then_some(InlineSaid { said, pool: w });
    land_chain_report_said(statics, next, tray, ti, landed, deadly_dealt + td_dealt, inline_said.as_ref());
    caused = caused - raw_deadly + dealt;
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
    if taken > 0 && def.retaliate_hits_per_wound > 0 && next.alive[si] > 0 {
        let hits = def.retaliate_hits_per_wound * taken;
        shot.log.push(format!("Retaliate: {} lashes back — {} hits", ut.name, hits));
        say_melee(tray, next.player[ti], format!(
            "Retaliate: {} lashes back — {} hit{} ({}: {} wound{} × {})",
            ut.name, hits, if hits == 1 { "" } else { "s" },
            ut.name, taken, if taken == 1 { "" } else { "s" }, def.retaliate_hits_per_wound,
        ));
        let su = &statics[next.roster.profile[si]];
        // The lash-back wounds the holder: read its LIVE ctx so a granted
        // Regeneration is asked about them (the defender side already does).
        let mut sctx = if rule_on(seams.rules_epoch, EPOCH_73_V36) {
            ctx_live(ctx_of(su, next, si), statics, next, si, true, seams.rules_epoch)
        } else {
            ctx_of(su, next, si)
        };
        sctx.side = next.player[si];
        let (unsaved, landed) = crate::dice::retaliate_saves_with_tray(
            hits, &sctx, &su.name, tray, &mut shot.rolls,
        );
        if unsaved > 0 {
            let before = chain_snapshot(next, si, tray);
            land_wounds_with(next, si, landed, seams.tray_exact, seams.rules_epoch);
            land_chain_report(statics, next, tray, si, before);
            retaliated = unsaved; // _solo_retaliate_credit += rw (main.gd:6171)
        }
    }
    // DAT-17a: the striker's grant is spent on wounds COMING IN (pre-Regeneration),
    // the same rule as the defender side — an all-ignored lash-back still spends it.
    let mut att_incoming = retaliated;
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
        let rule = if ut.ctx.self_destruct_rating > 0 { "Self-Destruct" } else { "Deathstrike" };
        shot.log.push(format!(
            "Deathstrike/Self-Destruct: {}'s dying models lash out — {} takes {} hits",
            ut.name, su.name, hits
        ));
        say_melee(tray, next.player[ti], format!(
            "{rule}: {}'s dying models lash out — {} takes {hits} hit{}",
            ut.name, su.name, if hits == 1 { "" } else { "s" },
        ));
        let mut sctx = if rule_on(seams.rules_epoch, EPOCH_73_V36) {
            ctx_live(ctx_of(su, next, si), statics, next, si, true, seams.rules_epoch)
        } else {
            ctx_of(su, next, si)
        };
        sctx.side = next.player[si];
        let (_, landed) = crate::dice::retaliate_saves_with_tray(
            hits, &sctx, &su.name, tray, &mut shot.rolls,
        );
        att_incoming += landed;
        let before = chain_snapshot(next, si, tray);
        land_wounds_with(next, si, landed, seams.tray_exact, seams.rules_epoch);
        land_chain_report(statics, next, tray, si, before);
    }
    // The skirmish Blast spread (ruling D12): the neighbours are no part of this melee - their wounds never join its tally,
    // and each one wounded tests morale after the melee's own test (`melee_spilled`).
    let neighbours: Vec<usize> = spread.iter().map(|n| n.0).collect();
    for hit in land_blast_spill(statics, next, &parts, &spill, &neighbours, (0.0, 0.0), true, seams, tray, shot) {
        if shot.melee_spilled.iter().all(|m| m.0 != hit.0) {
            shot.melee_spilled.push(hit);
        }
    }
    let att_wounded = att_incoming > 0;
    spend_exchange_wounded(next, si, ti, true, att_wounded, def_incoming, seams.rules_epoch); // main.gd:6152, per strike phase
    say_marks_consumed(statics, next, tray, shot);
    spend_protection_feat(statics, next, ti, def_incoming, seams.rules_epoch);
    (caused, retaliated, hazard_self, scourge_taken)
}

/// The charge's Impact, pool by pool — `main._solo_charge_impact` :6292. The
/// pools are resolved SEPARATELY because :6304 re-checks the defender's alive
/// count before each one: an Impact pool that wipes the defender means the Heavy
/// pool never rolls. Returns the pre-Regeneration wounds caused.
/// Rules 3.6 (`EPOCH_73_V36`) — one Impact event with Parry: every pool's hit
/// dice first, then the defender's Parry dice (capped at the hits taken),
/// then the saves with the heavy pool's hits cancelled first.
#[allow(clippy::too_many_arguments)]
fn impact_with_parry(
    statics: &[UnitStatic], next: &mut State, si: usize, ti: usize, us: &UnitStatic, ut: &UnitStatic,
    pools: [(i64, i64); 2], parry_dice: i64, charge: Option<(f64, bool)>, tray: &mut Tray,
    shot: &mut ShootResult, tally_post_regen: bool, rules_epoch: u32,
) -> i64 {
    let exact = matches!(charge, Some((_, true)));
    let meta = [("Impact", us.ctx.impact), ("Heavy Impact", us.ctx.heavy_impact)];
    let mut hits: [(i64, i64); 2] = [(0, 0), (0, 0)];
    for (i, &(dice, ap)) in pools.iter().enumerate() {
        if dice <= 0 || next.alive[ti] <= 0 { continue; }
        tray.owner_next(Some(si));
        let (roll, h) = crate::dice::impact_hit_roll(dice, &us.name, tray);
        shot.rolls.push(roll);
        let (label, rating) = meta[i];
        say_melee(tray, next.player[si], format!("{}: {label}({rating}) rolls {dice} di{} → {h} hit{}",
            us.name, if dice == 1 { "e" } else { "ce" }, if h == 1 { "" } else { "s" }));
        hits[i] = (h, ap);
    }
    let n = parry_dice.min(hits[0].0 + hits[1].0);
    if n > 0 {
        tray.owner_next(Some(ti));
        let faces = tray.roll(n as usize);
        let k = faces.iter().filter(|&&f| f >= 6).count() as i64;
        shot.rolls.push(crate::dice::Roll {
            kind: "parry", count: n, target: 6, faces: faces.clone(), owner: ut.name.clone(),
        });
        let line = format!("Parry: {} rolls {} dice and ignores {} Impact hits", ut.name, n, k);
        shot.log.push(line.clone());
        say_melee(tray, next.player[ti], line);
        hits = crate::dice::parry_cancel(&faces, hits);
    }
    let mut caused = 0;
    for &(h, ap) in &hits {
        if h <= 0 || next.alive[ti] <= 0 { continue; }
        let mut def = ctx_of_melee(ut, next, ti, rules_epoch);
        def.side = next.player[ti];
        let r = crate::dice::impact_saves_with_tray(h, ap, &def, &ut.name, charge, tray);
        // MEL-10r (`EPOCH_73_V36`) — Impact wounds Regeneration cancels are not TAKEN.
        caused += if tally_post_regen { r.wounds } else { r.caused };
        shot.regen_ignored += r.caused - r.wounds;
        let w = shot.absorb(r);
        let before = chain_snapshot(next, ti, tray);
        land_wounds_with(next, ti, w, exact, rules_epoch);
        land_chain_report(statics, next, tray, ti, before);
    }
    caused
}

/// Rules 3.6 (`EPOCH_73_V36`) — the Parry dice ONE hits event brings: every
/// living carrier model on the host AND its joined heroes contributes its own
/// `Ctx::parry_dice` (the table's `[defender] + get_attached_heroes()` walk,
/// main.gd:8647-8653). The Impact event and the strike Parry read this same
/// sum, so both sides count the same models.
/// `EPOCH_75_TABLE_FIXES` (table #2642): a Parry WEAPON counts only the models
/// that carry it (`UnitStatic::parry_weapons`, empty below 75 and for the rule form).
fn parry_dice_total(statics: &[UnitStatic], state: &State, ti: usize) -> i64 {
    std::iter::once(ti)
        .chain(state.attached[ti].iter().copied())
        .filter(|&m| state.alive[m] > 0)
        .map(|m| {
            let us = &statics[state.roster.profile[m]];
            if us.parry_weapons.is_empty() {
                us.ctx.parry_dice * state.alive[m]
            } else {
                us.parry_weapons.iter().map(|&(x, carriers)| x * carriers.min(state.alive[m])).sum()
            }
        })
        .sum()
}

/// Impact pool by pool; the caller lands the wounds.
#[allow(clippy::too_many_arguments)]
fn impact_phase(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    ti: usize,
    tray: &mut Tray,
    shot: &mut ShootResult,
    rules_epoch: u32,
    charge_from_in: f64,
    exact: bool,
) -> i64 {
    let us = &statics[next.roster.profile[si]];
    let ut = &statics[next.roster.profile[ti]];
    let mut cut_by = ctx_of(ut, next, ti);
    if exact {
        // Tray-exact tail — the table's Impact cut walks the host AND its living attached heroes
        // (`counter_models_of`, solo_controller.gd:8465), each at its own per-model magnitude.
        cut_by.counter_models = std::iter::once(ti).chain(next.attached[ti].iter().copied())
            .filter(|&m| next.alive[m] > 0)
            .map(|m| { let c = ctx_of(&statics[next.roster.profile[m]], next, m); c.counter_models * c.counter_impact_per_model.unwrap_or(1) })
            .sum();
        cut_by.counter_impact_per_model = Some(1);
    }
    if rule_on(rules_epoch, EPOCH_73_V36) {
        // Rules 3.6 — Counter no longer cuts Impact dice; Brace is the only cut.
        cut_by.counter_models = 0;
        // The Brace walk, host AND living attached heroes: the unit's single
        // rating X, never multiplied by models or carriers. A Fatigued braced
        // unit removes nothing; Shaken does not switch it off.
        let (brace, brace_rule): (i64, &str) = std::iter::once(ti).chain(next.attached[ti].iter().copied())
            .filter(|&m| next.alive[m] > 0)
            .map(|m| {
                let su = &statics[next.roster.profile[m]];
                let c = ctx_of(su, next, m);
                (if c.brace_models > 0 { c.brace_impact_per_model.unwrap_or(1) } else { 0 }, su.brace_rule.as_str())
            })
            .max_by_key(|b| b.0)
            .unwrap_or((0, ""));
        let braced = next.fatigued[ti];
        if brace > 0 {
            let line = if braced {
                format!("{brace_rule}: no effect, {} is Fatigued", ut.name)
            } else {
                format!("{brace_rule}: {} takes {} Impact dice off {}", ut.name, brace, us.name)
            };
            shot.log.push(line.clone());
            say_melee(tray, next.player[ti], line);
        }
        cut_by.brace_models = if braced || brace == 0 { 0 } else { 1 };
        cut_by.brace_impact_per_model = Some(brace.max(1));
    }
    let pools = crate::dice::impact_pools(&ctx_of_melee(us, next, si, rules_epoch), &cut_by);
    // Rules 3.6 (`EPOCH_73_V36`) — Parry(X): each living carrier model (host
    // and joined heroes) contributes X dice against this Impact event.
    // `EPOCH_75_TABLE_FIXES` (maintainer ruling): Impact hits are never parried,
    // so no Parry die is drawn; a record stamped 74 or below replays its draw.
    let parry_dice: i64 = if rule_on(rules_epoch, EPOCH_73_V36) && !rule_on(rules_epoch, EPOCH_75_TABLE_FIXES) {
        parry_dice_total(statics, next, ti)
    } else {
        0
    };
    let tally_post_regen = rule_on(rules_epoch, EPOCH_73_V36);
    if parry_dice > 0 {
        return impact_with_parry(statics, next, si, ti, us, ut, pools, parry_dice, Some((charge_from_in, exact)), tray, shot, tally_post_regen, rules_epoch);
    }
    let meta = [("Impact", us.ctx.impact), ("Heavy Impact", us.ctx.heavy_impact)];
    let mut caused = 0;
    for (i, (dice, ap)) in pools.into_iter().enumerate() {
        if dice <= 0 || next.alive[ti] <= 0 {
            continue; // :6304 — nothing left to hit, no dice
        }
        tray.owner_next(Some(si));
        let (roll, hits) = crate::dice::impact_hit_roll(dice, &us.name, tray);
        shot.rolls.push(roll);
        let (label, rating) = meta[i];
        say_melee(tray, next.player[si], format!("{}: {label}({rating}) rolls {dice} di{} → {hits} hit{}",
            us.name, if dice == 1 { "e" } else { "ce" }, if hits == 1 { "" } else { "s" }));
        if hits <= 0 {
            continue;
        }
        let mut def = ctx_of_melee(ut, next, ti, rules_epoch);
        def.side = next.player[ti];
        let r = crate::dice::impact_saves_with_tray(
            hits, ap, &def, &ut.name, Some((charge_from_in, exact)), tray,
        );
        // MEL-10r (`EPOCH_73_V36`) — Impact wounds Regeneration cancels are not TAKEN.
        caused += if tally_post_regen { r.wounds } else { r.caused };
        shot.regen_ignored += r.caused - r.wounds;
        let w = shot.absorb(r);
        let before = chain_snapshot(next, ti, tray);
        land_wounds_with(next, ti, w, exact, rules_epoch);
        land_chain_report(statics, next, tray, ti, before);
    }
    caused
}

/// Block C4 — the SURVIVAL half of `Self-Destruct` (`_solo_self_destruct_post_melee`
/// main.gd:17346-17370, called for BOTH combatants at main.gd:8431-8433 and
/// :10456-10458): after both sides have finished attacking, every surviving
/// carrier of `ui` is removed — "it is immediately killed", the table applies
/// 9999 wounds with NO saves (main.gd:17363) — and the enemy takes X hits per
/// removed model, X = the rule's own `maxi(rating, 1)` read off the alive count
/// BEFORE the removal (main.gd:17351-17358). The hits save at the enemy's
/// Shielded-adjusted melee Defense with ap 0 — the same `retaliate_saves_with_tray`
/// the death half and Retaliate use (main.gd:17366-17369) — and land through
/// `land_wounds` alone, never through another strike phase. NO tally credit:
/// the table's melee score (main.gd:8436-8437) is tallied from the strike
/// phases only, so the detonation cannot move the who-wins comparison or the
/// loser's morale. No Shaken/Routed read: the table gates only on the member's
/// alive count (main.gd:17351-17352) and runs the half BEFORE the melee
/// result / morale test, so a Shaken carrier still detonates. EPOCH_41 gate:
/// below 41 every recorded game replays byte-exact.
fn self_destruct_post_melee(
    statics: &[UnitStatic],
    next: &mut State,
    ui: usize,
    enemy: usize,
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
) {
    if !rule_on(seams.rules_epoch, EPOCH_41_SELF_DESTRUCT_SURVIVORS) {
        return;
    }
    let ut = &statics[next.roster.profile[ui]];
    if ut.ctx.self_destruct_rating <= 0 {
        return;
    }
    let alive = next.alive[ui];
    if alive <= 0 {
        return;
    }
    let hits = ut.ctx.self_destruct_rating * alive;
    let enemy_name = statics[next.roster.profile[enemy]].name.clone();
    shot.log.push(format!(
        "Self-Destruct: {alive} surviving models detonate, {hits} hits to {enemy_name}"
    ));
    say_melee(tray, next.player[ui], format!(
        "Self-Destruct: {} detonates after the melee — destroyed; {enemy_name} takes {hits} hit{}",
        ut.name, if hits == 1 { "" } else { "s" },
    ));
    let before_self = chain_snapshot(next, ui, tray);
    land_wounds(next, ui, 9999); // main.gd:17363 — "it is immediately killed", no saves
    land_chain_report(statics, next, tray, ui, before_self);
    if next.alive[enemy] > 0 {
        let eu = &statics[next.roster.profile[enemy]];
        let mut ectx = ctx_of(eu, next, enemy);
        ectx.side = next.player[enemy];
        let (_, landed) = crate::dice::retaliate_saves_with_tray(
            hits, &ectx, &eu.name, tray, &mut shot.rolls,
        );
        let before_enemy = chain_snapshot(next, enemy, tray);
        // DS-GMC1 (`EPOCH_92_MELEE_CAUSES`): the table's casualty order (a wounded Tough first, kits) on every path from 92.
        land_wounds_with(next, enemy, landed, seams.tray_exact && rule_on(seams.rules_epoch, EPOCH_92_MELEE_CAUSES), seams.rules_epoch);
        land_chain_report(statics, next, tray, enemy, before_enemy);
    }
}

pub(crate) const HERO_AURA_TOUGH: i64 = 9;
pub(crate) const HERO_AURA_REACH_IN: f64 = 6.0;

/// Rules 3.6 hero morale aura (`EPOCH_73_V36`; `main._solo_aura_hero_for_morale` twin): the friendly Hero with
/// the best Quality, when it beats `own`, that lends unit `i` its morale test — alive, not Shaken, in play,
/// Tough >= `aura.min_tough`, within `aura.reach_in` base edge to base edge (`modifier_distance_in`, the table's
/// `nearest_melee_gap_in`). A Shaken `i` rolls no die, so no aura is spent.
fn hero_aura_quality_for_book(
    statics: &[UnitStatic],
    state: &State,
    i: usize,
    own: i64,
    seams: Seams,
    aura: crate::rules::HeroAura,
) -> Option<(usize, i64)> {
    if !rule_on(seams.rules_epoch, EPOCH_73_V36) || unit_shaken(state, i, seams) {
        return None;
    }
    let mut best: Option<(usize, i64)> = None;
    for h in 0..state.units() {
        let hs = &statics[state.roster.profile[h]];
        if h == i || state.player[h] != state.player[i] || state.alive[h] <= 0 || state.shaken[h] || state.dormant[h]
            || !hs.is_hero || hs.ctx.tough < aura.min_tough || (aura.joins && state.attached[i].contains(&h))
        {
            continue;
        }
        if hs.quality >= best.map_or(own, |b| b.1) {
            continue;
        }
        if modifier_distance_in(state, i, h, seams) <= aura.reach_in + CONTROL_EPS {
            best = Some((h, hs.quality));
        }
    }
    best
}

fn hero_aura_quality(statics: &[UnitStatic], state: &State, i: usize, own: i64, seams: Seams) -> Option<(usize, i64)> {
    hero_aura_quality_for_book(statics, state, i, own, seams, state.book(i).hero_aura_at(seams.rules_epoch))
}

/// G4R4 C-BANNER-DEAD-HOST (`EPOCH_73_V36`): the part of unit `i`'s recorded Banner bonus that left with its carrier. The
/// table reads the Banner by LIVING member (`morale_bonus_named_of` skips a member without models), so once the host that
/// carried it has no models, only a living joined hero's own Banner is left. 0 below 73 and while the host lives.
fn banner_gone(statics: &[UnitStatic], state: &State, i: usize, seams: Seams) -> i64 {
    let share = |u: usize| (state.morale_bonus[u] - statics[state.roster.profile[u]].ctx.morale_rating).max(0);
    let root = morale_root(state, i, seams);
    if !rule_on(seams.rules_epoch, EPOCH_73_V36) || !seams.hero_attach || state.alive[root] > 0 {
        return 0;
    }
    let kept = state.attached[root].iter().filter(|&&h| state.alive[h] > 0).map(|&h| share(h)).max().unwrap_or(0);
    (share(i) - kept).max(0)
}

/// One live context for ordinary morale and the Mind Control family.
fn live_morale_ctx(statics: &[UnitStatic], state: &State, i: usize, melee: bool, seams: Seams, shot: &mut ShootResult, tray: &mut Tray) -> Ctx {
    let us = &statics[state.roster.profile[i]];
    let mut ctx = ctx_of(us, state, i);
    // The table's `_solo_morale_quality` names who lends the Quality, once per test that rolls a die: the aura Hero, else the
    // joined Hero whose Quality the unit uses.
    let rolls = !unit_shaken(state, i, seams);
    // A lone hero's test is its host's in the table's log: the lines name the host, whose joined heroes lend the Quality.
    let root = morale_root(state, i, seams);
    let shown = &statics[state.roster.profile[root]].name;
    if rule_on(seams.rules_epoch, EPOCH_65_MELEE_TRUTH) && seams.hero_attach {
        ctx.quality = morale_quality(statics, state, i, seams);
    }
    let mut lender = morale_hero(statics, state, root, seams);
    if let Some((h, quality)) = hero_aura_quality(statics, state, i, ctx.quality, seams) {
        ctx.quality = quality;
        let line = format!("{} (Tough 9+) lends its Quality to {shown}'s morale test (Q{}+)", statics[state.roster.profile[h]].name, quality);
        shot.log.push(line.clone());
        say_rule(tray, "morale", state.player[i], || line);
        lender = None;
    }
    if let (true, Some((h, quality))) = (rolls, lender) {
        say_rule(tray, "morale", state.player[i], || format!("Hero {} tests on behalf of {shown} (Q{quality}+)", statics[state.roster.profile[h]].name));
    }
    if rule_on(seams.rules_epoch, EPOCH_65_MELEE_TRUTH) {
        ctx.fearless = morale_fearless(statics, state, i, seams);
    }
    // The LIVE Banner/spell bonus, not the static one: `morale_fails_expected`
    // reads `state.morale_bonus[i]` and `_solo_morale_bonus` (main.gd:6632) is
    // the same live read, so the ROLLED target has to be too. Reading the static
    // profile instead is a whole point of target off on every Banner unit.
    // B2b: the live morale records join the Banner bonus in the SAME
    // [2,6]-clamped target the table builds (main.gd:8288-8296). Wave 2: a
    // granted "Hold the Line Boost" joins the same net, epoch-gated.
    let gone = banner_gone(statics, state, i, seams);
    if gone > 0 {
        let root = &statics[state.roster.profile[morale_root(state, i, seams)]].name;
        let line = format!("Banner: {root} died with its Banner — {}'s morale test loses +{gone}", us.name);
        say_rule(tray, "banner", state.player[i], || line.clone()); // the step path's lines are the tray's
        shot.log.push(line);
    }
    ctx.morale_bonus = state.morale_bonus[i] - gone
        + mods::sum(state, i, mods::Role::Morale, melee, |r| r.morale_mod)
        + if rule_on(seams.rules_epoch, EPOCH_5_TABLE_RULES) && mods::granted(state, i, "Enhanced Hold the Line") { HOLD_THE_LINE_BOOST_MORALE_BONUS } else { 0 };
    ctx.no_retreat = ctx.no_retreat || mods::granted(state, i, "No Retreat");
    ctx
}

/// Rules 3.6 Banner (`EPOCH_73_V36`): the Banner family's +1 only helps a
/// morale test that shooting or melee caused. Any other cause (`Some(rule)`)
/// takes the Banner share (the capture stamp minus the Morale(X) rating it
/// also carries) back out of the target and names the cause once. Spell
/// tokens and a granted Hold the Line Boost stay in.
///
/// MOR-09 Valiant: a shooting- or melee-caused test whose forcing distance sits
/// INSIDE the band (shot at 9" or under, charge from 6" or under) also loses the
/// Banner share. The distance is threaded from the call sites that already know
/// the geometry; `None` means the caller could not supply it without inventing
/// one, so the 3.5 reading stands (do not guess). Great Banner stays with the
/// cause gate — it is a Utility Buff, not a Valiant-family entry.
///
/// MOR-09b: `charged_by_enemy = false` is the melee the unit itself charged and
/// lost. Melee caused the test, so Banner stays; but the unit was not charged,
/// so the Valiant share comes out (an explicit state, never the `None` reading).
///
/// Returns the Banner-family share it took out of the target (a Great Banner spell token excluded: the table keeps
/// that one with the spell tokens), which is what the table's own "gets +N to morale test rolls" line counts.
#[allow(clippy::too_many_arguments)] // the cause/distance flags join the existing parity args
fn drop_banner_for_cause(
    statics: &[UnitStatic], state: &State, i: usize, melee: bool, charged_by_enemy: bool,
    cause: Option<&str>, over_in: Option<f64>, charge_from_in: Option<f64>, seams: Seams,
    ctx: &mut Ctx, shot: &mut ShootResult, tray: &mut Tray,
) -> i64 {
    if !rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) || unit_shaken(state, i, seams) { return 0; }
    let us = &statics[state.roster.profile[i]];
    let shown = &statics[state.roster.profile[morale_root(state, i, seams)]].name; // a lone hero's test is its host's
    let banner = ((state.morale_bonus[i] - us.ctx.morale_rating).max(0) - banner_gone(statics, state, i, seams)).max(0);
    if let Some(cause) = cause {
        // `EPOCH_75_TABLE_FIXES` (main.gd's cause branch): Bravery Aura has no shooting/melee
        // qualifier, so its share stays on a test any other rule forced; only the rest comes out.
        let kept = if rule_on(seams.rules_epoch, EPOCH_75_TABLE_FIXES) { us.ctx.bravery_bonus.min(banner).max(0) } else { 0 };
        if kept > 0 {
            shot.log.push(format!("[Bravery Aura] {}: keeps +{kept} against {cause} (no shooting/melee qualifier)", us.name));
        }
        let banner = banner - kept;
        if banner > 0 {
            ctx.morale_bonus -= banner;
            shot.log.push(format!("[Banner] {}: no +{} against {} (only shooting or melee)", us.name, banner, cause));
            say_rule(tray, "banner", state.player[i], || format!("Banner: {shown} gets no +{banner} against {cause} (only shooting or melee)"));
        }
        let great_banner = mods::sum(state, i, mods::Role::Morale, melee, |r| {
            if &*r.name == "Great Banner" { r.morale_mod } else { 0 }
        });
        if great_banner != 0 {
            ctx.morale_bonus -= great_banner;
            shot.log.push(format!("[Great Banner] {}: no +{} against {} (only shooting or melee)", us.name, great_banner, cause));
            say_rule(tray, "banner", state.player[i], || format!("Great Banner: {shown} gets no +{great_banner} against {cause} (only shooting or melee)"));
        }
        return banner.max(0);
    }
    if !charged_by_enemy {
        // MOR-09b: the unit itself charged and lost. Melee caused the test, so
        // Banner stays; the Valiant family does not — the unit was not charged.
        let vt = us.ctx.valiant_bonus.min(banner).max(0);
        if vt > 0 {
            ctx.morale_bonus -= vt;
            let line = format!(
                "[Banner] {}: no +{vt} — it charged, it was not charged (Valiant needs a shot or a charge)",
                us.name
            );
            trace_rule("morale", "Banner", &line);
            shot.log.push(line);
            say_rule(tray, "banner", state.player[i], || format!("Banner: {shown} gets no +{vt} — it charged, it was not charged (Valiant needs a shot or a charge)"));
        }
        return vt;
    }
    if !crate::unit::valiant_inside_band(melee, over_in, charge_from_in) { return 0; }
    let vt = us.ctx.valiant_bonus.min(banner).max(0);
    if vt > 0 {
        ctx.morale_bonus -= vt;
        let (kind, band) = if melee {
            ("charge from", crate::unit::VALIANT_CHARGE_GATE_IN)
        } else {
            ("shot at", crate::unit::VALIANT_SHOT_GATE_IN)
        };
        let line = format!(
            "[Banner] {}: no +{vt} from a {kind} {band}\" or under (Valiant counts only beyond the gate)",
            us.name
        );
        trace_rule("morale", "Banner", &line);
        shot.log.push(line);
        say_rule(tray, "banner", state.player[i], || format!(
            "Banner: {shown} gets no +{vt} from a {kind} {band}\" or under (Valiant counts only beyond the gate)"));
    }
    vt
}

/// Ruling D16: unit `u` carries an AoF: Skirmish command group with `rule` (Banner or Musician).
fn command_rule(state: &State, u: usize, rule: &str) -> bool {
    // read the way `State::book` does: a synthetic state without its profile list carries no command group
    let Some(p) = state.roster.profile.get(u).and_then(|&pi| state.profiles.list.get(pi)) else { return false };
    crate::rules::carries_command(&p.game_system, &p.special_rules) && p.special_rules.iter().any(|r| r == rule)
}

/// Ruling D16: unit `u`'s command-group bearer is killed. A State built without the bearer list (an empty vector) knows
/// no death; `Some(None)` is a killed bearer.
fn bearer_dead(state: &State, u: usize) -> bool {
    matches!(state.cmd_bearer.get(u), Some(None))
}

/// KIT-BEARER-NAME (lead ruling 26.11., `PENDING_EPOCH_TWO_BEARERS`): the Musician dies with the model that carries it,
/// which may not be the Banner's; below the placeholder it rides with the one bearer (`bearer_dead`), as recorded.
fn musician_dead(state: &State, u: usize, rules_epoch: u32) -> bool {
    if rule_on(rules_epoch, crate::acts::PENDING_EPOCH_TWO_BEARERS) { matches!(state.musician_bearer(u), Some(None)) } else { bearer_dead(state, u) }
}

/// Ruling D16: the friendly command-group unit with `rule` whose profile picked unit `i` (`Profile::command_picks`).
fn command_lender(state: &State, i: usize, rule: &str) -> Option<usize> {
    let key = &state.roster.keys[i];
    (0..state.units()).find(|&k| k != i && state.player[k] == state.player[i] && command_rule(state, k, rule)
        && state.profile(k).command_picks.iter().any(|p| p == key))
}

/// Ruling D17 for the Musician (AoF: Skirmish p.13, `EPOCH_103_COMMAND_BANNER`): the +1 in on move actions lives with
/// the bearer. The unit's own Musician inch already rides its recorded bands, so a killed bearer takes it back (-1); a unit
/// a friendly living bearer's Musician unit picked gets +1. The line says which, or `None` when nothing changes.
pub(crate) fn command_musician_in(statics: &[UnitStatic], state: &State, i: usize, kind: i64, rules_epoch: u32) -> (f64, Option<String>) {
    if !rule_on(rules_epoch, crate::acts::EPOCH_103_COMMAND_BANNER) || !matches!(kind, ADVANCE | RUSH | CHARGE) {
        return (0.0, None);
    }
    let name = |u: usize| statics.get(state.roster.profile[u]).map_or("", |us| us.name.as_str());
    if command_rule(state, i, "Musician") && musician_dead(state, i, rules_epoch) {
        return (-MUSICIAN_MOVE_IN, Some(format!("Musician: {}'s bearer (the last model carries it - no per-model data) is dead - no +1\" move", name(i))));
    }
    match command_lender(state, i, "Musician") {
        Some(k) if musician_dead(state, k, rules_epoch) || state.alive[k] == 0 =>
            (0.0, Some(format!("Musician (from {}): its bearer is dead - {} gets no +1\" move", name(k), name(i)))),
        Some(k) => (MUSICIAN_MOVE_IN, Some(format!("Musician (from {}, the last model carries it - no per-model data): {} moves +1\"", name(k), name(i)))),
        None => (0.0, None),
    }
}

/// The AoF: Skirmish Musician's inch on move actions (its rules-map entry's `move_bonus_in`, which the recorded bands carry).
const MUSICIAN_MOVE_IN: f64 = 1.0;

/// Ruling D17 (AoF: Skirmish p.13, `EPOCH_103_COMMAND_BANNER`): the command-group Banner lives with its bearer. A unit
/// whose own bearer is killed loses its Banner +1 (returned, so the bonus line counts without it); a unit another living
/// bearer's Banner unit picked gets +1 on a test that shooting or melee caused. The bearer is the last model (no per-model
/// data names it, KIT-BEARER-NAME), and a test from the attack that killed him reads him as gone. Table games carry no picks
/// until CMD-ROUNDTRIP, so only the own-unit half reaches them.
#[allow(clippy::too_many_arguments)]
fn command_banner(
    statics: &[UnitStatic], state: &State, i: usize, cause: Option<&str>, seams: Seams,
    ctx: &mut Ctx, shot: &mut ShootResult, tray: &mut Tray,
) -> i64 {
    if !rule_on(seams.rules_epoch, crate::acts::EPOCH_103_COMMAND_BANNER) || unit_shaken(state, i, seams) {
        return 0;
    }
    let banner = |u: usize| command_rule(state, u, "Banner");
    let bearer_dead = |u: usize| bearer_dead(state, u);
    let shown = &statics[state.roster.profile[morale_root(state, i, seams)]].name;
    if cause.is_some() {
        return 0; // a test no shooting or melee caused gets no Banner at all (`drop_banner_for_cause` took it out)
    }
    let mut lost = 0;
    if banner(i) && bearer_dead(i) {
        let us = &statics[state.roster.profile[i]];
        lost = (state.morale_bonus[i] - us.ctx.morale_rating).clamp(0, BANNER_MORALE_BONUS);
        if lost > 0 {
            ctx.morale_bonus -= lost;
            let line = format!("Banner: {shown}'s bearer (the last model carries it - no per-model data) is dead - no +{lost}");
            shot.log.push(line.clone());
            say_rule(tray, "banner", state.player[i], || line);
        }
    }
    if let Some(k) = command_lender(state, i, "Banner") {
        let name = &statics[state.roster.profile[k]].name;
        if bearer_dead(k) || state.alive[k] == 0 {
            let line = format!("Banner (from {name}): its bearer is dead - {shown}'s morale test gets no +{BANNER_MORALE_BONUS}");
            shot.log.push(line.clone());
            say_rule(tray, "banner", state.player[i], || line);
        } else {
            ctx.morale_bonus += BANNER_MORALE_BONUS;
            let line = format!("Banner (from {name}, the last model carries it - no per-model data): {shown} gets +{BANNER_MORALE_BONUS} to its morale test roll (passes on {}+)",
                morale_target(ctx.quality, ctx.morale_bonus));
            shot.log.push(line.clone());
            say_rule(tray, "banner", state.player[i], || line);
        }
    }
    lost
}

/// The table's lines before the test die (`_solo_morale_test`), for a unit that rolls one: the rating and the Banner family name the
/// bonus they add (the bonus is the stamped share minus what a cause or the Valiant band took back out, so spell tokens stay out of
/// it), then the live spell tokens ("<spell> +1: ... passes on N+"), a Great Banner token left out when a rule forced the test.
/// The target is the one the die is rolled against. Shared by the ordinary test and the Mind Control family's.
#[allow(clippy::too_many_arguments)]
fn say_morale_bonus(
    statics: &[UnitStatic], state: &State, i: usize, melee: bool, cause: Option<&str>, seams: Seams, ctx: &Ctx, banner_dropped: i64, tray: &mut Tray,
) {
    if tray.feed().is_none() {
        return;
    }
    let us = &statics[state.roster.profile[i]];
    let shown = &statics[state.roster.profile[morale_root(state, i, seams)]].name;
    if unit_shaken(state, i, seams) {
        return; // a Shaken unit rolls no die and the table writes no bonus line (its "already Shaken" line is the caller's)
    }
    let target = morale_target(ctx.quality, ctx.morale_bonus);
    let bonus = state.morale_bonus[i] - banner_gone(statics, state, i, seams) - banner_dropped;
    if bonus > 0 {
        say_rule(tray, "morale", state.player[i], || format!("{}: {shown} gets +{bonus} to morale test rolls (passes on {target}+)",
            morale_bonus_source(us, bonus)));
    }
    let skip_great = cause.is_some() && rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36);
    let tokens = mods::morale_tokens(state, i, melee).into_iter().filter(|(n, _)| !(skip_great && &**n == "Great Banner")).collect::<Vec<_>>();
    let spell: i64 = tokens.iter().map(|t| t.1).sum();
    if spell != 0 {
        let notes = tokens.iter().map(|(n, m)| format!("{n} {m:+}")).collect::<Vec<_>>().join(", ");
        say_rule(tray, "morale", state.player[i], || format!("{notes}: {spell:+} to morale test rolls — {shown} passes on {target}+"));
    }
}

/// The name the table's "gets +N to morale test rolls" line puts in front of the colon: the Morale(X) rating when the
/// unit has one, the Banner-family source otherwise, both joined by " + " when the bonus exceeds the rating alone.
fn morale_bonus_source(us: &UnitStatic, bonus: i64) -> String {
    let family = if us.morale_family.is_empty() { "Banner" } else { us.morale_family.as_str() };
    let rating = us.ctx.morale_rating;
    if rating <= 0 {
        return family.to_string();
    }
    if bonus > rating { format!("Morale({rating}) + {family}") } else { format!("Morale({rating})") }
}

/// `main._solo_morale_test` :8305 on the played path — the tray twin of
/// `morale_fails_expected`, with No Retreat's self-wounds landed regen-free
/// ("can't be ignored") and the Rout half clearing the unit off the board
/// exactly as `expected_melee_morale` does. A test shooting or melee caused.
#[allow(clippy::too_many_arguments)] // the cause/distance flags join the existing parity args
fn tray_morale(
    state: &mut State,
    statics: &[UnitStatic],
    i: usize,
    melee: bool,
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
    over_in: Option<f64>,
    charge_from_in: Option<f64>,
) {
    tray_morale_for(state, statics, i, melee, true, None, seams, tray, shot, over_in, charge_from_in);
}

/// `tray_morale` with its cause: `None` = shooting or melee, `Some(rule)` =
/// any other rule that forced the test (`drop_banner_for_cause`).
#[allow(clippy::too_many_arguments)]
pub(crate) fn tray_morale_for(
    state: &mut State, statics: &[UnitStatic], i: usize, melee: bool, charged_by_enemy: bool,
    cause: Option<&str>, seams: Seams, tray: &mut Tray, shot: &mut ShootResult,
    over_in: Option<f64>, charge_from_in: Option<f64>,
) {
    if !morale_side_alive(state, i, seams) {
        return;
    }
    let us = &statics[state.roster.profile[i]];
    // The table's test is about the unit that was aimed at: a lone hero's lines and die labels name its host.
    let shown = &statics[state.roster.profile[morale_root(state, i, seams)]].name;
    let mut ctx = live_morale_ctx(statics, state, i, melee, seams, shot, tray);
    ctx.side = state.player[i]; // the seat the morale dice lines (Fearless, No Retreat) are said for
    let banner_dropped = drop_banner_for_cause(statics, state, i, melee, charged_by_enemy, cause, over_in, charge_from_in, seams, &mut ctx, shot, tray);
    let banner_dropped = banner_dropped + command_banner(statics, state, i, cause, seams, &mut ctx, shot, tray);
    // G4R4 C-LONEHERO-SHAKEN: the unit's flag, the dead host's included (rules-must-log names the Shaken rule).
    let shaken = unit_shaken(state, i, seams);
    if shaken && !state.shaken[i] {
        let host = &statics[state.roster.profile[morale_root(state, i, seams)]].name;
        shot.log.push(format!("Shaken: {} is the unit of its dead host {host}, which is Shaken — the test fails without a die", us.name));
    }
    if shaken {
        // The table's `_solo_morale_test` says it before the outcome line: a lone hero's test is its host's (the unit it was aimed at).
        say_rule(tray, "morale", state.player[i], || format!("{shown} is already Shaken — automatically fails morale ({CITE})"));
    }
    // EPOCH_39_MORALE_RATING — rules-must-log (main.gd:8596-8602): the test
    // that adds the rating names it, once per drawn die. A Shaken auto-fail
    // draws no die and adds nothing, so it stays silent.
    if us.ctx.morale_rating > 0 && !shaken {
        shot.log.push(format!(
            "[Morale({})] {}: +{} to the morale test (passes on {}+)",
            us.ctx.morale_rating,
            us.name,
            us.ctx.morale_rating,
            morale_target(ctx.quality, ctx.morale_bonus)
        ));
    }
    say_morale_bonus(statics, state, i, melee, cause, seams, &ctx, banner_dropped, tray);
    // main.gd:8303 — the test die spends the morale once-mods it just used.
    // Placed after the call because `ctx` already carries the target it built.
    let (outcome, r) = crate::dice::resolve_morale_with_tray(
        &ctx,
        &us.name,   // the dice row keeps the roller's own name; the door's label shows the host (core_activation.gd `_shown_owner`)
        Some(i),
        melee,
        below_half(state, statics, us, i, seams),
        shaken,
        // `SoloController.wounds_to_destroy` :6084 also counts the attached
        // heroes' models; this port counts the unit's own wounds, which is the
        // die COUNT of a No Retreat roll and nothing else.
        wounds_left(state, i),
        tray,
    );
    // Rules 3.6 rules-must-log (main.gd `_solo_morale_test`): a unit Fearless by MOST of its models names the
    // count when it draws the recovery die - the die follows the test die, or stands alone for a Shaken unit.
    if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) && ctx.fearless && r.rolls.len() > usize::from(!shaken) {
        let (with, total) = fearless_models(statics, state, i, seams);
        if with < total {
            shot.log.push(format!("Fearless: {with} of {total} models of {} have it — most do, so the whole unit counts", us.name));
            say_rule(tray, "morale", state.player[i], || format!("Fearless: {with} of {total} models of {} have it — most do, so the whole unit counts", us.name));
        }
    }
    // EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF: an auto-failed test (no die) spends no once morale buff (table `_solo_morale_test`, #2804).
    if !(shaken && rule_on(seams.rules_epoch, crate::acts::EPOCH_81_SHAKEN_KEEPS_MORALE_BUFF)) {
        mods::spend_once_except(state, i, &[mods::Role::Morale], melee, |r| {
            cause.is_some() && rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36)
                && &*r.name == "Great Banner"
        });
    }
    let self_wounds = shot.absorb(r);
    land_wounds_with(state, i, self_wounds, seams.tray_exact, seams.rules_epoch);
    // One-core P3 step 26: the table's outcome line after the last morale die (`_solo_morale_test`'s match,
    // main.gd:13170-13184); its dice line stays the tray's. Every cause reaches that one match on the table.
    tray.say(|| LogLine { rule: "morale", category: Category::Combat, side: state.player[i], text: match outcome {
        Morale::Passed => format!("{shown} passes morale"),
        Morale::Shaken => format!("{shown} fails morale — Shaken"),
        Morale::Routed => format!("{shown} fails morale at half strength — ROUTS"),
    }, detail: None });
    // No Retreat's self-wounds land before the table writes its outcome: the landing report that follows this test says
    // their wound and loss lines ahead of this line (a rout's removal, which follows the outcome, holds nothing).
    if self_wounds > 0 {
        tray.hold_outcome();
    }
    match outcome {
        Morale::Passed => {}
        Morale::Shaken if seams.hero_attach && rule_on(seams.rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) => {
            // The table's Shaken outcome: a unit that is not Shaken yet (the lone hero's own flag decides) gets the flag on the unit the volley
            // named (its host, a dead one for a lone hero), mirrored onto every joined hero (`_solo_mirror_shaken`); each member drops what it carries.
            let unit = morale_root(state, i, seams);
            if !state.shaken[i] {
                for u in std::iter::once(unit).chain(state.attached[unit].clone()) {
                    state.shaken[u] = true;
                    drop_carried(state, u);
                }
            }
        }
        Morale::Shaken => {
            state.shaken[i] = true;
            drop_carried(state, i);
        }
        Morale::Routed => {
            // R3-C3 (`EPOCH_73_V36`, the Hero rule): a rout destroys the whole chain, the living joined heroes too.
            let mut gone = vec![i];
            if seams.hero_attach && rule_on(seams.rules_epoch, EPOCH_73_V36) {
                gone.extend(state.attached[i].iter().copied().filter(|&h| state.alive[h] > 0));
            }
            for &u in &gone {
                drop_carried(state, u);
                state.wounds[u].clear();
                state.positions[u].clear();
                Rc::make_mut(&mut state.radii)[u].clear();
                state.kits_drop(u);
                state.alive[u] = 0;
                if u != i {
                    shot.log.push(format!("Routed: {} is destroyed with {}", statics[state.roster.profile[u]].name, us.name));
                }
            }
        }
    }
}

/// E-24 (`main._solo_confirm_strike_back`): the defender's owner decides ONCE per melee whether it strikes back (the Counter
/// phase, else the strike-back slot); `decided` keeps the answer. Only a transcript that names `strike_back:<charger>:<defender>`
/// asks: an answer is said in the table's words, no answer (or only asked) strikes back, the AI's rule (Solo & Co-Op p.57).
fn strike_back_answer(next: &State, si: usize, ti: usize, tname: &str, tray: &mut Tray, decided: &mut Option<bool>) -> bool {
    if let Some(d) = *decided {
        return d;
    }
    let id = format!("strike_back:{}:{}", next.key(si), next.key(ti));
    let answer = tray.strike_back(&id, next.key(ti));
    if let Some(yes) = answer {
        say_melee(tray, next.player[ti], if yes { format!("{tname} strikes back") } else { format!("{tname} holds — no strike back") });
    }
    let d = answer.unwrap_or(true);
    *decided = Some(d);
    d
}

/// The whole CHARGE melee on the tray — `main._solo_resolve_ai_charge`
/// :8039-8118 in its own order: Counter's pre-phase (flagged), Impact (:8067),
/// the charger's strikes (:8081), the strike-back (:8100), the melee result
/// (:8110). UNWIELDY swaps the charger BEHIND the strike-back (:8073-8078);
/// Counter and Impact keep their slots either way.
///
/// Returns the loser of the melee — the destroyed side from epoch 65, else
/// the side that caused fewer wounds (Fear(X) adds to the score only).
/// `None` on a live tie or mutual wipe: nobody tests. From `EPOCH_73_V36` the side
/// that TOOK more wounds in the activation loses; `charger_self_wounds` is what
/// the charger's own Dangerous test cost it on the charge move.
#[cfg(test)]
#[allow(clippy::too_many_arguments)]
fn tray_charge(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    ti: usize,
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
    charge_from_in: f64,
    cover: Cover,
) -> Option<usize> {
    tray_charge_with_self_wounds(statics, next, si, ti, seams, tray, shot, charge_from_in, cover, 0, 0, 0)
}

#[allow(clippy::too_many_arguments)]
fn tray_charge_with_self_wounds(
    statics: &[UnitStatic],
    next: &mut State,
    si: usize,
    ti: usize,
    seams: Seams,
    tray: &mut Tray,
    shot: &mut ShootResult,
    charge_from_in: f64,
    cover: Cover,
    charger_self_wounds: i64,
    pre_melee_su: i64,
    pre_melee_tu: i64,
) -> Option<usize> {
    let mut charger_self_wounds = charger_self_wounds;
    let mut defender_self_wounds = 0;
    let regen_ignored_before = shot.regen_ignored;
    // The table's announce line (`_solo_show_attack_announce`), after the pile-in and before any strike.
    let (sname, tname) = (statics[next.roster.profile[si]].name.clone(), statics[next.roster.profile[ti]].name.clone());
    say_melee(tray, next.player[si], format!("{sname} charges {tname}"));
    let strikes_first =
        |u: usize| statics[next.roster.profile[u]].melee.iter().any(|p| p.counter && p.counter_strikes_first.unwrap_or(true));
    // The table asks the host AND its living attached heroes (`_solo_has_counter`, main.gd:7050);
    // tray-exact reads the heroes too, the old read sees the host only.
    let hero_counter = next.attached[ti].iter().any(|&h| next.alive[h] > 0 && strikes_first(h));
    let epoch13 = rule_on(seams.rules_epoch, EPOCH_13_WHO_WINS);
    if (!epoch13 && strikes_first(ti)) || (hero_counter && !seams.tray_exact) {
        // :8055-8059 — a Counter weapon runs a WHOLE extra strike phase before
        // Impact, and strips Impact dice with it: unported below 13, and for a
        // joined hero's Counter without tray_exact.
        shot.mark("counter_strikes_first");
    }
    // Audit 2026-09-13 §2.2, strike-order half — main.gd:8268-8274: at the
    // CURRENT epoch the defender's Counter weapons run a whole COUNTER_ONLY
    // strike phase BEFORE Impact, counted into the defender's tally; only
    // the NON-counter weapons remain for the normal strike-back slot
    // (:8315). Below the epoch the core keeps its marker-only reading.
    let v36 = rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36);
    let wants_first = strikes_first(ti) || (seams.tray_exact && hero_counter);
    let counter_blocked = v36 && (next.fatigued[ti] || next.shaken[ti]);
    let counter_first = epoch13 && wants_first && !counter_blocked;
    if v36 && epoch13 && wants_first {
        let name = &statics[next.roster.profile[ti]].name;
        if counter_blocked {
            let line = format!("Counter: {name} is Fatigued - no strike-first");
            say_melee(tray, next.player[ti], line.clone());
            shot.log.push(line);
        } else {
            shot.log.push(format!("Counter: {name} strikes first"));
        }
    }
    // Rules 3.6 (`EPOCH_73_V36`, table twin `_run_ai_melee`/`_run_human_melee`): Impact rolls before
    // either side strikes, so it moves ahead of the Counter phase, which keeps its alive gates (an
    // Impact wipe leaves none). The Counter cut of the Impact dice is read before any strike either way.
    let impact_first = rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36);
    let mut by_su = 0;
    let mut by_tu = 0;
    // SHO-15b Scourge: phantom wounds each side SUFFERED this melee, added to
    // the enemy's winner tally at EPOCH_73_V36 only.
    let mut scourge_on_charger = 0;
    let mut scourge_on_defender = 0;
    if impact_first && side_up(next, si, seams) && next.alive[ti] > 0 {
        by_su += impact_phase(statics, next, si, ti, tray, shot, seams.rules_epoch, charge_from_in, seams.tray_exact);
    }
    let mut strikes_back = None;
    if counter_first && side_up(next, si, seams) && side_up(next, ti, seams) {
        if !strike_back_answer(next, si, ti, &tname, tray, &mut strikes_back) {
            say_melee(tray, next.player[ti], format!("Counter: {tname} declines to strike first"));
        } else {
            if impact_first {
                say_melee(tray, next.player[ti], format!("Counter: {tname} strikes first, after the Impact dice ({CITE})"));
            }
            let (c, rc, h, s) = strike_phase(statics, next, ti, si, false, 0.0, seams, tray, shot, StrikeSet::CounterOnly, cover);
            by_tu += c;
            by_su += rc;
            defender_self_wounds += h;
            scourge_on_charger += s;
        }
    }
    // main.gd:8276's alive gate — a counter phase that wiped the charger
    // closes the card, nothing left to roll.
    if !impact_first && side_up(next, si, seams) && next.alive[ti] > 0 {
        by_su += impact_phase(statics, next, si, ti, tray, shot, seams.rules_epoch, charge_from_in, seams.tray_exact);
    }
    // main.gd:8035 — the charger's Mark lands after Impact and before the
    // strikes, measured at 0" (the two units are in base contact).
    tray_vs_marks(statics, next, si, ti, 0.0, seams, tray, shot);
    let charger_last = charger_strikes_last(statics, next, si, seams);
    let charger_static = &statics[next.roster.profile[si]];
    if charger_last && rule_on(seams.rules_epoch, EPOCH_73_V36) {
        shot.log.push(format!("Unwieldy: {} strikes last on the charge", charger_static.name));
        say_melee(tray, next.player[si], format!("Unwieldy: {} strikes last on the charge", charger_static.name));
    } else if charger_static.ctx.unwieldy_mixed {
        shot.log.push(format!("Unwieldy: {} has it on some weapons only - normal strike order (per-weapon order not modelled)", charger_static.name));
        say_melee(tray, next.player[si], format!("Unwieldy: {} has it on some weapons only - normal strike order (per-weapon order not modelled)", charger_static.name));
    }
    let strike_back_set = if counter_first { StrikeSet::NonCounter } else { StrikeSet::All };
    for slot in 0..2 {
        if (slot == 0) != charger_last {
            // :8079 — the charger strikes only while BOTH sides still stand;
            // an Impact pool that wiped the defender ends the melee here.
            if side_up(next, si, seams) && next.alive[ti] > 0 {
                // R3-X2a (`EPOCH_73_V36`, lead ruling 2): the charger's host died in its Dangerous test, a joined hero stands.
                if let Some(h) = next.attached[si].iter().copied().find(|&h| next.alive[h] > 0).filter(|_| next.alive[si] <= 0) {
                    shot.log.push(format!("Hero: {} has no models left - {} charges on as the unit",
                        statics[next.roster.profile[si]].name, statics[next.roster.profile[h]].name));
                }
                // B13: the defender's lash-back credits ITS OWN tally (by_tu).
                let (c, rc, h, s) = strike_phase(statics, next, si, ti, true, charge_from_in, seams, tray, shot, StrikeSet::All, cover);
                by_su += c;
                by_tu += rc;
                charger_self_wounds += h;
                scourge_on_defender += s;
                set_melee_fatigue(next, si, seams);
            }
        } else if side_up(next, ti, seams) && side_up(next, si, seams) {
            // :8100 — and so does the strike-back, in both directions.
            // B13: the strike-back's lash-back credits the charger's tally.
            // MEL-PAR-B14 (`EPOCH_73_V36`, main.gd:10817-10823): a defender with no melee weapon at
            // all does not strike back and takes no phantom fatigue — the rule logs itself instead.
            if rule_on(seams.rules_epoch, EPOCH_73_V36) && chain_has_no_melee(statics, next, ti) {
                shot.log.push(format!(
                    "{} has no melee weapons - cannot strike back",
                    statics[next.roster.profile[ti]].name
                ));
                say_melee(tray, next.player[ti], format!("{} has no melee weapons — cannot strike back ({CITE})", statics[next.roster.profile[ti]].name));
            } else if strike_back_answer(next, si, ti, &tname, tray, &mut strikes_back) {
                // R3-C1 (`EPOCH_73_V36`, the Hero rule): the host's models are gone, a joined hero stands - it strikes back.
                if let Some(h) = next.attached[ti].iter().copied().find(|&h| next.alive[h] > 0).filter(|_| next.alive[ti] <= 0) {
                    shot.log.push(format!("Hero: {} has no models left - {} strikes back for the unit",
                        statics[next.roster.profile[ti]].name, statics[next.roster.profile[h]].name));
                }
                let (c, rc, h, s) = strike_phase(statics, next, ti, si, false, 0.0, seams, tray, shot, strike_back_set, cover);
                by_tu += c;
                by_su += rc;
                defender_self_wounds += h;
                scourge_on_charger += s;
                set_melee_fatigue(next, ti, seams);
            }
        }
    }
    // Block C4 — the survival half, the table's own order (main.gd:8431-8433):
    // the charger's carriers detonate first, then the defender's — AFTER both
    // sides have finished attacking, BEFORE the melee result / morale test.
    self_destruct_post_melee(statics, next, si, ti, seams, tray, shot);
    self_destruct_post_melee(statics, next, ti, si, seams, tray, shot);
    let mut a = by_su + chain_fear(statics, next, si, seams);
    let mut b = by_tu + chain_fear(statics, next, ti, seams);
    // Rules 3.6 (`EPOCH_73_V36`): the loser TOOK more wounds, so each side scores what its ENEMY took: wounds dealt, the
    // Fear it bears and the enemy's own self-wounds (the twin rolls no Hazardous, so only the charger adds any).
    if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
        b += charger_self_wounds + pre_melee_su;
        a += defender_self_wounds + pre_melee_tu;
        // SHO-15b Scourge: phantom wounds a side's blocks earned count as wounds it TOOK, so they lift the enemy's
        // tally. The verdict without them names whether they decided this melee.
        let (a_base, b_base) = (a, b);
        a += scourge_on_defender;
        b += scourge_on_charger;
        let loser_without = melee_loser(next, si, ti, a_base, b_base, seams);
        let loser_with = melee_loser(next, si, ti, a, b, seams);
        // The table's result line (`_solo_log_melee_result`): what each side TOOK = the enemy's score, with the Fear
        // and self-inflicted parts named. The Regeneration note is said; the Scourge notes are not (that rule stays off the door).
        let tally = |struck: i64, taken: i64, fear: i64| {
            let mut extra = Vec::new();
            if fear > 0 { extra.push(format!("Fear: {fear}")); }
            if taken - struck - fear > 0 { extra.push(format!("self-inflicted: {}", taken - struck - fear)); }
            if extra.is_empty() { taken.to_string() } else { format!("{taken} ({})", extra.join(", ")) }
        };
        let verdict = match loser_with {
            Some(l) => format!("{} loses the melee", statics[next.roster.profile[l]].name),
            None if combined_alive(next, si, seams) <= 0 && combined_alive(next, ti, seams) <= 0 => "both destroyed — no morale test".into(),
            None => "a draw — no morale test".into(),
        };
        // MEL-10r: only when Regeneration cancelled a wound that would have counted (`_solo_log_melee_result`).
        let cancelled = shot.regen_ignored - regen_ignored_before;
        let regen_note = if cancelled > 0 { format!(" ({cancelled} wound{} cancelled by Regeneration {} not count)", if cancelled == 1 { "" } else { "s" }, if cancelled == 1 { "does" } else { "do" }) } else { String::new() };
        let text = format!("Melee result: {sname} took {}, {tname} took {} — {verdict}{regen_note}",
            tally(by_tu, b, chain_fear(statics, next, ti, seams)), tally(by_su, a, chain_fear(statics, next, si, seams)));
        say_melee(tray, next.player[si], text);
        shot.log.push(format!(
            "[Melee result] {} took {b} wounds, {} took {a} (Fear and self-inflicted wounds count)",
            statics[next.roster.profile[si]].name, statics[next.roster.profile[ti]].name
        ));
        for (n, unit) in [(scourge_on_defender, ti), (scourge_on_charger, si)] {
            if n > 0 {
                let decides = loser_with == Some(unit) && loser_without != Some(unit);
                // tray twin: melee
                shot.log.push(format!(
                    "Scourge: {n} phantom wounds count for {} in the melee result — they {}",
                    statics[next.roster.profile[unit]].name,
                    if decides { "decide it" } else { "do not decide it" }
                ));
            }
        }
        // The table's `_solo_log_melee_result` says the notes right after the result line, the charger's side first.
        for (n, unit) in [(scourge_on_charger, si), (scourge_on_defender, ti)] {
            if n > 0 {
                let decides = loser_with == Some(unit) && loser_without != Some(unit);
                say_melee(tray, next.player[si], format!(
                    "Scourge: {n} phantom wounds count for {} in the melee result — they {}",
                    statics[next.roster.profile[unit]].name,
                    if decides { "decide it" } else { "do not decide it" }));
            }
        }
    }
    melee_loser(next, si, ti, a, b, seams)
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

/// G4-C11 (`EPOCH_73_V36`) — a charge NAMED at a host with no models left while a joined hero lives: the chain's models are
/// the hero's now (the Hero rule: the hero is the unit once its host is gone, and the table's `_solo_combined_alive`
/// still counts the unit), so the melee, which guards on `alive[ti]`, runs against the first living attached hero.
/// `None` for every other target.
fn lone_hero_of(state: &State, ti: usize, seams: Seams) -> Option<usize> {
    if !seams.hero_attach || !rule_on(seams.rules_epoch, EPOCH_73_V36) || state.alive[ti] > 0 {
        return None;
    }
    state.attached[ti].iter().copied().find(|&h| state.alive[h] > 0)
}

/// The table's executed-move stamp (`_solo_animate_move`): the host's `moved_round`, and from `EPOCH_94_PARITY_BATCH` the living
/// joined heroes' too (their models are in the move paths, the stamp goes to the unit of each model).
pub(crate) fn stamp_moved(state: &mut State, si: usize, hero_attach: bool, rules_epoch: u32) {
    state.moved_round[si] = state.round;
    if hero_attach && rule_on(rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) {
        for h in state.attached[si].clone() {
            if state.alive[h] > 0 {
                state.moved_round[h] = state.round;
            }
        }
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

/// The obstacle models of one `spacing_fraction` call in capture order, plus one box per unit: `spans[g] = (end, [min x, max x,
/// min z, max z] of the centres, largest radius + buffer)`. `legal` skips a whole unit when on one axis the gap between its box and
/// the box of the mover models exceeds `r + own_r + SPACING_SKIP_MARGIN_M`: `length(flat)` is at least `|flat.x|` and `|flat.z|`,
/// and the margin dominates the f32 error of the subtraction (< 6e-5 m inside the +-1e3 m envelope), so no pair of that unit can
/// compare below. Boxes outside the envelope (or not finite) and units 64 and up are never skipped.
#[derive(Default)]
struct SpacingObstacles {
    list: Vec<(geom::V3, f64)>,
    spans: Vec<(usize, [f32; 4], f64)>,
}

const SPACING_SKIP_MARGIN_M: f64 = 1e-3;
const SPACING_ENVELOPE_M: f32 = 1.0e3;

impl SpacingObstacles {
    /// Close the unit whose models were pushed since the last call (a unit without models adds no span).
    fn end_unit(&mut self) {
        let from = self.spans.last().map_or(0, |s| s.0);
        let (mut b, mut rm) = ([f32::INFINITY, f32::NEG_INFINITY, f32::INFINITY, f32::NEG_INFINITY], f64::NEG_INFINITY);
        for (c, r) in &self.list[from..] {
            (b, rm) = ([b[0].min(c[0]), b[1].max(c[0]), b[2].min(c[2]), b[3].max(c[2])], rm.max(*r));
        }
        if self.list.len() > from {
            self.spans.push((self.list.len(), b, rm));
        }
    }

    /// Bit `g` is clear when unit `g` (< 64) cannot touch any mover model (`own` = f32 centre, radius) moved by `step`.
    fn live(&self, own: &[(geom::V3, f64)], step: geom::V3) -> u64 {
        let (mut lo, mut hi, mut ro) = ([f32::INFINITY; 2], [f32::NEG_INFINITY; 2], f64::NEG_INFINITY);
        for (p, r) in own {
            let c = geom::add(*p, step);
            (lo, hi, ro) = ([lo[0].min(c[0]), lo[1].min(c[2])], [hi[0].max(c[0]), hi[1].max(c[2])], ro.max(*r));
        }
        let inside = |v: &[f32]| v.iter().all(|x| x.abs() <= SPACING_ENVELOPE_M);
        let mut live = u64::MAX;
        if inside(&lo) && inside(&hi) {
            for (g, (_, b, rm)) in self.spans.iter().enumerate().take(64) {
                let far = |gap: f32| f64::from(gap) > rm + ro + SPACING_SKIP_MARGIN_M;
                if inside(b) && (far(b[0] - hi[0]) || far(lo[0] - b[1]) || far(b[2] - hi[1]) || far(lo[1] - b[3])) {
                    live &= !(1u64 << g);
                }
            }
        }
        live
    }

    /// `true` when no mover model moved by `step` is within `r + own_r` of any obstacle model.
    fn legal(&self, own: &[(geom::V3, f64)], step: geom::V3) -> bool {
        let live = self.live(own, step);
        for (p, own_r) in own {
            let q = geom::add(*p, step);
            let mut from = 0;
            for (g, (end, _, _)) in self.spans.iter().enumerate() {
                if g >= 64 || live >> g & 1 == 1 {
                    for (oc, r) in &self.list[from..*end] {
                        let flat: geom::V3 = [q[0] - oc[0], 0.0, q[2] - oc[2]];
                        if (geom::length(flat) as f64) < r + own_r {
                            return false;
                        }
                    }
                }
                from = *end;
            }
        }
        true
    }
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
    let mut obstacles = SpacingObstacles::default();
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
            obstacles.list.push((geom::to_f32(*pos), r + o_buffer));
        }
        obstacles.end_unit();
    }
    if obstacles.list.is_empty() {
        return 1.0;
    }
    let own: Vec<(geom::V3, f64)> = (state.positions[mi].iter().enumerate())
        .map(|(i, p)| (geom::to_f32(*p), state.radii[mi].get(i).copied().unwrap_or(DEFAULT_BASE_RADIUS_M)))
        .collect();
    let legal = |t: f64| obstacles.legal(&own, geom::mul(delta, t));
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
/// WALLS: built with an empty wall list, so Impassable CELLS are the only hard
/// obstacle the imagination sees. `walled_reach_index_for_state` is the sibling
/// that also blocks on the board's ruin walls.
pub fn reach_index_for_state(state: &State, terrain: &Terrain) -> Option<ReachIndex> {
    reach_index_with_walls(state, terrain, &[])
}

/// MEL-PAR-F8 — `reach_index_for_state` plus the board's ruin walls
/// (`Terrain::walls_in`) as impassable segments, the way the table's charge
/// move treats them. Only the menu's charge path check (`charge_needs_path`)
/// asks for it; every other planner user keeps the wall-less index.
pub fn walled_reach_index_for_state(state: &State, terrain: &Terrain, rules_epoch: u32) -> Option<ReachIndex> {
    reach_index_with_walls(state, terrain, terrain.walls_in_at(rules_epoch)) // from EPOCH_94_PARITY_BATCH the cliffs too
}

fn reach_index_with_walls(state: &State, terrain: &Terrain, walls: &[crate::mv::cost::Wall]) -> Option<ReachIndex> {
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
    let mut b = ReachBuild::new(board, walls);
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
/// prices at 0, so it simply takes the nearest. Rules 3.6 (D-SPELL-LOS): from
/// `EPOCH_73_V36` sight binds only when the entry's own `needs_los` says so;
/// below the epoch every spell still needs it.
// The rules epoch is threaded from the frozen seams, not held globally.
#[allow(clippy::too_many_arguments)]
fn best_spell_target(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    entry: &Spell,
    los: &[bool],
    origins: &[(usize, i64)],
    rules_epoch: u32,
) -> Option<(usize, usize)> {
    let player = state.player[si];
    let sight_required = !rule_on(rules_epoch, EPOCH_73_V36) || entry.needs_los;
    let mut best: Option<(usize, usize)> = None;
    let mut best_ev = -1.0f64;
    let mut best_d = f64::INFINITY;
    for ti in 0..state.units() {
        if state.player[ti] == player || state.alive[ti] <= 0 {
            continue;
        }
        // The official walk (spell_candidates, PR 1's twin): the FIRST
        // origin in walk order that reaches the target is the cast's
        // origin for it — walk and break, no EV-shopping over origins.
        let mut reach: Option<(usize, f64)> = None;
        for &(ou, _) in origins {
            let seen = if !sight_required {
                true
            } else if ou == si {
                state.sees_idx(si, ti) && los[ti]
            } else {
                state.sees_idx(ou, ti) && state.los_clear(ou, ti)
            };
            if !seen {
                continue;
            }
            let d = geom::dist_in(&state.positions[ou], &state.positions[ti]);
            if d > entry.range_in + CONTROL_EPS {
                continue;
            }
            reach = Some((ou, d));
            break;
        }
        let Some((ou, d)) = reach else { continue; };
        let ut = &statics[state.roster.profile[ti]];
        let ev = spell_damage_ev_of(entry, &ctx_of(ut, state, ti), rules_epoch);
        if ev > best_ev + CONTROL_EPS || ((ev - best_ev).abs() <= CONTROL_EPS && d < best_d) {
            best_ev = ev;
            best_d = d;
            best = Some((ti, ou));
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
    origins: &[(usize, i64)],
    rules_epoch: u32,
) -> Option<(usize, usize, usize)> {
    for idx in official_pick_order(spells.len(), d3, caster_x) {
        let entry = &spells[idx];
        if entry.status == "unmodeled" || entry.threshold > tokens {
            continue;
        }
        if entry.effect_kind == "buff" {
            return Some((idx, si, origins[0].0)); // a buff takes the caster itself
        }
        if entry.effect_kind == "utility" {
            // EPOCH_52_UTILITY_SPELLS: the MAPPED utility archetypes are
            // picked and stamped below; every other name still skips ("an
            // effect kind the sim has no arithmetic for").
            let Some(a) = crate::spell::utility_archetype_of(&entry.name) else {
                continue;
            };
            if !rule_on(rules_epoch, EPOCH_52_UTILITY_SPELLS) {
                continue;
            }
            if a.friendly() {
                return Some((idx, si, origins[0].0)); // a friendly utility takes the caster's unit
            }
            if let Some((ti, ou)) = best_spell_target(statics, state, si, entry, los, origins, rules_epoch) {
                return Some((idx, ti, ou)); // EV 0 -> the nearest enemy, like a debuff
            }
            continue;
        }
        if entry.effect_kind != "damage" && entry.effect_kind != "debuff" {
            continue; // an effect kind the sim has no arithmetic for
        }
        if let Some((ti, ou)) = best_spell_target(statics, state, si, entry, los, origins, rules_epoch) {
            return Some((idx, ti, ou));
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
    seams: Seams,
    rng: Option<&mut GodotRng>,
) {
    if entry.effect_kind == "utility" {
        apply_utility_effect(statics, state, ti, entry, scale);
        return;
    }
    if entry.effect_kind == "damage" {
        let ut = &statics[state.roster.profile[ti]];
        let ev = spell_damage_ev_of(entry, &ctx_of(ut, state, ti), seams.rules_epoch);
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
            ap_mod: 0,
            def_mod: 0,
            defense_mod: 0,
            move_mod: 0,
            range_in: 0,
            grants_rule: Rc::from(entry.grants_rule.as_str()),
            scope: Rc::from(""),
            attackers: entry.beneficiary == "attackers",
            once: true,
            name: Rc::from(""),
        });
        // Rules-must-log: the landing names the granted rule, like the utility pushes.
        trace_rule(
            "cast",
            &format!("Spell {} grant", entry.name),
            &format!(
                "{} granted to {} until the first exchange spends it",
                entry.grants_rule,
                statics[state.roster.profile[ti]].name
            ),
        );
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
        // EPOCH_62_CASTING_MOD: the debuff's cast-roll shift lands in its own
        // snapshot slot (gated — the `mods` record export must stay
        // byte-exact below the gate); `casting_net_of` folds it at read.
        if rule_on(seams.rules_epoch, EPOCH_62_CASTING_MOD) {
            mods.casting += scale * m.casting_mod;
        }
    }
    mods.morale += scale * m.morale_mod;
    mods.range_in += scale * m.range_in;
    mods.advance += scale * m.advance_in;
    mods.rush += scale * m.rush_in;
}

/// SEAM 5 (Utility SPELLS, CASTER_SEAM_2026-09-14.md row 5 + port 3) — the
/// mapped utility-kind cast lands (`spell::utility_archetype_of`, the frozen
/// `EPOCH_52_UTILITY_SPELLS`; the PICK already refused the unmapped names and
/// the below-51 epochs, so an entry here is an applied one). Grants and flags
/// land whole at cast success — the DEFECT_LEDGER #33 shape — and one
/// rules-must-log line names each applied effect.
fn apply_utility_effect(
    statics: &[UnitStatic],
    state: &mut State,
    ti: usize,
    entry: &Spell,
    scale: f64,
) {
    let Some(a) = crate::spell::utility_archetype_of(&entry.name) else {
        return;
    };
    if scale <= 0.0 {
        return;
    }
    match a {
        crate::spell::UtilityArchetype::TerrainHazard { dangerous } => {
            let rule: &'static str =
                if dangerous { "Dangerous Terrain" } else { "Difficult Terrain" };
            state.buffs[ti].push(mods::LiveMod {
                hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0,
                def_mod: 0, defense_mod: 0, move_mod: 0, range_in: 0,
                grants_rule: Rc::from(rule),
                scope: Rc::from(""),
                attackers: false,
                once: true,
                name: Rc::from(entry.name.as_str()),
            });
        }
        crate::spell::UtilityArchetype::FatigueOnFailedMorale => {
            state.fatigued[ti] = true;
        }
        crate::spell::UtilityArchetype::ApOwn { ap, scope } => {
            state.buffs[ti].push(mods::LiveMod {
                hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: ap,
                def_mod: 0, defense_mod: 0, move_mod: 0, range_in: 0,
                grants_rule: Rc::from(""),
                scope: Rc::from(scope),
                attackers: false,
                once: true,
                name: Rc::from(entry.name.as_str()),
            });
        }
    }
    trace_rule(
        "cast",
        &format!("Spell {}", entry.name),
        &format!("{} applied to {}", a.label(), statics[state.roster.profile[ti]].name),
    );
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
        // EPOCH_62_CASTING_MOD: the spell-side snapshot slot joins the ledger
        // walk — ROUNDED at read, the table's own shape (ai_spell.gd:105-130).
        if rule_on(seams.rules_epoch, EPOCH_62_CASTING_MOD) {
            let m = state.mods[u].casting.round() as i64;
            if m != 0 {
                net += m;
                trace_rule(
                    "cast",
                    "Casting modifier",
                    &format!(
                        "{:+} to {}'s cast target (casting_net now {net})",
                        m, statics[state.roster.profile[ci]].name
                    ),
                );
            }
        }
    }
    // MOR-15 — a WEAPON-borne "Spell Amplifier" lifts the CASTER'S own target
    // only (never the attached host's, never a conduit origin): the static is
    // stamped off `ci`'s profile and gated at `EPOCH_73_V36`.
    let amplifier = statics[state.roster.profile[ci]].spell_amplifier_casting_mod;
    if amplifier != 0 {
        net += amplifier;
        trace_rule(
            "cast",
            "Spell Amplifier",
            &format!(
                "{:+} to {}'s cast target (casting_net now {net})",
                amplifier, statics[state.roster.profile[ci]].name
            ),
        );
    }
    net
}

/// Spell Conduit (design #824 §4 PR 2) — the conduit half of the
/// cast-origin walk, PR 1's `battle_sim.gd _cast_origins` twin: every
/// friendly ALIVE "Spell Conduit" bearer within the rule's OWN `range_in`
/// of the CASTER, `requires_not_shaken` binding the CONDUIT; entries are
/// (origin unit, the rule's `casting_mod`). The gate is the FROZEN
/// EPOCH_8_PLANNER_MENU — the #838 epoch-8 ruling (the #831 call: a MENU
/// change is a NEW frozen gate), so every epoch-7 record replays with the
/// menu it was recorded with and the walk below 8 is empty — the set stays
/// [caster].
fn cast_origins(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    seams: Seams,
) -> Vec<(usize, i64)> {
    if !rule_on(seams.rules_epoch, EPOCH_8_PLANNER_MENU) {
        return Vec::new();
    }
    let player = state.player[si];
    let mut found: Vec<(usize, i64)> = Vec::new();
    for u in 0..state.units() {
        let s = &statics[state.roster.profile[u]];
        if !s.spell_conduit || u == si || state.player[u] != player || state.alive[u] <= 0 {
            continue;
        }
        if s.spell_conduit_needs_steady && state.shaken[u] {
            continue;
        }
        if geom::dist_in(&state.positions[si], &state.positions[u]) > s.spell_conduit_reach_in + CONTROL_EPS {
            continue;
        }
        found.push((u, s.spell_conduit_casting_mod));
    }
    found
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
pub(crate) fn cast_phase(
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
    // Wave 4 follow-up (port-spell-accumulator) — the EMPTY-POOL fallback:
    // at epoch 7 a chain caster with spells but no tokens still reaches the
    // battery pool below; pre-epoch records keep the early return.
    let ci = caster_of(statics, state, si, seams)
        .or_else(|| battery_chain_caster(statics, state, si, seams));
    let Some(ci) = ci else {
        return;
    };
    // Wave 4 follow-up (port-spell-accumulator) — the battery pool
    // (solo_controller.gd:4520-4548): every friendly, ALIVE, un-Shaken
    // `Spell Accumulator` bearer of ANOTHER unit within the rule's own 12"
    // joins the token pool, NEAREST first (the table's own sort). A battery
    // is never a real caster ("is_caster() stays false", game_unit.gd:417),
    // and the Shaken gate is the rule text's own "Friendly casters may only
    // use this rule if this unit isn't Shaken" (NML-936).
    let own = state.casts[ci];
    let lenders = battery_pool(statics, state, si, ci, seams);
    let tokens = own + lenders.iter().map(|(_, t)| *t).sum::<i64>();
    // Wave 6 (port-caster-boost) — the boost pool's helper half (the own
    // leftover joins the plan below, the FIRST source). Empty below the
    // frozen `EPOCH_48_CASTER_BOOST`.
    let helpers = caster_boost_pool(statics, state, si, ci, los, seams);
    // Wave 6 (port-caster-interference) — the OPPOSING casters' counter
    // pool, read ONCE with the boost purse (solo_controller.gd:4378-4386,
    // the both-AI auto-plan; empty below the frozen
    // `EPOCH_51_CASTER_INTERFERENCE`).
    let enemies = interference_pool(statics, state, si, ci, los, seams);
    let mut lend_log: Vec<String> = Vec::new();
    let pi = state.roster.profile[ci];
    let spells = statics[pi].spells.clone();
    // The PICK still starts from the host: `si` carries the models the buff
    // lands on and the `los` row the caller built, and p.14 makes the joined
    // hero part of that unit, so "buff myself" is the unit, not the hero.
    let caster_x = state.profile(ci).caster_value;
    let weight = 1.0 / 3.0;
    // Spell Conduit (design #824 §4 PR 2) — the origin walk, built ONCE
    // per cast phase (PR 1's battle_sim.gd `_cast_origins` twin); empty
    // below the frozen gate, so the set is the caster alone.
    let mut origins: Vec<(usize, i64)> = vec![(si, 0)];
    origins.extend(cast_origins(statics, state, si, seams));
    let mut cost: Option<i64> = None;
    // Wave 6 (port-caster-boost, port-caster-interference) — (boost, own
    // draw, helper draw, interference, post-boost target, final roll
    // target), planned ONCE at the first face that produces a pick (the
    // face that names the attempt and pays for it, like the threshold).
    let mut boost_plan: Option<(i64, i64, i64, i64, i64, i64)> = None;
    for d3 in 1..=3i64 {
        let Some((idx, ti, ou)) =
            pick_cast(statics, state, si, &spells, tokens, d3, caster_x, los, &origins, seams.rules_epoch)
        else { continue; };
        // The +1 rides the origin (design #824 §3): the conduit's
        // casting_mod folds in only when THIS cast is made through it.
        let origin_mod = origins.iter().find(|o| o.0 == ou).map_or(0, |o| o.1);
        let casting_net = casting_net_of(statics, state, ci, seams) + origin_mod;
        // The PLANNER prices the table's `priced_target` from 73 (MOR-15);
        // below the gate it stays blind (net 0) so every recorded corpus
        // keeps its exact boost/interference decision.
        let priced_net = if rule_on(seams.rules_epoch, EPOCH_73_V36) { casting_net } else { 0 };
        // Wave 6 (port-caster-boost) — the boost plan lands at the FIRST
        // pick; the purse was read once before the loop, so later faces
        // shop with (and roll with) the attempt's one boost decision.
        let plan = boost_plan
            .get_or_insert_with(|| {
                let (b, o, h) = if rule_on(seams.rules_epoch, EPOCH_48_CASTER_BOOST) {
                    plan_caster_boost(statics, state, si, &spells[idx], ti, own, &helpers, seams.rules_epoch, priced_net)
                } else {
                    (0, 0, 0)
                };
                // Wave 6 (port-caster-interference) — the counter plans
                // AGAINST the committed boost, at the cast's own EV (an
                // unpriced cast draws no counter, ai_spell.gd:518-527).
                let i = if rule_on(seams.rules_epoch, EPOCH_51_CASTER_INTERFERENCE) {
                    plan_interference(
                        cast_ev_of(statics, state, si, &spells[idx], ti, seams.rules_epoch),
                        enemies.iter().map(|(_, t)| *t).sum(),
                        b,
                        priced_net,
                    )
                } else {
                    0
                };
                (b, o, h, i,
                    (CAST_BASE_TARGET - casting_net - b).clamp(2, 6),
                    (CAST_BASE_TARGET - casting_net - b + i).clamp(2, 6))
            });
        let boost = plan.0;
        let p_success = cast_success_chance_vs(casting_net, boost, plan.3);
        // The cast ATTEMPT event, the table's own shape (battle_sim.gd `_cast_phase`):
        // the FIRST face's spell names it, and it is the only entry the
        // `_spells_by_kind_tally` counts (the log lines below carry no kind).
        if cost.is_none() {
            let mut ev = serde_json::json!({
                "spell": spells[idx].name, "kind": spells[idx].effect_kind,
                "cost": spells[idx].threshold, "target": state.roster.keys[ti],
                "p_success": p_success, "boost": boost, "interference": plan.3,
            });
            if ou != si {
                ev["origin"] = serde_json::json!({
                    "unit": state.roster.keys[ou],
                    "position": geom::centre(&state.positions[ou]),
                });
            }
            state.cast_events.push(Rc::new(ev));
        }
        if origin_mod != 0 {
            // Rules-must-log (#782), the table's own line shape (main.gd
            // `_solo_resolve_one_cast`).
            let line = format!(
                "Spell Conduit: {} casts as if standing at {} ({:+} to the cast target)",
                statics[state.roster.profile[ci]].name, statics[state.roster.profile[ou]].name, origin_mod
            );
            trace_rule("cast", "Spell Conduit", &line);
            state.cast_events.push(Rc::new(serde_json::json!({ "rule": "Spell Conduit", "log": line })));
        }
        apply_cast_effect(statics, state, ti, &spells[idx], weight * p_success, seams, rng.as_deref_mut());
        if cost.is_none() {
            cost = Some(spells[idx].threshold);
        }
    }
    if let Some(c) = cost {
        // Wave 4 follow-up (port-spell-accumulator) — the spend order: the
        // caster's OWN tokens first, then the batteries nearest-first; each
        // battery's draw names itself (rules-must-log, the table's
        // battery-join log).
        let mut left = c;
        let take_own = own.min(left);
        left -= take_own;
        state.casts[ci] = (own - take_own).max(0);
        for (u, t) in &lenders {
            if left <= 0 {
                break;
            }
            let take = (*t).min(left);
            left -= take;
            state.casts[*u] = (state.casts[*u] - take).max(0);
            let line = format!(
                "Spell Accumulator: {} lends {} token(s) to {}",
                statics[state.roster.profile[*u]].name, take, statics[state.roster.profile[ci]].name
            );
            lend_log.push(line.clone());
            state.cast_events.push(Rc::new(serde_json::json!({ "rule": "Spell Accumulator", "log": line })));
        }
        // Wave 6 (port-caster-boost) — the BOOST tokens ride the same spend
        // order: the caster's own leftover first, then the helpers
        // nearest-first — the table pays threshold + boost before the roll,
        // one try per spell (solo_controller.gd:4387-4395). Rules-must-log:
        // one line per cast that spent tokens (the brief's shape).
        if let Some((boost, bown, bhelp, _, target, _)) = boost_plan.filter(|p| p.0 > 0) {
            state.casts[ci] = (state.casts[ci] - bown).max(0);
            let mut bleft = bhelp;
            for (u, t) in &helpers {
                if bleft <= 0 {
                    break;
                }
                let take = (*t).min(bleft);
                bleft -= take;
                state.casts[*u] = (state.casts[*u] - take).max(0);
            }
            let note = if bhelp > 0 { aura_pool_note(seams.rules_epoch) } else { "" };
            let line = format!("Caster: {} tokens spent (own {}, helpers {}), target 4+ -> {}+{}", boost, bown, boost - bown, target, note);
            trace_rule("cast", "Caster", &line);
            state.cast_events.push(Rc::new(serde_json::json!({ "rule": "Caster", "log": line })));
        }
        // Wave 6 (port-caster-interference) — the OPPOSING casters' tokens
        // ride the same payment block, AFTER the boost (the table spends
        // boost_sources then interference_sources, all before the roll,
        // solo_controller.gd:4387-4397). Rules-must-log: one line per
        // interfered cast (the brief's own line shape).
        if let Some((_, _, _, inter, itarget, ifinal)) = boost_plan.filter(|p| p.3 > 0) {
            let mut ileft = inter;
            let mut from: Vec<&str> = Vec::new();
            for (u, t) in &enemies {
                if ileft <= 0 {
                    break;
                }
                let take = (*t).min(ileft);
                ileft -= take;
                state.casts[*u] = (state.casts[*u] - take).max(0);
                from.push(statics[state.roster.profile[*u]].name.as_str());
            }
            let line = format!(
                "Caster: interference {} tokens from {}, target {}+ -> {}+{}",
                inter, from.join(", "), itarget, ifinal, aura_pool_note(seams.rules_epoch)
            );
            trace_rule("cast", "Caster", &line);
            state.cast_events.push(Rc::new(serde_json::json!({ "rule": "Caster", "log": line })));
        }
    }
}

/// CC-5b/5c: how an offered cast ends. Before any die: its caster is down when the cast resolves (a Dangerous test, an earlier cast's
/// Hazardous), skipped silently as `_solo_resolve_ai_casts` does; no target stands, the cast fizzles. At the cast die: it fails, or it
/// succeeds: `Landed` = a damage spell's hits are saved and landed (CC-6a), `Hit` = the effect is CC-8b's (a buff or debuff), so the
/// step API refuses a `Hit` for now.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum CastEnd {
    Skipped,
    Fizzled,
    Failed,
    Hit,
    Landed,
}

/// CC-5b: `Some(end)` when `c` ends before any die in `state`; `None` = it goes on to the cast die.
pub(crate) fn cast_ends(state: &State, c: &CastInput) -> Option<CastEnd> {
    let at = |k: &String| state.roster.index.get(k.as_str()).copied();
    if at(&c.caster).is_none_or(|i| state.alive[i] <= 0) {
        return Some(CastEnd::Skipped);
    }
    c.targets.iter().filter_map(at).all(|t| state.alive[t] <= 0).then_some(CastEnd::Fizzled)
}

fn cast_say(tray: &mut Tray, side: i64, text: String) {
    tray.say(|| LogLine { rule: "cast", category: Category::Combat, side, text, detail: None });
}

fn spell_say(tray: &mut Tray, side: i64, text: String) {
    tray.say(|| LogLine { rule: "spell", category: Category::Combat, side, text, detail: None });
}

fn spend_cast_tokens(state: &mut State, c: &CastInput) {
    for (key, n) in std::iter::once((&c.caster, &c.threshold)).chain(c.boost_sources.iter().chain(&c.interference_sources).map(|(k, n)| (k, n))) {
        if let Some(&i) = state.roster.index.get(key.as_str()) {
            state.casts[i] = (state.casts[i] - (*n).max(0)).max(0);
        }
    }
}

/// CC-5d/9c: log Shaken Spell Accumulator batteries of `side` (`solo_controller.shaken_lenders`, table unit order).
fn say_shaken_batteries(statics: &[UnitStatic], state: &State, side: i64, tray: &mut Tray) {
    for cu in (0..state.units()).filter(|&u| state.player[u] == side && state.alive[u] > 0 && !state.dormant[u]) {
        for &m in std::iter::once(&cu).chain(&state.attached[cu]) {
            let s = &statics[state.roster.profile[m]];
            if state.alive[m] > 0 && !state.dormant[m] && state.casts[m] > 0 && !s.is_caster && state.shaken[m] && s.spell_accumulator {
                cast_say(tray, side, format!("Spell Accumulator: {} is Shaken \u{2014} its tokens do not feed friendly casters", s.name));
            }
        }
    }
}

/// CC-9c: whether `side` fields any living non-dormant caster with tokens left (`_solo_side_has_caster_tokens` main.gd:6471).
fn side_has_caster_tokens(statics: &[UnitStatic], state: &State, side: i64) -> bool {
    (0..state.units()).any(|u| {
        state.player[u] == side
            && state.alive[u] > 0
            && statics[state.roster.profile[u]].is_caster
            && state.casts[u] > 0
    })
}

/// CC-5c/5d: the notes of the casting net in the table's order (`caster_casting_net` solo_controller.gd:5225): the conduit mod,
/// then each casting record of the caster and its host, then the Spell Amplifier.
fn casting_notes(statics: &[UnitStatic], state: &State, ci: usize, conduit_mod: i64) -> Vec<String> {
    let mut notes: Vec<String> = (conduit_mod != 0).then(|| format!("Spell Conduit {conduit_mod:+}")).into_iter().collect();
    for u in [Some(ci), state.attached_to[ci]].into_iter().flatten() {
        notes.extend(state.buffs[u].iter().filter(|r| mods::matches(r, mods::Role::Casting, false)).map(|r| format!("{} {:+}", r.name, r.casting_mod)));
    }
    let amp = statics[state.roster.profile[ci]].spell_amplifier_casting_mod;
    notes.extend((amp != 0).then(|| format!("Spell Amplifier {amp:+}")));
    notes
}

/// CC-5b/5c/5d: one offered cast (`_solo_resolve_one_cast` main.gd:5598, after the plan's own spend). The tokens go first and stay
/// spent whatever follows: the table paid them at plan time, so its capture holds the counts BEFORE the plan and the core pays them
/// here, the threshold from the caster, boost and interference from the listed payers in list order. A skipped cast then says
/// nothing, a fizzled one says so. Otherwise the shaken-battery, conduit, casting-net and announce/needs lines, the cast die (kind
/// "cast", the caster's), its result line, and the casting once-mod is spent by the roll. The target is the table's double clamp:
/// the casting net (including the conduit mod) moves the base first (`caster_casting_net`), boost and interference the clamped
/// result (`AiSpell.cast_target`). `si` is the activating unit (the announce line names it). A hit of a damage spell lands its hits
/// on each standing target in list order (`tray_spell_damage`, CC-6a); any other effect ends `Hit`, which the step API still refuses.
pub(crate) fn tray_cast(statics: &[UnitStatic], state: &mut State, si: usize, c: &CastInput, seams: Seams, tray: &mut Tray, shot: &mut ShootResult) -> CastEnd {
    spend_cast_tokens(state, c);
    let ci = state.roster.index.get(c.caster.as_str()).copied().unwrap_or(si);
    let (side, caster) = (state.player[ci], statics[state.roster.profile[ci]].name.clone());
    let end = cast_ends(state, c);
    if end == Some(CastEnd::Fizzled) {
        cast_say(tray, side, format!("{caster}'s {} fizzles — no target remains", c.spell));
    }
    if let Some(end) = end {
        return end;
    }
    let name = |u: usize| statics[state.roster.profile[u]].name.as_str();
    let standing_idx: Vec<usize> = c.targets.iter().filter_map(|k| state.roster.index.get(k.as_str()).copied()).filter(|&t| state.alive[t] > 0).collect();
    // CC-6a hazard 2: a record placed by an earlier cast in the same activation was not present at activation start;
    // re-check standing targets of a damage spell before rolling its die. CC-13e: `step_activation` refuses the case at activation
    // start (`earlier_record_break`), so this stays the guard for a direct caller.
    if statics[state.roster.profile[ci]].spells.iter().any(|s| s.name == c.spell && s.effect_kind == "damage") {
        if let Some(&t) = standing_idx.iter().find(|&&t| !crate::activation::damage_target_plain(statics, state, t)) {
            tray.note_cast_refused(c.seq, format!("cast {}: {} meets {} with a rule the core does not say for spell damage yet", c.seq, name(t), c.spell));
            return CastEnd::Hit;
        }
    }
    say_shaken_batteries(statics, state, side, tray);
    for k in &c.conduit_shaken {
        if let Some(&sh) = state.roster.index.get(k.as_str()) {
            cast_say(tray, side, format!("Spell Conduit: {} is Shaken — its conduit does not help {caster} cast", name(sh)));
        }
    }
    let mut conduit_mod = 0;
    if let Some(&cu) = (!c.conduit.is_empty()).then(|| state.roster.index.get(c.conduit.as_str())).flatten() {
        let s = &statics[state.roster.profile[cu]];
        conduit_mod = if s.spell_conduit { s.spell_conduit_casting_mod } else { 0 };
        cast_say(tray, side, format!("Spell Conduit: {caster} casts as if standing at {} ({})", name(cu), geom::godot_vec3(geom::centre(&state.positions[cu]))));
    }
    let net = casting_net_of(statics, state, ci, seams) + conduit_mod;
    let base = if net != 0 { (c.base - net).clamp(2, 6) } else { c.base };
    if net != 0 {
        cast_say(tray, side, format!("{net:+} to casting rolls ({}) — {caster} casts on {base}+ (base {}+)", casting_notes(statics, state, ci, conduit_mod).join(", "), c.base));
    }
    let mut interference = c.interference.max(0);
    let mut target = (base - c.boost.max(0) + interference).clamp(2, 6);
    let standing: Vec<&str> = c.targets.iter().filter_map(|k| state.roster.index.get(k.as_str())).filter(|&&t| state.alive[t] > 0).map(|&t| name(t)).collect();
    let mut tokens = format!("{} token{}", c.threshold, if c.threshold == 1 { "" } else { "s" });
    tokens += &(if c.boost > 0 { format!(", +{} boost", c.boost) } else { String::new() });
    tokens += &(if c.interference > 0 { format!(", -{} interference", c.interference) } else { String::new() });
    cast_say(tray, side, format!("{} casts {} at {}", name(si), c.spell, standing[0]));
    cast_say(tray, side, format!("{caster} casts {} at {} — needs {target}+ ({tokens})", c.spell, standing.join(", ")));
    // CC-9c: open human interference per foe slot in `c.pools`, spending in list order and logging the table's lines (`main.gd:6490-6542`).
    if c.open {
        let v36 = rule_on(seams.rules_epoch, EPOCH_73_V36);
        let reach = if v36 { "within 18\", no line of sight needed" } else { "within 18\" and line of sight" };
        let pool_note = if v36 { format!(" (casters {reach})") } else { String::new() };
        for (slot, payers) in &c.pools {
            say_shaken_batteries(statics, state, *slot, tray);
            let eligible: Vec<(usize, i64)> = payers
                .iter()
                .filter_map(|(k, n)| {
                    let &u = state.roster.index.get(k.as_str())?;
                    let avail = if state.alive[u] > 0 && !state.dormant[u] { state.casts[u].min(*n).max(0) } else { 0 };
                    (avail > 0).then_some((u, avail))
                })
                .collect();
            let pool: i64 = eligible.iter().map(|&(_, a)| a).sum();
            if pool == 0 {
                if side_has_caster_tokens(statics, state, *slot) {
                    cast_say(tray, *slot, format!("{}: no caster of P{slot} {reach} \u{2014} no interference", c.spell));
                }
                continue;
            }
            let id = format!("interference:{}:{}:{slot}", c.seq, c.caster);
            let owner = state.key(eligible[0].0).to_string();
            let Some(spent) = tray.interference(&id, pool, &owner) else { continue };
            if spent <= 0 {
                continue;
            }
            let (mut rem, mut parts) = (spent, Vec::new());
            for &(u, avail) in &eligible {
                if rem <= 0 {
                    break;
                }
                let take = rem.min(avail).min(state.casts[u]);
                if take > 0 {
                    state.casts[u] -= take;
                    rem -= take;
                    parts.push(format!("{} \u{00d7}{take}", name(u)));
                }
            }
            interference += spent;
            target = (base - c.boost.max(0) + interference).clamp(2, 6);
            let (verb, plural) = (if parts.len() == 1 { "s" } else { "" }, if spent == 1 { "" } else { "s" });
            cast_say(
                tray,
                *slot,
                format!("Interference: {} spend{verb} {spent} token{plural} \u{2014} the cast roll worsens to {target}+{pool_note}", parts.join(", ")),
            );
        }
    }
    tray.owner_next(Some(ci));
    let faces = tray.roll(1);
    let hit = crate::dice::faces_to_hits(&faces, target as u8) > 0;
    let face = faces.first().copied().unwrap_or(0);
    shot.rolls.push(crate::dice::Roll { kind: "cast", count: 1, target, faces, owner: caster });
    cast_say(tray, side, format!("{}: cast roll {face} vs {target}+ — {}", c.spell, if hit { "SUCCESS" } else { "FAILED" }));
    mods::spend_once(state, ci, &[mods::Role::Casting], false);
    if !hit {
        return CastEnd::Failed;
    }
    let Some(spell) = statics[state.roster.profile[ci]].spells.iter().find(|s| s.name == c.spell) else { return CastEnd::Hit };
    match spell.effect_kind.as_str() {
        "damage" => {
            for &t in &standing_idx {
                tray_spell_damage(statics, state, ci, si, t, c.seq, spell, None, seams, tray, shot);
            }
            CastEnd::Landed
        }
        "buff" | "debuff" | "utility" => {
            tray_spell_effect(state, &standing_idx, c, spell, seams.rules_epoch);
            CastEnd::Landed
        }
        _ => CastEnd::Hit,
    }
}

/// CC-8b / CC-13e: a hit of this buff / debuff spell leaves nothing on the board: neither a non-zero modifier nor a grant (the table
/// announces it and places the token only). The one predicate `tray_spell_effect` and the activation's static hazard-2 check share.
pub(crate) fn spell_effect_less(spell: &Spell) -> bool {
    let m = spell.modifier;
    let parts = (m.hit_mod as i64, m.def_mod as i64, m.casting_mod as i64, m.morale_mod as i64, m.range_in as i64, m.advance_in as i64, m.rush_in as i64);
    spell.grants_rule.is_empty() && (!m.present || parts == (0, 0, 0, 0, 0, 0, 0))
}

/// CC-8b: a buff or debuff spell's effect on every standing target (`_solo_record_spell_mod` main.gd:6078). Builds the
/// table's `PlainBuff` shape and converts it through `PlainBuff::to_live_mod` (the capture's own conversion), so the
/// core's `LiveMod` equals what capturing the landed table record produces. A spell with neither a non-zero modifier nor a
/// grant is resolved with nothing pushed on the board (table: announce + token only). CC-8c: every standing target of a hit
/// buff / debuff cast, effect-less ones included, is also named in `State::cast_buffs` (the delta's `buffs_gained`).
fn tray_spell_effect(state: &mut State, targets: &[usize], c: &CastInput, spell: &Spell, rules_epoch: u32) {
    let m = spell.modifier;
    let (hit, def, cast, morale, range) = (m.hit_mod as i64, m.def_mod as i64, m.casting_mod as i64, m.morale_mod as i64, m.range_in as i64);
    let effect_less = spell_effect_less(spell);
    let rec = crate::io::PlainBuff {
        spell: spell.name.clone(),
        hit_mod: hit,
        casting_mod: cast,
        morale_mod: morale,
        ap_mod: 0,
        def_mod: def,
        defense_mod: 0,
        range_in: range,
        grants_rule: spell.grants_rule.clone(),
        scope: spell.scope.clone(),
        beneficiary: spell.beneficiary.clone(),
        duration: if c.once { "once" } else { "round" }.into(),
    };
    let live = rec.to_live_mod(rules_epoch);
    for &t in targets {
        // EPOCH_95_PARITY_BATCH: the same spell does not stack (GF 3.6), an identical record already on the target is refreshed, none is added
        if !effect_less && rule_on(rules_epoch, crate::acts::EPOCH_95_PARITY_BATCH) && state.buffs[t].contains(&live) {
            continue;
        }
        if !effect_less {
            state.buffs[t].push(live.clone());
        }
        state.cast_buffs.push((t, live.clone(), false)); // CAST-O7 / CC-8c: the delta names it (gained, or spent by this activation)
    }
}

/// CC-7b: the rules-3.6 "applied facets" clauses for `_solo_resolve_spell_damage` (main.gd:5756-5784), in table order.
fn spell_applied_facets(spell: &Spell, facets: &crate::spell::Facets, def: &Ctx, state: &State, ti: usize) -> Vec<String> {
    let has = |name: &str| crate::rules::has_special_rule(&spell.weapon_rules, name);
    let state_name = match (state.shaken[ti], state.fatigued[ti]) {
        (true, true) => "Shaken + Fatigued",
        (true, false) => "Shaken",
        _ => "Fatigued",
    };
    let mut applied = Vec::new();
    if has("Destructive") {
        applied.push(if def.above_half_strength { "Destructive +1 AP (above half)" } else { "Destructive not applied (target at or below half)" }.into());
    }
    if has("Fracture") { applied.push("Fracture — sixes get AP(+2)".into()); }
    if has("Puncture") { applied.push("Puncture — ignores Regeneration, AP(+2) vs Defense 3 or less".into()); }
    if has("Disintegrate") { applied.push("Disintegrate — ignores Regeneration, AP(+2) vs Tough(3)+".into()); }
    if has("Shatter") { applied.push("Shatter — sixes get AP(+3)".into()); }
    if facets.ap_vs_shaken > 0 && def.shaken_or_fatigued { applied.push(format!("Purge +{} AP vs {state_name}", facets.ap_vs_shaken)); }
    if facets.bane_above_half && def.above_half_strength { applied.push("Decimate — Bane vs a target above half".into()); }
    if facets.bane_tough3_low > 1 && def.tough.max(1) >= 3 { applied.push("Obliterate — save window 5+ vs Tough(3)+, Regeneration bypassed".into()); }
    if facets.bane_shaken_low > 1 && def.shaken_or_fatigued { applied.push(format!("Reap — save window 5+ vs {state_name}")); }
    if facets.bane_def56_low > 1 && def.defense >= 5 { applied.push("Fragment — save window 5+ vs Defense 5+".into()); }
    applied
}

/// CC-6a/6b/7a/7b/8a: a damage spell's hits on one target (`_solo_resolve_spell_damage` main.gd:5747). The printed hits are fixed
/// (no to-hit die); rules-3.6 applied facets log before the trigger roll (`spell_attack`, 6+, caster owner for Surge / on-6 AP /
/// Hazardous). CC-7b multiplies Blast(X) by `min(X, models)` (`1` for a `"model"` target, else `combined_alive`) and applies
/// `effective_ap` and `bane_window` (and Shred) through `save_batch` (on-6 AP batch first, CC-7a). Shielded, Cover and the over-9"
/// family do not count against a spell (NML-104); saves are `spell_defense` and Regeneration / Resistance (at the spell threshold,
/// obeying `ignores_regen`) are `spell_attack`. CC-6b lands Deadly(X) per model and honours `wound_alloc` when open; CC-7a lands
/// Hazardous trigger-1 wounds on `host` (no save/regen) before the target's morale test (`spell_morale`, O2).
/// `fixed`: a skirmish Blast spill's share for a neighbour of the spell's target - exactly that many hits, no trigger roll
/// (a spilled hit carries no unmodified 6) and no Blast of its own.
#[allow(clippy::too_many_arguments)]
fn tray_spell_damage(statics: &[UnitStatic], state: &mut State, ci: usize, host: usize, ti: usize, seq: i64, spell: &Spell, fixed: Option<i64>, seams: Seams, tray: &mut Tray, shot: &mut ShootResult) {
    if spell.effect_hits <= 0 {
        return;
    }
    shot.attacked.push(ti);
    let ut = &statics[state.roster.profile[ti]];
    let alive_before = morale_alive(state, ti, seams);
    let wounds_before = morale_wounds_left(state, ti, seams);
    let mut def = with_modifier_sum(with_cond_ap_state(ctx_live(ctx_of(ut, state, ti), statics, state, ti, false, seams.rules_epoch), statics, state, ti, seams), seams.rules_epoch);
    def.side = state.player[ti];
    def.playtest_rules = rule_on(seams.rules_epoch, EPOCH_72_PLAYTEST_RULES);
    def.rules_epoch = seams.rules_epoch;
    let facets = crate::spell::spell_facets(&spell.weapon_rules, seams.rules_epoch);
    let caster_side = state.player[ci];
    if rule_on(seams.rules_epoch, EPOCH_73_V36) {
        let applied = spell_applied_facets(spell, &facets, &def, state, ti);
        if !applied.is_empty() {
            spell_say(tray, caster_side, format!("{}: {}", spell.name, applied.join(", ")));
        }
    }
    let hazardous = crate::rules::has_special_rule(&spell.weapon_rules, "Hazardous");
    let (mut trigger_sixes, mut trigger_ones) = (0i64, 0i64);
    if fixed.is_none() && (facets.surge || facets.on6_ap > 0 || hazardous) {
        tray.owner_next(Some(ci));
        let faces = tray.roll(spell.effect_hits as usize);
        trigger_sixes = faces.iter().filter(|&&f| f == 6).count() as i64;
        trigger_ones = faces.iter().filter(|&&f| f == 1).count() as i64;
        shot.rolls.push(crate::dice::Roll {
            kind: "spell_attack", count: spell.effect_hits, target: crate::combat::UNMODIFIED_SIX,
            faces, owner: statics[state.roster.profile[ci]].name.clone(),
        });
    }
    let mut total_hits = fixed.unwrap_or(spell.effect_hits + if facets.surge { trigger_sixes } else { 0 });
    // CC-7b: Blast ×min(X, models) — a "model"-targeted spell resolves as a unit of 1 (no fan-out, main.gd:5804-5805).
    let fanout = if spell.target_kind == "model" {
        1
    } else {
        blast_cap_models(state, ti, seams, state.book(ti))
    };
    // The skirmish Blast spread (3.6 Firefight / AoF: Skirmish): the hits split over the target and its side's units within
    // reach, each capped at its models; a "model"-targeted spell resolves as a unit of 1 and keeps the plain multiply.
    let spread = if fixed.is_none() && facets.blast > 1 && spell.target_kind != "model" { blast_spread_units(state, ti, seams) } else { Vec::new() };
    let mut spill: Vec<(usize, i64)> = Vec::new();
    if !spread.is_empty() {
        let models: Vec<i64> = spread.iter().map(|n| n.1).collect();
        let split = crate::dice::blast_split_at(total_hits, facets.blast, fanout.max(1), &models, seams.rules_epoch);
        let (kept, out) = (split[0], split[1..].iter().sum::<i64>());
        let line = format!("Blast({}): {total_hits} hit{} -> {kept} on {}, {out} on units within reach, {} lost", facets.blast,
            if total_hits == 1 { "" } else { "s" }, ut.name, total_hits * facets.blast - kept - out);
        shot.log.push(line.clone());
        say_rule(tray, "blast", caster_side, || line);
        spill = spread.iter().map(|n| n.0).zip(split[1..].iter().copied()).filter(|n| n.1 > 0).collect();
        total_hits = kept;
    } else if fixed.is_none() && facets.blast > 1 {
        total_hits *= facets.blast.clamp(1, fanout.max(1));
    }
    if state.in_cover[ti] {
        spell_say(tray, state.player[ti], format!("Cover does not apply to spell damage (its +1 is against shooting) — {} saves on {}+", ut.name, def.defense.clamp(2, 6)));
    }
    let ap = crate::spell::effective_ap(&facets, &def);
    let bane = crate::spell::bane_window(&facets, &def);
    let upgraded = if facets.on6_ap > 0 { trigger_sixes.min(total_hits) } else { 0 };
    if upgraded > 0 {
        spell_say(tray, caster_side, format!("{}: {upgraded} hit{} on a 6 → AP(+{})", spell.name, if upgraded == 1 { "" } else { "s" }, facets.on6_ap));
    }
    let draw0 = tray.feed().map_or(0, |f| f.draws());
    let mut out = crate::dice::resolve_spell_hits_with_tray(
        total_hits, upgraded, ap, facets.on6_ap, facets.deadly, facets.ignores_regen, bane, facets.shred, &spell.weapon_rules, &spell.name, &def, &ut.name, tray,
    );
    for r in &mut out.rolls {
        r.kind = if r.kind == "defense" { "spell_defense" } else { "spell_attack" };
    }
    tray.tag_spell_regeneration(draw0); // the cast leg keeps its plain `spell_attack` for the ignore dice (the ignore groups name them `regeneration`)
    let def_incoming = out.caused > 0;
    let w = shot.absorb(out);
    let before = chain_snapshot(state, ti, tray);
    let deadly: i64 = shot.deadly_groups.iter().map(|d| d.0).sum();
    let alloc_id = format!("wound_alloc:{}:{}:cast:{seq}", state.key(ci), state.key(ti));
    let mut alloc = if seams.tray_exact { open_alloc_id(state, ti, &alloc_id, (w, deadly), tray) } else { None };
    let mut deadly_dealt = 0;
    let mut groups = std::mem::take(&mut shot.deadly_groups).into_iter();
    for (weapon, unsaved, dx, n) in std::mem::take(&mut shot.deadly_lines) {
        let (mut dealt, mut forced) = (0, 0);
        for (post, gx) in groups.by_ref().take(n) {
            let d = land_deadly_group(state, ti, post, gx, seams, &mut alloc, &mut forced);
            shot.log.push(format!("Deadly({gx}): {post} unsaved ×{gx}, no carry-over → {d} wounds dealt"));
            dealt += d;
        }
        deadly_dealt += dealt;
        let s = |n: i64| if n == 1 { "" } else { "s" };
        if dealt > 0 {
            say_rule(tray, "deadly", caster_side, || format!("Deadly({dx}): {unsaved} unsaved ×{dx}, no carry-over → {dealt} wound{} dealt ({weapon})", s(dealt)));
            if forced > 0 {
                say_rule(tray, "deadly", caster_side, || format!("Deadly({dx}): {forced} wound{} finish the already-wounded Tough model first ({CITE})", s(forced)));
            }
        }
    }
    let left = if seams.tray_exact { alloc.as_mut().map_or(w, |a| land_pool_picked(state, ti, w, a, tray)) } else { w };
    land_pool_wounds(state, ti, left, seams.tray_exact, seams, &mut shot.log);
    land_chain_report_inline(statics, state, tray, ti, before, deadly_dealt);
    spend_protection_feat(statics, state, ti, def_incoming, seams.rules_epoch);
    // CC-7a: Hazardous ("this model's unit takes one wound on unmodified rolls of 1") lands on the caster's HOST (no save/regen) before morale.
    if trigger_ones > 0 && hazardous {
        let before_h = chain_snapshot(state, host, tray);
        land_pool_wounds(state, host, trigger_ones, seams.tray_exact, seams, &mut shot.log);
        land_chain_report_inline(statics, state, tray, host, before_h, 0);
        let s = if trigger_ones == 1 { "" } else { "s" };
        spell_say(tray, caster_side, format!("{}: {trigger_ones} trigger roll{s} of 1 — {} takes {trigger_ones} wound{s}",
            spell.name, statics[state.roster.profile[host]].name));
    }
    let landed = w + deadly_dealt;
    // CC-8a (O2): morale runs right after that target's spell damage (main.gd `_solo_resolve_spell_damage` -> `_solo_shooting_morale`),
    // carrying the spell's name as its cause (Banner does not apply) and tagging the morale dice onto the spell leg (`spell_morale`).
    if landed > 0 && shooting_morale_trigger(state, statics, seams, ut, ti, alive_before, wounds_before) {
        if tray.feed().is_some() {
            if let Some(line) = shooting_morale_line(state, statics, seams, ut, ti, alive_before, wounds_before) {
                say_rule(tray, "morale", state.player[ti], || line);
            }
        }
        let draw0 = tray.feed().map_or(0, |f| f.draws());
        let before_m = chain_snapshot(state, ti, tray);
        tray_morale_for(state, statics, ti, false, true, Some(&spell.name), seams, tray, shot, None, None);
        tray.tag_spell_morale(draw0);
        land_chain_report(statics, state, tray, ti, before_m);
    }
    for (nj, h) in spill {
        if state.alive[nj] > 0 {
            tray_spell_damage(statics, state, ci, host, nj, seq, spell, Some(h), seams, tray, shot);
        }
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
///
/// The priced pair is the live root ctx (families 2-4 of the blindness
/// report). Feature reconstruction passes the recording epoch; live callers
/// use the current epoch through `reply_threat`.
#[allow(clippy::too_many_arguments)]
fn volley_ev(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    ti: usize,
    d: f64,
    sc: &mut Scratch,
    rules_epoch: u32,
    reach_shave: Option<f64>,
    cache: &mut ReplyCtxCache,
) -> (f64, i64) {
    let us = &statics[state.roster.profile[si]];
    let ut = &statics[state.roster.profile[ti]];
    profiles_of(us, state.alive[si], d, sc);
    if let Some(shave) = reach_shave {
        reach_rescale(us, state.alive[si], &state.positions[si], &state.positions[ti], shave, sc);
    }
    // Exact early-out (aifix training-speed lane): nothing in range and no spell tokens means `shoot_ev` and
    // `spell_ev_of` are both zero whatever the contexts are — skip the two `ctx_live` builds.
    if sc.keep.is_empty() && (state.casts[si] <= 0 || !us.is_caster) {
        return (0.0, 0);
    }
    if !cache.on {
        cache.slots.clear();
    }
    let ai = cache.slot(us, statics, state, si, rules_epoch);
    let di = cache.slot(ut, statics, state, ti, rules_epoch);
    let (att, def) = (&cache.slots[ai].1, &cache.slots[di].1);
    let shooting = shoot_ev(&us.shoot, &sc.keep, &sc.attacks, att, def, d);
    let (sp_ev, sp_cost) = spell_ev_of(us.is_caster, &us.spells, state.casts[si], def, d, rules_epoch);
    (shooting + sp_ev, sp_cost)
}

/// The volley's live root ctx of each unit, built at most once inside ONE `reply_threat_core` call.
///
/// `ctx_live(ctx_of(unit), melee = false)` is a pure function of `(statics, state, unit, rules_epoch)`, and all four are
/// fixed for the whole call (`state` is a shared borrow, `rules_epoch` a parameter), so the second request for the same
/// unit returns exactly the value a rebuild would. The attacker and the defender build are the same function of the unit
/// (the role only says where the result is read), so the key is the unit alone. A call prices ~12 builds over ~6
/// distinct units. The cache lives on the caller's stack and is dropped with it: nothing crosses a call.
///
/// The one effect `ctx_live` has besides its value is the `NML_TRACE_RULES` stderr line; with tracing on the cache is
/// bypassed (the slots are cleared before every volley) so every build logs exactly as before.
struct ReplyCtxCache {
    slots: Vec<(usize, Ctx)>,
    on: bool,
}

impl ReplyCtxCache {
    fn new(on: bool) -> Self {
        ReplyCtxCache { slots: Vec::new(), on }
    }

    /// The index in `slots` of unit `i`'s live ctx: found, or built now (the first use computes what it always did).
    fn slot(&mut self, us: &UnitStatic, statics: &[UnitStatic], state: &State, i: usize, rules_epoch: u32) -> usize {
        if self.on {
            if let Some(p) = self.slots.iter().position(|(k, _)| *k == i) {
                return p;
            }
        }
        if self.slots.capacity() == 0 {
            self.slots.reserve_exact(8);
        }
        let mut c = ctx_live(ctx_of(us, state, i), statics, state, i, false, rules_epoch);
        // SHO-06e: the reply-threat estimate prices the enemy's volley as a Hold shot.
        c.held = true;
        self.slots.push((i, c));
        self.slots.len() - 1
    }
}

/// `NML_TRACE_RULES=1`, read once per process (the cache is bypassed while it is on).
fn trace_rules_on() -> bool {
    static ON: std::sync::OnceLock<bool> = std::sync::OnceLock::new();
    *ON.get_or_init(|| std::env::var("NML_TRACE_RULES").as_deref() == Ok("1"))
}

/// `BattleSim.melee_threat` battle_sim.gd:852-853 — `si`'s melee EV onto `ti`,
/// valued as a CHARGE and with `si`'s own fatigue state: the magnitude
/// `AiMissionEval.features` reads for `my_melee_in`/`their_melee_in` when the
/// feature wave is on (ai_mission_eval.gd:544).
///
/// Feature reconstruction passes the record epoch; live callers use
/// `melee_threat`, which selects the current epoch.
pub fn melee_threat_at_epoch(statics: &[UnitStatic], state: &State, si: usize, ti: usize, rules_epoch: u32) -> f64 {
    let us = &statics[state.roster.profile[si]];
    let ut = &statics[state.roster.profile[ti]];
    let att =
        ctx_live(ctx_of_melee(us, state, si, rules_epoch), statics, state, si, true, rules_epoch);
    let def = with_cond_ap_state(ctx_live(ctx_of(ut, state, ti), statics, state, ti, true, rules_epoch), statics, state, ti, Seams { rules_epoch, ..Seams::default() });
    let mut sc = Scratch::default();
    melee_profiles_of(us, state.alive[si], &mut sc);
    let gap = charge_estimate_gap_in(rules_epoch, || {
        modifier_distance_in(state, si, ti, Seams { rules_epoch, ..Seams::default() })
    });
    melee_ev(&us.melee, &sc.attacks, &att, &def, true, gap)
}

pub fn melee_threat(statics: &[UnitStatic], state: &State, si: usize, ti: usize) -> f64 {
    melee_threat_at_epoch(statics, state, si, ti, CURRENT_RULES_EPOCH)
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
///
/// Each volley prices the LIVE root ctx (families 2-4 of the blindness
/// report) — see `volley_ev`.
pub fn reply_threat_at_epoch(statics: &[UnitStatic], state: &State, player: i64, rules_epoch: u32) -> Vec<f64> {
    reply_threat_core(statics, state, player, rules_epoch, ReplyOpts::default())
}

/// The charge band the v2 reply reads a melee threat inside (GF p.7 Charge: 12").
const REPLY_CHARGE_IN: f64 = 12.0;
/// The Advance band the v2 reply shoots after (GF p.7: Advance moves 6" and may still fire).
const REPLY_ADVANCE_IN: f64 = 6.0;

/// Inventory T03: the enemy `e`'s live charge reach against `m` — the gate's own band (`charge` or the
/// Rush band, Fast +4" / Slow -4" already in the bands), Melee-Shrouding folded.
fn speed_charge_in(statics: &[UnitStatic], state: &State, e: usize, m: usize) -> f64 {
    let bands = &state.bands[e];
    let (_, rush_in) = live_bands_of(statics, state, e);
    let band = bands.charge.map_or(rush_in, |c| c + rush_in - bands.rush);
    crate::gate::melee_shroud_charge_in(band, state, m)
}

/// E[max(0, w - X)] for X ~ Poisson(lambda): the wounds a unit of `w` keeps standing against an
/// expected `lambda` unsaved wounds, as a probability tail instead of `max(0, w - lambda)`.
fn expected_remaining(w: f64, lambda: f64) -> f64 {
    let mut p = (-lambda).exp();
    let mut sum = 0.0f64;
    for k in 0..(w.floor() as i64) {
        sum += p * (w - k as f64);
        p *= lambda / (k as f64 + 1.0);
    }
    sum
}

/// `reply_threat` with `Seams::reply_v2` choosing the aifix D2 reading: an enemy
/// may also CHARGE a unit inside 12" (`melee_threat`, never added before), a
/// Shaken enemy only holds so it threatens nothing, and each enemy still picks
/// ONE best target, shooting or charging.
pub fn reply_threat_with(statics: &[UnitStatic], state: &State, player: i64, v2: bool) -> Vec<f64> {
    reply_threat_opts(statics, state, player, ReplyOpts { v2, ..ReplyOpts::default() })
}

/// The reply-threat readings, one flag per audit fix (`Seams::reply_opts`). `v2` = D2 (charge, advance,
/// Shaken, survival tail); `skip_activated` = E5; `hold_gate` = Immobile/Artillery may only Hold, so
/// they neither advance-shoot nor charge. The last two only matter with `v2` (they gate its extras)
/// except `skip_activated`, which stands alone.
#[derive(Clone, Copy, Debug, Default)]
pub struct ReplyOpts {
    pub v2: bool,
    /// Inventory C01: the enemy's volley distance is the base-edge gap (`range_gap_in`).
    pub range_edge: bool,
    pub skip_activated: bool,
    pub hold_gate: bool,
    /// Inventory C02: the enemy's volley counts only the models within each weapon's range.
    pub reach_only: bool,
    /// Inventory T03-T06: the enemy's charge threat uses ITS live charge band, the base-edge gap and
    /// never targets an Aircraft; its advance-then-shoot closes ITS live advance band.
    pub by_speed: bool,
}

pub fn reply_threat_opts(statics: &[UnitStatic], state: &State, player: i64, o: ReplyOpts) -> Vec<f64> {
    reply_threat_core(statics, state, player, CURRENT_RULES_EPOCH, o)
}

/// One remembered `geom::dist_in` answer: the two position arrays it was computed from, bit for bit, and the result.
#[derive(Default)]
struct PairDistEnt {
    a: Vec<[f64; 3]>,
    b: Vec<[f64; 3]>,
    d: f64,
    ok: bool,
}

#[derive(Default)]
struct PairDistMemo {
    n: usize,
    ent: Vec<PairDistEnt>,
}

thread_local! {
    static PAIR_DIST: std::cell::RefCell<PairDistMemo> = std::cell::RefCell::new(PairDistMemo::default());
}

fn same_bits(x: &[[f64; 3]], y: &[[f64; 3]]) -> bool {
    x.len() == y.len() && x.iter().zip(y).all(|(p, q)| p.iter().zip(q).all(|(u, v)| u.to_bits() == v.to_bits()))
}

/// `geom::dist_in(a, b)` for the pair (e, m) of an `n`-unit roster, remembered across calls. `dist_in` is a pure function of
/// the two position arrays, and an entry is only reused when BOTH arrays match the stored copies bit for bit, so the
/// answer is identical to a fresh `dist_in` whatever the slot index means (another state, another game, a moved unit =
/// a miss). A policy step scores many candidate states that differ in one mover; every other pair is a hit. Pairs of
/// fewer than 16 model-pairs are cheaper to compute than to compare and go straight to `dist_in`.
fn pair_dist_memo(n: usize, e: usize, m: usize, a: &[[f64; 3]], b: &[[f64; 3]]) -> f64 {
    if a.len() * b.len() < 16 || e >= n || m >= n {
        return geom::dist_in(a, b);
    }
    PAIR_DIST.with(|c| {
        let mut c = c.borrow_mut();
        if c.n != n {
            c.n = n;
            c.ent.clear();
            c.ent.resize_with(n * n, PairDistEnt::default);
        }
        let slot = &mut c.ent[e * n + m];
        if slot.ok && same_bits(&slot.a, a) && same_bits(&slot.b, b) {
            return slot.d;
        }
        let d = geom::dist_in(a, b);
        slot.a.clear();
        slot.a.extend_from_slice(a);
        slot.b.clear();
        slot.b.extend_from_slice(b);
        slot.d = d;
        slot.ok = true;
        d
    })
}

pub(crate) fn reply_threat_core(statics: &[UnitStatic], state: &State, player: i64, rules_epoch: u32, o: ReplyOpts) -> Vec<f64> {
    reply_threat_core_with(statics, state, player, rules_epoch, o, !trace_rules_on())
}

/// `reply_threat_core` with the per-call ctx cache switched explicitly (`cache_ctx = false` rebuilds every ctx, the
/// original behaviour — the reference side of the differential test).
fn reply_threat_core_with(
    statics: &[UnitStatic],
    state: &State,
    player: i64,
    rules_epoch: u32,
    o: ReplyOpts,
    cache_ctx: bool,
) -> Vec<f64> {
    let v2 = o.v2;
    let mut ctxs = ReplyCtxCache::new(cache_ctx);
    let n = state.units();
    let mut incoming = vec![0.0f64; n];
    let mut sc = Scratch::default();
    // E5: mid-round (someone alive has yet to activate) an enemy that already activated cannot fire
    // again; at a round end everyone is activated and the next round's volley is what is priced.
    let mid_round = o.skip_activated && (0..n).any(|i| state.alive[i] > 0 && !state.activated[i]);
    for e in 0..n {
        if state.player[e] == player || state.alive[e] <= 0 || (v2 && state.shaken[e])
            || (mid_round && state.activated[e])
        {
            continue;
        }
        // Rules 3.6 (SHO-16): a Cumbersome enemy may neither charge nor
        // advance-and-shoot, so it is not `movable` for those two legs; the
        // standing volley above stays.
        let cumbersome = statics.get(state.roster.profile[e]).is_some_and(|s| s.cumbersome)
            && rule_on(rules_epoch, crate::acts::EPOCH_73_V36);
        let movable = !(o.hold_gate && crate::menu::holds_only(state, statics, e)) && !cumbersome;
        let mut best_key: Option<usize> = None;
        let mut best_ev = 0.0f64;
        for m in 0..n {
            if state.player[m] != player || state.alive[m] <= 0 {
                continue;
            }
            let d = if o.range_edge {
                range_gap_in(state, &state.positions[e], e, m)
            } else {
                pair_dist_memo(n, e, m, &state.positions[e], &state.positions[m])
            };
            let mut ev = 0.0f64;
            if state.sees_idx(e, m) && los_clear(state, e, m) {
                ev = volley_ev(statics, state, e, m, d, &mut sc, rules_epoch, o.reach_only.then_some(0.0), &mut ctxs).0;
            }
            // T03-T06: off = the fixed 12" / 6" bands on the centre distance; on = the enemy's live bands,
            // the base-edge gap for the charge, and no charge against an Aircraft.
            let (charge_gap, charge_reach) = if o.by_speed {
                (range_gap_in(state, &state.positions[e], e, m).max(0.0), speed_charge_in(statics, state, e, m))
            } else {
                (d, REPLY_CHARGE_IN)
            };
            let adv_in = if o.by_speed { live_bands_of(statics, state, e).0 } else { REPLY_ADVANCE_IN };
            let chargeable = !(o.by_speed && state.aircraft[m]);
            if v2 && movable && chargeable && charge_gap <= charge_reach {
                ev = ev.max(melee_threat_at_epoch(statics, state, e, m, rules_epoch));
            }
            if v2 && movable && d > adv_in && state.sees_idx(e, m) && los_clear(state, e, m) {
                let after = volley_ev(statics, state, e, m, d - adv_in, &mut sc, rules_epoch, o.reach_only.then_some(adv_in), &mut ctxs).0;
                ev = ev.max(after);
            }
            if ev > best_ev {
                best_ev = ev;
                best_key = Some(m);
            }
        }
        if let Some(m) = best_key {
            incoming[m] += best_ev;
        }
    }
    if v2 {
        // `presence` reads `max(0, W - incoming)`: hand it the Poisson tail instead, so that
        // expression is exactly the expected wounds left (a 10-wound unit under 8 EV keeps ~2.9, not 2).
        for (inc, wounds) in incoming.iter_mut().zip(&state.wounds) {
            if *inc > 0.0 {
                let w: f64 = wounds.iter().map(|&x| x as f64).sum();
                *inc = w - expected_remaining(w, *inc);
            }
        }
    }
    incoming
}

pub fn reply_threat(statics: &[UnitStatic], state: &State, player: i64) -> Vec<f64> {
    reply_threat_at_epoch(statics, state, player, CURRENT_RULES_EPOCH)
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
    /// The over-9" modifier measure, kept apart from the range gate. Epoch 65
    /// recordings use unit centres; epoch 66 uses the nearest live base gap.
    mod_d: f64,
    /// Per member index, the weapon indices of that member's `shoot` list the
    /// table aimed at THIS group, in build order. `None` = the pooled plan:
    /// every kept weapon fires, no narrowing.
    weapons: Option<HashMap<usize, Vec<usize>>>,
}

/// EPOCH_38_WATCHBORN_LATCH — Versatile Attack's once-per-ACTIVATION pick.
/// Book (the `Versatile Attack`/`Versatile Reach` `pick_one` pair): the FIRST
/// eligible attack of the activation decides by EV — the same
/// `versatile_best_mode` chooser the planner folds — and the stamp lives on
/// the State's per-unit round latch (one act per unit per round makes the
/// round comparison the activation latch, the `hit_and_run_round` shape), so
/// every later volley/charge of the activation reuses it. Rules-must-log: one
/// line per activation naming the pick. Returns the latched
/// `(hit_mod, ap_mod)` and whether a pick is latched for this activation.
/// G4R5 F-VERSATILE-DEF (`EPOCH_73_V36`): the Versatile chooser reads the target's Defense AFTER the over-gate Guarded/Sturdy fold
/// (the table's `shot_base`), as the dice do. `gate_in` is the fold's own gate for the half asking (a shot's 9", a charge's stamped gate).
fn guarded_folds(def: &Ctx, over_in: f64, gate_in: f64, rules_epoch: u32) -> bool {
    rule_on(rules_epoch, EPOCH_73_V36) && def.guarded && over_in > gate_in && !def.sturdy_boost_gates_guarded
}

#[allow(clippy::too_many_arguments)]
fn versatile_latch(
    next: &mut State,
    statics: &[UnitStatic],
    mi: usize,
    hit_target: i64,
    def: &Ctx,
    guarded: bool,
    prof: Option<&ShootProfile>,
    log: &mut Vec<String>,
    tray: Option<&mut Tray>,
    rules_epoch: u32,
) -> (i64, i64, bool) {
    if next.versatile_pick_round[mi] == next.round {
        let mode = next.versatile_pick_mode[mi];
        return ((mode == 1) as i64, (mode == 2) as i64, true);
    }
    let (ap, bane, rule_name, say_name) = match prof {
        Some(p) => (p.ap, p.bane, if p.versatile_name.is_empty() { "Versatile Attack" } else { p.versatile_name.as_str() },
            p.versatile_say_name.as_str()),
        None => (0, false, "Versatile Attack", ""),
    };
    let (hit_mod, ap_mod) = crate::combat::versatile_best_mode(
        hit_target,
        crate::combat::guarded_defense(shielded_defense(def.defense, def.shielded_bonus(), def.def_floor()), guarded, def.def_floor()),
        ap,
        bane,
    );
    next.versatile_pick_round[mi] = next.round;
    next.versatile_pick_mode[mi] = if ap_mod > 0 { 2 } else { 1 };
    say_versatile_pick(rule_name, say_name, &statics[next.roster.profile[mi]].name, ap_mod > 0, next.player[mi], log, tray, rules_epoch);
    (hit_mod, ap_mod, true)
}

/// The once-per-activation pick's rules-must-log line: the book rule's name, who picked, which mode. The table's
/// `_solo_log_versatile_pick`, said where the volley decides (`versatile_latch` before the dice, or the dice themselves from
/// `EPOCH_94_PARITY_BATCH`). The recorded log names `rule_name`; the tray (a door) names `say_name` when there is one, the book rule the
/// table's `primitive_book_name` finds (`ShootProfile::versatile_say_name`).
#[allow(clippy::too_many_arguments)] // the two names, the unit, the mode and the three sinks of one line
pub(crate) fn say_versatile_pick(rule_name: &str, say_name: &str, unit: &str, ap_mode: bool, side: i64, log: &mut Vec<String>, tray: Option<&mut Tray>, rules_epoch: u32) {
    let mode = if ap_mode { "AP(+1)" } else { "+1 to hit" };
    log.push(format!("{rule_name}: {unit} picks {mode} for this activation"));
    if let Some(t) = tray {
        let said = if say_name.is_empty() { rule_name } else { say_name };
        say_rule(t, "versatile", side, || format!("{said}: {unit} picks {mode} for this activation"));
    }
    // Rules 3.6 (row W1.TRACE) — the once-per-activation pick names itself (arm `versatile-attack`).
    if rule_on(rules_epoch, EPOCH_73_V36) {
        trace_rule("versatile-attack", "Versatile Attack", &format!("{unit} picks {mode} for this activation"));
    }
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
    seams: Seams,
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
        // EPOCH_88_SPLIT_LONE_HERO: a split group aimed at a host with no models left is shot as its living joined hero, as
        // the one-target volley is from EPOCH_83_LONE_HERO_TARGET (the table: `_solo_defense_holder` for every group).
        let ti = if rule_on(seams.rules_epoch, EPOCH_88_SPLIT_LONE_HERO) { lone_hero_of(state, ti, seams).unwrap_or(ti) } else { ti };
        // B11 (main.gd:4098-4104): the table measures shooting range base-EDGE
        // to base-edge — the centre-space equivalent subtracts BOTH base radii
        // from every pair distance. The group exists because the TABLE's own
        // test fired, so every gate below runs on that EDGE gap.
        let radius = |u: usize| state.radii[u].first().copied().unwrap_or(DEFAULT_BASE_RADIUS_M);
        let d = chain_gap_in(state, ti, seams, |t| {
            (geom::dist_in(&state.positions[si], &state.positions[t]) - (radius(si) + radius(t)) / IN2M).max(0.0)
        });
        // Epoch 66 follows the table's nearest-base modifier measure; older
        // records keep the centre gap independently of this range gate.
        let mod_d = volley_distance_in(state, si, ti, seams);
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
    // NML-1100 (D76/W3-6 a): this is the sole production site a real `Tray`
    // reaches a `.roll()` from, so the record's own epoch decides the
    // zero-draw reading for every nested `tray_*` call this resolve makes.
    tray.set_zero_draws(rule_on(seams.rules_epoch, EPOCH_67_MARKERS_BURSTS));
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

/// EPOCH_26_PLACE_D3 — the D3" activation placement's hop, the FRESH-sim arm
/// of `bounding_bonus_in` above (a recorded act replays the table's own
/// band-bonus model byte-exact and never reaches here): the caller gates on
/// the frozen constant, a move kind and no recorded `bounding_d3` trace, and
/// this rolls the carrier's dice from the SEEDED stream (one `randi_range(1,
/// 3)` per die — `solo_controller.gd:1692`'s `_draw_traced(1, 3, ..)` twin)
/// and re-places the whole unit BEFORE the move with #930's free-placement
/// scan (`deployment::vanguard_free_place`, radius = the rolled inches,
/// admissible = fully within and not overlapping, the same deterministic
/// strict-`<` tie-break — Wave-Step/Wolfborn/Rapid Blink and the Vanguard
/// family share one mechanism). The table's AI never declines (:1688 fires
/// unconditionally), so the core takes it whenever the scan finds a strictly
/// closer legal spot — the scan is the only decline. No board or no seeded
/// stream: no hop. Returns the rules-must-log line when the unit moved.
fn place_d3_hop(
    next: &mut State,
    si: usize,
    cover: Cover,
    spec: &crate::unit::PlaceSpec,
    rng: Option<&mut GodotRng>,
) -> Option<String> {
    let rng = rng?;
    let t = match cover {
        Cover::Board(t) if t.is_valid() => t,
        _ => return None,
    };
    if next.alive.get(si).copied().unwrap_or(0) <= 0 || next.positions[si].is_empty() {
        return None;
    }
    let mut faces = Vec::with_capacity(spec.dice.max(1) as usize);
    for _ in 0..spec.dice.max(1) {
        faces.push(rng.randi_range(1, 3));
    }
    let reach_in = faces.iter().sum::<i64>() as f64 + spec.plus;
    if reach_in <= 0.0 { return None; }
    // The unit as ONE disc (the placement moves all models together): the
    // centroid and the widest model's radius; every other live unit is one
    // disc too (its centroid, its widest radius).
    let centre_of = |ps: &[[f64; 3]]| -> (f64, f64) {
        let n = ps.len().max(1) as f64;
        (ps.iter().map(|p| p[0]).sum::<f64>() / n, ps.iter().map(|p| p[2]).sum::<f64>() / n)
    };
    let widest = |radii: &[f64]| {
        radii.iter().copied().fold(0.0f64, f64::max).max(DEFAULT_BASE_RADIUS_M)
    };
    let own_r = widest(&next.radii[si]);
    let occupied: Vec<crate::deployment::Occupied> = next
        .positions
        .iter()
        .enumerate()
        .filter(|(j, ps)| *j != si && !ps.is_empty())
        .map(|(j, ps)| crate::deployment::Occupied {
            pos: centre_of(ps), radius: widest(&next.radii[j]),
        })
        .collect();
    let objectives: Vec<(f64, f64)> =
        next.objectives.iter().map(|o| (o.pos[0], o.pos[2])).collect();
    let spot = centre_of(&next.positions[si]);
    let blocked = |p: (f64, f64)| crate::deployment::spot_blocked(t, p, false, own_r, &[], own_r);
    let dest = crate::deployment::vanguard_free_place(
        spot, &occupied, &objectives, &blocked, own_r, &[], own_r, t.walls_in(),
        reach_in * t.in2m(), t,
    );
    if dest == spot {
        return None;
    }
    let (dx, dz) = (dest.0 - spot.0, dest.1 - spot.1);
    for m in next.positions[si].iter_mut() {
        m[0] += dx;
        m[2] += dz;
    }
    let hop_in = dx.hypot(dz) / t.in2m();
    Some(format!(
        "{}: on activation the unit is placed within D3\" of its position — rolled {reach_in:.0}\" — a {hop_in:.2}\" hop before its move",
        spec.name
    ))
}

/// EPOCH_73_V36 — the FRESH-sim arm for every `Bounding`-primitive carrier: the
/// same seeded draws as `place_d3_hop` (one `randi_range(1, 3)` per die, so the
/// stream stays aligned with the table's `bounding_d3` roll), but the inches
/// widen every move band this activation — the table's own band model — so the
/// move keeps the normal path rules. Returns the inches and the
/// rules-must-log line.
fn bounding_move_in(spec: &crate::unit::PlaceSpec, rng: Option<&mut GodotRng>) -> Option<(f64, String)> {
    let rng = rng?;
    let mut reach_in = spec.plus;
    for _ in 0..spec.dice.max(1) {
        reach_in += rng.randi_range(1, 3) as f64;
    }
    Some((reach_in, format!(
        "{}: on activation the unit moves up to the rolled {reach_in:.0}\" — every move band +{reach_in:.0}\" this activation",
        spec.name
    )))
}

/// The Mark's attackers-side grant on the target, priced by the charger's own
/// registry stamp. One matching record grants the book's +4" once, never once
/// per duplicate mark; the old epoch remains untouched.
fn rapid_charge_mark_bonus_in(
    statics: &[UnitStatic], state: &State, si: usize, ci: Option<usize>,
    kind: i64, rules_epoch: u32,
) -> f64 {
    if kind != CHARGE || !rule_on(rules_epoch, EPOCH_66_DISTANCE_TRUTH) {
        return 0.0;
    }
    let Some(ti) = ci.filter(|&ti| state.alive[ti] > 0) else { return 0.0 };
    if state.buffs[ti].iter().any(|r| r.scope.as_ref() == "melee"
        && r.grants_rule.as_ref() == "Rapid Charge"
        && mods::matches(r, mods::Role::GrantVs, true))
    {
        statics[state.roster.profile[si]].rapid_charge_grant_in
    } else { 0.0 }
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
// The 8th argument (rules_epoch) is the EPOCH_10_CHARGE_BAND spelling of the
// table's charge reach; bundling the arguments would touch every parity call
// site for no runtime gain, so the lint is silenced here deliberately.
#[allow(clippy::too_many_arguments)]
fn versatile_reach_charge_in(
    statics: &[UnitStatic], state: &State, si: usize, kind: i64,
    ci: Option<usize>, bounding_in: f64, versatile_reach: bool, rules_epoch: u32,
) -> f64 {
    if kind != CHARGE || !versatile_reach { return 0.0; }
    let us = &statics[state.roster.profile[si]];
    let (Some(bonus), Some(ti)) = (us.versatile_reach_charge_in, ci) else { return 0.0 };
    if us.melee.is_empty() { return 0.0; } // solo_controller.gd:1791
    // = the table's `charge_reach` (solo_controller.gd:1647). The distinct
    // charge band reads from `EPOCH_10_CHARGE_BAND` on; below it the pre-port
    // reading stays `rush`, so every existing corpus replays byte-exact.
    let band = if rule_on(rules_epoch, EPOCH_10_CHARGE_BAND) {
        state.bands[si].charge.unwrap_or(state.bands[si].rush) + bounding_in
    } else {
        state.bands[si].rush + bounding_in
    } + rapid_charge_mark_bonus_in(statics, state, si, ci, kind, rules_epoch);
    let gap = geom::edge_gap_in(
        &state.positions[si], &state.radii[si],
        &state.positions[ti], &state.radii[ti],
        crate::menu::DEFAULT_BASE_RADIUS_M,
    )
    .max(0.0);
    if gap > band && gap <= band + bonus { bonus } else { 0.0 }
}


/// Speed Feat (FEAT PR 1) — the band bonus THIS move earns: `+advance_mod` on
/// an ADVANCE, `+rush_mod` on a RUSH/CHARGE (the table's `advance += adv_b;
/// rush += rush_b; charge_reach += rush_b`, solo_controller.gd:1718-1720).
/// Every gate is the table's own spend condition, in its own order:
/// epoch 7 (the frozen gate), a stamped bearer, the latch still open
/// (`feats_used` — the recorder's key and the fold keep it open across acts),
/// and the endgame window (`rounds_left <= 2`, the table's `_rounds_left()
/// > 2: continue`). 0.0 otherwise — nothing else in this port reads the feat.
fn speed_feat_band_in(
    statics: &[UnitStatic], state: &State, si: usize, kind: i64, rules_epoch: u32,
) -> f64 {
    if !rule_on(rules_epoch, EPOCH_7_TABLE_RULES) {
        return 0.0;
    }
    let Some(spec) = &statics[state.roster.profile[si]].speed_feat else {
        return 0.0;
    };
    if state.feats_used[si].iter().any(|n| n == &spec.name) {
        return 0.0;
    }
    let rounds_left = (state.rounds_total - state.round + 1).max(1);
    if rounds_left > 2 {
        return 0.0;
    }
    match kind {
        ADVANCE => spec.advance_mod,
        RUSH | CHARGE => spec.rush_mod,
        _ => 0.0,
    }
}

/// Great Musician — the LIVE per-activation band bonus off this unit's own
/// ledger (self plus host, `mods::sum`'s chain, the same one every other
/// Utility-Buff read walks). Gated `EPOCH_12_MOVE_BUFF`. Only rows this core
/// recorded carry a non-zero `move_mod` (see `mods::LiveMod`), so a replayed
/// corpus's already-folded `state.bands` are never added to twice — the
/// `speed_feat_band_in` asymmetry, written down.
fn live_move_bonus_in(state: &State, statics: &[UnitStatic], i: usize, rules_epoch: u32) -> f64 {
    if !rule_on(rules_epoch, EPOCH_12_MOVE_BUFF) {
        return 0.0;
    }
    mods::sum_logged(state, i, mods::Role::Speed, false,
        &statics[state.roster.profile[i]].name, "move", |r| r.move_mod) as f64
}

/// E1 (`EPOCH_76_MOVE_FIXES`) — the buffed unit's NEXT move uses the Great Musician +1" up: every `once` speed row on
/// the unit and its host (the chain `live_move_bonus_in` reads) goes, as the table spends it after an executed move
/// (main.gd `_solo_spend_once_kind(unit, ["speed"])`). Rules-must-log: one trace line per spent row.
fn spend_move_rows(statics: &[UnitStatic], next: &mut State, si: usize) {
    let unit = &statics[next.roster.profile[si]].name;
    for u in [Some(si), next.attached_to[si]].into_iter().flatten() {
        for r in next.buffs[u].iter().filter(|r| r.once && r.move_mod != 0) {
            trace_rule("utility-buff", &r.name, &format!("on {unit} is consumed by this move (applies once)"));
        }
    }
    mods::spend_once(next, si, &[mods::Role::Speed], false);
}

thread_local! {
    /// The once-per-game latch of the `bands_prefolded` trace line: printed
    /// on the FIRST move act the replay-aware arm turns off, never again.
    static PREFOLD_NOTE: std::cell::Cell<bool> = const { std::cell::Cell::new(false) };
}

/// EPOCH_19_MOVE_GRANTS_FOLD — the SOLO move-grant family folded for REAL.
/// The census read (`ctx_live`'s `solo_move_grants` loop) stays evidence-only
/// below the gate; from 19 a live grant of Slow, Fast, Swift, Rapid Advance
/// or Rapid Rush moves the unit at the one point the core spends a move
/// budget: this delta joins the per-activation `band_in` accumulation next
/// to Bounding/Grounded Speed/Speed Feat/Great Musician. A band recompute
/// was rejected, not chosen: the recorded games' `state.bands` already fold
/// every grant, so a recompute would double-count exactly the corpora the
/// epoch gate keeps byte-exact. The numbers are the registry's own
/// (`unit.rs::solo_move_grant_mods_of`, the table band pass's
/// `advance_mod`/`rush_mod`), never inches; a name the profile already
/// PRINTS is skipped (the loader's band fold already spent it, the table's
/// overlay never re-grants, main.gd:3858); granted Swift cancels a granted
/// Slow, and so does a PRINTED Swift. `kind` picks the band the way Speed
/// Feat does: `advance_mod` on an ADVANCE, `rush_mod` on a RUSH/CHARGE —
/// the charge inherits the rush band (movement_range_controller.gd:170-187).
///
/// The REPLAY-AWARE arm: `bands_prefolded` marks a header that carried
/// `"books"` — a TABLE recording (`act_recorder.gd:266-268`; no writer in
/// `core/nml-core/src` emits the key) — whose recorded `bands` already fold
/// every grant (`battle_sim.gd:1707 -> move_bands_for_props`), so this
/// function returns 0.0 and names the arm once per game on stderr; a fresh
/// core sim has no `books`, the flag is false, the delta folds as before.
/// The trace line fires the first time the arm does.
/// `trace` — the spend fold logs (true); the EV read through `live_bands_of`
/// passes false: the imagination never logs, the one real move does.
#[allow(clippy::too_many_arguments)] // the fold's own kind split reads one arg per band axis
fn solo_move_grant_delta_in(
    statics: &[UnitStatic], state: &State, si: usize, kind: i64, rules_epoch: u32,
    bands_prefolded: bool, trace: bool,
) -> f64 {
    if !rule_on(rules_epoch, EPOCH_19_MOVE_GRANTS_FOLD) {
        return 0.0;
    }
    if bands_prefolded {
        // One trace line the first time the arm fires for this game — the
        // fold is off, the recorded bands carry the grants.
        if !PREFOLD_NOTE.with(std::cell::Cell::get) {
            PREFOLD_NOTE.set(true);
            trace_rule("move-bands", "prefold", "recorded bands carry the grants, live delta off");
        }
        return 0.0;
    }
    let us = &statics[state.roster.profile[si]];
    let Some(stamp) = us.solo_move_grant_mods.as_ref() else {
        return 0.0;
    };
    let un = &us.name;
    // The kind split is Speed Feat's own: `advance_mod` on an ADVANCE,
    // `rush_mod` on a RUSH/CHARGE (the charge inherits the rush band),
    // nothing on the non-move kinds.
    let (adv_kind, moving) = match kind {
        ADVANCE => (true, true),
        RUSH | CHARGE => (false, true),
        _ => (false, false),
    };
    if !moving {
        return 0.0;
    }
    // Rules-must-log: every firing grant names itself the one time it moves
    // the band (the static band pass's own trace shape). A name whose faction
    // registry fields no entry spends 0.0 and stays silent.
    let band = if adv_kind { "advance" } else { "rush/charge" };
    let fire = |name: &'static str, v: f64| {
        if trace && v != 0.0 {
            trace_rule("move-bands", name, &format!("{un}: {v:+}\" {band} from a live grant"));
        }
        v
    };
    let mut d = 0.0;
    if mods::granted(state, si, "Fast") && !stamp.fast_printed {
        d += fire("Fast", if adv_kind { stamp.fast_advance } else { stamp.fast_rush });
    }
    if mods::granted(state, si, "Rapid Advance") && !stamp.rapid_advance_printed {
        d += fire("Rapid Advance", stamp.rapid_advance);
    }
    if mods::granted(state, si, "Rapid Rush") && !stamp.rapid_rush_printed
        && (kind == RUSH || !rule_on(rules_epoch, EPOCH_66_DISTANCE_TRUTH)) {
        d += fire("Rapid Rush", stamp.rapid_rush);
    }
    let slow = mods::granted(state, si, "Slow") && !stamp.slow_printed;
    if slow {
        if mods::granted(state, si, "Swift") || stamp.swift_printed {
            if trace {
                trace_rule("move-bands", "Swift", &format!("{un}: cancels the granted Slow"));
            }
        } else {
            d += fire("Slow", if adv_kind { stamp.slow_advance } else { stamp.slow_rush });
        }
    }
    d
}

/// evmove — the move bands the EVALUATOR reads: the static band plus the
/// granted solo family's delta, quiet (`trace=false`) — the seam behind
/// menu.rs's gap math, the playout's rush demotion, gate.rs's charge band,
/// score.rs's reachability and tokens.rs's band columns
/// (EV_GRANT_BLINDNESS_2026-09-15, family 1: bands gate every action). The
/// epoch gate is the stamp itself — `solo_move_grant_mods` is None below
/// EPOCH_19_MOVE_GRANTS_FOLD and wherever no registry entry carries numbers,
/// exactly where the spend fold answers 0.0 — so a pre-fold corpus reads its
/// static bands unchanged and the EV arm gains no epoch of its own.
///
/// Blindness family 6 (EV_VOCAB_2026-09-15 §4) rides the same seam: the
/// carried "Difficult Terrain" debuff caps BOTH bands exactly where
/// `mv::step::execute` caps the real move (`reach = band_in.min(
/// DIFFICULT_MOVE_CAP_IN)`, mv/step.rs:691) — after the grant delta, on
/// every arm, the early static one included.
pub fn live_bands_of(statics: &[UnitStatic], state: &State, i: usize) -> (f64, f64) {
    // No-grants shortcut (`ctx_live` takes the same one): every `granted*` read needs a record with a
    // non-empty `grants_rule` on the joined chain, so with none the move-grant delta is exactly `0.0`
    // (`x + 0.0` is spelled out to keep the bit pattern) and no terrain debuff is carried (`difficult`
    // is false). ONE `chain_has_grants` walk replaces the twelve `chain_grant` walks of the full body.
    if !mods::chain_has_grants(state, i) {
        let b = &state.bands[i];
        let stamped = statics
            .get(state.roster.profile[i])
            .and_then(|us| us.solo_move_grant_mods.as_ref())
            .is_some();
        return if stamped { (b.advance + 0.0, b.rush + 0.0) } else { (b.advance, b.rush) };
    }
    live_bands_walk(statics, state, i)
}

/// The full body of `live_bands_of`: one `solo_move_grant_delta_in` per band and the terrain-debuff
/// fold, each walking the joined buff chain. Reached only when the chain carries a grant record (and,
/// in the differential tests, as the reference the shortcut must equal bit for bit).
pub(crate) fn live_bands_walk(statics: &[UnitStatic], state: &State, i: usize) -> (f64, f64) {
    let b = &state.bands[i];
    // The stamp-first gate: an EMPTY statics slice (score()'s doctrine arm)
    // and every pre-fold or number-less profile answer the static bands here,
    // before the spend fold's own `statics[...]` index is ever reached.
    let (advance, rush) = if statics
        .get(state.roster.profile[i])
        .and_then(|us| us.solo_move_grant_mods.as_ref())
        .is_none()
    {
        (b.advance, b.rush)
    } else {
        (
            b.advance + solo_move_grant_delta_in(
                statics, state, i, ADVANCE, EPOCH_19_MOVE_GRANTS_FOLD, false, false,
            ),
            b.rush + solo_move_grant_delta_in(
                statics, state, i, RUSH, EPOCH_19_MOVE_GRANTS_FOLD, false, false,
            ),
        )
    };
    let (difficult, _) = terrain_debuff_folds(statics, state, i);
    if difficult {
        (
            advance.min(crate::gate::DIFFICULT_MOVE_CAP_IN),
            rush.min(crate::gate::DIFFICULT_MOVE_CAP_IN),
        )
    } else {
        (advance, rush)
    }
}

/// Blindness family 6 (EV_VOCAB_2026-09-15 §4) — the EV twin of the move
/// engine's own terrain-debuff reads: what a unit CARRYING a live
/// Difficult/Dangerous Terrain debuff (`mods::granted_terrain_debuff`) does
/// to its own priced movement. Answers `(difficult_cap, danger_loss)`: the
/// difficult flag caps the band read where `mv::step::execute` caps the real
/// move (mv/step.rs:691); the dangerous loss is the `dangerous_dice`
/// expectation — one `max(1, wounds_max)` die per alive mover
/// (dangerous_dice:2514-2526), wound on a 1 of the d6 tray the spend path
/// rolls (sim.rs:6381, `dangerous_wounds` counts 1s), so `dice / 6`. Flying
/// and Strider ignore difficult ground (p.11, mv/step.rs:1189), but only
/// Flying tests for nothing on the dangerous roll — Strider dodges the
/// difficult cap, never the dangerous dice (mv/step.rs:1188, the
/// dangerous_dice guard at :2479 and the `!flying` avoidance gates at
/// :1101/:1194 all agree). The ignore flags read the LIVE profile's
/// special rules exactly where those sites read them (`state.profile(si)`);
/// the charge arm's `charge_no_difficult` honour knob is a per-activation
/// table decision, not a unit property, so the band read does not model it.
///
/// The epoch rides EPOCH_27_TERRAIN_DEBUFF itself — the read fires exactly
/// when the rule exists, and since `State::buffs` is never serialised every
/// replay answers `(false, 0.0)` here regardless (menu.rs:240-247 doctrine):
/// the EV arms gain no epoch of their own.
pub(crate) fn terrain_debuff_folds(
    statics: &[UnitStatic], state: &State, si: usize,
) -> (bool, f64) {
    let Some(us) = statics.get(state.roster.profile[si]) else {
        return (false, 0.0);
    };
    let sr = state.profile(si).special_rules.as_slice();
    let flying = sr.iter().any(|r| r == "Flying");
    let strider = sr.iter().any(|r| r == "Strider");
    let difficult = !(flying || strider)
        && mods::granted_terrain_debuff(
            state, si, "Difficult Terrain", crate::acts::EPOCH_27_TERRAIN_DEBUFF,
        );
    let danger_loss = if flying
        || !mods::granted_terrain_debuff(
            state, si, "Dangerous Terrain", crate::acts::EPOCH_27_TERRAIN_DEBUFF,
        )
    {
        0.0
    } else if rule_on(us.rules_epoch, crate::acts::EPOCH_73_V36) {
        // UX-21 (rules 3.6): the whole joined unit tests once, for the wounds it has left.
        let mut chain = vec![si];
        chain.extend(state.attached[si].iter().copied());
        let dice: i64 = chain.iter().map(|&u| wounds_left(state, u)).sum();
        dice as f64 / 6.0
    } else {
        // `wounds_max` is the FULL model list and `positions` only the
        // survivors — the tail — exactly dangerous_dice's own counting; on a
        // charge every alive model moves, so every one of them rolls.
        let w = &us.wounds_max;
        let off = w.len().saturating_sub(state.positions[si].len());
        let dice: i64 = (0..state.positions[si].len())
            .map(|m| w.get(off + m).copied().unwrap_or(1).max(1))
            .sum();
        dice as f64 / 6.0
    };
    (difficult, danger_loss)
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
    if trace_rules_on() {
        eprintln!("[{arm}] {rule} — {detail}");
    }
}

const AIRCRAFT_MOVE_IN: f64 = 30.0;
const AIRCRAFT_HEADINGS: usize = 16;
/// Rules 3.6 `Aircraft` (`EPOCH_73_V36`), `_act_aircraft` :2968 / `_aircraft_heading` :3018: a mandatory straight 30" run
/// toward an enemy centre or one of 16 compass points, legal while it stays on the board, the best volley from the
/// endpoint wins (1e-4 better; ties to the larger edge margin). `None` = no board or no legal lane.
pub(crate) fn aircraft_delta(statics: &[UnitStatic], state: &State, si: usize, t: &Terrain, shelf: bool, rules_epoch: u32) -> Option<V3> {
    let board = t.board_in(); // an absent board is [0, 0]: no lane is legal, the answer is None
    // The table's `los_checker` (main.gd:3373): point to point, infantry height, terrain volumes only.
    let (zones, h) = (board_zones(t, shelf, rules_epoch), sight::height_in_for_base_mm(sight::DEFAULT_BASE_MM) * IN2M);
    let cyl = |p: V3| sight::Cyl { c: [p[0] as f64, p[2] as f64], r: 0.0, y0: 0.0, y1: h };
    let (c, us, mut sc) = (geom::centre(&state.positions[si]), &statics[state.roster.profile[si]], Scratch::default());
    // The heading's EV prices the PRINTED reach: `profiles_in_range` carries no `shooting_range_bonus` (:3038).
    let bare: Vec<ShootProfile> = us.shoot.iter().cloned().map(|p| ShootProfile { reach_bonus_in: 0.0, ..p }).collect();
    let base_r = state.radii[si].iter().copied().fold(DEFAULT_BASE_RADIUS_M, f64::max);
    let own_r = crate::deployment::deploy_footprint_radius(state.alive[si] as usize, base_r);
    let lim = [board[0] * 0.5 * IN2M - 0.02 - own_r, board[1] * 0.5 * IN2M - 0.02 - own_r];
    let foes: Vec<usize> = crate::menu::enemy_keys(state, si).into_iter().filter(|&e| !state.dormant[e] && state.attached_to[e].is_none()).collect();
    let mut heads: Vec<V3> = foes.iter().map(|&e| geom::sub(geom::centre(&state.positions[e]), c))
        .filter(|d| d[0].hypot(d[2]) > 0.001).map(|d| geom::normalized([d[0], 0.0, d[2]])).collect();
    heads.extend((0..AIRCRAFT_HEADINGS).map(|i| (std::f64::consts::TAU * i as f64 / AIRCRAFT_HEADINGS as f64) as f32)
        .map(|a| [a.cos(), 0.0, a.sin()]));
    let mut best: Option<(f64, f64, V3)> = None;
    for h in heads {
        let delta = geom::mul(h, AIRCRAFT_MOVE_IN * IN2M);
        let end = geom::add(c, delta);
        let (mx, mz) = (lim[0] - (end[0] as f64).abs(), lim[1] - (end[2] as f64).abs());
        if mx < 0.0 || mz < 0.0 { continue; }
        let mut ev = 0.0f64;
        for &e in &foes {
            let ec = geom::centre(&state.positions[e]);
            if sight::has_los(&cyl(end), &cyl(ec), false, &zones, &[]) {
                profiles_of(us, state.alive[si], 0.0, &mut sc);
                let def = ctx_of(&statics[state.roster.profile[e]], state, e);
                let d = geom::length(geom::sub(end, ec)) as f64 / IN2M;
                ev = ev.max(shoot_ev(&bare, &sc.keep, &sc.attacks, &ctx_of(us, state, si), &def, d));
            }
        }
        let margin = mx.min(mz);
        if best.is_none_or(|(be, bm, _)| ev > be + 1e-4 || ((ev - be).abs() <= 1e-4 && margin > bm)) {
            best = Some((ev, margin, delta));
        }
    }
    best.map(|b| b.2)
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
                .map(|w| w.range as f64 + w.reach_bonus_in)
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

/// meleefix: `MoveIntent.distance_inches(a, b)` with the table's arithmetic: the XZ difference in f32 (`Vector3`), its f32 length
/// (`geom::length`), widened and divided by 0.0254 in f64 (GDScript float). Positions are f32 values held in f64, so the narrowing is exact.
fn table_inches(a: V3, b: V3) -> f64 {
    geom::length([b[0] - a[0], 0.0, b[2] - a[2]]) as f64 / crate::IN2M
}

/// meleefix (`EPOCH_96_PARITY_BATCH`): `SoloController._units_controlling` - the units of the winner's side (`own`) or the
/// other side that hold `o`: alive, not Shaken, not in reserve, not a joined hero, not Aircraft, a model centre within 3 in (+0.001).
fn holders_at(next: &State, winner: usize, o: V3, own: bool, skip: Option<usize>) -> usize {
    let pid = next.player[winner];
    let near = |p: &[f64; 3]| table_inches(geom::to_f32(*p), o) <= crate::OBJECTIVE_CONTROL_IN + 0.001;
    (0..next.units()).filter(|&k| Some(k) != skip && (next.player[k] == pid) == own && next.alive[k] > 0 && !next.shaken[k] && !next.dormant[k]
        && next.attached_to[k].is_none() && !next.aircraft[k] && next.positions[k].iter().any(near)).count()
}

/// meleefix (`EPOCH_96_PARITY_BATCH`): the table's goal for a melee winner's 3 in move (`consolidate_after_melee_win` ->
/// `_nearest_uncontrolled_objective`, NML-210), read on the state after the fight from the planner inputs the door sent: a `seize`
/// task's marker (none once the side holds it by a live majority; 2.5 in to the side on a laned pair), a `fight` task's garrison
/// (the marker within 3 in only this unit holds), else the tiered greedy (holdable before contested, unclaimed before claimed when
/// the spread is on, nearer first), else the nearest enemy's centre. Same f32 / f64 arithmetic as the table, step for step.
pub fn planned_consolidation_goal(next: &State, winner: usize, plan: &ConsolidatePlan) -> Option<V3> {
    let centre = geom::centre(&next.positions[winner]);
    let marker = |i: i64| next.objectives.get(usize::try_from(i).ok()?).map(|o| geom::to_f32(o.pos));
    let objective = match (plan.planner, plan.task.as_str(), marker(plan.marker)) {
        (true, "seize", Some(m)) if holders_at(next, winner, m, true, Some(winner)) > holders_at(next, winner, m, false, None) => None,
        (true, "seize", Some(m)) if plan.lane => {
            // `dirv = mpos - from; dirv.y = 0; perp = Vector3(-dirv.z, 0, dirv.x).normalized(); mpos + perp * (2.5 * 0.0254)`
            let d = geom::sub(m, centre);
            Some(geom::add(m, geom::mul(geom::normalized([-d[2], 0.0, d[0]]), 2.5 * crate::IN2M)))
        }
        (true, "seize", Some(m)) => Some(m),
        (true, "fight", _) => garrison_marker(next, winner),
        _ => greedy_objective(next, winner, centre, plan),
    };
    objective.or_else(|| nearest_enemy_of(next, winner).map(|e| geom::centre(&next.positions[e])))
}

/// meleefix: `SoloController._garrisoned_marker` - the nearest marker within 3 in (+0.001) of a model of the unit that no other unit of
/// its side holds; none for a Shaken or Aircraft unit.
fn garrison_marker(next: &State, winner: usize) -> Option<V3> {
    if next.shaken[winner] || next.aircraft[winner] {
        return None;
    }
    let mut best: Option<(f64, V3)> = None;
    for o in &next.objectives {
        let pos = geom::to_f32(o.pos);
        let gap = next.positions[winner].iter().map(|p| table_inches(geom::to_f32(*p), pos)).fold(f64::INFINITY, f64::min);
        if gap > crate::OBJECTIVE_CONTROL_IN + 0.001 || holders_at(next, winner, pos, true, Some(winner)) > 0 {
            continue;
        }
        if best.is_none_or(|(bd, _)| gap < bd) {
            best = Some((gap, pos));
        }
    }
    best.map(|(_, p)| p)
}

/// meleefix: the greedy tail of `_nearest_uncontrolled_objective` - skip a marker the side owns (owner 0 is neutral, never a side's)
/// or holds by a live majority; tier = holdable (no enemy holds it) x2 + unclaimed (spread off, or no runner booked) x1; the higher
/// tier, then the nearer marker wins.
fn greedy_objective(next: &State, winner: usize, centre: V3, plan: &ConsolidatePlan) -> Option<V3> {
    let mut best: Option<(i32, f64, V3)> = None;
    for (i, o) in next.objectives.iter().enumerate() {
        let pos = geom::to_f32(o.pos);
        let enemy_near = holders_at(next, winner, pos, false, None);
        if (o.owner != 0 && o.owner == next.player[winner]) || holders_at(next, winner, pos, true, Some(winner)) > enemy_near {
            continue;
        }
        let unclaimed = !plan.spread || plan.runners.get(i).copied().unwrap_or(0) == 0;
        let tier = if enemy_near == 0 { 2 } else { 0 } + i32::from(unclaimed);
        let d = table_inches(centre, pos);
        if best.is_none_or(|(bt, bd, _)| tier > bt || (tier == bt && d < bd)) {
            best = Some((tier, d, pos));
        }
    }
    best.map(|(_, _, p)| p)
}

/// The placeholder a melee line carries where the table cites its rules book; the charge door fills it in
/// (`CoreActivation.drive`), since the core holds no book version.
pub const CITE: &str = "{cite}";

/// One table melee line on a supplied tray (a seeded tray says nothing).
fn say_melee(tray: &mut Tray, side: i64, text: String) {
    tray.say(|| LogLine { rule: "melee", category: Category::Combat, side, text, detail: None });
}

/// Consolidation Moves (GF v3.5.1 p.9; the table's `_solo_consolidate_melee`), seam-gated by `consolidate`
/// and, from `EPOCH_73_V36`, by the epoch alone. One side destroyed: the survivor may move up to 3" via the
/// SAME routed chain `plain_move` gives ADVANCE/RUSH. From 73 also neither destroyed: the charger moves back 1",
/// the sides counted with their joined heroes, then on the dice path the move's Dangerous terrain test
/// (`_run_ai_dangerous(unit, dang)`: one die per affected model; `no_dangerous` is the RED switch of the MOVE's
/// test, which the gate turns off when the tray already spent that leg, so this later test ignores it).
fn consolidate_after_melee(next: &mut State, statics: &[UnitStatic], cover: Cover, seams: Seams, si: usize, ti: usize, mut dice: Option<(&mut Tray, &mut ShootResult)>) {
    let v36 = rule_on(seams.rules_epoch, EPOCH_73_V36);
    let (sa, ta) = if v36 { (combined_alive(next, si, seams), combined_alive(next, ti, seams)) } else { (next.alive[si], next.alive[ti]) };
    let sep = v36 && sa > 0 && ta > 0;
    let winner = if (ta <= 0 && sa > 0) || sep {
        si
    } else if sa <= 0 && ta > 0 {
        ti
    } else {
        return;
    };
    let Cover::Board(t) = cover else { return };
    if next.alive[winner] <= 0 || (sep && next.alive[ti] <= 0) {
        return;
    }
    // The table's consolidation lines (`_solo_consolidate_melee`): the separation always, a win's move or its hold.
    let wname = statics[next.roster.profile[winner]].name.clone();
    let side = next.player[winner];
    let say = |dice: &mut Option<(&mut Tray, &mut ShootResult)>, text: String| if let (true, Some((tray, _))) = (v36, dice.as_mut()) { say_melee(tray, side, text) };
    let holds = format!("Consolidation: {wname} holds its ground (enemy destroyed, no room to move — {CITE})");
    let (goal, band_in, what) = if sep {
        let (c, d) = (geom::centre(&next.positions[si]), geom::centre(&next.positions[ti]));
        (geom::sub(geom::mul(c, 2.0), d), 1.0, "moves back 1\" (the charger separates)")
    } else {
        // meleefix: the table's planner goal when the transcript carries its inputs (from EPOCH_96_PARITY_BATCH), else the old greedy.
        let key = next.roster.keys[winner].clone();
        let plan = dice.as_ref().and_then(|(tray, _)| tray.consolidation_of(&key)).filter(|_| rule_on(seams.rules_epoch, crate::acts::EPOCH_96_PARITY_BATCH)).cloned();
        let goal = match &plan { Some(p) => planned_consolidation_goal(next, winner, p), None => consolidation_goal(next, winner) };
        let Some(goal) = goal else { return say(&mut dice, holds) };
        (goal, CONSOLIDATE_WIN_IN, "consolidates up to 3\" (enemy destroyed)")
    };
    let land = (crate::mv::step::MoveRules { rules_epoch: seams.rules_epoch }).plain_move(
        next, t, winner, goal, band_in, seams.hero_attach, true, crate::mv::FAST_PLANNER_GUARD);
    let moved = land.as_ref().is_some_and(|l| l.movers.iter().zip(&l.end).any(|(m, e)| geom::length(geom::sub(*e, geom::to_f32(next.positions[m.unit][m.model]))) > 0.0005));
    if sep {
        // The table says what the models really did (`_solo_consolidate_melee`): the step back, or that no legal spot let them take it.
        say(&mut dice, if moved { format!("Consolidation: {wname} moves back 1\" (the charger separates — {CITE})") }
            else { format!("Consolidation: {wname} stays put (no legal spot to move back 1\" — {CITE})") });
    } else {
        say(&mut dice, if moved { format!("{wname} consolidates up to 3\" (enemy destroyed — {CITE})") } else { holds });
    }
    if let Some(land) = land {
        // `_execute_move` tests only a move that moved (its 0.0005 m early-out); the count reads the pre-move state.
        let moved = land.movers.iter().zip(&land.end).any(|(m, e)| geom::length(geom::sub(*e, geom::to_f32(next.positions[m.unit][m.model]))) > 0.0005);
        let name = statics[next.roster.profile[winner]].name.clone();
        let mut n = 0;
        if let (true, true, Some((_, shot))) = (v36, moved, dice.as_mut()) {
            shot.log.push(format!("Consolidation: {name} {what}"));
            n = dangerous_dice(statics, next, next, winner, seams, Some(&land), cover, shot, true);
        }
        land.spend_sidestep(next);
        for (i, m) in land.movers.iter().enumerate() {
            next.positions[m.unit][m.model] = geom::to_f64(land.end[i]);
        }
        // Wave 4 (port-entrenched) — consolidation counts as moving.
        stamp_moved(next, winner, seams.hero_attach, seams.rules_epoch);
        if let (true, Some((tray, shot))) = (n > 0, dice) {
            shot.log.push(format!("Dangerous terrain: {name} takes one test for the whole unit ({n} dice)"));
            tray.owner_next(Some(winner));
            tray.name_next("dangerous"); // the table's kind (main.gd `_run_ai_dangerous`): its dice line counts the 1s
            let faces = tray.roll(n as usize);
            let w = dangerous_wounds(&faces);
            shot.rolls.push(crate::dice::Roll { kind: "attack", count: n, target: DANGEROUS_TARGET, faces, owner: name });
            if w > 0 {
                land_wounds_with(next, winner, w, seams.tray_exact, seams.rules_epoch);
            }
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

/// The Grounded Speed read (epoch 7) — the per-activation conditional band
/// (aof "Grounded Speed", `rules_mechanics_aof.json`): "+2\" on Advance, +4\"
/// on Rush/Charge during this activation" while MOST of the unit's models are
/// within the entry's own `terrain_within_in` of terrain when activated. The
/// condition is answered LIVE from the ACTIVATION-START picture — the
/// pre-move `state.positions`/`state.radii` against `terrain::base_in_terrain`
/// with the base radius widened by the rule's own proximity (the
/// dangerous-terrain triggers' semantics, sim.rs:1927) over the untyped class
/// `terrain::is_any` (the book text restricts no terrain kind) — so the core's
/// own terrain picture answers it WITHOUT a new shared signature. An absent
/// board reads false: the condition honestly fails without terrain. The bonus
/// is added at `band_in` assembly, never pre-folded into the recorded bands
/// (no double-count of `move_bands`); the log line is Bounding's
/// (sim.rs:4313) shape.
fn grounded_speed_bonus_in(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    cover: Cover,
    rules_epoch: u32,
    kind: i64,
) -> f64 {
    let Some(gs) = &statics[state.roster.profile[si]].grounded_speed else {
        return 0.0;
    };
    if !rule_on(rules_epoch, EPOCH_7_TABLE_RULES) {
        return 0.0;
    }
    let Cover::Board(t) = cover else {
        return 0.0;
    };
    let models = state.positions[si].len();
    if models == 0 {
        return 0.0;
    }
    let near = state
        .positions
        .get(si)
        .map(|ps| {
            ps.iter()
                .enumerate()
                .filter(|(m, p)| {
                    let r = state.radii[si].get(*m).copied().unwrap_or(DEFAULT_BASE_RADIUS_M)
                        + gs.terrain_within_in * IN2M;
                    crate::terrain::base_in_terrain(
                        crate::geom::to_f32(**p),
                        r,
                        t,
                        crate::terrain::is_any,
                    )
                })
                .count()
        })
        .unwrap_or(0);
    if near * 2 <= models {
        return 0.0;
    }
    (match kind {
        ADVANCE => gs.advance_mod,
        RUSH | CHARGE => gs.rush_mod,
        _ => 0,
    }) as f64
}

/// The Grounded Stealth read (`EPOCH_60_GROUNDED_STEALTH`, D-STEALTH
/// 15.09.) — the Stealth family's terrain-conditional alias gate, resolved
/// LIVE at the def build (shooting AND melee): the alias applies only while
/// the TARGET actually stands in/at terrain — per model
/// `terrain::base_in_terrain` with the base radius widened by the alias's
/// proximity (`unit::STEALTH_ALIAS_TERRAIN_WITHIN_IN`), class
/// `terrain::is_any` (the book text restricts no terrain kind) — the SAME
/// per-model read Grounded Speed's verdict answers, and the majority fold
/// the family's unit-level shape keeps (`near * 2 > models`, the fold the
/// table's replaced majority-in-cover-CELL approximation had). An armed
/// alias whose read fails is stood down here (the penalty zeroed), so both
/// the shooting and the melee fold consume a closed gate.
/// Rules 3.6 (SHO-09b): the same majority verdict stamps `def.near_terrain`
/// on every target this seam builds, alias carrier or not, so the shared
/// conditional-AP predicate reads one sampler instead of a second geometry.
/// Rules-must-log: both verdicts trace, the trace names the rule and the
/// verdict. `Cover::Recorded` replays read false = gate closed (records
/// below 57 never consult this read at all — the stamp is gated).
fn stealth_alias_terrain_gate(
    statics: &[UnitStatic],
    state: &State,
    ti: usize,
    cover: Cover,
    def: &mut Ctx,
) {
    let open = match cover {
        // A replayed node carries no board: the read is honest false and the
        // gate closes.
        Cover::Recorded(_) => true,
        Cover::Board(t) => {
            let models = state.positions.get(ti).map(|ps| ps.len()).unwrap_or(0);
            let near = state
                .positions
                .get(ti)
                .map(|ps| {
                    ps.iter()
                        .enumerate()
                        .filter(|(m, p)| {
                            let r = state.radii[ti].get(*m).copied().unwrap_or(DEFAULT_BASE_RADIUS_M)
                                + crate::unit::STEALTH_ALIAS_TERRAIN_WITHIN_IN * IN2M;
                            crate::terrain::base_in_terrain(
                                crate::geom::to_f32(**p),
                                r,
                                t,
                                crate::terrain::is_any,
                            )
                        })
                        .count()
                })
                .unwrap_or(0);
            near * 2 <= models
        }
    };
    // Rules 3.6 (SHO-09b): the same majority read answers the conditional-AP arm, so it stamps on
    // every target this seam builds — not only on the alias carriers below (`open` is its inverse).
    def.near_terrain = !open;
    if !def.stealth_alias_near_terrain {
        return;
    }
    let unit = &statics[state.roster.profile[ti]].name;
    if open {
        def.stealth_alias_penalty = 0;
        trace_rule("grounded-stealth", unit, "in the open -> no -1 to hit (the gate holds)");
    } else {
        trace_rule("grounded-stealth", unit, "within 1\" of terrain -> -1 to hit");
    }
}

/// `(Terrain::uid, shelf reading, rules epoch, the board's sight volumes)`.
type BoardZones = Option<(u64, bool, u32, Rc<Vec<sight::Zone>>)>;

thread_local! {
    /// SHO-PAR-F3 — the last board's sight volumes, keyed on its content identity (`Terrain::uid`), the shelf
    /// reading and the rules epoch (a ruin is a volume at 72 and none at 73), so the moved-shooter gate does not
    /// flood-fill the board again on every candidate it scores.
    static BOARD_ZONES: std::cell::RefCell<BoardZones> = const { std::cell::RefCell::new(None) };
}

/// `sight::zones_of_with_at(t, shelf, rules_epoch)`, remembered for the last board. A bare `Default` board (uid 0)
/// has no identity and is built fresh every call; a hit needs the same uid, which `Terrain` mints anew on every
/// content change.
fn board_zones(t: &Terrain, shelf: bool, rules_epoch: u32) -> Rc<Vec<sight::Zone>> {
    if t.uid() == 0 {
        return Rc::new(sight::zones_of_with_at(t, shelf, rules_epoch));
    }
    BOARD_ZONES.with(|c| {
        let mut c = c.borrow_mut();
        match c.as_ref() {
            Some((uid, sh, ep, z)) if *uid == t.uid() && *sh == shelf && *ep == rules_epoch => Rc::clone(z),
            _ => {
                let z = Rc::new(sight::zones_of_with_at(t, shelf, rules_epoch));
                *c = Some((t.uid(), shelf, rules_epoch, Rc::clone(&z)));
                z
            }
        }
    })
}

/// `TerrainRules.base_fully_in_cover` terrain_rules.gd:64 — the centre AND 8 rim points all give cover (`r <= 0`: the centre alone).
fn base_fully_in_cover(p: V3, r: f64, t: &Terrain) -> bool {
    gives_cover(t.type_at(p))
        && (r <= 0.0
            || (0..8).all(|i| {
                let a = std::f64::consts::TAU * i as f64 / 8.0;
                gives_cover(t.type_at(geom::add(p, [(a.cos() * r) as f32, 0.0, (a.sin() * r) as f32])))
            }))
}

/// The mover's cover flag after a move. Below `EPOCH_73_V36` the host's centre cell. From it every moving member —
/// the host and its joined heroes — is read the way `main._solo_majority_in_cover` :10498 reads it (Grounded Precision
/// asks AFTER the move): a unit built with one model by its centre, a squad when more than half of its bases lie
/// fully inside. A flag that changes is logged under its book name (rules-must-log).
fn land_cover(statics: &[UnitStatic], next: &mut State, si: usize, t: &Terrain, seams: Seams, mut shot: Option<&mut ShootResult>) {
    if !rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
        next.in_cover[si] = gives_cover(t.type_at(geom::centre(&next.positions[si])));
        return;
    }
    let chain: Vec<usize> = std::iter::once(si).chain(next.attached[si].iter().copied().filter(|_| seams.hero_attach)).collect();
    for u in chain {
        let single = next.profile(u).model_count <= 1;
        let fully = (0..next.positions[u].len()).filter(|&k| {
            let r = if single { 0.0 } else { next.radii[u].get(k).copied().unwrap_or(DEFAULT_BASE_RADIUS_M) };
            base_fully_in_cover(geom::to_f32(next.positions[u][k]), r, t)
        });
        let now = fully.count() * 2 > next.positions[u].len();
        if let (true, Some(s)) = (now != next.in_cover[u], shot.as_deref_mut()) {
            s.log.push(format!("Cover: {} {} cover at its landing", statics[next.roster.profile[u]].name, if now { "is in" } else { "leaves" }));
        }
        next.in_cover[u] = now;
    }
}

/// P3 step 13 - the parts of one activation's move band. `total` sums them in exactly the order the real move
/// always did (a float sum depends on its order), so the move and the allowance spend one number, bit for bit.
#[derive(Clone, Copy, Debug)]
pub(crate) struct BandParts {
    pub base: f64, pub bounding: f64, pub vr: f64, pub gs: f64,
    pub feat: f64, pub buff: f64, pub grant: f64, pub rapid_mark: f64,
    /// Ruling D17: the command-group Musician's inch (`command_musician_in`), 0.0 below its placeholder.
    pub cmd: f64,
}

impl BandParts {
    pub(crate) fn total(&self) -> f64 {
        self.base + self.bounding + self.vr + self.gs + self.feat + self.buff + self.grant + self.rapid_mark + self.cmd
    }
}

/// The eight band reads of `resolve_with` (its comments name each rule), in its order. Pure: the Speed Feat latch
/// stamp and every log line stay with the caller. `trace` is `solo_move_grant_delta_in`'s last argument.
#[allow(clippy::too_many_arguments)]
pub(crate) fn band_parts(
    statics: &[UnitStatic], state: &State, next: &State, si: usize, kind: i64, ci: Option<usize>,
    bounding_in: f64, cover: Cover, seams: Seams, trace: bool,
) -> BandParts {
    let vr_on = seams.versatile_reach || rule_on(seams.rules_epoch, 1);
    let vr = versatile_reach_charge_in(statics, next, si, kind, ci, bounding_in, vr_on, seams.rules_epoch);
    let gs = grounded_speed_bonus_in(statics, state, si, cover, seams.rules_epoch, kind);
    let feat = speed_feat_band_in(statics, next, si, kind, seams.rules_epoch);
    let buff = live_move_bonus_in(next, statics, si, seams.rules_epoch);
    let grant = solo_move_grant_delta_in(statics, next, si, kind, seams.rules_epoch, seams.bands_prefolded, trace);
    let rapid_mark = rapid_charge_mark_bonus_in(statics, next, si, ci, kind, seams.rules_epoch);
    let b = &next.bands[si];
    let base = match kind {
        ADVANCE => b.advance,
        RUSH => b.rush,
        // CHARGE reads the table's distinct `charge` band from `EPOCH_10_CHARGE_BAND` on (solo_controller.gd:1647);
        // below it the pre-port reading stays `rush`, so existing corpora replay byte-exact.
        CHARGE if rule_on(seams.rules_epoch, EPOCH_10_CHARGE_BAND) => b.charge.unwrap_or(b.rush),
        CHARGE => b.rush,
        _ => 0.0,
    };
    let cmd = command_musician_in(statics, next, si, kind, seams.rules_epoch).0;
    BandParts { base, bounding: bounding_in, vr, gs, feat, buff, grant, rapid_mark, cmd }
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
    if kind != HOLD && kind != ADVANCE && kind != RUSH && kind != CHARGE && kind != REPOSITION {
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
    let named = state.roster.index.get(charge_key.as_str()).copied().filter(|_| !charge_key.is_empty());
    let lone = named.and_then(|c| lone_hero_of(state, c, seams).map(|h| (c, h)));
    let ci = lone.map(|(_, h)| h).or_else(|| named.map(|c| combat_unit(state, c, seams)));
    let pi_s = state.roster.profile[si];
    let mut next = state.clone();
    let was_shaken = next.shaken[si];
    let mut sc = Scratch::default();
    // #816 PR 2 — the activation-start latch clear (main.gd:17456's erase).
    next.teleport_used[si] = false;
    next.cast_buffs.clear(); // CAST-O7: a board that already ran an activation carries no ledger into this one
    next.casualty_f32 = rule_on(seams.rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH);
    sc.rules_epoch = seams.rules_epoch; // wave-3 mark consumers read it off Scratch

    // --- REANIMATION (main.gd:953-957), the activation trigger BEFORE the
    // action — every action kind with a tray. See `tray_reanimation`; a
    // full-strength or Shaken carrier rolls nothing.
    // D-PAR3 14a: skipped when the table's capture already holds the start it paid (`Input::Paid { start }`).
    if let Some((tray, shot)) = dice.as_mut().filter(|(tray, _)| !tray.paid_start()) {
        let board = match cover { Cover::Board(t) if t.is_valid() => Some(t), _ => None };
        tray_reanimation(statics, &mut next, si, seams, tray, shot, board);
        // Surprise Attack (wave-5) — the same activation-trigger slot, the
        // book's own "first time this unit is activated" beat; see above.
        tray_surprise_attack(statics, state, &mut next, si, seams, tray, shot);
    }

    // --- EPOCH_26_PLACE_D3 — the D3" activation placement, BEFORE the move
    // (the table rolls it at the activation's head, solo_controller.gd:1688-
    // 1710). A RECORDED act replays the table's band-bonus model byte-exact
    // (`bounding_bonus_in` above) — the hop is the FRESH arm. Below the gate
    // every corpus replays the plain reading, byte-exact. From EPOCH_73_V36
    // Every Bounding-primitive carrier spends the roll as a move instead (UX-17, UX-18).
    let mut move_d3_in = 0.0;
    let hop_log = if rule_on(seams.rules_epoch, crate::acts::EPOCH_26_PLACE_D3)
        && bounding_bonus_in(action) == 0.0
        && matches!(kind, ADVANCE | RUSH | CHARGE)
    {
        statics[pi_s].bounding_place.as_ref().and_then(|spec| {
            if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
                bounding_move_in(spec, rng.as_deref_mut()).map(|(inches, line)| {
                    move_d3_in = inches;
                    line
                })
            } else {
                place_d3_hop(&mut next, si, cover, spec, rng.as_deref_mut())
            }
        })
    } else {
        None
    };

    // --- move (battle_sim.gd:575-596) ---
    // `SoloController.sim_move_bands(su["unit"])` is a pure read of the unit's
    // rules (bands + the Musician bonus, solo_controller.gd:4966-4982), flattened
    // into the profile table at capture; RUSH and CHARGE share the rush band.
    let bounding_in = bounding_bonus_in(action) + move_d3_in;
    // Versatile Reach — the witness policy evaluated at the resolve seam, the
    // same seam Bounding rides (`sim::versatile_reach_charge_in`). CLASS FIX
    // (external review 03.09. item 3 / F9, `acts::rule_on`): a pre-epoch
    // record with the boolean legacy-OFF (or absent) stays unaffected;
    // `rules_epoch >= 1` turns this rule on regardless of the boolean.
    // Grounded Speed (epoch 7) — the LIVE per-activation read: the majority
    // condition sees the activation-START positions (`state`), never the
    // landing (`next` after the move below).
    // FEAT PR 1 — Speed Feat, the once-per-game latch's first reader: the
    // table's move pass spends it at `rounds_left <= 2` (solo_controller.gd:
    // 1704-1726) and rides +advance/+rush on this one activation's bands, so
    // a recorded endgame push replays at its recorded dest (the replay's own
    // `state.bands` never carry the feat — the import's band pass skips
    // `uses_per_game` entries, list_to_profile.py:567). Unspent + endgame +
    // epoch 7 grants the bonus and stamps the latch; a later act sees the
    // folded name and never grants again. Below `EPOCH_7_TABLE_RULES` the
    // read is inert — an older record keeps every replay byte-identical.
    // The Great Musician port: the LIVE move-knob read, folded AFTER the
    // `match kind` so ADVANCE, RUSH and CHARGE all receive it — which is what
    // `move_bands_for_props` does (rush += spell; charge = rush + charge_extra,
    // movement_range_controller.gd:168-170).
    // EPOCH_19 — the granted SOLO move family, folded for real at the spend
    // (see `solo_move_grant_delta_in`): the same live read the census loop
    // below only logs below the gate.
    let parts = band_parts(statics, state, &next, si, kind, ci, bounding_in, cover, seams, true);
    let (gs_in, feat_in, rapid_mark_in) = (parts.gs, parts.feat, parts.rapid_mark);
    if feat_in != 0.0 {
        Rc::make_mut(&mut next.feats_used)[si].push(
            statics[pi_s]
                .speed_feat
                .as_ref()
                .expect("granted ⇒ stamped")
                .name
                .clone(),
        );
    }
    let band_in = parts.total();
    if let (Some(line), Some((tray, shot))) = (command_musician_in(statics, &next, si, kind, seams.rules_epoch).1, dice.as_mut()) {
        // ruling D17: the Musician's inch, given, taken back or gone with its bearer
        say_rule(tray, "musician", state.player[si], || line.clone());
        shot.log.push(line);
    }
    // DS-GMC2 (`EPOCH_92_MELEE_CAUSES`, table twin `SoloController.melee_shroud_charge_in`):
    // Melee Shrouding shortens the working CHARGE band (-2"/-3", floor 6") against a shrouded target.
    let band_in = if kind == CHARGE && rule_on(seams.rules_epoch, EPOCH_92_MELEE_CAUSES) {
        ci.map_or(band_in, |ti| crate::gate::melee_shroud_charge_in(band_in, &next, ti))
    } else {
        band_in
    };
    // Rules 3.6 (G4-H7): a charge on a unit with no living model, host and joined heroes, is void - the table logs
    // "the charge falls short" and moves nothing, so there is no move, no Dangerous test and no fight.
    let charge_void = kind == CHARGE
        && rule_on(seams.rules_epoch, EPOCH_73_V36)
        && ci.is_some_and(|ti| combined_alive(state, ti, seams) <= 0);
    let band_in = if charge_void { 0.0 } else { band_in };
    if charge_void {
        if let Some((_, shot)) = dice.as_mut() {
            shot.log.push(format!("{}'s charge falls short: the target has no models left", statics[pi_s].name));
        }
    }
    if rapid_mark_in > 0.0 {
        if let (Some(ti), Some((_, shot))) = (ci, dice.as_mut()) {
            shot.log.push(format!("Rapid Charge Mark: +{rapid_mark_in:.0}\" charge reach against {}",
                statics[next.roster.profile[ti]].name));
        }
    }
    // NML-1152 B14 step 1 — rules-must-log: the live read names itself the
    // one time it changes the band (Bounding's line above is the shape).
    if gs_in != 0.0 {
        if let Some((_, shot)) = dice.as_mut() {
            shot.log.push(format!(
                "Grounded Speed: {} \u{2014} +{gs_in:.0}\" band (most models within 1\" of terrain)",
                statics[pi_s].name
            ));
        }
    }
    // NML-1152 B14 step 1 — rules-must-log: the ONLY table die this port does
    // not draw itself, named here (dice.rs's `ShootResult.log` precedent) the
    // one time it changes the band. A fresh EPOCH_73_V36 move logs its own
    // line (the hop line below).
    if bounding_in != 0.0 && move_d3_in == 0.0 {
        if let Some((_, shot)) = dice.as_mut() {
            shot.log.push(format!(
                "Bounding: {} — +{bounding_in:.0}\" every move band this activation",
                statics[pi_s].name
            ));
        }
    }
    // EPOCH_26_PLACE_D3 — rules-must-log: ONE trace line per hop, naming the
    // rule and the rolled distance (`place_d3_hop` above), or per EPOCH_73_V36
    // rolled move (`bounding_move_in`).
    if let Some(line) = hop_log {
        // Rules 3.6 (row W1.TRACE) — the Bounding hop names itself once
        // (arm `bounding`), recorded band leg excluded by construction.
        if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
            trace_rule("bounding", "Bounding", &line);
        }
        if let Some((_, shot)) = dice.as_mut() {
            shot.log.push(line);
        }
    }
    if feat_in != 0.0 {
        if let Some((_, shot)) = dice.as_mut() {
            shot.log.push(format!(
                "Speed Feat: {} — +{feat_in:.0}\" {} band this activation (once per game)",
                statics[pi_s].name,
                if kind == ADVANCE { "Advance" } else { "Rush" }
            ));
        }
    }
    let mut moved = false;
    // D5-1 — what the band still has left after the charge move, and so what
    // the melee snap may spend (solo_controller.gd:8659). Infinite while the
    // seam is off: the second engage gate then never refuses anything, which is
    // what every corpus recorded before D5-1 replayed with.
    let mut charge_remaining_in = if seams.movement && !seams.plain_only && rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
        band_in.max(0.0)
    } else { f64::INFINITY };
    let mut charge_arcs: Option<(Vec<f64>, f64)> = None;
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
    // Rules 3.6 Aircraft (`EPOCH_73_V36`): the straight run replaces the band move, no planner/spacing/Dangerous test (:3080).
    let mut flew = false;
    // One-core P3: a supplied tray may carry the player's own per-model end positions for an
    // ADVANCE/RUSH; they replace every move arm below. Seeded trays never carry one (inert).
    let placed: Option<Vec<[f64; 3]>> = dice.as_ref().and_then(|d| d.0.placed().map(|p| p.to_vec()))
        .filter(|p| p.len() == next.positions[si].len() || p.len() == crate::activation::placed_chain_len(&next, si))
        .filter(|_| matches!(kind, ADVANCE | RUSH));
    if placed.is_none() && matches!(kind, ADVANCE | RUSH) && next.aircraft[si] && rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
        if let Some(d) = if let Cover::Board(t) = cover { aircraft_delta(statics, &next, si, t, seams.shelf_sight, seams.rules_epoch) } else { None } {
            let chain = std::iter::once(si).chain(next.attached[si].iter().copied().filter(|_| seams.hero_attach));
            for u in chain.collect::<Vec<_>>() {
                next.positions[u].iter_mut().for_each(|p| *p = geom::to_f64(geom::add(geom::to_f32(*p), d)));
            }
            (flew, moved) = (true, true);
            stamp_moved(&mut next, si, seams.hero_attach, seams.rules_epoch);
            let line = format!(
                "Aircraft: {} flies {AIRCRAFT_MOVE_IN:.0}\" straight (heading {:.0}\u{b0})",
                statics[pi_s].name, (d[2] as f64).atan2(d[0] as f64).to_degrees()
            );
            trace_rule("aircraft", "Aircraft", &line);
            if let Some((_, shot)) = dice.as_mut() { shot.log.push(line); }
        }
    }
    if placed.is_none() && seams.movement && !seams.plain_only && kind == CHARGE && band_in > 0.0 {
        if let (Cover::Board(t), Some(ti)) = (cover, ci) {
            let mr = crate::mv::step::MoveRules { rules_epoch: seams.rules_epoch };
            landing = if seams.charge_direct {
                mr.charge_move_direct(&next, t, si, ti, band_in, seams.hero_attach, true, crate::mv::FAST_PLANNER_GUARD)
            } else {
                mr.charge_move(&next, t, si, ti, band_in, seams.hero_attach, true, crate::mv::FAST_PLANNER_GUARD)
            };
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
    if placed.is_none() && seams.movement && !seams.move_rigid && kind != CHARGE && band_in > 0.0 && !flew {
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
        // G4-C7b (Regroup, `EPOCH_73_V36`): a unit that starts out of coherency spends its advance gathering — the
        // move port ran the placement gate on it; the log names the rule.
        if let (Cover::Board(t), true, Some((_, shot))) = (cover, kind == ADVANCE, dice.as_mut()) {
            if crate::menu::starts_incoherent(state, t, si, seams.rules_epoch) {
                shot.log.push(format!("Regroup: {} starts out of coherency - its action gathers it back", statics[pi_s].name));
            }
        }
        // Wave 4 (port-entrenched) — every EXECUTED move stamps (main.gd:7786).
        stamp_moved(&mut next, si, seams.hero_attach, seams.rules_epoch);
        for (i, m) in land.movers.iter().enumerate() {
            next.positions[m.unit][m.model] = geom::to_f64(land.end[i]);
        }
        // Rules-must-log (main.gd:1210-1212): a climb names the Terrain rule and the inches it cost.
        if let (true, Some((_, shot))) = (land.climb_in > 0.0, dice.as_mut()) {
            shot.log.push(format!("Terrain: {} climbs onto terrain (+{:.1}\" of its move)", statics[pi_s].name, land.climb_in));
        }
        // D5-2 review fix: the table's own arc only feeds the D5-1 budget
        // gate when `charge_landing` asks for it — otherwise `movement=
        // "table"` silently forces `charge_landing="table"` on, and the
        // engage snap gate refuses charges D5-1-off never refused.
        if seams.charge_landing || rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
            charge_remaining_in = land.remaining_in();
            charge_arcs = Some((land.arcs(), land.budget_in)); // #183: per-model snap budgets (EPOCH_77)
        }
        // battle_sim.gd:598-600 — the mover's cover follows it, probed at the
        // POST-move unit centre, which is now the solved formation's centre.
        if let Cover::Board(t) = cover {
            if t.is_valid() {
                land_cover(statics, &mut next, si, t, seams, dice.as_mut().map(|d| &mut *d.1));
            }
        }
    } else if let Some(dest_raw) = action.dest.filter(|_| placed.is_none() && band_in > 0.0
        && !hold
        && !flew
        && !next.positions[si].is_empty())
    {
        moved = true;
        stamp_moved(&mut next, si, seams.hero_attach, seams.rules_epoch);
        let dest = geom::to_f32(dest_raw);
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
                    land_cover(statics, &mut next, si, t, seams, dice.as_mut().map(|d| &mut *d.1));
                }
            }
        }
    }
    // The skirmish Falling rule: the unit's (alive, wounds) before its first fall wound, for the end-of-activation test.
    let mut fall_morale_due: Option<(i64, i64)> = None;
    // One-core P3: a supplied placement IS the move — every model lands where the player put it.
    if let Some(p) = placed {
        // One-core P3 step 61: the walked paths the tray carries become the move's landing, so the Dangerous test
        // below reads each model's route, not only its end (`dangerous_dice`'s end-only arm); a climb names its rule.
        let trails = dice.as_ref().and_then(|d| d.0.placed_trails()).filter(|t| !t.is_empty()).map(|t| t.to_vec());
        // EPOCH_94_PARITY_BATCH: the table stamps an EXECUTED move; remember the chain's stamps and whether any model left its place.
        let chain: Vec<usize> = std::iter::once(si).chain(next.attached[si].iter().copied()
            .filter(|_| seams.hero_attach && p.len() == crate::activation::placed_chain_len(&next, si))).collect();
        let stamps: Vec<(usize, i64)> = chain.iter().map(|&u| (u, next.moved_round[u])).collect();
        let left_place = chain.iter().flat_map(|&u| next.positions[u].iter()).zip(p.iter())
            .any(|(a, b)| geom::length(geom::sub(geom::to_f32(*a), geom::to_f32(*b))) > 0.0005);
        // S1: a placement past the host's models moves the joined heroes with it (host first, then each hero in
        // `attached` order); a host-only placement leaves them where they stood, as before.
        let host_n = next.positions[si].len();
        // The skirmish Jumping rule: the jumps `check_move` accepted for this placement, read off the START positions.
        let jumps = match (cover, dice.is_some()) {
            (Cover::Board(t), true) => crate::activation::jump_dice_of(&next, si, seams, t,
                &crate::activation::Drop { mode: kind, placed: p.clone(), trails: trails.clone().unwrap_or_default() }),
            _ => Vec::new(),
        };
        if seams.hero_attach && p.len() == crate::activation::placed_chain_len(&next, si) {
            let mut at = host_n;
            for h in next.attached[si].clone() {
                let n = next.positions[h].len();
                next.positions[h] = p[at..at + n].to_vec();
                at += n;
            }
        }
        next.positions[si] = p.into_iter().take(host_n).collect();
        moved = true;
        stamp_moved(&mut next, si, seams.hero_attach, seams.rules_epoch);
        // Jumping (3.6 skirmish p.15): each jumping model rolls one die per inch at 2+; any miss and that model falls.
        if let Some((tray, shot)) = dice.as_mut() {
            let name = statics[pi_s].name.clone();
            // Models a fall removed, by their index at the start: a later jumper's slot moves up past each of them.
            let mut gone: Vec<usize> = Vec::new();
            for (m, n, h, foot) in jumps {
                tray.owner_next(Some(si));
                let faces = tray.roll(n as usize);
                let lands = crate::mv::jump::jump_passes(&faces);
                let line = format!("Jump: {name} model {} jumps down {h:.0} in - {faces:?} at 2+ - {}", m + 1,
                    if lands { "it lands" } else { "a 1, it falls" });
                shot.rolls.push(crate::dice::Roll { kind: "jump", count: n as i64, target: crate::mv::jump::JUMP_TARGET as i64, faces, owner: name.clone() });
                shot.log.push(line.clone());
                say_rule(tray, "jump", next.player[si], || line);
                if !lands {
                    shot.falls.push((si, m, h));
                    // Falling (3.6 skirmish p.15, ruling D13): the model lands at the foot of the drop on its own path, rolls one
                    // die per inch fallen and takes one wound per 1-3; the unit's other models keep the player's placement.
                    let slot = m - gone.iter().filter(|&&g| g < m).count();
                    if let Some(p) = next.positions[si].get_mut(slot) {
                        *p = foot;
                    }
                    // Plan step 27b (H-8, as the push): the fall is its own landing, before its wounds, so the table moves
                    // the model to its foot first and the wounds' `at` finds it there
                    let moved_to = next.positions[si].clone();
                    tray.land(|| Landing { unit: si, models: Vec::new(), loss_line: false, moved_to });
                    tray.owner_next(Some(si));
                    let n = (h - 1e-6).ceil().max(0.0) as usize;
                    let faces = tray.roll(n);
                    let w = faces.iter().filter(|&&f| f <= 3).count() as i64;
                    let line = format!("Falling: {name} model {} falls {h:.0} in and lands at the foot of the drop ({:.1} in, {:.1} in) - {faces:?}, {w} wound{} on 1-3",
                        m + 1, foot[0] / IN2M, foot[2] / IN2M, if w == 1 { "" } else { "s" });
                    shot.rolls.push(crate::dice::Roll { kind: "fall", count: n as i64, target: 4, faces, owner: name.clone() });
                    shot.log.push(line.clone());
                    say_rule(tray, "fall", next.player[si], || line);
                    if w > 0 {
                        fall_morale_due.get_or_insert((morale_alive(&next, si, seams), morale_wounds_left(&next, si, seams)));
                        let before = chain_snapshot(&next, si, tray);
                        // The model that fell takes the wounds (3.6 p.15), not the unit's casualty order; past its last wound
                        // they are lost.
                        let (take, models) = (w.min(next.wounds[si].get(slot).copied().unwrap_or(0)), next.positions[si].len());
                        land_wounds_in_order(&mut next, si, take, vec![slot]);
                        if next.positions[si].len() < models {
                            gone.push(m);
                        }
                        land_chain_report(statics, &next, tray, si, before);
                    }
                }
            }
        }
        if let (Some(trails), Cover::Board(t)) = (trails, cover) {
            let land = crate::mv::step::placed_landing(&next, si, t, &trails, band_in, seams.hero_attach, seams.rules_epoch);
            if let (true, Some((_, shot))) = (land.climb_in > 0.0, dice.as_mut()) {
                shot.log.push(format!("Terrain: {} climbs onto terrain (+{:.1}\" of its move)", statics[pi_s].name, land.climb_in));
            }
            landing = Some(land);
        }
        if let Cover::Board(t) = cover {
            if t.is_valid() {
                land_cover(statics, &mut next, si, t, seams, dice.as_mut().map(|d| &mut *d.1));
            }
        }
        if !left_place && rule_on(seams.rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) {
            for (u, round) in stamps {
                next.moved_round[u] = round;
            }
        }
    }
    // E1 (`EPOCH_76_MOVE_FIXES`): the move that ran spends the Great Musician +1" (the band above already rode it).
    // Below 76 the row stays and rides every later move, the frozen replay reading.
    if moved && rule_on(seams.rules_epoch, EPOCH_76_MOVE_FIXES) {
        spend_move_rows(statics, &mut next, si);
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
    // F-DANG-HOLD (`EPOCH_73_V36`, ruling D2): the book's Dangerous Terrain test also fires for a unit that
    // ACTIVATES in it, a Hold included. The table asks for it whenever the activation moved nothing
    // (`_dangerous_standing_counts` solo_controller.gd:5943: Aircraft and reserve skip it, Flying is
    // guarded in `dangerous_dice`). Below 73 only a move tests.
    let activated_in_it = !moved
        && rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36)
        && !next.aircraft[si]
        && !next.dormant[si];
    if ((moved && !flew) || activated_in_it) && !seams.no_dangerous {
        if let Some((tray, shot)) = dice.as_mut() {
            let n = dangerous_dice(statics, state, &next, si, seams, landing.as_ref(), cover, shot, false);
            if n > 0 {
                tray.name_next("dangerous"); // the table's kind (main.gd `_run_ai_dangerous`): its dice line counts the 1s
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
                    let alive_before = morale_alive(&next, si, seams);
                    let wounds_before = morale_wounds_left(&next, si, seams);
                    // One-core P3 step 59: the unit chain (host, then its joined heroes) before the wounds land, as
                    // the volley's step 7. Only a supplied tray takes it: a seeded one clones nothing.
                    let chain_before = tray.feed().is_some().then(|| std::iter::once(si)
                        .chain(next.attached[si].iter().copied())
                        .map(|u| (u, next.positions[u].clone(), next.wounds[u].clone())).collect::<Vec<_>>());
                    // R3-X2a (`EPOCH_73_V36`, lead ruling 2): the surplus wounds the host's models cannot soak go on to the
                    // joined hero (heroes last); below 73 `land_pool_wounds` drops them as before.
                    land_pool_wounds(&mut next, si, w, seams.tray_exact, seams, &mut shot.log);
                    // One-core P3 step 59: one landing per changed chain member, stamped right after the test's draw.
                    for (u, at, wounds) in chain_before.into_iter().flatten() {
                        if let Some(l) = landing_of(&next, u, &at, &wounds, &tray.dead_slots(u)) {
                            tray.land(|| l);
                        }
                    }
                    // main.gd:1096-1098 — a NON-charge activation tests morale for
                    // these wounds at its very END ("units in melee don't take
                    // morale tests from wounds at the end of an activation").
                    // Knob-gated (DEFECT_LEDGER #12): OFF replays a corpus
                    // recorded before this rule unchanged.
                    // The flag names the SKIPPED test (knob off), never the
                    // ported one: the tray tree declines on every flag, and
                    // the stage-0 census found it on 491 ported moves.
                    if kind != CHARGE && seams.dangerous_end_morale {
                        dangerous_morale_due = Some((alive_before, wounds_before));
                    } else if kind != CHARGE {
                        shot.mark("dangerous_end_morale");
                    }
                }
            }
        }
    }
    // F-DANG-TAIL (`EPOCH_73_V36`, replay gates only): the gate cut the table's Dangerous test (`no_dangerous`) and patched its
    // wounds into `state`; the header knob hands back the unit's act-start (alive, wounds). Their difference to the patched state
    // is the cut test's tail: the end-of-activation morale test below (non-charge) and, for a charge, the charger's self-inflicted
    // wounds in the melee result (`dangerous_tail_wounds`). Play never sets the knob, so it runs the test above and this is skipped.
    let mut dangerous_tail_wounds = 0;
    if let (true, Some((alive_before, wounds_before))) = (seams.no_dangerous && rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36), seams.dangerous_replay) {
        dangerous_tail_wounds = (wounds_before - morale_wounds_left(&next, si, seams)).max(0);
        if dangerous_tail_wounds > 0 {
            if let Some((_, shot)) = dice.as_mut() {
                shot.log.push(format!("Dangerous terrain: {} took {dangerous_tail_wounds} wound(s) in the test the replay cut - the morale test and the melee tally still count them", statics[pi_s].name));
            }
            if kind != CHARGE && seams.dangerous_end_morale {
                dangerous_morale_due = Some((alive_before, wounds_before));
            }
        }
    }

    // --- cast sub-phase (battle_sim.gd:602-607), seam-gated ---
    // `_best_spell_target` (:930) probes `_los_clear` with the POST-move
    // centres, which the pre-move `los_pairs` of `state_before` cannot answer —
    // the same shape of missing input `cover_dest` fixed for terrain. The
    // caller supplies the caster's row; without one the pre-move matrix is used
    // and a moved caster's targeting is an approximation.
    // FAB-B2 (rules 3.6): the melee tally counts EVERY wound each side took in
    // the activation. The cast sub-phase is the pre-melee source the core
    // tracks itself, so the wound delta across it is the honest counter; the
    // charge move's own self-wounds ride `charger_self_wounds` separately.
    // D-PAR3 14b: `Input::Paid { beats }` - the table resolved the pre-attack phase before its capture (its casts, every beat below,
    // the move-through attacks), so none of it runs again here.
    // Falling (3.6 skirmish p.15): a unit whose model fell ends its activation - no cast, pre-attack beat or attack follows.
    let fell = dice.as_ref().is_some_and(|(_, shot)| shot.falls.iter().any(|f| f.0 == si));
    let beats = !dice.as_ref().is_some_and(|(tray, _)| tray.paid_beats()) && !fell;
    let cast_wounds_before_su = wounds_left(&next, si);
    let cast_wounds_before_tu = ci.map_or(0, |t| wounds_left(&next, t));
    // CC-5a: casts offered on a supplied tray are the tray path's own (`tray_cast`); the expectation model never runs beside them.
    if seams.cast && beats && dice.as_ref().is_none_or(|(tray, _)| tray.casts().is_empty()) {
        let row: Vec<bool> = match cast_los {
            Some(r) => r.to_vec(),
            None => (0..next.units()).map(|j| los_clear(&next, si, j)).collect(),
        };
        cast_phase(statics, &mut next, si, &row, seams, rng.as_deref_mut());
    }
    // CC-5b/7a/8b: the casts offered on the tray, in plan order; their wounds (CC-6) join the melee tally like the expectation cast's.
    // Activating unit wiped by Dangerous or by its own cast ends the activation here (main.gd:1290-1301); host dead + hero alive goes on.
    if let Some((tray, shot)) = dice.as_mut() {
        let casts = if fell { Vec::new() } else { tray.casts().to_vec() };
        if !casts.is_empty() {
            if !side_up(&next, si, seams) {
                for c in casts {
                    spend_cast_tokens(&mut next, &c);
                }
                return Ok(finish_activation(statics, state, next, si, seams, cover));
            }
            if next.alive[si] <= 0 && rule_on(seams.rules_epoch, EPOCH_73_V36) {
                tray.say(|| LogLine { rule: "hero", category: Category::Combat, side: next.player[si], detail: None,
                    text: format!("{} is destroyed but its joined hero lives - the unit is not destroyed and goes on", statics[pi_s].name) });
            }
            for c in casts {
                if tray_cast(statics, &mut next, si, &c, seams, tray, shot) == CastEnd::Hit {
                    tray.note_cast_refused(c.seq, "casts are not resolved by the core yet".into());
                    break;
                }
            }
            if !side_up(&next, si, seams) {
                return Ok(finish_activation(statics, state, next, si, seams, cover));
            }
        }
    }
    let pre_melee_su = (cast_wounds_before_su - wounds_left(&next, si)).max(0);
    let pre_melee_tu = ci.map_or(0, |t| (cast_wounds_before_tu - wounds_left(&next, t)).max(0));

    // --- MEND (main.gd:1056-1058), the pre-attack slot — every action kind,
    // tray path only. See `tray_mend`; no bearer, no patient, no draw.
    if let (true, Some((tray, shot))) = (beats, dice.as_mut()) {
        tray_mend(statics, &mut next, si, seams, tray, shot);
    }

    // --- BREATH ATTACK (main.gd:1059), right after Mend in the table's own
    // pre-attack slot order — every action kind, tray path only. See
    // `tray_breath_attack`; no bearer, no target, no draw.
    if let (true, Some((tray, shot))) = (beats, dice.as_mut()) {
        tray_breath_attack(statics, &mut next, si, seams, tray, shot);
    }

    // --- Utility Buff / Re-Position Artillery (main.gd:1062, right after
    // Mend + Breath Attack), tray path only — see `tray_utility_buff`.
    // Dice-free: no tray draw either way.
    if dice.is_some() && beats {
        tray_utility_buff(statics, &mut next, si, seams, cover);
    }

    // --- MIND CONTROL / Fatigue Debuff (main.gd:1070, the table's own slot
    // between Utility Buffs and Piercing Tag) — tray path only, the fatigue
    // arm (`tray_fatigue_debuff`) and the displacement arm
    // (`tray_mind_control`).
    if let (true, Some((tray, shot))) = (beats, dice.as_mut()) {
        tray_fatigue_debuff(statics, &mut next, si, seams, tray, shot);
        tray_mind_control(statics, &mut next, si, seams, tray, shot, cover);
    }

    // --- PIERCING TAG (main.gd:1071, the table's pre-attack slot right after
    // the Utility Buffs + Mind Control), tray path only — see
    // `tray_piercing_tag`. From EPOCH_67_MARKERS_BURSTS a `place_roll` entry
    // (Piercing Spotter) draws its 4+; every other name is still dice-free
    // (the marker count comes off the rule's rating).
    if let (true, Some((tray, shot))) = (beats, dice.as_mut()) {
        tray_piercing_tag(statics, &mut next, si, seams, tray, shot);
    }

    // --- PRECISION MARKERS — TAG/TARGET (main.gd:1089-1090, the pre-attack
    // slot right after the Piercing Tag), tray path only — see
    // `tray_precision_markers`. The Tag draws nothing (the count is the
    // rating); the Spotter does NOT run here — its beat is the activation's
    // END (main.gd:1127).
    if let (true, Some((tray, shot))) = (beats, dice.as_mut()) {
        tray_precision_markers(statics, &mut next, si, seams, tray, shot, false);
        // Rules 3.6: the Spotter rolls BEFORE the bearer's own attacks.
        if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
            tray_precision_markers(statics, &mut next, si, seams, tray, shot, true);
        }
    }

    // --- RECKLESS PIERCING (main.gd:1072, the table's own slot between the
    // Piercing Tag and the Storm Attack) — tray path only, see
    // `tray_reckless_piercing`.
    if let (true, Some((tray, shot))) = (beats, dice.as_mut()) {
        tray_reckless_piercing(statics, &mut next, si, seams, tray, shot);
    }

    // --- STORM ATTACK (main.gd:1073, after Utility Buff in the table's own
    // pre-attack slot order), every action kind, tray path only. See
    // `tray_storm_attack`; no enemy in reach does not spend the burst.
    if let (true, Some((tray, shot))) = (beats, dice.as_mut()) {
        tray_storm_attack(statics, &mut next, si, seams, tray, shot);
    }

    // --- TELEPORT / ETHEREAL (main.gd:1075, right after Surprise; #816 PR 2)
    if beats {
        teleport_beat(statics, &mut next, si, action, seams, dice.as_mut(), cover);
    }

    // --- STRAFING (main.gd:1096, right after Teleport and BEFORE the Crossing
    // Attack in the table's own pre-attack slot order), every action kind with
    // a tray — see `tray_strafing`; no move trail, no carrier, no crossed
    // enemy rolls nothing.
    if let (true, Some((tray, shot))) = (beats, dice.as_mut()) {
        tray_strafing(statics, state, &mut next, si, seams, tray, shot, cover);
    }

    // --- CROSSING ATTACK (main.gd:1081, right after Storm in the table's own
    // pre-attack order), every action kind with a tray — see
    // `tray_crossing_attack`; no crossed enemy rolls nothing.
    if let (true, Some((tray, shot))) = (beats, dice.as_mut()) {
        tray_crossing_attack(statics, state, &mut next, si, seams, tray, shot);
    }

    // --- GROWTH MARKERS (main.gd:16984), the per-round tick lazily anchored
    // to this unit's own next activation — tray path only. See
    // `growth_round_start`; dice-free, `was_shaken` is the round-start
    // reading (captured before this activation's own moves/tests run it).
    if dice.is_some() {
        growth_round_start(statics, &mut next, si, was_shaken);
        growth_round_start_heroes(statics, &mut next, si, was_shaken, seams);
    }

    // Heightfield plan step 12: the pre-attack beats above (Teleport, Mind Control, a revived model) may have moved a
    // model in x/z only; the volley below reads its height (3D sight), so it stands on its surface first.
    settle_on_surface(&mut next, state, cover, seams.rules_epoch);

    // --- shoot (battle_sim.gd:608-630); HOLD and ADVANCE only, plus RUSH for
    // a Quick Shot carrier (block B11, solo_controller.gd:1846/:2257/:4033 —
    // "may shoot after using Rush actions": its move-and-shoot band becomes
    // its RUSH distance). The `moved` decline right below still applies to a
    // Quick Shot RUSH exactly as it already does to a moved ADVANCE.
    let quick_shot_active =
        statics[pi_s].quick_shot_active || mods::granted(&next, si, "Quick Shot");
    // Rules 3.6 Cumbersome (SHO-16): a unit that moved fires no volley. The key
    // is dropped here, so the Hit & Run shot leg below sees no attack either.
    let shoot_key = if fell && !shoot_key.is_empty() {
        if let Some((tray, shot)) = dice.as_mut() {
            let line = format!("Falling: {}'s activation ends, so it does not shoot", statics[pi_s].name);
            say_rule(tray, "fall", next.player[si], || line.clone());
            shot.log.push(line);
        }
        String::new()
    } else if !shoot_key.is_empty()
        && moved
        && statics[pi_s].cumbersome
        && rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36)
    {
        if let Some((tray, shot)) = dice.as_mut() {
            let line = format!("Cumbersome: {} moved, so it cannot shoot this activation", statics[pi_s].name);
            say_rule(tray, "cumbersome", next.player[si], || line.clone()); // the step path's lines are the tray's
            shot.log.push(line);
        }
        String::new()
    } else {
        shoot_key
    };
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
        // EPOCH_83_LONE_HERO_TARGET: a host with no models left and a living joined hero is shot as the hero.
        let lone_shot = named.filter(|_| rule_on(seams.rules_epoch, EPOCH_83_LONE_HERO_TARGET))
            .and_then(|t| lone_hero_of(&next, t, seams).map(|h| (t, h)));
        if let (Some((host, hero)), Some((_, shot))) = (lone_shot, dice.as_mut()) {
            shot.log.push(format!("Hero: {} is the unit now — shots from {} at {} are measured and saved as the hero",
                statics[next.roster.profile[hero]].name, statics[pi_s].name, statics[next.roster.profile[host]].name));
        }
        if let Some(ti) = lone_shot.map(|(_, h)| h).or_else(|| named.map(|t| combat_unit(&next, t, seams))) {
            // NML-1150: the split plan is decided BEFORE the recorded target's
            // gate — a split act may aim at units the recorded key does not
            // name, and then validity is gated PER GROUP below (main.gd
            // :2963-2984). The EV half keeps the one-target gate.
            let (plan, split_marks) = match dice.as_mut() {
                Some(_) => split_plan(action.split.as_ref(), statics, &next, si, &shoot_key, seams),
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
            // G4R5 F-HOSTDEAD-SHOOT (`EPOCH_73_V36`): a MOVED volley probes sight and range from the first living chain member
            // once the host's own Dangerous test took its last model (`lone_hero_of`); the host's key finds no model to probe.
            let probe = if moved { lone_hero_of(&next, si, seams).unwrap_or(si) } else { si };
            // G4R5 F-MOVED-SIGHT-CHAIN (`EPOCH_73_V36`): the table decides sight per member (`_solo_sighted_count`), so a
            // living but blind host does not silence a joined hero that sees the target: the first seeing chain member.
            let mut blind_host_hero: Option<usize> = None;
            let sighted = if moved {
                (match cover {
                    // SHO-PAR-F3 (EPOCH_73_V36): the table's own per-model 3D sight (`_solo_has_los`), not the
                    // coarse grid line between the two centres, which refused a shot the outer models see past
                    // a forest. The EV half runs the same gate, so the search now prices that shot too.
                    Cover::Board(t) if t.is_valid() && rule_on(sc.rules_epoch, EPOCH_73_V36) => {
                        let zones = board_zones(t, seams.shelf_sight, seams.rules_epoch);
                        let chain = std::iter::once(si).chain(next.attached[si].iter().copied().filter(|_| seams.hero_attach));
                        let seen_by = chain.filter(|&m| next.alive[m] > 0).find(|&m| sight::unit_sees(&next, &zones, m, ti, sc.rules_epoch));
                        blind_host_hero = seen_by.filter(|&m| m != si && next.alive[si] > 0);
                        seen_by.is_some()
                    }
                    Cover::Board(t) if t.is_valid() => !t.los_blocked_at(
                        geom::centre(&next.positions[si]),
                        geom::centre(&next.positions[ti]),
                        seams.rules_epoch,
                    ),
                    _ => next.los[si].is_none() && next.los_pairs.is_none(),
                }) || mark_indirect
            } else {
                (next.sees(si, &shoot_key) && los_clear(&next, si, ti)) || mark_indirect
            };
            // EPOCH_85_INDIRECT_GATE: a weapon's own Indirect opens the pooled gate (the per-weapon sight counts decide what fires).
            let sighted = sighted
                || (seams.sighting && rule_on(sc.rules_epoch, crate::acts::EPOCH_85_INDIRECT_GATE)
                    && indirect_waives_gate(statics, &next, si, ti, kind == HOLD, seams));
            if mark_indirect && !(next.sees(si, &shoot_key) && los_clear(&next, si, ti)) {
                trace_rule("volley", "Indirect Mark",
                    &format!("{} may target {} without line of sight", statics[pi_s].name, statics[next.roster.profile[ti]].name));
            }
            if plan.is_some() || sighted {
                let d = chain_gap_in(&next, ti, seams, |t| if seams.range_by_base_edge {
                    range_gap_in(&next, &next.positions[probe], probe, t)
                } else {
                    geom::dist_in(&next.positions[probe], &next.positions[t])
                });
                // The table's epoch-66 nearest-base modifier measure remains
                // separate from this pooled range-validity distance.
                let mod_d = volley_distance_in(&next, si, ti, seams);
                // NML-1132: the EXPECTED-VALUE half measures over the table's folded
                // model set (`fold_dist_in`); the TRAY half below keeps the plain
                // host-to-host `d`, because it already measures per FIRING MEMBER
                // (`sighted_profiles_of`, `main._solo_sighted_count` :4103) and a
                // folded reach there would let a host weapon fire from a hero's model.
                let d_ev = if seams.hero_attach { fold_dist_in(&next, si, ti, seams) } else { d };
                let morale_alive_before = morale_alive(&next, ti, seams);
                let wounds_before = morale_wounds_left(&next, ti, seams);
                // Seam ON: a plain volley — the cast sub-phase above already
                // ran. Seam OFF: the LEGACY spell rider (battle_sim.gd:621-628),
                // where the spell's EV joins the volley and the caster pays for
                // it inside the shoot pick.
                // NML-1157: the rider's caster is the CHAIN's, not the host's —
                // see `caster_of`. With `cast_fold` off this is `Some(si)` under
                // exactly the conditions `spell_ev_of` already tested, or `None`
                // where it already returned `(0.0, 0)`.
                let caster = caster_of(statics, &next, si, seams);
                let (volley, sp_cost, phantom) = {
                    let us = &statics[pi_s];
                    let ut = &statics[next.roster.profile[ti]];
                    member_profiles_reach(statics, &next, si, ti, d_ev, seams, &mut sc);
                    let mut att = ctx_of(us, &next, si);
                    // SHO-06e: the volley's own action decides the Artillery shooter's Hold.
                    att.held = !moved;
                    let mut def = ctx_of(ut, &next, ti);
                    // FAB-A5 (`EPOCH_79_EV_MOVED_ROUND`, table twin `_held_for`): the target's own move stamp.
                    if rule_on(seams.rules_epoch, EPOCH_79_EV_MOVED_ROUND) {
                        (def.moved_round, def.round) = (next.moved_round[ti], next.round);
                    }
                    let shooting = shoot_ev(
                        folded_slice(&us.shoot, &sc), &sc.keep, &sc.attacks, &att, &def, d_ev,
                    );
                    // AI-06 (EPOCH_73_V36): the expected phantom wounds — the Shred-vs-plain EV
                    // gap is hits * SIX_P, each such 1 worth SCOURGE_PHANTOM_WOUNDS. Regeneration
                    // is neutralised on both clones so it cannot scale the gap.
                    let mut phantom = 0.0;
                    if rule_on(seams.rules_epoch, EPOCH_73_V36) {
                        let mut no_regen = def;
                        no_regen.regeneration = false;
                        let profiles = folded_slice(&us.shoot, &sc);
                        for (k, &pi) in sc.keep.iter().enumerate() {
                            let p = &profiles[pi];
                            if !p.rules.iter().any(|r| r.trim() == "Scourge") {
                                continue;
                            }
                            let (mut plain, mut probe) = (p.clone(), p.clone());
                            plain.shred = false;
                            probe.shred = true;
                            phantom += crate::combat::profile_ev(&probe, sc.attacks[k], &att, &no_regen, d_ev, false)
                                - crate::combat::profile_ev(&plain, sc.attacks[k], &att, &no_regen, d_ev, false);
                        }
                        phantom *= crate::dice::SCOURGE_PHANTOM_WOUNDS as f64;
                    }
                    // EPOCH_93_DANGER_RULES_RIDER: from 93 the rider is off on every path (the table has none), as seam ON always was.
                    if seams.cast || rule_on(seams.rules_epoch, crate::acts::EPOCH_93_DANGER_RULES_RIDER) {
                        (shooting, 0, phantom)
                    } else {
                        let (sp_ev, sp_cost) = match caster {
                            Some(ci) => {
                                let cs = &statics[next.roster.profile[ci]];
                                spell_ev_of(true, &cs.spells, next.casts[ci], &def, d_ev, seams.rules_epoch)
                            }
                            None => (0.0, 0),
                        };
                        if sp_ev > 0.0 {
                            (shooting + sp_ev, sp_cost, phantom)
                        } else {
                            (shooting, 0, phantom)
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
                        if probe != si {
                            shot.log.push(format!("Hero: {} has no models left - {} fires the volley as the unit",
                                statics[pi_s].name, statics[next.roster.profile[probe]].name));
                        }
                        if let Some(h) = blind_host_hero {
                            shot.log.push(format!("Hero: {} has no model that sees {} - {} sees it and fires the volley as the unit",
                                statics[pi_s].name, statics[next.roster.profile[ti]].name, statics[next.roster.profile[h]].name));
                        }
                        for m in split_marks {
                            shot.mark(m);
                        }
                        // D6a-B4: with `sighting="model"` the die count is the
                        // table's own, per member and per WEAPON — the board's
                        // sight volumes are built once for the whole volley.
                        let zones = match (seams.sighting, cover) {
                            (true, Cover::Board(t)) => sight::zones_of_with_at(t, seams.shelf_sight, seams.rules_epoch),
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
                        for (gi, g) in gs.iter().enumerate() {
                            if plan.is_some() && next.roster.index.get(g.key.as_str()).is_some_and(|&k| k != g.ti) {
                                shot.log.push(format!("Hero: {} is the unit now — shots from {} at {} are measured and saved as the hero",
                                    statics[next.roster.profile[g.ti]].name, statics[pi_s].name, g.key));
                            }
                            // The Hero rule on the step path (`_solo_resolve_ai_volley`, main.gd): the group was NAMED at a host whose
                            // own models are all gone and is shot as its living joined hero. The table says so before the volley and
                            // calls the target by the host's name; `shot.log` above is the plain path's copy, the tray's line is the
                            // step path's (a log line, no die: no epoch).
                            let lone_host = next.roster.index.get(g.key.as_str()).copied()
                                .filter(|&k| k != g.ti && lone_hero_of(&next, k, seams) == Some(g.ti));
                            if let Some(host) = lone_host {
                                tray.say(|| LogLine { rule: "hero", category: Category::Combat, side: next.player[si], detail: None,
                                    text: format!("Hero: {} is the unit now — shots from {} at {} are measured and saved as the hero",
                                        statics[next.roster.profile[g.ti]].name, statics[pi_s].name, statics[next.roster.profile[host]].name) });
                            }
                            // EPOCH_96_PARITY_BATCH: a target-side range cut leaves no weapon in reach, so there is no volley
                            // (the table's "no target in range or sight"): nothing is marked, spent or announced.
                            // Each member's gap is the one its weapons are gated by below (`dm`): the host's `g.d`, a joined hero's own.
                            let member_gap = |m: usize| if m == si || !rule_on(seams.rules_epoch, EPOCH_73_V36) { g.d } else {
                                chain_gap_in(&next, g.ti, seams, |t| if seams.range_by_base_edge || plan.is_some() {
                                    range_gap_in(&next, &next.positions[m], m, t) } else { geom::dist_in(&next.positions[m], &next.positions[t]) })
                            };
                            if rule_on(seams.rules_epoch, crate::acts::EPOCH_96_PARITY_BATCH)
                                && cut_out_of_reach(statics, &next, si, g.ti, seams, member_gap)
                            {
                                let said = format!("{}: no volley — no target in range or sight — the unit holds", statics[pi_s].name);
                                shot.log.push(said.clone());
                                tray.say(|| LogLine { rule: "shoot", category: Category::Combat, side: next.player[si], detail: None, text: said });
                                continue;
                            }
                            // main.gd:3042 — the Mark is picked and recorded
                            // BEFORE this group's profiles and contexts are
                            // read (:3082), so the grant reaches this volley.
                            tray_vs_marks(statics, &mut next, si, g.ti, g.d, seams, tray, shot);
                            // Wave 3 — Piercing Tag: the marked target's pool
                            // spends EVERY marker on THIS volley (main.gd
                            // :3123 AI / :9857 human, shooting only — the
                            // melee seams never call it), once per group.
                            // The Piercing spend lines (`Piercing Tag: one token spent ...`, `Piercing Target: ... stands`) are the DOOR's: it runs the
                            // table's own `_solo_spend_piercing_tag` (`CoreActivation._spend_tag`), which writes them. The core says none on the tray.
                            let tag_ap = piercing_tag_spend(&mut next, g.ti, seams.rules_epoch);
                            if tag_ap > 0 {
                                if next.piercing_tag_persistent[g.ti] {
                                    let tn = statics[next.roster.profile[g.ti]].name.clone();
                                    if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
                                        shot.log.push(format!("Piercing Target: +1 (Target) stands while {tn} lives"));
                                    } else {
                                        shot.log.push(format!(
                                            "Piercing Target: +AP({tag_ap}) stands while {tn} lives"
                                        ));
                                    }
                                } else if rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
                                    let left = next.piercing_tag_markers[g.ti];
                                    shot.log.push(format!("Piercing Tag: one token spent — +1 AP on this volley ({left} left)"));
                                } else {
                                    let s = if tag_ap == 1 { "" } else { "s" };
                                    shot.log.push(format!(
                                        "Piercing Tag: {tag_ap} marker{s} spent — +AP({tag_ap}) on this volley"
                                    ));
                                }
                            }
                            // Wave 6 — Precision Spotter/Tag: the marked
                            // target's pools spend EVERY marker on THIS
                            // volley (+1 to hit per marker), once per group.
                            let side_now = next.player[si];
                            let (spot_hit, tag_hit) = precision_markers_spend(&mut next, si, g.ti, seams.rules_epoch, &mut shot.log, tray, side_now);
                            let precision_hit = spot_hit + tag_hit;
                            let ut_g = &statics[next.roster.profile[g.ti]];
                            let mut def = with_modifier_sum(with_cond_ap_state(ctx_live(ctx_of(ut_g, &next, g.ti), statics, &next, g.ti, false, seams.rules_epoch), statics, &next, g.ti, seams), seams.rules_epoch);
                            stamp_blast_models(&mut def, &next, g.ti, seams);
                            def.side = next.player[g.ti]; // One-core P3 step 25: the save line's seat
                            // D-STEALTH — the def build's terrain gate: the alias
                            // applies only while the TARGET stands within 1" of
                            // terrain (per model, the majority fold).
                            stealth_alias_terrain_gate(statics, &next, g.ti, cover, &mut def);
                            // Cover from sight blockers, one verdict per target group for every weapon (the save fold
                            // lifts it per weapon for a held Indirect). Placeholder gate, no outcome below 95.
                            let mut td_hidden: Option<Vec<bool>> = None; // step 8: the Takedown pick's own screen
                            if seams.sighting && rule_on(seams.rules_epoch, crate::acts::EPOCH_95_PARITY_BATCH) {
                                let sc = sight::screen_of(&next, &zones, si, g.ti, seams.rules_epoch);
                                def.screened = sc.screened;
                                td_hidden = Some(sc.hidden.clone());
                                if sc.screened {
                                    let k = sc.hidden.iter().filter(|&&h| h).count();
                                    let tail = if def.in_cover { "already in Cover terrain, one +1" } else { "+1 Defense" };
                                    let said = format!("Cover: {} is behind a sight blocker from {} ({k} of {} models) - {tail}",
                                        ut_g.name, statics[pi_s].name, sc.hidden.len());
                                    shot.log.push(said.clone());
                                    // The doors write the tray's lines (#3286): the screen says itself there too.
                                    tray.say(|| LogLine { rule: "cover_screen", category: Category::Combat, side: next.player[g.ti],
                                        detail: None, text: said });
                                }
                            }
                            // rules-wave3-growthmark (epoch 6) — the volley's
                            // LOGGING-RULE lines, named after the entry that
                            // carried the facet (the two Defensive names share
                            // one ladder).
                            if rule_on(seams.rules_epoch, EPOCH_6_TABLE_RULES) {
                                let usg = &statics[next.roster.profile[g.ti]];
                                growth_log_defender(usg, &def, next.growth_markers[g.ti], shot);
                            }
                            let alive_before_g = next.alive[g.ti];
                            let morale_alive_g = morale_alive(&next, g.ti, seams);
                            let wounds_before_g = morale_wounds_left(&next, g.ti, seams);
                            let mut feat_spends: Vec<usize> = Vec::new();
                            let mut parts: Vec<(usize, Scratch, Ctx)> = Vec::new();
                            for &mi in std::iter::once(&si).chain(next.attached[si].iter()) {
                                if next.alive[mi] <= 0 {
                                    continue;
                                }
                                let um = &statics[next.roster.profile[mi]];
                                let mut msc = Scratch {
                                    rules_epoch: seams.rules_epoch,
                                    bearers_last: seams.casualties_bearers_last,
                                    say_sight: tray.feed().is_some(), // step 27: the hit line's sight part
                                    ..Default::default()
                                };
                                // G4R3 F-HERO-RANGE (EPOCH_73_V36): range is per MODEL — a joined hero's weapons
                                // are gated by the hero's own nearest gap (the host's `g.d` below 73 and for the host).
                                let hero_own_gap = mi != si && rule_on(seams.rules_epoch, EPOCH_73_V36);
                                // G4R5 F-TARGET-CHAIN-GAP: this member's gap to ONE unit of the target's chain.
                                let gap_to = |t: usize| if seams.range_by_base_edge || plan.is_some() {
                                    range_gap_in(&next, &next.positions[mi], mi, t)
                                } else {
                                    geom::dist_in(&next.positions[mi], &next.positions[t])
                                };
                                let dm = if !hero_own_gap { g.d } else { chain_gap_in(&next, g.ti, seams, gap_to) };
                                if seams.sighting {
                                    sighted_profiles_of(
                                        um, &next, statics, mi, g.ti, &zones, dm, kind == HOLD, &mut msc,
                                    );
                                } else {
                                    profiles_of(um, next.alive[mi], dm, &mut msc);
                                    shoot_bearers_rescale(um, &next, mi, seams.rules_epoch, &mut msc);
                                }
                                if hero_own_gap && dm < g.d {
                                    // Rules-must-log: the hero's own gap kept a weapon the host's gap would have dropped.
                                    let mark = if mods::granted_vs(&next, g.ti, "+6\" shooting range") { INCREASED_SHOOTING_RANGE_MARK_IN } else { 0.0 };
                                    for p in msc.keep.iter().map(|&k| &um.shoot[k]).filter(|p| p.range as f64 + p.reach_bonus_in + mark < g.d) {
                                        let line = format!("Shooting Range: {} fires {} from its own base, {dm:.1}\" away", um.name, p.name);
                                        say_rule(tray, "shooting_range", next.player[si], || line.clone());
                                        shot.log.push(line);
                                    }
                                }
                                // G4R4 C-GRANTED-RANGE: a live spell grant's reach kept a weapon the static reach would drop.
                                let (granted, granted_rule) = granted_reach(um, &next, mi);
                                for _ in msc.keep.iter().map(|&k| &um.shoot[k]).filter(|p| granted > 0.0 && (p.range as f64) + p.reach_bonus_in < dm) {
                                    let line = format!("{granted_rule}: {} gains +{granted:.0}\" reach on {}", um.name, ut_g.name);
                                    say_rule(tray, "granted_range", next.player[si], || line.clone());
                                    shot.log.push(line);
                                }
                                if rule_on(seams.rules_epoch, EPOCH_73_V36) {
                                    // Shooting Range: the target's joined hero put a weapon in reach that its host's gap alone would drop.
                                    let host_gap = gap_to(g.ti);
                                    for p in msc.keep.iter().map(|&k| &um.shoot[k]) {
                                        let printed = p.range as f64 + p.reach_bonus_in.max(granted_reach(um, &next, mi).0);
                                        let shrunk = if def.ranged_shrouding { shrouded_reach(printed, def.ranged_shroud_penalty_in, def.ranged_shroud_floor_in) } else { printed };
                                        if (dm..host_gap).contains(&(shrunk + def.range_mark_in)) {
                                            let line = format!("Shooting Range: {} fires {} - range is measured to the nearest model of {} ({dm:.1}\" away)", um.name, p.name, ut_g.name);
                                            say_rule(tray, "shooting_range", next.player[si], || line.clone());
                                            shot.log.push(line);
                                        }
                                    }
                                    // Limited: the log names the book rule for each spent weapon the volley leaves out.
                                    for p in msc.keep.iter().map(|&k| &um.shoot[k]) {
                                        if p.limited && next.limited_used[mi].iter().any(|n| n == &p.name) {
                                            shot.log.push(format!("Limited: {} is used up — once per game", p.name));
                                            // The table's line names the member (`_solo_log_limited_spent`).
                                            say_rule(tray, "limited_spent", next.player[si], || format!("Limited: {}'s {} is used up — once per game", um.name, p.name));
                                        }
                                    }
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
                                // FEAT PR 2 — the latch's volley seam, AFTER
                                // the split aims: the extra attack joins this
                                // group exactly like the table's per-volley
                                // append (main.gd:3097), spent once per game.
                                takedown_shot_gate(
                                    statics, &next, mi, &mut msc, seams.rules_epoch,
                                    &mut feat_spends,
                                );
                                // Wave 3 — Mobile Artillery's stationary gate:
                                // the act-scope `moved` flag is the twin of the
                                // table's `moved_round == current_round` stamp
                                // (main.gd:7650/:5773-5775) — a HOLD act never
                                // moves, an ADVANCE/RUSH did.
                                let mut att = ctx_live_vs(ctx_of(um, &next, mi), statics, &next, mi, g.ti, false, seams.rules_epoch);
                                // Rules-must-log (F-SURGE-GRANT): the grant names the book rule and the spell.
                                if rule_on(seams.rules_epoch, EPOCH_73_V36) && !msc.keep.is_empty() {
                                    let grant = next.buffs[g.ti].iter().find(|r| r.attackers && &*r.grants_rule == "Surge");
                                    if let Some(r) = grant {
                                        shot.log.push(format!("Surge: {} against {} — granted by {}, once", um.name, ut_g.name, r.name));
                                    }
                                }
                                // FEAT PR 3 — the latch feats' volley read
                                // (design §4 PRs 3+4): a bearer fires at its
                                // FIRST qualifying attack while unspent —
                                // policy (a) auto, zero candidates. The gate
                                // reads the PRE-ACTIVATION snapshot (`state`),
                                // so every group of THIS volley rides the
                                // one-activation window; the spend closes the
                                // latch once per feat name (one key per feat —
                                // spending Precision never spends Speed Feat's).
                                if rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) {
                                    if um.precision_feat_hit > 0 && !state.feats_used[mi].iter().any(|n| n == "Precision Feat") {
                                        att.feat_hit_bonus += um.precision_feat_hit;
                                        if !next.feats_used[mi].iter().any(|n| n == "Precision Feat") {
                                            Rc::make_mut(&mut next.feats_used)[mi].push("Precision Feat".to_string());
                                            shot.log.push(format!("[feat] Precision Feat spent by {}", um.name));
                                        }
                                    }
                                    if um.piercing_feat_ap > 0 && !state.feats_used[mi].iter().any(|n| n == "Piercing Feat") {
                                        att.feat_ap_bonus += um.piercing_feat_ap;
                                        if !next.feats_used[mi].iter().any(|n| n == "Piercing Feat") {
                                            Rc::make_mut(&mut next.feats_used)[mi].push("Piercing Feat".to_string());
                                            shot.log.push(format!("[feat] Piercing Feat spent by {}", um.name));
                                        }
                                    }
                                }
                                att.moved_this_round = moved;
                                att.held = kind == HOLD;
                                att.member_gap_in = hero_own_gap.then_some(dm);
                                att.side = next.player[mi];
                                att.granted_reach_in = granted_reach(um, &next, mi).0;
                                parts.push((mi, msc, att));
                            }
                            // FEAT PR 2 — the deferred stamp: the unspent
                            // bearer's first volley closes its latch here, so
                            // the next group's gate (and the next volley's)
                            // sees the folded name — once per game, never
                            // re-spent.
                            for &mi in &feat_spends {
                                Rc::make_mut(&mut next.feats_used)[mi].push("Takedown Shot".to_string());
                            }
                            // Block C5 — Instinctive: the +1 reaches the
                            // shooting fold ONLY when THIS group's target is
                            // the closest enemy (main.gd:5745-5748), per
                            // member carrying it.
                            for (mi, msc, att) in parts.iter_mut() {
                                if att.instinctive_hit_bonus > 0
                                    && instinctive_applies(&next, *mi, g.ti)
                                {
                                    att.hit_mod += att.instinctive_hit_bonus;
                                    att.instinctive_applied = att.instinctive_hit_bonus;
                                }
                                att.tag_ap_mod = tag_ap;
                                // Wave 6 — the Precision pools' +1-per-marker
                                // rides the SAME attacker-side net the
                                // instinctive bonus folds into (both legs
                                // read `att.hit_mod` at the roll).
                                att.hit_mod += precision_hit;
                                att.spot_hit_note = spot_hit;
                                att.tag_hit_note = tag_hit;
                                // Reckless Piercing (epoch 7, main.gd:9877):
                                // the chain's buff stamp and the TARGET's
                                // backfire stamp — `_solo_reckless_ap`'s net.
                                att.reckless_ap = (next.reckless_ap_round[*mi] == next.round) as i64
                                    + (next.reckless_backfire_round[g.ti] == next.round) as i64;
                                // EPOCH_38_WATCHBORN_LATCH — the FIRST eligible volley decides.
                                if rule_on(seams.rules_epoch, EPOCH_38_WATCHBORN_LATCH)
                                    && (att.versatile_no_gate
                                        || g.mod_d > crate::combat::LONG_RANGE_IN)
                                {
                                    let shoot36 = &statics[next.roster.profile[*mi]].shoot;
                                    let prof36 = if rule_on(seams.rules_epoch, EPOCH_73_V36) {
                                        // The table latches on the FIRST FIRED weapon: the member's weapons that
                                        // fire, in the volley's resolve-first order (Takedown, Deadly, the rest).
                                        let mut fired: Vec<&ShootProfile> = msc.keep.iter().zip(&msc.attacks)
                                            .filter(|(_, &n)| n > 0).map(|(&k, _)| &shoot36[k]).collect();
                                        fired.sort_by_key(|p| crate::dice::shot_rank(p));
                                        fired.into_iter().find(|p| p.versatile_attack)
                                    } else {
                                        shoot36.iter().find(|p| p.versatile_attack)
                                    };
                                    if (prof36.is_some() || att.versatile_grant)
                                        && rule_on(seams.rules_epoch, EPOCH_94_PARITY_BATCH)
                                        && next.versatile_pick_round[*mi] != next.round
                                    {
                                        // The dice decide on the number the first eligible shot rolls at; stamped after the volley below.
                                        att.versatile_defer = true;
                                    } else if prof36.is_some() || att.versatile_grant {
                                        let (vh, va, vl) = versatile_latch(&mut next, statics, *mi,
                                            crate::combat::reliable_quality(att.quality,
                                                prof36.map(|p| p.reliable).unwrap_or(false)),
                                            &def, guarded_folds(&def, g.mod_d, crate::combat::LONG_RANGE_IN, seams.rules_epoch),
                                            prof36, &mut shot.log, Some(&mut *tray), seams.rules_epoch);
                                        att.versatile_pick_hit = vh;
                                        att.versatile_pick_ap = va;
                                        att.versatile_latched = vl;
                                    }
                                }
                            }
                            // G4R5 F-AMBUSH-ARRIVAL-AP (the table's `_solo_ambush_arrival_ap`): each member with the arrival AP
                            // names the rule once, before the announce (`EPOCH_73_V36`, the table's gate for the line and the AP).
                            if tray.feed().is_some() && rule_on(seams.rules_epoch, EPOCH_73_V36) {
                                for (mi, _, att) in parts.iter().filter(|(_, m, a)| !m.keep.is_empty() && a.ambush_arrival_ap > 0) {
                                    tray.say(|| LogLine { rule: "ambush_arrival", category: Category::Combat, side: next.player[si],
                                        text: format!("Ambushing Piercing Shot: {} shoots with AP(+{}) in its arrival round",
                                            statics[next.roster.profile[*mi]].name, att.ambush_arrival_ap), detail: None });
                                }
                            }
                            // One-core P3 step 24: the table's announce (`_solo_show_attack_announce`, main.gd:11752), said
                            // before the volley's first die; a group with no weapon in range never reaches it (main.gd:4693).
                            if gi == 0 && tray.feed().is_some() && parts.iter().any(|(_, m, _)| m.indirect_lost) {
                                tray.say(|| LogLine { rule: "indirect", category: Category::Combat, side: next.player[si], detail: None,
                                    text: format!("Indirect: {} did not Hold — its Indirect weapons need line of sight", statics[pi_s].name) });
                            }
                            // A unit with no ready ranged weapon at all (Strafing only, or every Limited one spent) says the table's `_solo_log_no_volley` line
                            // instead of the announce (the activation's only group; the out-of-reach case is the pending epoch's).
                            let ready = parts.iter().any(|(mi, _, _)| statics[next.roster.profile[*mi]].shoot.iter().any(|p| !(p.limited && next.limited_used[*mi].contains(&p.name))));
                            if tray.feed().is_some() && !ready && gs.len() == 1 {
                                tray.say(|| LogLine { rule: "shoot", category: Category::Combat, side: next.player[si], detail: None,
                                    text: format!("{}: no volley — no ready ranged weapon{}", statics[pi_s].name, if kind == HOLD { " — the unit holds" } else { "" }) });
                            }
                            if tray.feed().is_some() && parts.iter().any(|(_, m, _)| !m.keep.is_empty()) {
                                // The table names the target it was aimed at: a lone hero's host, not the hero (see above).
                                let aimed = lone_host.map_or(ut_g.name.as_str(), |h| statics[next.roster.profile[h]].name.as_str());
                                crate::dice::say_armor(tray, &def, ut_g.name.as_str());
                                crate::dice::say_shielded(tray, &def, aimed);
                                crate::dice::say_growth_defense(tray, &def, aimed, &growth_defense_parts(statics, &next, g.ti));
                                crate::dice::say_sturdy_replaces(tray, &def);
                                // The table's over-9" Defense line stands here, after the Defense parts and ahead of the announce.
                                crate::dice::say_guarded(tray, &def, &ut_g.name, g.mod_d);
                                def.guarded_said = true;
                                tray.say(|| LogLine { rule: "shoot", category: Category::Combat, side: next.player[si],
                                    text: format!("{} fires at {}", statics[pi_s].name, aimed), detail: None });
                            }
                            // CLASS FIX (external review 03.09. item 3 / F9,
                            // `acts::rule_on`) — same gate as `strike_phase`'s
                            // melee half above.
                            // A lone hero's hit lines call the target by its host's name, as the table does.
                            tray.aim(lone_host.map(|h| statics[next.roster.profile[h]].name.clone()));
                            // EPOCH_94_PARITY_BATCH: a volley with a Deadly weapon beside another fires its Deadly groups onto a scratch copy of
                            // the state as the weapons go (the table's inline landing); the fold asks whether the target's chain is wiped by then.
                            // Below 94, or with nothing to land inline, no clone is made and the fold is exactly what it was.
                            let inline_on = rule_on(seams.rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH)
                                && rule_on(seams.rules_epoch, EPOCH_14_DEADLY_LANDING)
                                && parts.iter().map(|(mi, msc, _)| msc.keep.iter().filter(|&&k| statics[next.roster.profile[*mi]].shoot[k].deadly > 0).count()).sum::<usize>() > 0
                                && parts.iter().map(|(_, msc, _)| msc.keep.len()).sum::<usize>() > 1;
                            let mut scratch_state = if inline_on { Some(next.clone()) } else { None };
                            let mut inline_land = |groups: &[(i64, i64)]| -> i64 {
                                let Some(sc) = scratch_state.as_mut() else { return i64::MAX };
                                for &(post, gx) in groups {
                                    land_deadly_group(sc, g.ti, post, gx, seams, &mut None, &mut 0);
                                }
                                combined_alive(sc, g.ti, seams)
                            };
                            let spread: Vec<(usize, i64)> = blast_spread_units(&next, g.ti, seams);
                            if !spread.is_empty() {   // step 29b: the defender's Blast split choice names these units
                                tray.blast_units(format!("blast_split:{}:{}", next.key(si), next.key(g.ti)),
                                    std::iter::once(g.ti).chain(spread.iter().map(|n| n.0)).map(|u| next.key(u).to_string()).collect());
                            }
                            let mut r = crate::dice::resolve_volley_with_pick_label(
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
                                // Audit 2026-09-13 §2.1 — the Deadly gate's leg
                                // pick: per-model landing from
                                // `EPOCH_14_DEADLY_LANDING`, pool multiply below.
                                rule_on(seams.rules_epoch, EPOCH_14_DEADLY_LANDING),
                                seams.tray_exact,
                                &|gr: &[i64]| takedown_pick_info_after(statics, &next, g.ti, cover, def.in_cover, td_hidden.as_deref(), gr, seams.takedown_pick),
                                &|i, pi| parts.get(i).and_then(|(mi, msc, _)| msc.sighted.get(pi)
                                    .map(|&n| (n, next.alive[*mi], msc.silent.get(pi).copied().unwrap_or("")))),
                                if inline_on { Some(&mut inline_land) } else { None },
                                rule_on(seams.rules_epoch, crate::acts::EPOCH_95_PARITY_BATCH).then_some(&|r: &ShootResult| deadly_wiped(&next, g.ti, r, seams)),
                                &spread.iter().map(|&(_, m)| m).collect::<Vec<i64>>(),
                                tray,
                            );
                            // WAVE 3, rules-must-log — the arm lowered a
                            // save target; the volley is the one leg whose
                            // over-9" gate can fire the gated aliases.
                            if r.fortified_fired {
                                let over9 =
                                    def.fortified_alias_over_in > 0.0 && g.mod_d > def.fortified_alias_over_in;
                                if let Some(n) = fortified_log_name(statics, &next, g.ti, over9) {
                                    let cut = def.fortified_boost_ap.max(if over9 { def.fortified_alias_ap } else { 0 }).max(1);
                                    shot.log.push(format!("{n}: {} takes the hits at AP(-{cut}), min. AP(0) — saves one better", ut_g.name));
                                }
                            }
                            tray.aim(None);
                            for (mi, msc, _) in &parts {
                                let shoot = &statics[next.roster.profile[*mi]].shoot;
                                mark_spent_limited(shoot, &msc.keep, &mut next.limited_used, *mi);
                            }
                            // D1-B5a: `absorb`, not `=` — a CHARGE activation
                            // puts several sub-phases into ONE report, and the
                            // replay gate compares the whole activation roll by
                            // roll.
                            // rules-wave3-growthmark (epoch 6) — the wounds
                            // this volley IGNORED, before `absorb` consumes
                            // the result (Regenerative Strength's trigger).
                            // The Deadly groups' raw tally rides `caused` but
                            // lands separately below — not an ignored wound.
                            let ignored = r.caused - r.wounds - r.deadly_tally;
                            for &(mi, ap_mode) in &r.versatile_picks {
                                (next.versatile_pick_round[mi], next.versatile_pick_mode[mi]) = (next.round, if ap_mode { 2 } else { 1 });
                            }
                            // DAT-17a: spend on wounds coming IN (pre-Regeneration),
                            // not on the post-roll count that `wounds_before_g` measures.
                            let def_incoming = r.caused > 0;
                            let phantom = r.scourge_wounds;
                            shot.attacked.push(g.ti);
                            let spill = std::mem::take(&mut r.blast_spill);
                            let w = shot.absorb(r);
                            let members: Vec<usize> = parts.iter().map(|(mi, _, _)| *mi).collect();
                            let att_incoming = land_hazardous_self(statics, &mut next, &members, seams, tray, shot);
                            // One-core P3 step 7: the target chain (host, then its joined heroes) before
                            // the landing. Only a supplied tray takes it: a seeded one clones nothing.
                            // A lone hero's wounds are reported on its host's chain as one unit ("Cultists takes 18 wounds (1/2)").
                            let rep = lone_host.unwrap_or(g.ti);
                            let chain_before = chain_snapshot(&next, rep, tray);
                            if !seams.tray_exact {
                                land_pool_wounds(&mut next, g.ti, w, false, seams, &mut shot.log);
                            }
                            // The owner's allocation opens before any inline landing of this group moves the slots.
                            let deadly: i64 = shot.deadly_groups.iter().map(|d| d.0).sum();
                            let mut alloc = if seams.tray_exact { open_alloc(&next, si, g.ti, gi, (w, deadly), tray) } else { None };
                            // Tray-exact S7: the table lands Takedown and Deadly INLINE per weapon
                            // (Takedown first, main.gd:4054-4067) and the pool at the volley's end.
                            let side = next.player[si];
                            // Plan H (H-17 lines): with the fold's marks the table's lines of each inline landing (Takedown, then each Deadly weapon)
                            // go back to that weapon's mark - its casualties and its line - and the end report counts as the melee's does (`InlineSaid`).
                            let members: Vec<usize> = chain_before.iter().flatten().map(|(u, ..)| *u).collect();
                            let mut ia = InlineAt { statics, said: vec![0; members.len()], members, rep, shift: 0 };
                            let td_marked = !shot.takedown_marks.is_empty() && !ia.members.is_empty();
                            let takedown_dealt = land_takedown_groups(&mut next, g.ti, shot, seams.takedown_pick, Some((tray, &ut_g.name, side)), Some(&mut ia));
                            // Audit 2026-09-13 §2.1 — Deadly lands PER MODEL
                            // with no carry-over (the table's
                            // `apply_deadly_wounds`, solo_controller.gd:8333):
                            // each unsaved wound ×X on the model with the most
                            // remaining wounds, capped there, surplus wasted.
                            let mut groups = std::mem::take(&mut shot.deadly_groups).into_iter();
                            let mut deadly_dealt = 0;
                            let marks = std::mem::take(&mut shot.deadly_marks);
                            let deadly_lines = std::mem::take(&mut shot.deadly_lines);
                            let inline_lines = !ia.members.is_empty() && !marks.is_empty() && marks.len() == deadly_lines.len();
                            for (i, (weapon, unsaved, dx, n)) in deadly_lines.into_iter().enumerate() {
                                let (mut dealt, mut forced) = (0, 0);
                                let lens0 = if inline_lines { model_counts(&next, &ia.members) } else { Vec::new() };
                                for (post, gx) in groups.by_ref().take(n) {
                                    let d = land_deadly_group(&mut next, g.ti, post, gx, seams, &mut alloc, &mut forced);
                                    // tray twin: deadly
                                    shot.log.push(format!(
                                        "Deadly({gx}): {post} unsaved ×{gx}, no carry-over → {d} wounds dealt"));
                                    dealt += d;
                                }
                                deadly_dealt += dealt;
                                // The table's lines (`_solo_land_deadly_wounds`), once per weapon and only when a wound landed.
                                let s = |n: i64| if n == 1 { "" } else { "s" };
                                if dealt > 0 {
                                    let mut at = if inline_lines { Some((marks[i].0 + ia.shift, marks[i].1)) } else { None };
                                    let at0 = at;
                                    let line = |text: String| LogLine { rule: "deadly", category: Category::Combat, side, text, detail: None };
                                    say_at_mark(tray, &mut at, line(format!(
                                        "Deadly({dx}): {unsaved} unsaved ×{dx}, no carry-over → {dealt} wound{} dealt ({weapon})", s(dealt))));
                                    if forced > 0 {
                                        say_at_mark(tray, &mut at, line(format!(
                                            "Deadly({dx}): {forced} wound{} finish the already-wounded Tough model first ({CITE})", s(forced))));
                                    }
                                    if inline_lines {
                                        let lost: Vec<i64> = lens0.iter().zip(model_counts(&next, &ia.members)).map(|(&a, b)| a as i64 - b as i64).collect();
                                        for l in chain_loss_lines(statics, &next, rep, &ia.members, &lost) {
                                            say_at_mark(tray, &mut at, l);
                                        }
                                        lost.iter().zip(ia.said.iter_mut()).for_each(|(l, sd)| *sd += l);
                                    }
                                    ia.shift += at.zip(at0).map_or(0, |(a, b)| a.0 - b.0);
                                }
                            }
                            for (post, gx) in groups {   // a group no weapon line owns still lands (the volley leg records one per weapon)
                                let d = land_deadly_group(&mut next, g.ti, post, gx, seams, &mut alloc, &mut 0);
                                shot.log.push(format!("Deadly({gx}): {post} unsaved ×{gx}, no carry-over → {d} wounds dealt"));
                                deadly_dealt += d;
                            }
                            if seams.tray_exact {
                                let left = alloc.as_mut().map_or(w, |a| land_pool_picked(&mut next, g.ti, w, a, tray));
                                land_pool_wounds(&mut next, g.ti, left, true, seams, &mut shot.log);
                            }
                            // One-core P3 steps 7/25/27: the landing's lines and its landings, stamped BEFORE the group's morale test below draws.
                            let inline_said = ((inline_lines || td_marked) && deadly_dealt + takedown_dealt > 0).then_some(InlineSaid { said: ia.said, pool: w });
                            land_chain_report_said(statics, &next, tray, rep, chain_before, deadly_dealt + takedown_dealt, inline_said.as_ref());
                            let neighbours: Vec<usize> = spread.iter().map(|&(u, _)| u).collect();
                            let spilled = land_blast_spill(statics, &mut next, &parts, &spill, &neighbours, (g.d, g.mod_d), false, seams, tray, shot);
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
                                growth_credit_kill(statics, &mut next, si, seams, tray);
                            }
                            // Wave 4 follow-up (port-vengeance) — the volley's
                            // wiped target banks its Vengeance markers on the
                            // shooter (main.gd:3310/:10043), epoch-gated like
                            // the fold.
                            if rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES)
                                && alive_before_g > 0
                                && next.alive[g.ti] <= 0
                            {
                                vengeance_on_kill(statics, &mut next, g.ti, si, shot, tray);
                            }
                            // main.gd:3244 — the exchange spends its own
                            // once-mods BEFORE the post-volley morale test.
    let att_wounded = att_incoming > 0;
                            spend_exchange_wounded(&mut next, si, g.ti, false, att_wounded, def_incoming, seams.rules_epoch);
                            spend_protection_feat(statics, &mut next, g.ti, def_incoming, seams.rules_epoch);
                            // D1-B5b: the volley's morale test is the NEXT
                            // thing on the table's tray (main.gd:8248-8251),
                            // per group — inside the per-group
                            // `_solo_resolve_ai_volley` (:3249-3255). Leaving
                            // it undrawn is what put every later activation of
                            // a `dice="table"` game on a different stream than
                            // the recording.
                            let log_from = shot.log.len();
                            let trigger = scourge_morale_trigger(
                                &next, statics, seams, ut_g, g.ti, morale_alive_g, wounds_before_g, phantom, &mut shot.log,
                            );
                            if tray.feed().is_some() {
                                // The table's order (`_solo_shooting_morale`): the half-strength line, then the Scourge note (said even when the
                                // phantom wounds do not decide), then the test.
                                if let Some(line) = shooting_morale_line(&next, statics, seams, ut_g, g.ti, morale_alive_g, wounds_before_g) {
                                    say_rule(tray, "morale", next.player[g.ti], || line);
                                }
                                say_scourge(tray, next.player[g.ti], &shot.log[log_from..]);
                            }
                            if trigger {
                                tray_morale(&mut next, statics, g.ti, false, seams, tray, shot, Some(g.mod_d), None);
                            }
                            // The skirmish Blast spread: every neighbour that took wounds tests morale like the target, in order.
                            blast_spill_morale(statics, &mut next, &spilled, Some(g.mod_d), seams, tray, shot);
                            // the table says the Mark's consumption after the volley's morale test (state spent above, ahead of it)
                            say_marks_consumed(statics, &next, tray, shot);
                        }
                    }
                    None => {
                        apply_expected_wounds(&mut next, ti, volley, rng.as_deref_mut());
                        let ut = &statics[next.roster.profile[ti]];
                        // AI-06: SHO-15a's trigger with the expected phantom wounds landed on a
                        // scratch copy, so nothing is removed (0 below the wave).
                        let mut log = Vec::new();
                        let trigger = scourge_morale_trigger(
                            &next, statics, seams, ut, ti, morale_alive_before, wounds_before,
                            phantom.round() as i64, &mut log,
                        );
                        log.iter().for_each(|line| trace_rule("volley", "Scourge", line));
                        if trigger && morale_fails_expected(&next, statics, ti, seams) {
                            next.shaken[ti] = true;
                            drop_carried(&mut next, ti);
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
            // #183 (`EPOCH_77_CHARGE_CAP`, main.gd `snap_charge_per_model`): each model spends its OWN leftover; the
            // fight needs the picked model's snap to land (a negative snap is the falls-short).
            let per_model = charge_arcs.as_ref().filter(|_| rule_on(seams.rules_epoch, EPOCH_77_CHARGE_CAP)
                && seams.movement && !seams.plain_only).map(|(arcs, band)| {
                let mut trial = next.clone();
                let snap = (crate::mv::step::MoveRules { rules_epoch: seams.rules_epoch })
                    .snap_charge_state_per_model(&mut trial, si, ti, arcs, *band, seams.hero_attach);
                (snap.filter(|s| s.0 >= 0.0).map(|s| (trial, s)), snap.map_or(0.0, |s| s.0))
            });
            if engage_gap_in <= MELEE_ENGAGE_IN && per_model.as_ref().map_or(engage_gap_in <= BASE_CONTACT_EPSILON_IN
                    || engage_gap_in <= charge_remaining_in + BASE_CONTACT_EPSILON_IN, |t| t.0.is_some())
            {
                // The snap the table narrates (`_run_ai_melee`): its size and the models left at their band.
                let mut said_snap = (0.0, 0);
                if let Some((Some((snapped, s)), _)) = per_model {
                    next = snapped;
                    said_snap = s;
                }
                let (sname, tname) = (statics[pi_s].name.clone(), statics[next.roster.profile[ti]].name.clone());
                if seams.movement && !seams.plain_only {
                    if !rule_on(seams.rules_epoch, EPOCH_77_CHARGE_CAP) || charge_arcs.is_none() {
                        said_snap.0 = (crate::mv::step::MoveRules { rules_epoch: seams.rules_epoch })
                            .snap_charge_state(&mut next, si, ti, charge_remaining_in, seams.hero_attach).unwrap_or(0.0);
                    }
                    if let (true, Some((tray, _))) = (said_snap.0 > 0.05, dice.as_mut()) {
                        say_melee(tray, next.player[si], format!("{sname} charges into base contact (+{:.1}\") — {CITE}", said_snap.0));
                        if said_snap.1 > 0 {
                            say_melee(tray, next.player[si], format!("{sname}: {} model{} stay at their band (Charge: up to 12\"; Unit Coherency as close as possible)",
                                said_snap.1, if said_snap.1 == 1 { "" } else { "s" }));
                        }
                    }
                    // G4-C8b: the defender's mandatory pile-in, before Counter, Impact and every strike.
                    if let (true, Cover::Board(t)) = (rule_on(seams.rules_epoch, EPOCH_73_V36), cover) {
                        let n = (crate::mv::step::MoveRules { rules_epoch: seams.rules_epoch }).pile_in_state(&mut next, t, si, ti, seams.hero_attach);
                        if let (true, Some((_, shot))) = (n > 0, dice.as_mut()) {
                            shot.log.push(format!("Pile In: {}: {n} model{} pile in up to 3\"", statics[next.roster.profile[ti]].name, if n == 1 { "" } else { "s" }));
                        }
                        if let Some((tray, _)) = dice.as_mut() {
                            let text = if n > 0 { format!("{tname}: {n} model{} pile in up to 3\" ({CITE})", if n == 1 { "" } else { "s" }) }
                                else { format!("{tname}: all models already in base contact — no pile-in needed ({CITE})") };
                            if n > 0 || combined_alive(&next, ti, seams) > 1 {
                                say_melee(tray, next.player[ti], text);
                            }
                        }
                    }
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
                    if let Some((host, hero)) = lone {
                        shot.log.push(format!(
                            "Hero: {} has no models left - {} is the unit now",
                            statics[next.roster.profile[host]].name, statics[next.roster.profile[hero]].name
                        ));
                    }
                    // EPOCH_22_SCREENED_MELEE — the pre-charge gap, measured the
                    // table's own way on the PRE-move snapshot
                    // (`report["charge_from_in"]`, solo_controller.gd:2329).
                    // `state` still holds the positions before the charge.
                    let charge_from_in =
                        modifier_distance_in(state, si, ti, seams);
                    // Rules 3.6: what the charger's own Dangerous test cost it on the charge move counts as taken.
                    let self_wounds = (wounds_left(state, si) - su_before).max(0) + dangerous_tail_wounds;
                    if let Some(li) = tray_charge_with_self_wounds(statics, &mut next, si, ti, seams, tray, shot, charge_from_in, cover, self_wounds, pre_melee_su, pre_melee_tu) {
                        // D1-B5b: the melee loser's test is a REAL die now
                        // (:8116-8118), where D1-B5a still asked the
                        // expected-value oracle for the outcome.
                        if !rule_on(seams.rules_epoch, EPOCH_65_MELEE_TRUTH) || morale_side_alive(&next, li, seams) {
                            // A rout removes the loser; the step path lands it with the table's lines.
                            let routed = chain_snapshot(&next, li, tray);
                            // MOR-09b: the loser's own charge keeps Banner but drops the
                            // Valiant share; only a unit that WAS charged keeps the band.
                            if li == si {
                                tray_morale_for(&mut next, statics, li, true, false, None,
                                    seams, tray, shot, None, None);
                            } else {
                                tray_morale(&mut next, statics, li, true, seams, tray, shot, None,
                                    Some(charge_from_in));
                            }
                            land_chain_report(statics, &next, tray, li, routed);
                        }
                    }
                    // Ruling D12: a bystander the melee's Blast wounded tests at the end of the activation like a shot target.
                    let spilled = std::mem::take(&mut shot.melee_spilled);
                    blast_spill_morale(statics, &mut next, &spilled, None, seams, tray, shot);
                    // Coverage wave — growth markers (Defensive Frenzy):
                    // main.gd:8137-8140 credits the WIPING side's own kill
                    // marker, win-by-wipe only — a mutual wipe or a fight
                    // that leaves both sides standing earns nothing.
                    if next.alive[ti] <= 0 && next.alive[si] > 0 {
                        growth_credit_kill(statics, &mut next, si, seams, tray);
                    } else if next.alive[si] <= 0 && next.alive[ti] > 0 {
                        growth_credit_kill(statics, &mut next, ti, seams, tray);
                    }
                    // Wave 4 follow-up (port-vengeance) — Vengeance at the
                    // melee consolidation's own guards (main.gd:8226-8231):
                    // win-by-wipe only, each direction credits the wiper.
                    if rule_on(seams.rules_epoch, EPOCH_7_TABLE_RULES) {
                        if next.alive[ti] <= 0 && next.alive[si] > 0 {
                            vengeance_on_kill(statics, &mut next, ti, si, shot, tray);
                        } else if next.alive[si] <= 0 && next.alive[ti] > 0 {
                            vengeance_on_kill(statics, &mut next, si, ti, shot, tray);
                        }
                    }
                } else {
                    // The charger strikes: charging profiles, its OWN fatigue state
                    // (still the pre-charge one), the defender's plain context.
                    let (ev, phantom_on_tu) = {
                        let us = &statics[pi_s];
                        let ut = &statics[next.roster.profile[ti]];
                        let att = ctx_of_melee(us, &next, si, seams.rules_epoch);
                        let def = with_cond_ap_state(ctx_of(ut, &next, ti), statics, &next, ti, seams);
                        // NML-1132: the charger's strike phase is the host's melee set
                        // PLUS every alive attached hero's, the way the table builds it.
                        member_profiles_of(statics, &next, si, true, 0.0, seams, &mut sc);
                        // D-GATE6: priced at the pre-charge gap (`state` is the pre-move snapshot).
                        let gap = charge_estimate_gap_in(seams.rules_epoch, || modifier_distance_in(state, si, ti, seams));
                        let ev = melee_ev(folded_slice(&us.melee, &sc), &sc.attacks, &att, &def, true, gap);
                        let phantom = scourge_phantom_ev(
                            folded_slice(&us.melee, &sc), None, &sc.attacks, &att, &def, gap,
                            true, seams.rules_epoch,
                        );
                        (ev, phantom)
                    };
                    apply_expected_wounds(&mut next, ti, ev, rng.as_deref_mut());
                    set_melee_fatigue(&mut next, si, seams);
                    let mut phantom_on_su = 0.0;
                    if next.alive[ti] > 0 {
                        // Survivors strike back, already survivor-scaled by the
                        // updated `alive`. W-P1 parity (p.9): the strike-back
                        // fatigues the DEFENDER too.
                        // MEL-PAR-B14 (`EPOCH_73_V36`): no melee weapon at all means no expected
                        // strike-back and no expected fatigue either.
                        if rule_on(seams.rules_epoch, EPOCH_73_V36) && chain_has_no_melee(statics, &next, ti) {
                            // nothing to strike with — the fight leaves the defender un-Fatigued
                        } else {
                            let (ev_back, phantom) = {
                                let ut = &statics[next.roster.profile[ti]];
                                let us = &statics[pi_s];
                                let att = ctx_of_melee(ut, &next, ti, seams.rules_epoch);
                                let def = with_cond_ap_state(ctx_of(us, &next, si), statics, &next, si, seams);
                                // The strike-back folds too (`_solo_attack_groups` is built
                                // for the DEFENDER the same way, main.gd:4284-4290).
                                member_profiles_of(statics, &next, ti, true, 0.0, seams, &mut sc);
                                let ev = melee_ev(folded_slice(&ut.melee, &sc), &sc.attacks, &att, &def, false, 0.0);
                                let phantom = scourge_phantom_ev(
                                    folded_slice(&ut.melee, &sc), None, &sc.attacks, &att, &def, 0.0,
                                    false, seams.rules_epoch,
                                );
                                (ev, phantom)
                            };
                            apply_expected_wounds(&mut next, si, ev_back, rng);
                            set_melee_fatigue(&mut next, ti, seams);
                            phantom_on_su = phantom;
                        }
                    }
                    // MEL-10e: the charger's own charge-move wounds are part of what
                    // it TOOK. The expected-value path rolls no Dangerous test, so the
                    // pre-move delta is 0 today; the term keeps this estimate's twin of
                    // `tray_charge_with_self_wounds` in step.
                    let self_wounds = (wounds_left(state, si) - su_before).max(0);
                    expected_melee_morale(&mut next, statics, si, su_before, ti, tu_before, self_wounds, phantom_on_su, phantom_on_tu, seams);
                }
                // Consolidation Moves (GF v3.5.1 p.9), seam-gated: one side
                // wiped by the melee just resolved above (wounds or the
                // morale rout), win or EV path alike — the survivor may move.
                if seams.consolidate || rule_on(seams.rules_epoch, EPOCH_73_V36) {
                    consolidate_after_melee(&mut next, statics, cover, seams, si, ti, dice.as_mut().map(|d| (&mut *d.0, &mut *d.1)));
                }
            } else if let Some((tray, _)) = dice.as_mut() {
                // The table's falls-short lines (`_run_ai_melee`): out of the engage reach, or the snap's budget spent.
                let sname = &statics[pi_s].name;
                say_melee(tray, next.player[si], if engage_gap_in > MELEE_ENGAGE_IN {
                    format!("{sname}'s charge falls short ({engage_gap_in:.1}\")")
                } else {
                    let gap = per_model.as_ref().map_or(engage_gap_in, |t| -t.1);
                    format!("{sname}'s charge falls short ({gap:.1}\" gap, move budget spent) — {CITE} 'as close as possible'")
                });
            }
        }
    }

    // --- PUSH (3.6 skirmish p.15: "When a unit is Shaken after being attacked, the attacker may try to push it") --- the
    // attacker's offer (`Input::Push`), see `push_holds`.
    if let Some((tray, shot)) = dice.as_mut() {
        if let (Some(p), true) = (tray.push().cloned(), next.book(si).vertical_moves && rule_on(seams.rules_epoch, crate::acts::EPOCH_101_SKIRMISH_PUSH)) {
            let name = statics[pi_s].name.clone();
            let line = match next.roster.index.get(&p.target).copied() {
                Some(ti) if push_holds(state, &next, si, ti, &shot.attacked) => {
                    // One die, 4+: the attacker may move one model of the target up to 2 in (3.6 p.15).
                    let tname = &statics[next.roster.profile[ti]].name;
                    tray.owner_next(Some(si));
                    let faces = tray.roll(1);
                    let face = faces.first().copied().unwrap_or(0);
                    shot.rolls.push(crate::dice::Roll { kind: "push", count: 1, target: 4, faces, owner: name.clone() });
                    if face < 4 {
                        format!("Push: {name} rolls {face} to push {tname} - no push on 1-3")
                    } else {
                        match push_spot(&next, ti, &p, cover) {
                            Ok((moved_in, fall)) => {
                                next.positions[ti][p.model] = p.to;
                                // Falling (3.6 p.15): pushed off 2 in or more, the model rolls one die per inch, each 1-3 a wound on
                                // it. The pushed unit is not the active one, so no activation ends (ruling D10).
                                let fell = fall.map(|h| {
                                    tray.owner_next(Some(ti));
                                    let faces = tray.roll((h - 1e-6).ceil().max(0.0) as usize);
                                    let w = faces.iter().filter(|&&f| f <= 3).count() as i64;
                                    shot.rolls.push(crate::dice::Roll { kind: "fall", count: faces.len() as i64, target: 4, faces: faces.clone(), owner: tname.clone() });
                                    let take = w.min(next.wounds[ti].get(p.model).copied().unwrap_or(0));
                                    land_wounds_in_order(&mut next, ti, take, vec![p.model]);
                                    format!(" off a {h:.0} in drop - it falls, {faces:?}, {w} wound{} on 1-3", if w == 1 { "" } else { "s" })
                                }).unwrap_or_default();
                                let alive = next.positions[ti].get(p.model).is_some_and(|q| *q == p.to);
                                let rest = if alive { push_regroup(&mut next, ti, p.model, cover) } else { String::new() };
                                format!("Push: {name} rolls {face} and pushes {tname} model {} {moved_in:.1} in{fell}{rest}", p.model + 1)
                            }
                            Err(why) => format!("Push: {name} rolls {face}, but {why} - nothing moves"),
                        }
                    }
                }
                Some(ti) => format!("Push: no push - {} is not Shaken by this attack", statics[next.roster.profile[ti]].name),
                None => format!("Push: no push - {} is no unit of this game", p.target),
            };
            shot.log.push(line.clone());
            say_rule(tray, "push", next.player[si], || line);
        } else if tray.push().is_none() && next.book(si).vertical_moves && rule_on(seams.rules_epoch, crate::acts::EPOCH_101_SKIRMISH_PUSH) {
            // No push declared (the AI never declares one; ruling D10 / step 19): where one would hold, say so once per unit.
            let mut seen: Vec<usize> = Vec::new();
            for &ti in &shot.attacked.clone() {
                if !seen.contains(&ti) && push_holds(state, &next, si, ti, &shot.attacked) {
                    seen.push(ti);
                    let line = format!("Push: {} does not push {}", statics[pi_s].name, statics[next.roster.profile[ti]].name);
                    shot.log.push(line.clone());
                    say_rule(tray, "push", next.player[si], || line);
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
        // Step 20: a human bearer's step is the player's drag (`Input::Intent { no_step }`): the core takes none.
        let hnr_attacked = hnr_attacked && !dice.as_ref().is_some_and(|(tray, _)| tray.no_step());
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
            if let Some((_, shot)) = dice.as_mut() {
                shot.log.push(format!("{rule}: {} steps up to {band}\" after its attack", us.name));
            }
            // Rules 3.6 (row W1.TRACE) — the melee leg's post-attack step
            // names itself once (arm `hit-and-run`).
            if !shot_leg && rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
                trace_rule("hit-and-run", "Hit & Run", &format!(
                    "{} steps up to {band}\" after its melee attack", us.name));
            }
            // Retreating Strike (main.gd:1097, resolver wave A): the post-
            // MELEE step may lash out -- the shooting leg never does.
            if !shot_leg {
                if let Some((tray, shot)) = dice.as_mut() {
                    tray_retreating_strike(statics, &mut next, si, seams, tray, shot);
                }
            }
        } else if hnr_attacked && hit_and_run_mixed(statics, &next, si, shot_leg, seams.rules_epoch) {
            // UX-19: the refusal's rules-must-log line (`SoloController.last_hit_and_run_note`).
            if let Some((_, shot)) = dice.as_mut() {
                shot.log.push(format!(
                    "Hit & Run: {} stays put - not every model in the unit has the rule",
                    statics[next.roster.profile[si]].name
                ));
            }
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
                if shooting_morale_trigger(&next, statics, seams, us, si, alive_before, wounds_before) {
                    tray_morale_for(&mut next, statics, si, false, true, Some("Dangerous terrain"), seams, tray, shot, None, None);
                }
            }
        }
    }

    // --- FALLING END MORALE (3.6 skirmish p.15: the fall's wounds count at the end of the activation, like Dangerous's) ---
    if let (Some((alive_before, wounds_before)), true) = (fall_morale_due, next.alive[si] > 0) {
        if let Some((tray, shot)) = dice.as_mut() {
            if shooting_morale_trigger(&next, statics, seams, &statics[pi_s], si, alive_before, wounds_before) {
                tray_morale_for(&mut next, statics, si, false, true, Some("Falling"), seams, tray, shot, None, None);
            }
        }
    }

    // --- PRECISION MARKERS — SPOTTER (main.gd:1127, the END-of-activation
    // beat — the spot fires after every attack of this activation, so its
    // marker lands for the NEXT friendly attack) — tray path only, see
    // `tray_precision_markers`; the 4+ is a real tray draw.
    if let Some((tray, shot)) = dice.as_mut() {
        if !rule_on(seams.rules_epoch, crate::acts::EPOCH_73_V36) {
            tray_precision_markers(statics, &mut next, si, seams, tray, shot, true);
        }
    }

    // --- shaken recovery (battle_sim.gd:648-650) ---
    if was_shaken && kind == HOLD && shoot_key.is_empty() {
        next.shaken[si] = false;
        // The table's idle recovery mirrors the cleared flag onto the unit's joined heroes (`_solo_mirror_shaken`).
        if seams.hero_attach && rule_on(seams.rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) {
            for h in next.attached[si].clone() {
                next.shaken[h] = false;
            }
        }
    }
    Ok(finish_activation(statics, state, next, si, seams, cover))
}

/// Heightfield plan step 12 (`EPOCH_94_PARITY_BATCH`, a board with tiers): every model of a unit that moved in this
/// activation stands on the surface under its x/z. A planned move already ends there (`Landing.end` reads
/// `surface_y_m`); the writers that shift a model in x/z and keep its y (rigid steps, Hit & Run, Mind Control, a
/// Teleport, the charge snap, the pile-in, a revived model) are repaired here, once, so the board has one height truth.
/// A flat board and every epoch below the gate are left exactly as they were.
fn settle_on_surface(next: &mut State, parent: &State, cover: Cover<'_>, rules_epoch: u32) {
    let Cover::Board(t) = cover else { return };
    if !rule_on(rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) || t.tier_boxes().is_empty() {
        return;
    }
    for (now, before) in next.positions.iter_mut().zip(&parent.positions) {
        if now != before {
            settle_models(t, now, rules_epoch);
        }
    }
    settle_objectives(t, &mut next.objectives, &parent.objectives, rules_epoch);
}

/// Heightfield plan step 15: a marker the activation moved (a relic dropped ~1 in from its carrier keeps the carrier's y) stands
/// on the surface under its new x/z; one that did not move is left as captured (the table owns marker heights, step 20).
pub(crate) fn settle_objectives(t: &Terrain, now: &mut [crate::state::Objective], before: &[crate::state::Objective], rules_epoch: u32) {
    if rule_on(rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) && !t.tier_boxes().is_empty() {
        for (o, _) in now.iter_mut().zip(before).filter(|(o, b)| o.pos != b.pos) {
            o.pos[1] = sight::surface_y_m(t, [o.pos[0], o.pos[2]], rules_epoch);
        }
    }
}

/// Heightfield plan step 14: put `models` on the surface under their x/z (a board with tiers at the height gate only).
pub(crate) fn settle_models(t: &Terrain, models: &mut [[f64; 3]], rules_epoch: u32) {
    if rule_on(rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) && !t.tier_boxes().is_empty() {
        for p in models {
            p[1] = sight::surface_y_m(t, [p[0], p[2]], rules_epoch);
        }
    }
}

/// Shared end-of-activation bookkeeping (normal finish and CC-7a early exit when a cast wipes the activating unit):
/// mark the unit + joined heroes activated, check Second Wind, refresh LOS pairs on a live board, and sync positions.
fn finish_activation(statics: &[UnitStatic], state: &State, mut next: State, si: usize, seams: Seams, cover: Cover<'_>) -> State {
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
    settle_on_surface(&mut next, state, cover, seams.rules_epoch);
    if let Cover::Board(terrain) = cover {
        refresh_los_pairs(&mut next, state, terrain, seams);
    }
    sync_carried_positions(&mut next);
    next
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
            m[i * n + j] = !terrain.los_blocked_at(centres[i], centres[j], seams.rules_epoch);
            m[j * n + i] = !terrain.los_blocked_at(centres[j], centres[i], seams.rules_epoch);
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
        assert_eq!(bearer_scaled_attacks(&rifle, 5, 5, 5, None), 10);
        assert_eq!(bearer_scaled_attacks(&rifle, 5, 5, 3, None), 6);
        assert_eq!(bearer_scaled_attacks(&rifle, 5, 5, 0, None), 0);
        // 2 special weapons in a unit of 5, 2 attacks each (merged base 4): the
        // bearer path caps at the copies, so a wide sightline adds nothing...
        let special = weapon(4, 2, 24);
        assert_eq!(bearer_scaled_attacks(&special, 5, 5, 5, None), 4);
        // ...and a narrow one binds instead of the copies.
        assert_eq!(bearer_scaled_attacks(&special, 5, 5, 1, None), 2);
        // Casualties take bearers with them: 1 model left carries at most 1 copy.
        assert_eq!(bearer_scaled_attacks(&special, 1, 5, 5, None), 2);
        // RED for the whole rung: answering `alive` instead of `sighted` gives
        // the count this port drew before D6a, and it is a different number.
        assert_ne!(bearer_scaled_attacks(&rifle, 5, 5, 3, None), bearer_scaled_attacks(&rifle, 5, 5, 5, None));
    }
}

#[cfg(test)]
mod pair_dist_memo_tests {
    use super::*;

    fn arr(seed: u64, n: usize) -> Vec<[f64; 3]> {
        let mut s = seed | 1;
        (0..n)
            .map(|_| {
                let mut c = [0.0; 3];
                for v in c.iter_mut() {
                    s ^= s << 13;
                    s ^= s >> 7;
                    s ^= s << 17;
                    *v = ((s >> 8) % 4000) as f64 / 100.0;
                }
                c
            })
            .collect()
    }

    /// The memo returns exactly `dist_in` whether the slot is empty, holds the same arrays, holds a stale pair
    /// (a moved unit), or belongs to another roster size.
    #[test]
    fn the_pair_distance_memo_always_equals_a_fresh_dist_in() {
        let (a0, b0) = (arr(11, 6), arr(12, 7));
        let want = |a: &[[f64; 3]], b: &[[f64; 3]]| geom::dist_in(a, b).to_bits();
        for n in [5usize, 9, 5] {
            for round in 0..3 {
                assert_eq!(pair_dist_memo(n, 1, 2, &a0, &b0).to_bits(), want(&a0, &b0), "cold/warm n={n} r={round}");
                let mut a1 = a0.clone();
                a1[3][0] += 0.25; // one model stepped: the slot is stale for this pair
                assert_eq!(pair_dist_memo(n, 1, 2, &a1, &b0).to_bits(), want(&a1, &b0), "stepped n={n} r={round}");
                let a2: Vec<[f64; 3]> = a0.iter().map(|p| [p[0] + 500.0, p[1], p[2]]).collect(); // the whole unit moved: d changes for certain
                assert_ne!(want(&a2, &b0), want(&a0, &b0));
                assert_eq!(pair_dist_memo(n, 1, 2, &a2, &b0).to_bits(), want(&a2, &b0), "a moved n={n} r={round}");
                let b2: Vec<[f64; 3]> = b0.iter().map(|p| [p[0], p[1] - 300.0, p[2]]).collect();
                assert_ne!(want(&a2, &b2), want(&a2, &b0));
                assert_eq!(pair_dist_memo(n, 1, 2, &a2, &b2).to_bits(), want(&a2, &b2), "b moved n={n} r={round}");
                assert_eq!(pair_dist_memo(n, 1, 2, &a0, &b0).to_bits(), want(&a0, &b0), "back n={n} r={round}");
                let c = arr(20 + round, 2); // < 16 model pairs: direct
                assert_eq!(pair_dist_memo(n, 0, 1, &c, &c).to_bits(), want(&c, &c));
                let z: Vec<[f64; 3]> = Vec::new();
                assert_eq!(pair_dist_memo(n, 2, 3, &z, &b0).to_bits(), want(&z, &b0), "empty side");
            }
        }
    }
}

#[cfg(test)]
#[path = "tests/sim/mod.rs"]
pub(crate) mod tests;

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
            needs_los: false,
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
            ..Default::default()
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
            hit_mod: 0, casting_mod, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0,
            move_mod: 0, range_in: 0,
            grants_rule: Rc::from(""), scope: Rc::from(""), attackers: false, once: false,
            name: Rc::from(""),
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
        apply_cast_effect(&statics, &mut st, 0, &grant, 1.0, Seams::default(), None);
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

    /// Firefight step 6: `hero_aura_quality` and `stamp_blast_models` read `rules::Book` fields
    /// (same values for all five systems today -> zero outcome change).
    #[test]
    fn hero_aura_and_blast_cap_read_book_fields() {
        use crate::rules::{book, Book, HeroAura};
        let (mut st, mut statics) = host_and_caster_hero();
        // Separate hero (unit 1) at 4" from unit 0, Tough(3), Quality 3+ vs unit 0 Quality 5+.
        Rc::make_mut(&mut st.attached)[0].clear();
        Rc::make_mut(&mut st.attached_to)[1] = None;
        st.positions[0] = vec![[0.0, 0.0, 0.0]];
        st.positions[1] = vec![[4.0 * IN2M, 0.0, 0.0]];
        Rc::make_mut(&mut st.radii)[0] = vec![0.0];
        Rc::make_mut(&mut st.radii)[1] = vec![0.0];
        statics[0].quality = 5;
        statics[1].is_hero = true;
        statics[1].quality = 3;
        statics[1].ctx.tough = 3;
        let seams = Seams { rules_epoch: EPOCH_73_V36, hero_attach: true, ..Seams::default() };

        // Today's GF and GFF books keep min_tough = 9, reach_in = 6.0 -> Tough(3) hero does not lend.
        assert_eq!(hero_aura_quality(&statics, &st, 0, 5, seams), None);
        assert_eq!(hero_aura_quality_for_book(&statics, &st, 0, 5, seams, book("gf").hero_aura), None);
        // Custom aura header lowers min_tough -> same hero lends within reach, not outside reach.
        let low_tough = HeroAura { reach_in: 6.0, min_tough: 1, joins: false };
        assert_eq!(hero_aura_quality_for_book(&statics, &st, 0, 5, seams, low_tough), Some((1, 3)));
        let short_reach = HeroAura { reach_in: 3.0, min_tough: 1, joins: false };
        assert_eq!(hero_aura_quality_for_book(&statics, &st, 0, 5, seams, short_reach), None);

        // Blast cap reads `book.hero_aura.joins`: host (3) + joined hero (1) = 4 when joins=true, 3 when joins=false.
        st.alive[0] = 3;
        st.alive[1] = 1;
        Rc::make_mut(&mut st.attached)[0] = vec![1];
        Rc::make_mut(&mut st.attached_to)[1] = Some(0);
        let mut def = Ctx::default();
        stamp_blast_models(&mut def, &st, 0, seams);
        assert_eq!(def.blast_models, Some(4), "today's book joins=true counts host + hero");
        let no_join = Book { hero_aura: low_tough, ..*book("gf") };
        assert_eq!(blast_cap_models(&st, 0, seams, &no_join), 3, "joins=false counts host models only");
    }
}
