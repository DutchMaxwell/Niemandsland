//! Loader harness (M1a-1): the public stand-in loads and passes its embedded
//! self-test, scores the golden leaf 48, and one flipped byte declines on the
//! hash. tract only.
#![cfg(feature = "onnx-tract")]

use nml_core::sim::Unsupported;
use nml_core_godot::onnx::{load, Batch};
use serde_json::Value;
use sha2::{Digest, Sha256};

const U_N: usize = 24;
const U_D: usize = 72;
const O_N: usize = 6;
const D: usize = 12;
const T_N: usize = 18;
const G_D: usize = 16;

fn fixture(name: &str) -> Vec<u8> {
    let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/onnx")
        .join(name);
    std::fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

fn flatten(value: &Value, out: &mut Vec<f32>) {
    match value {
        Value::Array(items) => items.iter().for_each(|v| flatten(v, out)),
        Value::Number(n) => out.push(n.as_f64().unwrap() as f32),
        other => panic!("fixture leaf holds a non-number: {other}"),
    }
}

fn numbers(value: &Value) -> Vec<f32> {
    let mut out = Vec::new();
    flatten(value, &mut out);
    out
}

fn copy(dst: &mut [f32], src: &[f32]) {
    assert_eq!(dst.len(), src.len(), "fixture leaf shape drifted");
    dst.copy_from_slice(src);
}

fn make_batch(leaves: &[Value], b: usize) -> Batch {
    let mut batch = Batch {
        units: vec![0.0; b * U_N * U_D],
        units_mask: vec![0.0; b * U_N],
        objs: vec![0.0; b * O_N * D],
        objs_mask: vec![0.0; b * O_N],
        terr: vec![0.0; b * T_N * D],
        glob: vec![0.0; b * G_D],
    };
    for (i, leaf) in leaves.iter().enumerate() {
        copy(&mut batch.units[i * U_N * U_D..(i + 1) * U_N * U_D], &numbers(&leaf["units"]));
        copy(&mut batch.units_mask[i * U_N..(i + 1) * U_N], &numbers(&leaf["units_mask"]));
        copy(&mut batch.objs[i * O_N * D..(i + 1) * O_N * D], &numbers(&leaf["objs"]));
        copy(&mut batch.objs_mask[i * O_N..(i + 1) * O_N], &numbers(&leaf["objs_mask"]));
        copy(&mut batch.terr[i * T_N * D..(i + 1) * T_N * D], &numbers(&leaf["terr"]));
        copy(&mut batch.glob[i * G_D..(i + 1) * G_D], &numbers(&leaf["glob"]));
    }
    batch
}

#[test]
fn onnx_loader_selftest_and_sha256() {
    let onnx = fixture("standin-v2x2.onnx");
    let golden: Value = serde_json::from_slice(&fixture("golden_standin-v2x2.json")).unwrap();
    let provenance: Value =
        serde_json::from_slice(&fixture("provenance_standin-v2x2.json")).unwrap();
    let sha = provenance["runs"]["run1"]["raw_sha256"].as_str().unwrap().to_string();

    // Positive: hash, metadata and embedded self-test all pass on the stand-in.
    let brain = load(&onnx, Some(&sha)).expect("stand-in must load and pass its embedded self-test");
    assert_eq!(brain.members(), 2);
    assert_eq!(brain.static_batch(), 32);

    let leaf = 48; // synthetic:u01-o0-bag0
    let static_batch = golden["static_batch"].as_u64().unwrap() as usize;
    let batch = make_batch(std::slice::from_ref(&golden["leaves"][leaf]), static_batch);
    let (value, member_values) = brain.run(&batch).expect("leaf run");
    assert_eq!(value.len(), static_batch);
    let tolerance = golden["tolerance"].as_f64().unwrap() as f32;
    let expected_value = numbers(&golden["expected"]["value"])[leaf];
    assert!(
        (value[0] - expected_value).abs() <= tolerance,
        "value {} off golden {expected_value}",
        value[0]
    );
    let expected_members: Vec<f32> = golden["expected"]["member_values"]
        .as_array()
        .unwrap()
        .iter()
        .map(|m| numbers(m)[leaf])
        .collect();
    assert_eq!(member_values.len(), static_batch * brain.members());
    for (m, want) in expected_members.iter().enumerate() {
        assert!((member_values[m] - want).abs() <= tolerance, "member {m} off golden {want}");
    }

    // RED: one flipped byte at len/2 must decline on the SHA-256 check.
    let mut corrupt = onnx.clone();
    let flip_at = corrupt.len() / 2;
    corrupt[flip_at] ^= 0xff;
    assert_ne!(format!("{:x}", Sha256::digest(&corrupt)), sha);
    let err = match load(&corrupt, Some(&sha)) {
        Ok(_) => panic!("a flipped byte at {flip_at} must not load"),
        Err(e) => e,
    };
    assert_eq!(err, Unsupported::LeafValueBridge("onnx: sha256 mismatch"));

    println!(
        "ONNX_LOADER runtime=tract sha=ok metadata=ok selftest=ok golden=ok red=ok \
         leaf={leaf} value={:.9} members={}",
        value[0],
        member_values.len()
    );
}