//! F-CONT (rules 3.6, `EPOCH_73_V36`, lead ruling D5) — the act header's `terrain.containers` list.
//!
//! The table keeps a placed container as its exact 6"x3" box (`TerrainOverlay._blocker_obbs`) and DROPS the painted
//! container cells whose centre the box covers; before this row the capture carried neither the box nor, always, the
//! cells, so the core saw through a container the table's line stopped at (gf_1000_net_033 acts 18 and 23, aof_1000_net_029
//! act 17). The boards below are read through serde from the header JSON a recorder writes, so the test holds the key
//! name and shape the recorder emits, not a hand-built struct.

use nml_core::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use nml_core::sight::{has_los, zones_of_at, Cyl};
use nml_core::terrain::{PlainTerrain, Terrain, CONTAINER};
use nml_core::IN2M;
use serde_json::json;

/// One model on a 32 mm base standing at `(x_in, z_in)`: radius 16 mm, eye 1.25" up.
fn model(x_in: f64, z_in: f64) -> Cyl {
    Cyl { c: [x_in * IN2M, z_in * IN2M], r: 0.016, y0: 0.0, y1: 1.25 * IN2M }
}

/// The header's terrain block: the painted `cells` plus the recorder's `containers` (absent when `boxes` is None).
fn board(cells: &[[f64; 3]], boxes: Option<serde_json::Value>) -> Terrain {
    let mut t = json!({"cells": cells, "sandbox": [], "walls": [],
        "cell_params": {"table_size_feet": [6.0, 4.0], "grid_rotation_degrees": 0.0,
            "grid_size_inches": 3.0, "inches_to_meters": IN2M}});
    if let Some(b) = boxes {
        t["containers"] = b;
    }
    Terrain::build(&serde_json::from_value::<PlainTerrain>(t).expect("the header's terrain block parses"))
}

/// A 6x3 box centred at `(cx_in, cz_in)`, axis-aligned, in the recorder's `{c, he, yaw}` shape (world metres).
fn container_at(cx_in: f64, cz_in: f64) -> serde_json::Value {
    json!([{"c": [cx_in * IN2M, cz_in * IN2M], "he": [3.0 * IN2M, 1.5 * IN2M], "yaw": 0.0}])
}

fn sees(t: &Terrain, epoch: u32, from: (f64, f64), to: (f64, f64)) -> bool {
    has_los(&model(from.0, from.1), &model(to.0, to.1), false, &zones_of_at(t, epoch), &[])
}

#[test]
fn a_container_box_with_no_painted_cells_blocks_the_line_from_epoch_73() {
    // No cell under the box (the gf_1000_net_033 case): the table stops the line, the header's box must too.
    let t = board(&[], Some(container_at(0.0, 0.0)));
    assert!(!sees(&t, EPOCH_73_V36, (0.0, -8.0), (0.0, 8.0)), "a 2.5\" box stops a 1.25\" eye line");
    assert!(sees(&t, EPOCH_73_V36, (8.0, -8.0), (8.0, 8.0)), "a line past the box end is open");
}

#[test]
fn the_box_is_not_read_below_epoch_73_and_an_old_header_has_none() {
    let t = board(&[], Some(container_at(0.0, 0.0)));
    assert!(sees(&t, EPOCH_72_PLAYTEST_RULES, (0.0, -8.0), (0.0, 8.0)), "epoch 72 is byte-identical: the box is not read");
    let old = board(&[], None);
    assert!(sees(&old, EPOCH_73_V36, (0.0, -8.0), (0.0, 8.0)), "a recording without the key still loads and sees as before");
}

#[test]
fn a_painted_container_cell_under_the_box_drops_out_like_the_tables_zone_volume() {
    // World cell (0, 0) is painted (15, 15): x, z in [0", 3"), centre (1.5", 1.5"). The box sits 1" further along +z, so
    // the cell's centre is inside it while the cell's z in [0", 1") strip is not. A line along z = 0.5" runs through that
    // strip: the cell alone would stop it (epoch 72, or a header without the box), the box does not touch it.
    let boxes = Some(container_at(1.5, 2.5));
    let with_box = board(&[[15.0, 15.0, CONTAINER as f64]], boxes);
    assert!(sees(&with_box, EPOCH_73_V36, (-2.0, 0.5), (5.0, 0.5)), "the covered cell is dropped, the box is the truth");
    assert!(!sees(&with_box, EPOCH_73_V36, (1.5, -4.0), (1.5, 8.0)), "and the box itself still stops a line through it");
    let cell_only = board(&[[15.0, 15.0, CONTAINER as f64]], None);
    assert!(!sees(&cell_only, EPOCH_73_V36, (-2.0, 0.5), (5.0, 0.5)), "no box in the header: the cell stays solid");
}
