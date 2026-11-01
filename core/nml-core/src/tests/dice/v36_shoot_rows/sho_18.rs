//! SHO-18 tests (rules 3.6, lane shoot): the offensive Surge/Shred alias families (Brutal,
//! Violent, Warbound, Ferocious and their siblings) fire only from a shot over 9". Below
//! `EPOCH_73_V36` the old unconditional read stays.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// The real books the registry resolves the two families through: Warbound is a gf
/// war_disciples Shred alias, Ferocious an aof orcs Surge alias. The Rifles are 8 attacks.
const SHO_18_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "warbound":{"unit_id":"warbound","name":"Warbound","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"war_disciples","special_rules":["Warbound"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}]},
  "ferocious":{"unit_id":"ferocious","name":"Ferocious","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"aof","faction_folder":"orcs","special_rules":["Ferocious"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},
      {"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]},
  "plain":{"unit_id":"plain","name":"Plain","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"war_disciples","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

fn sho18_static(id: &str, epoch: u32) -> UnitStatic {
    let header = read_act_header(SHO_18_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get(id).expect(id);
    UnitStatic::build_for(&mut reg, p, epoch)
}

fn one_rifle_volley(id: &str, epoch: u32, d_in: f64, seed: i64) -> ShootResult {
    let us = sho18_static(id, epoch);
    let p = [us.shoot[0].clone()];
    resolve_volley_with_tray(
        &[striker(&p, &[0], &[8], &us.ctx)],
        &defender(4, 5),
        "Target",
        d_in,
        d_in,
        true,
        true,
        true,
        true,
        &mut Tray::seeded(seed),
    )
}

/// RED on main: a Warbound shot from 10" fires its Shred at rules 3.6 while a 7" shot does
/// not; the non-carrier is the control on the same dice.
#[test]
fn warbound_shreds_on_a_ten_inch_shot_and_not_on_a_seven_inch_shot_at_epoch_73() {
    let ten = one_rifle_volley("warbound", EPOCH_73_V36, 10.0, 2);
    let seven = one_rifle_volley("warbound", EPOCH_73_V36, 7.0, 2);
    let plain_ten = one_rifle_volley("plain", EPOCH_73_V36, 10.0, 2);
    let plain_seven = one_rifle_volley("plain", EPOCH_73_V36, 7.0, 2);
    assert!(ten.wounds > plain_ten.wounds,
        "10\" pays the Shred, the plain unit does not ({ten:?} vs {plain_ten:?})");
    assert_eq!(seven.wounds, plain_seven.wounds,
        "inside the gate the family is silent, the plain unit's wounds");
}

/// The old side: below 73 the Warbound shot shreds at 7" too.
#[test]
fn below_epoch_73_a_warbound_shot_shreds_at_seven_inches_too() {
    let seven = one_rifle_volley("warbound", EPOCH_72_PLAYTEST_RULES, 7.0, 2);
    let plain = one_rifle_volley("plain", EPOCH_72_PLAYTEST_RULES, 7.0, 2);
    assert!(seven.wounds > plain.wounds,
        "below 73 the old unconditional read fires at 7\" ({seven:?} vs {plain:?})");
}

/// RED on main: a Ferocious shot from 10" fires at 73 while a 7" shot does not.
#[test]
fn ferocious_fires_on_a_ten_inch_shot_and_not_on_a_seven_inch_shot_at_epoch_73() {
    let ten = one_rifle_volley("ferocious", EPOCH_73_V36, 10.0, 9);
    let seven = one_rifle_volley("ferocious", EPOCH_73_V36, 7.0, 9);
    assert!(ten.rolls[1].count > seven.rolls[1].count,
        "10\" pays the sixes, 7\" does not ({ten:?} vs {seven:?})");
}

/// The old side: below 73 the same 7" shot pays its sixes.
#[test]
fn below_epoch_73_a_ferocious_shot_pays_its_sixes_at_seven_inches() {
    let ten = one_rifle_volley("ferocious", EPOCH_72_PLAYTEST_RULES, 10.0, 9);
    let seven = one_rifle_volley("ferocious", EPOCH_72_PLAYTEST_RULES, 7.0, 9);
    assert_eq!(ten.rolls[1].count, seven.rolls[1].count,
        "below 73 the alias is unconditional");
}

/// Rules-must-log: the applied gate names the rule and its band.
#[test]
fn the_applied_alias_gates_name_the_rule_and_their_bands() {
    let shot = one_rifle_volley("ferocious", EPOCH_73_V36, 10.0, 9);
    assert!(shot.log.iter().any(|l| l.contains("Ferocious") && l.contains("over 9")),
        "the shot gate names Ferocious and the 9\" band: {:?}", shot.log);
    let shred = one_rifle_volley("warbound", EPOCH_73_V36, 10.0, 2);
    assert!(shred.log.iter().any(|l| l.contains("Warbound") && l.contains("over 9")),
        "the Shot Shred gate names Warbound and the 9\" band: {:?}", shred.log);
}
