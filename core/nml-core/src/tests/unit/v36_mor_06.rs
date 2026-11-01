//! Rules 3.6 row MOR-06 tests (unit module); owned by lane morale.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// One unit of `host_models` carriers of `rules`, plus one joined hero per entry of
/// `heroes` (each hero's own rule list).
fn mor06_profile(system: &str, faction: &str, rules: &[&str], host_models: i64, heroes: &[&[&str]]) -> Profile {
    let mut p: Profile = serde_json::from_str(r#"{"unit_id":"mor06","name":"Mor06"}"#).unwrap();
    p.game_system = system.into();
    p.faction_folder = faction.into();
    p.special_rules = rules.iter().map(|r| r.to_string()).collect();
    p.model_count = host_models;
    p.attached_hero_rules = heroes
        .iter()
        .map(|h| h.iter().map(|r| r.to_string()).collect())
        .collect();
    p
}

fn mor06_registry() -> Registries {
    Registries::new(&repo_root())
}

const PLAIN_HERO: &[&str] = &["Hero"];

// --- D-MOST, Steadfast and Battleborn recovery. ---

#[test]
fn steadfast_recovery_keeps_with_a_plain_joined_hero_at_epoch_73() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "change_disciples", &["Steadfast"], 5, &[PLAIN_HERO]);
    assert_eq!(
        battleborn_recover_target_of(&mut reg, &p, EPOCH_73_V36), 4,
        "five of six models carry Steadfast: the recovery die stays"
    );
}

#[test]
fn steadfast_recovery_needs_every_model_at_epoch_72() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "change_disciples", &["Steadfast"], 5, &[PLAIN_HERO]);
    assert_eq!(
        battleborn_recover_target_of(&mut reg, &p, EPOCH_72_PLAYTEST_RULES), 0,
        "the old reading: one plain hero strips the recovery die"
    );
}

#[test]
fn battleborn_recovery_keeps_with_a_plain_joined_hero_at_epoch_73() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "battle_brothers", &["Battleborn"], 5, &[PLAIN_HERO]);
    assert_eq!(
        battleborn_recover_target_of(&mut reg, &p, EPOCH_73_V36), 4,
        "five of six models carry Battleborn: the recovery die stays"
    );
}

#[test]
fn battleborn_recovery_needs_every_model_at_epoch_72() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "battle_brothers", &["Battleborn"], 5, &[PLAIN_HERO]);
    assert_eq!(
        battleborn_recover_target_of(&mut reg, &p, EPOCH_72_PLAYTEST_RULES), 0,
        "the old reading: one plain hero strips the recovery die"
    );
}

// --- D-MOST, Evasive and Melee Evasion. ---

#[test]
fn evasive_keeps_with_a_plain_joined_hero_at_epoch_73() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "battle_brothers", &["Evasive"], 5, &[PLAIN_HERO]);
    assert!(ctx_for(&mut reg, &p, EPOCH_73_V36).evasive,
        "five of six models carry Evasive: most models, the squad keeps it");
}

#[test]
fn evasive_needs_every_model_at_epoch_72() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "battle_brothers", &["Evasive"], 5, &[PLAIN_HERO]);
    assert!(!ctx_for(&mut reg, &p, EPOCH_72_PLAYTEST_RULES).evasive,
        "the old reading: one plain hero strips the whole squad");
}

#[test]
fn melee_evasion_keeps_with_a_plain_joined_hero_at_epoch_73() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "dark_elf_raiders", &["Melee Evasion"], 5, &[PLAIN_HERO]);
    assert!(ctx_for(&mut reg, &p, EPOCH_73_V36).melee_evasion,
        "five of six models carry Melee Evasion: most models, the squad keeps it");
}

#[test]
fn melee_evasion_needs_every_model_at_epoch_72() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "dark_elf_raiders", &["Melee Evasion"], 5, &[PLAIN_HERO]);
    assert!(!ctx_for(&mut reg, &p, EPOCH_72_PLAYTEST_RULES).melee_evasion,
        "the old reading: one plain hero strips the whole squad");
}

// --- D-MOST, Melee and Ranged Shrouding. ---

#[test]
fn melee_shrouding_keeps_with_a_plain_joined_hero_at_epoch_73() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "battle_brothers", &["Melee Shrouding"], 5, &[PLAIN_HERO]);
    assert!(capture_reads_for_epoch(&mut reg, &p, EPOCH_73_V36).shroud.is_some(),
        "five of six models carry Melee Shrouding: the charge penalty stays");
}

#[test]
fn melee_shrouding_needs_every_model_at_epoch_72() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "battle_brothers", &["Melee Shrouding"], 5, &[PLAIN_HERO]);
    assert!(capture_reads_for_epoch(&mut reg, &p, EPOCH_72_PLAYTEST_RULES).shroud.is_none(),
        "the old reading: one plain hero strips the charge penalty");
}

#[test]
fn ranged_shrouding_keeps_with_a_plain_joined_hero_at_epoch_73() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "custodian_brothers", &["Ranged Shrouding"], 5, &[PLAIN_HERO]);
    assert!(ctx_for(&mut reg, &p, EPOCH_73_V36).ranged_shrouding,
        "five of six models carry Ranged Shrouding: the range penalty stays");
}

#[test]
fn ranged_shrouding_needs_every_model_at_epoch_72() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "custodian_brothers", &["Ranged Shrouding"], 5, &[PLAIN_HERO]);
    assert!(!ctx_for(&mut reg, &p, EPOCH_72_PLAYTEST_RULES).ranged_shrouding,
        "the old reading: one plain hero strips the range penalty");
}

// --- D-MOST, Growth Markers. ---

#[test]
fn growth_markers_keep_with_a_plain_joined_hero_at_epoch_73() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "alien_hives", &["Piercing Growth"], 5, &[PLAIN_HERO]);
    let us = UnitStatic::build_for(&mut reg, &p, EPOCH_73_V36);
    assert_eq!(us.growth.len(), 1,
        "five of six models carry Piercing Growth: the marker rule stays");
}

#[test]
fn growth_markers_need_every_model_at_epoch_72() {
    let mut reg = mor06_registry();
    let p = mor06_profile("gf", "alien_hives", &["Piercing Growth"], 5, &[PLAIN_HERO]);
    let us = UnitStatic::build_for(&mut reg, &p, EPOCH_72_PLAYTEST_RULES);
    assert!(us.growth.is_empty(),
        "the old reading: one plain hero strips the marker rule");
}

// --- D-MOST, Grounded Evasion (the rules 3.6 name of Grounded Stealth). ---

#[test]
fn grounded_evasion_keeps_with_a_plain_joined_hero_at_epoch_73() {
    let p = mor06_profile("gf", "", &["Grounded Evasion"], 5, &[PLAIN_HERO]);
    assert!(stealth_family_on(&p, "Grounded Evasion", EPOCH_73_V36),
        "five of six models carry Grounded Evasion: most models, the squad keeps it");
}

#[test]
fn grounded_evasion_needs_every_model_at_epoch_72() {
    let p = mor06_profile("gf", "", &["Grounded Evasion"], 5, &[PLAIN_HERO]);
    assert!(!stealth_family_on(&p, "Grounded Evasion", EPOCH_72_PLAYTEST_RULES),
        "the old reading: one plain hero strips the whole squad");
}
