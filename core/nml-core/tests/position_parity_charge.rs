//! Shared Stage A charge pins; separate process from global movement RED switches.
use nml_core::{geom, io, mv::step::{Landing, MoveRules}, state::{ProfileCache, Profiles, State}, terrain::Terrain};
use serde_json::{json, Value};
use std::{collections::HashMap, rc::Rc};

fn pinned_charge(id: &str, epoch: u32) -> (State, usize, Landing, Value, f64) {
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/cases.json")).unwrap();
    let pins: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/charge_gates.json")).unwrap();
    let case = fixtures["cases"].as_array().unwrap().iter().find(|c| c["id"] == id).unwrap();
    let pin = pins["cases"].as_array().unwrap().iter().find(|p| p["id"] == id).unwrap().clone();
    let mut profiles = Profiles { list:vec![], index:HashMap::new() };
    let mut units = serde_json::Map::new();
    for spec in case["units"].as_array().unwrap() {
        let key = spec["id"].as_str().unwrap().to_string();
        let mut profile = spec.clone();
        profile["unit_id"] = json!(key);
        profile["name"] = json!(key);
        profile["quality"] = json!(4);
        profile["defense"] = json!(4);
        profile["model_count"] = json!(spec["positions"].as_array().unwrap().len());
        profile["special_rules"] = spec["rules"].clone();
        profiles.index.insert(key.clone(), profiles.list.len());
        profiles.list.push(serde_json::from_value(profile).unwrap());
        let mut unit = spec.clone();
        unit["alive"] = json!(spec["positions"].as_array().unwrap().len());
        units.insert(key, unit);
    }
    let mut cache = ProfileCache::new(Rc::new(profiles));
    let state = io::state_from_json(&json!({"units":units,"round":case["round"],
        "rounds_total":4}).to_string(), &mut cache, &mut None).unwrap();
    let terrain = Terrain::build(&serde_json::from_value(case["terrain"].clone()).unwrap());
    let actor = state.roster.index[case["action"]["unit"].as_str().unwrap()];
    let target = state.roster.index[case["action"]["target"].as_str().unwrap()];
    let landing = MoveRules { rules_epoch:epoch }.charge_move(&state,&terrain,actor,target,
        case["action"]["band_in"].as_f64().unwrap(),true,
        case["fast_planner"].as_bool().unwrap(),case["fast_planner_guard"].as_i64().unwrap()).unwrap();
    (state,target,landing,pin,pins["tolerance_in"].as_f64().unwrap())
}

fn assert_endpoint_pin(id: &str, bucket: &str) {
    let (state,target,mut got,pin,tolerance) = pinned_charge(id,6);
    got.snap_charge(&state,target,6);
    let expected: Vec<geom::V3> = serde_json::from_value(pin["expected_world"].clone()).unwrap();
    assert_eq!(got.end.len(),expected.len());
    let delta = got.end.iter().zip(expected).map(|(a,b)|
        geom::length(geom::sub(*a,b)) as f64 / nml_core::IN2M).fold(0.0f64,f64::max);
    assert!(delta <= tolerance, "{id}: {bucket} differs from table by {delta:.9}in");
}

#[test]
fn charge_final_placement_matches_the_table_pin() {
    assert_endpoint_pin("generated-charge-14","charge_final_placement");
}

#[test]
fn charge_base_shapes_matches_the_table_pin() {
    assert_endpoint_pin("recorded-136","base_shapes");
}

#[test]
fn charge_snap_reports_the_pinned_budget_rejection() {
    let (state,target,mut got,pin,tolerance) = pinned_charge("generated-charge-14",6);
    let snap = got.snap_charge(&state,target,6);
    assert!(snap.is_some(), "generated-charge-14: charge_snap stage is missing");
    let delta = (snap.unwrap()-pin["snap_in"].as_f64().unwrap()).abs();
    assert!(delta <= tolerance,"generated-charge-14: snap residual differs by {delta:.9}in");
}
