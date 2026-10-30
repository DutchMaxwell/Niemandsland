//! Rules 3.6 lane morale tests for the unit module; owned by lane morale.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// MOR-05 — one unit of `host_models` carriers of `rules`, plus one joined hero per entry of
/// `heroes` (each hero's own rule list). Returns the stamped combat context.
fn morale_ctx(system: &str, faction: &str, rules: &[&str], host_models: i64, heroes: &[&[&str]], epoch: u32) -> Ctx {
    let mut p: Profile = serde_json::from_str(r#"{"unit_id":"morale","name":"Morale"}"#).unwrap();
    p.game_system = system.into();
    p.faction_folder = faction.into();
    p.special_rules = rules.iter().map(|r| r.to_string()).collect();
    p.model_count = host_models;
    p.attached_hero_rules = heroes
        .iter()
        .map(|h| h.iter().map(|r| r.to_string()).collect())
        .collect();
    let mut reg = Registries::new(&format!("{}/../..", env!("CARGO_MANIFEST_DIR")));
    ctx_for(&mut reg, &p, epoch)
}

const PLAIN_HERO: &[&str] = &["Hero"];

// --- D-MOST, Fortified: five carriers and one plain hero are five of six models. ---

#[test]
fn a_fortified_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() {
    let ctx = morale_ctx("gf", "", &["Fortified"], 5, &[PLAIN_HERO], EPOCH_73_V36);
    assert!(ctx.fortified, "five of six models carry Fortified: most models, the squad keeps it");
}

#[test]
fn a_fortified_squad_loses_it_with_a_plain_joined_hero_at_epoch_72() {
    let ctx = morale_ctx("gf", "", &["Fortified"], 5, &[PLAIN_HERO], EPOCH_72_PLAYTEST_RULES);
    assert!(!ctx.fortified, "the old reading: one plain hero strips the whole squad");
}

#[test]
fn a_lone_fortified_model_and_a_plain_hero_are_an_exact_half_at_epoch_73() {
    let ctx = morale_ctx("gf", "", &["Fortified"], 1, &[PLAIN_HERO], EPOCH_73_V36);
    assert!(!ctx.fortified, "one of two models is exactly half, not most");
}

#[test]
fn a_fortified_squad_with_a_fortified_hero_stays_on_at_epoch_73() {
    let hero: &[&str] = &["Hero", "Fortified"];
    let ctx = morale_ctx("gf", "", &["Fortified"], 5, &[hero], EPOCH_73_V36);
    assert!(ctx.fortified, "every model carries it: the majority read agrees with the old one");
}

// --- D-MOST, Fortified family alias: Warden (aof eternal_wardens, over-9 form). ---

#[test]
fn a_warden_squad_keeps_the_alias_with_a_plain_joined_hero_at_epoch_73() {
    let ctx = morale_ctx("aof", "eternal_wardens", &["Warden"], 5, &[PLAIN_HERO], EPOCH_73_V36);
    assert_eq!(ctx.fortified_alias_ap, 1, "five of six models carry Warden: the alias stays on");
}

#[test]
fn a_warden_squad_loses_the_alias_with_a_plain_joined_hero_at_epoch_72() {
    let ctx = morale_ctx("aof", "eternal_wardens", &["Warden"], 5, &[PLAIN_HERO], EPOCH_72_PLAYTEST_RULES);
    assert_eq!(ctx.fortified_alias_ap, 0, "the old reading: one plain hero strips the alias");
}

#[test]
fn a_lone_warden_model_and_a_plain_hero_are_an_exact_half_at_epoch_73() {
    let ctx = morale_ctx("aof", "eternal_wardens", &["Warden"], 1, &[PLAIN_HERO], EPOCH_73_V36);
    assert_eq!(ctx.fortified_alias_ap, 0, "one of two models is exactly half, not most");
}

// --- D-MOST, Shielded. ---

#[test]
fn a_shielded_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() {
    let ctx = morale_ctx("gf", "", &["Shielded"], 5, &[PLAIN_HERO], EPOCH_73_V36);
    assert!(ctx.shielded, "five of six models carry Shielded: most models, the squad keeps it");
}

#[test]
fn a_shielded_squad_loses_it_with_a_plain_joined_hero_at_epoch_72() {
    let ctx = morale_ctx("gf", "", &["Shielded"], 5, &[PLAIN_HERO], EPOCH_72_PLAYTEST_RULES);
    assert!(!ctx.shielded, "the old reading: one plain hero strips the whole squad");
}

#[test]
fn a_lone_shielded_model_and_a_plain_hero_are_an_exact_half_at_epoch_73() {
    let ctx = morale_ctx("gf", "", &["Shielded"], 1, &[PLAIN_HERO], EPOCH_73_V36);
    assert!(!ctx.shielded, "one of two models is exactly half, not most");
}
