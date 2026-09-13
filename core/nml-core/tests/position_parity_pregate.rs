//! PR6 instrument (scope 162): the table's own pre-gate planner rows
//! (`_plan_move`, solo_controller.gd:5228) replayed through the core twin
//! `plan_once` (mv/step.rs:497). The pin is the RED proof that one of the
//! eleven models is planned differently at the difficult-terrain cap
//! (docs/plans/POSITION_PARITY_2026-09-05.md:130). The replay goes through
//! `MoveRules::plan_once_probe`, a `#[doc(hidden)]` test-only hook; the port
//! is a separate launch.
use nml_core::{
    geom, io,
    mv::{gate, step::MoveRules},
    state::{ProfileCache, Profiles, State},
    terrain::Terrain,
};
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
fn pregate_planner_matches_the_tables_plan_move_pins() {
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/cases.json")).unwrap();
    let pins: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/pregate_planner.json")).unwrap();
    let id = pins["case"].as_str().unwrap();
    let case = fixtures["cases"].as_array().unwrap().iter()
        .find(|c| c["id"] == id).unwrap();
    let (state, terrain, actor) = build(case);
    let board = terrain.board_in();
    let epoch = pins["rules_epoch"].as_u64().unwrap() as u32;
    let tolerance = pins["tolerance_in"].as_f64().unwrap();
    let mut labels: Vec<String> = (0..state.positions[actor].len())
        .map(|i| format!("{}:{i}", state.key(actor))).collect();
    for &h in state.attached[actor].iter() {
        labels.extend((0..state.positions[h].len()).map(|i| format!("{}:{i}", state.key(h))));
    }
    for call in pins["calls"].as_array().unwrap() {
        assert!(!call["allow_contact"].as_bool().unwrap(), "{id}: pin is a plain move");
        let goal: Vec<f64> = serde_json::from_value(call["goal"].clone()).unwrap();
        let planned = MoveRules { rules_epoch: epoch }.plan_once_probe(
            &state, &terrain, actor, geom::to_f32([goal[0], 0.0, goal[1]]), true,
            case["fast_planner"].as_bool().unwrap(),
            case["fast_planner_guard"].as_i64().unwrap(),
            call["reach_in"].as_f64().unwrap(),
            call["avoid_difficult"].as_bool().unwrap(),
            call["avoid_dangerous"].as_bool().unwrap(),
        ).expect("the pinned case has a valid board and live models");
        let want: Vec<[f64; 3]> = serde_json::from_value(call["out"].clone()).unwrap();
        assert_eq!(planned.len(), want.len(), "{id}: call {} model count", call["call"]);
        for (i, p) in planned.iter().enumerate() {
            let got = gate::to_world_f32(*p, board);
            let delta = ((got[0] as f64 - want[i][0]).powi(2)
                + (got[1] as f64 - want[i][2]).powi(2)).sqrt() / nml_core::IN2M;
            assert!(delta <= tolerance,
                "{id} call {} model {i} ({}): pre-gate planner differs by {delta:.9}in (tol {tolerance})",
                call["call"], labels[i]);
        }
    }
}
