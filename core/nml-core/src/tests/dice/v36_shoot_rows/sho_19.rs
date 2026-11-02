//! SHO-19 tests (rules 3.6, lane shoot): the charge-gated Versatile families need over 6"
//! charging at `EPOCH_73_V36` and Versatile Expert carries no distance gate. Below
//! `EPOCH_73_V36` the old reads stay pinned.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

const SHO_19_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "havoc":{"unit_id":"havoc","name":"Havocbound","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"havoc_brothers","special_rules":["Havocbound"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":20,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":20,"count":1,"ap":0,"rules":[]}]},
  "watch":{"unit_id":"watch","name":"Watchborn","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"watch_brothers","special_rules":["Watchborn"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":20,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":20,"count":1,"ap":0,"rules":[]}]},
  "expert":{"unit_id":"expert","name":"Expert","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"watch_brothers","special_rules":["Versatile Expert"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":20,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":20,"count":1,"ap":0,"rules":[]}]},
  "plain":{"unit_id":"plain","name":"Plain","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"war_disciples","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":20,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":20,"count":1,"ap":0,"rules":[]}]}}}"#;

fn sho19_static(id: &str, epoch: u32) -> UnitStatic {
    let header = read_act_header(SHO_19_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get(id).expect(id);
    UnitStatic::build_for(&mut reg, p, epoch)
}

fn save_target(r: &ShootResult) -> i64 {
    r.rolls.iter().find(|x| x.kind == "defense").map(|x| x.target).unwrap_or(-1)
}

fn charge(id: &str, epoch: u32, gap_in: f64, seed: i64) -> ShootResult {
    let us = sho19_static(id, epoch);
    let p = [us.melee[0].clone()];
    let att = Ctx { versatile_latched: true, versatile_pick_ap: 1, ..us.ctx };
    resolve_melee_leg(
        &[striker(&p, &[0], &[20], &att)],
        &defender(4, 5),
        "Target",
        true,
        true,
        true,
        false,
        gap_in,
        false,
        true,
        true,
        false,
        false,
        &mut Tray::seeded(seed),
    )
}

fn volley(id: &str, epoch: u32, d_in: f64, seed: i64) -> ShootResult {
    let us = sho19_static(id, epoch);
    let p = [us.shoot[0].clone()];
    let att = Ctx { versatile_latched: true, versatile_pick_ap: 1, ..us.ctx };
    resolve_volley_with_tray(
        &[striker(&p, &[0], &[20], &att)],
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

/// RED on main: Havocbound's charge AP fires from 4" at 73; it needs over 6".
#[test]
fn havocbound_charge_pays_ap_from_over_six_inches_at_epoch_73() {
    assert_eq!(save_target(&charge("havoc", EPOCH_73_V36, 7.0, 2)), 5, "7\" clears the 6\" gate");
    assert_eq!(save_target(&charge("havoc", EPOCH_73_V36, 4.0, 2)), 4, "4\" stays inside the gate");
}

/// The old side: below 73 Havocbound's charge leg is unconditional.
#[test]
fn below_epoch_73_havocbound_charge_pays_ap_at_four_inches() {
    assert_eq!(save_target(&charge("havoc", EPOCH_72_PLAYTEST_RULES, 4.0, 2)), 5);
}

/// RED on main: Watchborn's charge pick needs over 6" at 73 and over 9" at 72.
#[test]
fn watchborn_charge_needs_over_six_inches_at_epoch_73_and_over_nine_below() {
    assert_eq!(save_target(&charge("watch", EPOCH_73_V36, 7.0, 2)), 5, "7\" clears the 6\" gate");
    assert_eq!(save_target(&charge("watch", EPOCH_73_V36, 5.0, 2)), 4, "5\" stays inside the gate");
    assert_eq!(save_target(&charge("watch", EPOCH_72_PLAYTEST_RULES, 7.0, 2)), 4, "the old 9\" gate");
}

/// RED on main: Versatile Expert resolves and fires at any distance at 73; 72 keeps the old gate.
#[test]
fn versatile_expert_works_at_any_distance_at_epoch_73_only() {
    assert_eq!(save_target(&volley("expert", EPOCH_73_V36, 5.0, 2)), 5, "5\" shot, no gate");
    assert_eq!(save_target(&charge("expert", EPOCH_73_V36, 3.0, 2)), 5, "3\" charge, no gate");
    assert_eq!(save_target(&volley("expert", EPOCH_72_PLAYTEST_RULES, 5.0, 2)), 4, "72 keeps the old gate");
}

/// The base form still needs over 9" shooting at 73; the Expert spelling is the only bypass.
#[test]
fn watchborn_still_needs_over_nine_inches_shooting_at_epoch_73() {
    assert_eq!(save_target(&volley("watch", EPOCH_73_V36, 10.0, 2)), 5, "10\" clears the 9\" gate");
    assert_eq!(save_target(&volley("watch", EPOCH_73_V36, 5.0, 2)), 4, "5\" stays inside the gate");
}

/// The data half: the shipped maps resolve the new names instead of printing "apply manually".
#[test]
fn the_shipped_maps_resolve_versatile_expert_and_warrior() {
    let mut reg = Registries::new(&repo_root());
    for system in ["gf", "aof"] {
        assert!(reg.rules_for(system).has_primitive("", "Versatile Expert"), "{system} lacks Versatile Expert");
        assert!(reg.rules_for(system).has_primitive("", "Versatile Warrior"), "{system} lacks Versatile Warrior");
    }
}
