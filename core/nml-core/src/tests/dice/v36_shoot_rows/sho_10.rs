use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

// SHO-10 (rules 3.6): the save re-roll window is data now. A re-roll entry may name the target
// condition that opens it (the SAME test the conditional-AP leg runs). No shipped entry spells
// the new optional params, so these build a probe registry with one conditioned Boost per
// spelling; at epoch 72 the condition is ignored (the old unconditional window), at 73 it opens
// or shuts the whole re-roll.

const PROBE_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "goblin":{"unit_id":"goblin","name":"Goblin","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"goblins",
    "special_rules":["Mischievous","Enhanced Mischievous"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}]},
  "beastman":{"unit_id":"beastman","name":"Beastman","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"beastmen",
    "special_rules":["Bestial","Enhanced Bestial"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

fn probe_root(tag: &str) -> String {
    let dir = std::env::temp_dir().join(format!("nml_sho10_{}_{}", tag, std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let map_dir = dir.join("assets/solo");
    std::fs::create_dir_all(&map_dir).expect("temp map dir");
    let body = r#"{"common":{},"factions":{
      "goblins":{"Mischievous":{"primitive":"Bane","rated":false,"book_version":"3.6.0","params":{"reroll_save_sixes":true}},
        "Enhanced Mischievous":{"primitive":"Bane","rated":false,"book_version":"3.6.0","params":{"condition":"def_5_6","over_in":9.0,"reroll_save_low":5,"upgrades":"Mischievous"}}},
      "beastmen":{"Bestial":{"primitive":"Bane","rated":false,"book_version":"3.6.0","params":{"reroll_save_sixes":true}},
        "Enhanced Bestial":{"primitive":"Bane","rated":false,"book_version":"3.6.0","params":{"condition":"over_half_range","over_in":9.0,"reroll_save_low":5,"upgrades":"Bestial"}}}}}"#;
    std::fs::write(map_dir.join("rules_mechanics_aof.json"), body).expect("write temp map");
    dir.to_string_lossy().into_owned()
}

fn probe_unit(root: &str, id: &str, epoch: u32) -> crate::unit::UnitStatic {
    let header = crate::acts::read_act_header(PROBE_HEADER).expect("header");
    let mut reg = crate::rules::Registries::new(root);
    crate::unit::UnitStatic::build_for(&mut reg, header.profiles.get(id).expect(id), epoch)
}

fn volley_of(
    us: &crate::unit::UnitStatic,
    p: &ShootProfile,
    defense: i64,
    dist: f64,
    seed: i64,
) -> ShootResult {
    let def = Ctx { defense, models: 1, tough: 1, ..Default::default() };
    let mut tray = Tray::seeded(seed);
    resolve_volley_with_tray(
        &[Shooter { profiles: std::slice::from_ref(p), keep: &[0], attacks: &[8], att: &us.ctx, owner: "" }],
        &def, "Target", dist, dist, true, true, true, true, &mut tray,
    )
}

fn without_bane(us: &crate::unit::UnitStatic) -> ShootProfile {
    let mut p = us.shoot[0].clone();
    p.bane = false;
    p.bane_low = 0;
    p
}

const SEED: i64 = 3;

#[test]
fn a_def_5_6_window_stays_shut_against_a_defense_3_target_at_epoch_73() {
    let root = probe_root("def56_shut");
    let old = probe_unit(&root, "goblin", EPOCH_72_PLAYTEST_RULES);
    let old_on = volley_of(&old, &old.shoot[0], 3, 12.0, SEED);
    let old_off = volley_of(&old, &without_bane(&old), 3, 12.0, SEED);
    assert_ne!(old_on.rolls, old_off.rolls, "fixture: seed {SEED} must land a re-rollable save");
    let us = probe_unit(&root, "goblin", EPOCH_73_V36);
    let bare = without_bane(&us);
    let on = volley_of(&us, &us.shoot[0], 3, 12.0, SEED);
    let off = volley_of(&us, &bare, 3, 12.0, SEED);
    assert_eq!(on.rolls, off.rolls, "RED on main: the conditioned window re-rolls at Defense 3");
}

#[test]
fn the_def_5_6_window_opens_against_a_defense_5_target_at_epoch_73() {
    let root = probe_root("def56_open");
    let us = probe_unit(&root, "goblin", EPOCH_73_V36);
    let bare = without_bane(&us);
    let on = volley_of(&us, &us.shoot[0], 5, 12.0, SEED);
    let off = volley_of(&us, &bare, 5, 12.0, SEED);
    assert_ne!(on.rolls, off.rolls, "Defense 5 opens the window");
}

#[test]
fn the_same_entry_stays_unconditional_at_epoch_72() {
    let root = probe_root("def56_72");
    let us = probe_unit(&root, "goblin", EPOCH_72_PLAYTEST_RULES);
    let bare = without_bane(&us);
    let on = volley_of(&us, &us.shoot[0], 3, 12.0, SEED);
    let off = volley_of(&us, &bare, 3, 12.0, SEED);
    assert_ne!(on.rolls, off.rolls, "epoch 72 ignores the condition: the old window re-rolls");
}

#[test]
fn an_over_half_range_window_needs_the_range_condition_at_epoch_73() {
    let root = probe_root("half_range");
    let old = probe_unit(&root, "beastman", EPOCH_72_PLAYTEST_RULES);
    let old_on = volley_of(&old, &old.shoot[0], 4, 10.0, SEED);
    let old_off = volley_of(&old, &without_bane(&old), 4, 10.0, SEED);
    assert_ne!(old_on.rolls, old_off.rolls, "fixture: seed {SEED} must land a re-rollable save");
    let us = probe_unit(&root, "beastman", EPOCH_73_V36);
    let bare = without_bane(&us);
    let inside = volley_of(&us, &us.shoot[0], 4, 10.0, SEED);
    let off = volley_of(&us, &bare, 4, 10.0, SEED);
    assert_eq!(inside.rolls, off.rolls, "RED on main: 10\" is inside half range but re-rolls");
    let outside = volley_of(&us, &us.shoot[0], 4, 13.0, SEED);
    assert_ne!(outside.rolls, off.rolls, "13\" is beyond half range: the window opens");
}

#[test]
fn the_volley_log_names_the_condition_that_opened_the_window() {
    let root = probe_root("def56_log");
    let us = probe_unit(&root, "goblin", EPOCH_73_V36);
    let out = volley_of(&us, &us.shoot[0], 5, 12.0, SEED);
    assert!(
        out.log.iter().any(|l| l.contains("target defends on 5+ or 6+")),
        "the re-roll line must name the condition: {:?}",
        out.log
    );
}
