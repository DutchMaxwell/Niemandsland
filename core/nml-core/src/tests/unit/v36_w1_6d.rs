//! Rules 3.6 row W1.6d tests (Boost -> Enhanced rename, batch 4/6); owned by row W1.6d.
//!
//! W1.6d (D-ENH), batch 4 of the Boost -> Enhanced rename: the 3.6 name stamps exactly the effect
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

/// W1.6d, code literals (unit.rs Evasive fold): the always -1 to hit, the base's over-9"
/// leg stood down, and the volley log names the 3.6 rule.
#[test]
fn enhanced_empyrean_spirit_makes_the_minus_one_unconditional_like_its_3_5_boost() {
    let us = enhanced_unit("aof", "ghostly_undead", &["Empyrean Spirit", "Enhanced Empyrean Spirit"]);
    assert!(us.ctx.evasive, "the 3.6 name folds into evasive");
    assert_eq!(us.ctx.stealth_alias_penalty, 0, "the base's conditional leg stands down");
    assert_eq!(us.ctx.evasive_alias_name, "Enhanced Empyrean Spirit", "the fold names the 3.6 rule");
    let profiles = [us.shoot[0].clone()];
    let att = Ctx { quality: 4, ..Default::default() };
    let strikers = [crate::dice::Shooter {
        profiles: &profiles, keep: &[0], attacks: &[64], att: &att, owner: "att",
    }];
    let mut tray = crate::dice::Tray::seeded(27);
    let shot = crate::dice::resolve_volley_with_tray(
        &strikers, &us.ctx, "Target", 6.0, 6.0, false, false, false, false, &mut tray,
    );
    assert_eq!(shot.rolls[0].target, 5, "inside 9\": Quality 4+ becomes 5+");
    assert!(
        shot.log.iter().any(|l| l.contains("Enhanced Empyrean Spirit")),
        "rules-must-log: the volley log prints the 3.6 name"
    );
    let old = enhanced_unit("aof", "ghostly_undead", &["Empyrean Spirit", "Empyrean Spirit Boost"]);
    assert!(!old.ctx.evasive, "the 3.5 name is gone (no alias)");
}

/// W1.6d, code literal (unit.rs Bane stamp): the widened save re-roll window over 9".
#[test]
fn enhanced_mischievous_widens_the_bane_window_like_its_3_5_boost() {
    let us = enhanced_unit("gf", "goblin_reclaimers", &["Mischievous", "Enhanced Mischievous"]);
    assert_eq!(us.shoot[0].bane_low, 5, "the entry's reroll_save_low");
    assert_eq!(us.shoot[0].bane_over_in, 9.0, "the entry's over_in");
    assert_eq!(us.shoot[0].bane_rule, "Enhanced Mischievous", "the window names the 3.6 rule");
}

/// W1.6d, code literal (unit.rs aura channel list): the aura hands its base to the carrier,
/// and every save batch against it eats 1 AP.
#[test]
fn an_enhanced_ossified_aura_hands_its_base_like_its_3_5_boost_aura() {
    let us = enhanced_unit("aof", "ossified_undead", &["Enhanced Ossified Aura"]);
    assert_eq!(us.ctx.fortified_boost_ap, 1, "the granted base's incoming_ap_reduction");
}

/// W1.6d, map-only name (no code literal): the Regeneration upgrade ignores wounds on 5+.
#[test]
fn enhanced_plaguebound_ignores_wounds_on_a_five_like_its_3_5_boost() {
    let us = enhanced_unit("gf", "plague_disciples", &["Plaguebound", "Enhanced Plaguebound"]);
    assert_eq!(us.ctx.regen_target, 5, "the entry's ignore_target");
}
