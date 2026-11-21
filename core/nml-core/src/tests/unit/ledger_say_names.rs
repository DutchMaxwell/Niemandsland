//! Coverage ledger, AI shoot door (lane covfix-lines, 21.11.): the names the door's tray lines carry, read off the REAL `build_for` product
//! through the real registry. Lines only: the recorded log (`ShootProfile::versatile_name`) keeps its own names, no die moves.
use super::*;
use crate::acts::EPOCH_73_V36;
use crate::Tray;

/// One rifle and one blade, so both stamped arrays are non-empty.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
      {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

/// A carrier printing `rules` in `<system>/<faction>`, read at `EPOCH_73_V36`.
fn carrier(system: &str, faction: &str, rules: &[&str]) -> UnitStatic {
    let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let tpl = HEADER
        .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
        .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
        .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
    let header = read_act_header(&tpl).expect("HEADER parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), EPOCH_73_V36)
}

/// Ledger 2 (21 cells): the table's pick line names the book rule the bearer carries (`primitive_book_name`: the first rule of the
/// Versatile Attack family in the unit's order, whatever its spelling); the core knew three spellings and said "Versatile Attack" for the
/// rest (Versatile Warrior, Enhanced Watchborn, Enhanced Vinci Tech without Vinci Tech). RED on main: the say name did not exist.
#[test]
fn the_versatile_pick_line_names_the_first_book_rule_of_the_bearer() {
    for (system, faction, rule) in [("aof", "human_empire", "Versatile Warrior"), ("gf", "watch_brothers", "Enhanced Watchborn"),
        ("aof", "duchies_of_vinci", "Enhanced Vinci Tech")] {
        let us = carrier(system, faction, &[rule]);
        assert_eq!(us.shoot[0].versatile_say_name, rule, "{system}/{faction}");
        assert_eq!(us.melee[0].versatile_say_name, rule, "the melee array carries it too");
    }
    // The first in the unit's order, as the table's walk; the recorded log's name stays its own (the upgrade's, here).
    let both = carrier("aof", "duchies_of_vinci", &["Vinci Tech", "Enhanced Vinci Tech"]);
    assert_eq!(both.shoot[0].versatile_say_name, "Vinci Tech");
    assert_eq!(both.shoot[0].versatile_name, "Enhanced Vinci Tech", "no replay moves: the recorded name is the old read");
    assert!(carrier("gf", "robot_legions", &[]).shoot[0].versatile_say_name.is_empty(), "no family rule, no name");
}

/// The recorded line keeps the old name, the tray's line says the book rule; with no say name both say the same.
#[test]
fn the_tray_says_the_book_rule_and_the_recorded_log_keeps_its_name() {
    let mut log = Vec::new();
    let mut tray = Tray::supplied(Vec::new());
    crate::sim::say_versatile_pick("Versatile Attack", "Versatile Warrior", "Unit", false, 1, &mut log, Some(&mut tray), EPOCH_73_V36);
    assert_eq!(log, ["Versatile Attack: Unit picks +1 to hit for this activation"]);
    let said: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
    assert_eq!(said, ["Versatile Warrior: Unit picks +1 to hit for this activation"]);
    let mut tray = Tray::supplied(Vec::new());
    crate::sim::say_versatile_pick("Watchborn", "", "Unit", true, 1, &mut Vec::new(), Some(&mut tray), EPOCH_73_V36);
    assert_eq!(tray.all_lines().into_iter().map(|l| l.text).collect::<Vec<_>>(), ["Watchborn: Unit picks AP(+1) for this activation"]);
}

