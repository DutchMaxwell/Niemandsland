//! The Banner-family source the table's morale line names (`SoloController.morale_bonus_named_of`), stamped on the
//! unit static as `morale_family`. Real units over the real registry (gf `human_defense_force`: Hold the Line, Courageous).
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_75_TABLE_FIXES};

fn family(rules: &[&str], heroes: &[&[&str]], epoch: u32) -> String {
    let mut p: Profile = serde_json::from_str(r#"{"unit_id":"fam","name":"Fam"}"#).unwrap();
    p.game_system = "gf".into();
    p.faction_folder = "human_defense_force".into();
    p.special_rules = rules.iter().map(|r| r.to_string()).collect();
    p.model_count = 5;
    p.attached_hero_rules = heroes.iter().map(|h| h.iter().map(|r| r.to_string()).collect()).collect();
    let mut reg = Registries::new(&format!("{}/../..", env!("CARGO_MANIFEST_DIR")));
    UnitStatic::build_for(&mut reg, &p, epoch).morale_family
}

#[test]
fn the_plain_banner_and_an_alias_name_themselves() {
    assert_eq!(family(&["Banner"], &[], EPOCH_75_TABLE_FIXES), "Banner");
    assert_eq!(family(&["Hold the Line"], &[], EPOCH_75_TABLE_FIXES), "Hold the Line");
}

/// The table's own fallback: a unit whose bonus is only a Morale(X) rating still names "Banner" as the family.
#[test]
fn a_unit_without_a_banner_family_rule_falls_back_to_banner() {
    assert_eq!(family(&["Fearless"], &[], EPOCH_75_TABLE_FIXES), "Banner");
}

/// The larger bonus wins, a tie keeps the first entry in rule order (the table's strict `>`), a joined hero's rule joins the walk.
#[test]
fn the_best_bonus_names_the_source_and_a_tie_keeps_the_first() {
    assert_eq!(family(&["Hold the Line", "Enhanced Hold the Line"], &[], EPOCH_75_TABLE_FIXES), "Enhanced Hold the Line");
    assert_eq!(family(&["Courageous", "Hold the Line"], &[], EPOCH_75_TABLE_FIXES), "Courageous");
    assert_eq!(family(&["Hold the Line", "Courageous"], &[], EPOCH_75_TABLE_FIXES), "Hold the Line");
    assert_eq!(family(&["Banner"], &[&["Enhanced Hold the Line"]], EPOCH_75_TABLE_FIXES), "Enhanced Hold the Line");
}

/// From the Bravery epoch the Bravery family is its own best-of that joins with " + "; below it Bravery folds into the one best-of.
#[test]
fn bravery_joins_the_family_from_its_epoch() {
    assert_eq!(family(&["Banner", "Bravery Aura"], &[], EPOCH_75_TABLE_FIXES), "Banner + Bravery Aura");
    assert_eq!(family(&["Bravery Aura"], &[], EPOCH_75_TABLE_FIXES), "Bravery Aura");
    assert_eq!(family(&["Banner", "Bravery Aura"], &[], EPOCH_72_PLAYTEST_RULES), "Banner");
}
