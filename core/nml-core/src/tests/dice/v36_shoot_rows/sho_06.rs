use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

// SHO-06 (rules 3.6): a shot at an Artillery unit takes -1 to hit only past 12", only while most
// models carry the rule and the unit has NOT moved this round. Below epoch 73 the old -2 / 9"
// reading stays byte-exact. The shipped map's Artillery entry is the data under test.

const SHOOTER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "shooter":{"unit_id":"shooter","name":"Shooter","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":[],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

const GUN: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "gun":{"unit_id":"gun","name":"Gun","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":["Artillery"],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

fn static_of(text: &str, id: &str, epoch: u32) -> UnitStatic {
    let parsed = read_act_header(text).expect("header parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, parsed.profiles.get(id).expect(id), epoch)
}

/// An Artillery target with `models` host models and the given `attached_hero_rules` list.
fn gun(epoch: u32, models: i64, heroes: &str) -> UnitStatic {
    let text = GUN
        .replace("\"model_count\":1", &format!("\"model_count\":{models}"))
        .replace("\"attached_hero_rules\":[]", &format!("\"attached_hero_rules\":{heroes}"));
    static_of(&text, "gun", epoch)
}

fn shooter(epoch: u32) -> UnitStatic {
    static_of(SHOOTER, "shooter", epoch)
}

/// One eight-shot Quality-4 volley at `dist_in`; `rolls[0].target` is the to-hit number.
fn volley(shooter_us: &UnitStatic, def: &Ctx, dist_in: f64) -> ShootResult {
    let p = [shooter_us.shoot[0].clone()];
    let mut tray = Tray::seeded(17);
    resolve_volley_with_tray(
        &[Shooter { profiles: &p, keep: &[0], attacks: &[8], att: &shooter_us.ctx, owner: "Shooter" }],
        def, "Gun", dist_in, dist_in, true, true, true, true, &mut tray,
    )
}

#[test]
fn an_unmoved_artillery_target_at_13in_takes_minus_one_at_epoch_73() {
    let def = gun(EPOCH_73_V36, 1, "[]").ctx;
    let out = volley(&shooter(EPOCH_73_V36), &def, 13.0);
    assert_eq!(out.rolls[0].target, 5, "Quality 4 + the -1: {:?}", out.log);
    assert!(
        out.log.iter().any(|l| l.contains("Artillery") && l.contains("12")),
        "the applied penalty names Artillery and the 12\" gate: {:?}",
        out.log
    );
}

#[test]
fn an_unmoved_artillery_target_at_10in_takes_nothing_at_epoch_73() {
    let def = gun(EPOCH_73_V36, 1, "[]").ctx;
    let out = volley(&shooter(EPOCH_73_V36), &def, 10.0);
    assert_eq!(out.rolls[0].target, 4, "inside 12\" the penalty is off: {:?}", out.log);
}

#[test]
fn an_artillery_target_that_moved_takes_nothing_at_13in_at_epoch_73() {
    let us = gun(EPOCH_73_V36, 1, "[]");
    let def = Ctx { moved_round: 3, round: 3, ..us.ctx };
    let out = volley(&shooter(EPOCH_73_V36), &def, 13.0);
    assert_eq!(out.rolls[0].target, 4, "a move takes the protection away: {:?}", out.log);
}

#[test]
fn an_artillery_target_that_moved_takes_nothing_at_10in_at_epoch_73() {
    let us = gun(EPOCH_73_V36, 1, "[]");
    let def = Ctx { moved_round: 3, round: 3, ..us.ctx };
    let out = volley(&shooter(EPOCH_73_V36), &def, 10.0);
    assert_eq!(out.rolls[0].target, 4, "moved and inside 12\": nothing: {:?}", out.log);
}

#[test]
fn an_exact_half_carrying_artillery_is_off_at_epoch_73() {
    let def = gun(EPOCH_73_V36, 1, r#"[["Rifle"]]"#).ctx;
    let out = volley(&shooter(EPOCH_73_V36), &def, 13.0);
    assert_eq!(out.rolls[0].target, 4, "one host + one hero is an exact half: off");
}

#[test]
fn most_models_carrying_artillery_keep_minus_one_at_epoch_73() {
    let def = gun(EPOCH_73_V36, 2, r#"[["Rifle"]]"#).ctx;
    let out = volley(&shooter(EPOCH_73_V36), &def, 13.0);
    assert_eq!(out.rolls[0].target, 5, "two host models + one hero is a strict majority");
}

#[test]
fn a_moved_artillery_target_keeps_the_old_minus_two_at_13in_at_epoch_72() {
    let us = gun(EPOCH_72_PLAYTEST_RULES, 1, "[]");
    let def = Ctx { moved_round: 3, round: 3, ..us.ctx };
    let out = volley(&shooter(EPOCH_72_PLAYTEST_RULES), &def, 13.0);
    assert_eq!(out.rolls[0].target, 6, "the old over-9\" leg: -2");
}

#[test]
fn an_artillery_target_at_10in_keeps_the_old_minus_two_at_epoch_72() {
    let def = gun(EPOCH_72_PLAYTEST_RULES, 1, "[]").ctx;
    let out = volley(&shooter(EPOCH_72_PLAYTEST_RULES), &def, 10.0);
    assert_eq!(out.rolls[0].target, 6, "the old leg still starts beyond 9\"");
}
