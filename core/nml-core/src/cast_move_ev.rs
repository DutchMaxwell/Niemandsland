//! D-MAGIC step 4 — movement-modifier pricing for the cast EV
//! (`BRIEF_castmove.md`). The movement fields of a `SpellModifier`
//! (`rush_in` / `advance_in` / `range_in`, rules.rs:328-336) price the
//! USAGE they move: the absolute charge/shoot usage value of the unit
//! that receives the modifier, with minus without the spell's fields.
//!
//! The usage value is the MAX of the two movement outlets (the table's
//! own max-of-shooting-and-melee shape, `_modifier_value_on_attack`
//! solo_controller.gd:4530-4556): the charge the band reaches
//! (`movement_range_controller.gd:182-191` — only the spell RUSH folds
//! into the charge reach; a spell advance NEVER does) and the
//! advance-then-shoot shot the band buys (`solo_controller.gd:5625` —
//! `shooting_range_bonus` rides EVERY profile). The maxf sign trap —
//! `max(-ev, 0) = 0` would zero every movement debuff — is avoided by
//! pricing ABSOLUTE usage values, so a buff's delta is a gain and a
//! debuff's delta a loss, both worth the same absolute number to the
//! caster's side.
//!
//! The table's spell menu prices these fields 0 (ai_spell.gd:250-252) —
//! the core prices them from its own charge/shoot EV, the ONE deviation
//! the PR body documents in full.

use crate::acts::CURRENT_RULES_EPOCH;
use crate::combat::{effective_attacks, melee_ev, shoot_ev};
use crate::geom;
use crate::menu::{nearest_enemy, FUTILE_CHARGE_EV};
use crate::rules::SpellModifier;
use crate::sim::{
    ctx_live, ctx_of, live_bands_of, melee_profiles_of, Scratch, DEFAULT_BASE_RADIUS_M,
};
use crate::state::State;
use crate::unit::UnitStatic;

/// The movement-modifier gain: `movement_value(with) −
/// movement_value(without)`, `.abs()` folding the arm's sign in (a buff
/// ADDS usage, a debuff REMOVES it — both help the caster's side).
pub(crate) fn movement_cast_gain(
    statics: &[UnitStatic],
    state: &State,
    actor: usize,
    m: &SpellModifier,
) -> f64 {
    let zero = SpellModifier { present: true, ..Default::default() };
    (movement_value(statics, state, actor, m)
        - movement_value(statics, state, actor, &zero))
    .abs()
}

/// The actor's movement usage value: the best EV its movement can convert
/// this activation, charge leg or advance-then-shoot leg (both priced on
/// the NEAREST enemy, `best_charge`'s single-candidate shape), floored at
/// 0.
fn movement_value(
    statics: &[UnitStatic],
    state: &State,
    i: usize,
    m: &SpellModifier,
) -> f64 {
    charge_usage(statics, state, i, m)
        .max(shoot_usage_ev(statics, state, i, m))
        .max(0.0)
}

/// The charge leg: the melee EV of the charging swing the LIVE band can
/// reach, 0 when it cannot. The band is the gate's own LIVE charge band
/// (`charge.unwrap_or(rush)` plus the rush-kind delta, gate.rs:68) with
/// the spell rush on top, Melee-Shrouding folded. The gate's aircraft
/// refusal and the futile bar (0.2, `best_charge`'s shape) come along; no
/// `&Terrain` reaches this leg, so the difficult corridor probe does not
/// run (documented in the PR body).
fn charge_usage(
    statics: &[UnitStatic],
    state: &State,
    i: usize,
    m: &SpellModifier,
) -> f64 {
    let us = &statics[state.roster.profile[i]];
    if us.melee.is_empty() {
        return 0.0;
    }
    let Some(e) = nearest_enemy(state, i) else { return 0.0; };
    if state.aircraft[e] {
        return 0.0;
    }
    let gap_in = geom::edge_gap_in(
        &state.positions[i],
        &state.radii[i],
        &state.positions[e],
        &state.radii[e],
        DEFAULT_BASE_RADIUS_M,
    )
    .max(0.0);
    let bands = &state.bands[i];
    let (_, rush_live) = live_bands_of(statics, state, i);
    let band = bands.charge.map_or(rush_live, |c| c + rush_live - bands.rush);
    if gap_in > crate::gate::melee_shroud_charge_in(band + m.rush_in, state, e) {
        return 0.0;
    }
    let mut sc = Scratch::default();
    melee_profiles_of(us, state.alive[i], &mut sc);
    let att = ctx_live(ctx_of(us, state, i), statics, state, i, true, CURRENT_RULES_EPOCH);
    let def = ctx_live(
        ctx_of(&statics[state.roster.profile[e]], state, e),
        statics, state, e, true, CURRENT_RULES_EPOCH,
    );
    let ev = melee_ev(&us.melee, &sc.attacks, &att, &def, true);
    if ev < FUTILE_CHARGE_EV {
        0.0
    } else {
        ev
    }
}

/// The advance-then-shoot leg: the shoot EV at (distance − advance band),
/// the planner's own pricing distance, every shooting reach widened by
/// the spell range. The range bonus stamps a CLONE of the profile list
/// (the immutable table stays shared); the ctxs read the unmodified
/// statics — no Ctx field carries a range.
fn shoot_usage_ev(
    statics: &[UnitStatic],
    state: &State,
    i: usize,
    m: &SpellModifier,
) -> f64 {
    let us = &statics[state.roster.profile[i]];
    if us.shoot.is_empty() {
        return 0.0;
    }
    let Some(e) = nearest_enemy(state, i) else { return 0.0; };
    let d = geom::dist_in(&state.positions[i], &state.positions[e]);
    let (advance_live, _) = live_bands_of(statics, state, i);
    let shoot_d = (d - (advance_live + m.advance_in)).max(0.0);
    let mut shoot = us.shoot.clone();
    for p in shoot.iter_mut() {
        p.range += m.range_in as i64;
    }
    // The `profiles_of` shape over the STAMPED list (its own gate reads the
    // immutable ranges, so a spell-widened profile must be picked here):
    // index-parallel keep/attacks, the once-per-game bonus group skipping
    // the survivor scaling.
    let mut keep = Vec::new();
    let mut attacks = Vec::new();
    for (pi, p) in shoot.iter().enumerate() {
        if (p.range as f64) < shoot_d {
            continue;
        }
        keep.push(pi);
        attacks.push(if p.extra_attack_q > 0 {
            p.attacks
        } else {
            effective_attacks(p.attacks, state.alive[i], us.model_count)
        });
    }
    if keep.is_empty() {
        return 0.0;
    }
    let att = ctx_live(ctx_of(us, state, i), statics, state, i, false, CURRENT_RULES_EPOCH);
    let def = ctx_live(
        ctx_of(&statics[state.roster.profile[e]], state, e),
        statics, state, e, false, CURRENT_RULES_EPOCH,
    );
    shoot_ev(&shoot, &keep, &attacks, &att, &def, shoot_d)
}
