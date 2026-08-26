//! NML-1073 M4-5 — `MovementPlanner._cap_difficult_polylines`
//! (movement_planner.gd:842), `trail_crosses_difficult_cells` (:864) and
//! `_difficult_at_point` (:879), a LITERAL transcription.
//!
//! GF/AoF v3.5.1 p.11: a model that moves IN or THROUGH difficult terrain may
//! not move more than 6" in total. NML-230 Breach B enforces it PER GENERATED
//! POLYLINE at the one seam every real-game plan flows through — LAST, after
//! `solve_formation`, so a solver-adjusted route that newly grazes a forest can
//! never keep the full band.
//!
//! FOUR DETAILS DECIDE PARITY:
//!
//!   * PER MODEL. Only a model whose OWN polyline enters difficult is trimmed;
//!     the rest keep the full band. Feasibility is never re-priced.
//!   * THE ORDER OF THE TWO GUARDS (:848-853). The cheap arc-length test runs
//!     FIRST, so a route that grazes a forest but stays under 6" is never even
//!     sampled — and a 6.0000001" route through clear ground is never trimmed.
//!   * EDGE-AWARE SAMPLING (:864-877). Each leg is sampled at
//!     `ceil(len / 1.5)` + 1 points, and each sample tests the base EDGE at
//!     eight compass points as well as the centre. A base grazing the corner of
//!     a difficult cell counts (Testspiel-Welle 3).
//!   * THE ENDPOINT FOLLOWS THE CUT (:861-862). `solved[i]` becomes the trimmed
//!     polyline's last point, so positions and trails stay ONE truth.

use super::cost::Grid;
use super::geom2::{add, distance_to, lerp, mul, polyline_length, trim_polyline, V2};
use super::{cell_of, is_difficult, CELL_IN, EPS, T_NONE};

/// `TerrainRules.terrain_at` — terrain_rules.gd:157.
#[inline]
pub fn terrain_at(grid: &Grid, p: V2) -> i64 {
    *grid.get(&cell_of(p, CELL_IN)).unwrap_or(&T_NONE)
}

/// `MovementPlanner._difficult_at_point` — movement_planner.gd:879. The
/// quantised-grid form of `TerrainRules.base_in_terrain`: the centre plus eight
/// compass samples at the base radius.
pub fn difficult_at_point(p: V2, grid: &Grid, radius_in: f64) -> bool {
    if is_difficult(terrain_at(grid, p)) {
        return true;
    }
    if radius_in <= EPS {
        return false;
    }
    for k in 0..8 {
        let ang = super::form::TAU * k as f64 / 8.0;
        // `Vector2(cos(ang), sin(ang))` narrows before the multiply.
        let unit: V2 = [ang.cos() as f32, ang.sin() as f32];
        if is_difficult(terrain_at(grid, add(p, mul(unit, radius_in)))) {
            return true;
        }
    }
    false
}

/// `MovementPlanner.trail_crosses_difficult_cells` — movement_planner.gd:864.
/// `steps = max(1, ceil(leg / (CELL_IN * 0.5)))`, sampled at `s/steps` for
/// `s` in `0..=steps`, i.e. BOTH endpoints of every leg included.
pub fn trail_crosses_difficult_cells(leg: &[V2], grid: &Grid, radius_in: f64) -> bool {
    if grid.is_empty() {
        return false;
    }
    for i in 1..leg.len() {
        let a = leg[i - 1];
        let b = leg[i];
        let steps = (((distance_to(a, b) / (CELL_IN * 0.5)).ceil()) as i64).max(1);
        for s in 0..=steps {
            if difficult_at_point(lerp(a, b, s as f64 / steps as f64), grid, radius_in) {
                return true;
            }
        }
    }
    false
}

/// What the cap did to one call — the corpus does not record it, so the gate
/// reports it as a census (and the end-to-end `planned`/`trails` comparison is
/// what actually falsifies it).
#[derive(Clone, Copy, Debug, Default)]
pub struct CapReport {
    /// How many polylines were trimmed.
    pub trimmed: usize,
    /// How many were over the cap but did NOT enter difficult terrain.
    pub over_but_clear: usize,
}

/// `MovementPlanner._cap_difficult_polylines` — movement_planner.gd:842.
/// Mutates `trails` and `solved` in place.
pub fn cap_difficult_polylines(
    trails: &mut [Vec<V2>],
    solved: &mut [V2],
    radii: &[f64],
    grid: &Grid,
    cap_in: f64,
) -> CapReport {
    let mut rep = CapReport::default();
    if cap_in <= 0.0 || grid.is_empty() {
        return rep;
    }
    for i in 0..trails.len().min(solved.len()) {
        if polyline_length(&trails[i]) <= cap_in + EPS {
            continue;
        }
        let r_in = radii.get(i).copied().unwrap_or(0.0);
        if !trail_crosses_difficult_cells(&trails[i], grid, r_in) {
            rep.over_but_clear += 1;
            continue;
        }
        let cut = trim_polyline(&trails[i], cap_in);
        if cut.is_empty() {
            continue;
        }
        solved[i] = *cut.last().unwrap();
        trails[i] = cut;
        rep.trimmed += 1;
    }
    rep
}
