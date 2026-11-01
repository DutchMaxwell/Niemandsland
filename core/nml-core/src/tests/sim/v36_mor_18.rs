//! Rules 3.6 row MOR-18 tests (sim module); owned by lane morale.
//!
//! From EPOCH_73_V36 a unit is MOVED by Mind Control at most once per round: a
//! second bearer that picks the same unit still forces its morale test (and the
//! Shaken that follows), but the unit is NOT moved again. The latch clears at
//! the start of each round. 72 keeps today's reading — it moves again.

use super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::state::Roster;
use std::collections::HashMap;
use std::rc::Rc;

/// A registry-built gf/jackals "Mind Control" bearer (the REAL entry: range
/// 18", move 6", needs LOS, no `effect`), named so the log line reads.
fn bearer(name: &str, rules_epoch: u32) -> UnitStatic {
    let p = Profile {
        cost: 0,
        unit_id: name.into(),
        name: name.into(),
        quality: 4,
        defense: 4,
        tough: 1,
        wounds_max: vec![1],
        model_count: 1,
        weapons: vec![],
        special_rules: vec!["Mind Control".into()],
        caster_value: 0,
        base_radius: 0.0,
        base_shape: String::new(),
        base_w_mm: 0.0,
        base_d_mm: 0.0,
        game_system: "gf".into(),
        faction_folder: "jackals".into(),
        item_grants: vec![],
        attached_hero_rules: vec![],
        move_bands: MoveBands::default(),
    };
    let mut reg = crate::rules::Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &p, rules_epoch)
}

/// TWO bearers side by side (slots 0 and 1) and one Q4 three-model target
/// (slot 2) 5" away in the open — both bearers pick the SAME target.
fn two_bearers_line(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: st.roster.keys.clone(),
        index: HashMap::new(),
        profile: vec![0, 1, 2, 3],
    });
    st.player = vec![0, 0, 1, 1];
    st.positions = vec![
        vec![[0.0, 0.0, 0.0]],
        vec![[0.5 * IN2M, 0.0, 0.0]],
        vec![
            [5.0 * IN2M, 0.0, 0.0],
            [5.02 * IN2M, 0.0, 0.0],
            [5.04 * IN2M, 0.0, 0.0],
        ],
        vec![],
    ];
    st.radii = Rc::new(vec![vec![IN2M], vec![IN2M], vec![IN2M; 3], vec![]]);
    st.wounds = vec![vec![1], vec![1], vec![1, 1, 1], vec![]];
    st.alive = vec![1, 1, 3, 0];
    let target = UnitStatic {
        name: "Victim".into(),
        quality: 4,
        ctx: Ctx { quality: 4, defense: 4, tough: 1, ..Ctx::default() },
        model_count: 3,
        wounds_max: vec![1, 1, 1],
        ..UnitStatic::default()
    };
    (
        st,
        vec![
            bearer("First", rules_epoch),
            bearer("Second", rules_epoch),
            target,
            UnitStatic::default(),
        ],
    )
}

/// One bearer's Mind Control slot, off the tray, on the same round.
fn run_bearer(
    st: &mut State,
    statics: &[UnitStatic],
    bearer: usize,
    rules_epoch: u32,
    seed: i64,
) -> ShootResult {
    let mut tray = Tray::seeded(seed);
    let mut shot = ShootResult::default();
    tray_mind_control(
        statics, st, bearer,
        Seams { rules_epoch, ..Seams::default() },
        &mut tray, &mut shot, Cover::Recorded(None),
    );
    shot
}

/// A seed whose FIRST assimilated face fails Quality 4 (asserted by the caller
/// so the test is never blind to a tray change).
fn failing_seed() -> i64 {
    (0..200_i64)
        .find(|&s| Tray::seeded(s).roll(1)[0] < 4)
        .expect("some seed fails Quality 4")
}

fn moved_m(from: [f64; 3], to: [f64; 3]) -> f64 {
    ((from[0] - to[0]).powi(2) + (from[2] - to[2]).powi(2)).sqrt()
}

/// RED on origin/main: the second bearer's failed test pins the target in
/// place at 73 — the morale test still fires and the line says why.
#[test]
fn a_second_bearer_does_not_move_the_same_unit_again_at_epoch_73() {
    let (mut st, statics) = two_bearers_line(EPOCH_73_V36);
    let seed = failing_seed();
    let before = st.positions[2][0];
    let first = run_bearer(&mut st, &statics, 0, EPOCH_73_V36, seed);
    let after_first = st.positions[2][0];
    assert!(moved_m(before, after_first) > 5.0 * IN2M, "the first bearer moves it: {first:?}");
    let second = run_bearer(&mut st, &statics, 1, EPOCH_73_V36, seed);
    assert!(
        second.log.iter().any(|l| l.contains("fails the morale test")),
        "the second bearer still forces the morale test: {:#?}", second.log
    );
    assert!(st.shaken[2], "the failed second test still Shakes the target");
    assert_eq!(st.positions[2][0], after_first, "the second bearer does not move it again");
    assert!(
        second.log.iter().any(|l| l.contains("already moved by Mind Control")),
        "rules-must-log: the own-words line — got {:#?}", second.log
    );
}

/// The latch clears at the start of the next round: the same second bearer
/// moves it again there.
#[test]
fn a_later_round_moves_the_unit_again_at_epoch_73() {
    let (mut st, statics) = two_bearers_line(EPOCH_73_V36);
    let seed = failing_seed();
    run_bearer(&mut st, &statics, 0, EPOCH_73_V36, seed);
    st.round += 1;
    let before = st.positions[2][0];
    run_bearer(&mut st, &statics, 1, EPOCH_73_V36, seed);
    assert!(
        moved_m(before, st.positions[2][0]) > 5.0 * IN2M,
        "next round: the latch is clear and the target moves again"
    );
}

/// Control: at 72 the second bearer moves the same unit a second time.
#[test]
fn at_epoch_72_the_second_bearer_moves_it_again() {
    let (mut st, statics) = two_bearers_line(EPOCH_72_PLAYTEST_RULES);
    let seed = failing_seed();
    run_bearer(&mut st, &statics, 0, EPOCH_72_PLAYTEST_RULES, seed);
    let before = st.positions[2][0];
    let second = run_bearer(&mut st, &statics, 1, EPOCH_72_PLAYTEST_RULES, seed);
    assert!(
        moved_m(before, st.positions[2][0]) > 5.0 * IN2M,
        "72 keeps today: it moves again — {:#?}", second.log
    );
}
