use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

// SHO-05 (rules 3.6): an Artillery shooter's +1 to hit needs a Hold and a target over 12". Under
// the older reading (epoch 72) any shot over 9" earned it. The shipped map's Artillery entry is
// the data under test, so these build the unit through the real registry at each epoch.

const ART_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":["Artillery"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

fn art_at(epoch: u32) -> crate::unit::UnitStatic {
    let parsed = crate::acts::read_act_header(ART_HEADER).expect("header parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    crate::unit::UnitStatic::build_for(&mut reg, parsed.profiles.get("carrier").expect("carrier"), epoch)
}

/// Hits of one eight-shot volley at Quality 4 against Defense 4; seed 17 rolls a 3, the one face
/// the Artillery +1 flips from miss to hit (fixture-guarded in each test).
fn hits(us: &crate::unit::UnitStatic, att: &Ctx, dist_in: f64) -> i64 {
    let p = [us.shoot[0].clone()];
    let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
    let mut tray = Tray::seeded(17);
    resolve_volley_with_tray(
        &[Shooter { profiles: &p, keep: &[0], attacks: &[8], att, owner: "" }],
        &def, "Target", dist_in, dist_in, true, true, true, true, &mut tray,
    )
    .rolls[1]
        .count
}

fn without_artillery(us: &crate::unit::UnitStatic) -> Ctx {
    Ctx { artillery: false, ..us.ctx }
}

#[test]
fn artillery_at_10in_keeps_the_plus_one_at_epoch_72() {
    assert!(Tray::seeded(17).roll(8).contains(&3), "fixture: seed 17 must roll a 3");
    let us = art_at(EPOCH_72_PLAYTEST_RULES);
    assert!(hits(&us, &us.ctx, 10.0) > hits(&us, &without_artillery(&us), 10.0), "older reading: any shot over 9\"");
}

#[test]
fn artillery_that_moved_gets_no_plus_one_at_10in_at_epoch_73() {
    assert!(Tray::seeded(17).roll(8).contains(&3), "fixture: seed 17 must roll a 3");
    let us = art_at(EPOCH_73_V36);
    let moved = Ctx { moved_this_round: true, ..us.ctx };
    assert_eq!(hits(&us, &moved, 10.0), hits(&us, &without_artillery(&us), 10.0), "RED on main: the +1 still pays at 10\"");
}

#[test]
fn artillery_that_moved_gets_no_plus_one_at_13in_at_epoch_73() {
    assert!(Tray::seeded(17).roll(8).contains(&3), "fixture: seed 17 must roll a 3");
    let us = art_at(EPOCH_73_V36);
    let moved = Ctx { moved_this_round: true, ..us.ctx };
    assert_eq!(hits(&us, &moved, 13.0), hits(&us, &without_artillery(&us), 13.0), "RED on main: a moved gun is paid at 13\"");
}

#[test]
fn artillery_that_held_gets_the_plus_one_at_13in_at_epoch_73() {
    assert!(Tray::seeded(17).roll(8).contains(&3), "fixture: seed 17 must roll a 3");
    let us = art_at(EPOCH_73_V36);
    let held = Ctx { held: true, ..us.ctx };
    assert!(hits(&us, &held, 13.0) > hits(&us, &without_artillery(&us), 13.0), "a held gun over 12\" earns the +1");
}

#[test]
fn artillery_that_held_gets_no_plus_one_at_10in_at_epoch_73() {
    assert!(Tray::seeded(17).roll(8).contains(&3), "fixture: seed 17 must roll a 3");
    let us = art_at(EPOCH_73_V36);
    let held = Ctx { held: true, ..us.ctx };
    assert_eq!(hits(&us, &held, 10.0), hits(&us, &without_artillery(&us), 10.0), "held is not enough inside 12\"");
}

#[test]
fn artillery_that_held_keeps_the_plus_one_at_10in_at_epoch_72() {
    assert!(Tray::seeded(17).roll(8).contains(&3), "fixture: seed 17 must roll a 3");
    let us = art_at(EPOCH_72_PLAYTEST_RULES);
    let held = Ctx { held: true, ..us.ctx };
    assert!(hits(&us, &held, 10.0) > hits(&us, &without_artillery(&us), 10.0), "older reading: any shot over 9\"");
}
