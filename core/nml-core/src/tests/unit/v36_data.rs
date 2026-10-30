//! Rules 3.6 lane data tests for the unit module; owned by lane data.
use super::*;
use serde_json::json;

/// DAT-01: Shred and Surge are core rules in both 3.6 systems, so the gf and aof maps carry them
/// as common entries. A book without its own entry resolves them through the common fallback,
/// with the params every faction entry already carries; a book with its own entry resolves the same.
fn assert_resolves(reg: &mut Registries, system: &str, book: &str, rule: &str, params: serde_json::Value) {
    let map = reg.rules_for(system);
    assert!(map.has_primitive(book, rule), "{system} / {book}: {rule} must resolve to a primitive");
    let entry = map.lookup(book, rule).expect("a resolving rule has an entry");
    assert_eq!(entry.primitive.as_deref(), Some(rule), "{system} / {book}: {rule} primitive");
    assert_eq!(entry.params, params, "{system} / {book}: {rule} params");
}

#[test]
fn dat_01_a_book_without_its_own_entry_resolves_shred_and_surge() {
    let mut reg = Registries::new(&repo_root());
    for (system, book) in [("gf", "human_defense_force"), ("aof", "orcs")] {
        assert_resolves(&mut reg, system, book, "Shred", json!({"extra_wound_per_save_one": 1}));
        assert_resolves(&mut reg, system, book, "Surge", json!({"bonus_hits_per_six": 1}));
    }
}

/// Control: the books that already had their own entries resolve unchanged.
#[test]
fn dat_01_a_book_with_its_own_entry_resolves_shred_and_surge_unchanged() {
    let mut reg = Registries::new(&repo_root());
    for (system, book) in [("gf", "alien_hives"), ("aof", "beastmen")] {
        assert_resolves(&mut reg, system, book, "Shred", json!({"extra_wound_per_save_one": 1}));
        assert_resolves(&mut reg, system, book, "Surge", json!({"bonus_hits_per_six": 1}));
    }
}

/// AI-08a: rules 3.6 prints Ignores Cover as Anti-Cover and Ignores Regeneration as Anti-Regen. Row
/// DAT-04 adds their map entries; this fixture is a temp repo root whose gf map is the real one plus
/// (with `with_entries`) the same entries, so the reads can be shown before those land.
fn ai_08a_root(tag: &str, with_entries: bool) -> String {
    let real = std::fs::read_to_string(format!("{}/assets/solo/rules_mechanics_gf.json", repo_root()))
        .expect("the gf map");
    let mut map: serde_json::Value = serde_json::from_str(&real).expect("the gf map parses");
    let common = map["common"].as_object_mut().expect("the gf map has common entries");
    for name in ["Anti-Cover", "Anti-Cover when Shooting", "Anti-Regen"] {
        common.remove(name);
    }
    if with_entries {
        let cover = json!({"ignores_cover": true, "cover_only": true});
        let shooting = json!({"ignores_cover": true, "cover_only": true, "shooting_only": true});
        common.insert("Anti-Cover".into(), json!({"primitive": "Indirect", "params": cover}));
        common.insert("Anti-Cover when Shooting".into(), json!({"primitive": "Indirect", "params": shooting}));
        common.insert("Anti-Regen".into(), json!({"primitive": "Lacerate", "params": {"bypass_regen": true}}));
    }
    let dir = std::env::temp_dir().join(format!("nml_ai_08a_{tag}_{}", std::process::id()));
    let maps = dir.join("assets/solo");
    std::fs::create_dir_all(&maps).expect("temp map dir");
    std::fs::write(maps.join("rules_mechanics_gf.json"), map.to_string()).expect("write the temp gf map");
    dir.to_string_lossy().into_owned()
}

/// One gf carrier with a 24in rifle and claws, both printing `weapon_rule` ("" = none), carrying
/// `unit_rule` ("" = none), built off `root` at `epoch`.
fn ai_08a_carrier(root: &str, unit_rule: &str, weapon_rule: &str, epoch: u32) -> UnitStatic {
    let list = |r: &str| if r.is_empty() { "[]".to_string() } else { format!("[\"{r}\"]") };
    let (unit_rules, weapon_rules) = (list(unit_rule), list(weapon_rule));
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "carrier":{{"unit_id":"carrier","name":"Carrier","quality":2,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":{unit_rules},"item_grants":[],
        "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Rifle","range":24,"attacks":24,"count":1,"ap":0,"rules":{weapon_rules}}},
          {{"name":"Claws","range":0,"attacks":24,"count":1,"ap":0,"rules":{weapon_rules}}}]}}}}}}"#
    );
    let header = read_act_header(&tpl).expect("header");
    let p = header.profiles.get("carrier").expect("carrier");
    UnitStatic::build_for(&mut Registries::new(root), p, epoch)
}

/// The shooter's and the one-model Defense 4 target's contexts.
fn ai_08a_ctx() -> (Ctx, Ctx) {
    let att = Ctx { quality: 2, models: 1, ..Default::default() };
    (att, Ctx { defense: 4, tough: 1, models: 1, ..Default::default() })
}

/// One volley of the carrier's rifle (24 dice) into `def`.
fn ai_08a_volley(us: &UnitStatic, def: &Ctx) -> crate::dice::ShootResult {
    let (att, _) = ai_08a_ctx();
    let mut tray = crate::dice::Tray::seeded(27);
    crate::dice::resolve_shooting_with_tray(&[us.shoot[0].clone()], &[0], &[24], &att, def, 12.0, &mut tray)
}

/// A weapon that prints Anti-Cover skips cover in the core: the profile flag the save step and the
/// AI's estimate both read. The volley names the rule when the skipped cover was there.
#[test]
fn ai_08a_a_weapon_printing_anti_cover_skips_cover_in_the_core() {
    let us = ai_08a_carrier(&ai_08a_root("cover", true), "", "Anti-Cover", CURRENT_RULES_EPOCH);
    assert!(us.shoot[0].ignores_cover, "the Anti-Cover rifle skips cover");
    let (att, open) = ai_08a_ctx();
    let covered = Ctx { in_cover: true, ..open };
    let ev = |def: &Ctx| crate::combat::profile_ev(&us.shoot[0], 24, &att, def, 12.0, false);
    assert_eq!(ev(&covered), ev(&open), "the AI's estimate charges no cover save");
    let out = ai_08a_volley(&us, &covered);
    let named = out.log.iter().any(|l| l.starts_with("Anti-Cover:") && l.contains("cover save is skipped"));
    assert!(named, "rules-must-log: {:?}", out.log);
}

/// A unit that carries Anti-Cover when Shooting already skips cover through its entry (DAT-04's
/// map-driven leg); the volley now names that rule too.
#[test]
fn ai_08a_a_unit_with_anti_cover_when_shooting_names_its_rule_in_the_volley() {
    let us = ai_08a_carrier(&ai_08a_root("unit", true), "Anti-Cover when Shooting", "", CURRENT_RULES_EPOCH);
    let (_, open) = ai_08a_ctx();
    let out = ai_08a_volley(&us, &Ctx { in_cover: true, ..open });
    let named = out.log.iter().any(|l| l.starts_with("Anti-Cover when Shooting:") && l.contains("cover save is skipped"));
    assert!(named, "rules-must-log: {:?}", out.log);
}

/// A weapon that prints Anti-Regen wounds a Regeneration unit with no Regeneration roll, in melee and
/// shooting alike; the AI's estimate counts every wound and the volley names the rule.
#[test]
fn ai_08a_a_weapon_printing_anti_regen_skips_regeneration_in_the_core() {
    let us = ai_08a_carrier(&ai_08a_root("regen", true), "", "Anti-Regen", CURRENT_RULES_EPOCH);
    assert!(us.shoot[0].bypass_regen, "the Anti-Regen rifle ignores Regeneration");
    assert!(!us.melee.is_empty() && us.melee.iter().all(|sp| sp.bypass_regen), "the claws too");
    let (att, plain) = ai_08a_ctx();
    let regen = Ctx { regeneration: true, regen_target: 5, ..plain };
    let ev = |def: &Ctx| crate::combat::profile_ev(&us.shoot[0], 24, &att, def, 12.0, false);
    assert_eq!(ev(&regen), ev(&plain), "the AI's estimate counts every wound");
    let out = ai_08a_volley(&us, &regen);
    assert!(out.caused > 0, "fixture seed no longer wounds - pick another");
    assert_eq!(out.wounds, out.caused, "no wound meets the Regeneration roll");
    let named = out.log.iter().any(|l| l.starts_with("Anti-Regen:") && l.contains("Regeneration ignored"));
    assert!(named, "rules-must-log: {:?}", out.log);
}

/// The weapon read goes through the map entry, so the old weapon-printed Ignores Regeneration (one
/// gf 3.5 weapon) now skips the roll in the core as it already did on the table.
#[test]
fn ai_08a_a_weapon_printing_ignores_regeneration_skips_regeneration_in_the_core() {
    let us = ai_08a_carrier(&ai_08a_root("old_regen", true), "", "Ignores Regeneration", CURRENT_RULES_EPOCH);
    assert!(us.shoot[0].bypass_regen, "the core matches the table's map read");
}

/// Control: without the map entries (this row lands before DAT-04) both new names stay inert; the
/// read is the map's, never a new name literal.
#[test]
fn ai_08a_without_the_map_entries_both_names_stay_inert() {
    let root = ai_08a_root("inert", false);
    assert!(!ai_08a_carrier(&root, "", "Anti-Cover", CURRENT_RULES_EPOCH).shoot[0].ignores_cover);
    assert!(!ai_08a_carrier(&root, "", "Anti-Regen", CURRENT_RULES_EPOCH).shoot[0].bypass_regen);
}

/// Control: the weapon read rides EPOCH_73_V36, so a record below it replays as recorded (no new
/// skip, no new line), and the old Ignores Cover keeps its name read at every epoch.
#[test]
fn ai_08a_below_the_3_6_epoch_the_weapon_read_stays_off() {
    let root = ai_08a_root("epoch", true);
    let old = crate::acts::EPOCH_72_PLAYTEST_RULES;
    assert!(!ai_08a_carrier(&root, "", "Anti-Cover", old).shoot[0].ignores_cover);
    assert!(!ai_08a_carrier(&root, "", "Anti-Regen", old).shoot[0].bypass_regen);
    assert!(!ai_08a_carrier(&root, "", "Ignores Regeneration", old).shoot[0].bypass_regen);
    for epoch in [old, CURRENT_RULES_EPOCH] {
        assert!(ai_08a_carrier(&root, "", "Ignores Cover", epoch).shoot[0].ignores_cover);
    }
}
