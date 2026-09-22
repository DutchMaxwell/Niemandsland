//! ONNX brain loader (M1a-1): bytes -> SHA-256 -> parsed metadata + I/O
//! contract -> embedded self-test -> tract session. Declines reuse
//! `Unsupported::LeafValueBridge` (`brain.rs:9`), one static reason each.

use nml_core::sim::Unsupported;
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::collections::HashMap;
use tract_onnx::prelude::*;
use nml_core::tokens::{F_U, N_UNITS, V1_ROWS, V1_UNITS};
use std::cell::Cell;

const SCHEMA: &str = "1";
const TOKEN_TAIL: &str = ",objs6x12,terr18x12,glob16,vocab1017,bag17";
const VALUE_HEAD: &str = "margin";
const SELFTEST_LABEL: &str = "standin-v2x2";
const SELFTEST_JSON: &str = include_str!("onnx_selftest.json");
/// `units{rows}x{width}` + the fixed tail. Two contracts are known: the v1 export
/// (`V1_ROWS` × `V1_UNITS`: 24 rows of 88 design fields + 2 pads) and the vocab-3
/// export (`N_UNITS` × `F_U`: the core's own 32 × 91 window). Anything else declines.
fn parse_token_schema(schema: &str) -> Option<(usize, usize)> {
    let head = schema.strip_prefix("units")?.strip_suffix(TOKEN_TAIL)?;
    let (r, w) = head.split_once('x')?;
    let (rows, width) = (r.parse::<usize>().ok()?, w.parse::<usize>().ok()?);
    let known = (rows == V1_ROWS && width == V1_UNITS) || (rows == N_UNITS && width == F_U);
    known.then_some((rows, width))
}

pub struct Batch {
    pub units: Vec<f32>, pub units_mask: Vec<f32>, // [b,rows,width] / [b,rows] — rows/width from the model's token_schema
    pub objs: Vec<f32>, pub objs_mask: Vec<f32>,   // [rows,6,12] / [rows,6]
    pub terr: Vec<f32>, pub glob: Vec<f32>,        // [rows,18,12] / [rows,16]
}

pub struct Brain {
    plan: Arc<TypedRunnableModel>, members: usize, static_batch: usize,
    rows: usize, width: usize, sha256: String,
    batches: Cell<u64>, micros: Cell<u64>,
}

fn decline(reason: &'static str) -> Unsupported { Unsupported::LeafValueBridge(reason) }

fn metadata_map(proto: &tract_onnx::pb::ModelProto) -> HashMap<String, String> {
    proto.metadata_props.iter().map(|e| (e.key.clone(), e.value.clone())).collect()
}

fn check_metadata(map: &HashMap<String, String>) -> Result<(usize, usize, String, usize, usize), Unsupported> {
    let get = |key: &str| map.get(key).map(String::as_str).unwrap_or("");
    let count = |key: &str| -> Option<usize> { map.get(key)?.parse::<usize>().ok().filter(|v| *v >= 1) };
    if get("nml.brain_schema") != SCHEMA { return Err(decline("onnx: metadata brain_schema")); }
    let (rows, width) = parse_token_schema(get("nml.token_schema")).ok_or_else(|| decline("onnx: metadata token_schema"))?;
    if get("nml.value_head") != VALUE_HEAD { return Err(decline("onnx: metadata value_head")); }
    let members = count("nml.members").ok_or_else(|| decline("onnx: metadata members"))?;
    let static_batch = count("nml.static_batch").ok_or_else(|| decline("onnx: metadata static_batch"))?;
    Ok((members, static_batch, get("nml.label").to_string(), rows, width))
}

/// `bytes` -> SHA-256 -> parse once -> metadata -> session -> embedded self-test.
pub fn load(bytes: &[u8], expected_sha256: Option<&str>) -> Result<Brain, Unsupported> {
    let sha256 = format!("{:x}", Sha256::digest(bytes));
    if let Some(expected) = expected_sha256 {
        let actual = &sha256;
        let expected = expected.strip_prefix("0x").or_else(|| expected.strip_prefix("0X")).unwrap_or(expected);
        if !actual.eq_ignore_ascii_case(expected) { return Err(decline("onnx: sha256 mismatch")); }
    }
    let mut reader: &[u8] = bytes;
    let proto = tract_onnx::onnx().proto_model_for_read(&mut reader)
        .map_err(|_| decline("onnx: model parse"))?;
    let (members, static_batch, label, rows, width) = check_metadata(&metadata_map(&proto))?;
    let plan = tract_onnx::onnx()
        .model_for_proto_model(&proto).map_err(|_| decline("onnx: session"))?
        .into_optimized().map_err(|_| decline("onnx: session"))?
        .into_runnable().map_err(|_| decline("onnx: session"))?;
    let brain = Brain { plan, members, static_batch, rows, width, sha256, batches: Cell::new(0), micros: Cell::new(0) };
    if label == SELFTEST_LABEL {
        let golden: Value = serde_json::from_str(SELFTEST_JSON).map_err(|_| decline("onnx: selftest shape"))?;
        brain.check_selftest(&golden)?;
    }
    Ok(brain)
}

fn numbers(value: &Value, out: &mut Vec<f32>) {
    if let Value::Array(items) = value { items.iter().for_each(|v| numbers(v, out)); }
    else if let Value::Number(n) = value { out.push(n.as_f64().unwrap_or(f64::NAN) as f32); }
}

impl Brain {
    pub fn run(&self, batch: &Batch) -> Result<(Vec<f32>, Vec<f32>), Unsupported> {
        let started = std::time::Instant::now();
        let b = batch.units.len() / (self.rows * self.width);
        let tensor = |shape: &[usize], data: &[f32]| Tensor::from_shape(shape, data)
            .map(TValue::from).map_err(|_| decline("onnx: run"));
        let inputs = tvec![tensor(&[b, self.rows, self.width], &batch.units)?, tensor(&[b, self.rows], &batch.units_mask)?,
            tensor(&[b, 6, 12], &batch.objs)?, tensor(&[b, 6], &batch.objs_mask)?,
            tensor(&[b, 18, 12], &batch.terr)?, tensor(&[b, 16], &batch.glob)?];
        let outputs = self.plan.run(inputs).map_err(|_| decline("onnx: run"))?;
        let value = outputs[0].to_plain_array_view::<f32>().map_err(|_| decline("onnx: run"))?.iter().copied().collect::<Vec<f32>>();
        let members = outputs[1].to_plain_array_view::<f32>().map_err(|_| decline("onnx: run"))?.iter().copied().collect::<Vec<f32>>();
        self.batches.set(self.batches.get() + 1);
        self.micros.set(self.micros.get() + started.elapsed().as_micros() as u64);
        Ok((value, members))
    }

    /// Replays the embedded golden leaf as row 0 of a zero-padded `static_batch`.
    fn check_selftest(&self, golden: &Value) -> Result<(), Unsupported> {
        let leaf = &golden["leaves"][0];
        let b = self.static_batch;
        let dims = self.dims();
        let mut batch = Batch { units: vec![0.0; b * dims[0]], units_mask: vec![0.0; b * dims[1]], objs: vec![0.0; b * dims[2]],
            objs_mask: vec![0.0; b * dims[3]], terr: vec![0.0; b * dims[4]], glob: vec![0.0; b * dims[5]] };
        for (key, len, out) in [
            ("units", dims[0], &mut batch.units), ("units_mask", dims[1], &mut batch.units_mask),
            ("objs", dims[2], &mut batch.objs), ("objs_mask", dims[3], &mut batch.objs_mask),
            ("terr", dims[4], &mut batch.terr), ("glob", dims[5], &mut batch.glob),
        ] {
            let mut row = Vec::new(); numbers(&leaf[key], &mut row);
            if row.len() != len { return Err(decline("onnx: selftest shape")); }
            out[..len].copy_from_slice(&row);
        }
        let (value, members) = self.run(&batch)?;
        let tolerance = golden["tolerance"].as_f64().unwrap_or(0.0) as f32;
        let (mut want_value, mut want_members) = (Vec::new(), Vec::new());
        numbers(&golden["expected"]["value"], &mut want_value);
        numbers(&golden["expected"]["member_values"], &mut want_members);
        if value.len() != b || members.len() != b * self.members || want_value.is_empty() || want_value.len() > b || want_members.len() != want_value.len() * self.members {
            return Err(decline("onnx: selftest shape"));
        }
        let off = |got: &[f32], want: &[f32]| got.iter().zip(want).any(|(g, w)| (g - w).abs() > tolerance);
        if off(&value[..want_value.len()], &want_value) || off(&members[..want_members.len()], &want_members) {
            return Err(decline("onnx: selftest value"));
        }
        Ok(())
    }

    /// Flat element counts per leaf: units, units_mask, objs, objs_mask, terr, glob.
    fn dims(&self) -> [usize; 6] { [self.rows * self.width, self.rows, 6 * 12, 6, 18 * 12, 16] }

    pub fn members(&self) -> usize { self.members }
    pub fn static_batch(&self) -> usize { self.static_batch }
    /// The unit window the model was exported with: rows × width (24×90 v1, 32×91 vocab-3).
    pub fn rows(&self) -> usize { self.rows }
    pub fn width(&self) -> usize { self.width }
    /// Hex SHA-256 of the model bytes — the brain record's `hash`.
    pub fn sha256(&self) -> &str { &self.sha256 }
    /// Batches run and wall micros spent since load (the brain record's counters).
    pub fn batches(&self) -> u64 { self.batches.get() }
    pub fn micros(&self) -> u64 { self.micros.get() }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tract_onnx::prelude::*;

    const ONNX: &[u8] = include_bytes!("../tests/fixtures/onnx/standin-v2x2.onnx");

    fn golden() -> Value {
        serde_json::from_str(SELFTEST_JSON).unwrap()
    }

    fn parsed_metadata() -> HashMap<String, String> {
        let mut reader: &[u8] = ONNX;
        metadata_map(&tract_onnx::onnx().proto_model_for_read(&mut reader).unwrap())
    }

    #[test]
    fn selftest_positive_on_standin() {
        let brain = load(ONNX, None).unwrap();
        assert_eq!(brain.members(), 2);
        assert_eq!(brain.static_batch(), 32);
    }

    #[test]
    fn selftest_shape_rejects_short_leaf() {
        let brain = load(ONNX, None).unwrap();
        let mut g = golden();
        let rows = g["leaves"][0]["units"].as_array_mut().unwrap();
        rows.last_mut().unwrap().as_array_mut().unwrap().pop();
        assert_eq!(brain.check_selftest(&g).unwrap_err(), decline("onnx: selftest shape"));
    }

    #[test]
    fn metadata_rejects_wrong_token_schema() {
        let mut map = parsed_metadata();
        map.insert("nml.token_schema".to_string(), "bogus".to_string());
        assert_eq!(check_metadata(&map).unwrap_err(), decline("onnx: metadata token_schema"));
    }

    #[test]
    fn metadata_rejects_wrong_value_head() {
        let mut map = parsed_metadata();
        map.insert("nml.value_head".to_string(), "bogus".to_string());
        assert_eq!(check_metadata(&map).unwrap_err(), decline("onnx: metadata value_head"));
    }

    #[test]
    fn selftest_rejects_off_by_1e3() {
        let brain = load(ONNX, None).unwrap();
        let mut g = golden();
        let value = g["expected"]["value"][0].as_f64().unwrap();
        g["expected"]["value"][0] = serde_json::json!(value + 1e-3);
        assert_eq!(brain.check_selftest(&g).unwrap_err(), decline("onnx: selftest value"));
    }
}