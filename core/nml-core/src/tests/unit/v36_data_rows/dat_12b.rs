//! DAT-12b-fix tests (rules 3.6, lane data): an "Enhanced <X>" rule drops X's
//! distance condition and keeps X's BASE trigger window. The data spells
//! `over_in: 0` (no distance) and drops the widened window key; the readers
//! honour the 0 only from `EPOCH_73_V36`, so an epoch-72 record keeps the 3.5
//! Boost read (5s past 9"). The Shred half (Infected/Warbound/Destroyer) is a
//! named follow-up; this row covers the Surge half.
use super::super::*;
use crate::acts::EPOCH_73_V36;

/// One rifle and one blade, so both stamped arrays are non-empty.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},
      {"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

/// A carrier printing `rules` in `<system>/<faction>`, read at `epoch`.
fn carrier(system: &str, faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
    let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let tpl = HEADER
        .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
        .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
        .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
    let header = read_act_header(&tpl).expect("HEADER parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), epoch)
}

/// One volley with profile 0, seed 6 (one 6 and two 5s in eight dice). The
/// save batch's `count` is the hit count, so the Surge bonus is observable.
fn hits_at(us: &UnitStatic, dist: f64) -> i64 {
    let p = [us.shoot[0].clone()];
    let att = Ctx { quality: 4, ..Default::default() };
    let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
    let strikers = [crate::dice::Shooter { profiles: &p, keep: &[0], attacks: &[8], att: &att, owner: "att" }];
    let mut tray = crate::dice::Tray::seeded(6);
    crate::dice::resolve_volley_with_tray(
        &strikers, &def, "Target", dist, dist, true, true, false, false, &mut tray,
    ).rolls[1].count
}

/// (a) Epoch 73: Enhanced Ferocious drops the distance condition and keeps the
/// base 6s window, so it pays at 6".
#[test]
fn an_enhanced_ferocious_carrier_fires_at_six_inches_at_epoch_73() {
    let us = carrier("aof", "orcs", &["Ferocious", "Enhanced Ferocious"], EPOCH_73_V36);
    assert_eq!(us.shoot[0].surge_low, 6, "the base Ferocious window, not the Boost's 5");
    assert_eq!(us.shoot[0].surge_over_in, -1.0, "an explicit 0 means no distance condition");
    let plain = carrier("aof", "orcs", &[], EPOCH_73_V36);
    assert_eq!(hits_at(&us, 6.0), hits_at(&plain, 6.0) + 1, "at 6\" the unmodified 6 pays");
}

/// (b) The base window is sixes only: a 5 never pays, even past 9".
#[test]
fn an_enhanced_ferocious_five_never_pays_at_epoch_73() {
    let us = carrier("aof", "orcs", &["Ferocious", "Enhanced Ferocious"], EPOCH_73_V36);
    let plain = carrier("aof", "orcs", &[], EPOCH_73_V36);
    assert_eq!(hits_at(&us, 10.0), hits_at(&plain, 10.0) + 1, "the 6 pays, the two 5s stay dead");
}

/// (c) Epoch 72 is byte-identical to the pre-fix read: the 3.5 Boost window
/// (5s) strictly past 9".
#[test]
fn an_enhanced_ferocious_carrier_keeps_the_boost_read_at_epoch_72() {
    let us = carrier("aof", "orcs", &["Ferocious", "Enhanced Ferocious"], 72);
    assert_eq!(us.shoot[0].surge_low, 5, "the old Boost window");
    assert_eq!(us.shoot[0].surge_over_in, 9.0, "the old default gate");
    let plain = carrier("aof", "orcs", &[], 72);
    assert_eq!(hits_at(&us, 6.0), hits_at(&plain, 6.0) + 1, "inside 9\": the 6 alone");
    assert_eq!(hits_at(&us, 10.0), hits_at(&plain, 10.0) + 3, "past 9\": the 6 and both 5s");
}
