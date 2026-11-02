//! Rules 3.6 row MOR-07: "Spell Resistance" (and its aura form) reaches the Resistance primitive
//! and reads most models from `EPOCH_73_V36`; the 3.5 "Resistance" name keeps the every-model
//! read below the gate. Owned by lane morale.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// One host in the REAL gf registry (`alien_hives` carries the 3.5 Resistance entry; the 3.6
/// Spell Resistance entry lives in `common`). `HERO_RULES` is the profile's attached-hero rule
/// list, `[]` = no hero.
const FIXTURE: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "host":{"unit_id":"host","name":"Host","quality":4,
    "defense":4,"tough":1,"wounds_max":HOST_WOUNDS,"model_count":HOST_MODELS,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
    "special_rules":HOST_RULES,"item_grants":[],
    "attached_hero_rules":HERO_RULES,"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[]}}}"#;

fn rules_json(rules: &[&str]) -> String {
    format!(
        "[{}]",
        rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",")
    )
}

/// Build the host through the REAL profile builder (the static stamp under test).
fn build(host_rules: &[&str], models: i64, hero_rules: Option<&[&str]>, epoch: u32) -> UnitStatic {
    let heroes = match hero_rules {
        Some(h) => format!("[{}]", rules_json(h)),
        None => "[]".to_string(),
    };
    let text = FIXTURE
        .replace("HOST_WOUNDS", &format!("{:?}", vec![1i64; models as usize]))
        .replace("HOST_MODELS", &models.to_string())
        .replace("HOST_RULES", &rules_json(host_rules))
        .replace("HERO_RULES", &heroes);
    let header = read_act_header(&text).expect("fixture header parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("host").expect("host"), epoch)
}

#[test]
fn spell_resistance_reaches_the_resistance_primitive_at_73() {
    let ctx = build(&["Spell Resistance"], 3, None, EPOCH_73_V36).ctx;
    assert!(ctx.regeneration, "Spell Resistance is the Resistance family's 3.6 name");
    assert_eq!(ctx.regen_target, 6, "a non-spell wound is ignored on 6+");
    assert_eq!(ctx.regen_target_spell, 2, "a spell wound is ignored on 2+");
}

#[test]
fn spell_resistance_counts_most_models_at_73() {
    // Two host models carry it, the joined hero does not: 2 of 3 is most.
    let ctx = build(&["Spell Resistance"], 2, Some(&[]), EPOCH_73_V36).ctx;
    assert!(ctx.regeneration, "a plain joined hero does not strip the host majority");
    assert_eq!(ctx.regen_target, 6);
    assert_eq!(ctx.regen_target_spell, 2);
}

#[test]
fn spell_resistance_tie_is_off_at_73() {
    // One host model carries it, the joined hero does not: 1 of 2 is an exact half.
    let ctx = build(&["Spell Resistance"], 1, Some(&[]), EPOCH_73_V36).ctx;
    assert!(!ctx.regeneration, "an exact half is not most models");
    assert_eq!(ctx.regen_target, 0);
    assert_eq!(ctx.regen_target_spell, 0);
}

#[test]
fn resistance_keeps_the_every_model_read_below_73() {
    let below = build(&["Resistance"], 2, Some(&[]), EPOCH_72_PLAYTEST_RULES).ctx;
    assert!(!below.regeneration, "below 73 one plain joined hero strips the every-model read");
    assert_eq!(below.regen_target, 0);

    let at = build(&["Resistance"], 2, Some(&[]), EPOCH_73_V36).ctx;
    assert_eq!(at.regen_target, 6, "at 73 two of three models are most");
    assert_eq!(at.regen_target_spell, 2);
}

#[test]
fn spell_resistance_aura_grants_the_base_at_73() {
    let ctx = build(&["Spell Resistance Aura"], 3, None, EPOCH_73_V36).ctx;
    assert_eq!(ctx.regen_target, 6, "the aura hands its base to the whole unit");
    assert_eq!(ctx.regen_target_spell, 2);
}
