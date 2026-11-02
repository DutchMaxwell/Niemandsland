//! SHO-19b tests (rules 3.6, lane shoot): an Enhanced Watchborn token/carrier skips the
//! 9"/6" gate at `EPOCH_73_V36`; below the epoch the old reads stay pinned.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

const SHO_19B_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "watch":{"unit_id":"watch","name":"Watchborn","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"watch_brothers","special_rules":["Watchborn"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":20,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":20,"count":1,"ap":0,"rules":[]}]},
  "enhanced":{"unit_id":"enhanced","name":"Enhanced Watchborn","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"watch_brothers",
    "special_rules":["Watchborn","Enhanced Watchborn"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":20,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":20,"count":1,"ap":0,"rules":[]}]}}}"#;

fn sho19b_static(id: &str, epoch: u32) -> UnitStatic {
    let header = read_act_header(SHO_19B_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get(id).expect(id);
    UnitStatic::build_for(&mut reg, p, epoch)
}

fn save_target(r: &ShootResult) -> i64 {
    r.rolls.iter().find(|x| x.kind == "defense").map(|x| x.target).unwrap_or(-1)
}

fn charge(id: &str, epoch: u32, gap_in: f64, seed: i64) -> ShootResult {
    let us = sho19b_static(id, epoch);
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
    let us = sho19b_static(id, epoch);
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

/// RED on main: Enhanced Watchborn skips the 9"/6" gate at 73; 72 keeps the old answers.
#[test]
fn enhanced_watchborn_skips_the_gate_at_epoch_73_only() {
    assert_eq!(save_target(&volley("enhanced", EPOCH_73_V36, 5.0, 2)), 5, "5\" shot, no gate");
    assert_eq!(save_target(&charge("enhanced", EPOCH_73_V36, 3.0, 2)), 5, "3\" charge, no gate");
    assert_eq!(save_target(&volley("enhanced", EPOCH_72_PLAYTEST_RULES, 5.0, 2)), 4, "72 keeps the old gate");
}

/// The base form still needs over 9" shooting at 73: the Enhanced bypass is not a family-wide one.
#[test]
fn watchborn_still_needs_over_nine_inches_shooting_at_epoch_73() {
    assert_eq!(save_target(&volley("watch", EPOCH_73_V36, 10.0, 2)), 5, "10\" clears the 9\" gate");
    assert_eq!(save_target(&volley("watch", EPOCH_73_V36, 5.0, 2)), 4, "5\" stays inside the gate");
}

/// The data half: the shipped map resolves the new name instead of printing "apply manually".
#[test]
fn the_shipped_maps_resolve_enhanced_watchborn() {
    let mut reg = Registries::new(&repo_root());
    for faction in ["watch_brothers", "watch_prime_brothers"] {
        assert!(reg.rules_for("gf").has_primitive(faction, "Enhanced Watchborn"), "gf lacks {faction}");
    }
}
