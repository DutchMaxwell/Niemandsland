//! `PENDING_EPOCH_FLYING_THROUGH`: a Flying unit's route ignores the other units' spacing zones (the table's `flies_through_units`, since 75). The case is a
//! lone 40 mm Flying hero charging a lone 40 mm hero 7 in away on an empty board (the melee census' Grunt Veteran -> Master Brother). The table's planner call
//! (NML_MOVE_DUMP) answers the straight contact slot, (5.425201, 0.0) in world inches; the core's route used to bend round the defender's zone, a grid detour
//! that landed 0.46 in off the axis. Below 94 the old landing is pinned; a lone walker keeps its landing at 94 (the zones still block a walker's route).
use nml_core::{io, mv::step::MoveRules, state::{ProfileCache, Profiles, State}, terrain::Terrain};
use serde_json::json;
use std::{collections::HashMap, rc::Rc};

fn case(rules: &[&str]) -> (State, Terrain, usize, usize) {
    let unit = |id: &str, player: i64, x: f64, rules: &[&str]| json!({"aircraft":false,"attached":[],"attached_to":"","base_d_mm":40,"base_shape":"round","base_w_mm":40,
        "charge_no_difficult":false,"charge_probe_r":0.02,"dormant":false,"game_system":"gf","id":id,"player":player,"positions":[[x,0.0,0.0]],"radii":[0.02],"rules":rules,
        "tough":3,"wounds":[3]});
    let specs = [unit("att", 2, 0.0, rules), unit("tgt", 1, 0.1778, &[])];
    let mut profiles = Profiles { list: vec![], index: HashMap::new() };
    let mut units = serde_json::Map::new();
    for spec in &specs {
        let key = spec["id"].as_str().unwrap().to_string();
        let mut profile = spec.clone();
        profile["unit_id"] = json!(key);
        profile["name"] = json!(key);
        profile["quality"] = json!(4);
        profile["defense"] = json!(4);
        profile["model_count"] = json!(1);
        profile["special_rules"] = spec["rules"].clone();
        profiles.index.insert(key.clone(), profiles.list.len());
        profiles.list.push(serde_json::from_value(profile).unwrap());
        let mut u = spec.clone();
        u["alive"] = json!(1);
        units.insert(key, u);
    }
    let mut cache = ProfileCache::new(Rc::new(profiles));
    let state = io::state_from_json(&json!({"units": units, "round": 1, "rounds_total": 4}).to_string(), &mut cache, &mut None).unwrap();
    let terrain = Terrain::build(&serde_json::from_value(json!({"cell_params":{"grid_rotation_degrees":0.0,"grid_size_inches":3.0,"inches_to_meters":0.0254,
        "table_size_feet":[6.0,4.0]},"cells":[],"sandbox":[],"walls":[]})).unwrap());
    let (att, tgt) = (state.roster.index["att"], state.roster.index["tgt"]);
    (state, terrain, att, tgt)
}

fn lands_at(epoch: u32, rules: &[&str]) -> [f64; 2] {
    let (state, terrain, att, tgt) = case(rules);
    let land = MoveRules { rules_epoch: epoch }.charge_move(&state, &terrain, att, tgt, 12.0, true, true, 320).unwrap();
    [land.end[0][0] as f64 / nml_core::IN2M, land.end[0][2] as f64 / nml_core::IN2M]
}

#[test]
fn a_flying_charger_takes_the_straight_slot_from_94() {
    let new = lands_at(nml_core::acts::PENDING_EPOCH_FLYING_THROUGH, &["Flying", "Strider", "Hero"]);
    assert!((new[0] - 5.425201).abs() < 1e-4 && new[1].abs() < 1e-4, "from 94 the flying charger lands on the table's slot: {new:?}");
    let old = lands_at(nml_core::acts::PENDING_EPOCH_FLYING_THROUGH - 1, &["Flying", "Strider", "Hero"]);
    assert!((old[0] - 5.494150).abs() < 1e-4 && (old[1] + 0.460880).abs() < 1e-4, "below 94 the old landing, byte-identical: {old:?}");
    let walker = lands_at(nml_core::acts::PENDING_EPOCH_FLYING_THROUGH, &["Strider", "Hero"]);
    assert_eq!(walker, lands_at(nml_core::acts::PENDING_EPOCH_FLYING_THROUGH - 1, &["Strider", "Hero"]), "a walker's route is untouched by the gate");
}
