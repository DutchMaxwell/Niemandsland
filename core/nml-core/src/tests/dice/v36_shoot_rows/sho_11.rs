use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

// SHO-11 (rules 3.6): the four data rows on the conditional-AP hook. The fixtures
// carry each rule on a weapon in the book that prints it, so the REAL registry
// decides the params; no test hand-builds the field the row is about.

const SHO_11_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "destructive":{"unit_id":"sho11_destructive","name":"Destructive","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"elven_jesters",
    "special_rules":[],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":["Destructive"]}]},
  "shatter":{"unit_id":"sho11_shatter","name":"Shatter","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":[],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":["Shatter"]}]},
  "disintegrate":{"unit_id":"sho11_disintegrate","name":"Disintegrate","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"custodian_brothers",
    "special_rules":[],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":["Disintegrate"]}]},
  "purge":{"unit_id":"sho11_purge","name":"Purge","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
    "special_rules":[],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":["Purge"]}]}}}"#;

fn sho_11_static(id: &str, epoch: u32) -> crate::unit::UnitStatic {
    let header = crate::acts::read_act_header(SHO_11_HEADER).expect("header");
    let mut reg = crate::rules::Registries::new(&format!("{}/../..", env!("CARGO_MANIFEST_DIR")));
    let p = header.profiles.get(id).expect(id);
    crate::unit::UnitStatic::build_for(&mut reg, p, epoch)
}

fn target(above_half_strength: bool) -> Ctx {
    Ctx { defense: 4, models: 5, tough: 1, above_half_strength, ..Default::default() }
}

/// Destructive: the 3.6 entry prices AP(+1) against a target still above half
/// strength through the generic condition, and the old unmodified-six AP(+4)
/// stops at the wave. The epoch-72 control keeps the 3.5 on-6 reading.
#[test]
fn destructive_trades_the_on_six_ap_for_the_above_half_condition_at_73() {
    let old = sho_11_static("destructive", EPOCH_72_PLAYTEST_RULES);
    let new = sho_11_static("destructive", EPOCH_73_V36);
    assert!(old.melee[0].destructive, "below the wave the 3.5 flag still drives the sixes");
    assert!(!new.melee[0].destructive, "from 73 the fixed on-6 AP is gone");
    let six = crate::combat::hit_ev(&new.melee[0], true, &target(true));
    let six_old = crate::combat::hit_ev(&old.melee[0], true, &target(true));
    assert!(six_old > six, "the 3.5 six saved worse than the 3.6 six");
    let spec = new.melee[0].cond_ap.first().expect("the 3.6 entry stamps a condition");
    assert_eq!(spec.condition, "above_half_strength");
    assert_eq!(spec.ap_bonus, 1);
    let high = crate::combat::profile_ev(&new.melee[0], 8, &new.ctx, &target(true), 0.0, false);
    let low = crate::combat::profile_ev(&new.melee[0], 8, &new.ctx, &target(false), 0.0, false);
    assert!(high > low, "AP(+1) above half strength must raise the expected wounds");
}

/// Shatter: the 3.6 text is the old six-to-hit shape, AP(+3) on the unmodified
/// sixes — an `on6_ap` param, not the 3.5 Tough-3 condition.
#[test]
fn shatter_stamps_ap_three_on_the_unmodified_sixes() {
    let us = sho_11_static("shatter", EPOCH_73_V36);
    assert_eq!(us.melee[0].on6_ap, 3, "Shatter's 3.6 bonus is an on-6 AP upgrade");
    assert!(us.melee[0].cond_ap.is_empty(), "no target condition rides the 3.6 Shatter entry");
    let six = crate::combat::hit_ev(&us.melee[0], true, &target(true));
    let plain = crate::combat::hit_ev(&us.melee[0], false, &target(true));
    assert!(six > plain, "a six must save worse");
}

/// Disintegrate: Tough 3+ is the 3.6 condition (not the 3.5 Defense arm), and
/// the Regeneration bypass still stamps the carrier's rule name.
#[test]
fn disintegrate_conditions_on_tough_and_keeps_the_regeneration_bypass() {
    let us = sho_11_static("disintegrate", EPOCH_73_V36);
    let spec = us.melee[0].cond_ap.first().expect("Disintegrate stamps a condition");
    assert_eq!(spec.condition, "vs_tough_ge");
    assert_eq!(spec.threshold, 3);
    assert_eq!(spec.ap_bonus, 2);
    assert!(spec.bypass_regen);
    assert_eq!(us.melee[0].regen_bypass_rule, "Disintegrate");
    let tough = Ctx { tough: 3, ..target(true) };
    let soft = Ctx { tough: 2, ..target(true) };
    let high = crate::combat::profile_ev(&us.melee[0], 8, &us.ctx, &tough, 0.0, false);
    let low = crate::combat::profile_ev(&us.melee[0], 8, &us.ctx, &soft, 0.0, false);
    assert!(high > low, "AP(+2) against Tough 3+ must raise the expected wounds");
}

/// Purge: a new row that prices AP(+2) against a Shaken or Fatigued target.
#[test]
fn purge_prices_ap_two_against_a_shaken_or_fatigued_target() {
    let us = sho_11_static("purge", EPOCH_73_V36);
    let spec = us.melee[0].cond_ap.first().expect("Purge stamps a condition");
    assert_eq!(spec.condition, "shaken_or_fatigued");
    assert_eq!(spec.ap_bonus, 2);
    let shaken = Ctx { shaken_or_fatigued: true, ..target(true) };
    let steady = target(true);
    let armed = crate::combat::profile_ev(&us.melee[0], 8, &us.ctx, &shaken, 0.0, false);
    let plain = crate::combat::profile_ev(&us.melee[0], 8, &us.ctx, &steady, 0.0, false);
    assert!(armed > plain, "AP(+2) against a Shaken target must raise the expected wounds");
}
