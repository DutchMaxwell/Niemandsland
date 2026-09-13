//! `OnnxHook` proofs (M1a-2): the 48 real leaves of `acts_25.jsonl` rebuilt in
//! Rust match the stand-in's golden tensors bit-exactly, their values and member
//! heads match within the fixture tolerance, and the search's pick with the hook
//! equals the pick with a golden-value oracle.
#![cfg(feature = "onnx-tract")]

use nml_core::plan::{plan_with_leaf_value, LeafValue};
use nml_core::rows::RowEncoder;
use nml_core::sim::Unsupported;
use nml_core::state::State;
use nml_core::terrain::Terrain;
use nml_core::tokens::{self, Tokens};
use nml_core::unit::UnitStatic;
use nml_core::ActCorpus;
use nml_core_godot::onnx::{load, Brain};
use nml_core_godot::onnx_hook::OnnxHook;
use serde_json::Value;
use std::cell::{Cell, RefCell};

const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const REAL_LEAVES: usize = 48;

fn fixture(name: &str) -> Vec<u8> {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/onnx")
        .join(name);
    std::fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

fn golden() -> Value {
    serde_json::from_slice(&fixture("golden_standin-v2x2.json")).expect("golden json")
}

fn corpus() -> ActCorpus {
    let path = format!("{ROOT}/core/nml-core/tests/fixtures/acts_25.jsonl");
    nml_core::load_acts(&path).expect("acts_25.jsonl")
}

fn standin() -> Brain {
    let provenance: Value = serde_json::from_slice(&fixture("provenance_standin-v2x2.json")).unwrap();
    let sha = provenance["runs"]["run1"]["raw_sha256"].as_str().unwrap().to_string();
    load(&fixture("standin-v2x2.onnx"), Some(&sha)).expect("the stand-in loads and passes its self-test")
}

/// Keeps every `Tokens` the search prices, in hand-out order, and answers zeros.
/// `opener_seat` is FALSE: the stand-in's golden capture used the trainer
/// statics (`selfplay.py:1189` `TRAINER_STATICS`), and every one of its 48 real
/// leaves carries `glob[5] == 0` — the frame the bit-exact proof needs.
struct Recorder<'a> {
    statics: &'a [UnitStatic],
    terrain: &'a Terrain,
    rows: RefCell<RowEncoder>,
    hero_attach: bool,
    kept: RefCell<Vec<Tokens>>,
}

impl LeafValue for Recorder<'_> {
    fn value(&self, leaves: &[&State], side: i64) -> Result<Vec<f64>, Unsupported> {
        let mut rows = self.rows.borrow_mut();
        let mut kept = self.kept.borrow_mut();
        for state in leaves {
            kept.push(tokens::build(state, side, self.statics, self.terrain, &mut rows,
                &[], -1, self.hero_attach, false)?);
        }
        Ok(vec![0.0; leaves.len()])
    }
}

/// The two-act corpus replay, one recorder instance for both acts.
fn record(corpus: &ActCorpus, statics: &[UnitStatic]) -> Vec<Tokens> {
    let rec = Recorder {
        statics,
        terrain: &corpus.terrain,
        rows: RefCell::new(RowEncoder::new(ROOT)),
        hero_attach: corpus.knobs.hero_attach,
        kept: RefCell::new(Vec::new()),
    };
    for act in &corpus.acts[..2] {
        plan_with_leaf_value(&act.state, &corpus.terrain, statics, &corpus.knobs,
            &act.statics, act.player, None, Some(&rec), 1.0)
            .unwrap_or_else(|e| panic!("act {}: {e:?}", act.round));
    }
    rec.kept.into_inner()
}

/// The golden expected values, sliced for the leaves handed in this call.
struct Oracle<'a> {
    expected: &'a [f64],
    cursor: Cell<usize>,
}

impl LeafValue for Oracle<'_> {
    fn value(&self, leaves: &[&State], _side: i64) -> Result<Vec<f64>, Unsupported> {
        let start = self.cursor.get();
        let end = start + leaves.len();
        self.cursor.set(end);
        Ok(self.expected[start..end].to_vec())
    }
}

fn expected_values(golden: &Value) -> Vec<f64> {
    golden["expected"]["value"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_f64().unwrap())
        .collect()
}

fn expected_member_values(golden: &Value) -> Vec<Vec<f64>> {
    golden["expected"]["member_values"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| m.as_array().unwrap().iter().map(|v| v.as_f64().unwrap()).collect())
        .collect()
}

/// Proof 1 — the corpus replay rebuilds exactly the 48 real leaves, 26 + 22.
#[test]
fn real_leaves_rebuild_in_hand_out_order() {
    let golden = golden();
    let provenance: Value = serde_json::from_slice(&fixture("provenance_standin-v2x2.json")).unwrap();
    let corpus = corpus();
    let statics = nml_core::build_act_statics(&corpus, ROOT);
    let tokens = record(&corpus, &statics);

    let sourced = |act: &str| {
        golden["leaves"].as_array().unwrap().iter()
            .filter(|leaf| leaf["source"].as_str().unwrap_or("").starts_with(&format!("acts_25:{act}:")))
            .count()
    };
    assert_eq!(sourced("act0"), 26);
    assert_eq!(sourced("act1"), 22);
    assert_eq!(provenance["verify"]["real_leaves"].as_u64().unwrap() as usize, REAL_LEAVES);
    assert_eq!(tokens.len(), REAL_LEAVES, "the replay must hand out exactly the 48 real leaves");
    eprintln!("ONNX_HOOK proof=tokens leaves={} act0=26 act1=22", tokens.len());
}

/// Proof 2 — every one of the six tensors is bit-identical to the golden leaf.
#[test]
fn real_leaf_tokens_match_the_golden_bit_exactly() {
    let golden = golden();
    let corpus = corpus();
    let statics = nml_core::build_act_statics(&corpus, ROOT);
    let tokens = record(&corpus, &statics);
    assert_eq!(tokens.len(), REAL_LEAVES);

    for (i, token) in tokens.iter().enumerate() {
        let json = token.to_json();
        for key in ["units", "units_mask", "objs", "objs_mask", "terr", "glob"] {
            assert_eq!(json[key], golden["leaves"][i][key], "leaf {i} tensor {key}");
        }
    }
    eprintln!("ONNX_HOOK proof=token_identity leaves={} tensors=6 status=bit_exact", tokens.len());
}

/// Proof 3 — the values (and both member heads) match the golden within 1e-5;
/// 48 tokens are one 32-row and one 16-row padded chunk, so the tail is covered.
#[test]
fn real_leaf_values_and_members_match_the_golden_within_tolerance() {
    let golden = golden();
    let corpus = corpus();
    let statics = nml_core::build_act_statics(&corpus, ROOT);
    let tokens = record(&corpus, &statics);
    let brain = standin();
    let act = &corpus.acts[0];
    let hook = OnnxHook {
        brain: &brain,
        statics: &statics,
        terrain: &corpus.terrain,
        rows: RefCell::new(RowEncoder::new(ROOT)),
        hero_attach: corpus.knobs.hero_attach,
        opener_seat: act.statics.opener_seat,
    };

    let (values, members) = hook.run_tokens(&tokens).expect("tract runs the 48 real leaves");
    assert_eq!(values.len(), tokens.len());
    assert_eq!(members.len(), tokens.len() * brain.members());
    assert_eq!(brain.members(), 2);

    let tolerance = golden["tolerance"].as_f64().unwrap();
    let expected = expected_values(&golden);
    let expected_members = expected_member_values(&golden);
    let (mut value_max_abs, mut member_max_abs) = (0.0_f64, 0.0_f64);
    for i in 0..tokens.len() {
        let got = f64::from(values[i]);
        value_max_abs = value_max_abs.max((got - expected[i]).abs());
        assert!(value_max_abs <= tolerance, "value leaf {i}: {got} vs {} (tol {tolerance})", expected[i]);
        for (m, want) in expected_members.iter().enumerate() {
            let got = f64::from(members[i * brain.members() + m]);
            member_max_abs = member_max_abs.max((got - want[i]).abs());
            assert!(member_max_abs <= tolerance, "member {m} leaf {i}: {got} vs {} (tol {tolerance})", want[i]);
        }
    }
    assert_eq!(tokens.chunks(brain.static_batch()).map(|chunk| chunk.len()).collect::<Vec<_>>(),
        vec![32, 16], "the 48 tokens must cover the padded tail path");
    eprintln!("ONNX_HOOK proof=values leaves={} value_max_abs={value_max_abs:.3e} \
        member_max_abs={member_max_abs:.3e} chunked=32+16", tokens.len());
}

/// Proof 4 — the pick with `OnnxHook` equals the pick with a golden oracle.
#[test]
fn onnx_pick_equals_the_golden_oracle_pick_on_act0() {
    let golden = golden();
    let corpus = corpus();
    let statics = nml_core::build_act_statics(&corpus, ROOT);
    let brain = standin();
    let act = &corpus.acts[0];
    // The golden oracle answers the fixture's own capture frame, so the hook
    // that must be equal to it scores that same frame (glob[5] == 0).
    let hook = OnnxHook {
        brain: &brain,
        statics: &statics,
        terrain: &corpus.terrain,
        rows: RefCell::new(RowEncoder::new(ROOT)),
        hero_attach: corpus.knobs.hero_attach,
        opener_seat: false,
    };
    let expected = expected_values(&golden);
    let oracle = Oracle { expected: &expected, cursor: Cell::new(0) };

    let onnx = plan_with_leaf_value(&act.state, &corpus.terrain, &statics, &corpus.knobs,
        &act.statics, act.player, None, Some(&hook), 1.0).expect("onnx pick");
    let gold = plan_with_leaf_value(&act.state, &corpus.terrain, &statics, &corpus.knobs,
        &act.statics, act.player, None, Some(&oracle), 1.0).expect("golden oracle pick");

    assert_eq!(oracle.cursor.get(), 26, "act0's leaf batch must be the golden act0 slice");
    assert_eq!(onnx.unit_key, gold.unit_key, "pick unit differs from the golden oracle");
    assert_eq!(format!("{:?}", onnx.action), format!("{:?}", gold.action),
        "pick action differs from the golden oracle");
    eprintln!("ONNX_HOOK proof=decision_identity unit={} oracle_leaves={} status=equal",
        onnx.unit_key, oracle.cursor.get());
}
