//! Rules 3.6 row W1.6f tests (Boost -> Enhanced rename, batch 6/6); owned by row W1.6f.
//!
//! W1.6f (D-ENH), batch 6 of the Boost -> Enhanced rename: the 3.6 name stamps exactly the effect
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

/// W1.6f, code literals (unit.rs Versatile Attack walk): with the base carried, the upgrade
/// takes both picks at once, and the stamped log name is the 3.6 rule.
#[test]
fn enhanced_vinci_tech_takes_both_picks_like_its_3_5_boost_and_logs_its_3_6_name() {
    let us = enhanced_unit("aof", "duchies_of_vinci", &["Vinci Tech", "Enhanced Vinci Tech"]);
    assert!(us.shoot[0].versatile_both, "both picks at once");
    assert_eq!(us.shoot[0].versatile_name, "Enhanced Vinci Tech", "rules-must-log: the 3.6 name");
    let old = enhanced_unit("aof", "duchies_of_vinci", &["Vinci Tech", "Vinci Tech Boost"]);
    assert!(!old.shoot[0].versatile_both, "the 3.5 name is gone (no alias)");
}

/// W1.6f, code literals (unit.rs Bounding read): the placement rolls two dice.
#[test]
fn enhanced_wave_step_reads_its_two_dice_placement_like_its_3_5_boost() {
    let us = enhanced_unit("aof", "deep_sea_elves", &["Wave-Step", "Enhanced Wave-Step"]);
    assert_eq!(us.bounding_dice, 2, "the entry's place_die 2d3");
}

/// W1.6f, code literal (unit.rs Shot Modifier names): a flat +1 to hit when shooting.
#[test]
fn enhanced_targeting_visor_adds_a_flat_plus_one_like_its_3_5_boost() {
    let us = enhanced_unit("gf", "dao_union", &["Enhanced Targeting Visor"]);
    assert_eq!(us.shoot[0].hit_bonus, 1, "the entry's flat hit_bonus");
    assert_eq!(us.shoot[0].hit_bonus_over9, 0, "no over_in");
    assert_eq!(us.melee[0].hit_bonus, 0, "shooting only");
}

/// W1.6f, map-only name (no code literal): the Shred upgrade widens the window to 2s.
#[test]
fn enhanced_warbound_widens_the_shred_window_like_its_3_5_boost() {
    let us = enhanced_unit("gf", "war_disciples", &["Warbound", "Enhanced Warbound"]);
    assert_eq!(us.shoot[0].shred_low, 2, "the entry's extra_wound_save_low window");
}

/// EPOCH_96_PARITY_BATCH (lead ruling 22.11., AoF 3.6 Duchies of Vinci: "either AP(+1) or +1 to hit ... always"):
/// from 96 a Vinci Tech bearer with the Enhanced rule makes ONE pick, inside 9 in as well; at 95 it took both arms past 9 in only.
#[test]
fn enhanced_vinci_tech_makes_one_pick_at_any_range_from_96() {
    let build = |epoch: u32| {
        let printed = r#""Vinci Tech","Enhanced Vinci Tech""#;
        let tpl = ENHANCED_HEADER
            .replace("\"game_system\":\"gf\"", "\"game_system\":\"aof\"")
            .replace("\"faction_folder\":\"robot_legions\"", "\"faction_folder\":\"duchies_of_vinci\"")
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"))
            .replace("\"attacks\":2", "\"attacks\":8");
        let header = read_act_header(&tpl).expect("ENHANCED_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, header.profiles.get("carrier").expect("carrier"), epoch)
    };
    // (to-hit target, Defense target) of one 8-dice rifle volley at a Defense 5 target `dist_in` away.
    let shot = |us: &UnitStatic, dist_in: f64| {
        let profiles = [us.shoot[0].clone()];
        let def = Ctx { defense: 5, models: 5, tough: 1, ..Default::default() };
        let strikers = [crate::dice::Shooter { profiles: &profiles, keep: &[0], attacks: &[8], att: &us.ctx, owner: "att" }];
        let mut tray = crate::dice::Tray::seeded(6);
        let out = crate::dice::resolve_volley_with_tray(&strikers, &def, "Target", dist_in, dist_in, true, false, false, false, &mut tray);
        let defense = out.rolls.iter().find(|r| r.kind == "defense").map(|r| r.target).expect("some hits");
        (out.rolls[0].target, defense)
    };
    let at96 = build(crate::acts::EPOCH_96_PARITY_BATCH);
    assert!(!at96.shoot[0].versatile_both, "96: never both arms");
    assert!(at96.ctx.versatile_no_gate, "96: the pick is 'always'");
    for dist in [6.0, 12.0] {
        let (hit, def) = shot(&at96, dist);
        assert!((hit == 3) != (def == 6), "96 at {dist} in: exactly one arm (+1 to hit -> 3+, or AP(+1) -> 6+), got {hit}/{def}");
    }
    let at95 = build(crate::acts::EPOCH_96_PARITY_BATCH - 1);
    assert_eq!(shot(&at95, 12.0), (3, 6), "95 past 9 in: both arms, byte-exact");
    assert_eq!(shot(&at95, 6.0), (4, 5), "95 inside 9 in: nothing");
}
