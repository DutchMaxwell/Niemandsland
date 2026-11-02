use super::super::*;
use crate::acts::CURRENT_RULES_EPOCH;
use serde_json::json;

// SHO-12 (rules 3.6): the five namesake weapon rules of the old Shatter family. Each book that
// prints a rule carries its own map entry, so the table resolves it instead of printing
// "apply manually". The entries are data; the base save re-roll / cover / AP legs are the
// existing ones. All thirty carrier books are pinned in the gdUnit twin; here the shipped
// map entries of one book per system and the live profile reads are the proof.

fn assert_entry(reg: &mut Registries, system: &str, book: &str, rule: &str, primitive: &str, params: serde_json::Value) {
    let map = reg.rules_for(system);
    assert!(map.has_primitive(book, rule), "{system} / {book}: {rule} must resolve");
    let entry = map.lookup(book, rule).expect("a resolving rule has an entry");
    assert_eq!(entry.primitive.as_deref(), Some(primitive), "{system} / {book}: {rule} primitive");
    assert_eq!(entry.params, params, "{system} / {book}: {rule} params");
}

#[test]
fn the_shipped_maps_resolve_the_five_rules_in_the_books_that_print_them() {
    let mut reg = Registries::new(&repo_root());
    for (system, book, rule, primitive, params) in [
        ("gf", "battle_brothers", "Smash", "Bane",
            json!({"reroll_save_sixes": true, "condition": "over_half_range", "bypass_regen": false})),
        ("aof", "wood_elves", "Smash", "Bane",
            json!({"reroll_save_sixes": true, "condition": "over_half_range", "bypass_regen": false})),
        ("gf", "titan_lords_plague_disciples", "Decimate", "Bane",
            json!({"reroll_save_sixes": true, "condition": "above_half_strength", "bypass_regen": false})),
        ("aof", "halflings", "Decimate", "Bane",
            json!({"reroll_save_sixes": true, "condition": "above_half_strength", "bypass_regen": false})),
        ("gf", "alien_hives", "Fragment", "Bane",
            json!({"reroll_save_sixes": true, "reroll_save_low": 5, "condition": "def_5_6", "bypass_regen": false})),
        ("aof", "ogres", "Fragment", "Bane",
            json!({"reroll_save_sixes": true, "reroll_save_low": 5, "condition": "def_5_6", "bypass_regen": false})),
        ("gf", "daemons_of_lust", "Obliterate", "Bane",
            json!({"reroll_save_sixes": true, "reroll_save_low": 5, "condition": "vs_tough_ge", "threshold": 3, "bypass_regen": true})),
        ("aof", "chivalrous_kingdoms", "Obliterate", "Bane",
            json!({"reroll_save_sixes": true, "reroll_save_low": 5, "condition": "vs_tough_ge", "threshold": 3, "bypass_regen": true})),
        ("gf", "machine_cults", "Demolish", "Indirect",
            json!({"ignores_cover": true, "cover_only": true, "ap_bonus": 1, "condition": "near_terrain"})),
        ("aof", "volcanic_dwarves", "Demolish", "Indirect",
            json!({"ignores_cover": true, "cover_only": true, "ap_bonus": 1, "condition": "near_terrain"})),
    ] {
        assert_entry(&mut reg, system, book, rule, primitive, params);
    }
}

#[test]
fn a_book_that_does_not_print_a_rule_does_not_resolve_it() {
    let mut reg = Registries::new(&repo_root());
    for (system, book, rule) in [
        ("gf", "battle_brothers", "Demolish"),
        ("aof", "wood_elves", "Demolish"),
        ("gf", "alien_hives", "Smash"),
        ("aof", "ogres", "Obliterate"),
    ] {
        assert!(!reg.rules_for(system).has_primitive(book, rule), "{system} / {book} must not resolve {rule}");
    }
}

const CARRIER_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "demolisher":{"unit_id":"demolisher","name":"Demolisher","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"machine_cults","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Gun","range":24,"attacks":8,"count":1,"ap":0,"rules":["Demolish"]}]},
  "smasher":{"unit_id":"smasher","name":"Smasher","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"battle_brothers","special_rules":["Smash"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Gun","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

fn carrier(id: &str) -> UnitStatic {
    let header = read_act_header(CARRIER_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get(id).expect(id);
    UnitStatic::build_for(&mut reg, p, CURRENT_RULES_EPOCH)
}

fn volley(us: &UnitStatic, near_terrain: bool, seed: i64) -> ShootResult {
    let p = [us.shoot[0].clone()];
    let def = Ctx { defense: 4, models: 1, tough: 1, near_terrain, ..Default::default() };
    let mut tray = Tray::seeded(seed);
    resolve_volley_with_tray(
        &[Shooter { profiles: &p, keep: &[0], attacks: &[8], att: &us.ctx, owner: "" }],
        &def, "Target", 12.0, 12.0, true, true, true, true, &mut tray,
    )
}

fn save_target(r: &ShootResult) -> i64 {
    r.rolls.iter().find(|x| x.kind == "defense").map(|x| x.target).unwrap_or(-1)
}

/// The live path: Demolish's own entry gives the weapon Ignore Cover and AP(+1) only when the
/// target stands by terrain. No test field is hand-built; the profile comes from the real map.
#[test]
fn demolish_skips_cover_and_gains_ap_only_against_a_target_by_terrain() {
    let us = carrier("demolisher");
    assert!(us.shoot[0].ignores_cover, "Demolish makes the weapon skip Cover");
    assert_eq!(save_target(&volley(&us, false, 3)), 4, "no terrain: printed AP(0)");
    assert_eq!(save_target(&volley(&us, true, 3)), 5, "by terrain: the entry's AP(+1)");
}

/// The live path: a unit that fields Smash gets the Bane save re-roll from its map entry.
#[test]
fn a_unit_that_fields_smash_gets_its_bane_save_re_roll() {
    let us = carrier("smasher");
    assert!(us.shoot[0].bane, "Smash's Bane entry reaches the shooting profile");
}
