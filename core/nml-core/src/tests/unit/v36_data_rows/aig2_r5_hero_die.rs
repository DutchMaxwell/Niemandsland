//! AIG-G2 R5 (release 0.3.15), Rust guard: Unpredictable Shooter on a JOINED HERO. The core's volley rolled ONE
//! Unpredictable die "off the FIRST shooter's context" (the host), so a hero carrying the rule while his host does
//! not fired with no die. From EPOCH_73_V36 each later shooter who carries the rule rolls ONE die for his own
//! profiles when the host rolled none; a host that carries the rule keeps covering the whole unit (one die). The
//! carriers are built the way the game builds them (header profile, real registry, `UnitStatic::build_for` at the
//! epoch under test) and the volley runs through `resolve_volley_with_tray`. Table twin:
//! `test/v36/aig2_r5_unpredictable_hero_test.gd`.
use super::super::*;
use crate::dice::{resolve_volley_with_tray, Shooter, Tray};

/// A one-model aof duchies_of_vinci unit (the book that fields the rule) with a 24" rifle, `rules` as its own.
fn r5_profile(name: &str, rules: &str) -> Profile {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "u":{{"unit_id":"u","name":"{name}","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,
        "caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"duchies_of_vinci",
        "special_rules":{rules},"item_grants":[],"attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
    );
    read_act_header(&tpl).expect("header").profiles.get("u").expect("unit").clone()
}

/// The rule dice of a volley: the count-1 "attack" rolls (every real hit batch here rolls its profile's 2 attacks),
/// as the owners that signed them.
fn r5_rule_dice(host_rules: &str, hero_rules: &str, epoch: u32) -> Vec<String> {
    let mut reg = Registries::new(&repo_root());
    let host = UnitStatic::build_for(&mut reg, &r5_profile("City Guard", host_rules), epoch);
    let hero = UnitStatic::build_for(&mut reg, &r5_profile("Zairetia", hero_rules), epoch);
    let shooters = [
        Shooter { profiles: &host.shoot, keep: &[0], attacks: &[2], att: &host.ctx, owner: "City Guard" },
        Shooter { profiles: &hero.shoot, keep: &[0], attacks: &[2], att: &hero.ctx, owner: "Zairetia" },
    ];
    let def = Ctx { defense: 4, tough: 1, models: 10, quality: 4, ..Default::default() };
    let mut tray = Tray::seeded(7);
    let out = resolve_volley_with_tray(&shooters, &def, "Target", 12.0, 12.0, true, true, true, true, &mut tray);
    out.rolls.iter().filter(|r| r.kind == "attack" && r.count == 1).map(|r| r.owner.to_string()).collect()
}

/// Controls (green before and after): a host carrying the rule rolls its one die for the whole unit; nobody
/// carrying it rolls none; below epoch 73 the first-shooter read stands byte for byte.
#[test]
fn aig2_r5_controls_a_host_die_covers_the_unit_and_a_plain_chain_rolls_none() {
    let rule = r#"["Unpredictable Shooter"]"#;
    assert_eq!(r5_rule_dice(rule, "[]", crate::acts::EPOCH_73_V36), vec!["City Guard".to_string()]);
    assert!(r5_rule_dice("[]", "[]", crate::acts::EPOCH_73_V36).is_empty());
    assert!(r5_rule_dice("[]", rule, crate::acts::EPOCH_73_V36 - 1).is_empty(), "below 73 the hero's rule rolls no die");
}

/// The guard: the host carries nothing, the joined hero carries Unpredictable Shooter -- the volley rolls ONE die,
/// signed by the hero, and none for the host.
#[test]
fn aig2_r5_a_joined_hero_carrying_the_rule_rolls_one_die_from_epoch_73() {
    let dice = r5_rule_dice("[]", r#"["Unpredictable Shooter"]"#, crate::acts::EPOCH_73_V36);
    assert_eq!(dice, vec!["Zairetia".to_string()], "ONE die, the hero's; none for the host's profiles");
}
