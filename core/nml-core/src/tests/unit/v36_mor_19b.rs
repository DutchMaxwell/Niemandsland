//! Rules 3.6 row MOR-19b tests (unit module); owned by lane morale.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// One Ethereal-printing carrier (aof ghostly_undead, Teleport primitive) at `epoch`. The rule
/// name and faction are swapped so the REAL registry entry resolves.
const ETHEREAL_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"ghostly_undead",
    "special_rules":["Ethereal"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

fn ethereal_bands(rule: &str, faction: &str, epoch: u32) -> Option<Bands> {
    let tpl = ETHEREAL_HEADER
        .replace(
            "\"special_rules\":[\"Ethereal\"]",
            &format!("\"special_rules\":[\"{rule}\"]"),
        )
        .replace(
            "\"faction_folder\":\"ghostly_undead\"",
            &format!("\"faction_folder\":\"{faction}\""),
        );
    let header = read_act_header(&tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), epoch)
        .move_rule_mods
}

/// Rules 3.6 (MOR-19b): the placement is optional, so the static band carries NO -6"/-6" at
/// epoch 73 — the penalty is re-applied per activation only while the model was placed.
/// Below 73 the static fold keeps today's always-on numbers.
#[test]
fn ethereal_static_bands_drop_the_minus_six_at_epoch_73() {
    assert_eq!(
        ethereal_bands("Ethereal", "ghostly_undead", EPOCH_73_V36),
        None,
        "epoch 73: the optional placement leaves the static bands at 6\"/12\" (RED before the fix)"
    );
    assert_eq!(
        ethereal_bands("Ethereal", "shadow_stalkers", EPOCH_73_V36),
        None,
        "epoch 73: the second Ethereal-printing faction drops the static penalty too"
    );
}

#[test]
fn ethereal_static_bands_keep_the_minus_six_at_epoch_72() {
    assert_eq!(
        ethereal_bands("Ethereal", "ghostly_undead", EPOCH_72_PLAYTEST_RULES),
        Some(Bands { advance: -6.0, rush: -6.0, ..Default::default() }),
        "epoch 72: today's always-on -6/-6 stays byte-exact"
    );
}

#[test]
fn teleport_stays_out_of_the_static_bands_at_epoch_73() {
    assert_eq!(
        ethereal_bands("Teleport", "vampiric_undead", EPOCH_73_V36),
        None,
        "the real Teleport rule shares the primitive with NO band mods"
    );
}
