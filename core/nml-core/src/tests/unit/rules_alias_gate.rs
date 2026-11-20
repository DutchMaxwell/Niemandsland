//! The 3.6 faction-folder alias in the RULES registry (`acts::EPOCH_93_DANGER_RULES_RIDER`), read through the unit build:
//! a list that kept an old army-book folder gets its book's faction rules from the gate on, below it the old
//! common-only read stays byte-exact. The record's epoch re-stamps a REUSED registry on every build, so a replay at a
//! lower epoch after a higher one never sees the alias. `Enhanced Lustbound` (a Royal Legion rule held only by the
//! lust book's faction section) adds +8" reach to a ranged gun, which makes the alias visible in `UnitStatic`.
use super::*;

fn lustbound_unit(system: &str, folder: &str) -> Profile {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "u":{{"unit_id":"u","name":"Lust Shooters","quality":4,"defense":5,"tough":3,"wounds_max":[3],
        "model_count":1,"caster_value":0,"base_radius":0.0125,"game_system":"{system}","faction_folder":"{folder}",
        "special_rules":["Enhanced Lustbound"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Gun","range":12,"attacks":2,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
    );
    read_act_header(&tpl).expect("header").profiles.get("u").expect("unit").clone()
}

fn reach(us: &UnitStatic) -> f64 {
    us.shoot.iter().filter(|p| p.range > 0).map(|p| p.range as f64 + p.reach_bonus_in).fold(0.0_f64, f64::max)
}

#[test]
fn an_old_lust_folder_reads_its_faction_rules_only_from_the_alias_gate() {
    let gate = crate::acts::EPOCH_93_DANGER_RULES_RIDER;
    let old = lustbound_unit("gf", "wormhole_daemons_of_lust");
    let canonical = lustbound_unit("gf", "daemons_of_lust");
    let mut reg = Registries::new(&repo_root());
    assert_eq!(reach(&UnitStatic::build_for(&mut reg, &canonical, gate - 1)), 20.0, "the 3.6 folder holds the rule at any epoch");
    assert_eq!(reach(&UnitStatic::build_for(&mut reg, &old, gate - 1)), 12.0, "below the gate the old folder keeps its common-only read");
    assert_eq!(reach(&UnitStatic::build_for(&mut reg, &old, gate)), 20.0, "from the gate the alias resolves the same faction rule");
    assert_eq!(
        reach(&UnitStatic::build_for(&mut reg, &old, gate - 1)),
        12.0,
        "a registry reused for a lower-epoch record is re-stamped, never left on the higher epoch's alias"
    );
}

#[test]
fn the_rules_alias_never_crosses_the_systems_folder_naming() {
    let gate = crate::acts::EPOCH_93_DANGER_RULES_RIDER;
    let mut reg = Registries::new(&repo_root());
    // An AoF folder in a GF list (and the other way round) is no alias: neither system's map keys it.
    assert_eq!(reach(&UnitStatic::build_for(&mut reg, &lustbound_unit("gf", "rift_daemons_of_lust"), gate)), 12.0);
    assert_eq!(reach(&UnitStatic::build_for(&mut reg, &lustbound_unit("aof", "wormhole_daemons_of_lust"), gate)), 12.0);
    assert_eq!(reach(&UnitStatic::build_for(&mut reg, &lustbound_unit("aof", "rift_daemons_of_lust"), gate)), 20.0);
}
