//! Rules 3.6 row UX-15 tests (Reinforcement arrival) for the rollout module; owned by lane ux.
//! UX-15 — a Reinforcement copy lands fully within 9" of a table edge (3.5: 12") and, from rules
//! epoch 73, over 9" from every enemy base (3.5 named no enemy distance). The band is map data and
//! reads the same at every epoch; only the enemy ring is epoch-gated.

use super::*;
use crate::acts::EPOCH_73_V36;
use crate::terrain::PlainTerrain;
use serde_json::{json, Value};

const NINE_IN_M: f64 = 9.0 * crate::IN2M;

/// Profiles: the Reinforcement carrier (three 0.02 m bases), a plain enemy, and a nine-model
/// friendly wall of 0.1 m bases used to fill the owner's back edge.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":2,
    "wounds_max":[2,2,2],"model_count":3,"caster_value":0,"base_radius":0.02,
    "game_system":"gf","faction_folder":"ratmen_clans",
    "special_rules":["Reinforcement"],"item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
  "p2_0_b":{"unit_id":"p2_0_b","name":"B","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.02,
    "game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
  "p3_0_c":{"unit_id":"p3_0_c","name":"C","quality":4,"defense":3,"tough":1,
    "wounds_max":[1,1,1,1,1,1,1,1,1],"model_count":9,"caster_value":0,"base_radius":0.1,
    "game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],
    "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

fn unit(player: i64, shaken: bool, pos: &[[f64; 3]], r: f64) -> Value {
    json!({"player": player, "alive": pos.len(), "wounds": vec![1; pos.len()],
        "radii": vec![r; pos.len()], "positions": pos, "in_cover": false, "shaken": shaken,
        "fatigued": false, "activated": false, "casts": 0, "morale_bonus": 0,
        "aircraft": false, "dormant": false, "ambush_arrived_round": -1,
        "earliest_arrival_round": -1, "wound_frac": 0.0, "mods": {}, "mods_base": {},
        "bands": {"advance": 6.0, "rush": 12.0}, "ledger": {}})
}

/// The Shaken carrier at the centre plus `extra` units; statics come off the production path at
/// `epoch`, so the band is whatever the shipped map says.
fn line(epoch: u32, extra: &[(&str, Value)]) -> (State, Vec<UnitStatic>) {
    let mut units = serde_json::Map::new();
    units.insert("p1_0_a".into(), unit(1, true, &[[0.0, 0.0, 0.0]], 0.02));
    for (k, v) in extra {
        units.insert((*k).into(), v.clone());
    }
    let state = json!({"round": 1, "rounds_total": 4, "scoring": "end", "units": units});
    let header = read_act_header(HEADER).expect("header");
    let mut cache = ProfileCache::new(header.profiles);
    let mut roster = None;
    let st = io::state_from_json(&state.to_string(), &mut cache, &mut roster).expect("state");
    let statics = statics_of(&st, epoch);
    (st, statics)
}

fn empty_board() -> Terrain {
    let plain: PlainTerrain = serde_json::from_value(json!({
        "cells": [], "sandbox": [], "walls": [],
        "cell_params": {"table_size_feet": [6.0, 4.0], "grid_rotation_degrees": 0.0,
                        "grid_size_inches": 6.0, "inches_to_meters": crate::IN2M},
    }))
    .expect("plain terrain");
    Terrain::build(&plain)
}

/// Round 1 withdraws the Shaken carrier, round 2 brings the copy back — the real driver, with
/// the seams stamped at `epoch`.
fn copy_after_two_beats(epoch: u32, extra: &[(&str, Value)]) -> (State, usize) {
    let (mut st, statics) = line(epoch, extra);
    let board = empty_board();
    let i = idx(&st, "p1_0_a");
    for round in 1..=2 {
        st.round = round;
        let seams = Seams { rules_epoch: epoch, ..Seams::default() };
        reinforcement_round_start(&statics, &board, seams, &mut st);
    }
    (st, i)
}

/// The band as the test's own arithmetic: a base is fully on the 72x48 in table and fully
/// within `band_in` of at least one edge.
fn in_band(p: (f64, f64), r: f64, band_in: f64) -> bool {
    let (x1, z1, band) = (36.0 * crate::IN2M, 24.0 * crate::IN2M, band_in * crate::IN2M);
    if p.0 - r < -x1 - 1e-6 || p.0 + r > x1 + 1e-6 || p.1 - r < -z1 - 1e-6 || p.1 + r > z1 + 1e-6 {
        return false;
    }
    (p.0 + r) + x1 <= band || x1 - (p.0 - r) <= band || (p.1 + r) + z1 <= band || z1 - (p.1 - r) <= band
}

/// Edge-to-edge gaps (metres) between every model of unit `a` and every model of unit `b`.
fn gaps(st: &State, a: usize, b: usize) -> Vec<f64> {
    let mut out = Vec::new();
    for (pa, ra) in st.positions[a].iter().zip(&st.radii[a]) {
        for (pb, rb) in st.positions[b].iter().zip(&st.radii[b]) {
            out.push(((pa[0] - pb[0]).powi(2) + (pa[2] - pb[2]).powi(2)).sqrt() - ra - rb);
        }
    }
    out
}

/// A plain enemy ~6 in in front of the owner's back-edge slot (the copy's preferred spot).
fn enemy_near_the_back_edge() -> [(&'static str, Value); 1] {
    [("p2_0_b", unit(2, false, &[[0.0, 0.0, -0.40]], 0.02))]
}

/// Nine friendly 0.1 m bases tiled along the owner's back edge (z = -0.5): the 9 in strip has
/// no free slot, only the 9-12 in belt just in front of the wall does.
fn back_edge_wall() -> [(&'static str, Value); 2] {
    let xs: Vec<[f64; 3]> = (0..9).map(|k| [-0.8 + 0.2 * k as f64, 0.0, -0.5]).collect();
    [
        ("p2_0_b", unit(2, false, &[[0.5, 0.0, 0.4]], 0.02)),
        ("p3_0_c", unit(1, false, &xs, 0.1)),
    ]
}

fn band_reads_nine_inches_from_the_map(epoch: u32) {
    let (st, statics) = line(epoch, &[]);
    let i = idx(&st, "p1_0_a");
    assert_eq!(statics[st.roster.profile[i]].reinforcement.within_in, 9.0, "map depth, every epoch");
}

#[test]
fn the_edge_band_reads_nine_inches_from_the_map_at_epoch_72() {
    band_reads_nine_inches_from_the_map(72);
}

#[test]
fn the_edge_band_reads_nine_inches_from_the_map_at_epoch_73() {
    band_reads_nine_inches_from_the_map(EPOCH_73_V36);
}

fn crowded_back_edge_lands_inside_nine_inches(epoch: u32) {
    let (st, i) = copy_after_two_beats(epoch, &back_edge_wall());
    assert_eq!(st.alive[i], 3, "the copy came back at full size");
    for m in &st.positions[i] {
        assert!(in_band((m[0], m[2]), 0.02, 9.0), "model at {m:?} is outside the 9\" band");
    }
}

#[test]
fn a_crowded_back_edge_sends_the_copy_inside_nine_inches_at_epoch_72() {
    crowded_back_edge_lands_inside_nine_inches(72);
}

#[test]
fn a_crowded_back_edge_sends_the_copy_inside_nine_inches_at_epoch_73() {
    crowded_back_edge_lands_inside_nine_inches(EPOCH_73_V36);
}

/// The 72 leg stays: no enemy distance, the copy takes the slot beside the enemy.
#[test]
fn a_copy_may_land_beside_an_enemy_at_epoch_72() {
    let (st, i) = copy_after_two_beats(72, &enemy_near_the_back_edge());
    let e = idx(&st, "p2_0_b");
    assert_eq!(st.alive[i], 3, "the copy came back at full size");
    let nearest = gaps(&st, i, e).into_iter().fold(f64::INFINITY, f64::min);
    assert!(nearest < NINE_IN_M, "epoch 72 reads no enemy distance, gap was {nearest:.3} m");
}

/// The 73 leg: the slot beside the enemy is refused and the next legal slot, over 9 in from
/// every enemy base and still inside the band, is used.
#[test]
fn a_copy_lands_over_nine_inches_from_every_enemy_at_epoch_73() {
    let (st, i) = copy_after_two_beats(EPOCH_73_V36, &enemy_near_the_back_edge());
    let e = idx(&st, "p2_0_b");
    assert_eq!(st.alive[i], 3, "the copy still came back, on a slot further along the edge");
    for g in gaps(&st, i, e) {
        assert!(g > NINE_IN_M, "a model stands {g:.3} m from the enemy, inside the 9\" ring");
    }
    for m in &st.positions[i] {
        assert!(in_band((m[0], m[2]), 0.02, 9.0), "model at {m:?} is outside the 9\" band");
    }
}
