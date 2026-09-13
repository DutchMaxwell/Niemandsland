//! ONNX runtime spike harness: golden vectors, repeat, RED, timings, size inputs.
//! Runs only with exactly one of the onnx-tract / onnx-ort features.
#![cfg(any(feature = "onnx-tract", feature = "onnx-ort"))]

use nml_core_godot::onnx_spike::{load, Batch};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::time::Instant;

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

fn batch_rows(index: usize, total: usize, static_batch: usize) -> usize {
    (total - index * static_batch).min(static_batch)
}

fn bits(values: &[f32]) -> Vec<u32> {
    values.iter().map(|v| v.to_bits()).collect()
}

fn first_line(error: &str) -> String {
    error.lines().next().unwrap_or("").to_string()
}

fn vm_rss_kb() -> Option<u64> {
    let status = std::fs::read_to_string("/proc/self/status").ok()?;
    status.lines().find_map(|line| {
        line.strip_prefix("VmRSS:")?
            .split_whitespace()
            .next()?
            .parse()
            .ok()
    })
}

#[test]
fn onnx_golden_spike() {
    let onnx = fixture("standin-v2x2.onnx");
    let golden_bytes = fixture("golden_standin-v2x2.json");
    let golden: Value = serde_json::from_slice(&golden_bytes).unwrap();
    let provenance: Value = serde_json::from_slice(&fixture("provenance_standin-v2x2.json")).unwrap();

    let runtime = if cfg!(feature = "onnx-tract") { "tract" } else { "ort" };
    let os = std::env::consts::OS;

    // (a) the bytes hashed are exactly the bytes loaded.
    let digest = format!("{:x}", Sha256::digest(&onnx));
    assert_eq!(
        digest,
        provenance["runs"]["run1"]["raw_sha256"].as_str().unwrap(),
        "stand-in sha256 does not match the provenance"
    );
    assert_eq!(
        format!("{:x}", Sha256::digest(&golden_bytes)),
        provenance["golden_sha256"].as_str().unwrap(),
        "golden json sha256 does not match the provenance"
    );

    let tolerance = golden["tolerance"].as_f64().unwrap() as f32;
    let static_batch = golden["static_batch"].as_u64().unwrap() as usize;
    let leaves = golden["leaves"].as_array().unwrap();
    let expected_value = numbers(&golden["expected"]["value"]);
    let expected_members: Vec<Vec<f32>> = golden["expected"]["member_values"]
        .as_array()
        .unwrap()
        .iter()
        .map(numbers)
        .collect();
    let members = expected_members.len();
    let input_names: Vec<&str> = golden["input_names"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap())
        .collect();
    let output_names: Vec<&str> = golden["output_names"]
        .as_array()
        .unwrap()
        .iter()
        .map(|v| v.as_str().unwrap())
        .collect();
    assert_eq!(input_names, ["units", "units_mask", "objs", "objs_mask", "terr", "glob"]);
    assert_eq!(output_names, ["value", "member_values"]);
    assert_eq!(expected_value.len(), leaves.len());

    // (f) timings: 20 loads, median.
    let rss_before = vm_rss_kb();
    let mut load_ms = Vec::new();
    let mut brain = None;
    let mut first_error = None;
    for _ in 0..20 {
        let started = Instant::now();
        match load(&onnx) {
            Ok(loaded) => {
                load_ms.push(started.elapsed().as_millis());
                brain.get_or_insert(loaded);
            }
            Err(e) => {
                first_error.get_or_insert_with(|| first_line(&e));
            }
        }
    }
    load_ms.sort_unstable();

    let Some(brain) = brain else {
        println!(
            "ONNX_SPIKE runtime={runtime} os={os} loads=fail:{} max_abs=na member_max_abs=na \
             repeat_bitident=na red=na load_ms_p50=na batch_ms_p50=na batch_ms_p95=na \
             act_ms_r4=na act_ms_r2=na rss_delta_kb=na",
            first_error.unwrap_or_default()
        );
        return;
    };

    // (b)+(c) golden leaves in static batches, zero-padded tail discarded.
    let batches: Vec<Batch> = leaves
        .chunks(static_batch)
        .map(|chunk| make_batch(chunk, static_batch))
        .collect();
    let mut first_pass = Vec::new();
    let mut max_abs = 0.0_f32;
    let mut member_max_abs = 0.0_f32;
    for (bi, batch) in batches.iter().enumerate() {
        let (value, member_values) = match brain.run(batch) {
            Ok(out) => out,
            Err(e) => {
                println!("SPIKE_RUN_FAIL {e}");
                println!(
                    "ONNX_SPIKE runtime={runtime} os={os} loads=ok max_abs=na member_max_abs=na \
                     repeat_bitident=na red=na load_ms_p50=na batch_ms_p50=na batch_ms_p95=na \
                     act_ms_r4=na act_ms_r2=na rss_delta_kb=na"
                );
                return;
            }
        };
        for i in 0..batch_rows(bi, leaves.len(), static_batch) {
            let idx = bi * static_batch + i;
            max_abs = max_abs.max((value[i] - expected_value[idx]).abs());
            for (m, expected_member) in expected_members.iter().enumerate() {
                let got = member_values[i * members + m];
                member_max_abs = member_max_abs.max((got - expected_member[idx]).abs());
            }
        }
        first_pass.push((bits(&value), bits(&member_values)));
    }
    assert!(max_abs <= tolerance, "max_abs {max_abs} exceeds tolerance {tolerance}");
    assert!(
        member_max_abs <= tolerance,
        "member_max_abs {member_max_abs} exceeds tolerance {tolerance}"
    );

    // (d) the whole set a second time: outputs bit-identical.
    let mut repeat = true;
    for (bi, batch) in batches.iter().enumerate() {
        let (value, member_values) =
            brain.run(batch).unwrap_or_else(|e| panic!("second run failed: {e}"));
        repeat &= bits(&value) == first_pass[bi].0 && bits(&member_values) == first_pass[bi].1;
    }

    // (f) 200 runs of one full batch, p50/p95.
    let mut batch_ms = Vec::with_capacity(200);
    for _ in 0..200 {
        let started = Instant::now();
        brain
            .run(&batches[0])
            .unwrap_or_else(|e| panic!("timed run failed: {e}"));
        batch_ms.push(started.elapsed().as_millis());
    }
    batch_ms.sort_unstable();
    let rss_after = vm_rss_kb();

    // (e) RED: one flipped byte in the middle of the file.
    let mut corrupted = onnx.clone();
    let flip_at = corrupted.len() / 2;
    corrupted[flip_at] ^= 0xff;
    let red = match load(&corrupted) {
        Err(_) => "ok",
        Ok(brain) => {
            let mut worst = 0.0_f32;
            for (bi, batch) in batches.iter().enumerate() {
                let (value, member_values) = match brain.run(batch) {
                    Ok(out) => out,
                    Err(_) => {
                        worst = f32::INFINITY;
                        break;
                    }
                };
                for i in 0..batch_rows(bi, leaves.len(), static_batch) {
                    let idx = bi * static_batch + i;
                    worst = worst.max((value[i] - expected_value[idx]).abs());
                    for (m, expected_member) in expected_members.iter().enumerate() {
                        worst =
                            worst.max((member_values[i * members + m] - expected_member[idx]).abs());
                    }
                }
            }
            if worst > tolerance {
                "ok"
            } else {
                "missed"
            }
        }
    };

    #[cfg(feature = "onnx-ort")]
    println!(
        "SPIKE_CONFIG runtime=ort threads=intra=1 inter=1 parallel=false opt=default(ORT_ENABLE_ALL) dylib={}",
        std::env::var("NML_ORT_DYLIB").unwrap_or_default()
    );
    #[cfg(feature = "onnx-tract")]
    println!("SPIKE_CONFIG runtime=tract threads=1 executor=default(single-thread) opt=into_optimized");

    // (g) exactly one result line.
    let load_p50 = load_ms[load_ms.len() / 2];
    let batch_p50 = batch_ms[99];
    let batch_p95 = batch_ms[189];
    let rss = match (rss_before, rss_after) {
        (Some(before), Some(after)) => (after as i64 - before as i64).to_string(),
        _ => "na".to_string(),
    };
    println!(
        "ONNX_SPIKE runtime={runtime} os={os} loads=ok max_abs={max_abs:.9} \
         member_max_abs={member_max_abs:.9} repeat_bitident={} red={red} load_ms_p50={load_p50} \
         batch_ms_p50={batch_p50} batch_ms_p95={batch_p95} act_ms_r4={} act_ms_r2={batch_p95} \
         rss_delta_kb={rss}",
        if repeat { "yes" } else { "no" },
        batch_p95 * 2
    );
}
