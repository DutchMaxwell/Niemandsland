//! The NML-1073 M1-1/M1-2/M1-3 gates, pinned on three recorded fixtures.
//!
//! All three come from the same 1000pt `core_selfplay` game (seed 27,
//! robot_legions vs blessed_sisters); they differ only in which A/B seam was
//! live, and each carries that answer in its own header (`seams`).
//!
//!   * `FIXTURE` — every 10th node of the 2000-node M1-2 recording, both seams
//!     OFF. A systematic sample, not the head: the first 200 nodes are all
//!     round 1 and carry no volley that lands a wound, so a head slice would
//!     pin GATE B without ever exercising the shoot path. Composition: 38 HOLD,
//!     53 ADVANCE, 71 RUSH, 38 CHARGE; 74 rich-leaf, 126 cheap-leaf; 15 shoot
//!     nodes of which 5 land wounds; 2 charges reach contact.
//!   * `SPACING` — every 10th node of the spacing-ON recording
//!     (`NML_SIM_SPACING=1`, the trainer's default going forward): 46 HOLD,
//!     45 ADVANCE, 50 RUSH, 59 CHARGE, of which 40 movers are SHORTENED by the
//!     `_spacing_fraction` clamp.
//!   * `MELEE` — EVERY charge node of the spacing-OFF recording that reached
//!     contact (35 of 518), not a sample. It has to be a spacing-OFF slice:
//!     with the clamp on, a legal move always ends at least (own radius + 1" +
//!     their radius) ~ 2.3" from an enemy model, so no charge can ever get
//!     inside the 1" CONTACT_IN ring and the melee branch is unreachable.
//!     Carries 7 routs and 22 newly-shaken units.
//!   * `CAST` — EVERY node of the cast-ON recording (`NML_SIM_CAST=1`, spacing
//!     also on) whose activation spent a caster token: 93 of 2000, 31 each on
//!     HOLD, RUSH and CHARGE. That HOLD/RUSH/CHARGE split IS the point of
//!     NML-1069 — the legacy rider only ever cast inside a shoot pick, so a
//!     rushing or charging caster never cast at all.
//!
//! GATE A: `score(state_after, player, incoming)` reproduces the recorded score
//! on every node, where `incoming` is `reply_threat` computed in Rust for a RICH
//! leaf and empty for a CHEAP one (`AiPlanner._policy_step` ai_planner.gd:508-510).
//!
//! GATE B: `resolve(state_before, action)` reproduces `state_after` field by
//! field on EVERY node — HOLD, ADVANCE, RUSH and CHARGE. Nothing is silently
//! skipped: a node the port cannot resolve fails the test by name.

use nml_core::{
    build_statics, load_nodes, read_nodes, reply_threat, resolve, score, Seams, State,
};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/nodes_200.jsonl");
const SPACING: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/nodes_200_spacing.jsonl");
const MELEE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/nodes_melee.jsonl");
const CAST: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/nodes_cast.jsonl");
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
        // `mods` moves only through the cast sub-phase (battle_sim.gd:976-982),
        // so it has to be compared or the whole modifier half is untested.
        let (a, b) = (&got.mods[i], &want.mods[i]);
        if (a.hit - b.hit).abs() > EPS
            || (a.def - b.def).abs() > EPS
            || (a.morale - b.morale).abs() > EPS
            || (a.range_in - b.range_in).abs() > EPS
            || (a.advance - b.advance).abs() > EPS
            || (a.rush - b.rush).abs() > EPS
        {
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

/// GATE B on one fixture: every node resolves and matches, and the per-kind
/// composition is pinned so a thinned corpus cannot quietly stop testing a branch.
fn gate_b_on(path: &str, want: [usize; 4]) {
    let corpus = load_nodes(path).expect("fixture loads");
    let statics = build_statics(&corpus, REPO);
    let mut per_kind = [(0usize, 0usize); 4];
    for (i, node) in corpus.nodes.iter().enumerate() {
        let got = match resolve(
            &statics,
            &node.state_before,
            &node.action,
            node.cover_dest,
            corpus.seams,
            node.cast_los(),
        ) {
            Ok(g) => g,
            Err(e) => panic!("node #{}: not resolved — {e:?}", i + 1),
        };
        let k = node.action.kind as usize;
        assert!(k < 4, "node #{}: unexpected action kind {k}", i + 1);
        per_kind[k].0 += 1;
        if states_match(&got, &node.state_after) {
            per_kind[k].1 += 1;
        } else {
            panic!(
                "node #{} (kind {}): resolve() state does not match state_after",
                i + 1,
                node.action.kind
            );
        }
    }
    let totals = [per_kind[0].0, per_kind[1].0, per_kind[2].0, per_kind[3].0];
    assert_eq!(totals, want, "{path}: fixture composition (HOLD, ADVANCE, RUSH, CHARGE)");
    for (k, (tot, ok)) in per_kind.iter().enumerate() {
        assert_eq!(ok, tot, "{path}: GATE B kind {k} — {ok}/{tot} exact");
    }
}

#[test]
fn gate_b_resolve_reproduces_state_after_on_every_kind() {
    gate_b_on(FIXTURE, [38, 53, 71, 38]);
}

/// The same gate on the spacing-ON recording: `resolve` must take the clamp
/// branch because the corpus header says the recording did.
#[test]
fn gate_b_spacing_corpus_resolves_every_kind() {
    let corpus = load_nodes(SPACING).expect("fixture loads");
    assert!(corpus.seams.spacing, "the spacing fixture records spacing=on");
    assert!(!corpus.seams.cast, "and cast=off");
    gate_b_on(SPACING, [46, 45, 50, 59]);
}

/// Red-green for the clamp: resolving the spacing corpus with the seam OFF must
/// break exactly the movers the clamp shortened. Without this the spacing gate
/// could be green on a `resolve` that never clamps, as long as no move was long
/// enough to bite.
#[test]
fn spacing_clamp_is_load_bearing() {
    let corpus = load_nodes(SPACING).expect("fixture loads");
    let statics = build_statics(&corpus, REPO);
    let off = Seams { spacing: false, cast: false };
    let mut broken = 0usize;
    for node in &corpus.nodes {
        let got = resolve(&statics, &node.state_before, &node.action, node.cover_dest, off, node.cast_los())
            .expect("resolves");
        if !states_match(&got, &node.state_after) {
            broken += 1;
        }
    }
    assert_eq!(broken, 40, "dropping the clamp must redden exactly the shortened movers");
}

/// The melee half of the CHARGE branch: every recorded contact, with the
/// strike, the strike-back, the fatigue stamps, the melee morale and the rout.
#[test]
fn gate_b_melee_charges_reproduce_strike_morale_and_rout() {
    let corpus = load_nodes(MELEE).expect("fixture loads");
    let statics = build_statics(&corpus, REPO);
    assert!(!corpus.seams.spacing, "the melee slice is the spacing-OFF recording");
    let mut contacts = 0usize;
    let mut routs = 0usize;
    let mut shaken = 0usize;
    let mut strike_backs = 0usize;
    for (i, node) in corpus.nodes.iter().enumerate() {
        assert_eq!(node.action.kind, nml_core::CHARGE, "the slice is charges only");
        let got = resolve(
            &statics,
            &node.state_before,
            &node.action,
            node.cover_dest,
            corpus.seams,
            node.cast_los(),
        )
        .expect("resolves");
        assert!(
            states_match(&got, &node.state_after),
            "node #{}: charge does not match state_after",
            i + 1
        );
        let si = got.roster.index[node.action.unit.as_str()];
        let ti = got.roster.index[node.action.charge.as_deref().expect("charge target")];
        assert!(got.fatigued[si], "node #{}: the charger is fatigued", i + 1);
        contacts += 1;
        if got.fatigued[ti] && !node.state_before.fatigued[ti] {
            strike_backs += 1;
        }
        for u in [si, ti] {
            if node.state_before.alive[u] > 0 && got.alive[u] == 0 && got.positions[u].is_empty() {
                routs += 1;
            } else if got.shaken[u] && !node.state_before.shaken[u] {
                shaken += 1;
            }
        }
    }
    assert_eq!(contacts, 35, "every recorded contact");
    assert_eq!(routs, 7, "melee morale routs a side seven times");
    assert_eq!(shaken, 22, "and shakes one twenty-two times");
    assert!(strike_backs > 0, "survivors strike back and fatigue the defender");
}

/// Red-green for the CHARGE branch: reading the same nodes as a RUSH (same move,
/// no melee) must break every one of them. Without it the melee gate could be
/// green on a `resolve` whose charge leg never fires.
#[test]
fn the_melee_leg_is_load_bearing() {
    let corpus = load_nodes(MELEE).expect("fixture loads");
    let statics = build_statics(&corpus, REPO);
    let mut broken = 0usize;
    for node in &corpus.nodes {
        let mut as_rush = node.action.clone();
        as_rush.kind = nml_core::RUSH; // same band, same move, no contact check
        let got = resolve(&statics, &node.state_before, &as_rush, node.cover_dest, corpus.seams, node.cast_los())
            .expect("resolves");
        if !states_match(&got, &node.state_after) {
            broken += 1;
        }
    }
    assert_eq!(broken, 35, "every contact node needs the charge leg");
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
        let Ok(got) =
            resolve(&statics, &node.state_before, &node.action, node.cover_dest, corpus.seams, node.cast_los())
        else {
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
        let got = resolve(&statics, &node.state_before, &node.action, Some(!c), corpus.seams, node.cast_los())
            .expect("resolves");
        if !states_match(&got, &node.state_after) {
            flipped += 1;
        }
    }
    assert!(moved > 0, "fixture carries ADVANCE nodes with a cover answer");
    assert_eq!(flipped, moved, "the cover answer reaches in_cover on every mover");
}

/// M1-3b: the cast sub-phase. Every recorded token spend, with the spell the
/// official pick order chose, the target it chose and the damage it dealt.
#[test]
fn gate_b_cast_subphase_reproduces_every_recorded_cast() {
    let corpus = load_nodes(CAST).expect("fixture loads");
    assert!(corpus.seams.cast, "the cast fixture records cast=on");
    let statics = build_statics(&corpus, REPO);
    let mut per_kind = [0usize; 4];
    let mut spent = 0i64;
    for (i, node) in corpus.nodes.iter().enumerate() {
        let got = resolve(
            &statics,
            &node.state_before,
            &node.action,
            node.cover_dest,
            corpus.seams,
            node.cast_los(),
        )
        .expect("resolves");
        assert!(
            states_match(&got, &node.state_after),
            "node #{}: cast node does not match state_after",
            i + 1
        );
        per_kind[node.action.kind as usize] += 1;
        for u in 0..got.units() {
            spent += node.state_before.casts[u] - got.casts[u];
        }
    }
    assert_eq!(per_kind, [31, 0, 31, 31], "HOLD / ADVANCE / RUSH / CHARGE casts");
    assert_eq!(spent, 145, "tokens the sub-phase spent across the slice");
}

/// Red-green for the seam: with `cast` off, `resolve` runs the LEGACY rider
/// instead (spell EV folded into a shoot pick), so every one of these nodes
/// must break. Without this the cast gate could be green on a `resolve` that
/// never enters the sub-phase.
#[test]
fn the_cast_subphase_is_load_bearing() {
    let corpus = load_nodes(CAST).expect("fixture loads");
    let statics = build_statics(&corpus, REPO);
    let legacy = Seams { spacing: true, cast: false };
    let mut broken = 0usize;
    for node in &corpus.nodes {
        let got = resolve(
            &statics,
            &node.state_before,
            &node.action,
            node.cover_dest,
            legacy,
            node.cast_los(),
        )
        .expect("resolves");
        if !states_match(&got, &node.state_after) {
            broken += 1;
        }
    }
    assert_eq!(broken, 93, "the legacy rider reproduces none of the recorded casts");
}

/// Red-green for the recorded POST-move sight answers: dropping them back to
/// the pre-move matrix of `state_before` must break the casts that only became
/// possible after the caster moved. 41 of the 93 do — proof that the answer is
/// a real input and not decoration.
#[test]
fn the_post_move_cast_los_is_a_real_input() {
    let corpus = load_nodes(CAST).expect("fixture loads");
    let statics = build_statics(&corpus, REPO);
    let mut broken = 0usize;
    for node in &corpus.nodes {
        let got = resolve(
            &statics,
            &node.state_before,
            &node.action,
            node.cover_dest,
            corpus.seams,
            None, // fall back to state_before's pre-move los_pairs
        )
        .expect("resolves");
        if !states_match(&got, &node.state_after) {
            broken += 1;
        }
    }
    assert_eq!(broken, 41, "moved casters need the post-move sight answers");
}

/// `AiSpell.official_pick_order` ai_spell.gd:305-312 — the rotation IS rule
/// data (the printed list is indexed by D3 + Caster(X), then cycled forward).
#[test]
fn the_official_pick_order_rotates_by_d3_plus_caster_value() {
    use nml_core::spell::official_pick_order;
    assert_eq!(official_pick_order(6, 1, 0), [0, 1, 2, 3, 4, 5]);
    assert_eq!(official_pick_order(6, 1, 1), [1, 2, 3, 4, 5, 0]);
    assert_eq!(official_pick_order(6, 3, 1), [3, 4, 5, 0, 1, 2]);
    assert_eq!(official_pick_order(4, 3, 3), [1, 2, 3, 0], "wraps");
    assert_eq!(official_pick_order(6, 9, 0), [2, 3, 4, 5, 0, 1], "the face is clamped to 3");
    assert!(official_pick_order(0, 1, 0).is_empty());
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
    c.mods[0].hit += 1.0;
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
