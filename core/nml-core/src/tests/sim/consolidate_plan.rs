//! meleefix (PENDING_EPOCH_CONSOLIDATE_PLAN = 96, lead call 22.11. option b): a melee winner's "may move up to 3 in" aims where the
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
