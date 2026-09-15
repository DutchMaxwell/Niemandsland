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
    // The stand-in's golden leaves were captured with the ACTS_25 legacy pin
    // (`core/nml-core/tests/common/mod.rs`, the generator's
    // `set_legacy_no_cond_ap(True)`), and the pin has to be set before
    // `build_act_statics` stamps `UnitStatic`. Without it the fixture's
    // pre-NML-1103 AP pricing is not what the replay prices.
    nml_core::unit::LEGACY_NO_COND_AP.store(true, std::sync::atomic::Ordering::Relaxed);
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
    calls: RefCell<Vec<usize>>,
}

impl LeafValue for Recorder<'_> {
    fn value(&self, leaves: &[&State], side: i64) -> Result<Vec<f64>, Unsupported> {
        let mut rows = self.rows.borrow_mut();
        let mut kept = self.kept.borrow_mut();
        self.calls.borrow_mut().push(leaves.len());
        for state in leaves {
            kept.push(tokens::build(state, side, self.statics, self.terrain, &mut rows,
                &[], -1, self.hero_attach, false, nml_core::acts::CURRENT_RULES_EPOCH)?);
        }
        Ok(vec![0.0; leaves.len()])
    }
}

/// The two-act corpus replay, one recorder instance for both acts. Returns the
/// tokens in hand-out order plus the leaf count of each `value()` call. The
/// golden capture kept at most 48 leaves (`onnx_export.py:229` `keep=48`), so
/// the first 48 are the fixture's real leaves and the tail (if the replay hands
/// out more) is beyond the fixture by construction.
fn record(corpus: &ActCorpus, statics: &[UnitStatic]) -> (Vec<Tokens>, Vec<usize>) {
    let rec = Recorder {
        statics,
        terrain: &corpus.terrain,
        rows: RefCell::new(RowEncoder::for_version(ROOT, corpus.knobs.rule_vocab_version)),
        hero_attach: corpus.knobs.hero_attach,
        kept: RefCell::new(Vec::new()),
        calls: RefCell::new(Vec::new()),
    };
    for act in &corpus.acts[..2] {
        plan_with_leaf_value(&act.state, &corpus.terrain, statics, &corpus.knobs,
            &act.statics, act.player, None, Some(&rec), 1.0)
            .unwrap_or_else(|e| panic!("act {}: {e:?}", act.round));
    }
    (rec.kept.into_inner(), rec.calls.into_inner())
}

/// The recorder's hand-out order sliced the way the fixture keeps it.
fn real_tokens<'a>(all: &'a [Tokens], calls: &[usize]) -> &'a [Tokens] {
    assert_eq!(calls.len(), 2, "one leaf batch per activation");
    assert_eq!(calls[0], 26, "act0 must hand out 26 leaves");
    assert!(calls[1] >= 22, "act1 must hand out at least the 22 the fixture kept");
    assert_eq!(all.len(), calls.iter().sum::<usize>(), "the calls and the kept tokens disagree");
    assert!(all.len() >= REAL_LEAVES, "the replay handed out {} leaves, fewer than 48", all.len());
    &all[..REAL_LEAVES]
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

/// Proof 1 — the corpus replay rebuilds the 48 real leaves, 26 + 22.
#[test]
fn real_leaves_rebuild_in_hand_out_order() {
    let golden = golden();
    let provenance: Value = serde_json::from_slice(&fixture("provenance_standin-v2x2.json")).unwrap();
    let corpus = corpus();
    let statics = nml_core::build_act_statics(&corpus, ROOT);
    let (all, calls) = record(&corpus, &statics);
    let tokens = real_tokens(&all, &calls);

    let sourced = |act: &str| {
        golden["leaves"].as_array().unwrap().iter()
            .filter(|leaf| leaf["source"].as_str().unwrap_or("").starts_with(&format!("acts_25:{act}:")))
            .count()
    };
    assert_eq!(sourced("act0"), 26);
    assert_eq!(sourced("act1"), 22);
    assert_eq!(provenance["verify"]["real_leaves"].as_u64().unwrap() as usize, REAL_LEAVES);
    assert_eq!(tokens.len(), REAL_LEAVES);
    eprintln!("ONNX_HOOK proof=tokens leaves={} calls={calls:?}", tokens.len());
}

/// Compares one token tensor with the golden at f32 precision, recursing
/// through the nested arrays of the token contract. The golden stores
/// shortest-f32 decimals and `to_json` promotes the same f32 to f64, so serde
/// `Value` equality at f64 can never hold.
fn assert_tensor_f32_eq(got: &Value, want: &Value, ctx: &str) {
    match (got, want) {
        (Value::Array(g), Value::Array(w)) => {
            assert_eq!(g.len(), w.len(), "{ctx}: arrays of different length");
            for (j, (gv, wv)) in g.iter().zip(w).enumerate() {
                assert_tensor_f32_eq(gv, wv, &format!("{ctx}[{j}]"));
            }
        }
        (Value::Number(_), Value::Number(_)) => {
            let (g, w) = (got.as_f64().unwrap() as f32, want.as_f64().unwrap() as f32);
            assert_eq!(g, w, "{ctx}: f32 {g} vs {w}");
        }
        _ => panic!("{ctx}: expected nested numbers, got {got} vs {want}"),
    }
}

/// Proof 2 — every one of the six tensors is bit-identical to the golden leaf.
#[test]
fn real_leaf_tokens_match_the_golden_bit_exactly() {
    let golden = golden();
    let corpus = corpus();
    let statics = nml_core::build_act_statics(&corpus, ROOT);
    let (all, calls) = record(&corpus, &statics);
    let tokens = real_tokens(&all, &calls);

    for (i, token) in tokens.iter().enumerate() {
        let json = token.to_json();
        for key in ["units", "units_mask", "objs", "objs_mask", "terr", "glob"] {
            if key != "units" {
                assert_tensor_f32_eq(&json[key], &golden["leaves"][i][key],
                    &format!("leaf {i} tensor {key}"));
                continue;
            }
            // The splice rides past the v1 contract: the live row is F_U 91,
            // the golden leaf is the v1 export (90). The v1 projection — the
            // first 88 design fields verbatim, the v1 pads zero — must be
            // bit-identical to the golden row, and the splice columns the v1
            // row never carried must read exactly zero on this pre-ledger
            // corpus (no `ledger` key on any unit).
            let got = json["units"].as_array().unwrap();
            let want = golden["leaves"][i]["units"].as_array().unwrap();
            let v1 = want[0].as_array().unwrap().len();
            assert_eq!(got.len(), want.len(), "leaf {i} units rows");
            for (r, (g, w)) in got.iter().zip(want).enumerate() {
                let row = g.as_array().unwrap();
                assert!(row.len() > v1, "leaf {i} units[{r}]: no splice columns past the v1 width");
                assert_tensor_f32_eq(&Value::Array(row[..v1].to_vec()), w,
                    &format!("leaf {i} units[{r}] (v1 view)"));
                for (k, col) in row[v1..].iter().enumerate() {
                    assert_eq!(col.as_f64().unwrap() as f32, 0.0,
                        "leaf {i} units[{r}][{}] (splice col) must read 0", v1 + k);
                }
            }
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
    let (all, calls) = record(&corpus, &statics);
    let tokens = real_tokens(&all, &calls);
    let brain = standin();
    let act = &corpus.acts[0];
    let hook = OnnxHook {
        brain: &brain,
        statics: &statics,
        terrain: &corpus.terrain,
        rows: RefCell::new(RowEncoder::for_version(ROOT, corpus.knobs.rule_vocab_version)),
        hero_attach: corpus.knobs.hero_attach,
        opener_seat: act.statics.opener_seat,
    };

    let (values, members) = hook.run_tokens(tokens).expect("tract runs the 48 real leaves");
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
        rows: RefCell::new(RowEncoder::for_version(ROOT, corpus.knobs.rule_vocab_version)),
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
