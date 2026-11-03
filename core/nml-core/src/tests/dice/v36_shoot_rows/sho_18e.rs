//! SHO-18e tests (rules 3.6, lane shoot): the AI's expected-wounds estimate is the twin of
//! SHO-18 / SHO-18b. The offensive Surge/Shred alias families (Ferocious, Warbound and their
//! siblings) only pay from a shot over 9" or a charge over 6"; a strike-back pays nothing.
//! `combat::profile_ev` receives the charge distance `melee_ev` is handed (the W1.5b edge gap,
//! 0.0 off a charge), so the estimate reads the SAME `alias_gate` / `surge_alias_rule` /
//! `dist_in` fields the resolver's `resolve_melee_leg` / volley fold read. Below
//! `EPOCH_73_V36` the old unconditional read stays.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::combat::{melee_ev, profile_ev};

/// The real books the registry resolves the two families through: Warbound is a gf
/// war_disciples Shred alias, Ferocious an aof orcs Surge alias. The Blade is 6 attacks, the
/// Rifle 8 (Quality 4 into Defense 4+: 1.5 / 2.0 wounds before the alias).
const SHO_18E_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "warbound":{"unit_id":"warbound","name":"Warbound","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"war_disciples","special_rules":["Warbound"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}]},
  "ferocious":{"unit_id":"ferocious","name":"Ferocious","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"aof","faction_folder":"orcs","special_rules":["Ferocious"],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},
      {"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]},
  "enhanced_ferocious":{"unit_id":"enhanced_ferocious","name":"Enhanced Ferocious",
    "quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"orcs",
    "special_rules":["Ferocious","Enhanced Ferocious"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},
      {"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]},
  "plain_surge":{"unit_id":"plain_surge","name":"Plain Surge","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"war_disciples","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":["Surge"]},
      {"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}]},
  "plain":{"unit_id":"plain","name":"Plain","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"war_disciples","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]},
      {"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

fn sho18e_static(id: &str, epoch: u32) -> UnitStatic {
    let header = read_act_header(SHO_18E_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get(id).expect(id);
    UnitStatic::build_for(&mut reg, p, epoch)
}

/// A charge estimate at `gap_in`, through the live stamp + `melee_ev`'s hand-off.
fn charge_ev(id: &str, epoch: u32, gap_in: f64) -> f64 {
    let us = sho18e_static(id, epoch);
    let attacks: Vec<i64> = us.melee.iter().map(|p| p.attacks).collect();
    melee_ev(&us.melee, &attacks, &us.ctx, &defender(4, 5), true, gap_in)
}

/// A shot estimate at `dist_in`, through the live stamp.
fn shot_ev(id: &str, epoch: u32, dist_in: f64) -> f64 {
    let us = sho18e_static(id, epoch);
    profile_ev(&us.shoot[0], us.shoot[0].attacks, &us.ctx, &defender(4, 5), dist_in, false)
}

fn close(a: f64, b: f64) -> bool {
    (a - b).abs() < 1e-9
}

/// RED on main: a Ferocious charge from 3" pays no Surge at rules 3.6; a 7" charge still does.
#[test]
fn ferocious_charge_pays_over_six_inches_and_not_inside_at_epoch_73() {
    let three = charge_ev("ferocious", EPOCH_73_V36, 3.0);
    let seven = charge_ev("ferocious", EPOCH_73_V36, 7.0);
    let plain = charge_ev("plain", EPOCH_73_V36, 7.0);
    assert!(close(three, plain), "3\" is inside the 6\" gate: {three} vs plain {plain}");
    assert!(seven > three, "7\" is over the gate: {seven} vs {three}");
}

/// RED on main: a Warbound charge from 3" pays no Shred at rules 3.6; a 7" charge still does.
/// Main's estimate is blind to the alias family entirely, so the 7" leg is the RED half too.
#[test]
fn warbound_charge_shreds_over_six_inches_and_not_inside_at_epoch_73() {
    let three = charge_ev("warbound", EPOCH_73_V36, 3.0);
    let seven = charge_ev("warbound", EPOCH_73_V36, 7.0);
    let plain = charge_ev("plain", EPOCH_73_V36, 7.0);
    assert!(close(three, plain), "3\" is inside the 6\" gate: {three} vs plain {plain}");
    assert!(seven > three, "7\" is over the gate: {seven} vs {three}");
}

/// The old side: below 73 both families pay on every charge distance, exactly like the
/// resolution (3" and 7" price the same).
#[test]
fn below_epoch_73_both_families_pay_at_every_charge_distance() {
    for id in ["ferocious", "warbound"] {
        let three = charge_ev(id, EPOCH_72_PLAYTEST_RULES, 3.0);
        let seven = charge_ev(id, EPOCH_72_PLAYTEST_RULES, 7.0);
        let plain = charge_ev("plain", EPOCH_72_PLAYTEST_RULES, 7.0);
        assert!(close(three, seven), "{id} at 72: 3\" and 7\" price the same, {three} vs {seven}");
        assert!(three > plain, "{id} at 72: the alias still pays, {three} vs plain {plain}");
    }
}

/// RED on main: the alias gate is the shot's over-9" band too, not only the charge leg.
#[test]
fn the_aliases_pay_over_nine_inches_shooting_and_not_inside_at_epoch_73() {
    for id in ["ferocious", "warbound"] {
        let seven = shot_ev(id, EPOCH_73_V36, 7.0);
        let ten = shot_ev(id, EPOCH_73_V36, 10.0);
        let plain = shot_ev("plain", EPOCH_73_V36, 7.0);
        assert!(close(seven, plain), "{id}: a 7\" shot is inside the 9\" band, {seven} vs {plain}");
        assert!(ten > seven, "{id}: a 10\" shot is over the band, {ten} vs {seven}");
    }
}

/// The old side: below 73 the same 7" shot pays, so both shot legs stay byte-identical.
#[test]
fn below_epoch_73_the_aliases_pay_at_every_shot_distance() {
    for id in ["ferocious", "warbound"] {
        let seven = shot_ev(id, EPOCH_72_PLAYTEST_RULES, 7.0);
        let ten = shot_ev(id, EPOCH_72_PLAYTEST_RULES, 10.0);
        let plain = shot_ev("plain", EPOCH_72_PLAYTEST_RULES, 10.0);
        assert!(close(seven, ten), "{id} at 72: 7\" and 10\" price the same, {seven} vs {ten}");
        assert!(seven > plain, "{id} at 72: the alias still pays, {seven} vs plain {plain}");
    }
}

/// RED on main: "Enhanced Ferocious" prints no distance gate, so the stamp stores the
/// `-1.0` sentinel and the shot pays its unmodified-6 Surge at 7" too — the dice twin's
/// own read (`dice.rs::alias_fires`). The gated Ferocious at 7", a weapon's own Surge and
/// the over-9" band stay unchanged.
#[test]
fn an_enhanced_ferocious_shot_pays_its_surge_at_seven_inches_at_epoch_73() {
    let seven = shot_ev("enhanced_ferocious", EPOCH_73_V36, 7.0);
    let ten = shot_ev("enhanced_ferocious", EPOCH_73_V36, 10.0);
    let plain = shot_ev("plain", EPOCH_73_V36, 7.0);
    let gated_seven = shot_ev("ferocious", EPOCH_73_V36, 7.0);
    let gated_ten = shot_ev("ferocious", EPOCH_73_V36, 10.0);
    let own = shot_ev("plain_surge", EPOCH_73_V36, 3.0);
    assert!(close(gated_seven, plain), "a plain Ferocious stays gated at 7\": {gated_seven} vs {plain}");
    assert!(seven > plain, "the sentinel opens the 7\" shot: {seven} vs {plain}");
    assert!(close(seven, ten), "the ungated sentinel prices 7\" and 10\" the same: {seven} vs {ten}");
    assert!(gated_ten > gated_seven, "the over-9\" gated alias keeps its band: {gated_ten} vs {gated_seven}");
    assert!(own > plain, "a weapon's own Surge stays unconditional: {own} vs {plain}");
}

/// The old side: at epoch 72 nothing stamps the sentinel (`over_in_gate` returns 9.0), so
/// the Enhanced profile keeps the old read — the 7" shot already paid because main's alias
/// gate is off below 73, and this change must leave that number exactly where it was.
#[test]
fn an_enhanced_ferocious_shot_at_epoch_72_keeps_the_old_read() {
    let us = sho18e_static("enhanced_ferocious", EPOCH_72_PLAYTEST_RULES);
    assert_eq!(us.shoot[0].surge_over_in, 9.0, "below 73 there is no sentinel");
    let seven = shot_ev("enhanced_ferocious", EPOCH_72_PLAYTEST_RULES, 7.0);
    let ten = shot_ev("enhanced_ferocious", EPOCH_72_PLAYTEST_RULES, 10.0);
    let plain = shot_ev("plain", EPOCH_72_PLAYTEST_RULES, 7.0);
    assert!(close(seven, ten), "at 72: 7\" and 10\" price the same, {seven} vs {ten}");
    assert!(seven > plain, "at 72: the old unconditional read still pays, {seven} vs plain {plain}");
}
