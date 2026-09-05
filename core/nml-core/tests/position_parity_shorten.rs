//! Separate test process: movement unit tests toggle global RED switches.
use nml_core::geom;
use nml_core::io::{Action, Seams};
use nml_core::sim::resolve_on_board;
use nml_core::state::Profiles;
use nml_core::terrain::Terrain;
use nml_core::unit::{Ctx, UnitStatic};
use std::{collections::HashMap, rc::Rc};

/// Replay the original fixed action through the real simulator as well as
/// the direct movement wrapper: losing Seams.rules_epoch must fail here.
#[test]
fn whole_unit_shorten_epoch_reaches_the_simulator_movement() {
    use serde_json::{json, Value};
    use nml_core::state::ProfileCache;
    use nml_core::mv::step::MoveRules;
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../../test/fixtures/position_parity/cases.json")).unwrap();
    let case = fixtures["cases"].as_array().unwrap().iter()
        .find(|c| c["id"] == "recorded-003").unwrap();
    let mut units = serde_json::Map::new();
    let mut profiles = Profiles { list: vec![], index: HashMap::new() };
    for spec in case["units"].as_array().unwrap() {
        let key = spec["id"].as_str().unwrap().to_string();
        let mut p = spec.clone();
        p["unit_id"] = json!(key);
        p["name"] = json!(key);
        p["quality"] = json!(4);
        p["defense"] = json!(4);
        p["special_rules"] = spec["rules"].clone();
        p["model_count"] = json!(spec["positions"].as_array().unwrap().len());
        profiles.index.insert(key.clone(), profiles.list.len());
        profiles.list.push(serde_json::from_value(p).unwrap());
        let mut u = spec.clone();
        u["alive"] = json!(spec["positions"].as_array().unwrap().len());
        units.insert(key, u);
    }
    let mut cache = ProfileCache::new(Rc::new(profiles));
    let state = nml_core::io::state_from_json(&json!({"round":case["round"],
        "rounds_total":4,"units":units}).to_string(), &mut cache, &mut None).unwrap();
    let terrain = Terrain::build(&serde_json::from_value(case["terrain"].clone()).unwrap());
    let action: Action = serde_json::from_value(case["action"].clone()).unwrap();
    let si = state.roster.index[&action.unit];
    let statics: Vec<UnitStatic> = state.profiles.list.iter().map(|p| UnitStatic {
        model_count: p.model_count, ctx: Ctx { models:p.model_count, tough:1,
            ..Default::default() }, ..Default::default()
    }).collect();
    let mut endings = vec![];
    for rules_epoch in [0, 5, 6, 7] {
        let expected = MoveRules { rules_epoch }.plain_move(&state, &terrain, si,
            geom::to_f32(action.dest.unwrap()), case["action"]["band_in"].as_f64().unwrap(),
            true, true, nml_core::mv::FAST_PLANNER_GUARD).unwrap();
        let got = resolve_on_board(&statics, &state, &action, &terrain,
            Seams { movement:true, hero_attach:true, rules_epoch,
                ..Seams::default() }).unwrap();
        for (m, end) in expected.movers.iter().zip(&expected.end) {
            assert_eq!(got.positions[m.unit][m.model], geom::to_f64(*end),
                "simulator lost movement epoch {rules_epoch}");
        }
        endings.push(expected.end);
    }
    assert_eq!(endings[0], endings[1]);
    assert_eq!(endings[2], endings[3]);
    assert_ne!(endings[1], endings[2], "fixture must exercise epoch-6 shortening");
}

