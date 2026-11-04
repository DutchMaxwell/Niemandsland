//! AIG-L6 (rules epoch 73), Rust twin of `test/v36/aig_l6_charge_wall_test.gd`: a charging model must never end
//! across a wall. The gate's charge coherency pull moves a straggler back toward its unit; the retraced trail then
//! closed on that spot with a straight leg from a trimmed point of the route, through the ruin wall the route had
//! bent around. Fixture = the captured act of a gate game, run through the real `charge_move`.
use nml_core::{acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36}, io,
    mv::{geom2::segments_cross, step::MoveRules}, state::{ProfileCache, Profiles, State}, terrain::Terrain, IN2M};
use serde_json::{json, Value};
use std::{collections::HashMap, rc::Rc};

/// Table inches (72x48 frame) -> world metres.
fn world(x_in: f64, z_in: f64) -> Value {
    json!([(x_in - 36.0) * IN2M, 0.0, (z_in - 24.0) * IN2M])
}

fn unit(id: &str, player: i64, positions: Vec<Value>, radius_m: f64, base_mm: i64) -> Value {
    let n = positions.len();
    json!({"aircraft": false, "attached": [], "attached_to": "", "base_d_mm": base_mm, "base_shape": "round",
        "base_w_mm": base_mm, "charge_no_difficult": false, "charge_probe_r": radius_m, "dormant": false,
        "game_system": "gf", "id": id, "player": player, "positions": positions, "radii": vec![radius_m; n],
        "rules": [], "tough": 1, "wounds": vec![1; n]})
}

/// The ruin walls of the gate game, world metres: west side, then the north side in two pieces.
fn walls_world() -> Vec<[[f64; 2]; 2]> {
    let seg = |a: [f64; 2], b: [f64; 2]| {
        [[(a[0] - 36.0) * IN2M, (a[1] - 24.0) * IN2M], [(b[0] - 36.0) * IN2M, (b[1] - 24.0) * IN2M]]
    };
    vec![seg([24.0, 36.0], [24.0, 33.0]), seg([24.0, 33.0], [27.0, 33.0]), seg([27.0, 33.0], [30.0, 33.0])]
}

/// Run the captured charge at `epoch`; returns (model trails whose polyline crosses a wall, still played as a charge).
fn run(epoch: u32) -> (usize, bool) {
    let charger = unit("u00", 2, vec![world(18.7986, 33.1899), world(20.2375, 32.9685), world(21.8079, 32.9816),
        world(22.8573, 33.7419), world(25.0947, 34.0595)], 0.016, 32);
    let target = unit("u01", 1, vec![world(23.0680, 30.4999)], 0.02, 40);
    let mut profiles = Profiles { list: vec![], index: HashMap::new() };
    let mut units = serde_json::Map::new();
    for spec in [&charger, &target] {
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
        let mut u = spec.clone();
        u["alive"] = json!(spec["positions"].as_array().unwrap().len());
        units.insert(key, u);
    }
    let mut cache = ProfileCache::new(Rc::new(profiles));
    let state: State = io::state_from_json(&json!({"units": units, "round": 4, "rounds_total": 4}).to_string(),
        &mut cache, &mut None).unwrap();
    let terrain = Terrain::build(&serde_json::from_value(json!({"cell_params": {"grid_rotation_degrees": 0,
        "grid_size_inches": 3, "inches_to_meters": IN2M, "table_size_feet": [6, 4]},
        "cells": [], "sandbox": [], "walls": walls_world()})).unwrap());
    let (actor, tgt) = (state.roster.index["u00"], state.roster.index["u01"]);
    let land = MoveRules { rules_epoch: epoch }.charge_move(&state, &terrain, actor, tgt, 9.0, true, true, 320).unwrap();
    let walls = terrain.walls_in().to_vec();
    let cuts = land.trails.iter().filter(|t| t.windows(2).any(|leg| walls.iter().any(|w| segments_cross(leg[0], leg[1], w[0], w[1])))).count();
    // A plan call without a charge goal is the table's rush re-gate: the charge was judged to end short.
    (cuts, land.call.is_some_and(|c| c.opts.charge_goal.is_some()))
}

#[test]
fn a_charging_model_never_ends_across_a_wall_at_epoch_73() {
    let (cuts, charged) = run(EPOCH_73_V36);
    assert_eq!(cuts, 0, "a charging model's published trail cuts across the ruin wall (AIG-L6)");
    // The wall-cutting last leg also inflated the longest arc past the band, so the core re-gated to a rush
    // a charge the table plays (the same act, 9" band): the route-true trail keeps it a charge.
    assert!(charged, "the charge was re-gated to a rush because its retraced arc cut a wall and ran past the band");
}

/// Control: below 73 the recorded rules play on byte for byte - the same board still cuts the wall.
#[test]
fn a_charge_below_epoch_73_is_untouched() {
    assert!(run(EPOCH_72_PLAYTEST_RULES).0 > 0);
}
