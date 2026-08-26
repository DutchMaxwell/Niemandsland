//! The movement planner's predicates and soft costs —
//! `MovementPlanner.step_blocked` (movement_planner.gd:214),
//! `_terrain_cost_at` (:1256), `_segment_cost` (:1281) and `_cspace_blocked`
//! (:1299), plus the `_wall_blocks` / `_zone_blocks` leaves they stand on.
//!
//! These four are what `_theta_star_b` (:1341) evaluates per edge — around 300k
//! calls per `plan_unit_step` — so they are the whole reason the GDScript
//! planner costs 177 s a game.
//!
//! NOTE ON BOARD BOUNDS: `step_blocked` does NOT test them. The board only ever
//! bounds the search through `_theta_star_b`'s `nx`/`ny` cell range (:1360-1361)
//! and through `_board_clamp` (:1551) in the walk and the solver, never inside
//! the step predicate. The port keeps that split.

use std::collections::{HashMap, HashSet};

use super::geom2::{
    distance_to, lerp, point_seg_distance, seg_seg_distance, segments_cross, V2,
};
use super::{
    is_dangerous, is_difficult, CELL_IN, DANGEROUS_COST_MULT, DIFFICULT_COST_MULT, EPS,
    PLAN_CELL_IN, T_NONE,
};

/// A wall segment in the planner's inch frame — `[a, b]`, the shape
/// `MovementPlanner._wall_a` / `_wall_b` (movement_planner.gd:128/134) accept.
pub type Wall = [V2; 2];

/// `TerrainRules` typed cell grid — `Vector2i -> TerrainType`, terrain_rules.gd:157.
pub type Grid = HashMap<(i32, i32), i64>;

/// One of the `avoid_cells` / `avoid_fine` / `forbid_cells` sets (`Vector2i -> true`).
pub type CellSet = HashSet<(i32, i32)>;

/// An `opts["zones"]` entry — `{"c": Vector2, "r": float}`, movement_planner.gd:214.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Zone {
    pub c: V2,
    pub r: f64,
}

/// The subset of `opts` the step/cost layer reads. Everything else in the
/// planner's `opts` dictionary belongs to a later stage.
#[derive(Clone, Copy, Debug)]
pub struct StepOpts<'a> {
    /// `opts["clearance"]` — the moving model's base radius + `CLEARANCE_EPS_IN`.
    pub clearance: f64,
    /// `opts["zones"]` — no-go discs. NOTE the flow rebuilds this per model.
    pub zones: &'a [Zone],
    /// `opts["avoid_cells"]` — coarse (3") go-around set.
    pub avoid_cells: &'a CellSet,
    /// `opts["avoid_fine"]` — base-inflated 1" set. The sequential flow's own
    /// per-model option dicts (movement_planner.gd:1091) DO NOT carry this key,
    /// so it is empty on every edge the flow's Theta* evaluates.
    pub avoid_fine: &'a CellSet,
}

/// An empty cell set, for callers that have no `avoid_*` sets.
pub fn empty_cells() -> &'static CellSet {
    static EMPTY: std::sync::OnceLock<CellSet> = std::sync::OnceLock::new();
    EMPTY.get_or_init(CellSet::new)
}

impl<'a> StepOpts<'a> {
    /// Walls-and-zones only — the legacy `opts = {}` shape plus a clearance.
    pub fn new(clearance: f64, zones: &'a [Zone]) -> Self {
        StepOpts { clearance, zones, avoid_cells: empty_cells(), avoid_fine: empty_cells() }
    }
}

/// `TerrainRules.cell_of` — terrain_rules.gd:153. `int(floor(p.x / cell_size))`
/// on Variant floats, i.e. f64 over f32-exact components.
#[inline]
pub fn cell_of(p: V2, cell_size: f64) -> (i32, i32) {
    (
        (p[0] as f64 / cell_size).floor() as i32,
        (p[1] as f64 / cell_size).floor() as i32,
    )
}

/// `MovementPlanner._wall_blocks` — movement_planner.gd:188. A crossing always
/// blocks; with clearance the step may not dip inside the inflated band, unless
/// it STARTED inside, where only distance-improving escapes are legal.
#[inline]
pub fn wall_blocks(p: V2, c: V2, wa: V2, wb: V2, clearance: f64) -> bool {
    if segments_cross(p, c, wa, wb) {
        return true;
    }
    if clearance <= 0.0 {
        return false;
    }
    if seg_seg_distance(p, c, wa, wb) >= clearance {
        return false;
    }
    let d_p = point_seg_distance(p, wa, wb);
    if d_p >= clearance - EPS {
        return true;
    }
    point_seg_distance(c, wa, wb) <= d_p + EPS
}

/// `MovementPlanner._zone_blocks` — movement_planner.gd:203. The step may
/// neither cross the disc nor end inside it; a model starting inside may only
/// move outward.
#[inline]
pub fn zone_blocks(p: V2, c: V2, centre: V2, r: f64) -> bool {
    if point_seg_distance(centre, p, c) >= r {
        return false;
    }
    let d_p = distance_to(p, centre);
    if d_p >= r - EPS {
        return true;
    }
    distance_to(c, centre) <= d_p + EPS
}

/// `MovementPlanner.path_crosses_wall` reached through `step_blocked`'s
/// clearance-zero branch — movement_planner.gd:220.
#[inline]
pub fn path_crosses_wall_opt(p: V2, c: V2, walls: &[Wall]) -> bool {
    super::geom2::path_crosses_wall(p, c, walls)
}

/// `MovementPlanner.step_blocked` — movement_planner.gd:214. The order matters:
/// walls (base-aware when `clearance > 0`, else the raw crossing test), then
/// every no-go disc, then the coarse avoid set, then the fine one. Each cell
/// set only blocks a step that ENTERS it from outside (escape is always legal).
pub fn step_blocked(p: V2, c: V2, walls: &[Wall], opts: &StepOpts) -> bool {
    if opts.clearance > 0.0 {
        for w in walls {
            if wall_blocks(p, c, w[0], w[1], opts.clearance) {
                return true;
            }
        }
    } else if path_crosses_wall_opt(p, c, walls) {
        return true;
    }
    for z in opts.zones {
        if zone_blocks(p, c, z.c, z.r) {
            return true;
        }
    }
    if !opts.avoid_cells.is_empty()
        && opts.avoid_cells.contains(&cell_of(c, CELL_IN))
        && !opts.avoid_cells.contains(&cell_of(p, CELL_IN))
    {
        return true;
    }
    if !opts.avoid_fine.is_empty()
        && opts.avoid_fine.contains(&cell_of(c, PLAN_CELL_IN))
        && !opts.avoid_fine.contains(&cell_of(p, PLAN_CELL_IN))
    {
        return true;
    }
    false
}

/// `MovementPlanner._terrain_cost_at` — movement_planner.gd:1259. `INF` is a
/// hard block (an avoided cell, coarse or fine); Dangerous and Difficult only
/// price a multiplier so the search may still enter them when the detour is
/// dearer. An EMPTY grid short-circuits to 1.0 before anything else is read —
/// including the avoid sets.
///
/// It does NOT consult `forbid_cells`: that set is read only by
/// `solve_formation` (:1588), the rest-position projection.
pub fn terrain_cost_at(p: V2, grid: &Grid, opts: &StepOpts) -> f64 {
    if grid.is_empty() {
        return 1.0;
    }
    let cell = cell_of(p, CELL_IN);
    let t = *grid.get(&cell).unwrap_or(&T_NONE);
    if opts.avoid_cells.contains(&cell) {
        return f64::INFINITY;
    }
    if opts.avoid_fine.contains(&cell_of(p, PLAN_CELL_IN)) {
        return f64::INFINITY;
    }
    if is_dangerous(t) {
        return DANGEROUS_COST_MULT;
    }
    if is_difficult(t) {
        return DIFFICULT_COST_MULT;
    }
    1.0
}

/// `MovementPlanner._segment_cost` — movement_planner.gd:1284. Path integral of
/// the straight segment a→b: `ceil(span / (PLAN_CELL_IN * 0.5))` samples at the
/// SUB-INTERVAL MIDPOINTS, each weighted by its sub-length. An INF sample prices
/// as plain ground here — hard blocking is `_cspace_blocked`'s job.
#[inline]
pub fn segment_cost(a: V2, b: V2, grid: &Grid, opts: &StepOpts) -> f64 {
    segment_cost_at(a, b, grid, opts, PLAN_CELL_IN * 0.5)
}

/// `_segment_cost` with the resample length as a parameter — the shipped call is
/// `segment_cost` (`sample_in = PLAN_CELL_IN * 0.5 = 0.5"`). The parameter exists
/// only so the gate can prove the step count is load-bearing (RED PROOF).
pub fn segment_cost_at(a: V2, b: V2, grid: &Grid, opts: &StepOpts, sample_in: f64) -> f64 {
    let span = distance_to(a, b);
    if grid.is_empty() || span <= EPS {
        return span;
    }
    let steps = ((span / sample_in).ceil() as i64).max(1);
    let sub = span / steps as f64;
    let mut total = 0.0f64;
    for i in 0..steps {
        let m = terrain_cost_at(
            lerp(a, b, (i as f64 + 0.5) / steps as f64),
            grid,
            opts,
        );
        total += sub * if m.is_infinite() { 1.0 } else { m };
    }
    total
}

/// `MovementPlanner._legs_cost` — movement_planner.gd:1483. Summed soft cost of
/// the existing polyline legs `path[i0..i1]`; the string-pull compares a
/// shortcut against it.
pub fn legs_cost(path: &[V2], i0: usize, i1: usize, grid: &Grid, opts: &StepOpts) -> f64 {
    let mut total = 0.0f64;
    for k in i0..i1 {
        total += segment_cost(path[k], path[k + 1], grid, opts);
    }
    total
}

/// `MovementPlanner._cspace_blocked` — movement_planner.gd:1301. `step_blocked`
/// plus a hard-terrain sweep of the segment INTERIOR: the endpoints are excluded
/// (the search validates nodes on expansion), so a route may start in a hard
/// cell and escape it. Same `ceil(span / 0.5)` sampling as `_segment_cost`, but
/// at the interval BOUNDARIES `i/steps`, not the midpoints.
pub fn cspace_blocked(a: V2, b: V2, walls: &[Wall], grid: &Grid, opts: &StepOpts) -> bool {
    if step_blocked(a, b, walls, opts) {
        return true;
    }
    if grid.is_empty() {
        return false;
    }
    let span = distance_to(a, b);
    let steps = ((span / (PLAN_CELL_IN * 0.5)).ceil() as i64).max(1);
    if steps < 2 {
        return false;
    }
    for i in 1..steps {
        if terrain_cost_at(lerp(a, b, i as f64 / steps as f64), grid, opts).is_infinite() {
            return true;
        }
    }
    false
}
