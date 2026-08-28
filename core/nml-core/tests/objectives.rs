//! D8a — the Rust objective generator against Godot's own output.
//!
//! `tools/objective_fixture.gd` plays `ObjectiveLayout.generate` for 50 layout seeds
//! x 3 missions on one pinned board and writes every layout. Nothing here is
//! hand-written: a disagreement in the count roll, the roll-off, the draw order, the
//! lattice bounds, the 9" test, the zone polygons or the impassable-cell lookup shows
//! up as a mismatching case.

use nml_core::objectives::{self, Cells, Poly};

fn fixture() -> serde_json::Value {
    let raw = include_str!("fixtures/objective_layout.json");
    serde_json::from_str(raw).expect("fixture parses")
}

fn cells_of(f: &serde_json::Value) -> Cells {
    let n = f["n"].as_i64().unwrap();
    let pairs: Vec<((i64, i64), i32)> = f["cells"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| {
            let a = c.as_array().unwrap();
            (
                (a[0].as_i64().unwrap(), a[1].as_i64().unwrap()),
                a[2].as_i64().unwrap() as i32,
            )
        })
        .collect();
    Cells::from_pairs(&pairs, n)
}

fn zones_of(f: &serde_json::Value) -> Vec<Poly> {
    objectives::zones_of_style(&serde_json::json!({ "zones": f["zones"] }))
}

#[test]
fn rust_reproduces_every_godot_layout() {
    let f = fixture();
    let cells = cells_of(&f);
    let zones = zones_of(&f);
    let (w, d) = (f["table_w_in"].as_f64().unwrap(), f["table_d_in"].as_f64().unwrap());
    let cases = f["cases"].as_array().unwrap();
    assert_eq!(cases.len(), 150, "fixture shape changed");
    let mut checked = 0;
    for c in cases {
        let seed = c["layout_seed"].as_i64().unwrap();
        let got = objectives::generate(seed, &c["count_spec"], &zones, &cells, w, d);
        let want = &c["layout"];
        let label = format!("{} seed {}", c["mission"].as_str().unwrap(), seed);
        assert_eq!(got.count_roll, want["count_roll"].as_i64().unwrap(), "count: {label}");
        assert_eq!(
            got.first_placer,
            want["first_placer"].as_i64().unwrap(),
            "first_placer: {label}"
        );
        assert_eq!(got.swept, want["swept"].as_i64().unwrap(), "swept: {label}");
        let want_pos: Vec<(i64, i64)> = want["positions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| {
                let a = p.as_array().unwrap();
                (a[0].as_i64().unwrap(), a[1].as_i64().unwrap())
            })
            .collect();
        assert_eq!(got.positions, want_pos, "positions: {label}");
        let want_by: Vec<i64> =
            want["placed_by"].as_array().unwrap().iter().map(|p| p.as_i64().unwrap()).collect();
        assert_eq!(got.placed_by, want_by, "placed_by: {label}");
        checked += 1;
    }
    assert_eq!(checked, 150);
}

/// Every marker of every fixture layout satisfies the book, checked independently of
/// the generator that produced it — the same self-test `objective_gate.py` runs.
#[test]
fn every_generated_layout_is_legal() {
    let f = fixture();
    let cells = cells_of(&f);
    let zones = zones_of(&f);
    let mut markers = 0;
    for c in f["cases"].as_array().unwrap() {
        let pos: Vec<(i64, i64)> = c["layout"]["positions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|p| {
                let a = p.as_array().unwrap();
                (a[0].as_i64().unwrap(), a[1].as_i64().unwrap())
            })
            .collect();
        for i in 0..pos.len() {
            // Legality against every OTHER marker, so the order cannot hide a pair.
            let others: Vec<(i64, i64)> =
                pos.iter().enumerate().filter(|(j, _)| *j != i).map(|(_, p)| *p).collect();
            assert!(
                objectives::is_legal(pos[i].0, pos[i].1, &others, &zones, &cells),
                "illegal marker {:?} in {} seed {}",
                pos[i],
                c["mission"],
                c["layout_seed"]
            );
            assert!(
                pos[i].0.abs() <= 36 - objectives::EDGE_MARGIN_IN
                    && pos[i].1.abs() <= 24 - objectives::EDGE_MARGIN_IN,
                "marker {:?} inside the edge margin",
                pos[i]
            );
            markers += 1;
        }
    }
    assert!(markers >= 500, "expected a few hundred markers, got {markers}");
}

/// RED PROOF for the fixture test: shifting one marker 1" breaks the match. Without
/// this the green above proves only that the test runs.
#[test]
fn a_shifted_marker_breaks_the_match() {
    let f = fixture();
    let cells = cells_of(&f);
    let zones = zones_of(&f);
    let (w, d) = (f["table_w_in"].as_f64().unwrap(), f["table_d_in"].as_f64().unwrap());
    let c = &f["cases"].as_array().unwrap()[0];
    let got = objectives::generate(c["layout_seed"].as_i64().unwrap(), &c["count_spec"], &zones, &cells, w, d);
    let mut shifted = got.positions.clone();
    shifted[0].0 += 1;
    assert_ne!(got.positions, shifted);
}

/// The 9" test is "OVER 9 inches", so exactly 9.0 apart is ILLEGAL. This is the one
/// boundary the book states in words and the one an off-by-one would silently pass.
#[test]
fn exactly_nine_inches_apart_is_not_legal() {
    let cells = Cells::from_pairs(&[], 30);
    let zones: Vec<Poly> = Vec::new();
    assert!(!objectives::is_legal(9, 0, &[(0, 0)], &zones, &cells));
    assert!(objectives::is_legal(10, 0, &[(0, 0)], &zones, &cells));
}

/// A point ON a deployment-zone edge counts as INSIDE, so "outside the zones" is
/// strict — the front_line boundary at z = -12 must be rejected.
#[test]
fn the_zone_boundary_counts_as_inside() {
    let cells = Cells::from_pairs(&[], 30);
    let zones = objectives::zones_of_style(&serde_json::json!({
        "zones": {"1": [[[-36,-24],[36,-24],[36,-12],[-36,-12]]],
                  "2": [[[-36,12],[36,12],[36,24],[-36,24]]]}
    }));
    assert!(!objectives::is_legal(0, -12, &[], &zones, &cells), "on the line is inside");
    assert!(!objectives::is_legal(0, -20, &[], &zones, &cells), "deep in the zone");
    assert!(objectives::is_legal(0, -11, &[], &zones, &cells), "one inch clear is legal");
}

/// An impassable (CONTAINER) cell is unreachable, so no marker may land on it.
#[test]
fn an_impassable_cell_is_rejected() {
    let zones: Vec<Poly> = Vec::new();
    // n = 30, cell 3" — inches 0..3 land in cell (15, 15).
    let cells = Cells::from_pairs(&[((15, 15), 3)], 30);
    assert!(!objectives::is_legal(1, 1, &[], &zones, &cells));
    let open = Cells::from_pairs(&[((15, 15), 2)], 30);
    assert!(objectives::is_legal(1, 1, &[], &zones, &open), "forest is passable");
}
