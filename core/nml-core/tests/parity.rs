//! NML-1073 M1-1 gate, pinned: the hand score of the Rust port must reproduce
//! the score the GDScript planner recorded for the same node.
//!
//! The fixture is the first 200 nodes of the M1-0 recording
//! (`~/selfplay_out/m1_0/run1/nodes.jsonl`, seed 27, 1000pt core_selfplay).
//!
//! DOCUMENTED GAP: `AiPlanner._policy_step` (ai_planner.gd:508-510) prices the
//! RICH leaf as `AiMissionEval.score(next, player, BattleSim.reply_threat(next,
//! player))`. Those nodes — in this recording every node of the planning side,
//! player 2 — carry a reply-threat term the port cannot produce yet: it needs
//! `AiEv.shoot_ev` + `AiShooting` + `AiCombatMath` + `spell_ev_of`, which plan
//! step M1-2 owns. The cheap-leaf nodes (player 1) pass with 0 exceptions, and
//! the threat can only ever SUBTRACT (`_presence` ai_mission_eval.gd:617), so
//! every rich-leaf node must come out `rust >= recorded` — both are asserted.

use nml_core::{load_nodes, read_nodes, score, NO_INCOMING};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/nodes_200.jsonl");

#[test]
fn cheap_leaf_nodes_match_the_recorded_score() {
    let corpus = load_nodes(FIXTURE).expect("fixture loads");
    assert_eq!(corpus.nodes.len(), 200, "fixture size");

    let mut matched = 0usize;
    let mut max_abs_matching = 0.0f64;
    for (i, node) in corpus.nodes.iter().enumerate() {
        let got = score(&node.state_after, node.player, NO_INCOMING);
        let diff = got - node.score;
        assert!(
            diff >= -1e-9,
            "node #{}: rust {got} BELOW recorded {} — a reply threat can only \
             lower the score, so a negative gap is a real port bug",
            i + 1,
            node.score
        );
        if diff.abs() <= 1e-9 {
            matched += 1;
            max_abs_matching = max_abs_matching.max(diff.abs());
        }
    }
    // 137 of the first 200 nodes score identically without a reply threat: all
    // 133 cheap-leaf (player 1) nodes plus 4 rich-leaf nodes whose threat map
    // happened to be empty.
    assert_eq!(matched, 137, "nodes within 1e-9 without a reply threat");
    assert!(
        max_abs_matching < 1e-14,
        "matching nodes should differ only by the recorder's ~15-digit decimal \
         truncation, got {max_abs_matching:e}"
    );
}

#[test]
fn every_cheap_leaf_player_is_exact() {
    let corpus = load_nodes(FIXTURE).expect("fixture loads");
    let mut total = 0usize;
    let mut exact = 0usize;
    for node in corpus.nodes.iter().filter(|n| n.player == 1) {
        total += 1;
        let got = score(&node.state_after, node.player, NO_INCOMING);
        if (got - node.score).abs() <= 1e-9 {
            exact += 1;
        }
    }
    assert!(total > 0, "fixture carries cheap-leaf nodes");
    assert_eq!(exact, total, "every player-1 (cheap-leaf) node within 1e-9");
}

/// The `units` object carries capture order in its key order and the port must
/// keep it — seize and threat tie-breaks read it. This game's keys happen to be
/// lexicographically sorted, so the fixture alone cannot tell a document-order
/// loader from a sorting one; the hand-written corpus below can.
#[test]
fn units_keep_document_order_not_sorted_order() {
    let corpus = read_nodes(std::io::Cursor::new(UNSORTED_CORPUS), "inline").expect("loads");
    let st = &corpus.nodes[0].state_after;
    let keys: Vec<&str> = (0..st.units()).map(|i| st.key(i)).collect();
    assert_eq!(keys, ["z_second", "a_first"], "document order, not sorted");
    assert_eq!(st.player, [2, 1], "per-unit arrays follow the same order");
    assert_eq!(st.profile(0).name, "Zed", "profile index follows the roster");
}

#[test]
fn fixture_roster_is_the_recorded_roster() {
    let corpus = load_nodes(FIXTURE).expect("fixture loads");
    let st = &corpus.nodes[0].state_after;
    assert_eq!(st.units(), 13);
    assert_eq!(st.key(0), "p1_0_lcEWPMS", "first captured unit");
    assert_eq!(st.key(12), "p2_5__nVdDbE", "last captured unit");
    assert_eq!(st.player, [1, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2]);
}

const UNSORTED_CORPUS: &str = concat!(
    r#"{"profiles":{"z_second":{"unit_id":"z_second","name":"Zed","move_bands":{"advance":6,"rush":12}},"#,
    r#""a_first":{"unit_id":"a_first","name":"Ay","move_bands":{"advance":4,"rush":8}}}}"#,
    "\n",
    r#"{"player":1,"score":0.5,"action":{"kind":0,"unit":"a_first"},"#,
    r#""state_before":{"round":1,"rounds_total":4,"scoring":"end","objectives":[],"units":{}},"#,
    r#""state_after":{"round":1,"rounds_total":4,"scoring":"end","objectives":[],"units":{"#,
    r#""z_second":{"player":2,"alive":1,"wounds":[1],"radii":[0.016],"positions":[[0,0,0]]},"#,
    r#""a_first":{"player":1,"alive":1,"wounds":[1],"radii":[0.016],"positions":[[0,0,0]]}}}}"#,
    "\n"
);

#[test]
fn clone_is_deep_where_the_gdscript_clone_is_deep() {
    let corpus = load_nodes(FIXTURE).expect("fixture loads");
    let st = &corpus.nodes[0].state_after;
    let mut c = st.clone();
    c.positions[0][0][0] += 1.0;
    c.wounds[0][0] -= 1;
    c.mods[0].hit += 1;
    assert_ne!(c.positions[0][0][0], st.positions[0][0][0], "positions deep");
    assert_ne!(c.wounds[0][0], st.wounds[0][0], "wounds deep");
    assert_ne!(c.mods[0].hit, st.mods[0].hit, "mods per clone");
    assert!(
        std::rc::Rc::ptr_eq(&c.mods_base[0], &st.mods_base[0]),
        "mods_base shared (battle_sim.gd:478-480)"
    );
    assert!(
        std::rc::Rc::ptr_eq(&c.roster, &st.roster),
        "roster/profile refs shared like the GameUnit refs"
    );
}
