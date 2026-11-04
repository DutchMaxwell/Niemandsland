//! W31-F3/F4 tests (rules 3.6, lane data): the named-hero marker and six rows that sat missing next to
//! mapped siblings. Every unit is built the way the game builds it (a recorded header profile over the
//! real mechanics maps), never with a hand-set flag.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

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

/// Every book that prints the named-hero marker (the gap report's two Unique Hero rows).
const UNIQUE_HERO_BOOKS: [(&str, &[&str]); 2] = [
    ("gf", &["alien_hives", "blessed_sisters", "daemons_of_change", "daemons_of_plague", "dwarf_guilds",
        "eternal_dynasty", "goblin_reclaimers", "high_elf_fleets", "human_defense_force", "jackals",
        "orc_marauders", "ratmen_clans", "robot_legions", "saurian_starhosts"]),
    ("aof", &["beastmen", "daemons_of_lust", "daemons_of_war", "duchies_of_vinci", "dwarves",
        "mummified_undead", "orcs", "ratmen", "saurians", "shadow_stalkers", "vampiric_undead", "wood_elves"]),
];

/// "Unique Hero" resolves in every book that prints it, and the engine still counts the carrier a Hero.
#[test]
fn unique_hero_resolves_as_a_mapped_marker_in_every_book_that_prints_it() {
    let mut reg = Registries::new(&repo_root());
    for (system, books) in UNIQUE_HERO_BOOKS {
        for book in books {
            assert!(reg.rules_for(system).has_primitive(book, "Unique Hero"), "{system}/{book} lacks Unique Hero");
            assert!(carrier(system, book, &["Unique Hero"], EPOCH_73_V36).is_hero, "{system}/{book}: not a Hero");
        }
    }
}

/// Enhanced Watchborn Aura hands the unit Enhanced Watchborn, which pins the Versatile pick's gate open.
#[test]
fn an_enhanced_watchborn_aura_carrier_pins_the_versatile_gate_open_at_73() {
    for book in ["watch_brothers", "watch_prime_brothers"] {
        let us = carrier("gf", book, &["Watchborn", "Enhanced Watchborn Aura"], EPOCH_73_V36);
        assert!(us.ctx.versatile_no_gate, "{book}: the aura must grant Enhanced Watchborn");
        let old = carrier("gf", book, &["Watchborn", "Enhanced Watchborn Aura"], EPOCH_72_PLAYTEST_RULES);
        assert!(!old.ctx.versatile_no_gate, "{book}: below 73 the pick keeps its 9\"/6\" gate");
    }
}

/// Versatile Warrior Aura hands the unit Versatile Warrior: the pick reaches the shooting profile.
#[test]
fn a_versatile_warrior_aura_carrier_gets_the_pick_on_its_weapons_at_73() {
    let us = carrier("aof", "saurians", &["Versatile Warrior Aura"], EPOCH_73_V36);
    assert!(us.shoot[0].versatile_attack, "the aura must grant Versatile Warrior to the rifle");
    assert!(us.melee[0].versatile_attack, "the aura must grant Versatile Warrior to the blade");
}

/// Versatile Warrior Buff stamps a once-per-activation friendly pick, like its Versatile Attack sibling.
#[test]
fn a_versatile_warrior_buff_carrier_offers_the_friendly_grant() {
    let us = carrier("aof", "kingdom_of_angels", &["Versatile Warrior Buff"], EPOCH_73_V36);
    let buff = us.utility_buffs.iter().find(|b| b.name == "Versatile Warrior Buff");
    let buff = buff.expect("the buff must be stamped under its book name");
    assert_eq!((buff.range_in, buff.max_targets, buff.target.as_str()), (12.0, 1, "friendly"));
}

/// Grounded Evasion is the 3.6 spelling of Grounded Stealth: -1 to hit while near terrain.
#[test]
fn a_grounded_evasion_carrier_gets_the_terrain_gated_stealth_alias_at_73() {
    let us = carrier("gf", "machine_cults", &["Grounded Evasion"], EPOCH_73_V36);
    assert_eq!(us.ctx.stealth_alias_penalty, 1, "Grounded Evasion must stamp the -1 alias");
    assert!(us.ctx.stealth_alias_near_terrain, "and keep it gated on terrain within 1\"");
    let twin = carrier("gf", "machine_cults", &["Grounded Stealth"], EPOCH_73_V36);
    assert_eq!(twin.ctx.stealth_alias_penalty, us.ctx.stealth_alias_penalty, "the sibling reads the same");
}

/// Spawn in the Infected Colonies book reads like the four books that already carry it.
#[test]
fn an_infected_colonies_spawn_carrier_may_summon_once_within_six_inches() {
    let us = carrier("gf", "infected_colonies", &["Spawn(Swarm 5)"], EPOCH_73_V36);
    assert_eq!(us.spawn.place_in, 6.0, "the summon lands within 6\"");
    assert!(us.spawn.once_per_game, "once per game");
    let sibling = carrier("gf", "alien_hives", &["Spawn(Swarm 5)"], EPOCH_73_V36);
    assert_eq!(us.spawn.place_in, sibling.spawn.place_in, "same read as the alien_hives sibling");
}

/// Increased Shooting Range in the Ratmen book gives +6" like the gf sibling row, and the Aura keeps its own read.
#[test]
fn a_ratmen_increased_shooting_range_carrier_gets_six_inches_at_73() {
    let us = carrier("aof", "ratmen", &["Increased Shooting Range"], EPOCH_73_V36);
    assert_eq!(us.royal_legion_range_in, 6.0, "the base rule must add 6\" of shooting range");
    let aura = carrier("aof", "ratmen", &["Increased Shooting Range Aura"], EPOCH_73_V36);
    assert_eq!((aura.royal_legion_range_in, aura.royal_legion_charge_in), (6.0, 0.0), "the Aura read stays as it was");
}
