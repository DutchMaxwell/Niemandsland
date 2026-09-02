//! S5a — `mv::gate::finalize_placement`, the port of `_finalize_placement`
//! passes 1 and 2 (solo_controller.gd:6371).
//!
//! The fixture is two RECORDED non-charge plans from `qbg_ref` whose own
//! models' bases overlap at the planner's endpoints, each the LAST plan call
//! its activation made — i.e. the configuration the table itself handed the
//! gate. `roomy` has band slack to spare and the gate must clear the overlap;
//! `frozen` walked its whole band, so `_gate_disp_caps_m` freezes six of seven
//! models at the packed-contact epsilon and the residual overlap is left to the
//! caller's ladder by design (:6722-6728) — there the RED is the CAP, not the
//! clearing.

use nml_core::mv::gate::{finalize_placement, Disc};
use nml_core::mv::geom2::V2;
use serde_json::Value;

/// `SoloController.GATE_SLACK_EPS_IN` :159.
const GATE_SLACK_EPS_IN: f64 = 0.05;

struct Case {
    planned: Vec<V2>,
    radii_in: Vec<f64>,
    caps_in: Vec<f64>,
    board_in: [f64; 2],
    worst_overlap_in: f64,
}

fn load(name: &str) -> Case {
    let raw = std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/tests/fixtures/mv_gate_overlap.json"
    ))
    .expect("the recorded gate fixture");
    let fx: Value = serde_json::from_str(&raw).expect("valid JSON");
    let c = &fx[name];
    let f = |v: &Value| v.as_f64().expect("number");
    let arr = |v: &Value| v.as_array().expect("array").clone();
    let reach = f(&c["reach_in"]);
    Case {
        planned: arr(&c["planned_in"])
            .iter()
            .map(|p| [f(&p[0]) as f32, f(&p[1]) as f32])
            .collect(),
        radii_in: arr(&c["radii_in"]).iter().map(f).collect(),
        // `_gate_disp_caps_m` :6343 — every leg here is under the p.11 cap
        // already (reach <= 12", and the difficult branch only lowers it to 6"),
        // so the budget is the granted reach and the slack is what it left.
        caps_in: arr(&c["trail_len_in"])
            .iter()
            .map(|l| (reach - f(l)).max(0.0) + GATE_SLACK_EPS_IN)
            .collect(),
        board_in: [f(&c["board_in"][0]), f(&c["board_in"][1])],
        worst_overlap_in: f(&c["worst_overlap_in"]),
    }
}

/// The deepest base-on-base overlap inside one configuration, inches.
fn worst_overlap(cfg: &[V2], radii: &[f64]) -> f64 {
    let mut w = f64::NEG_INFINITY;
    for i in 0..cfg.len() {
        for j in (i + 1)..cfg.len() {
            let d = ((cfg[i][0] as f64 - cfg[j][0] as f64).powi(2)
                + (cfg[i][1] as f64 - cfg[j][1] as f64).powi(2))
            .sqrt();
            w = w.max(radii[i] + radii[j] - d);
        }
    }
    w
}

/// RED: with the gate the recorded 0.686" base overlap is gone, and no model
/// spent more than its band slack getting there. Make `finalize_placement`
/// return its input untouched (the gate off) and the first assertion fails by
/// the full 0.686" — 68 times the 0.01" the resolver calls cleared.
#[test]
fn the_gate_clears_a_recorded_base_overlap_inside_every_band_cap() {
    let c = load("roomy");
    assert!(
        c.worst_overlap_in > 0.5,
        "the fixture must actually overlap, else it proves nothing: {}",
        c.worst_overlap_in
    );
    assert!(
        (worst_overlap(&c.planned, &c.radii_in) - c.worst_overlap_in).abs() < 1e-4,
        "the fixture's own number and its endpoints disagree"
    );

    let (got, rep) = finalize_placement(&c.planned, &c.radii_in, &[], &c.caps_in, c.board_in, None);

    // `SeparationResolver.RESOLVE_EPSILON_INCHES` :46 is what "cleared" means.
    let left = worst_overlap(&got, &c.radii_in);
    assert!(
        left <= 0.01,
        "still {left}\" of base overlap after the gate"
    );
    for (i, d) in rep.disp_in.iter().enumerate() {
        assert!(
            *d <= c.caps_in[i] + 1e-9,
            "model {i} spent {d}\" of a {}\" cap",
            c.caps_in[i]
        );
    }
    assert_eq!(rep.bounds_in, 0.0, "no model was off the table here");
    assert!(
        rep.disp_in.iter().any(|d| *d > 0.01),
        "the gate did nothing at all"
    );
}

/// The other half of the cap rule: a unit that walked its whole band gets only
/// the 0.05" packed-contact epsilon, so the gate may NOT buy its way out of the
/// overlap — it stays inside every cap and hands the debt on. Remove the cap
/// truncation and model 3 walks 0.667", thirteen times the 0.05" it had.
#[test]
fn a_band_spent_unit_is_frozen_rather_than_pushed_past_its_cap() {
    let c = load("frozen");
    assert!(c.worst_overlap_in > 0.5, "{}", c.worst_overlap_in);
    let (got, rep) = finalize_placement(&c.planned, &c.radii_in, &[], &c.caps_in, c.board_in, None);
    for (i, d) in rep.disp_in.iter().enumerate() {
        assert!(
            *d <= c.caps_in[i] + 1e-9,
            "model {i} spent {d}\" of a {}\" cap",
            c.caps_in[i]
        );
    }
    // And the debt really is left standing, exactly as :6722-6728 says.
    assert!(
        worst_overlap(&got, &c.radii_in) > 0.01,
        "the frozen case cleared — cap not binding"
    );
}

/// Pass 1 on its own: a model planned off the table edge is clamped back inside
/// the 0.02 m margin, on BOTH axes, and the report says by how much.
#[test]
fn pass_one_clamps_a_model_back_onto_the_table() {
    let board = [72.0, 48.0];
    let margin = 0.02 / 0.0254;
    let planned: Vec<V2> = vec![[80.0, -3.0], [36.0, 24.0]];
    let (got, rep) = finalize_placement(&planned, &[0.5, 0.5], &[], &[], board, None);
    assert!(
        (got[0][0] as f64 - (72.0 - margin)).abs() < 1e-4,
        "{:?}",
        got[0]
    );
    assert!((got[0][1] as f64 - margin).abs() < 1e-4, "{:?}", got[0]);
    assert_eq!(got[1], planned[1], "a model already inside is untouched");
    assert!(rep.bounds_in > 8.0, "the clamp was {}\"", rep.bounds_in);
}

/// The external obstacle set is real too: one model planned on top of another
/// unit's base is pushed off it, not merely off its own unit's models.
#[test]
fn the_gate_pushes_off_another_units_base() {
    let planned: Vec<V2> = vec![[36.0, 24.0]];
    let other = Disc {
        c: [36.4, 24.0],
        r: 0.8,
    };
    let (got, _) = finalize_placement(&planned, &[0.8], &[other], &[4.0], [72.0, 48.0], None);
    let d =
        ((got[0][0] as f64 - other.c[0]).powi(2) + (got[0][1] as f64 - other.c[1]).powi(2)).sqrt();
    assert!(
        d >= 0.8 + other.r - 0.01,
        "still {d}\" apart, bases sum to 1.6\""
    );
}

// === S5b — pass 3, the terrain projection ==================================

use nml_core::terrain::{self, CellParams, PlainTerrain, Terrain, CONTAINER};

/// The school table, 6x4 ft on the 3" grid — cell `(cx, cz)` covers world
/// `x in [(cx - 15) * 3", (cx - 14) * 3")`, so `(15, 15)` is the 3" square with
/// its corner on the board centre.
fn school(cells: &[(i64, i64, i32)]) -> Terrain {
    Terrain::build(&PlainTerrain {
        cells: cells.iter().map(|c| [c.0 as f64, c.1 as f64, c.2 as f64]).collect(),
        sandbox: vec![],
        walls: vec![],
        cell_params: CellParams {
            table_size_feet: [6.0, 4.0],
            grid_rotation_degrees: 0.0,
            grid_size_inches: 3.0,
            inches_to_meters: 0.0254,
        },
    })
}

/// Is this base, at an INCH-frame point, resting in the impassable class?
fn in_container(t: &Terrain, p: V2, r_in: f64) -> bool {
    terrain::base_in_terrain(t.from_inch(p, 0.0), r_in * 0.0254, t, terrain::is_forbidden_rest)
}

/// RED: a plan that parks a 0.5" base dead in the middle of a CONTAINER cell —
/// impassable, "may never move through", and resting inside is worse. With pass
/// 3 the gate hops it out to the nearest clear ring and the base is clear;
/// without pass 3 the model is still inside the container and the second
/// assertion fails by the full 3" cell. The hop is 2.36" (ring 6 of the 0.3937"
/// rings, sixteen compass points, `-x` winning the x-then-z tie-break) — well
/// inside the 6" of band slack, so the cap never bites here.
#[test]
fn pass_three_projects_a_model_out_of_an_impassable_container() {
    let t = school(&[(15, 15, CONTAINER)]);
    let planned: Vec<V2> = vec![[37.5, 25.5]]; // world (1.5", 1.5") = the cell centre
    assert_eq!(t.type_at(t.from_inch(planned[0], 0.0)), CONTAINER, "fixture is not in a container");
    assert!(in_container(&t, planned[0], 0.5));

    let (got, rep) = finalize_placement(&planned, &[0.5], &[], &[6.0], [72.0, 48.0], Some(&t));

    assert!(!in_container(&t, got[0], 0.5), "still resting in the container at {:?}", got[0]);
    assert!(rep.disp_in[0] > 2.0 && rep.disp_in[0] <= 6.0, "hop was {}\"", rep.disp_in[0]);
    assert!(!rep.capped[0], "the 6\" cap must not bite on a 2.4\" hop");
    // the x-then-z tie-break inside the ring: straight -x, nothing diagonal
    assert!((got[0][1] as f64 - 25.5).abs() < 1e-3, "{:?}", got[0]);
    assert!(got[0][0] < 37.5, "{:?}", got[0]);
}

/// The other half of the cap rule (:6407-6411): a model with only 1" of band
/// slack left cannot afford the 2.36" hop, and a PARTIAL hop would still rest
/// inside the container — so the projection is refused WHOLE, the route-true
/// spot is kept and the model is marked for the caller's ladder.
#[test]
fn a_projection_beyond_the_band_slack_is_refused_whole() {
    let t = school(&[(15, 15, CONTAINER)]);
    let planned: Vec<V2> = vec![[37.5, 25.5]];
    let (got, rep) = finalize_placement(&planned, &[0.5], &[], &[1.0], [72.0, 48.0], Some(&t));
    assert_eq!(got[0], planned[0], "the route-true spot must survive");
    assert!(rep.capped[0], "the refusal must be marked");
    assert_eq!(rep.disp_in[0], 0.0);
}

/// `None` is the board with no terrain line: pass 3 is off and the same plan
/// comes back untouched — the S5a behaviour, bit for bit.
#[test]
fn pass_three_is_off_without_a_terrain() {
    let planned: Vec<V2> = vec![[37.5, 25.5]];
    let (got, _) = finalize_placement(&planned, &[0.5], &[], &[6.0], [72.0, 48.0], None);
    assert_eq!(got[0], planned[0]);
}
