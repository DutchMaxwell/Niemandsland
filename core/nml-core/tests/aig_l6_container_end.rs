//! AIG-L6b (rules epoch 73), Rust twin of `test/v36/aig_l6_container_end_test.gd`: a model never ends its move with
//! its base on a container block. A charging hero climbed a 6"x3" container and came down its far edge; the gate's
//! push-out (away from the block) was reverted by the wall clamp, so it ended a hair outside the edge with a 52 mm
//! base overlapping the block. The table twin replays the captured act; the core does not reproduce that capture
//! (its planner routes the same hero around the block), so this board is built for the core: a host of three models
//! with its joined hero (104 mm base) charges across the container (cells (16,16), (17,16), four edge walls), run
//! through the real `charge_move`. "Just drop the clamp" would stand the push but break the charge band.
use nml_core::{acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36}, io,
    mv::{geom2::point_seg_distance, step::MoveRules}, state::{ProfileCache, Profiles, State},
    terrain::{Terrain, CONTAINER}, IN2M};
use serde_json::{json, Value};
use std::{collections::HashMap, rc::Rc};

const BAND_IN: f64 = 11.0;
const HERO_R_M: f64 = 0.052;
/// The container's footprint, world metres: x 0.0762..0.2286, z 0.0762..0.1524 (two 3" cells, 2.5" tall).
const WALLS_M: [[[f64; 2]; 2]; 4] = [
    [[0.0762, 0.0762], [0.0762, 0.1524]], [[0.0762, 0.1524], [0.2286, 0.1524]],
    [[0.2286, 0.1524], [0.2286, 0.0762]], [[0.2286, 0.0762], [0.0762, 0.0762]],
];

fn unit(id: &str, player: i64, positions: Vec<Value>, radius_m: f64, base_mm: i64, attached: &[&str], attached_to: &str) -> Value {
    let n = positions.len();
    json!({"aircraft": false, "attached": attached, "attached_to": attached_to, "base_d_mm": base_mm,
        "base_shape": "round", "base_w_mm": base_mm, "charge_no_difficult": false, "charge_probe_r": radius_m,
        "dormant": false, "game_system": "gf", "id": id, "player": player, "positions": positions,
        "radii": vec![radius_m; n], "rules": [], "tough": 1, "wounds": vec![1; n]})
}

fn board() -> Terrain {
    Terrain::build(&serde_json::from_value(json!({"cell_params": {"grid_rotation_degrees": 0, "grid_size_inches": 3,
        "inches_to_meters": IN2M, "table_size_feet": [6, 4]},
        "cells": [[16, 16, CONTAINER], [17, 16, CONTAINER]], "sandbox": [], "walls": WALLS_M})).unwrap())
}

/// Run the charge at `epoch` (table inches from the centre -> world metres); returns the hero's resting place
/// (world x, z) and the longest arc (ground + climb).
fn run(epoch: u32) -> ([f64; 2], f64) {
    let at = |p: [f64; 2]| json!([p[0] * IN2M, 0.0, p[1] * IN2M]);
    let host = vec![at([-6.0, 3.0]), at([-6.0, 4.5]), at([-6.0, 6.0])];
    let specs = [unit("u00", 2, host, 0.016, 32, &["u01"], ""), unit("u01", 2, vec![at([-3.0, 4.5])], HERO_R_M, 104, &[], "u00"),
        unit("u02", 1, vec![at([16.0, 4.5])], 0.03, 60, &[], "")];
    let mut profiles = Profiles { list: vec![], index: HashMap::new() };
    let mut units = serde_json::Map::new();
    for spec in &specs {
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
    let state: State = io::state_from_json(&json!({"units": units, "round": 3, "rounds_total": 4}).to_string(),
        &mut cache, &mut None).unwrap();
    let (actor, tgt, hero) = (state.roster.index["u00"], state.roster.index["u02"], state.roster.index["u01"]);
    let land = MoveRules { rules_epoch: epoch }.charge_move(&state, &board(), actor, tgt, BAND_IN, true, true, 320).unwrap();
    let h = land.movers.iter().position(|m| m.unit == hero).expect("the joined hero moves with its host");
    ([land.end[h][0] as f64, land.end[h][2] as f64], land.arc_in)
}

/// May a base of the hero's size rest here? Not inside the block and not within 2 mm of its edge (the table's rest rule).
fn rests_on_the_block(p: [f64; 2]) -> bool {
    let inside = p[0] > 0.0762 && p[0] < 0.2286 && p[1] > 0.0762 && p[1] < 0.1524;
    let near = WALLS_M.iter().any(|w| {
        let (a, b) = ([w[0][0] as f32, w[0][1] as f32], [w[1][0] as f32, w[1][1] as f32]);
        point_seg_distance([p[0] as f32, p[1] as f32], a, b) as f64 <= HERO_R_M + 0.002
    });
    inside || near
}

#[test]
fn the_hero_never_ends_with_its_base_on_a_container_at_epoch_73() {
    let (end, _) = run(EPOCH_73_V36);
    assert!(!rests_on_the_block(end), "the hero ends with its 52 mm base on the container: {end:?} (AIG-L6b)");
}

/// Guards the shortcut: letting the gate's push-out stand also frees the base, but the trail then runs past the
/// charge band. The pulled-back end must keep the arc (ground + climb) inside the band.
#[test]
fn the_pulled_back_hero_stays_inside_the_charge_band() {
    let (_, arc) = run(EPOCH_73_V36);
    assert!(arc <= BAND_IN + 0.01, "the longest arc (ground + climb) is {arc:.2} in, past the {BAND_IN} in charge band");
}

/// Control: below 73 the container is a wall to the core, so the same charge stops short of it, as recorded.
#[test]
fn a_charge_below_epoch_73_is_untouched() {
    let (end, arc) = run(EPOCH_72_PLAYTEST_RULES);
    assert!((end[0] / IN2M - 0.5).abs() < 0.01 && (end[1] / IN2M - 4.5).abs() < 0.01, "the recorded end moved: {end:?}");
    assert!((arc - 4.53).abs() < 0.01, "the recorded arc moved: {arc:.2}");
}
