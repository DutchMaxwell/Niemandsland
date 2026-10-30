//! Rules 3.6 row W1.6e tests (Boost -> Enhanced rename, batch 5/6); owned by row W1.6e.
//!
//! W1.6e (D-ENH), batch 5 of the Boost -> Enhanced rename: the 3.6 name stamps exactly the effect
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

/// W1.6e, code literal (unit.rs Bane stamp): the widened save re-roll window over 9", and
/// the volley log names the 3.6 rule.
#[test]
fn enhanced_scrapper_widens_the_bane_window_like_its_3_5_boost() {
    let us = enhanced_unit("gf", "jackals", &["Scrapper", "Enhanced Scrapper"]);
    assert_eq!(us.shoot[0].bane_low, 5, "the entry's reroll_save_from");
    assert_eq!(us.shoot[0].bane_over_in, 9.0, "the entry's over_in");
    assert_eq!(us.shoot[0].bane_rule, "Enhanced Scrapper", "the window names the 3.6 rule");
    let p = [us.shoot[0].clone()];
    let att = Ctx { quality: 4, ..Default::default() };
    let def = Ctx { defense: 5, models: 1, tough: 1, ..Default::default() };
    let strikers = [crate::dice::Shooter { profiles: &p, keep: &[0], attacks: &[64], att: &att, owner: "att" }];
    let mut tray = crate::dice::Tray::seeded(27);
    let shot = crate::dice::resolve_volley_with_tray(
        &strikers, &def, "Target", 12.0, 12.0, true, false, false, false, &mut tray,
    );
    assert!(
        shot.log.iter().any(|l| l.contains("Enhanced Scrapper")),
        "rules-must-log: the volley log prints the 3.6 name"
    );
    let old = enhanced_unit("gf", "jackals", &["Scrapper", "Scrapper Boost"]);
    assert_eq!(old.shoot[0].bane_rule, "", "the 3.5 name is gone (no alias)");
}

/// W1.6e, code literal (unit.rs Fast band): +4"/+4" on top of the base's +2"/+2".
#[test]
fn enhanced_scurry_stacks_its_band_like_its_3_5_boost() {
    let us = enhanced_unit("gf", "ratmen_clans", &["Scurry", "Enhanced Scurry"]);
    let bands = us.move_rule_mods.expect("a move band");
    assert_eq!((bands.advance, bands.rush), (6.0, 6.0), "Scurry 2/2 + Enhanced Scurry 4/4");
}

/// W1.6e, code literals (unit.rs Shielded alias list + its log name): one +1 Defense that
/// replaces the base's gates, and the dice log names the 3.6 rule.
#[test]
fn enhanced_sturdy_shields_like_its_3_5_boost_and_logs_its_3_6_name() {
    let us = enhanced_unit("gf", "dwarf_guilds", &["Sturdy", "Enhanced Sturdy"]);
    assert!(us.ctx.sturdy_boost_gates_guarded, "the upgrade replaces the base's gates");
    assert_eq!(us.ctx.shielded_alias.name(), "Enhanced Sturdy", "rules-must-log: the 3.6 name");
}

/// W1.6e, map-only name (no code literal): the Royal Legion upgrade's range and charge.
#[test]
fn enhanced_royal_legion_stamps_range_and_charge_like_its_3_5_boost() {
    let us = enhanced_unit("aof", "mummified_undead", &["Enhanced Royal Legion"]);
    assert_eq!(us.royal_legion_range_in, 4.0, "the entry's range_bonus_in");
    assert_eq!(us.royal_legion_charge_in, 2.0, "the entry's charge_mod");
}
