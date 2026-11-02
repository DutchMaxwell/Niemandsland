//! SHO-19-fix tests (rules 3.6, lane shoot): only Versatile Expert skips the pick's
//! distance condition; Versatile Warrior keeps the 9" shot / 6" charge gate.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

const SHO_19FIX_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "warrior":{"unit_id":"warrior","name":"Warrior","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"watch_brothers","special_rules":["Versatile Warrior"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":20,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":20,"count":1,"ap":0,"rules":[]}]},
  "expert":{"unit_id":"expert","name":"Expert","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"watch_brothers","special_rules":["Versatile Expert"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":20,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":20,"count":1,"ap":0,"rules":[]}]}}}"#;

fn sho19fix_static(id: &str, epoch: u32) -> UnitStatic {
    let header = read_act_header(SHO_19FIX_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get(id).expect(id);
    UnitStatic::build_for(&mut reg, p, epoch)
}

/// True when the Versatile pick changes the estimate, i.e. the distance gate let it through.
fn pick_applied(id: &str, epoch: u32, melee: bool, dist_in: f64) -> bool {
    let us = sho19fix_static(id, epoch);
    let base = if melee { us.melee[0].clone() } else { us.shoot[0].clone() };
    let mut without = base.clone();
    without.versatile_attack = false;
    let def = Ctx { defense: 4, models: 5, tough: 1, ..Default::default() };
    let ev = |p: &ShootProfile| crate::combat::profile_ev(p, 20, &us.ctx, &def, dist_in, melee);
    (ev(&base) - ev(&without)).abs() > 1e-12
}

/// RED on main: the Warrior spelling is wrongly ungated, so a 6" shot still picks.
#[test]
fn warrior_gets_no_pick_inside_the_shooting_band_at_epoch_73() {
    assert!(!pick_applied("warrior", EPOCH_73_V36, false, 6.0), "6\" stays inside the 9\" gate");
    assert!(pick_applied("warrior", EPOCH_73_V36, false, 10.0), "10\" clears the 9\" gate");
}

/// RED on main: the Warrior spelling is wrongly ungated, so a 3" charge still picks.
#[test]
fn warrior_gets_no_pick_inside_the_charge_band_at_epoch_73() {
    assert!(!pick_applied("warrior", EPOCH_73_V36, true, 3.0), "3\" stays inside the 6\" gate");
    assert!(pick_applied("warrior", EPOCH_73_V36, true, 7.0), "7\" clears the 6\" gate");
}

/// The Expert spelling keeps the ungated pick at any distance.
#[test]
fn expert_keeps_the_ungated_pick_at_epoch_73() {
    assert!(pick_applied("expert", EPOCH_73_V36, false, 5.0), "5\" shot, no gate");
    assert!(pick_applied("expert", EPOCH_73_V36, true, 3.0), "3\" charge, no gate");
}

/// The pin: below 73 both spellings keep the old distance gates.
#[test]
fn below_epoch_73_the_old_distance_gates_return() {
    assert!(!pick_applied("warrior", EPOCH_72_PLAYTEST_RULES, false, 6.0), "72 keeps the 9\" shot gate");
    assert!(!pick_applied("warrior", EPOCH_72_PLAYTEST_RULES, true, 5.0), "72 keeps the 9\" charge gate");
    assert!(!pick_applied("expert", EPOCH_72_PLAYTEST_RULES, false, 5.0), "72 keeps the Expert gate");
}
