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
    distance_to, lerp, point_seg_distance, seg_seg_distance_apart, segments_cross, V2,
};
use super::{
    is_dangerous, is_difficult, CELL_IN, DANGEROUS_COST_MULT, DIFFICULT_COST_MULT, EPS,
    PLAN_CELL_IN, T_NONE,
};

/// A wall segment in the planner's inch frame — `[a, b]`, the shape
/// `MovementPlanner._wall_a` / `_wall_b` (movement_planner.gd:128/134) accept.
pub type Wall = [V2; 2];

/// `TerrainRules` typed cell grid — `Vector2i -> TerrainType`, terrain_rules.gd:157.
pub type Grid = HashMap<(i32, i32), i64, CellBuild>;

/// One of the `avoid_cells` / `avoid_fine` / `forbid_cells` sets (`Vector2i -> true`).
pub type CellSet = HashSet<(i32, i32), CellBuild>;

/// The cell grids are probed once per planner step, so SipHash (the std default) was ~35 % of the
/// route planner (aifix preselect-speed profile). A multiplicative Fx-style hasher over the two `i32`
/// coordinates is enough for these small, trusted, integer keys; the grids are only looked up and
/// never iterated for a result, so no order-dependence rides on the hasher.
#[derive(Default, Clone, Copy)]
pub struct CellHasher(u64);

impl CellHasher {
    #[inline]
    fn add(&mut self, x: u64) {
        self.0 = (self.0.rotate_left(5) ^ x).wrapping_mul(0x517c_c1b7_2722_0a95);
    }
}

impl std::hash::Hasher for CellHasher {
    #[inline]
    fn write(&mut self, bytes: &[u8]) {
        for &b in bytes {
            self.add(u64::from(b));
        }
    }
    #[inline]
    fn write_i32(&mut self, i: i32) {
        self.add(i as u32 as u64);
    }
    #[inline]
    fn finish(&self) -> u64 {
        self.0
    }
}

/// `BuildHasher` of `Grid` / `CellSet` (`Grid::default()` replaces `Grid::new()`).
pub type CellBuild = std::hash::BuildHasherDefault<CellHasher>;

/// An `opts["zones"]` entry — `{"c": Vector2, "r": float}`, movement_planner.gd:214.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Zone {
    pub c: V2,
    pub r: f64,
}

/// An `opts["ledges"]` entry (heights B2, movement_planner.gd `ledge_crossings`) — a climbable edge
/// `{"a", "b", "dy_in"}`: a leg crossing it pays `dy_in` inches on top of its flat length (GF p.11).
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Ledge {
    pub a: V2,
    pub b: V2,
    pub dy_in: f64,
}

/// GF p.11: pieces over 3" tall are impassable — such ledges stay walls.
pub const LEDGE_CLIMB_MAX_IN: f64 = 3.0;
/// A model that cannot pay a climb halts this far short of the ledge.
pub const LEDGE_STOP_IN: f64 = 0.05;

/// `MovementPlanner.ledge_crossings` — `[t along a→b, dy_in]` per crossed ledge, sorted by `t`. The hit
/// point is Godot's `Geometry2D.segment_intersects_segment`, ported in f32 (no hit for parallels).
pub fn ledge_crossings(a: V2, b: V2, ledges: &[Ledge]) -> Vec<(f64, f64)> {
    let mut out: Vec<(f64, f64)> = Vec::new();
    for l in ledges {
        let bv = [b[0] - a[0], b[1] - a[1]];
        let ablen = bv[0] * bv[0] + bv[1] * bv[1];
        if ablen <= 0.0 {
            continue;
        }
        let bn = [bv[0] / ablen, bv[1] / ablen];
        let rot = |p: V2| -> [f32; 2] {
            let (px, py) = (p[0] - a[0], p[1] - a[1]);
            [px * bn[0] + py * bn[1], py * bn[0] - px * bn[1]]
        };
        let (c, d) = (rot(l.a), rot(l.b));
        // Godot 4: both ends strictly on one side (CMP_EPSILON band) or parallel (`is_equal_approx`) → none;
        // a leg that only touches an edge's end still crosses it.
        const CMP: f32 = 0.00001;
        let approx = |x: f32, y: f32| x == y || (x - y).abs() < (CMP * x.abs()).max(CMP);
        if (c[1] < -CMP && d[1] < -CMP) || (c[1] > CMP && d[1] > CMP) || approx(c[1], d[1]) {
            continue;
        }
        let abpos = d[0] + (c[0] - d[0]) * d[1] / (d[1] - c[1]);
        if !(0.0..=1.0).contains(&abpos) {
            continue;
        }
        let hit = [a[0] + bv[0] * abpos, a[1] + bv[1] * abpos];
        out.push((distance_to(a, hit) / distance_to(a, b).max(EPS), l.dy_in));
    }
    out.sort_by(|x, y| x.0.total_cmp(&y.0));
    out
}

/// `MovementPlanner.ledge_cost` — the climb inches the straight leg a→b pays.
pub fn ledge_cost(a: V2, b: V2, ledges: &[Ledge]) -> f64 {
    ledge_crossings(a, b, ledges).iter().map(|c| c.1).sum()
}

/// The subset of `opts` the step/cost layer reads. Everything else in the
/// planner's `opts` dictionary belongs to a later stage.
#[derive(Clone, Copy, Debug)]
pub struct StepOpts<'a> {
    /// `opts["ledges"]` — climbable edges priced by `segment_cost` and spent by the walk.
    pub ledges: &'a [Ledge],
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
    /// STANDALONE_SWEEP_A_2026-09-14, rows `Dangerous Terrain Debuff` /
    /// `Difficult Terrain Debuff` — the moving unit's granted terrain debuffs
    /// (the FROZEN `EPOCH_27_TERRAIN_DEBUFF`). The carried rule prices the
    /// same way the cell does: Dangerous first, then Difficult, exactly the
    /// cell order below. False on every call recorded before the gate.
    pub dangerous_debuff: bool,
    pub difficult_debuff: bool,
}

/// An empty cell set, for callers that have no `avoid_*` sets.
pub fn empty_cells() -> &'static CellSet {
    static EMPTY: std::sync::OnceLock<CellSet> = std::sync::OnceLock::new();
    EMPTY.get_or_init(CellSet::default)
}

impl<'a> StepOpts<'a> {
    /// Walls-and-zones only — the legacy `opts = {}` shape plus a clearance.
    pub fn new(clearance: f64, zones: &'a [Zone]) -> Self {
        StepOpts {
            ledges: &[],
            clearance,
            zones,
            avoid_cells: empty_cells(),
            avoid_fine: empty_cells(),
            dangerous_debuff: false,
            difficult_debuff: false,
        }
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

/// The f32 rounding guard of the wall culling in `step_blocked`, inches.
const WALL_CULL_GUARD: f64 = 1e-3;

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
    // `segments_cross` was just answered false, so the crossing arm of `seg_seg_distance` cannot fire.
    if seg_seg_distance_apart(p, c, wa, wb) >= clearance {
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
        // Exact culling (aifix preselect-speed): a wall whose box lies farther than the clearance
        // (+ an f32 rounding guard) from the step's box can neither cross the step nor come within
        // `clearance` of it, so `wall_blocks` would answer false — skip it without the 4 distance tests.
        let q = QueryBox::new(p, c, opts.clearance);
        for w in walls {
            if q.may_touch(w) && wall_blocks(p, c, w[0], w[1], opts.clearance) {
                return true;
            }
        }
    } else if path_crosses_wall_opt(p, c, walls) {
        return true;
    }
    non_wall_blocked(p, c, opts)
}

/// The step's bounding box grown by `clearance` + the f32 guard: a wall outside it cannot block the step.
struct QueryBox {
    lo_x: f64,
    hi_x: f64,
    lo_y: f64,
    hi_y: f64,
}

impl QueryBox {
    #[inline]
    fn new(p: V2, c: V2, clearance: f64) -> QueryBox {
        let m = clearance + WALL_CULL_GUARD;
        QueryBox {
            lo_x: (p[0].min(c[0]) as f64) - m,
            hi_x: (p[0].max(c[0]) as f64) + m,
            lo_y: (p[1].min(c[1]) as f64) - m,
            hi_y: (p[1].max(c[1]) as f64) + m,
        }
    }

    #[inline]
    fn may_touch(&self, w: &Wall) -> bool {
        !((w[0][0].min(w[1][0]) as f64) > self.hi_x
            || (w[0][0].max(w[1][0]) as f64) < self.lo_x
            || (w[0][1].min(w[1][1]) as f64) > self.hi_y
            || (w[0][1].max(w[1][1]) as f64) < self.lo_y)
    }
}

/// Everything `step_blocked` asks AFTER the walls: the no-go discs, then the coarse and the fine avoid sets.
fn non_wall_blocked(p: V2, c: V2, opts: &StepOpts) -> bool {
    if !opts.zones.is_empty() {
        // `zone_blocks` answers false whenever the disc centre is `r` or more from the segment; a centre farther than
        // `r` (+ the f32 guard) from the segment's bounding box is, so those discs are skipped without the distance.
        let (lo_x, hi_x) = (p[0].min(c[0]) as f64, p[0].max(c[0]) as f64);
        let (lo_y, hi_y) = (p[1].min(c[1]) as f64, p[1].max(c[1]) as f64);
        for z in opts.zones {
            let r = z.r + WALL_CULL_GUARD;
            let (zx, zy) = (z.c[0] as f64, z.c[1] as f64);
            if zx < lo_x - r || zx > hi_x + r || zy < lo_y - r || zy > hi_y + r {
                continue;
            }
            if zone_blocks(p, c, z.c, z.r) {
                return true;
            }
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

/// A uniform grid over a wall list, built once per search (aifix route lane): `step_blocked` for one step asks only the
/// walls whose box overlaps the step's grown box, found through the buckets, instead of scanning all of them. The answer
/// is an OR over walls, so which walls are asked and in what order cannot change it — the same walls are the only ones
/// that can answer true (`QueryBox::may_touch` is applied to every candidate).
pub struct WallIndex<'a> {
    walls: &'a [Wall],
    ox: f64,
    oy: f64,
    nx: usize,
    ny: usize,
    start: Vec<u32>,
    ids: Vec<u32>,
}

/// Bucket edge in inches (a step of the planner is 1-3", a wall a few).
const WALL_BUCKET_IN: f64 = 6.0;
/// Below this many walls a scan beats the index.
const WALL_INDEX_MIN: usize = 8;

impl<'a> WallIndex<'a> {
    pub fn new(walls: &'a [Wall]) -> WallIndex<'a> {
        let (mut lo_x, mut lo_y, mut hi_x, mut hi_y) = (f64::INFINITY, f64::INFINITY, f64::NEG_INFINITY, f64::NEG_INFINITY);
        for w in walls {
            for e in w {
                lo_x = lo_x.min(e[0] as f64);
                hi_x = hi_x.max(e[0] as f64);
                lo_y = lo_y.min(e[1] as f64);
                hi_y = hi_y.max(e[1] as f64);
            }
        }
        if walls.len() < WALL_INDEX_MIN || !lo_x.is_finite() {
            return WallIndex { walls, ox: 0.0, oy: 0.0, nx: 0, ny: 0, start: Vec::new(), ids: Vec::new() };
        }
        let nx = (((hi_x - lo_x) / WALL_BUCKET_IN).floor() as usize + 1).min(64);
        let ny = (((hi_y - lo_y) / WALL_BUCKET_IN).floor() as usize + 1).min(64);
        let mut me = WallIndex { walls, ox: lo_x, oy: lo_y, nx, ny, start: vec![0; nx * ny + 1], ids: Vec::new() };
        for pass in 0..2 {
            let mut fill = me.start.clone();
            for (wi, w) in walls.iter().enumerate() {
                let (x0, x1) = me.span(w[0][0].min(w[1][0]) as f64, w[0][0].max(w[1][0]) as f64, me.ox, me.nx);
                let (y0, y1) = me.span(w[0][1].min(w[1][1]) as f64, w[0][1].max(w[1][1]) as f64, me.oy, me.ny);
                for by in y0..=y1 {
                    for bx in x0..=x1 {
                        let b = by * me.nx + bx;
                        if pass == 0 {
                            me.start[b + 1] += 1;
                        } else {
                            me.ids[fill[b] as usize] = wi as u32;
                            fill[b] += 1;
                        }
                    }
                }
            }
            if pass == 0 {
                for b in 0..me.nx * me.ny {
                    me.start[b + 1] += me.start[b];
                }
                me.ids = vec![0; me.start[me.nx * me.ny] as usize];
            }
        }
        me
    }

    /// The clamped bucket range of the interval [lo, hi] along one axis.
    #[inline]
    fn span(&self, lo: f64, hi: f64, origin: f64, n: usize) -> (usize, usize) {
        let f = |v: f64| (((v - origin) / WALL_BUCKET_IN).floor().max(0.0) as usize).min(n - 1);
        (f(lo), f(hi))
    }

    /// `step_blocked(p, c, walls, opts)` with the walls asked through the buckets.
    pub fn step_blocked(&self, p: V2, c: V2, opts: &StepOpts) -> bool {
        if self.nx == 0 || opts.clearance <= 0.0 {
            return step_blocked(p, c, self.walls, opts);
        }
        let q = QueryBox::new(p, c, opts.clearance);
        let (x0, x1) = self.span(q.lo_x, q.hi_x, self.ox, self.nx);
        let (y0, y1) = self.span(q.lo_y, q.hi_y, self.oy, self.ny);
        for by in y0..=y1 {
            for bx in x0..=x1 {
                let b = by * self.nx + bx;
                for &wi in &self.ids[self.start[b] as usize..self.start[b + 1] as usize] {
                    let w = &self.walls[wi as usize];
                    if q.may_touch(w) && wall_blocks(p, c, w[0], w[1], opts.clearance) {
                        return true;
                    }
                }
            }
        }
        non_wall_blocked(p, c, opts)
    }

    /// `cspace_blocked(a, b, walls, grid, opts)` through the index.
    pub fn cspace_blocked(&self, a: V2, b: V2, grid: &Grid, opts: &StepOpts) -> bool {
        self.step_blocked(a, b, opts) || cspace_tail(a, b, grid, opts)
    }
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
    if opts.dangerous_debuff || is_dangerous(t) {
        return DANGEROUS_COST_MULT;
    }
    if opts.difficult_debuff || is_difficult(t) {
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
        return span + ledge_cost(a, b, opts.ledges);
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
    total + ledge_cost(a, b, opts.ledges)
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
    step_blocked(a, b, walls, opts) || cspace_tail(a, b, grid, opts)
}

/// The terrain half of `cspace_blocked`: a hard-blocked cell (INF cost) on the sampled line.
fn cspace_tail(a: V2, b: V2, grid: &Grid, opts: &StepOpts) -> bool {
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
