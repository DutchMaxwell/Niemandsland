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

/// DAT-04: rules 3.6 renames Ignores Cover to Anti-Cover and Ignores Regeneration to Anti-Regen (the
/// same mechanics, checked against the 3.6 descriptions), and gf renames the Ignores Cover family
/// forms the same way. Both maps carry the new names with the old entries' primitive and params, so
/// a 3.6 book that fields them resolves them instead of printing "apply manually".
fn dat_04_assert_entry(
    reg: &mut Registries,
    system: &str,
    book: &str,
    rule: &str,
    primitive: &str,
    params: serde_json::Value,
) {
    let map = reg.rules_for(system);
    assert!(map.has_primitive(book, rule), "{system} / {book}: {rule} must resolve to a primitive");
    let entry = map.lookup(book, rule).expect("a resolving rule has an entry");
    assert_eq!(entry.primitive.as_deref(), Some(primitive), "{system} / {book}: {rule} primitive");
    assert_eq!(entry.params, params, "{system} / {book}: {rule} params");
}

/// One gf unit of `book` with a 24in rifle and a melee blade, carrying `rules` (a JSON array) at
/// unit level, built off the real registry at the live epoch.
fn dat_04_carrier(book: &str, rules: &str) -> UnitStatic {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "carrier":{{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"{book}",
        "special_rules":{rules},"item_grants":[],
        "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}},
          {{"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
    );
    let header = read_act_header(&tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("carrier").expect("carrier");
    UnitStatic::build_for(&mut reg, p, CURRENT_RULES_EPOCH)
}

fn dat_04_ranged(us: &UnitStatic) -> Vec<&ShootProfile> {
    let ranged: Vec<&ShootProfile> = us.shoot.iter().filter(|sp| sp.range > 0).collect();
    assert!(!ranged.is_empty(), "the carrier fixture has a ranged weapon");
    ranged
}

#[test]
fn dat_04_both_systems_resolve_anti_cover_and_anti_regen() {
    let mut reg = Registries::new(&repo_root());
    for (system, book) in [("gf", "alien_hives"), ("aof", "dragon_empire")] {
        let cover = json!({"ignores_cover": true, "cover_only": true});
        dat_04_assert_entry(&mut reg, system, book, "Anti-Cover", "Indirect", cover);
        dat_04_assert_entry(&mut reg, system, book, "Anti-Regen", "Lacerate", json!({"bypass_regen": true}));
    }
}

#[test]
fn dat_04_gf_resolves_the_anti_cover_family_forms() {
    let mut reg = Registries::new(&repo_root());
    let shooting = json!({"ignores_cover": true, "cover_only": true, "shooting_only": true});
    dat_04_assert_entry(&mut reg, "gf", "dwarf_guilds", "Anti-Cover when Shooting", "Indirect", shooting);
    let aura = json!({"grants": "Anti-Cover"});
    dat_04_assert_entry(&mut reg, "gf", "eternal_dynasty", "Anti-Cover Aura", "Aura Channel", aura);
    let aura = json!({"grants": "Anti-Cover when Shooting"});
    dat_04_assert_entry(&mut reg, "gf", "dwarf_guilds", "Anti-Cover when Shooting Aura", "Aura Channel", aura);
}

/// The map-driven legs (no name literal): a unit-level Anti-Cover when Shooting makes the ranged
/// weapons skip cover through its own entry, melee stays as it was. The weapon-printed Anti-Cover
/// flag is a name read and belongs to row AI-08.
#[test]
fn dat_04_a_unit_with_anti_cover_when_shooting_skips_cover_with_its_ranged_weapons() {
    let us = dat_04_carrier("dwarf_guilds", r#"["Anti-Cover when Shooting"]"#);
    assert!(dat_04_ranged(&us).iter().all(|sp| sp.ignores_cover), "ranged weapons skip cover");
    assert!(us.melee.iter().all(|sp| !sp.ignores_cover), "melee has no cover to skip");
}

/// The aura form hands its unit the base name it grants, and that base skips cover in turn.
#[test]
fn dat_04_a_unit_with_anti_cover_aura_skips_cover_with_its_ranged_weapons() {
    let us = dat_04_carrier("eternal_dynasty", r#"["Anti-Cover Aura"]"#);
    assert!(dat_04_ranged(&us).iter().all(|sp| sp.ignores_cover), "the aura's granted Anti-Cover skips cover");
}

/// A unit-level Anti-Regen cuts through Regeneration with every weapon, as Ignores Regeneration did.
#[test]
fn dat_04_a_unit_with_anti_regen_ignores_regeneration_with_every_weapon() {
    let us = dat_04_carrier("alien_hives", r#"["Anti-Regen"]"#);
    assert!(dat_04_ranged(&us).iter().all(|sp| sp.bypass_regen), "ranged weapons ignore Regeneration");
    assert!(!us.melee.is_empty() && us.melee.iter().all(|sp| sp.bypass_regen), "melee ignores Regeneration");
}

/// Control: the 3.5 names stay (row DAT-14 removes them later) and resolve exactly as before.
#[test]
fn dat_04_the_old_names_resolve_unchanged() {
    let mut reg = Registries::new(&repo_root());
    for (system, book) in [("gf", "alien_hives"), ("aof", "dragon_empire")] {
        let cover = json!({"ignores_cover": true, "cover_only": true});
        dat_04_assert_entry(&mut reg, system, book, "Ignores Cover", "Indirect", cover);
        let regen = json!({"bypass_regen": true});
        dat_04_assert_entry(&mut reg, system, book, "Ignores Regeneration", "Lacerate", regen);
    }
    let aura = json!({"grants": "Ignores Cover"});
    dat_04_assert_entry(&mut reg, "gf", "eternal_dynasty", "Ignores Cover Aura", "Aura Channel", aura);
}
