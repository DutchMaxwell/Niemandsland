//! R0 — mission.rs pinned: one test per scoring/vp_flavour arm, hand-computed
//! VP; plus playout_seize (unopposed presence) and can_hold_marker (its three
//! round-end exclusions). No production line touched.
use nml_core::{
    can_hold_marker, mission_winner, playout_seize, read_act_header, sabotage_winner,
    state_from_json, vp_score_end, vp_score_round, Marker, ProfileCache,
};
use serde_json::{json, Map};

fn mk(owned_by: i64, destroyed: bool, destroyed_seq: i64) -> Marker {
    Marker { owned_by, destroyed, destroyed_seq, ..Default::default() }
}

#[test]
fn round_vp_flavours_pitched_battle_and_domination() {
    let (mut vp, mut memo) = ([0i64, 0], Map::new());
    vp_score_round(&[1, 1, 2], &mut vp, &json!({}), &mut memo, &[]);
    assert_eq!(vp, [2, 1], "1 VP/controlled marker, this round");
    vp_score_end(&[1, 1, 2], &mut vp, &json!({}));
    assert_eq!(vp, [3, 1], "pitched_battle: majority bonus deferred to game end");
    let (mut vp2, mut memo2) = ([0i64, 0], Map::new());
    vp_score_round(&[1, 1, 2], &mut vp2, &json!({"majority": "round"}), &mut memo2, &[]);
    assert_eq!(vp2, [3, 1], "domination: majority bonus paid every round");
}

#[test]
fn mosh_pit_pays_the_first_seizer_once() {
    let (mut vp, mut memo) = ([0i64, 0], Map::new());
    let f = json!({"first_seize": true});
    vp_score_round(&[2], &mut vp, &f, &mut memo, &[]);
    assert_eq!(vp, [0, 2], "marker VP + the bounty");
    vp_score_round(&[1], &mut vp, &f, &mut memo, &[]);
    assert_eq!(vp, [1, 2], "already claimed: round 2 pays only the marker");
}

#[test]
fn demolition_pays_a_standing_marker_then_the_revenge_vp() {
    let (mut vp, mut memo) = ([0i64, 0], Map::new());
    let f = json!({"mode": "demolition"});
    vp_score_round(&[], &mut vp, &f, &mut memo, &[mk(1, false, 0), mk(2, true, 2)]);
    assert_eq!(vp, [1, 0], "p1's marker stands; p2's fell but p1's is still up");
    let mut vp2 = [0i64, 0];
    vp_score_round(&[], &mut vp2, &f, &mut memo, &[mk(1, true, 2), mk(2, true, 1)]);
    assert_eq!(vp2, [0, 1], "p2's marker fell FIRST: p2 collects revenge");
}

#[test]
fn sabotage_and_mission_winner_delegates() {
    assert_eq!(sabotage_winner(&[mk(1, false, 0), mk(2, true, 1)]), "p1");
    assert_eq!(sabotage_winner(&[mk(1, true, 1), mk(2, false, 0)]), "p2");
    assert_eq!(sabotage_winner(&[mk(1, false, 0), mk(2, false, 0)]), "draw");
    assert_eq!(sabotage_winner(&[mk(1, true, 1), mk(2, true, 2)]), "draw");
    let m = [mk(1, false, 0), mk(2, true, 1)];
    assert_eq!(mission_winner("sabotage", &[], [0, 0], &m, 0, 0), "p1");
    assert_eq!(mission_winner("round_vp", &[], [5, 3], &[], 0, 0), "p1");
    assert_eq!(mission_winner("round_vp", &[], [3, 3], &[], 0, 0), "draw");
}

#[test]
fn mission_winner_end_by_marker_count_or_by_survivors() {
    assert_eq!(mission_winner("end", &[1, 1, 2], [0, 0], &[], 0, 0), "p1");
    assert_eq!(mission_winner("end", &[1, 2], [0, 0], &[], 0, 0), "draw");
    assert_eq!(mission_winner("end", &[], [0, 0], &[], 3, 1), "p1", "no markers: survivors");
}

const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{"p1_0_a":{"unit_id":"p1_0_a","name":"A"},"p2_0_a":{"unit_id":"p2_0_a","name":"B"},"p1_1_b":{"unit_id":"p1_1_b","name":"C"},"p1_2_c":{"unit_id":"p1_2_c","name":"D"},"p1_3_d":{"unit_id":"p1_3_d","name":"E"}}}"#;

#[test]
fn playout_seize_unopposed_presence_claims_the_marker() {
    const PLAIN: &str = r#"{"round":1,"rounds_total":4,"scoring":"end","objectives":[{"pos":[0,0,0],"owner":0}],"units":{"p1_0_a":{"player":1,"alive":1,"positions":[[0.03,0,0]],"radii":[0.02]},"p2_0_a":{"player":2,"alive":1,"positions":[[3,0,0]],"radii":[0.02]}}}"#;
    let header = read_act_header(HEADER).expect("header");
    let mut cache = ProfileCache::new(header.profiles);
    let mut roster = None;
    let mut st = state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
    let mut owners = vec![0i64];
    playout_seize(&mut st, &mut owners);
    assert_eq!(owners[0], 1, "only p1 is inside the 3\" ring");
    assert_eq!(st.objectives[0].owner, 1);
}

#[test]
fn can_hold_marker_excludes_shaken_aircraft_and_arrived_this_round() {
    const PLAIN: &str = r#"{"round":2,"rounds_total":4,"scoring":"end","units":{"p1_0_a":{"player":1,"alive":1},"p1_1_b":{"player":1,"alive":1,"shaken":true},"p1_2_c":{"player":1,"alive":1,"aircraft":true},"p1_3_d":{"player":1,"alive":1,"ambush_arrived_round":2}}}"#;
    let header = read_act_header(HEADER).expect("header");
    let mut cache = ProfileCache::new(header.profiles);
    let mut roster = None;
    let st = state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
    assert!(can_hold_marker(&st, 0, 2));
    assert!(!can_hold_marker(&st, 1, 2), "shaken");
    assert!(!can_hold_marker(&st, 2, 2), "aircraft");
    assert!(!can_hold_marker(&st, 3, 2), "arrived this round");
}
