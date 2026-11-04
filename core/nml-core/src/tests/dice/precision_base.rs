use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

// ------ W31-F2: Precision Charge / Precision Fighter, the model-level BASES (rules 3.6) ------
//
// "This model gets +1 to hit rolls when charging" / "... in melee". The Aura forms already pay the
// carrier; the import also copies the base name onto every member of the aura's unit. Units are built
// the way the game builds them: a recorded header profile over the real mechanics maps.

const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"orc_marauders",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
      {"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

fn carrier(system: &str, faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
    let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let tpl = HEADER
        .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
        .replace("\"faction_folder\":\"orc_marauders\"", &format!("\"faction_folder\":\"{faction}\""))
        .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
    let header = read_act_header(&tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), epoch)
}

/// The to-hit target of the carrier's blade (Quality 4+) in melee.
fn target_of(us: &UnitStatic, charging: bool) -> i64 {
    melee_hit_target(&us.melee[0], &us.ctx, &defender(4, 5), charging, 0, 0.0, false).0
}

/// The battle-log lines of one two-attack strike.
fn log_of(us: &UnitStatic, charging: bool) -> Vec<String> {
    let p = [us.melee[0].clone()];
    let mut tray = Tray::seeded(27);
    let strikers = [striker(&p, &[0], &[2], &us.ctx)];
    resolve_melee_with_tray(&strikers, &defender(4, 5), "Target", charging, true, true, &mut tray).log
}

/// The three books that print a base: (system, book, rule, pays on a plain strike too).
const BASES: [(&str, &str, &str, bool); 3] = [
    ("gf", "orc_marauders", "Precision Charge", false),
    ("aof", "dwarves", "Precision Charge", false),
    ("gf", "eternal_dynasty", "Precision Fighter", true),
];

/// (a) At 73 a carrier of the base hits one better: Precision Charge only on a charge, Precision Fighter on
/// every melee strike. RED on main: the base has no map row, so both targets stay 4+.
#[test]
fn a_base_carrier_hits_one_better_at_73() {
    for (system, book, rule, every_strike) in BASES {
        let us = carrier(system, book, &[rule], EPOCH_73_V36);
        let plain = if every_strike { 3 } else { 4 };
        assert_eq!(target_of(&us, false), plain, "{system}/{book}: {rule} on a plain strike");
        assert_eq!(target_of(&us, true), 3, "{system}/{book}: {rule} on a charge");
    }
}

/// (b) The base names itself in the battle log whenever it pays, and stays silent when it does not.
#[test]
fn a_base_carrier_names_the_rule_in_the_battle_log_when_it_pays() {
    for (system, book, rule, every_strike) in BASES {
        let us = carrier(system, book, &[rule], EPOCH_73_V36);
        let named = |charging: bool| log_of(&us, charging).iter().any(|l| l.starts_with(rule));
        assert!(named(true), "{system}/{book}: {rule} must name itself on a charge");
        assert_eq!(named(false), every_strike, "{system}/{book}: {rule} on a plain strike");
    }
}

/// (c) Below 73 the base reads nothing: the epoch-72 targets and log stay as they were.
#[test]
fn a_base_carrier_is_unchanged_below_73() {
    for (system, book, rule, _) in BASES {
        let us = carrier(system, book, &[rule], EPOCH_72_PLAYTEST_RULES);
        assert_eq!((target_of(&us, false), target_of(&us, true)), (4, 4), "{system}/{book}: {rule} at 72");
        assert!(!log_of(&us, true).iter().any(|l| l.starts_with(rule)), "{system}/{book}: {rule} logs at 72");
    }
}

/// (d) The control that caught the double count in the earlier data row: a model that carries the Aura AND its
/// expanded base gets +1 once at 73 (the Aura pays, the base stands down), never +2; below 73 the Aura alone
/// pays exactly as before.
#[test]
fn an_aura_carrier_with_the_expanded_base_counts_the_bonus_once() {
    for (system, book, base, every_strike) in BASES {
        let both = [base, &format!("{base} Aura")[..]].map(String::from);
        let rules: Vec<&str> = both.iter().map(String::as_str).collect();
        let aura = carrier(system, book, &rules[1..], EPOCH_73_V36);
        let us = carrier(system, book, &rules, EPOCH_73_V36);
        let plain = if every_strike { 3 } else { 4 };
        assert_eq!((target_of(&aura, false), target_of(&aura, true)), (plain, 3), "{book}: the Aura alone");
        assert_eq!((target_of(&us, false), target_of(&us, true)), (plain, 3), "{book}: Aura + base counts once");
        let old = carrier(system, book, &rules, EPOCH_72_PLAYTEST_RULES);
        assert_eq!((target_of(&old, false), target_of(&old, true)), (plain, 3), "{book}: at 72 the Aura pays alone");
    }
}

/// (e) Model scope: the bonus is read off the attacking member's OWN profile. A host that does not carry the
/// base keeps 4+ while the joined hero that carries it hits at 3+.
#[test]
fn only_the_carrier_member_gets_the_bonus() {
    let host = carrier("gf", "eternal_dynasty", &[], EPOCH_73_V36);
    let hero = carrier("gf", "eternal_dynasty", &["Hero", "Precision Fighter"], EPOCH_73_V36);
    assert_eq!(target_of(&host, true), 4, "the host without the rule");
    assert_eq!(target_of(&hero, true), 3, "the hero with the rule");
}
