//! SHO-03 tests (rules 3.6, lane shoot): Quick Throw lets a unit's Indirect weapons ignore line of
//! sight without a Hold. A mechanics-map entry only: its "Indirect" family entry prints
//! `los_needs_hold` false, and `UnitStatic::build_for` stamps the lift on every Indirect weapon.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// One Indirect mortar of `faction` (`game_system` gf), `rules` as the unit's own special rules.
const MORTAR: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"FACTION",
    "special_rules":RULES,"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Mortar","range":24,"attacks":1,"count":1,"ap":0,
      "rules":["Indirect"]}]}}}"#;

/// The stamped Indirect weapons of a mortar in `faction` carrying `rules`, at `epoch`.
fn mortar_shoot(faction: &str, rules: &str, epoch: u32) -> Vec<ShootProfile> {
    let header = MORTAR.replace("FACTION", faction).replace("RULES", rules);
    let parsed = read_act_header(&header).expect("header parses");
    let mut reg = Registries::new(&repo_root());
    let p = parsed.profiles.get("carrier").expect("carrier");
    UnitStatic::build_for(&mut reg, p, epoch).shoot
}

/// Each of the four book sections that carry Quick Throw resolves the entry.
const BOOKS: [&str; 4] = ["human_inquisition", "ratmen_clans", "dragon_empire", "ratmen"];

/// NEW leg: from 73 a Quick Throw book's moved Indirect shooter needs no Hold for the sight waiver.
#[test]
fn a_quick_throw_indirect_shooter_stamps_no_hold_need_at_epoch_73() {
    for faction in BOOKS {
        let shoot = mortar_shoot(faction, r#"["Quick Throw"]"#, EPOCH_73_V36);
        assert_eq!(shoot.len(), 1, "{faction}: the mortar");
        assert!(!shoot[0].indirect_los_needs_hold,
            "{faction}: Quick Throw lifts the Hold need (RED on main: the entry is missing)");
    }
}

/// CONTROL: the same mortar without Quick Throw still needs a Hold at 73 (passes before and after).
#[test]
fn a_plain_indirect_shooter_still_needs_a_hold_at_epoch_73() {
    let shoot = mortar_shoot("human_inquisition", "[]", EPOCH_73_V36);
    assert!(shoot[0].indirect_los_needs_hold, "no Quick Throw, no lift");
}

/// OLD leg: at 72 the stamp never runs, so the field keeps its default whatever the unit carries.
#[test]
fn the_hold_need_is_not_stamped_at_epoch_72() {
    let plain = mortar_shoot("human_inquisition", "[]", EPOCH_72_PLAYTEST_RULES);
    let quick = mortar_shoot("human_inquisition", r#"["Quick Throw"]"#, EPOCH_72_PLAYTEST_RULES);
    assert!(!plain[0].indirect_los_needs_hold);
    assert!(!quick[0].indirect_los_needs_hold);
}
