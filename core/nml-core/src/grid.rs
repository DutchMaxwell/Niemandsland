//! LAZARUS M1 step 8 — 1-inch grid cells: the reachable destinations of a unit's move for an open action
//! space. This module is UNUSED by the planner until the `grid_k` knob (step 9) wires `reachable_cells`
//! into the one-ply, so adding it changes no existing behaviour. `GRID_IN` is the 1-inch lattice laid
//! over `Terrain::to_inch`'s 0-origin inch frame — the same frame the movement planner uses.

use crate::geom::{self, V3};
use crate::mv::{owner_bit, ReachIndex, ReachQuery, CLEARANCE_EPS_IN, NO_OWNER};
use crate::state::State;
use crate::terrain::Terrain;
use crate::unit::UnitStatic;
use crate::{DEFAULT_BASE_RADIUS_M, IN2M};

/// One grid cell edge, inches.
pub const GRID_IN: f64 = 1.0;

/// The 1-inch grid's column count: the table width in inches, rounded up (`to_inch`'s frame).
#[inline]
fn nx_of(t: &Terrain) -> i64 {
    (t.board_in()[0] / GRID_IN).ceil() as i64
}

/// The 1-inch grid's row count: the table height in inches, rounded up.
#[inline]
fn ny_of(t: &Terrain) -> i64 {
    (t.board_in()[1] / GRID_IN).ceil() as i64
}

/// The 1-inch cell id holding world point `p` (metres): `floor(x_in) + nx*floor(y_in)` in `to_inch`'s
/// 0-origin frame. `None` off the table.
pub fn cell_of(t: &Terrain, p: V3) -> Option<u16> {
    let (nx, ny) = (nx_of(t), ny_of(t));
    if nx <= 0 || ny <= 0 {
        return None;
    }
    let q = t.to_inch(p);
    let (cx, cy) = ((q[0] as f64 / GRID_IN).floor() as i64, (q[1] as f64 / GRID_IN).floor() as i64);
    if cx < 0 || cy < 0 || cx >= nx || cy >= ny {
        return None;
    }
    Some((cx + nx * cy) as u16)
}

/// The world point at the centre of cell `id`, at height `y_m`.
pub fn cell_centre(t: &Terrain, id: u16, y_m: f32) -> V3 {
    let nx = nx_of(t).max(1);
    let (cx, cy) = ((id as i64) % nx, (id as i64) / nx);
    t.from_inch([(cx as f64 + 0.5) as f32, (cy as f64 + 0.5) as f32], y_m)
}

/// The 180° mirror of a cell id on an `nx`×`ny` grid: `nx*ny - 1 - id` (row-major `x + nx*y`).
#[inline]
pub fn mirror_cell(id: u16, nx: u16, ny: u16) -> u16 {
    nx * ny - 1 - id
}

/// The 1-inch cells a `unit` may legally END its move on within `band_in` inches: inside the table by the
/// mover's own base radius, not Impassable terrain, and reachable per the tier-2 `reach` index. The mover
/// mask (unit + attached + host) and the clearance radius are built exactly as the sim's charge path
/// (`sim.rs:7517-7536`); the query carries no charge victim.
pub fn reachable_cells(
    state: &State,
    _statics: &[UnitStatic],
    t: &Terrain,
    reach: &ReachIndex,
    unit: usize,
    band_in: f64,
) -> Vec<u16> {
    let (nx, ny) = (nx_of(t), ny_of(t));
    if band_in <= 0.0 || nx <= 0 || ny <= 0 || state.positions[unit].is_empty() {
        return Vec::new();
    }
    let mut mover = owner_bit(unit);
    for h in state.attached[unit].iter() {
        mover |= owner_bit(*h);
    }
    if let Some(host) = state.attached_to[unit] {
        mover |= owner_bit(host);
    }
    let radius_in = state.radii[unit]
        .iter()
        .copied()
        .fold(DEFAULT_BASE_RADIUS_M, f64::max)
        / IN2M
        + CLEARANCE_EPS_IN;
    let centre = geom::centre(&state.positions[unit]);
    let start = t.to_inch(centre);
    let (bx, by) = (t.board_in()[0], t.board_in()[1]);
    let (cxi, cyi) = ((start[0] as f64 / GRID_IN).floor() as i64, (start[1] as f64 / GRID_IN).floor() as i64);
    let r = (band_in / GRID_IN).ceil() as i64;
    let mut out = Vec::new();
    for gy in (cyi - r).max(0)..=(cyi + r).min(ny - 1) {
        for gx in (cxi - r).max(0)..=(cxi + r).min(nx - 1) {
            let p = cell_centre(t, (gx + nx * gy) as u16, centre[1]);
            let pin = t.to_inch(p);
            let d_in = (((p[0] - centre[0]) as f64).hypot((p[2] - centre[2]) as f64)) / IN2M;
            if d_in > band_in
                || (pin[0] as f64) < radius_in
                || (pin[1] as f64) < radius_in
                || (pin[0] as f64) > bx - radius_in
                || (pin[1] as f64) > by - radius_in
                || t.type_at(p) == crate::terrain::CONTAINER
            {
                continue;
            }
            let q = ReachQuery { start, target: pin, radius: radius_in, band: band_in, cap_in: 0.0, mover, foe: NO_OWNER };
            if reach.query(&q).reachable {
                out.push((gx + nx * gy) as u16);
            }
        }
    }
    out
}

#[cfg(test)]
#[path = "tests/grid/mod.rs"]
mod tests;
