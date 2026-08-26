//! NML-1073 M4-7 TIER 2 — `reach_query`, the movement answer for the
//! IMAGINATION.
//!
//! `mv::plan::plan_unit_step` is TIER 1: the exact solver, output-identical to
//! the GDScript on all 1 101 recorded calls, ~32 ms a call. That is the right
//! price for the 64 calls a game actually executes on the table and three orders
//! of magnitude too dear for the planner's rollouts, which resolve an imagined
//! activation 20-40k times per real one (see the M4 recon, § D).
//!
//! Today that imagination moves a unit in a STRAIGHT LINE with no obstacle of
//! any kind (`sim::resolve_with`'s move step; `grep wall core/nml-core/src` is
//! empty), which is why the planner over-refuses charges. Tier 2 closes that
//! gap at ~1 µs a query by answering one question and no more:
//!
//! > can this unit, from where it stands, get to that point inside this band —
//! > and if not, where does it stop?
//!
//! WHAT IT IS NOT. No per-model formation, no untangle, no 24-pass solver, no
//! coherency: tier 2 moves a single disc — the unit CENTRE carrying the unit's
//! largest base radius — along a coarse any-angle route. It is an
//! approximation, gated by AGREEMENT with tier 1 rather than by identity, and
//! it never runs on the table.
//!
//! THE THREE ENGINEERING DECISIONS, and why:
//!
//!   * `REACH_CELL_IN = 2.0`. Base diameters are 1-2", unit spacing is 1" and
//!     coherency is 1", so a 2" cell is the COARSEST grid that still resolves a
//!     one-base gap; a 12" charge band is then 6 cells and the whole 72x48"
//!     board is 36x24 = 864 cells, small enough that the terrain raster is one
//!     cache-resident `Vec<f32>`. 3" would align with the terrain raster exactly
//!     and halve the expansions, but it cannot represent the gap a charge
//!     actually threads. Doubling it to 4" moves every number the corpus gate
//!     reports (end centre p90 3.46" -> 4.57"), so the choice is load-bearing.
//!   * `REACH_CAP = 192` expansions, and it is a BELT, not the binding
//!     constraint — say so rather than claim credit for it. The band bound
//!     (`arc > band + one cell` prunes) already stops the frontier: measured on
//!     the corpus, a search averages 22.6 expansions and NOTHING changes at
//!     cap 96 or even 24; only cap 16 starts to move the end centres. The cap
//!     exists so a pathological board cannot make one query unbounded.
//!   * The obstacle index is STATIC and built once (per game header / per
//!     round). Walls and the terrain raster genuinely do not move; the unit
//!     discs are a round-start snapshot and go stale inside a rollout, which is
//!     the deal tier 2 makes — the alternative is rebuilding 80 discs 20-40k
//!     times an activation and losing the whole budget to it.
//!
//! MEMOISATION. `query_memo` keys on (mover, foe, start, target, band, cap,
//! radius) with the two positions and the three lengths quantised to
//! `REACH_MEMO_IN` = 0.25". The task's key is "(unit, target, band)"; this one
//! is that PLUS the geometry, so a hit can only be returned when the query is
//! genuinely the same query — a unit that moved 3" between rollout steps misses
//! instead of being answered from a stale row.

use std::cell::{Cell, RefCell};
use std::cmp::Reverse;
use std::collections::{BinaryHeap, HashMap};

use super::cost::{wall_blocks, zone_blocks, Grid, StepOpts, Wall, Zone};
use super::geom2::{add, distance_to, lerp, mul, normalized, point_seg_distance, sub, to_f32, V2};
use super::io::MoveCall;
use super::{terrain_cost_at, CELL_IN, EPS, THETA_DIAG};

/// The coarse search cell, inches. See the module header for why 2".
pub const REACH_CELL_IN: f64 = 2.0;
/// The hard expansion cap of one query.
pub const REACH_CAP: usize = 192;
/// The memo's quantisation, inches.
pub const REACH_MEMO_IN: f64 = 0.25;
/// The largest query `radius` the WALL buckets are built for. A query above it
/// falls back to scanning every wall — correct, just slower.
pub const REACH_WALL_PAD_IN: f64 = 2.0;
/// How far ahead the string pull looks for a shortcut. Paths inside a 12" band
/// are ~10 nodes, so this is "the whole path" without an O(n^2) blow-up.
pub const REACH_PULL_AHEAD: usize = 6;

/// `Disc::bit` for an obstacle that belongs to no unit and can never be
/// exempted — a recorded `opts["zones"]` entry, already resolved to a disc.
pub const NO_OWNER: u32 = 0;

/// The owner bit of roster index `i`. `BattleSim._spacing_fraction`'s exemptions
/// are per GROUP (the mover plus its attached heroes plus its host,
/// sim.rs:295-299), which is a SET, not one index — so ownership travels as a
/// bit and the query carries two masks. A roster beyond 32 units simply cannot
/// exempt its tail: `owner_bit` answers 0, i.e. "always an obstacle", the safe
/// side.
#[inline]
pub fn owner_bit(i: usize) -> u32 {
    if i < 32 {
        1u32 << i
    } else {
        0
    }
}

/// One no-go disc. `r_body` is the obstacle itself, `r_buf` the same disc with
/// the 1" unit-spacing buffer — the split `BattleSim._spacing_fraction`
/// (battle_sim.gd:550-620) makes, where a CHARGE victim projects body-only so
/// the charge may end in base contact.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Disc {
    pub c: V2,
    pub r_body: f32,
    pub r_buf: f32,
    /// `owner_bit(roster index)`, or `NO_OWNER`.
    pub bit: u32,
}

/// One tier-2 question.
#[derive(Clone, Copy, Debug)]
pub struct ReachQuery {
    /// The unit centre now.
    pub start: V2,
    /// Where it wants to be.
    pub target: V2,
    /// The moving unit's clearance — its largest base radius (+ the planner's
    /// `CLEARANCE_EPS_IN` when the caller has it), inches.
    pub radius: f64,
    /// The arc-length allowance, inches. `_walk_offset` spends ARC against this,
    /// which is why the terrain multipliers steer the route but never pay for it.
    pub band: f64,
    /// The p.11 per-polyline difficult cap (`opts["difficult_cap_in"]`), or 0
    /// for none: a route that enters Difficult may spend at most this much.
    pub cap_in: f64,
    /// Owner-bit MASK of the mover's group — those discs are no obstacle at all.
    pub mover: u32,
    /// Owner-bit MASK of the charge victim's group — BODY radius, no buffer.
    pub foe: u32,
}

impl ReachQuery {
    /// The plain shape: no owners, no cap.
    pub fn new(start: V2, target: V2, radius: f64, band: f64) -> ReachQuery {
        ReachQuery {
            start,
            target,
            radius,
            band,
            cap_in: 0.0,
            mover: NO_OWNER,
            foe: NO_OWNER,
        }
    }
}

/// The answer. `end_centre` is where the unit centre actually stops — the
/// target when it got there, the point on the route where the band ran out
/// otherwise.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Reach {
    pub reachable: bool,
    pub arc_in: f64,
    pub end_centre: V2,
}

/// What the index did, for the bench and the gate. Never read by the sim.
#[derive(Clone, Copy, Debug, Default)]
pub struct ReachStats {
    pub queries: u64,
    pub memo_hits: u64,
    /// Queries the straight line answered without a search.
    pub straight: u64,
    pub searches: u64,
    pub expansions: u64,
}

/// A CSR bucket table: `off[cell]..off[cell+1]` indexes into `idx`.
#[derive(Clone, Debug, Default)]
struct Buckets {
    off: Vec<u32>,
    idx: Vec<u32>,
}

impl Buckets {
    fn build(cells: usize, pairs: &[(u32, u32)]) -> Buckets {
        let mut off = vec![0u32; cells + 1];
        for (c, _) in pairs {
            off[*c as usize + 1] += 1;
        }
        for i in 0..cells {
            off[i + 1] += off[i];
        }
        let mut cur = off.clone();
        let mut idx = vec![0u32; pairs.len()];
        for (c, item) in pairs {
            let s = cur[*c as usize] as usize;
            idx[s] = *item;
            cur[*c as usize] += 1;
        }
        Buckets { off, idx }
    }

    #[inline]
    fn get(&self, cell: usize) -> &[u32] {
        if self.off.is_empty() {
            return &[];
        }
        let a = self.off[cell] as usize;
        let b = self.off[cell + 1] as usize;
        &self.idx[a..b]
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
struct MemoKey {
    mover: u32,
    foe: u32,
    s: (i32, i32),
    t: (i32, i32),
    band: i32,
    cap: i32,
    rad: i32,
}

#[derive(Clone, Debug, Default)]
struct Scratch {
    gen: u32,
    seen: Vec<u32>,
    closed: Vec<u32>,
    g: Vec<f64>,
    arc: Vec<f64>,
    parent: Vec<i32>,
    heap: BinaryHeap<Reverse<(u64, u32)>>,
    path: Vec<V2>,
    pulled: Vec<V2>,
}

impl Scratch {
    fn begin(&mut self, cells: usize) {
        if self.seen.len() != cells {
            self.seen = vec![0; cells];
            self.closed = vec![0; cells];
            self.g = vec![0.0; cells];
            self.arc = vec![0.0; cells];
            self.parent = vec![-1; cells];
            self.gen = 0;
        }
        self.gen = self.gen.wrapping_add(1);
        if self.gen == 0 {
            // A wrap would make a stale stamp look fresh; clear once every 4bn.
            self.seen.iter_mut().for_each(|s| *s = 0);
            self.closed.iter_mut().for_each(|s| *s = 0);
            self.gen = 1;
        }
        self.heap.clear();
        self.path.clear();
        self.pulled.clear();
    }
}

/// How one index was built — the inputs `ReachIndex::build` needs besides the
/// terrain sampler.
pub struct ReachBuild<'a> {
    pub cell_in: f64,
    /// Board extents in the planner's 0-origin inch frame, `[x, y]`.
    pub board_in: [f64; 2],
    pub walls: &'a [Wall],
    pub discs: Vec<Disc>,
    /// True when the disc radii are the OBSTACLE's alone and the mover's own
    /// radius must be added per query (`sim` builds them that way). False when
    /// the radii are already the final ones (`opts["zones"]` folds the mover's
    /// radius in at record time, solo_controller.gd:5022-5051).
    pub add_mover_radius: bool,
    pub wall_pad_in: f64,
    /// The hard expansion cap of one query. Shipped: `REACH_CAP`.
    pub cap: usize,
    /// How far ahead the string pull looks. Shipped: `REACH_PULL_AHEAD`.
    pub pull_ahead: usize,
}

impl<'a> ReachBuild<'a> {
    pub fn new(board_in: [f64; 2], walls: &'a [Wall]) -> ReachBuild<'a> {
        ReachBuild {
            cell_in: REACH_CELL_IN,
            board_in,
            walls,
            discs: Vec::new(),
            add_mover_radius: false,
            wall_pad_in: REACH_WALL_PAD_IN,
            cap: REACH_CAP,
            pull_ahead: REACH_PULL_AHEAD,
        }
    }
}

/// The static per-round obstacle index: the terrain rasterised onto the coarse
/// grid, plus walls and unit discs bucketed onto the same grid.
#[derive(Clone, Debug, Default)]
pub struct ReachIndex {
    cell_in: f64,
    nx: i32,
    ny: i32,
    /// Per-cell terrain multiplier; `f32::INFINITY` is a hard block.
    mult: Vec<f32>,
    walls: Vec<Wall>,
    /// `[min_x, min_y, max_x, max_y]` per wall.
    wall_box: Vec<[f32; 4]>,
    wall_b: Buckets,
    wall_pad: f64,
    /// Per cell: the distance from its CENTRE to the nearest wall. An edge
    /// whose bucket cell is farther than `radius + slack` from every wall
    /// cannot be wall-blocked, so the whole wall loop is skipped. This is what
    /// pays for the query budget — 81 % of the corpus's edges are nowhere near
    /// a wall and the 48-segment scan is pure waste on them.
    wall_dist: Vec<f32>,
    /// The same early-out for discs: the distance from the cell centre to the
    /// nearest disc SURFACE (`|c - d.c| - r_buf`), so an exemption can only make
    /// the true answer emptier, never fuller.
    disc_dist: Vec<f32>,
    /// How far outside its bucket cell one edge can reach — `cell + diag/2`,
    /// the bound both `segment_blocked`'s sub-steps and the A*'s diagonal hops
    /// respect. See `build`.
    slack: f64,
    discs: Vec<Disc>,
    disc_b: Buckets,
    add_mover_radius: bool,
    cap: usize,
    pull_ahead: usize,
    /// `1.0 / cell_in`, so the hot path multiplies instead of dividing.
    inv_cell: f64,
    memo: RefCell<HashMap<MemoKey, Reach>>,
    scratch: RefCell<Scratch>,
    stats: Cell<ReachStats>,
}

impl ReachIndex {
    /// Rasterises `mult_at` (an inch-frame point -> terrain multiplier, with
    /// `f32::INFINITY` for impassable) onto the coarse grid and buckets the
    /// walls and discs onto the same cells.
    pub fn build(b: ReachBuild, mult_at: impl Fn(V2) -> f32) -> ReachIndex {
        let cell_in = if b.cell_in > 0.0 { b.cell_in } else { REACH_CELL_IN };
        let nx = ((b.board_in[0] / cell_in).ceil() as i32).max(1);
        let ny = ((b.board_in[1] / cell_in).ceil() as i32).max(1);
        let cells = (nx as usize) * (ny as usize);
        let mut ix = ReachIndex {
            cell_in,
            nx,
            ny,
            mult: Vec::with_capacity(cells),
            walls: b.walls.to_vec(),
            wall_box: Vec::new(),
            wall_b: Buckets::default(),
            wall_pad: b.wall_pad_in,
            wall_dist: Vec::new(),
            disc_dist: Vec::new(),
            slack: 0.0,
            discs: b.discs,
            disc_b: Buckets::default(),
            add_mover_radius: b.add_mover_radius,
            cap: if b.cap > 0 { b.cap } else { REACH_CAP },
            pull_ahead: b.pull_ahead,
            inv_cell: 1.0 / cell_in,
            memo: RefCell::new(HashMap::new()),
            scratch: RefCell::new(Scratch::default()),
            stats: Cell::new(ReachStats::default()),
        };
        for cy in 0..ny {
            for cx in 0..nx {
                ix.mult.push(mult_at(ix.cell_centre((cx, cy))));
            }
        }
        // A blocking obstacle for the edge (p -> c) can sit this far from the
        // centre of p's cell: p is inside the cell (<= diag/2), c is at most one
        // cell further, and the obstacle itself reaches out by its radius.
        let diag = cell_in * std::f64::consts::SQRT_2;
        let slack = cell_in + diag * 0.5;
        ix.slack = slack;
        ix.wall_dist = vec![f32::INFINITY; cells];
        ix.disc_dist = vec![f32::INFINITY; cells];
        for cy in 0..ny {
            for cx in 0..nx {
                let k = ix.idx((cx, cy));
                let q = ix.cell_centre((cx, cy));
                let mut dw = f64::INFINITY;
                for w in &ix.walls {
                    dw = dw.min(point_seg_distance(q, w[0], w[1]));
                }
                ix.wall_dist[k] = dw as f32;
                let mut dd = f64::INFINITY;
                for d in &ix.discs {
                    dd = dd.min(distance_to(q, d.c) - d.r_buf.max(d.r_body) as f64);
                }
                ix.disc_dist[k] = dd as f32;
            }
        }
        let mut pairs: Vec<(u32, u32)> = Vec::new();
        for (i, d) in ix.discs.iter().enumerate() {
            let r = d.r_buf.max(d.r_body) as f64 + slack;
            let lo = ix.clamp_cell(ix.cell_of(to_f32([d.c[0] as f64 - r, d.c[1] as f64 - r])));
            let hi = ix.clamp_cell(ix.cell_of(to_f32([d.c[0] as f64 + r, d.c[1] as f64 + r])));
            for cy in lo.1..=hi.1 {
                for cx in lo.0..=hi.0 {
                    if distance_to(ix.cell_centre((cx, cy)), d.c) <= r {
                        pairs.push((ix.idx((cx, cy)) as u32, i as u32));
                    }
                }
            }
        }
        ix.disc_b = Buckets::build(cells, &pairs);
        pairs.clear();
        let pad = b.wall_pad_in + slack;
        for (i, w) in ix.walls.iter().enumerate() {
            let lo = ix.clamp_cell(ix.cell_of(to_f32([
                (w[0][0].min(w[1][0])) as f64 - pad,
                (w[0][1].min(w[1][1])) as f64 - pad,
            ])));
            let hi = ix.clamp_cell(ix.cell_of(to_f32([
                (w[0][0].max(w[1][0])) as f64 + pad,
                (w[0][1].max(w[1][1])) as f64 + pad,
            ])));
            for cy in lo.1..=hi.1 {
                for cx in lo.0..=hi.0 {
                    if point_seg_distance(ix.cell_centre((cx, cy)), w[0], w[1]) <= pad {
                        pairs.push((ix.idx((cx, cy)) as u32, i as u32));
                    }
                }
            }
        }
        ix.wall_b = Buckets::build(cells, &pairs);
        // The wall AABBs, so the hot loop can reject a wall with six compares
        // instead of a `segments_cross` plus three distance solves.
        ix.wall_box = ix
            .walls
            .iter()
            .map(|w| {
                [
                    w[0][0].min(w[1][0]),
                    w[0][1].min(w[1][1]),
                    w[0][0].max(w[1][0]),
                    w[0][1].max(w[1][1]),
                ]
            })
            .collect();
        ix
    }

    /// The index for ONE recorded `plan_unit_step` call — the obstacle set the
    /// exact solver saw on that call, and nothing else: its walls, its typed
    /// terrain grid, its `avoid_cells` as hard blocks (the ladder rung the
    /// recording actually ran), and its `opts["zones"]` as discs.
    pub fn from_move_call(call: &MoveCall, cell_in: f64, cap: usize, pull_ahead: usize) -> ReachIndex {
        let board = call.board();
        let grid: &Grid = &call.grid;
        let opts = StepOpts {
            clearance: 0.0,
            zones: &[],
            avoid_cells: &call.opts.avoid_cells,
            avoid_fine: &call.opts.avoid_fine,
        };
        // movement_planner.gd:1050 — Traversal (`zones_rest_only`) means the
        // move itself ignores every disc; only the RESTING place must be clear.
        let zones: &[Zone] = if call.opts.zones_rest_only { &[] } else { &call.opts.zones };
        let discs: Vec<Disc> = zones
            .iter()
            .map(|z: &Zone| Disc {
                c: z.c,
                r_body: z.r as f32,
                r_buf: z.r as f32,
                bit: NO_OWNER,
            })
            .collect();
        let mut b = ReachBuild::new([board[0] as f64, board[1] as f64], &call.walls);
        b.cell_in = cell_in;
        b.cap = cap;
        b.pull_ahead = pull_ahead;
        b.discs = discs;
        b.wall_pad_in = call.opts.clearance.max(REACH_WALL_PAD_IN);
        ReachIndex::build(b, |p| {
            let m = terrain_cost_at(p, grid, &opts);
            if m.is_infinite() {
                f32::INFINITY
            } else {
                m as f32
            }
        })
    }

    pub fn cell_in(&self) -> f64 {
        self.cell_in
    }
    pub fn cap(&self) -> usize {
        self.cap
    }
    pub fn pull_ahead(&self) -> usize {
        self.pull_ahead
    }
    pub fn cells(&self) -> usize {
        (self.nx as usize) * (self.ny as usize)
    }
    pub fn discs(&self) -> &[Disc] {
        &self.discs
    }
    pub fn stats(&self) -> ReachStats {
        self.stats.get()
    }
    pub fn memo_len(&self) -> usize {
        self.memo.borrow().len()
    }
    pub fn clear_memo(&self) {
        self.memo.borrow_mut().clear();
    }
    /// The discs bucketed onto one cell — the unit test's window into the index.
    pub fn disc_bucket(&self, cell: (i32, i32)) -> &[u32] {
        if !self.in_bounds(cell) {
            return &[];
        }
        self.disc_b.get(self.idx(cell))
    }
    /// The walls bucketed onto one cell.
    pub fn wall_bucket(&self, cell: (i32, i32)) -> &[u32] {
        if !self.in_bounds(cell) {
            return &[];
        }
        self.wall_b.get(self.idx(cell))
    }
    /// The rasterised terrain multiplier of one cell.
    pub fn mult_at_cell(&self, cell: (i32, i32)) -> f32 {
        if !self.in_bounds(cell) {
            return f32::INFINITY;
        }
        self.mult[self.idx(cell)]
    }

    #[inline]
    fn idx(&self, c: (i32, i32)) -> usize {
        (c.1 as usize) * (self.nx as usize) + (c.0 as usize)
    }
    #[inline]
    fn in_bounds(&self, c: (i32, i32)) -> bool {
        c.0 >= 0 && c.1 >= 0 && c.0 < self.nx && c.1 < self.ny
    }
    #[inline]
    pub fn cell_of(&self, p: V2) -> (i32, i32) {
        (
            (p[0] as f64 * self.inv_cell).floor() as i32,
            (p[1] as f64 * self.inv_cell).floor() as i32,
        )
    }
    #[inline]
    fn clamp_cell(&self, c: (i32, i32)) -> (i32, i32) {
        (c.0.clamp(0, self.nx - 1), c.1.clamp(0, self.ny - 1))
    }
    #[inline]
    pub fn cell_centre(&self, c: (i32, i32)) -> V2 {
        to_f32([
            (c.0 as f64 + 0.5) * self.cell_in,
            (c.1 as f64 + 0.5) * self.cell_in,
        ])
    }

    /// `reach_query` WITH the per-rollout memo. This is the entry the sim uses.
    pub fn query_memo(&self, q: &ReachQuery) -> Reach {
        let k = self.memo_key(q);
        if let Some(r) = self.memo.borrow().get(&k) {
            let mut s = self.stats.get();
            s.queries += 1;
            s.memo_hits += 1;
            self.stats.set(s);
            return *r;
        }
        let r = self.query(q);
        self.memo.borrow_mut().insert(k, r);
        r
    }

    fn memo_key(&self, q: &ReachQuery) -> MemoKey {
        let qz = |v: f64| (v / REACH_MEMO_IN).round() as i32;
        MemoKey {
            mover: q.mover,
            foe: q.foe,
            s: (qz(q.start[0] as f64), qz(q.start[1] as f64)),
            t: (qz(q.target[0] as f64), qz(q.target[1] as f64)),
            band: qz(q.band),
            cap: qz(q.cap_in),
            rad: qz(q.radius),
        }
    }

    /// `reach_query(unit, target, band)` — the tier-2 answer, no memo.
    pub fn query(&self, q: &ReachQuery) -> Reach {
        let mut s = self.stats.get();
        s.queries += 1;
        let straight = distance_to(q.start, q.target);
        if straight <= EPS {
            self.stats.set(s);
            return Reach { reachable: true, arc_in: 0.0, end_centre: q.start };
        }
        if self.nx <= 0 || self.mult.is_empty() {
            // No index (an absent board): the legacy straight line, band-clamped.
            self.stats.set(s);
            return self.finish(&[q.start, q.target], q);
        }
        if !self.segment_blocked(q.start, q.target, q) {
            s.straight += 1;
            self.stats.set(s);
            return self.finish(&[q.start, q.target], q);
        }
        s.searches += 1;
        self.stats.set(s);
        let path = self.search(q);
        self.finish(&path, q)
    }

    /// Turns a route into the answer: spend the band along it, and say
    /// "reachable" only when the route both ENDED at the target and fitted.
    fn finish(&self, path: &[V2], q: &ReachQuery) -> Reach {
        if path.len() < 2 {
            return Reach { reachable: false, arc_in: 0.0, end_centre: q.start };
        }
        let total = polyline_arc(path);
        let mut budget = q.band;
        if q.cap_in > 0.0 && self.crosses_difficult(path) {
            budget = budget.min(q.cap_in);
        }
        let last = path[path.len() - 1];
        if total <= budget + EPS {
            let reachable = distance_to(last, q.target) <= EPS;
            return Reach { reachable, arc_in: total, end_centre: last };
        }
        Reach { reachable: false, arc_in: budget, end_centre: walk_to(path, budget) }
    }

    /// True when any sample of the route sits in a Difficult cell — the trigger
    /// `mv::cap::trail_crosses_difficult_cells` uses for the p.11 cap.
    fn crosses_difficult(&self, path: &[V2]) -> bool {
        let step = self.cell_in * 0.5;
        for w in path.windows(2) {
            let span = distance_to(w[0], w[1]);
            let n = ((span / step).ceil() as i64).max(1);
            for i in 0..=n {
                let p = lerp(w[0], w[1], i as f64 / n as f64);
                let c = self.cell_of(p);
                if self.in_bounds(c) && self.mult[self.idx(c)] == super::DIFFICULT_COST_MULT as f32
                {
                    return true;
                }
            }
        }
        false
    }

    /// DIAGNOSTIC ONLY — which obstacle class blocks the straight run `a -> b`:
    ///
    ///   bit 1  hard terrain or the board edge
    ///   bit 2  a wall, found through the BUCKETS (what an answer uses)
    ///   bit 4  a disc, found through the BUCKETS
    ///   bit 8  a disc, found by scanning EVERY disc
    ///   bit 16 a wall, found by scanning EVERY wall
    ///
    /// The pairs (2, 16) and (4, 8) must agree on every edge: a bit set only in
    /// the linear half is a bucketing HOLE, which is what `tests/mv_reach.rs`
    /// exists to rule out. Never consulted by an answer.
    pub fn block_reason(&self, a: V2, b: V2, q: &ReachQuery) -> u8 {
        let span = distance_to(a, b);
        let steps = ((span / self.cell_in).ceil() as i64).max(1);
        let mut prev = a;
        let mut bits = 0u8;
        for i in 1..=steps {
            let c = lerp(a, b, i as f64 / steps as f64);
            let cc = self.cell_of(c);
            let pc = self.cell_of(prev);
            if !self.in_bounds(cc)
                || (self.mult[self.idx(cc)].is_infinite()
                    && (!self.in_bounds(pc) || !self.mult[self.idx(pc)].is_infinite()))
            {
                bits |= 1;
            } else {
                let bucket = self.idx(self.clamp_cell(pc));
                for wi in self.wall_b.get(bucket) {
                    let w = self.walls[*wi as usize];
                    if wall_blocks(prev, c, w[0], w[1], q.radius) {
                        bits |= 2;
                    }
                }
                if self.walls.iter().any(|w| wall_blocks(prev, c, w[0], w[1], q.radius)) {
                    bits |= 16;
                }
                for di in self.disc_b.get(bucket) {
                    let d = self.discs[*di as usize];
                    if d.bit & q.mover != 0 {
                        continue;
                    }
                    let mut r = if d.bit & q.foe != 0 { d.r_body } else { d.r_buf } as f64;
                    if self.add_mover_radius {
                        r += q.radius;
                    }
                    if r > 0.0 && zone_blocks(prev, c, d.c, r) {
                        bits |= 4;
                    }
                }
                // bit 8: the SAME test without the buckets. A line that sets 8
                // without 4 is a bucketing hole, not an obstacle.
                for d in &self.discs {
                    if d.bit & q.mover != 0 {
                        continue;
                    }
                    let mut r = if d.bit & q.foe != 0 { d.r_body } else { d.r_buf } as f64;
                    if self.add_mover_radius {
                        r += q.radius;
                    }
                    if r > 0.0 && zone_blocks(prev, c, d.c, r) {
                        bits |= 8;
                    }
                }
            }
            prev = c;
        }
        bits
    }

    /// Walks a straight run in sub-steps of at most one cell so every sub-step
    /// can be answered from ONE bucket — see the slack in `build`.
    fn segment_blocked(&self, a: V2, b: V2, q: &ReachQuery) -> bool {
        let span = distance_to(a, b);
        let steps = ((span / self.cell_in).ceil() as i64).max(1);
        let mut prev = a;
        for i in 1..=steps {
            let c = lerp(a, b, i as f64 / steps as f64);
            if self.edge_blocked(prev, c, q) {
                return true;
            }
            prev = c;
        }
        false
    }

    /// One sub-step. Hard terrain and the board edge block on ENTRY only, the
    /// same "escape is always legal" rule `cost::step_blocked` applies.
    fn edge_blocked(&self, p: V2, c: V2, q: &ReachQuery) -> bool {
        let pc = self.cell_of(p);
        self.edge_blocked_from(p, c, q, self.idx(self.clamp_cell(pc)), self.in_bounds(pc))
    }

    /// The same test with p's bucket already known — the A* has it, and two f64
    /// divisions per neighbour are worth saving in a loop this hot.
    fn edge_blocked_from(
        &self,
        p: V2,
        c: V2,
        q: &ReachQuery,
        bucket: usize,
        p_in: bool,
    ) -> bool {
        let cc = self.cell_of(c);
        if !self.in_bounds(cc) {
            return true;
        }
        if self.mult[self.idx(cc)].is_infinite() && (!p_in || !self.mult[bucket].is_infinite()) {
            return true;
        }
        if (self.wall_dist[bucket] as f64) <= q.radius + self.slack {
            if q.radius > self.wall_pad {
                for w in &self.walls {
                    if wall_blocks(p, c, w[0], w[1], q.radius) {
                        return true;
                    }
                }
            } else {
                let r = q.radius as f32;
                let (lox, hix) = if p[0] < c[0] { (p[0] - r, c[0] + r) } else { (c[0] - r, p[0] + r) };
                let (loy, hiy) = if p[1] < c[1] { (p[1] - r, c[1] + r) } else { (c[1] - r, p[1] + r) };
                for wi in self.wall_b.get(bucket) {
                    let bx = self.wall_box[*wi as usize];
                    if bx[2] < lox || bx[0] > hix || bx[3] < loy || bx[1] > hiy {
                        continue;
                    }
                    let w = self.walls[*wi as usize];
                    if wall_blocks(p, c, w[0], w[1], q.radius) {
                        return true;
                    }
                }
            }
        }
        let disc_reach = self.slack + if self.add_mover_radius { q.radius } else { 0.0 };
        if (self.disc_dist[bucket] as f64) <= disc_reach {
            for di in self.disc_b.get(bucket) {
                let d = self.discs[*di as usize];
                if d.bit & q.mover != 0 {
                    continue;
                }
                let mut r = if d.bit & q.foe != 0 { d.r_body } else { d.r_buf } as f64;
                if self.add_mover_radius {
                    r += q.radius;
                }
                if r > 0.0 && zone_blocks(p, c, d.c, r) {
                    return true;
                }
            }
        }
        false
    }

    /// The bounded coarse A*. Nodes are cell centres (the start node keeps the
    /// TRUE start point); `g` is terrain-weighted so the route steers around
    /// Difficult, `arc` is the plain length the band is spent in.
    fn search(&self, q: &ReachQuery) -> Vec<V2> {
        let cells = self.cells();
        let sc = &mut *self.scratch.borrow_mut();
        sc.begin(cells);
        let start = self.clamp_cell(self.cell_of(q.start));
        let goal = self.clamp_cell(self.cell_of(q.target));
        let si = self.idx(start);
        sc.seen[si] = sc.gen;
        sc.g[si] = 0.0;
        sc.arc[si] = 0.0;
        sc.parent[si] = -1;
        sc.heap.push(Reverse((distance_to(q.start, q.target).to_bits(), si as u32)));
        let mut best_h = f64::INFINITY;
        let mut best_i = si;
        let mut reached: Option<usize> = None;
        let mut expansions = 0u64;
        let limit = q.band + self.cell_in;
        while let Some(Reverse((_, cur))) = sc.heap.pop() {
            let cur = cur as usize;
            if sc.closed[cur] == sc.gen {
                continue;
            }
            sc.closed[cur] = sc.gen;
            expansions += 1;
            if expansions as usize > self.cap {
                break;
            }
            let cell = ((cur % self.nx as usize) as i32, (cur / self.nx as usize) as i32);
            let p = if cur == si { q.start } else { self.cell_centre(cell) };
            let h = distance_to(p, q.target);
            if h < best_h {
                best_h = h;
                best_i = cur;
            }
            if cell == goal {
                reached = Some(cur);
                break;
            }
            for (dx, dy) in THETA_DIAG {
                let n = (cell.0 + dx, cell.1 + dy);
                if !self.in_bounds(n) {
                    continue;
                }
                let ni = self.idx(n);
                if sc.closed[ni] == sc.gen {
                    continue;
                }
                let m = self.mult[ni];
                if m.is_infinite() {
                    continue;
                }
                let c = self.cell_centre(n);
                let step = distance_to(p, c);
                let arc = sc.arc[cur] + step;
                if arc > limit {
                    continue;
                }
                let w = 0.5 * (self.mult[cur] as f64 + m as f64);
                let g = sc.g[cur] + step * w;
                if sc.seen[ni] == sc.gen && g >= sc.g[ni] - EPS {
                    continue;
                }
                if self.edge_blocked_from(p, c, q, cur, true) {
                    continue;
                }
                sc.seen[ni] = sc.gen;
                sc.g[ni] = g;
                sc.arc[ni] = arc;
                sc.parent[ni] = cur as i32;
                let f = g + distance_to(c, q.target);
                sc.heap.push(Reverse((f.to_bits(), ni as u32)));
            }
        }
        let mut s = self.stats.get();
        s.expansions += expansions;
        self.stats.set(s);
        // Reconstruct from the goal cell, or from the node that got closest.
        let mut cur = reached.unwrap_or(best_i) as i32;
        sc.path.clear();
        while cur >= 0 {
            let cell = ((cur as usize % self.nx as usize) as i32, (cur as usize / self.nx as usize) as i32);
            sc.path.push(if cur as usize == si { q.start } else { self.cell_centre(cell) });
            cur = sc.parent[cur as usize];
        }
        sc.path.reverse();
        if reached.is_some() {
            // The last hop is to the TRUE target, not to its cell centre.
            let tail = sc.path[sc.path.len() - 1];
            if distance_to(tail, q.target) > EPS && !self.segment_blocked(tail, q.target, q) {
                sc.path.push(q.target);
            }
        }
        let mut out: Vec<V2> = Vec::with_capacity(sc.path.len());
        self.string_pull(&sc.path, &mut out, q);
        out
    }

    /// The greedy line-of-sight shortcut: a coarse 8-connected route is up to
    /// 8 % longer than the taut one, and the band is spent in ARC, so without
    /// this tier 2 would refuse moves the exact solver makes.
    fn string_pull(&self, path: &[V2], out: &mut Vec<V2>, q: &ReachQuery) {
        out.clear();
        if path.is_empty() {
            return;
        }
        out.push(path[0]);
        let mut i = 0usize;
        while i + 1 < path.len() {
            let far = (i + self.pull_ahead.max(1)).min(path.len() - 1);
            let mut j = far;
            while j > i + 1 && self.segment_blocked(path[i], path[j], q) {
                j -= 1;
            }
            out.push(path[j]);
            i = j;
        }
    }
}

/// The plain arc length of a polyline.
pub fn polyline_arc(path: &[V2]) -> f64 {
    let mut total = 0.0f64;
    for w in path.windows(2) {
        total += distance_to(w[0], w[1]);
    }
    total
}

/// The point `budget` inches along the polyline — `_walk_offset`'s spend, with
/// no obstacle test (the polyline is already clear).
pub fn walk_to(path: &[V2], budget: f64) -> V2 {
    if path.is_empty() {
        return [0.0, 0.0];
    }
    if budget <= 0.0 {
        return path[0];
    }
    let mut spent = 0.0f64;
    for w in path.windows(2) {
        let leg = distance_to(w[0], w[1]);
        if leg <= EPS {
            continue;
        }
        if spent + leg <= budget + EPS {
            spent += leg;
            continue;
        }
        let want = budget - spent;
        return add(w[0], mul(normalized(sub(w[1], w[0])), want));
    }
    path[path.len() - 1]
}

/// `TerrainRules` cell size in the coarse frame — a convenience for callers
/// that rasterise a recorded `Grid` (3" typed cells) onto a 2" reach grid.
pub const TERRAIN_CELL_IN: f64 = CELL_IN;
