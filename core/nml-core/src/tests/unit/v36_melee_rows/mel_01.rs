//! MEL-01 tests (rules 3.6, lane melee); empty until the row lands - start with `use super::super::*;`.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::sim::{melee_profiles_of, Scratch};

// MEL-01 (lead ruling D-ASSAULT): a weapon carrying Assault also strikes in melee from `EPOCH_73_V36`,
// with its own attacks, AP and rules; at 72 a ranged weapon never strikes.

/// Three models, each armed only with an Assault pistol (12", A2, AP(1)).
const PISTOLS: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "pistols":{"unit_id":"pistols","name":"Pistols","quality":4,
    "defense":4,"tough":1,"wounds_max":[1,1,1],"model_count":3,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Assault Pistol","range":12,"attacks":2,"count":3,"ap":1,
      "rules":["Assault","AP(1)"]}]}}}"#;

fn pistols_at(epoch: u32) -> UnitStatic {
    let header = read_act_header(PISTOLS).expect("header");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("pistols").expect("pistols"), epoch)
}

/// OLD leg: at 72 the pistol only shoots; the unit has nothing to strike with.
#[test]
fn an_assault_pistol_makes_no_melee_strike_at_epoch_72() {
    let us = pistols_at(EPOCH_72_PLAYTEST_RULES);
    assert!(us.melee.is_empty(), "72 keeps the old reading: a ranged weapon never strikes");
    let mut sc = Scratch::default();
    melee_profiles_of(&us, 3, &mut sc);
    assert!(sc.attacks.is_empty());
    assert_eq!(us.shoot.len(), 1);
}

/// NEW leg: at 73 the pistol strikes with its own attacks and AP, and still shoots.
#[test]
fn an_assault_pistol_strikes_in_melee_at_epoch_73() {
    let us = pistols_at(EPOCH_73_V36);
    assert_eq!(us.melee.len(), 1, "the Assault pistol's melee copy");
    let mut sc = Scratch::default();
    melee_profiles_of(&us, 3, &mut sc);
    assert_eq!(sc.attacks, vec![6], "2 attacks x 3 pistols, every model alive");
    assert_eq!(us.melee[0].ap, 1);
    assert_eq!((us.shoot.len(), us.shoot[0].range), (1, 12), "the ranged profile is untouched");
}

/// D-ASSAULT trap: the copy stays a melee profile (range 0) and carries the printed 12" apart, so a
/// half-range gate reads 6", never "over half of 0".
#[test]
fn the_melee_copy_keeps_its_printed_range_apart_at_epoch_73() {
    let us = pistols_at(EPOCH_73_V36);
    assert_eq!((us.melee[0].range, us.melee[0].printed_range), (0, 12));
    assert!(!facet_applies(false, true, us.melee[0].range), "a shooting-only facet stays off the copy");
}
