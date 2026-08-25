//! The NML-1073 M1-1/M1-2 gates, pinned on a 200-node fixture.
//!
//! Fixture = every 10th node of the 2000-node M1-2 recording
//! (`~/selfplay_out/m1_2/run1/nodes.jsonl`, 1000pt core_selfplay seed 27,
//! robot_legions vs blessed_sisters, both A/B seams off). A systematic sample,
//! not the head: the first 200 nodes are all round 1 and carry no volley that
//! lands a wound, so a head slice would pin GATE B without ever exercising the
//! shoot path. Composition: 38 HOLD, 53 ADVANCE, 71 RUSH, 38 CHARGE;
//! 74 rich-leaf, 126 cheap-leaf; 15 shoot nodes of which 5 land wounds.
//!
//! GATE A: `score(state_after, player, incoming)` reproduces the recorded score
//! on every node, where `incoming` is `reply_threat` computed in Rust for a RICH
//! leaf and empty for a CHEAP one (`AiPlanner._policy_step` ai_planner.gd:508-510).
//!
//! GATE B: `resolve(state_before, action)` reproduces `state_after` field by
//! field on every HOLD and ADVANCE node. RUSH and CHARGE are reported as
//! unsupported (plan step M1-3), never silently counted as passes.

use nml_core::sim::Unsupported;
use nml_core::{build_statics, load_nodes, read_nodes, reply_threat, resolve, score, State};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/nodes_200.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const EPS: f64 = 1e-9;

fn incoming_for(statics: &[nml_core::UnitStatic], node: &nml_core::Node) -> Vec<f64> {
    if node.rich {
        reply_threat(statics, &node.state_after, node.player)
    } else {
        Vec::new()
    }
}

/// Every field `resolve` may write, plus the ones it must leave alone.
fn states_match(got: &State, want: &State) -> bool {
    if got.units() != want.units() {
        return false;
    }
    if got.player != want.player
        || got.alive != want.alive
        || got.activated != want.activated
        || got.shaken != want.shaken
        || got.fatigued != want.fatigued
        || got.in_cover != want.in_cover
        || got.aircraft != want.aircraft
        || got.casts != want.casts
        || got.morale_bonus != want.morale_bonus
        || got.ambush_arrived_round != want.ambush_arrived_round
        || got.wounds != want.wounds
        || got.round != want.round
        || got.rounds_total != want.rounds_total
    {
        return false;
    }
    for i in 0..got.units() {
        if (got.wound_frac[i] - want.wound_frac[i]).abs() > EPS {
            return false;
        }
        if got.positions[i].len() != want.positions[i].len() || got.radii[i].len() != want.radii[i].len() {
            return false;
        }
        for (a, b) in got.positions[i].iter().zip(&want.positions[i]) {
            if (0..3).any(|k| (a[k] - b[k]).abs() > EPS) {
                return false;
            }
        }
        for (a, b) in got.radii[i].iter().zip(&want.radii[i]) {
            if (a - b).abs() > EPS {
                return false;
            }
        }
    }
    true
}

#[test]
fn gate_a_every_node_scores_within_1e_9() {
    let corpus = load_nodes(FIXTURE).expect("fixture loads");
    assert_eq!(corpus.nodes.len(), 200, "fixture size");
    let statics = build_statics(&corpus, REPO);

    let mut exact = 0usize;
    let mut rich = 0usize;
    let mut max_abs = 0.0f64;
    for (i, node) in corpus.nodes.iter().enumerate() {
        if node.rich {
            rich += 1;
        }
        let got = score(&node.state_after, node.player, &incoming_for(&statics, node));
        let d = (got - node.score).abs();
        max_abs = max_abs.max(d);
        if d <= EPS {
            exact += 1;
        } else {
            panic!(
                "node #{} (player {}, rich {}): rust {got:.17} vs recorded {:.17}, diff {d:e}",
                i + 1,
                node.player,
                node.rich,
                node.score
            );
        }
    }
    assert_eq!(exact, 200, "GATE A: every node within 1e-9");
    assert!(rich > 0 && rich < 200, "fixture carries BOTH leaf kinds, got {rich} rich");
    assert!(
        max_abs < 1e-14,
        "matching nodes should differ only by float noise, got {max_abs:e}"
    );
}

/// Red-green for GATE A: pricing a RICH node with the CHEAP leaf must break it.
/// Without this the gate could be green because the threat is always zero.
#[test]
fn gate_a_reddens_when_the_reply_threat_is_dropped() {
    let corpus = load_nodes(FIXTURE).expect("fixture loads");
    let mut broken = 0usize;
    let mut rich = 0usize;
    for node in corpus.nodes.iter().filter(|n| n.rich) {
        rich += 1;
        let cheap = score(&node.state_after, node.player, &[]);
        if (cheap - node.score).abs() > EPS {
            broken += 1;
        }
    }
    assert!(rich > 0, "fixture carries rich-leaf nodes");
    assert!(
        broken * 2 > rich,
        "dropping the threat must redden most rich nodes, only {broken}/{rich} moved"
    );
}

#[test]
fn gate_b_resolve_reproduces_state_after_on_hold_and_advance() {
    let corpus = load_nodes(FIXTURE).expect("fixture loads");
    let statics = build_statics(&corpus, REPO);
    let mut hold = (0usize, 0usize);
    let mut advance = (0usize, 0usize);
    let mut unsupported = 0usize;
    for (i, node) in corpus.nodes.iter().enumerate() {
        match resolve(&statics, &node.state_before, &node.action, node.cover_dest) {
            Ok(got) => {
                let slot = if node.action.kind == nml_core::HOLD {
                    &mut hold
                } else {
                    &mut advance
                };
                slot.0 += 1;
                if states_match(&got, &node.state_after) {
                    slot.1 += 1;
                } else {
                    panic!("node #{}: resolve() state does not match state_after", i + 1);
                }
            }
            Err(Unsupported::ActionKind(k)) => {
                assert!(k == nml_core::RUSH || k == nml_core::CHARGE, "unexpected kind {k}");
                unsupported += 1;
            }
            Err(e) => panic!("node #{}: {e:?}", i + 1),
        }
    }
    assert!(hold.0 > 0 && advance.0 > 0, "fixture carries HOLD and ADVANCE nodes");
    assert_eq!(hold.1, hold.0, "GATE B: every HOLD node exact");
    assert_eq!(advance.1, advance.0, "GATE B: every ADVANCE node exact");
    assert_eq!(
        hold.0 + advance.0 + unsupported,
        200,
        "every node is either resolved or reported, none silently skipped"
    );
}

/// Red-green for GATE B's shoot path: GATE B would be green on a `resolve()`
/// that never fires a shot, as long as the recorded volleys all dealt zero. So
/// count the volleys that actually MOVE the defender — the fixture carries 15
/// shoot nodes, 5 of which land expected wounds (the rest are out of range, out
/// of sight, or worth exactly nothing).
#[test]
fn gate_b_shoot_nodes_actually_deal_damage() {
    let corpus = load_nodes(FIXTURE).expect("fixture loads");
    let statics = build_statics(&corpus, REPO);
    let mut shooters = 0usize;
    let mut changed = 0usize;
    for node in corpus.nodes.iter() {
        let Some(target) = node.action.shoot.as_deref() else {
            continue;
        };
        shooters += 1;
        let Ok(got) = resolve(&statics, &node.state_before, &node.action, node.cover_dest) else {
            continue;
        };
        let ti = node.state_before.roster.index[target];
        if got.wound_frac[ti] != node.state_before.wound_frac[ti]
            || got.wounds[ti] != node.state_before.wounds[ti]
        {
            changed += 1;
        }
    }
    assert_eq!(shooters, 15, "fixture's HOLD+shoot nodes");
    assert_eq!(changed, 5, "volleys that land expected wounds");
}

/// Red-green for the recorded terrain answer: flipping `cover_dest` must change
/// the resolved state of a node that moves, or the answer is not being read.
#[test]
fn gate_b_reddens_when_the_cover_answer_is_flipped() {
    let corpus = load_nodes(FIXTURE).expect("fixture loads");
    let statics = build_statics(&corpus, REPO);
    let mut moved = 0usize;
    let mut flipped = 0usize;
    for node in corpus.nodes.iter().filter(|n| n.action.kind == nml_core::ADVANCE) {
        let Some(c) = node.cover_dest else { continue };
        moved += 1;
        let got = resolve(&statics, &node.state_before, &node.action, Some(!c)).expect("resolves");
        if !states_match(&got, &node.state_after) {
            flipped += 1;
        }
    }
    assert!(moved > 0, "fixture carries ADVANCE nodes with a cover answer");
    assert_eq!(flipped, moved, "the cover answer reaches in_cover on every mover");
}

/// The port must NAME what it does not implement. An empty list here is the
/// claim "this corpus fields no unmodelled rule" — a new corpus that does will
/// fail loudly instead of scoring around it.
#[test]
fn unimplemented_rules_are_listed_not_hidden() {
    let corpus = load_nodes(FIXTURE).expect("fixture loads");
    let statics = build_statics(&corpus, REPO);
    let names: Vec<&str> = statics
        .iter()
        .flat_map(|u| u.unimplemented.iter().map(|x| x.rule.as_str()))
        .collect();
    assert!(
        names.is_empty(),
        "unimplemented rules in this corpus: {names:?} — extend the port or the report"
    );
}

/// …and the empty list above is only worth something if the lane can fire.
/// Sergeant IS in the gf mechanics map (`assets/solo/rules_mechanics_gf.json`,
/// primitive "Sergeant") and its per-bearer attack share reads a live alive
/// count the static profile does not carry — so a unit that fields it must be
/// REPORTED, not quietly scored without the facet.
#[test]
fn an_unmodelled_rule_is_reported_when_a_unit_fields_it() {
    let corpus = read_nodes(std::io::Cursor::new(SERGEANT_CORPUS), "inline").expect("loads");
    let statics = build_statics(&corpus, REPO);
    let reported: Vec<&str> = statics[0].unimplemented.iter().map(|u| u.rule.as_str()).collect();
    assert_eq!(reported, ["Sergeant"], "the reporting lane fires");
    assert!(
        statics[0].unimplemented[0].why.contains("get_alive_count"),
        "the reason names the missing input"
    );
}

const SERGEANT_CORPUS: &str = concat!(
    r#"{"profiles":{"sarge":{"unit_id":"sarge","name":"Sarge","game_system":"gf","#,
    r#""special_rules":["Sergeant"],"quality":4,"defense":4,"model_count":5,"#,
    r#""weapons":[{"name":"Rifle","range":24,"attacks":1,"count":5,"ap":0,"rules":[]}]}}}"#,
    "\n",
    r#"{"player":1,"score":0.5,"rich":false,"action":{"kind":0,"unit":"sarge"},"#,
    r#""state_before":{"round":1,"rounds_total":4,"scoring":"end","objectives":[],"units":{}},"#,
    r#""state_after":{"round":1,"rounds_total":4,"scoring":"end","objectives":[],"units":{}}}"#,
    "\n"
);

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
