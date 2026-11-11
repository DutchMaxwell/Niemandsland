//! Rules 3.6 row MOR-05b tests (unit module); owned by lane morale.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// MOR-05b — one unit of `host_models` carriers of `rules`, plus one joined hero per entry of
/// `heroes` (each hero's own rule list). Returns the stamped combat context.
fn guarded_ctx(system: &str, faction: &str, rules: &[&str], host_models: i64, heroes: &[&[&str]], epoch: u32) -> Ctx {
    let mut p: Profile = serde_json::from_str(r#"{"unit_id":"guarded","name":"Guarded"}"#).unwrap();
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

// --- D-MOST, Guarded: five carriers and one plain hero are five of six models. ---

#[test]
fn a_guarded_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() {
    let ctx = guarded_ctx("gf", "", &["Guarded"], 5, &[PLAIN_HERO], EPOCH_73_V36);
    assert!(ctx.guarded, "five of six models carry Guarded: most models, the squad keeps it");
}

#[test]
fn a_guarded_squad_loses_it_with_a_plain_joined_hero_at_epoch_72() {
    let ctx = guarded_ctx("gf", "", &["Guarded"], 5, &[PLAIN_HERO], EPOCH_72_PLAYTEST_RULES);
    assert!(!ctx.guarded, "the old reading: one plain hero strips the whole squad");
}

#[test]
fn a_lone_guarded_model_and_a_plain_hero_are_an_exact_half_at_epoch_73() {
    let ctx = guarded_ctx("gf", "", &["Guarded"], 1, &[PLAIN_HERO], EPOCH_73_V36);
    assert!(!ctx.guarded, "one of two models is exactly half, not most");
}

#[test]
fn a_guarded_squad_with_a_guarded_hero_stays_on_at_epoch_73() {
    let hero: &[&str] = &["Hero", "Guarded"];
    let ctx = guarded_ctx("gf", "", &["Guarded"], 5, &[hero], EPOCH_73_V36);
    assert!(ctx.guarded, "every model carries it: the majority read agrees with the old one");
}

// --- D-MOST, Versatile Defense and the data aliases Sturdy / Safety Gear / Tenacious. ---

#[test]
fn a_versatile_defense_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() {
    let ctx = guarded_ctx("gf", "", &["Versatile Defense"], 5, &[PLAIN_HERO], EPOCH_73_V36);
    assert!(ctx.guarded, "five of six models carry Versatile Defense: most models, the squad keeps it");
}

#[test]
fn a_versatile_defense_squad_loses_it_with_a_plain_joined_hero_at_epoch_72() {
    let ctx = guarded_ctx("gf", "", &["Versatile Defense"], 5, &[PLAIN_HERO], EPOCH_72_PLAYTEST_RULES);
    assert!(!ctx.guarded, "the old reading: one plain hero strips the whole squad");
}

#[test]
fn a_sturdy_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() {
    let ctx = guarded_ctx("gf", "dwarf_guilds", &["Sturdy"], 5, &[PLAIN_HERO], EPOCH_73_V36);
    assert!(ctx.guarded, "five of six models carry Sturdy: the alias follows the majority");
}

#[test]
fn a_safety_gear_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() {
    let ctx = guarded_ctx("gf", "", &["Safety Gear"], 5, &[PLAIN_HERO], EPOCH_73_V36);
    assert!(ctx.guarded, "five of six models carry Safety Gear: the alias follows the majority");
}

#[test]
fn a_tenacious_squad_keeps_it_with_a_plain_joined_hero_at_epoch_73() {
    let ctx = guarded_ctx("aof", "", &["Tenacious"], 5, &[PLAIN_HERO], EPOCH_73_V36);
    assert!(ctx.guarded, "five of six models carry Tenacious: the alias follows the majority");
}
