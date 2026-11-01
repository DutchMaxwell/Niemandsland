use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::combat::profile_ev;

// SHO-06e (rules 3.6): the AI's shooting ESTIMATE prices Artillery the way the resolver does at
// EPOCH_73_V36 — the shooter's +1 needs a Hold and a target past 12", the target's -1 needs most
// models carrying the rule and no move this round, and both only past 12". At epoch 72 the estimate
// keeps the old over-9" numbers (+1 shooter, -2 target). The shipped map's Artillery entry is the
// data under test, so the fixtures build the unit through the real registry at each epoch.

const GUN: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "gun":{"unit_id":"gun","name":"Gun","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":2,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":["Artillery"],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

/// The Artillery unit's estimate context at `epoch`: `artillery` plus both SHO-05/SHO-06 map legs.
fn gun_at(epoch: u32) -> Ctx {
    let parsed = read_act_header(GUN).expect("header parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, parsed.profiles.get("gun").expect("gun"), epoch).ctx
}

fn rifle() -> ShootProfile {
    ShootProfile { name: "Rifle".into(), attacks: 10, count: 1, range: 24, ..Default::default() }
}

/// A Quality-4 shooter with no rules of its own.
fn plain(epoch: u32) -> Ctx {
    Ctx { quality: 4, models: 5, rules_epoch: epoch, ..Default::default() }
}

/// 10 Quality-4 attacks into Defense 4+.
const FREE: f64 = 2.5;
/// -1 to hit (5+): 10 x 2/6 hits, half saved.
const ONE_MINUS: f64 = 10.0 / 3.0 * 0.5;
/// -2 to hit (6+): 10 x 1/6 hits, half saved.
const TWO_MINUS: f64 = 10.0 / 6.0 * 0.5;
/// +1 to hit (3+): 10 x 4/6 hits, half saved.
const PLUS_ONE: f64 = 10.0 * 4.0 / 6.0 * 0.5;

fn ev(att: &Ctx, def: &Ctx, dist_in: f64) -> f64 {
    profile_ev(&rifle(), 10, att, def, dist_in, false)
}

#[test]
fn an_unmoved_artillery_target_over_12in_is_priced_minus_one_at_epoch_73() {
    // RED on main: the estimate still charges the old -2 here.
    let def = gun_at(EPOCH_73_V36);
    let got = ev(&plain(EPOCH_73_V36), &def, 13.0);
    assert!((got - ONE_MINUS).abs() < 1e-9, "13\": one minus, not the old -2 (got {got})");
}

#[test]
fn an_artillery_target_that_moved_over_12in_is_priced_free_at_epoch_73() {
    let def = Ctx { moved_round: 3, round: 3, ..gun_at(EPOCH_73_V36) };
    let got = ev(&plain(EPOCH_73_V36), &def, 13.0);
    assert!((got - FREE).abs() < 1e-9, "a move takes the target -1 away (got {got})");
}

#[test]
fn an_unmoved_artillery_target_under_12in_is_priced_free_at_epoch_73() {
    let def = gun_at(EPOCH_73_V36);
    let got = ev(&plain(EPOCH_73_V36), &def, 10.0);
    assert!((got - FREE).abs() < 1e-9, "inside 12\" the target -1 is off (got {got})");
}

#[test]
fn an_artillery_shooter_that_held_over_12in_earns_the_plus_one_at_epoch_73() {
    let att = Ctx { held: true, ..gun_at(EPOCH_73_V36) };
    let got = ev(&att, &defender(4, 5), 13.0);
    assert!((got - PLUS_ONE).abs() < 1e-9, "a held gun over 12\" earns the +1 (got {got})");
}

#[test]
fn an_artillery_shooter_that_moved_over_12in_earns_no_plus_one_at_epoch_73() {
    // RED on main: the estimate still pays the +1 without a Hold.
    let att = Ctx { held: false, ..gun_at(EPOCH_73_V36) };
    let got = ev(&att, &defender(4, 5), 13.0);
    assert!((got - FREE).abs() < 1e-9, "a moved gun earns no +1 (got {got})");
}

#[test]
fn the_old_numbers_stay_byte_identical_at_epoch_72() {
    // The target keeps the old over-9" -2 whether or not it moved ...
    let target = Ctx { moved_round: 3, round: 3, ..gun_at(EPOCH_72_PLAYTEST_RULES) };
    let got = ev(&plain(EPOCH_72_PLAYTEST_RULES), &target, 13.0);
    assert!((got - TWO_MINUS).abs() < 1e-9, "72: the old target -2 (got {got})");
    // ... and the shooter keeps the old over-9" +1 whether or not it held.
    let moved = Ctx { held: false, ..gun_at(EPOCH_72_PLAYTEST_RULES) };
    let got = ev(&moved, &defender(4, 5), 13.0);
    assert!((got - PLUS_ONE).abs() < 1e-9, "72: the old shooter +1 (got {got})");
}
