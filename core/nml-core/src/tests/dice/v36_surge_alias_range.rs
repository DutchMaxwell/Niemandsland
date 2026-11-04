//! Rules 3.6 row G4-C3: a plain Surge alias pays at any range like the table.
//!
//! The table stamps every Surge DATA ALIAS with its own `over_in` (default
//! `-1.0`, "no distance condition") and opens such an alias at any distance.
//! This row moves the core's stamp to match from `EPOCH_73_V36`: the
//! no-distance sentinel rides a plain alias (natural-6 window, `surge_low` 6)
//! from 73, and the 5s window still needs the printed `low < 6`. Below 73 the
//! stamp is byte-identical to the recorded corpora.
use super::*;
use crate::acts::EPOCH_73_V36;

/// One rifle and one blade, so both stamped arrays exist.
const ALIAS_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},
      {"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

/// A carrier printing `rules` in `aof/halflings`, read at `epoch`.
fn alias_unit(rules: &[&str], epoch: u32) -> UnitStatic {
    alias_unit_in("aof", "halflings", rules, epoch)
}

/// The same carrier in another army book (the gated-alias control).
fn alias_unit_in(system: &str, faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
    let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let tpl = ALIAS_HEADER
        .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"))
        .replace("\"game_system\":\"aof\"", &format!("\"game_system\":\"{system}\""))
        .replace("\"faction_folder\":\"halflings\"", &format!("\"faction_folder\":\"{faction}\""));
    let header = read_act_header(&tpl).expect("ALIAS_HEADER parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), epoch)
}

/// "Lucky" (aof/halflings) is the plain auto-hit alias the book prints with no
/// `over_in`: the entry's `-1.0` sentinel is the data's "any range". From 73
/// the core carries it on the stamped profile; the natural 6s stay the window.
#[test]
fn a_plain_surge_alias_carries_the_any_range_sentinel_from_73() {
    let us = alias_unit(&["Lucky"], EPOCH_73_V36);
    assert!(us.shoot[0].surge, "the plain alias keeps its facet");
    assert_eq!(us.shoot[0].surge_low, 6, "a plain alias keeps the natural 6s");
    assert!(
        us.shoot[0].surge_over_in < 0.0,
        "from 73 a plain alias carries the no-distance sentinel, got {}",
        us.shoot[0].surge_over_in
    );
    assert_eq!(us.melee[0].surge_low, 6, "same window on the melee profile");

    let old = alias_unit(&["Lucky"], EPOCH_73_V36 - 1);
    assert_eq!(old.shoot[0].surge_low, 6, "below 73 the plain 6s window replays");
    assert_eq!(
        old.shoot[0].surge_over_in, 0.0,
        "below 73 the stamp stays the recorded 0.0 (byte-exact replay)"
    );
}

/// End to end on the tray: at 3" the table pays the plain alias's 6s. Seed 6
/// rolls one 6 in 8 dice, so the alias adds exactly one hit from 73. The
/// pre-gate leg keeps the legacy (alias-gate off) any-range read.
#[test]
fn a_plain_surge_alias_pays_one_six_at_three_inches_from_73() {
    let want = Tray::seeded(6).roll(8);
    assert_eq!(want.iter().filter(|&&f| f == 6).count(), 1, "fixture: seed 6 rolls one 6");
    let base = faces_to_hits(&want, 4) as i64;

    let us = alias_unit(&["Lucky"], EPOCH_73_V36);
    let mut t = Tray::seeded(6);
    assert_eq!(
        surge_volley(&[us.shoot[0].clone()], 4, 3.0, true, &mut t).rolls[1].count,
        base + 1,
        "from 73 the sentinel opens the 6 at 3\""
    );

    let old = alias_unit(&["Lucky"], EPOCH_73_V36 - 1);
    let mut t = Tray::seeded(6);
    assert_eq!(
        surge_volley(&[old.shoot[0].clone()], 4, 3.0, true, &mut t).rolls[1].count,
        base + 1,
        "below 73 the legacy alias-gate-off read still pays at 3\""
    );
}

/// The battle-log text of one seed-6 volley (one natural 6 in 8 dice) at `d`.
fn alias_log(us: &UnitStatic, d: f64) -> String {
    let mut t = Tray::seeded(6);
    surge_volley(&[us.shoot[0].clone()], 4, d, true, &mut t).log.join("\n")
}

/// The line names the BOOK rule and, for a plain alias, no distance it does not
/// have: it pays at any range from 73, so a 3" shot must not claim "over 9in".
#[test]
fn a_plain_alias_line_names_no_nine_inch_gate_from_73() {
    let log = alias_log(&alias_unit(&["Lucky"], EPOCH_73_V36), 3.0);
    assert!(log.contains("Lucky"), "the plain alias paid but never named itself, got: {log}");
    assert!(!log.contains("over 9"), "the 3\" plain-alias line still claims a 9\" gate, got: {log}");
}

/// Below 73 the recorded wording stands byte-exact.
#[test]
fn below_73_the_recorded_over_nine_line_stands() {
    let log = alias_log(&alias_unit(&["Lucky"], EPOCH_73_V36 - 1), 3.0);
    assert!(
        log.contains("Lucky: shot from over 9in \u{2014} bonus hits on unmodified 6s"),
        "below 73 the recorded 9in line must stay, got: {log}"
    );
}

/// Control: Devout Boost carries a real 9" condition, so its line keeps the band.
#[test]
fn a_gated_alias_keeps_its_over_nine_line_from_73() {
    let us = alias_unit_in("gff", "blessed_sisters", &["Devout", "Devout Boost"], EPOCH_73_V36);
    let log = alias_log(&us, 10.0);
    assert!(
        log.contains("Devout") && log.contains("from over 9in"),
        "the gated alias lost its 9in band, got: {log}"
    );
}
