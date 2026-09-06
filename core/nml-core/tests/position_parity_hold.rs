//! Stage A coherency hold: the table refuses a move that would tear a unit
//! which started coherent, and returns zero instead of its best torn rung.
use nml_core::{geom, io, mv::step::MoveRules, state::{ProfileCache, Profiles, State},
    terrain::Terrain};
use serde_json::{json, Value};
use std::{collections::HashMap, rc::Rc};

fn build(case: &Value) -> (State, Terrain, usize) {
    let mut profiles = Profiles { list: vec![], index: HashMap::new() };
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
    let state = io::state_from_json(&json!({"units": units, "round": case["round"],
        "rounds_total": 4}).to_string(), &mut cache, &mut None).unwrap();
    let terrain = Terrain::build(&serde_json::from_value(case["terrain"].clone()).unwrap());
    let actor = state.roster.index[case["action"]["unit"].as_str().unwrap()];
    (state, terrain, actor)
}

fn landing_end(case: &Value, epoch: u32) -> (Vec<geom::V3>, f64) {
    let (state, terrain, actor) = build(case);
    let landing = MoveRules { rules_epoch: epoch }.plain_move(&state, &terrain, actor,
        serde_json::from_value(case["action"]["dest"].clone()).unwrap(),
        case["action"]["band_in"].as_f64().unwrap(), true,
        case["fast_planner"].as_bool().unwrap(),
        case["fast_planner_guard"].as_i64().unwrap()).unwrap();
    (landing.end, landing.budget_in)
}

#[test]
fn a_move_that_tears_a_coherent_unit_holds_at_the_table_epoch() {
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/cases.json")).unwrap();
    let pins: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/coherency_hold.json")).unwrap();
    let tolerance = pins["tolerance_in"].as_f64().unwrap();
    for pin in pins["cases"].as_array().unwrap() {
        let id = pin["id"].as_str().unwrap();
        let case = fixtures["cases"].as_array().unwrap().iter()
            .find(|c| c["id"] == id).unwrap();
        let expected: Vec<geom::V3> = serde_json::from_value(pin["expected_world"].clone()).unwrap();
        let (end, budget) = landing_end(case, 6);
        assert_eq!(end.len(), expected.len(), "{id}: model count");
        let delta = end.iter().zip(&expected)
            .map(|(a, b)| geom::length(geom::sub(*a, *b)) as f64 / nml_core::IN2M)
            .fold(0.0f64, f64::max);
        assert!(delta <= tolerance, "{id}: hold differs from the table by {delta:.9}in");
        assert!((budget - pin["budget_in"].as_f64().unwrap()).abs() <= tolerance,
            "{id}: a hold grants no band, got {budget}");
        // Replays below the table-rules epoch keep the best torn rung.
        let (below, _) = landing_end(case, 5);
        let moved = below.iter().zip(&expected)
            .map(|(a, b)| geom::length(geom::sub(*a, *b)) as f64 / nml_core::IN2M)
            .fold(0.0f64, f64::max);
        assert!(moved > 0.5, "{id}: the earlier epoch must keep moving, got {moved:.6}in");
    }
}
