//! AIG-G2 row R3 tests (rules 3.6): a Crossing Strike weapon never strikes as plain melee.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

// The weapon attacks only when its bearer moves through an enemy unit (the move-through set), so the
// melee list must not carry it. A plain range-0 weapon on the same unit keeps striking (the control).

/// One model armed with Drop Bombs (range 0, Crossing Strike) and a plain Gondola Crew melee weapon.
const ZEPPELIN: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "zeppelin":{"unit_id":"zeppelin","name":"Zeppelins","quality":4,
    "defense":4,"tough":6,"wounds_max":[6],"model_count":1,"caster_value":0,
    "base_radius":0.05,"game_system":"aof","faction_folder":"sky_city_dwarves",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Drop Bombs","range":0,"attacks":6,"count":1,"ap":1,"rules":["Crossing Strike"]},
               {"name":"Gondola Crew","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

fn zeppelin_at(epoch: u32) -> UnitStatic {
    let header = read_act_header(ZEPPELIN).expect("header");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("zeppelin").expect("zeppelin"), epoch)
}

fn range0(name: &str, rule: &str) -> Weapon {
    Weapon { name: name.into(), range: 0.0, attacks: 6, count: 1, ap: 1, rules: vec![rule.into()] }
}

fn melee_names(us: &UnitStatic) -> Vec<&str> {
    us.melee.iter().map(|p| p.name.as_str()).collect()
}

#[test]
fn a_crossing_strike_weapon_makes_no_melee_strike_at_epoch_73() {
    let us = zeppelin_at(EPOCH_73_V36);
    assert_eq!(melee_names(&us), vec!["Gondola Crew"], "Drop Bombs struck as plain melee");
    let moving: Vec<&str> = us.strafe_shoot.iter().map(|p| p.name.as_str()).collect();
    assert_eq!(moving, vec!["Drop Bombs"], "the weapon stays in the move-through set");
}

#[test]
fn the_bare_weapon_list_yields_no_melee_profile_at_epoch_73() {
    assert!(crate::unit::melee_profiles_at(&[range0("Drop Bombs", "Crossing Strike")], EPOCH_73_V36).is_empty());
    assert!(crate::unit::melee_profiles_at(&[range0("Drop Bombs", "Strafing")], EPOCH_73_V36).is_empty(), "the 3.5 name too");
}

/// Below the gate the old reading replays byte for byte: the weapon still strikes.
#[test]
fn a_crossing_strike_weapon_still_strikes_at_epoch_72() {
    let us = zeppelin_at(EPOCH_72_PLAYTEST_RULES);
    assert_eq!(melee_names(&us), vec!["Drop Bombs", "Gondola Crew"]);
    assert_eq!(crate::unit::melee_profiles_at(&[range0("Drop Bombs", "Crossing Strike")], EPOCH_72_PLAYTEST_RULES).len(), 1);
}

/// Control: a plain range-0 weapon is untouched at the new epoch.
#[test]
fn a_plain_range_zero_weapon_still_strikes_at_epoch_73() {
    let plain = Weapon { name: "Blade".into(), range: 0.0, attacks: 2, count: 1, ap: 0, rules: vec![] };
    assert_eq!(crate::unit::melee_profiles_at(&[plain], EPOCH_73_V36).len(), 1);
}

// S6 (#2612, EPOCH_75_TABLE_FIXES): the move-through volley is a shooting attack, so a unit-level Shred-family
// rule stamps its profiles; a range-0 weapon (Drop Bombs) reads the facet with reach max(range, 1).
fn strafer_with(rule: &str, epoch: u32) -> UnitStatic {
    let src = ZEPPELIN.replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"))
        .replace("{\"name\":\"Drop Bombs\"", "{\"name\":\"Strafe Gun\",\"range\":24,\"attacks\":4,\"count\":1,\"ap\":0,\"rules\":[\"Crossing Strike\"]},\n               {\"name\":\"Drop Bombs\"");
    let header = read_act_header(&src).expect("header");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("zeppelin").expect("zeppelin"), epoch)
}

#[test]
fn a_crossing_strike_volley_shreds_like_a_shooting_attack_from_epoch_75() {
    let us = strafer_with("Shred when Shooting", crate::acts::EPOCH_75_TABLE_FIXES);
    assert_eq!(us.strafe_shoot.len(), 2, "ranged and range-0 Crossing Strike weapons");
    assert!(us.strafe_shoot.iter().all(|p| p.shred_alias), "a strafe profile lacks the Shred stamp");
    // The melee-only facet never stamps a shooting volley; a rule-free unit never does.
    assert!(!strafer_with("Shred in Melee", crate::acts::EPOCH_75_TABLE_FIXES).strafe_shoot.iter().any(|p| p.shred_alias));
    assert!(!strafer_with("Fast", crate::acts::EPOCH_75_TABLE_FIXES).strafe_shoot.iter().any(|p| p.shred_alias));
}

#[test]
fn a_crossing_strike_volley_stays_unstamped_at_epoch_74() {
    let us = strafer_with("Shred when Shooting", crate::acts::EPOCH_75_TABLE_FIXES - 1);
    assert_eq!(us.strafe_shoot.len(), 2);
    assert!(!us.strafe_shoot.iter().any(|p| p.shred_alias), "epoch 74 must keep the raw array");
}
