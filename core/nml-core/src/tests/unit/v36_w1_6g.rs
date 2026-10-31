//! Rules 3.6 row W1.6g tests (Enhanced names with no rename row); owned by row W1.6g.
//!
//! W1.6g: the Brothers book's "Enhanced Bloodborn" upgrades the base "Bloodborn" so its extra
//! attack draws on an unmodified 5 as well as a 6. Every carrier is the REAL `build_for` product
//! through the real registry, read at the 3.6 epoch.
use super::*;
use crate::acts::EPOCH_73_V36;

/// One rifle and one blade, so both stamped arrays are non-empty.
const ENHANCED_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"blood_brothers",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
      {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

/// A blood_brothers carrier printing `rules`, read at `EPOCH_73_V36`.
fn enhanced_unit(rules: &[&str]) -> UnitStatic {
    let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let tpl = ENHANCED_HEADER.replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
    let header = read_act_header(&tpl).expect("ENHANCED_HEADER parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), EPOCH_73_V36)
}

/// W1.6g, map upgrade (unit.rs Surge block 3b): the base gives the extra attack on 6, the
/// enhancement widens the shooting window to 5-6 through the entry's `surge_low`.
#[test]
fn enhanced_bloodborn_widens_the_extra_attack_to_five() {
    let us = enhanced_unit(&["Bloodborn", "Enhanced Bloodborn"]);
    assert!(us.shoot[0].surge_attack, "Bloodborn's extra attack");
    assert_eq!(us.shoot[0].surge_attack_low, 5, "the entry's surge_low");
    let plain = enhanced_unit(&["Bloodborn"]);
    assert!(plain.shoot[0].surge_attack, "Bloodborn's extra attack");
    assert_eq!(plain.shoot[0].surge_attack_low, 6, "without the enhancement only the 6s draw");
}
