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
    sim::resolve_stochastic_tray_on_board,
    terrain::Terrain,
    IN2M,
};
use serde_json::Value;
use std::io::Cursor;

const FIXTURE: &str = include_str!("fixtures/climb_y_aof000_act10.json");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const ROOF_M: f64 = 2.5 * IN2M;

/// Replays the fixture act at `epoch`; returns the next state, the board and the moving chain's models (the acting unit
/// plus its joined hero) in that state.
fn replay(epoch: u32) -> (Vec<[f64; 3]>, Terrain) {
    let fx: Value = serde_json::from_str(FIXTURE).unwrap();
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
    (chain, corpus.terrain)
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
