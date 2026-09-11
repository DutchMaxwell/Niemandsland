//! Stage A gate-collapse ladder (parity-frame 5): the rung the table KEEPS,
//! pinned on the table's own endpoints and band. Separate process from the
//! global movement RED switches, like the other Stage A pins.
//!
//! recorded-037 is a 21-model rush (20 x 25 mm round + a 40 mm hero, Strider)
//! whose full 16 in plan the gate shortens; the ladder then re-plans at 12, 8
//! and 4 in. The table keeps the FULL rung (achieved 1.2440 in) and rejects
//! the 12 in rung (1.3873 in) because it is not better by more than 0.005 m
//! (`a3 > best_ach + 0.005`, solo_controller.gd:4974); the core keeps the
//! 12 in rung (`budget_in` 12), and every model lands 0.12-0.74 in off.
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

#[test]
fn the_collapse_ladder_keeps_the_table_rung() {
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/cases.json")).unwrap();
    let pins: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/collapse_ladder.json")).unwrap();
    let tolerance = pins["tolerance_in"].as_f64().unwrap();
    for pin in pins["cases"].as_array().unwrap() {
        let id = pin["id"].as_str().unwrap();
        let case = fixtures["cases"].as_array().unwrap().iter()
            .find(|c| c["id"] == id).unwrap();
        let (state, terrain, actor) = build(case);
        let landing = MoveRules { rules_epoch: 6 }.plain_move(&state, &terrain, actor,
            serde_json::from_value(case["action"]["dest"].clone()).unwrap(),
            case["action"]["band_in"].as_f64().unwrap(), true,
            case["fast_planner"].as_bool().unwrap(),
            case["fast_planner_guard"].as_i64().unwrap()).unwrap();
        // The rung first: the band the table kept is the whole difference.
        let want_budget = pin["budget_in"].as_f64().unwrap();
        assert!((landing.budget_in - want_budget).abs() <= tolerance,
            "{id}: the ladder kept the {} in rung, the table kept {want_budget}", landing.budget_in);
        let expected: Vec<geom::V3> = serde_json::from_value(pin["expected_world"].clone()).unwrap();
        assert_eq!(landing.end.len(), expected.len(), "{id}: model count");
        let delta = landing.end.iter().zip(&expected)
            .map(|(a, b)| geom::length(geom::sub(*a, *b)) as f64 / nml_core::IN2M)
            .fold(0.0f64, f64::max);
        assert!(delta <= tolerance, "{id}: collapse ladder differs from the table by {delta:.9}in");
    }
}

#[test]
fn whole_unit_shorten_preserves_nearly_exact_endpoints() {
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/cases.json")).unwrap();
    let pins: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/shorten_precision.json")).unwrap();
    let tolerance = pins["tolerance_in"].as_f64().unwrap();
    for pin in pins["cases"].as_array().unwrap() {
        let id = pin["id"].as_str().unwrap();
        let case = fixtures["cases"].as_array().unwrap().iter()
            .find(|c| c["id"] == id).unwrap();
        let (state, terrain, actor) = build(case);
        for rules_epoch in [6, nml_core::CURRENT_RULES_EPOCH] {
            let landing = MoveRules { rules_epoch }.plain_move(&state, &terrain, actor,
                serde_json::from_value(case["action"]["dest"].clone()).unwrap(),
                case["action"]["band_in"].as_f64().unwrap(), true,
                case["fast_planner"].as_bool().unwrap(),
                case["fast_planner_guard"].as_i64().unwrap()).unwrap();
            let expected: Vec<geom::V3> = serde_json::from_value(pin["expected_world"].clone()).unwrap();
            assert_eq!(landing.end.len(), expected.len());
            assert!((landing.budget_in - pin["budget_in"].as_f64().unwrap()).abs() <= tolerance);
            for (model, (got, want)) in landing.end.iter().zip(&expected).enumerate() {
                let delta = geom::length(geom::sub(*got, *want)) as f64 / nml_core::IN2M;
                assert!(delta <= tolerance,
                    "{id} model {model} epoch {rules_epoch}: {delta:.9}in > {tolerance:.9}in");
            }
        }
    }
}
