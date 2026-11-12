//! Epoch 75 (`EPOCH_75_TABLE_FIXES`, table PR #2615): an "Enhanced X" Shred entry carried with
//! its base pays unmodified Defense 1s at ANY distance on a shot and on a charge, never widens
//! the save window to 1-2, and a strike-back keeps the base gate (pays nothing). Below 75 the
//! 3.5 Boost read replays. Dice are seeded; "pays" sums many seeds, "equal" is per seed.
use super::super::*;
use crate::acts::{EPOCH_74_CLIMB_COST, EPOCH_75_TABLE_FIXES};

/// One profile: a 6-attack blade and an 8-attack 24in rifle, `rules` the carried special rules.
fn profile(id: &str, sys: &str, fac: &str, rules: &str) -> String {
    format!(r#""{id}":{{"unit_id":"{id}","name":"{id}","quality":4,"defense":3,"tough":1,
      "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"{sys}",
      "faction_folder":"{fac}","special_rules":[{rules}],"item_grants":[],"attached_hero_rules":[],
      "move_bands":{{"advance":6.0,"rush":12.0}},"weapons":[
      {{"name":"Blade","range":0,"attacks":6,"count":1,"ap":0,"rules":[]}},
      {{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]}}]}}"#)
}

fn stat(id: &str, epoch: u32) -> UnitStatic {
    let profiles = [
        profile("plain", "gf", "war_disciples", ""),
        profile("warbound", "gf", "war_disciples", r#""Warbound""#),
        profile("enh_warbound", "gf", "war_disciples", r#""Warbound","Enhanced Warbound""#),
        profile("destroyer", "aof", "ogres", r#""Destroyer""#),
        profile("enh_destroyer", "aof", "ogres", r#""Destroyer","Enhanced Destroyer""#),
        profile("enh_infected", "gf", "infected_colonies", r#""Infected","Enhanced Infected""#),
    ];
    let header = read_act_header(&format!(r#"{{"kind":"header","knobs":{{}},"profiles":{{{}}}}}"#, profiles.join(","))).expect("header");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get(id).expect(id), epoch)
}

fn shot(id: &str, epoch: u32, d_in: f64, seed: i64) -> i64 {
    let us = stat(id, epoch);
    let p = [us.shoot[0].clone()];
    resolve_volley_with_tray(
        &[striker(&p, &[0], &[8], &us.ctx)], &defender(4, 5), "Target", d_in, d_in,
        true, true, true, true, &mut Tray::seeded(seed),
    ).wounds
}

fn strike(id: &str, epoch: u32, charging: bool, gap_in: f64, seed: i64) -> i64 {
    let us = stat(id, epoch);
    let p = [us.melee[0].clone()];
    resolve_melee_leg(
        &[striker(&p, &[0], &[6], &us.ctx)], &defender(4, 5), "Target", charging, true, true,
        false, gap_in, false, false, false, false, false, &mut Tray::seeded(seed),
    ).wounds
}

const SEEDS: std::ops::Range<i64> = 0..60;

fn total(f: impl Fn(i64) -> i64) -> i64 {
    SEEDS.clone().map(f).sum()
}

fn same_per_seed(a: impl Fn(i64) -> i64, b: impl Fn(i64) -> i64) -> bool {
    SEEDS.clone().all(|s| a(s) == b(s))
}

#[test]
fn enhanced_shreds_a_six_inch_shot_and_a_short_charge_at_epoch_75() {
    for id in ["enh_warbound", "enh_destroyer", "enh_infected"] {
        assert!(total(|s| shot(id, EPOCH_75_TABLE_FIXES, 6.0, s)) > total(|s| shot("plain", EPOCH_75_TABLE_FIXES, 6.0, s)),
            "{id}: a 6in shot pays on unmodified 1s");
        assert!(total(|s| strike(id, EPOCH_75_TABLE_FIXES, true, 4.0, s)) > total(|s| strike("plain", EPOCH_75_TABLE_FIXES, true, 0.0, s)),
            "{id}: a 4in charge pays on unmodified 1s");
    }
}

#[test]
fn enhanced_strike_back_pays_nothing_at_epoch_75() {
    for id in ["enh_warbound", "enh_destroyer", "enh_infected"] {
        assert!(same_per_seed(|s| strike(id, EPOCH_75_TABLE_FIXES, false, 0.0, s), |s| strike("plain", EPOCH_75_TABLE_FIXES, false, 0.0, s)),
            "{id}: a strike-back is not a charge, the base gate pays nothing");
    }
}

#[test]
fn enhanced_has_no_one_two_window_at_twelve_inches_at_epoch_75() {
    for (id, base) in [("enh_warbound", "warbound"), ("enh_destroyer", "destroyer")] {
        assert!(same_per_seed(|s| shot(id, EPOCH_75_TABLE_FIXES, 12.0, s), |s| shot(base, EPOCH_75_TABLE_FIXES, 12.0, s)),
            "{id}: at 12in a 2 is not a shred, exactly the base form's wounds");
    }
}

#[test]
fn base_forms_keep_their_distance_gates_at_epoch_75() {
    for id in ["warbound", "destroyer"] {
        assert!(same_per_seed(|s| shot(id, EPOCH_75_TABLE_FIXES, 6.0, s), |s| shot("plain", EPOCH_75_TABLE_FIXES, 6.0, s)),
            "{id}: a 6in shot pays nothing without the Enhanced entry");
        assert!(same_per_seed(|s| strike(id, EPOCH_75_TABLE_FIXES, true, 4.0, s), |s| strike("plain", EPOCH_75_TABLE_FIXES, true, 4.0, s)),
            "{id}: a 4in charge pays nothing without the Enhanced entry");
    }
}

#[test]
fn at_epoch_74_the_boost_reading_replays() {
    let e = EPOCH_74_CLIMB_COST;
    assert!(same_per_seed(|s| shot("enh_warbound", e, 6.0, s), |s| shot("plain", e, 6.0, s)),
        "74: a 6in shot is still gated");
    assert!(same_per_seed(|s| strike("enh_warbound", e, true, 4.0, s), |s| strike("plain", e, true, 4.0, s)),
        "74: a 4in charge is still gated");
    assert!(total(|s| shot("enh_warbound", e, 12.0, s)) > total(|s| shot("warbound", e, 12.0, s)),
        "74: over 9in the 1-2 window still widens");
}
