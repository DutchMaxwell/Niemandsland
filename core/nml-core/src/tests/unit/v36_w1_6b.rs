//! Rules 3.6 row W1.6b tests (Boost -> Enhanced rename, batch 2/6); owned by row W1.6b.
//!
//! W1.6b (D-ENH), batch 2 of the Boost -> Enhanced rename: the 3.6 name stamps exactly the effect
//! the 3.5 "<X> Boost" stamped; the 3.5 name is gone (no alias). Every carrier is the REAL
//! `build_for` product through the real registry, read at the 3.6 epoch.
use super::*;
use crate::acts::EPOCH_73_V36;

/// One rifle and one blade, so both stamped arrays are non-empty.
const ENHANCED_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
      {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

/// A carrier printing `rules` in `<system>/<faction>`, read at `EPOCH_73_V36`.
fn enhanced_unit(system: &str, faction: &str, rules: &[&str]) -> UnitStatic {
    let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let tpl = ENHANCED_HEADER
        .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
        .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
        .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
    let header = read_act_header(&tpl).expect("ENHANCED_HEADER parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), EPOCH_73_V36)
}

/// Every stamped conditional-AP form whose condition is `cond`, ranged and melee.
fn forms_with<'a>(us: &'a UnitStatic, cond: &str) -> Vec<&'a CondAp> {
    us.shoot.iter().chain(us.melee.iter()).flat_map(|sp| sp.cond_ap.iter())
        .filter(|c| c.condition == cond).collect()
}

/// W1.6b, code literals (unit.rs Piercing Hunter walk): the always AP(+1) leg replaces the
/// base's two conditional legs, and the volley log names the 3.6 rule.
#[test]
fn enhanced_havocbound_stamps_the_always_leg_like_its_3_5_boost() {
    let us = enhanced_unit("gf", "havoc_brothers", &["Havocbound", "Enhanced Havocbound"]);
    let always = forms_with(&us, "always");
    assert_eq!(always.len(), 2, "the always leg on both stamped profiles");
    assert_eq!(always[0].ap_bonus, 1, "AP(+1)");
    assert_eq!(always[0].name, "Enhanced Havocbound", "the form names the 3.6 rule");
    assert!(forms_with(&us, "on_charge").is_empty(), "replaces the charge leg");
    let p = [us.shoot[0].clone()];
    let att = Ctx { quality: 4, ..Default::default() };
    let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
    let strikers = [crate::dice::Shooter { profiles: &p, keep: &[0], attacks: &[16], att: &att, owner: "att" }];
    let mut tray = crate::dice::Tray::seeded(27);
    let shot = crate::dice::resolve_volley_with_tray(
        &strikers, &def, "Target", 6.0, 6.0, true, false, false, false, &mut tray,
    );
    assert!(
        shot.log.iter().any(|l| l.contains("Enhanced Havocbound: AP(+1)")),
        "rules-must-log: the volley log prints the 3.6 name"
    );
    let old = enhanced_unit("gf", "havoc_brothers", &["Havocbound", "Havocbound Boost"]);
    assert!(forms_with(&old, "always").is_empty(), "the 3.5 name is gone (no alias)");
}

/// W1.6b, code literal (unit.rs Hit & Run band): the 6" move instead of the base's 3".
#[test]
fn enhanced_guerrilla_moves_six_inches_like_its_3_5_boost() {
    let us = enhanced_unit("gf", "rebel_guerrillas", &["Guerrilla", "Enhanced Guerrilla"]);
    assert_eq!(us.hit_and_run_move_in, 6.0, "the entry's move_in");
    assert_eq!(us.hit_and_run_rule, "Enhanced Guerrilla", "the band names the 3.6 rule");
}

/// W1.6b, code literal (unit.rs Fast band): +4"/+4" on top of the base's +0"/+2" (DAT-10).
#[test]
fn enhanced_highborn_stacks_its_band_like_its_3_5_boost() {
    let us = enhanced_unit("gf", "high_elf_fleets", &["Highborn", "Enhanced Highborn"]);
    let bands = us.move_rule_mods.expect("a move band");
    assert_eq!((bands.advance, bands.rush), (4.0, 6.0), "Highborn 0/2 + Enhanced Highborn 4/4");
}

/// W1.6b, map-only name (no code literal): the Surge upgrade counts 5s past 9".
#[test]
fn enhanced_ferocious_widens_the_surge_like_its_3_5_boost() {
    let us = enhanced_unit("aof", "orcs", &["Ferocious", "Enhanced Ferocious"]);
    assert_eq!(us.melee[0].surge_low, 5, "the entry's surge_low");
    assert_eq!(us.melee[0].surge_over_in, 9.0, "the entry's over_in");
}
