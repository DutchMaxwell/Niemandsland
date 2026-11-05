//! G4R5 R3 F-CLIMB-Y (rules epoch 73): a model whose route ends on a container stands on its roof.
//! The core priced the climb over the container edge (`Landing.climb_in`) but handed back the end positions at the
//! start height, so a climber stood at y 0 inside the box while the table put it on the roof (aof_000/10, gf_006/26,
//! gf_031/25): the eye and cover reads of the following volley then differ. The table settles every moved model on
//! `surface_y_at(end)`. The fixture is the recorded act aof_1000_net_000 act 10 (an Advance of "Change Acolyte
//! Chanters" with its joined hero "Change Birdman Champion", who climbs onto a container; the table's log says
//! "climbs onto terrain"), header + pre-act state committed verbatim, replayed through the real simulator.
use nml_core::{
    act_statics,
    acts::{read_acts, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36},
    dice::Tray,
    io::{Action, Seams},
    plan::seams_of,
    rng::GodotRng,
    sight::surface_y_m,
    sim::resolve_stochastic_tray_on_board,
    terrain::{PlainTerrain, Terrain, CONTAINER},
    IN2M,
};
use serde_json::Value;
use std::io::Cursor;

const FIXTURE: &str = include_str!("fixtures/climb_y_aof000_act10.json");
/// G4R5 R3b: aof_1000_net_016 act 8, an Advance whose model 0 starts on a 2.5in roof and walks off it.
const WALK_OFF: &str = include_str!("fixtures/walk_off_roof_aof016_act8.json");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const ROOF_M: f64 = 2.5 * IN2M;

/// Replays the fixture act at `epoch`; returns the next state, the board and the moving chain's models (the acting unit
/// plus its joined hero) in that state.
fn replay(epoch: u32) -> (Vec<[f64; 3]>, Terrain) {
    let (chain, board, _) = replay_of(FIXTURE, epoch);
    (chain, board)
}

/// As `replay`, for any fixture; the third value is the chain's models in the pre-act state.
fn replay_of(fixture: &str, epoch: u32) -> (Vec<[f64; 3]>, Terrain, Vec<[f64; 3]>) {
    let fx: Value = serde_json::from_str(fixture).unwrap();
    let text = format!("{}\n{}\n", fx["header"], fx["act_line"]);
    let corpus = read_acts(Cursor::new(text), "fixture").unwrap();
    let acts = act_statics(&corpus, REPO);
    let act = &corpus.acts[0];
    let action: Action = serde_json::from_value(fx["act_line"]["pick"]["action"].clone()).unwrap();
    // The header's knobs are the source of the seams; `--movement` of the shooting gate adds the movement port and the
    // joined heroes, the epoch is the variable.
    let seams = Seams { rules_epoch: epoch, movement: true, hero_attach: true, ..seams_of(&corpus.knobs) };
    let mut tray = Tray::seeded(fx["dice_seed"].as_i64().unwrap());
    let mut rng = GodotRng::new(0);
    let (next, _shot) =
        resolve_stochastic_tray_on_board(&acts[0], &act.state, &action, &corpus.terrain, seams, &mut rng, &mut tray)
            .unwrap_or_else(|e| panic!("act declined: {e:?}"));
    let mut keys = vec![action.unit.clone()];
    keys.extend(fx["act_line"]["state"]["units"][&action.unit]["attached"].as_array().unwrap().iter().map(|k| k.as_str().unwrap().to_string()));
    let chain = keys.iter().flat_map(|k| next.positions[next.roster.index[k.as_str()]].iter().copied()).collect();
    let start = keys
        .iter()
        .flat_map(|k| fx["act_line"]["state"]["units"][k.as_str()]["positions"].as_array().unwrap().iter())
        .map(|p| [0, 1, 2].map(|i| p[i].as_f64().unwrap()))
        .collect();
    (chain, corpus.terrain, start)
}

fn over_a_container(t: &Terrain, p: &[f64; 3]) -> bool {
    t.containers().iter().any(|b| {
        let (d, (s, c)) = ([p[0] - b.c[0], p[2] - b.c[1]], b.yaw.sin_cos());
        (d[0] * c - d[1] * s).abs() <= b.he[0] && (d[0] * s + d[1] * c).abs() <= b.he[1]
    })
}

#[test]
fn the_joined_hero_that_climbs_a_container_stands_on_its_roof_from_epoch_73() {
    let (chain, board) = replay(EPOCH_73_V36);
    let on: Vec<_> = chain.iter().filter(|p| over_a_container(&board, p)).collect();
    assert_eq!(on.len(), 1, "exactly the climbing hero's route ends over a container footprint, found {on:?}");
    assert!((on[0][1] - ROOF_M).abs() < 1e-6, "a climber stands at the container's top: y {:.4} m, roof {ROOF_M:.4} m", on[0][1]);
    assert_eq!(chain.iter().filter(|p| p[1] > 0.0).count(), 1, "and nobody else of the chain leaves the table");
}

#[test]
fn below_epoch_73_nobody_of_the_chain_stands_above_the_table() {
    let (chain, _) = replay(EPOCH_72_PLAYTEST_RULES);
    assert!(chain.iter().all(|p| p[1] == 0.0), "epoch 72 keeps the recorded behaviour byte for byte");
}

/// R3b: the table settles every moved model on `surface_y_at(end)`, so a model that starts on a roof and ends off every
/// roof stands on the table again (y 0). The core kept the start height: the model floated 2.5in above the table, and the
/// eye height and cover of the following volley differed.
#[test]
fn a_model_that_walks_off_a_roof_stands_on_the_table_from_epoch_73() {
    let (chain, board, start) = replay_of(WALK_OFF, EPOCH_73_V36);
    let walkers: Vec<_> = start.iter().zip(&chain).filter(|(s, _)| (s[1] - ROOF_M).abs() < 1e-6).collect();
    assert_eq!(walkers.len(), 1, "exactly one model of the chain starts on the roof: {start:?}");
    let (_, end) = walkers[0];
    assert!(!over_a_container(&board, end), "the model ends off every roof: {end:?}");
    assert_eq!(end[1], 0.0, "and stands on the table: y {:.4} m, it started at {ROOF_M:.4} m", end[1]);
}

#[test]
fn below_epoch_73_the_model_that_walks_off_a_roof_keeps_its_start_height() {
    let (chain, _, start) = replay_of(WALK_OFF, EPOCH_72_PLAYTEST_RULES);
    let walkers: Vec<_> = start.iter().zip(&chain).filter(|(s, _)| (s[1] - ROOF_M).abs() < 1e-6).collect();
    assert_eq!(walkers.len(), 1);
    assert!((walkers[0].1[1] - ROOF_M).abs() < 1e-6, "epoch 72 keeps the recorded behaviour byte for byte: {:?}", walkers[0].1);
}

/// The helper behind the landing height, read the way the table reads a container: the placed box, a painted cell no
/// box covers, nothing under a painted cell the box covers by its centre, and the box is not read below epoch 73.
#[test]
fn the_surface_is_the_roof_over_a_box_or_an_uncovered_painted_cell_and_the_table_elsewhere() {
    let board = |cells: serde_json::Value, boxes: serde_json::Value| {
        let t = serde_json::json!({"cells": cells, "sandbox": [], "walls": [], "containers": boxes,
            "cell_params": {"table_size_feet": [6.0, 4.0], "grid_rotation_degrees": 0.0, "grid_size_inches": 3.0, "inches_to_meters": IN2M}});
        Terrain::build(&serde_json::from_value::<PlainTerrain>(t).unwrap())
    };
    let at = |x_in: f64, z_in: f64| [x_in * IN2M, z_in * IN2M];
    let cell = serde_json::json!([[15.0, 15.0, CONTAINER as f64]]); // world cell (0, 0): x, z in [0", 3"), centre (1.5", 1.5")
    let boxed = serde_json::json!([{"c": [1.5 * IN2M, 2.5 * IN2M], "he": [3.0 * IN2M, 1.5 * IN2M], "yaw": 0.0}]);
    let none = serde_json::json!([]);
    let only_box = board(none.clone(), boxed.clone());
    assert_eq!(surface_y_m(&only_box, at(1.5, 2.5), EPOCH_73_V36), ROOF_M, "over the placed box");
    assert_eq!(surface_y_m(&only_box, at(8.0, 2.5), EPOCH_73_V36), 0.0, "beside it");
    assert_eq!(surface_y_m(&only_box, at(1.5, 2.5), EPOCH_72_PLAYTEST_RULES), 0.0, "the box is not read below epoch 73");
    assert_eq!(surface_y_m(&board(cell.clone(), none), at(1.5, 0.5), EPOCH_73_V36), ROOF_M, "a painted cell no box covers");
    assert_eq!(surface_y_m(&board(cell, boxed), at(1.5, 0.5), EPOCH_73_V36), 0.0, "the cell the box covers by its centre drops out");
}
