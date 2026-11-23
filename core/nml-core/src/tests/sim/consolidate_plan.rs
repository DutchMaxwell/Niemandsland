//! meleefix (EPOCH_96_PARITY_BATCH = 96, lead call 22.11. option b): a melee winner's "may move up to 3 in" aims where the
//! table's AI round planner aims it when the door's transcript carries the planner inputs (`Input::Consolidate`, offered on the
//! tray). The fixture: the charger "a" wiped "b" next to it at the origin; marker A lies 6 in north (+z), marker B 9 in south.
//! The old greedy picks the nearer A; a seize task on B sends the unit south. RED without the port: the plan is ignored, the unit
//! walks north.
use super::*;
use crate::activation::ConsolidatePlan;

fn wiped(epoch: u32, plan: Option<ConsolidatePlan>) -> [f64; 3] {
    let (mut st, statics) = vr_charge_line(0.0);
    st.player = vec![1, 2];
    st.alive[1] = 0;
    st.positions[1].clear();
    st.wounds[1].clear();
    st.objectives = vec![
        crate::state::Objective { pos: [0.0, 0.0, 6.0 * IN2M], owner: 0 },
        crate::state::Objective { pos: [0.0, 0.0, -9.0 * IN2M], owner: 0 },
    ];
    let board = small_board();
    let mut tray = Tray::supplied(vec![]);
    tray.offer_consolidation(plan.into_iter().collect());
    let mut shot = ShootResult::default();
    let seams = Seams { movement: true, rules_epoch: epoch, ..Seams::default() };
    consolidate_after_melee(&mut st, &statics, Cover::Board(&board), seams, 0, 1, Some((&mut tray, &mut shot)));
    let p = st.positions[0][0];
    [p[0] / IN2M, p[1] / IN2M, p[2] / IN2M]
}

fn seize_b(lane: bool) -> ConsolidatePlan {
    ConsolidatePlan { unit: "a".into(), planner: true, task: "seize".into(), marker: 1, lane, ..Default::default() }
}

#[test]
fn a_seize_task_sends_the_winner_to_its_own_marker_at_96() {
    let at = wiped(96, Some(seize_b(false)));
    assert!((at[2] + 3.0).abs() < 0.01 && at[0].abs() < 0.01, "3 in south toward the task's marker B, got {at:?}");
}

#[test]
fn a_record_at_95_and_a_transcript_without_the_plan_keep_the_old_greedy() {
    for (epoch, plan) in [(95, Some(seize_b(false))), (96, None)] {
        let at = wiped(epoch, plan.clone());
        assert!((at[2] - 3.0).abs() < 0.01, "epoch {epoch}, plan {}: 3 in north toward the nearer marker A, got {at:?}", plan.is_some());
    }
}

#[test]
fn a_laned_seize_aims_two_and_a_half_inches_beside_the_marker() {
    // The goal is B + 2.5 in along the perpendicular (-dz, 0, dx) of the winner->B line = (2.5, 0, -9): 3 in toward it.
    let at = wiped(96, Some(seize_b(true)));
    let want = [3.0 * 2.5 / (2.5f64 * 2.5 + 81.0).sqrt(), -3.0 * 9.0 / (2.5f64 * 2.5 + 81.0).sqrt()];
    assert!((at[0] - want[0]).abs() < 0.01 && (at[2] - want[1]).abs() < 0.01, "toward (2.5, -9): want {want:?}, got {at:?}");
}

#[test]
fn a_planned_side_without_a_task_skips_a_marker_it_already_owns() {
    // No task: the table's tiered greedy, which skips a marker its own side owns (A, owner 1) -> B.
    let plan = ConsolidatePlan { unit: "a".into(), planner: true, ..Default::default() };
    let (mut st, _statics) = vr_charge_line(0.0);
    st.player = vec![1, 2];
    st.alive[1] = 0;
    st.positions[1].clear();
    st.wounds[1].clear();
    st.objectives = vec![
        crate::state::Objective { pos: [0.0, 0.0, 6.0 * IN2M], owner: 1 },
        crate::state::Objective { pos: [0.0, 0.0, -9.0 * IN2M], owner: 0 },
    ];
    let goal = planned_consolidation_goal(&st, 0, &plan).expect("a goal");
    assert!((goal[2] as f64 / IN2M + 9.0).abs() < 1e-4, "marker B, got {goal:?}");
}

// ---- review round 1: every branch on a four-unit board, and the whole path through `step_activation` ----

/// Four units on one board: the winner "a" (side 1) at the origin, "ah" (side 1) and "b", "bh" (side 2) parked far off, all
/// independent (no joined heroes unless a test joins one). Markers: A 6 in north, B 9 in south, both neutral.
fn board4() -> State {
    let mut st = four_unit_line();
    st.player = vec![1, 1, 2, 2];
    st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None; 4]);
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[-30.0 * IN2M, 0.0, 0.0]], vec![[30.0 * IN2M, 0.0, 20.0 * IN2M]], vec![[30.0 * IN2M, 0.0, -20.0 * IN2M]]];
    st.objectives = vec![
        crate::state::Objective { pos: [0.0, 0.0, 6.0 * IN2M], owner: 0 },
        crate::state::Objective { pos: [0.0, 0.0, -9.0 * IN2M], owner: 0 },
    ];
    st
}

fn at(st: &mut State, unit: usize, x_in: f64, z_in: f64) {
    st.positions[unit] = vec![[x_in * IN2M, 0.0, z_in * IN2M]];
}

fn goal_in(st: &State, plan: ConsolidatePlan) -> [f64; 3] {
    let g = planned_consolidation_goal(st, 0, &plan).expect("a goal");
    [g[0] as f64 / IN2M, g[1] as f64 / IN2M, g[2] as f64 / IN2M]
}

fn task(kind: &str, marker: i64) -> ConsolidatePlan {
    ConsolidatePlan { unit: "a".into(), planner: true, task: kind.into(), marker, ..Default::default() }
}

const B_CENTRE: [f64; 3] = [30.0, 0.0, 20.0];

fn near(g: [f64; 3], want: [f64; 3]) -> bool {
    (g[0] - want[0]).abs() < 1e-4 && (g[2] - want[2]).abs() < 1e-4
}

#[test]
fn a_seize_on_a_marker_its_side_already_holds_goes_to_the_nearest_enemy() {
    let mut st = board4();
    at(&mut st, 1, 0.0, -9.0); // the friend "ah" stands on B: own 1 > enemy 0
    let g = goal_in(&st, task("seize", 1));
    assert!(near(g, B_CENTRE), "the promise is kept, the winner fights on: {g:?}");
}

#[test]
fn a_fight_task_holds_the_marker_only_it_holds_and_leaves_one_a_friend_holds() {
    let mut st = board4();
    at(&mut st, 0, 0.0, 5.0); // the winner stands within 3 in of A
    assert!(near(goal_in(&st, task("fight", -1)), [0.0, 0.0, 6.0]), "garrison: A");
    at(&mut st, 1, 0.5, 6.0); // a friend holds A too
    let g = goal_in(&st, task("fight", -1));
    assert!(near(g, B_CENTRE), "not needed there: the nearest enemy, got {g:?}");
}

#[test]
fn the_greedy_puts_a_holdable_far_marker_before_a_contested_near_one() {
    let mut st = board4();
    at(&mut st, 2, 0.0, 6.5); // the enemy "b" holds A
    let g = goal_in(&st, task("", -1));
    assert!(near(g, [0.0, 0.0, -9.0]), "B (holdable) beats A (contested): {g:?}");
}

#[test]
fn with_the_spread_on_a_booked_marker_ranks_below_a_free_one() {
    let st = board4();
    let mut plan = task("", -1);
    plan.runners = vec![1, 0];
    assert!(near(goal_in(&st, plan.clone()), [0.0, 0.0, 6.0]), "spread off: the nearer A");
    plan.spread = true;
    assert!(near(goal_in(&st, plan), [0.0, 0.0, -9.0]), "spread on: A has a runner, B is free");
}

#[test]
fn a_marker_its_side_holds_by_majority_is_skipped_but_not_by_a_shaken_or_joined_holder() {
    let mut st = board4();
    at(&mut st, 1, 0.0, 6.5); // the friend on A: own 1 > enemy 0 -> skipped
    assert!(near(goal_in(&st, task("", -1)), [0.0, 0.0, -9.0]), "A is held: B");
    st.shaken[1] = true;
    assert!(near(goal_in(&st, task("", -1)), [0.0, 0.0, 6.0]), "a Shaken friend holds nothing: A");
    st.shaken[1] = false;
    st.attached_to = Rc::new(vec![None, Some(0), None, None]);
    assert!(near(goal_in(&st, task("", -1)), [0.0, 0.0, 6.0]), "a joined hero counts with its host, not alone: A");
}

#[test]
fn a_neutral_marker_is_not_a_side_zero_marker() {
    let mut st = board4();
    st.player = vec![0, 0, 2, 2]; // a fixture side 0: owner 0 still means neutral
    assert!(near(goal_in(&st, task("", -1)), [0.0, 0.0, 6.0]), "A, the nearer neutral marker");
}

/// The whole path: a charge through `step_activation` whose transcript carries the winner's inputs (seize B). At 96 the wiped
/// target's charger walks south toward B; at 95 the same transcript keeps the greedy (north, the nearer A). RED: drop the
/// `Input::Consolidate` collection in `step_activation` and both runs walk north.
#[test]
fn a_stepped_charge_reads_the_consolidation_inputs_at_96_and_not_at_95() {
    use crate::activation::{step_activation, ActStep, Input};
    let (mut st, statics) = vr_charge_line(0.0);
    st.player = vec![1, 2];
    st.objectives = vec![
        crate::state::Objective { pos: [0.0, 0.0, 6.0 * IN2M], owner: 0 },
        crate::state::Objective { pos: [0.0, 0.0, -9.0 * IN2M], owner: 0 },
    ];
    let board = small_board();
    let run = |epoch: u32, seed: i64| {
        let seams = Seams { movement: true, rules_epoch: epoch, tray_exact: true, ..Seams::default() };
        let mut t = vec![Input::Begin, Input::Intent { kind: CHARGE, shoot: None, split: None, charge: Some("b".into()), no_step: false },
            Input::Consolidate(seize_b(false))];
        let mut dice = Tray::seeded(seed);
        loop {
            match step_activation(&statics, &st, "a", &board, seams, &t, true) {
                ActStep::NeedRoll { faces: n, .. } => t.push(Input::Faces(dice.roll(n))),
                ActStep::Done { state, .. } => break state,
                other => panic!("epoch {epoch} seed {seed}: {other:?}"),
            }
        }
    };
    let mut wiped = 0;
    for seed in 0..16i64 {
        let (s96, s95) = (run(96, seed), run(95, seed));
        if s96.alive[1] > 0 || s95.alive[1] > 0 {
            continue;
        }
        wiped += 1;
        let (z96, z95) = (s96.positions[0][0][2] / IN2M, s95.positions[0][0][2] / IN2M);
        assert!(z96 < -2.9 && z95 > 2.9, "seed {seed}: 96 south toward B ({z96:.3}), 95 north toward A ({z95:.3})");
    }
    assert!(wiped >= 4, "the fixture must wipe the target on several seeds: {wiped}");
}

#[test]
fn the_order_check_takes_the_inputs_once_per_unit_between_the_intent_and_the_first_die() {
    use crate::activation::{order_check, Input};
    let intent = Input::Intent { kind: CHARGE, shoot: None, split: None, charge: Some("b".into()), no_step: false };
    let c = Input::Consolidate(seize_b(false));
    assert_eq!(order_check("a", &[Input::Begin, intent.clone(), c.clone(), Input::Faces(vec![4])]), Ok(()));
    assert!(order_check("a", &[Input::Begin, c.clone(), intent.clone()]).is_err(), "before the intent");
    assert!(order_check("a", &[Input::Begin, intent.clone(), Input::Faces(vec![4]), c.clone()]).is_err(), "after the first die");
    assert!(order_check("a", &[Input::Begin, intent, c.clone(), c]).is_err(), "twice for one unit");
}
