//! ONNX<->Python parity over a deterministic pinned corpus (M1a-3).
//!
//! Compares the merged M1a-1 tract loader against the Python/onnxruntime
//! reference receipt `parity_pinned_10238.json` on 10,238 positions seeded from
//! the public stand-in leaves. `wt-onnxpar` branches from `origin/main` where
//! M1a-2 (`OnnxHook`) is not merged, so the harness drives the merged batched
//! entry point directly: `onnx::load` (`src/onnx.rs:46`) and `onnx::Brain::run`
//! (`src/onnx.rs:74`) in `static_batch`-wide `Batch` chunks, zero-padded tail
//! with the padding rows discarded — the same packing `onnx_golden.rs` uses.
//! It does not reimplement the loader.
//!
//! The corpus mix is the one `gen_onnx_parity_corpus.py` documents; the first
//! assertion pins the sha256 of the exact float32 inputs the reference ran on,
//! so a drifting Rust mix is a RED test, never a silent re-baseline.
#![cfg(feature = "onnx-tract")]

use nml_core_godot::onnx::{load, Batch};
use serde_json::Value;
use sha2::{Digest, Sha256};

const U_N: usize = 24;
const U_D: usize = 72;
const O_N: usize = 6;
const O_D: usize = 12;
const T_N: usize = 18;
const G_D: usize = 16;
const BASE_LEAVES: u64 = 60;
const K: u64 = 0x9E37_79B9_7F4A_7C15;
const MIX2: u64 = 0xA5A5_A5A5_A5A5_A5A5;

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
        other => panic!("fixture holds a non-number: {other}"),
    }
}

fn numbers(value: &Value) -> Vec<f32> {
    let mut out = Vec::new();
    flatten(value, &mut out);
    out
}

struct Leaf {
    units: Vec<f32>,
    units_mask: Vec<f32>,
    objs: Vec<f32>,
    objs_mask: Vec<f32>,
    terr: Vec<f32>,
    glob: Vec<f32>,
}

fn leaf_of(value: &Value) -> Leaf {
    Leaf {
        units: numbers(&value["units"]),
        units_mask: numbers(&value["units_mask"]),
        objs: numbers(&value["objs"]),
        objs_mask: numbers(&value["objs_mask"]),
        terr: numbers(&value["terr"]),
        glob: numbers(&value["glob"]),
    }
}

fn splitmix64(x: u64) -> u64 {
    let z = x.wrapping_add(0x9E37_79B9_7F4A_7C15);
    let z = (z ^ (z >> 30)).wrapping_mul(0xBF58_476D_1CE4_E5B9);
    let z = (z ^ (z >> 27)).wrapping_mul(0x94D0_49BB_1331_11EB);
    z ^ (z >> 31)
}

fn pick(p: usize, block: u64, row: u64, seed: u64) -> bool {
    splitmix64(seed ^ (p as u64).wrapping_mul(K) ^ (block * 64 + row)) & 1 == 0
}

fn pair(p: usize, seed: u64) -> (usize, usize) {
    let p = p as u64;
    (
        (splitmix64(seed ^ p) % BASE_LEAVES) as usize,
        (splitmix64(seed ^ p ^ MIX2) % BASE_LEAVES) as usize,
    )
}

fn row_of(leaves: &[Leaf], p: usize, seed: u64) -> Leaf {
    if p < leaves.len() {
        let leaf = &leaves[p];
        return Leaf {
            units: leaf.units.clone(),
            units_mask: leaf.units_mask.clone(),
            objs: leaf.objs.clone(),
            objs_mask: leaf.objs_mask.clone(),
            terr: leaf.terr.clone(),
            glob: leaf.glob.clone(),
        };
    }
    let (a, b) = pair(p, seed);
    let (la, lb) = (&leaves[a], &leaves[b]);
    let mut row = Leaf {
        units: Vec::with_capacity(U_N * U_D),
        units_mask: Vec::with_capacity(U_N),
        objs: Vec::with_capacity(O_N * O_D),
        objs_mask: Vec::with_capacity(O_N),
        terr: Vec::with_capacity(T_N * O_D),
        glob: Vec::with_capacity(G_D),
    };
    for r in 0..U_N {
        let src = if pick(p, 1, r as u64, seed) { la } else { lb };
        row.units
            .extend_from_slice(&src.units[r * U_D..(r + 1) * U_D]);
        row.units_mask.push(src.units_mask[r]);
    }
    for r in 0..O_N {
        let src = if pick(p, 2, r as u64, seed) { la } else { lb };
        row.objs
            .extend_from_slice(&src.objs[r * O_D..(r + 1) * O_D]);
        row.objs_mask.push(src.objs_mask[r]);
    }
    for r in 0..T_N {
        let src = if pick(p, 3, r as u64, seed) { la } else { lb };
        row.terr
            .extend_from_slice(&src.terr[r * O_D..(r + 1) * O_D]);
    }
    row.glob.extend_from_slice(&if pick(p, 4, 0, seed) {
        la.glob.as_slice()
    } else {
        lb.glob.as_slice()
    });
    row
}

fn hash_row(hasher: &mut Sha256, row: &Leaf) {
    for block in [
        &row.units,
        &row.units_mask,
        &row.objs,
        &row.objs_mask,
        &row.terr,
        &row.glob,
    ] {
        for v in block {
            hasher.update(v.to_le_bytes());
        }
    }
}

fn place(batch: &mut Batch, i: usize, row: &Leaf) {
    let units = i * U_N * U_D;
    batch.units[units..units + U_N * U_D].copy_from_slice(&row.units);
    let units_mask = i * U_N;
    batch.units_mask[units_mask..units_mask + U_N].copy_from_slice(&row.units_mask);
    let objs = i * O_N * O_D;
    batch.objs[objs..objs + O_N * O_D].copy_from_slice(&row.objs);
    let objs_mask = i * O_N;
    batch.objs_mask[objs_mask..objs_mask + O_N].copy_from_slice(&row.objs_mask);
    let terr = i * T_N * O_D;
    batch.terr[terr..terr + T_N * O_D].copy_from_slice(&row.terr);
    batch.glob[i * G_D..(i + 1) * G_D].copy_from_slice(&row.glob);
}

#[test]
fn onnx_parity_pinned_corpus() {
    let onnx = fixture("standin-v2x2.onnx");
    let golden: Value = serde_json::from_slice(&fixture("golden_standin-v2x2.json")).unwrap();
    let receipt: Value = serde_json::from_slice(&fixture("parity_pinned_10238.json")).unwrap();

    let count = receipt["corpus"]["count"].as_u64().unwrap() as usize;
    let seed = receipt["corpus"]["seed"].as_u64().unwrap();
    let tolerance = receipt["tolerance"].as_f64().unwrap() as f32;
    assert!(count >= 10_000, "corpus {count} is under 10,000 positions");

    let leaves: Vec<Leaf> = golden["leaves"]
        .as_array()
        .unwrap()
        .iter()
        .map(leaf_of)
        .collect();
    let brain = load(
        &onnx,
        Some(receipt["reference"]["onnx_sha256"].as_str().unwrap()),
    )
    .expect("the merged M1a-1 loader declined the stand-in");
    let width = brain.static_batch();
    let members = brain.members();

    let mut hasher = Sha256::new();
    let mut got_value = Vec::with_capacity(count);
    let mut got_members = Vec::with_capacity(count * members);
    for start in (0..count).step_by(width) {
        let rows = (count - start).min(width);
        let mut batch = Batch {
            units: vec![0.0; width * U_N * U_D],
            units_mask: vec![0.0; width * U_N],
            objs: vec![0.0; width * O_N * O_D],
            objs_mask: vec![0.0; width * O_N],
            terr: vec![0.0; width * T_N * O_D],
            glob: vec![0.0; width * G_D],
        };
        for i in 0..rows {
            let row = row_of(&leaves, start + i, seed);
            hash_row(&mut hasher, &row);
            place(&mut batch, i, &row);
        }
        let (value, member_values) = brain
            .run(&batch)
            .unwrap_or_else(|e| panic!("tract declined corpus chunk at {start}: {e:?}"));
        got_value.extend_from_slice(&value[..rows]);
        got_members.extend_from_slice(&member_values[..rows * members]);
    }
    let digest = format!("{:x}", hasher.finalize());
    assert_eq!(
        digest,
        receipt["corpus"]["input_sha256"].as_str().unwrap(),
        "the rebuilt corpus does not hash to the reference inputs"
    );

    let want_value = numbers(&receipt["expected"]["value"]);
    let want_members: Vec<Vec<f32>> = receipt["expected"]["member_values"]
        .as_array()
        .unwrap()
        .iter()
        .map(numbers)
        .collect();
    assert_eq!(want_value.len(), count);
    assert_eq!(want_members.len(), members);

    let mut max_abs = 0.0_f32;
    for (got, want) in got_value.iter().zip(&want_value) {
        max_abs = max_abs.max((got - want).abs());
    }
    let mut member_max_abs = 0.0_f32;
    for (m, want) in want_members.iter().enumerate() {
        assert_eq!(want.len(), count);
        for p in 0..count {
            member_max_abs = member_max_abs.max((got_members[p * members + m] - want[p]).abs());
        }
    }

    println!(
        "ONNX_PARITY count={count} seed={seed} max_abs={max_abs:.9} \
         member_max_abs={member_max_abs:.9} tolerance={tolerance:.1e} input_sha256={digest}"
    );
    assert!(
        max_abs <= tolerance,
        "value max_abs {max_abs:.3e} exceeds tolerance {tolerance:.1e}"
    );
    assert!(
        member_max_abs <= tolerance,
        "member max_abs {member_max_abs:.3e} exceeds tolerance {tolerance:.1e}"
    );
}
