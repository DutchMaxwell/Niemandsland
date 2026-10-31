//! Rules 3.6 row MOR-19 tests (unit module); owned by lane morale.
//!
//! MOR-19 rule 1: the Great Banner Utility-Buff one-shot (+1 to morale test
//! rolls) counts only on a test shooting or melee caused (the MOR-08 cause
//! flag). A non-combat cause skips the +1, names it, and leaves the record
//! unspent; epoch 72 keeps the old always-on reading.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::dice::{ShootResult, Tray};
use crate::io::Seams;
use crate::mods::LiveMod;
use crate::sim::tray_morale_for;
use std::rc::Rc;

/// The four-unit line's target "b" (index 2) with one Great Banner one-shot
/// record on its own ledger and no capture-stamp Banner share.
fn great_banner_line() -> (crate::state::State, Vec<UnitStatic>) {
    let mut st = crate::sim::tests::four_unit_line();
    st.morale_bonus[2] = 0;
    st.buffs[2] = vec![LiveMod {
        hit_mod: 0,
        casting_mod: 0,
        morale_mod: 1,
        ap_mod: 0,
        def_mod: 0,
        defense_mod: 0,
        move_mod: 0,
        grants_rule: Rc::from(""),
        scope: Rc::from(""),
        attackers: false,
        once: true,
        name: Rc::from("Great Banner"),
    }];
    let mut us = UnitStatic { name: "b".into(), ..Default::default() };
    us.ctx.quality = 4;
    (st, vec![us; 4])
}

/// The first seed whose first tray face is a 3: a pass only with the +1.
fn seed_rolling_a_three() -> i64 {
    (0..500).find(|&s| Tray::seeded(s).roll(1)[0] == 3).expect("some seed rolls a 3")
}

/// One morale test on "b" with the given cause.
fn run(cause: Option<&str>, epoch: u32) -> (crate::state::State, ShootResult) {
    let (mut st, statics) = great_banner_line();
    let mut tray = Tray::seeded(seed_rolling_a_three());
    let mut shot = ShootResult::default();
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    tray_morale_for(&mut st, &statics, 2, false, cause, seams, &mut tray, &mut shot);
    (st, shot)
}

/// RED: from epoch 73 Mind Control is neither shooting nor melee, so the
/// Great Banner +1 does not count: the 3 fails the plain Quality 4+.
#[test]
fn great_banner_is_skipped_on_a_mind_control_test_at_epoch_73() {
    let (st, shot) = run(Some("Mind Control"), EPOCH_73_V36);
    let die = shot.rolls.iter().find(|r| r.count == 1).expect("the morale die is drawn");
    assert_eq!((die.faces[0], die.target), (3, 4), "epoch 73: no Great Banner +1 against Mind Control: {die:?}");
    assert!(st.shaken[2], "the 3 fails the plain Quality test, so the target is Shaken");
    assert!(
        shot.log.iter().any(|l| l.contains("Great Banner") && l.contains("Mind Control")),
        "rules-must-log: the skipped Great Banner is named with its cause — got {:#?}",
        shot.log
    );
    assert!(
        st.buffs[2].iter().any(|r| &*r.name == "Great Banner"),
        "the one-shot did not count, so it is not spent by that test: {:?}",
        st.buffs[2]
    );
}

/// Control: below epoch 73 the Great Banner still helps against Mind Control.
#[test]
fn great_banner_helps_a_mind_control_test_at_epoch_72() {
    let (st, shot) = run(Some("Mind Control"), EPOCH_72_PLAYTEST_RULES);
    let die = shot.rolls.iter().find(|r| r.count == 1).expect("the morale die is drawn");
    assert_eq!((die.faces[0], die.target), (3, 3), "epoch 72: the +1 makes the 3 a pass: {die:?}");
    assert!(!st.shaken[2], "epoch 72: the target holds");
    assert!(st.buffs[2].iter().all(|r| &*r.name != "Great Banner"), "epoch 72 spends the one-shot");
}

/// Control: a shooting morale test keeps the Great Banner +1 at epoch 73.
#[test]
fn great_banner_helps_a_shooting_test_at_epoch_73() {
    let (st, shot) = run(None, EPOCH_73_V36);
    let die = shot.rolls.iter().find(|r| r.count == 1).expect("the morale die is drawn");
    assert_eq!((die.faces[0], die.target), (3, 3), "shooting: the +1 makes the 3 a pass: {die:?}");
    assert!(!st.shaken[2], "shooting: the target holds");
    assert!(st.buffs[2].iter().all(|r| &*r.name != "Great Banner"), "the combat test spends the one-shot");
}

// ------------------- MOR-19 rule 3: Speed Debuff targets one enemy MODEL -----

use crate::IN2M;

/// The bearer's real registry stamp: aof dwarves' "Speed Debuff" (Utility
/// Buff, enemy, grants Slow, once).
fn speed_debuff_bearer(epoch: u32) -> UnitStatic {
    let p = Profile {
        cost: 0,
        unit_id: "a".into(),
        name: "a".into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1],
        model_count: 1,
        weapons: vec![],
        special_rules: vec!["Speed Debuff".into()],
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: "aof".into(),
        faction_folder: "dwarves".into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: crate::state::MoveBands::default(),
    };
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &p, epoch)
}

/// Bearer "a" at the origin; enemy "b" is an ordinary three-model unit at 12"
/// (index 2), enemy "c" a single model at 9" (index 3). Both inside the 18".
fn speed_debuff_line(epoch: u32) -> (crate::state::State, Vec<UnitStatic>) {
    let mut st = crate::sim::tests::four_unit_line();
    st.alive = vec![1, 0, 3, 1];
    st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None, None]);
    st.positions[2] = vec![
        [12.0 * IN2M, 0.0, 0.0], [12.5 * IN2M, 0.0, 0.0], [13.0 * IN2M, 0.0, 0.0],
    ];
    st.wounds[2] = vec![1, 1, 1];
    st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M; 3], vec![IN2M]]);
    st.positions[3] = vec![[9.0 * IN2M, 0.0, 0.0]];
    let mut target = UnitStatic { name: "b".into(), ..Default::default() };
    target.ctx.quality = 4;
    target.ctx.tough = 1;
    (st, vec![speed_debuff_bearer(epoch), UnitStatic::default(), target.clone(), target])
}

/// One pre-attack utility-buff pass for the bearer.
fn run_speed_debuff(epoch: u32) -> crate::state::State {
    let (st, statics) = speed_debuff_line(epoch);
    let mut next = st.clone();
    let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Seams::default() };
    crate::sim::tray_utility_buff(&statics, &mut next, 0, seams, crate::sim::Cover::Recorded(None));
    next
}

fn slowed(st: &crate::state::State, ti: usize) -> bool {
    st.buffs[ti].iter().any(|r| &*r.grants_rule == "Slow")
}

/// RED: at epoch 73 the ordinary three-model unit gains nothing; the AI pick
/// prefers the single-model unit, which keeps the unit-level Slow grant.
#[test]
fn speed_debuff_prefers_and_slows_a_single_model_unit_at_epoch_73() {
    let next = run_speed_debuff(EPOCH_73_V36);
    assert!(slowed(&next, 3), "the single-model pick keeps the Slow: {:?}", next.buffs[3]);
    assert!(!slowed(&next, 2), "an ordinary model of a multi-model unit has no effect: {:?}", next.buffs[2]);
}

/// Control: below epoch 73 the multi-model unit is the higher-value pick and
/// still takes the Slow.
#[test]
fn speed_debuff_still_slows_a_multi_model_unit_at_epoch_72() {
    let next = run_speed_debuff(EPOCH_72_PLAYTEST_RULES);
    assert!(slowed(&next, 2), "epoch 72: the multi-model pick keeps the Slow: {:?}", next.buffs[2]);
    assert!(!slowed(&next, 3), "epoch 72: the single-model unit was not the pick: {:?}", next.buffs[3]);
}

/// RED (forced pick): with only the ordinary multi-model unit in range, epoch
/// 73 leaves it unslowed.
#[test]
fn speed_debuff_spares_an_ordinary_multi_model_unit_at_epoch_73() {
    let (mut st, statics) = speed_debuff_line(EPOCH_73_V36);
    st.alive[3] = 0;
    st.positions[3].clear();
    Rc::make_mut(&mut st.radii)[3].clear();
    let mut next = st.clone();
    let seams = Seams { rules_epoch: EPOCH_73_V36, hero_attach: true, ..Seams::default() };
    crate::sim::tray_utility_buff(&statics, &mut next, 0, seams, crate::sim::Cover::Recorded(None));
    assert!(!slowed(&next, 2), "the only pick is an ordinary model: no Slow: {:?}", next.buffs[2]);
}
