//! Referee pins for the ten catalogue missions (`assets/solo/missions.json`):
//! one test per mission, each walking `playout_seize` -> `apply_destroy_step`
//! -> `vp_score_round` in the game's booking order and ending in a
//! NON-symmetric verdict, so any referee flip is caught by the suite.
//!
//! The referee counts owners 1 and 2 (`mission.rs`), unlike the eval's 0/1
//! fixture convention, so the shared `four_unit_line` board is re-skinned:
//! units 0/1 act for side 1, units 2/3 for side 2. Positions are inches,
//! converted through `IN2M` like the fixture does.

use std::rc::Rc;

use super::*;
use crate::mission::{
    apply_destroy_step, escort_winner, extract_winner, mission_winner, playout_seize, role_winner,
    sabotage_winner, vp_score_end, apply_reveal_step, Reveal,
    vp_score_round,
};
use crate::objectives::marker_positions;
use crate::state::{Marker, Objective};

/// The shared four-unit board, re-skinned to the referee's 1/2 convention.
fn ref_board(scoring: &str) -> State {
    let mut st = four_unit_line();
    st.player = vec![1, 1, 2, 2];
    st.scoring = Rc::from(scoring);
    st.rounds_total = 4;
    st
}

/// One single-model unit parked on (x_in, z_in), inches.
fn place(st: &mut State, u: usize, x_in: f64, z_in: f64) {
    st.positions[u] = vec![[x_in * IN2M, 0.0, z_in * IN2M]];
}

/// Every unit starts far outside any 3" ring the tests draw.
fn parked(st: &mut State) {
    place(st, 0, -100.0, -100.0);
    place(st, 1, -101.0, -100.0);
    place(st, 2, 100.0, 100.0);
    place(st, 3, 101.0, 100.0);
}

fn objs(ps: &[(f64, f64)]) -> Vec<Objective> {
    ps.iter().map(|&(x, z)| Objective { pos: [x * IN2M, 0.0, z * IN2M], owner: 0 }).collect()
}

/// front_line's deployment zones, table-centred inches (deployments.json).
fn front_line_style() -> serde_json::Value {
    serde_json::json!({"zones": {
        "1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
        "2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]]
    }})
}

/// The two owned+destructible markers sabotage/demolition place at the
/// deploy_zone_front edge, in `owned_by = index + 1` order.
fn owned_markers() -> Vec<Marker> {
    vec![
        Marker { owned_by: 1, destructible: true, destroyed: false, destroyed_seq: 0, ..Default::default() },
        Marker { owned_by: 2, destructible: true, destroyed: false, destroyed_seq: 0, ..Default::default() },
    ]
}

/// `AiPlanner._imagined_round_end` (ai_planner.gd:355-380) booking order:
/// seize, then destroy, then the round_vp ledger; end-scoring missions book
/// no VP at all.
fn book_round_end(
    st: &mut State,
    owners: &mut [i64],
    vp: &mut [i64; 2],
    flavour: &serde_json::Value,
    memo: &mut serde_json::Map<String, serde_json::Value>,
) {
    playout_seize(st, owners);
    if !st.markers_meta.is_empty() {
        apply_destroy_step(&mut st.markers_meta, owners, &mut st.destroy_seq);
    }
    if &*st.scoring != "round_vp" {
        return;
    }
    vp_score_round(owners, vp, flavour, memo, &st.markers_meta);
}

#[test]
fn duel_end_majority_pins_held_markers() {
    let mut st = ref_board("end");
    parked(&mut st);
    st.objectives = objs(&[(-15.0, 0.0), (0.0, 0.0), (15.0, 0.0)]);
    let mut owners = vec![0; 3];
    let mut vp = [0i64; 2];
    let mut memo = serde_json::Map::new();
    let flavour = serde_json::json!({});
    place(&mut st, 0, -15.0, 3.0);
    place(&mut st, 2, 15.0, 3.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [1, 0, 2], "R1: each side seizes its own marker");
    place(&mut st, 2, 0.0, 3.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [1, 2, 2], "R2: P2 takes the middle marker");
    place(&mut st, 0, 0.0, -3.0);
    place(&mut st, 2, 10.0, 10.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [1, 1, 2], "R3: P1 retakes it, 2-1");
    assert_eq!(vp, [0, 0], "end-scoring missions never book a round ledger");
    assert_eq!(
        mission_winner("end", &owners, vp, &[], 4, 4),
        "p1",
        "the majority of held markers decides"
    );
    assert_eq!(
        mission_winner("end", &[], vp, &[], 3, 1),
        "p1",
        "no markers at all: surviving models decide"
    );
}

#[test]
fn seize_ground_quarter_centres_contested_goes_neutral() {
    let ps = marker_positions("quarter_centres", 0.0, &front_line_style(), 72.0, 48.0);
    assert_eq!(ps, vec![(-18.0, -6.0), (18.0, -6.0), (-18.0, 6.0), (18.0, 6.0)]);
    let mut st = ref_board("end");
    parked(&mut st);
    st.objectives = objs(&ps);
    let mut owners = vec![0; 4];
    let mut vp = [0i64; 2];
    let mut memo = serde_json::Map::new();
    let flavour = serde_json::json!({});
    place(&mut st, 0, -18.0, -3.0);
    place(&mut st, 2, -18.0, -9.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners[0], 0, "R1: both sides in the ring make the marker NEUTRAL");
    assert_eq!(st.objectives[0].owner, 0, "and the state's objective carries the verdict");
    place(&mut st, 2, 18.0, 9.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [1, 0, 0, 2], "R2: P1 holds marker 0, P2 seizes marker 3");
    place(&mut st, 0, 18.0, -3.0);
    place(&mut st, 2, 30.0, 20.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [1, 1, 0, 2], "R3: P1 crosses and takes marker 1, 2-1");
    assert_eq!(mission_winner("end", &owners, vp, &[], 4, 4), "p1");
}

#[test]
fn breakthrough_cross_seizes_enemy_front_marker() {
    let ps = marker_positions("deploy_zone_front", 12.0, &front_line_style(), 72.0, 48.0);
    assert_eq!(ps, vec![(0.0, -12.0), (0.0, 12.0)]);
    let mut st = ref_board("end");
    parked(&mut st);
    st.objectives = objs(&ps);
    let mut owners = vec![0; 2];
    let mut vp = [0i64; 2];
    let mut memo = serde_json::Map::new();
    let flavour = serde_json::json!({});
    place(&mut st, 0, 0.0, -9.0);
    place(&mut st, 2, 0.0, 9.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [1, 2], "R1: each front marker is held by its owner");
    place(&mut st, 0, 0.0, 9.0);
    place(&mut st, 2, 6.0, 18.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [1, 1], "R2: P1 crossed the line and holds BOTH markers");
    assert_eq!(mission_winner("end", &owners, vp, &[], 4, 4), "p1");
}

#[test]
fn king_of_the_hill_contest_then_lone_holder() {
    let ps = marker_positions("table_centre", 0.0, &front_line_style(), 72.0, 48.0);
    assert_eq!(ps, vec![(0.0, 0.0)]);
    let mut st = ref_board("end");
    parked(&mut st);
    st.objectives = objs(&ps);
    let mut owners = vec![0; 1];
    let mut vp = [0i64; 2];
    let mut memo = serde_json::Map::new();
    let flavour = serde_json::json!({});
    place(&mut st, 0, 0.0, -3.0);
    place(&mut st, 2, 0.0, 3.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [0], "R1: the hill contested is NEUTRAL");
    place(&mut st, 2, 0.0, 30.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [1], "R2: P2 steps off, P1 holds the hill alone");
    assert_eq!(mission_winner("end", &owners, vp, &[], 4, 4), "p1");
}

#[test]
fn pitched_battle_round_ledger_end_majority() {
    let mut st = ref_board("round_vp");
    parked(&mut st);
    st.objectives = objs(&[(-15.0, 0.0), (0.0, 0.0), (15.0, 0.0)]);
    let mut owners = vec![0; 3];
    let mut vp = [0i64; 2];
    let mut memo = serde_json::Map::new();
    let flavour = serde_json::json!({"majority": "end"});
    place(&mut st, 0, -15.0, 3.0);
    place(&mut st, 2, 15.0, 3.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(vp, [1, 1], "R1: 1 VP per held marker, majority deferred to the end");
    place(&mut st, 0, 0.0, -3.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [1, 1, 2], "R2-R4: P1 holds two markers, P2 one");
    vp_score_end(&owners, &mut vp, &flavour);
    assert_eq!(vp, [8, 4], "end: the 2-1 majority pays +1 on top of the 7-4 ledger");
    assert_eq!(mission_winner("round_vp", &owners, vp, &[], 4, 4), "p1");
}

#[test]
fn domination_round_majority_pays_every_round() {
    let ps = marker_positions("quarter_centres", 0.0, &front_line_style(), 72.0, 48.0);
    let mut st = ref_board("round_vp");
    parked(&mut st);
    st.objectives = objs(&ps);
    let mut owners = vec![0; 4];
    let mut vp = [0i64; 2];
    let mut memo = serde_json::Map::new();
    let flavour = serde_json::json!({"majority": "round"});
    place(&mut st, 0, -18.0, -3.0);
    place(&mut st, 1, 18.0, -3.0);
    place(&mut st, 2, 18.0, 9.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(vp, [3, 1], "R1: 2 markers + the majority bonus pay every round");
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(vp, [6, 2], "R2: the same board pays again");
    place(&mut st, 0, 18.0, 9.0);
    place(&mut st, 2, 30.0, 30.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [1, 1, 0, 1], "R3: P1's second unit takes marker 3");
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(vp, [14, 2], "R4: 3 markers + majority, and no end bonus is due");
    vp_score_end(&owners, &mut vp, &flavour);
    assert_eq!(vp, [14, 2], "majority 'round' pays nothing at the end");
    assert_eq!(mission_winner("round_vp", &owners, vp, &[], 4, 4), "p1");
}

#[test]
fn headquarters_hold_both_front_markers() {
    let ps = marker_positions("deploy_zone_front", 12.0, &front_line_style(), 72.0, 48.0);
    let mut st = ref_board("round_vp");
    parked(&mut st);
    st.objectives = objs(&ps);
    let mut owners = vec![0; 2];
    let mut vp = [0i64; 2];
    let mut memo = serde_json::Map::new();
    let flavour = serde_json::json!({"majority": "end"});
    place(&mut st, 0, 0.0, -9.0);
    place(&mut st, 2, 0.0, 9.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(vp, [1, 1], "R1: each side holds its own headquarters marker");
    place(&mut st, 0, 0.0, 9.0);
    place(&mut st, 2, 20.0, 20.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(owners, [1, 1], "R2-R4: P1 holds both markers");
    vp_score_end(&owners, &mut vp, &flavour);
    assert_eq!(vp, [8, 1], "ledger 7-1 plus the end majority bonus");
    assert_eq!(mission_winner("round_vp", &owners, vp, &[], 4, 4), "p1");
}

#[test]
fn mosh_pit_first_seize_bounty_paid_once() {
    let ps = marker_positions("table_centre", 0.0, &front_line_style(), 72.0, 48.0);
    let mut st = ref_board("round_vp");
    parked(&mut st);
    st.objectives = objs(&ps);
    let mut owners = vec![0; 1];
    let mut vp = [0i64; 2];
    let mut memo = serde_json::Map::new();
    let flavour = serde_json::json!({"majority": "none", "first_seize": true});
    place(&mut st, 0, 0.0, -3.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(vp, [2, 0], "R1: the marker VP plus the first-seize bounty");
    assert_eq!(memo["first_seizer"], 1, "P1 stamped as the first seizer");
    place(&mut st, 0, 0.0, -30.0);
    place(&mut st, 2, 0.0, 3.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(vp, [2, 1], "R2: P2 scores the marker, but NO second bounty");
    place(&mut st, 0, 0.0, -3.0);
    place(&mut st, 2, 30.0, 30.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(vp, [4, 1], "R3-R4: P1 holds on; majority 'none' pays nothing at the end");
    vp_score_end(&owners, &mut vp, &flavour);
    assert_eq!(vp, [4, 1]);
    assert_eq!(mission_winner("round_vp", &owners, vp, &[], 4, 4), "p1");
}

#[test]
fn sabotage_destroy_theirs_keep_yours() {
    let ps = marker_positions("deploy_zone_front", 12.0, &front_line_style(), 72.0, 48.0);
    let mut st = ref_board("sabotage");
    parked(&mut st);
    st.objectives = objs(&ps);
    st.markers_meta = owned_markers();
    let mut owners = vec![0; 2];
    let mut vp = [0i64; 2];
    let mut memo = serde_json::Map::new();
    let flavour = serde_json::json!({});
    place(&mut st, 0, 0.0, 9.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert!(st.markers_meta[1].destroyed, "R1: P1 alone holds P2's marker -> it falls");
    assert_eq!(st.markers_meta[1].destroyed_seq, 1, "the first destruction is stamped seq 1");
    assert_eq!(owners[1], 0, "the fallen marker's owner slot is zeroed, no ghost");
    assert_eq!(sabotage_winner(&st.markers_meta), "p1", "destroyed theirs, kept mine");
    assert_eq!(mission_winner("sabotage", &owners, vp, &st.markers_meta, 4, 4), "p1");
    let intact = owned_markers();
    assert_eq!(sabotage_winner(&intact), "draw", "both markers standing is a draw");
    assert_eq!(mission_winner("sabotage", &owners, vp, &intact, 4, 4), "draw");
}

#[test]
fn demolition_own_marker_stands_and_first_fallen_collects() {
    let ps = marker_positions("deploy_zone_front", 12.0, &front_line_style(), 72.0, 48.0);
    let mut st = ref_board("round_vp");
    parked(&mut st);
    st.objectives = objs(&ps);
    st.markers_meta = owned_markers();
    let mut owners = vec![0; 2];
    let mut vp = [0i64; 2];
    let mut memo = serde_json::Map::new();
    let flavour = serde_json::json!({"mode": "demolition", "majority": "none"});
    place(&mut st, 0, 0.0, -9.0);
    place(&mut st, 2, 0.0, 9.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(vp, [1, 1], "R1: 1 VP per side while the own marker stands");
    place(&mut st, 0, 0.0, 9.0);
    place(&mut st, 2, 20.0, 20.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert!(st.markers_meta[1].destroyed && st.markers_meta[1].destroyed_seq == 1);
    assert_eq!(owners[1], 0);
    assert_eq!(vp, [2, 1], "R2: P1's marker still stands, P2's fell");
    place(&mut st, 0, 0.0, -9.0);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    book_round_end(&mut st, &mut owners, &mut vp, &flavour, &mut memo);
    assert_eq!(vp, [4, 1], "R3-R4: P1 keeps scoring, P2 collects nothing yet");
    vp_score_end(&owners, &mut vp, &flavour);
    assert_eq!(vp, [4, 1], "majority 'none' pays nothing at the end");
    assert_eq!(mission_winner("round_vp", &owners, vp, &st.markers_meta, 4, 4), "p1");
    let revenge = [
        Marker { owned_by: 1, destructible: true, destroyed: true, destroyed_seq: 2, ..Default::default() },
        Marker { owned_by: 2, destructible: true, destroyed: true, destroyed_seq: 1, ..Default::default() },
    ];
    let mut rvp = [0i64; 2];
    vp_score_round(&owners, &mut rvp, &flavour, &mut memo, &revenge);
    assert_eq!(rvp, [0, 1], "once both fell, the FIRST-fallen side (seq 1 = P2) collects");
}

/// One marker on (x_in, z_in) over the referee board, the attacker in slot `att`.
fn role_board(att: i64, x_in: f64, z_in: f64) -> State {
    let mut st = ref_board("escort");
    parked(&mut st);
    st.attacker = att;
    st.objectives = vec![Objective { pos: [x_in * IN2M, 0.0, z_in * IN2M], owner: 0 }];
    st.markers_meta = vec![Marker::default()];
    st
}

#[test]
fn escort_defender_wins_within_six_of_the_opposite_edge() {
    // deployed on the +z edge, so the target is the -z edge (z = -24")
    assert_eq!(escort_winner(&role_board(1, 0.0, -18.0), 1, 48.0), "p2", "6.0\" from the target edge");
    assert_eq!(escort_winner(&role_board(2, 0.0, -18.0), 1, 48.0), "p1", "slot 2 attacks, so slot 1 defends");
    assert_eq!(escort_winner(&role_board(1, 0.0, -17.0), 1, 48.0), "p1", "7\" out: the attacker wins");
    assert_eq!(escort_winner(&role_board(1, 0.0, 22.0), 1, 48.0), "p1", "the HOME edge does not count");
}

#[test]
fn escort_carried_marker_uses_the_carrier_base_edge() {
    let mut st = role_board(1, 0.0, 0.0);
    st.markers_meta[0].carry = true;
    st.markers_meta[0].carried_by = 2;
    place(&mut st, 2, 0.0, -20.0);
    st.radii[2] = vec![1.0 * IN2M];
    assert_eq!(escort_winner(&st, 1, 48.0), "p2", "centre 4\" out, base edge 3\"");
    place(&mut st, 2, 0.0, -17.5);
    assert_eq!(escort_winner(&st, 1, 48.0), "p2", "centre 6.5\" out, base edge 5.5\"");
    place(&mut st, 2, 0.0, -16.5);
    assert_eq!(escort_winner(&st, 1, 48.0), "p1", "base edge 6.5\" out");
    st.attacker = 0;
    assert_eq!(escort_winner(&st, 1, 48.0), "draw", "no roles, no verdict");
}

#[test]
fn extract_attacker_wins_within_six_of_any_edge() {
    assert_eq!(extract_winner(&role_board(1, 30.0, 0.0), 72.0, 48.0), "p1", "6\" from the +x edge");
    assert_eq!(extract_winner(&role_board(2, 0.0, 18.0), 72.0, 48.0), "p2", "6\" from the +z edge");
    assert_eq!(extract_winner(&role_board(1, 29.0, 0.0), 72.0, 48.0), "p2", "7\" from every edge: the defender holds");
    assert_eq!(extract_winner(&role_board(1, -30.0, -17.0), 72.0, 48.0), "p1", "any edge, any corner");
}

#[test]
fn extract_skips_destroyed_markers_and_reads_the_scoring_id() {
    let mut st = role_board(1, 35.0, 0.0);
    assert_eq!(role_winner("extract", &st, 0, 72.0, 48.0), Some("p1"));
    st.markers_meta[0].destroyed = true;
    assert_eq!(role_winner("extract", &st, 0, 72.0, 48.0), Some("p2"), "a removed marker is not extracted");
    assert_eq!(role_winner("escort", &st, 1, 72.0, 48.0), Some("p1"), "no marker home: the attacker wins");
    assert_eq!(role_winner("end", &st, 1, 72.0, 48.0), None, "other ids keep their own referee");
}

/// Four plain statics for the reveal tests: Defense 4, one model each.
fn plain_statics() -> Vec<crate::unit::UnitStatic> {
    ["a", "ah", "b", "bh"]
        .iter()
        .map(|n| {
            let mut s = crate::unit::UnitStatic { name: (*n).into(), ..Default::default() };
            s.model_count = 1;
            s.wounds_max = vec![1];
            s.ctx.defense = 4;
            s
        })
        .collect()
}

/// Attacker slot 1, unit 0 standing on the marker; marker secret kind `kind`, owned by `owner`.
fn reveal_board(kind: Option<&str>, owner: i64) -> (State, Vec<i64>) {
    let mut st = role_board(1, 0.0, 0.0);
    place(&mut st, 0, 0.0, 0.5);
    st.markers_meta[0].secret = kind.map(str::to_string);
    st.objectives[0].owner = owner;
    (st, vec![owner])
}

#[test]
fn reveal_removes_an_empty_marker_and_keeps_the_relic() {
    let (mut st, mut owners) = reveal_board(Some(""), 1);
    let (ev, rolls) = apply_reveal_step(&plain_statics(), &mut st, &mut owners, None);
    assert_eq!(ev, vec![Reveal { index: 0, secret: String::new(), unit: 0 }]);
    assert!(rolls.is_empty());
    assert!(st.markers_meta[0].revealed && st.markers_meta[0].destroyed);
    assert_eq!(owners, [0], "an empty marker is gone and nobody owns it");
    let (mut st, mut owners) = reveal_board(Some("relic"), 1);
    let (ev, _) = apply_reveal_step(&plain_statics(), &mut st, &mut owners, None);
    assert_eq!(ev.len(), 1);
    assert!(st.markers_meta[0].revealed && !st.markers_meta[0].destroyed, "the relic stays for the carry step");
    assert_eq!(owners, [1]);
}

#[test]
fn reveal_skips_defender_held_plain_and_already_revealed_markers() {
    for (kind, owner, revealed) in [(Some("trap"), 2, false), (None, 1, false), (Some("trap"), 1, true)] {
        let (mut st, mut owners) = reveal_board(kind, owner);
        st.markers_meta[0].revealed = revealed;
        let (ev, _) = apply_reveal_step(&plain_statics(), &mut st, &mut owners, None);
        assert!(ev.is_empty(), "{kind:?} owner {owner} revealed {revealed}");
        assert!(!st.markers_meta[0].destroyed);
    }
}

#[test]
fn reveal_trap_rolls_d6_plus_one_hits_on_the_tray_and_none_without_one() {
    let (mut st, mut owners) = reveal_board(Some("trap"), 1);
    apply_reveal_step(&plain_statics(), &mut st, &mut owners, None);
    assert_eq!(st.alive[0], 1, "expected-value dice: the trap costs nothing");
    let seed = 11;
    let die = i64::from(Tray::seeded(seed).roll(1)[0]);
    let (mut st, mut owners) = reveal_board(Some("trap"), 1);
    let mut tray = Tray::seeded(seed);
    let (ev, rolls) = apply_reveal_step(&plain_statics(), &mut st, &mut owners, Some(&mut tray));
    assert_eq!(ev[0].secret, "trap");
    assert_eq!(rolls[0].faces, vec![die as u8], "the first tray die is the D6");
    assert_eq!(rolls[1].kind, "defense");
    assert_eq!(rolls[1].count, die + 1, "D6+1 hits go to the save batch");
    let saved = crate::dice::faces_to_hits(&rolls[1].faces, 4) as i64;
    assert_eq!(st.alive[0], if die + 1 - saved > 0 { 0 } else { 1 }, "unsaved hits kill the lone model");
    assert!(st.markers_meta[0].destroyed, "the trap is spent");
}
