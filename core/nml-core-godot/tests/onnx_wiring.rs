//! Wiring proof (M1a-4): `NML_BRAIN_ONNX` drives the plan seam's leaf brain.
//!
//! One test, two phases, through the narrowest entries the existing tests
//! already drive: `onnx_brain_from_env` (the `set_game_header` env leg) and
//! `plan_with_onnx` (the `plan_with_rollout` ONNX-precedence leg — the same
//! call the godot class makes before marshalling `out["brain"]`). Phase one
//! proves `brain.name == "onnx"`, `batches >= 1` and the recorded sha256;
//! phase two proves the unset env loads nothing — the default route whose
//! pick is serialized without a `brain` key — and still plans unarmed.
#![cfg(feature = "onnx-tract")]

use nml_core::plan::{plan_with_leaf_value, LeafValue};
use nml_core_godot::{onnx_brain_from_env, plan_with_onnx};

const ROOT: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

#[test]
fn nml_brain_onnx_wires_the_leaf_brain_and_unset_leaves_it_out() {
    let path = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/onnx/standin-v2x2.onnx");
    std::env::set_var("NML_BRAIN_ONNX", path);
    std::env::remove_var("NML_BRAIN_ONNX_SHA256");

    // Phase one — env set: the header leg loads the stand-in and records its
    // sha256; the plan leg prices the search through tract and answers the
    // brain record with batches >= 1.
    let (brain, sha) = onnx_brain_from_env()
        .unwrap_or_else(|| panic!("NML_BRAIN_ONNX is set but no load was attempted"))
        .unwrap_or_else(|e| panic!("the stand-in declined: {e}"));
    assert_eq!(sha.len(), 64, "the sha256 record is hex-encoded");
    let corpus = nml_core::load_acts(&format!("{ROOT}/core/nml-core/tests/fixtures/acts_25.jsonl"))
        .expect("acts_25.jsonl");
    let statics = nml_core::build_act_statics(&corpus, ROOT);
    let act = &corpus.acts[0];
    let (_pick, run) = plan_with_onnx(&act.state, &corpus.terrain, &statics,
        &corpus.knobs, &act.statics, act.player, None, ROOT, &brain)
        .expect("the onnx-wired plan declines nothing on act0");
    assert_eq!(run.name, "onnx");
    assert_eq!(run.hash, sha, "the brain record carries the same sha256");
    assert!(run.batches >= 1, "the search consumed at least one batch");
    eprintln!("ONNX_WIRING proof=env name={} batches={} batch_us={}",
        run.name, run.batches, run.batch_us);

    // Phase two — env unset: the header leg loads nothing, so the plan takes
    // the default path (no hook) whose pick is serialized without a brain key.
    std::env::remove_var("NML_BRAIN_ONNX");
    assert!(onnx_brain_from_env().is_none(), "unset env must mean no brain");
    plan_with_leaf_value(&act.state, &corpus.terrain, &statics, &corpus.knobs,
        &act.statics, act.player, None, None::<&dyn LeafValue>, 0.0)
        .expect("the default path still plans");
}

/// The vocab-3 contract (`units32x91`): a real export, when the lab points at one.
/// `NML_ONNX_REAL=<path>` (never a repo fixture — the nets are private); unset = skipped
/// loudly, never green by silence.
#[test]
fn a_units32x91_export_prices_the_search_when_provided() {
    let Ok(path) = std::env::var("NML_ONNX_REAL") else {
        eprintln!("ONNX_WIRING real-model leg SKIPPED: NML_ONNX_REAL unset");
        return;
    };
    let bytes = std::fs::read(&path).expect("NML_ONNX_REAL readable");
    let brain = nml_core_godot::onnx::load(&bytes, None).expect("the export loads");
    assert_eq!((brain.rows(), brain.width()), (nml_core::tokens::N_UNITS, nml_core::tokens::F_U),
        "this leg is for the vocab-3 window");
    let corpus = nml_core::load_acts(&format!("{ROOT}/core/nml-core/tests/fixtures/acts_25.jsonl"))
        .expect("acts_25.jsonl");
    let statics = nml_core::build_act_statics(&corpus, ROOT);
    let mut priced = 0;
    for act in corpus.acts.iter().take(5) {
        let (_pick, run) = plan_with_onnx(&act.state, &corpus.terrain, &statics, &corpus.knobs,
            &act.statics, act.player, None, ROOT, &brain).expect("the real export declines nothing");
        assert_eq!(run.name, "onnx");
        assert_eq!(run.hash, brain.sha256());
        assert!(run.batches >= 1);
        priced += run.batches;
        eprintln!("ONNX_WIRING real batches={} batch_us={} per_batch_us={}",
            run.batches, run.batch_us, run.batch_us / run.batches.max(1));
    }
    assert!(priced >= 5);
}
