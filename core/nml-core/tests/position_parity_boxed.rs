//! Shared Stage A boxed escape pins; separate process from global movement RED switches.
use nml_core::{geom, io, mv::step::{Landing, MoveRules}, state::{ProfileCache, Profiles, State}, terrain::Terrain};
use serde_json::{json, Value};
use std::{collections::HashMap, rc::Rc};

fn pinned_move(id: &str, epoch: u32) -> (State, usize, Landing, Value, f64) {
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/cases.json")).unwrap();
    let pins: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/boxed_escape.json")).unwrap();
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
    let landing = MoveRules { rules_epoch:epoch }.plain_move(&state,&terrain,actor,
        serde_json::from_value(case["action"]["dest"].clone()).unwrap(),
        case["action"]["band_in"].as_f64().unwrap(),true,
        case["fast_planner"].as_bool().unwrap(),case["fast_planner_guard"].as_i64().unwrap()).unwrap();
    (state,actor,landing,pin,pins["tolerance_in"].as_f64().unwrap())
}

fn assert_boxed_pin(id: &str) {
    let (_,_,got,pin,tolerance) = pinned_move(id,6);
    let expected: Vec<geom::V3> = serde_json::from_value(pin["expected_world"].clone()).unwrap();
    assert_eq!(got.end.len(),expected.len());
    let delta = got.end.iter().zip(expected).map(|(a,b)|
        geom::length(geom::sub(*a,b)) as f64 / nml_core::IN2M).fold(0.0f64,f64::max);
    assert!(delta <= tolerance,"{id}: boxed_escape differs from table by {delta:.9}in");
    assert!((got.budget_in-pin["budget_in"].as_f64().unwrap()).abs() <= tolerance);
}

#[test]
fn boxed_escape_small_base_matches_the_table_pin() { assert_boxed_pin("recorded-144"); }
#[test]
fn boxed_escape_large_oval_matches_the_table_pin() { assert_boxed_pin("recorded-077"); }

#[test]
fn boxed_budget_and_round_reset_reach_the_simulator() {
    use nml_core::{state::SidestepBudget, unit::{Ctx, UnitStatic}};
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/cases.json")).unwrap();
    let budget: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/boxed_budget.json")).unwrap();
    let limit = budget["limit"].as_i64().unwrap();
    for id in budget["cases"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()) {
        let fixture = fixtures["cases"].as_array().unwrap().iter().find(|c| c["id"] == id).unwrap();
        let (mut base,actor,_,pin,tolerance) = pinned_move(id,6);
        let terrain = Terrain::build(&serde_json::from_value(fixture["terrain"].clone()).unwrap());
        let action: io::Action = serde_json::from_value(fixture["action"].clone()).unwrap();
        let band = fixture["action"]["band_in"].as_f64().unwrap();
        base.bands[actor].advance = band;
        base.bands[actor].rush = band;
        let statics: Vec<UnitStatic> = base.profiles.list.iter().map(|p| UnitStatic {
            model_count:p.model_count, ctx:Ctx {models:p.model_count,tough:1,..Default::default()},
            ..Default::default()
        }).collect();
        for probe in budget["probes"].as_array().unwrap() {
            let mut state = base.clone();
            let used = probe["used"].as_i64().unwrap();
            let reset = probe["new_round"].as_bool().unwrap();
            state.sidestep_budget = SidestepBudget {round:state.round,used};
            if reset { state.round += 1; }
            let left = if reset { limit } else { limit-used };
            let big = id == "recorded-077";
            let permitted = big || left > 0;
            let spent = !big && permitted;
            let got = MoveRules {rules_epoch:6}.plain_move(&state,&terrain,actor,
                geom::to_f32(action.dest.unwrap()),band,true,true,nml_core::mv::FAST_PLANNER_GUARD).unwrap();
            assert_eq!(got.sidestep_spent,spent,"{id}: {probe}");
            let expected: Vec<geom::V3> = serde_json::from_value(pin["expected_world"].clone()).unwrap();
            let delta = got.end.iter().zip(expected).map(|(a,b)|
                geom::length(geom::sub(*a,b)) as f64 / nml_core::IN2M).fold(0.0f64,f64::max);
            assert_eq!(delta <= tolerance,permitted,"{id}: {probe}: delta {delta}");
            let resolved = nml_core::sim::resolve_on_board(&statics,&state,&action,&terrain,
                io::Seams {movement:true,hero_attach:true,rules_epoch:6,..Default::default()}).unwrap();
            for (m,end) in got.movers.iter().zip(&got.end) {
                assert_eq!(resolved.positions[m.unit][m.model],geom::to_f64(*end),"{id}: {probe}");
            }
            let remaining = if resolved.sidestep_budget.round == resolved.round {
                limit-resolved.sidestep_budget.used
            } else { limit };
            assert_eq!(remaining,left-i64::from(spent),"{id}: {probe}");
        }
    }
}
