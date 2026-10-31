//! Rules 3.6 row W1.7 tests (renamed aura channel names); owned by row W1.7.
//!
//! W1.7 (D-ENH on channel names): two aura channel entries and one shielded base change their
//! printed name at rules 3.6. The 3.6 name does exactly what the 3.5 name did; the 3.5 name is
//! gone (no alias). The carrier is the real `build_for` product through the real registry.
use super::*;
use crate::acts::CURRENT_RULES_EPOCH;

/// One rifle and one blade, so the profile is a normal fighting unit.
const W17_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"soul_snatcher_cults",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
      {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

/// A carrier of `soul_snatcher_cults` printing `rules`, read at the current epoch.
fn w17_unit(rules: &[&str]) -> UnitStatic {
    let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let tpl = W17_HEADER.replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
    let header = read_act_header(&tpl).expect("W17_HEADER parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), CURRENT_RULES_EPOCH)
}

/// The two renamed channel entries hand their base to the unit under the 3.6 name; the 3.5 entry
/// names hand nothing any more.
#[test]
fn the_renamed_channel_auras_grant_their_base_and_the_old_names_grant_nothing() {
    for (new_aura, old_aura) in [
        ("Piercing Marksman Aura", "Piercing Hunter Aura"),
        ("Grounded Defense Aura", "Grounded Reinforcement Aura"),
    ] {
        let new_base = new_aura.strip_suffix(" Aura").expect("aura name ends ' Aura'");
        let old_base = old_aura.strip_suffix(" Aura").expect("aura name ends ' Aura'");
        let granted = aura_expanded(&format!("[\"{new_aura}\"]"), "[]", 6).special_rules;
        assert!(granted.iter().any(|r| r == new_base), "{new_aura} grants '{new_base}'");
        let stale = aura_expanded(&format!("[\"{old_aura}\"]"), "[]", 6).special_rules;
        assert!(!stale.iter().any(|r| r == old_base), "{old_aura} is gone: no alias");
    }
}

/// The shielded base prints as "Grounded Defense": the 3.6 name stamps the Grounded alias, the
/// 3.5 name stamps nothing, and the alias's log name (the rules-must-log text) is the 3.6 name.
#[test]
fn a_grounded_defense_carrier_stamps_the_grounded_alias_and_logs_its_new_name() {
    use crate::unit::ShieldedAlias;
    assert_eq!(
        w17_unit(&["Grounded Defense"]).ctx.shielded_alias,
        ShieldedAlias::GroundedReinforcement,
        "the 3.6 name stamps the alias"
    );
    assert_eq!(
        w17_unit(&["Grounded Reinforcement"]).ctx.shielded_alias,
        ShieldedAlias::None,
        "the 3.5 name is gone"
    );
    assert_eq!(ShieldedAlias::GroundedReinforcement.name(), "Grounded Defense", "the log line names the 3.6 rule");
}
