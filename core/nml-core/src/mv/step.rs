//! NML-1073 M5 D5-2 — the CHARGE MOVE as the TABLE executes it, over a `State`.
//!
//! The chain on the table is `_charge_move` (solo_controller.gd:8582, the aim)
//! -> `_move_toward` (:4558) -> `_execute_move` (:4769, the band and the passes)
//! -> `_plan_positions` (:6136, the `plan_unit_step` call) -> the M4 port. This
//! file is that chain built from a `State` instead of from live `GameUnit`
//! nodes, so the fast core lands a charge where the table lands it and can
//! measure the arc the melee snap has to fit into (`last_move_remaining_in`
//! :8659 = the granted band minus the LONGEST single-model arc).
//!
//! WHAT IS NOT PORTED HERE, stated so the seam is not read as more than it is:
//!   * `_finalize_placement` (:6303) — the hard post-plan gate. A charge skips
//!     its coherency and terrain shorten but still gets its overlap push, so a
//!     landing here can sit a hair inside a base the table would have pushed off.
//!   * the stall escalation (:4816), the gate-collapse ladder (:4871) and the
//!     boxed/sidestep escape (:4941). All three are `not allow_contact`, so a
//!     charge never enters any of them — no divergence, only unwritten code.
//!   * the prewarm plan cache (pure, cannot change a result) and the regiment
//!     tray slide (`_is_regiment`, not a `State` field).
//!
//! WALLS. `plan_unit_step` routes around `TerrainOverlay.get_wall_segments_world()`
//! and the act corpus carried none before rung D5-2a. `Terrain::walls_in` is
//! empty on such a corpus and the route then bends only around Impassable CELLS
//! — the caller says so out loud rather than pretending the board is clear.

use crate::geom::{self, V3};
use crate::state::State;
use crate::terrain::{self, Terrain};
use crate::IN2M;

use super::cost::{CellSet, Grid, Zone};
use super::entry::plan_unit_step_call;
use super::geom2::{self as g2, V2};
use super::io::{CallOpts, MoveCall};

/// `SoloController.BOUNDS_MARGIN_M` :16 — models stay a hair inside the edge.
const BOUNDS_MARGIN_M: f64 = 0.02;
/// `SoloController.DIFFICULT_MOVE_CAP_IN` :67 — GF/AoF v3.5.1 p.11.
const DIFFICULT_MOVE_CAP_IN: f64 = 6.0;
/// `SoloController.UNIT_SPACING_IN` :74.
const UNIT_SPACING_IN: f64 = 1.0;
/// `SeparationChecker.DEFAULT_BASE_RADIUS_M` separation_checker.gd:81.
const DEFAULT_BASE_RADIUS_M: f64 = 0.016;
/// `SoloController.OVERLAP_EPS_M` :154 — also the distance-truth trim's slack.
const OVERLAP_EPS_M: f64 = 0.0005;

/// One model the charge displaces — `SoloController._moving_models` :5375 is the
/// unit's own alive models PLUS its attached heroes', one flat list.
#[derive(Clone, Copy, Debug)]
pub struct Mover {
    pub unit: usize,
    pub model: usize,
}

/// What the charge move did.
#[derive(Clone, Debug)]
pub struct Landing {
    pub movers: Vec<Mover>,
    /// Per-model resting place, WORLD metres, in `movers` order.
    pub end: Vec<V3>,
    /// `last_move_budget_in` :5060 — the band the move was actually granted
    /// (the p.11 cap may have cut it).
    pub budget_in: f64,
    /// The LONGEST single-model arc, in inches — what :8659 subtracts.
    pub arc_in: f64,
    /// `_dangerous_trail_flags(trails, trail_radii_m)` :5036, in `movers` order:
    /// did this model's ROUTE cross a DANGEROUS cell? Read off the trails at the
    /// same point the table reads them — after the distance-truth trim, BEFORE
    /// `_retrace_to` (:5053) rewrites them toward the gated endpoint. Always
    /// false for a Flying unit, which ignores terrain effects while moving (p.13).
    pub dangerous: Vec<bool>,
    /// The `plan_unit_step` call this landing was solved from — the LAST one,
    /// so a p.11 re-plan reports the call it actually kept. `None` only when
    /// the bounds-clamped delta was zero and no call was ever made. Kept for
    /// the gate, which holds it against the recorded `moves_calls.jsonl` line.
    pub call: Option<MoveCall>,
}

impl Landing {
    /// `SoloController.last_move_remaining_in` :8659-8667.
    pub fn remaining_in(&self) -> f64 {
        (self.budget_in - self.arc_in).max(0.0)
    }
}

fn radius_of(state: &State, m: Mover) -> f64 {
    state.radii[m.unit].get(m.model).copied().unwrap_or(DEFAULT_BASE_RADIUS_M)
}

fn pos_of(state: &State, m: Mover) -> V3 {
    geom::to_f32(state.positions[m.unit][m.model])
}

/// `_moving_models` :5375 — own models first, then each attached hero's.
fn movers_of(state: &State, u: usize) -> Vec<Mover> {
    let mut out: Vec<Mover> =
        (0..state.positions[u].len()).map(|model| Mover { unit: u, model }).collect();
    for &h in state.attached[u].iter() {
        out.extend((0..state.positions[h].len()).map(|model| Mover { unit: h, model }));
    }
    out
}

/// `SoloController.unit_centre` :8510 — the unit's OWN alive models, falling
/// back to its attached heroes' when the hero is the sole survivor.
fn unit_centre(state: &State, u: usize) -> V3 {
    if !state.positions[u].is_empty() {
        return geom::centre(&state.positions[u]);
    }
    let mut pts: Vec<[f64; 3]> = Vec::new();
    for &h in state.attached[u].iter() {
        pts.extend_from_slice(&state.positions[h]);
    }
    geom::centre(&pts)
}

/// `SoloController.nearest_charge_vector` :8550 — the smallest base-EDGE gap
/// (inches) over all charger/target model pairs and the unit table-plane
/// direction from that charger model toward that target model.
fn nearest_charge_vector(state: &State, from: &[Mover], to: &[Mover]) -> (f64, V2) {
    let mut best_gap = f64::INFINITY;
    let mut best_dir: V2 = [0.0, 0.0];
    for cm in from {
        let c = pos_of(state, *cm);
        let rc = radius_of(state, *cm);
        for em in to {
            let e = pos_of(state, *em);
            let flat: V3 = [c[0] - e[0], 0.0, c[2] - e[2]];
            let gap = (geom::length(flat) as f64 - rc - radius_of(state, *em)) / IN2M;
            if gap < best_gap {
                best_gap = gap;
                best_dir = [e[0] - c[0], e[2] - c[2]];
            }
        }
    }
    if g2::length(best_dir) < 0.00001 {
        return (best_gap, [0.0, 0.0]);
    }
    (best_gap, g2::normalized(best_dir))
}

/// `SoloController._clamp_to_bounds` :8879, `half` in METRES.
fn clamp_to_bounds(p: V3, half: [f64; 2]) -> V3 {
    let cl = |v: f32, lim: f64| -> f32 { v.max(-(lim as f32)).min(lim as f32) };
    [cl(p[0], half[0] - BOUNDS_MARGIN_M), p[1], cl(p[2], half[1] - BOUNDS_MARGIN_M)]
}

/// `SoloController._axis_scale` :8896.
fn axis_scale(start: f64, d: f64, limit: f64) -> f64 {
    let dest = start + d;
    if dest.abs() <= limit || d.abs() < 1e-5 {
        return 1.0;
    }
    let bound = if dest > 0.0 { limit } else { -limit };
    ((bound - start) / d).clamp(0.0, 1.0)
}

/// `SoloController._clamp_delta_to_bounds` :8886.
fn clamp_delta_to_bounds(pos: &[V3], delta: V3, half: [f64; 2]) -> V3 {
    let mut scale = 1.0f64;
    for p in pos {
        scale = scale.min(axis_scale(p[0] as f64, delta[0] as f64, half[0] - BOUNDS_MARGIN_M));
        scale = scale.min(axis_scale(p[2] as f64, delta[2] as f64, half[1] - BOUNDS_MARGIN_M));
    }
    geom::mul(delta, scale.clamp(0.0, 1.0))
}

/// `MoveIntent.plan_unit_move` move_intent.gd:49 — anchor, clamp, rigid delta.
fn plan_unit_move(pos: &[V3], target: V3, max_in: f64) -> V3 {
    if pos.is_empty() {
        return [0.0, 0.0, 0.0];
    }
    let owned: Vec<[f64; 3]> = pos.iter().map(|p| geom::to_f64(*p)).collect();
    let anchor = geom::centre(&owned);
    let to: V3 = [target[0] - anchor[0], 0.0, target[2] - anchor[2]];
    let dist = geom::length(to) as f64;
    let max_m = max_in * IN2M;
    let dest = if dist <= max_m || dist < 0.0001 {
        [target[0], anchor[1], target[2]]
    } else {
        geom::add(anchor, geom::mul(geom::normalized(to), max_m))
    };
    [dest[0] - anchor[0], 0.0, dest[2] - anchor[2]]
}

/// `_targets_in_difficult` :5144 / `_targets_in_dangerous` :5160 — would the
/// RIGID move's per-model targets land (base edge included) in that class?
fn targets_in(
    pos: &[V3],
    goal: V3,
    reach_in: f64,
    radius_m: f64,
    t: &Terrain,
    half: [f64; 2],
    class: fn(i32) -> bool,
) -> bool {
    if !t.is_valid() {
        return false;
    }
    let delta = clamp_delta_to_bounds(pos, plan_unit_move(pos, goal, reach_in), half);
    pos.iter().any(|p| terrain::base_in_terrain(geom::add(*p, delta), radius_m, t, class))
}

/// `_terrain_grid_in` :5254 — the typed 3" cell grid plus its avoid set.
fn terrain_cells(t: &Terrain, board: [f64; 2], avoid_diff: bool, avoid_dang: bool) -> (Grid, CellSet) {
    let mut grid = Grid::new();
    let mut avoid = CellSet::new();
    if !t.is_valid() {
        return (grid, avoid);
    }
    let nx = ((board[0] / terrain::CELL_IN).ceil() as i64).max(1);
    let ny = ((board[1] / terrain::CELL_IN).ceil() as i64).max(1);
    for cy in 0..ny {
        for cx in 0..nx {
            let c = [
                ((cx as f64 + 0.5) * terrain::CELL_IN) as f32,
                ((cy as f64 + 0.5) * terrain::CELL_IN) as f32,
            ];
            let ty = t.type_at(t.from_inch(c, 0.0));
            if ty == terrain::NONE {
                continue;
            }
            let cell = (cx as i32, cy as i32);
            grid.insert(cell, ty as i64);
            if (avoid_diff && terrain::is_difficult(ty)) || (avoid_dang && terrain::is_dangerous(ty)) {
                avoid.insert(cell);
            }
        }
    }
    (grid, avoid)
}

/// The 1"-cell sweep `_avoid_fine_cells_in` :5296 and `_forbid_cells_in` :5335
/// share: the move's own AABB plus a margin, clamped to the board, one
/// predicate per cell CENTRE in world metres.
fn fine_cells(
    mpos: &[V2],
    mdelta: V2,
    board: [f64; 2],
    margin_in: f64,
    t: &Terrain,
    hit: &dyn Fn(V3) -> bool,
) -> CellSet {
    let mut out = CellSet::new();
    if !t.is_valid() || mpos.is_empty() {
        return out;
    }
    let (mut lo, mut hi) = ([f64::INFINITY; 2], [f64::NEG_INFINITY; 2]);
    for p in mpos {
        for q in [*p, g2::add(*p, mdelta)] {
            for a in 0..2 {
                lo[a] = lo[a].min(q[a] as f64);
                hi[a] = hi[a].max(q[a] as f64);
            }
        }
    }
    let cell = super::PLAN_CELL_IN;
    let nx = ((board[0] / cell).ceil() as i64).max(1);
    let ny = ((board[1] / cell).ceil() as i64).max(1);
    let span = |v: f64, n: i64| -> i64 { ((v / cell).floor() as i64).clamp(0, n - 1) };
    let (x0, x1) = (span(lo[0] - margin_in, nx), span(hi[0] + margin_in, nx));
    let (y0, y1) = (span(lo[1] - margin_in, ny), span(hi[1] + margin_in, ny));
    for cy in y0..=y1 {
        for cx in x0..=x1 {
            let c = [((cx as f64 + 0.5) * cell) as f32, ((cy as f64 + 0.5) * cell) as f32];
            if hit(t.from_inch(c, 0.0)) {
                out.insert((cx as i32, cy as i32));
            }
        }
    }
    out
}

/// `_spacing_zones_world` :5218, already in the planner's inch frame: one circle
/// per alive model of every OTHER on-table unit. The charge target and its
/// attached heroes get a BODY-ONLY zone (no 1" buffer) — a charge may end in
/// base contact with its own target but never move through it (p.7).
fn spacing_zones(state: &State, t: &Terrain, si: usize, ci: usize, own_r_m: f64) -> Vec<Zone> {
    let member = |u: usize, host: usize| u == host || state.attached_to[u] == Some(host);
    let mut zones = Vec::new();
    for gu in 0..state.units() {
        if member(gu, si) || state.dormant[gu] || state.aircraft[gu] {
            continue;
        }
        let buffer_m = if member(gu, ci) { 0.0 } else { UNIT_SPACING_IN * IN2M };
        for m in 0..state.positions[gu].len() {
            let r = radius_of(state, Mover { unit: gu, model: m });
            zones.push(Zone {
                c: t.to_inch(pos_of(state, Mover { unit: gu, model: m })),
                r: (r + buffer_m + own_r_m) / IN2M,
            });
        }
    }
    zones
}

/// Everything one charge's plan passes need that does not change between them —
/// the two passes differ ONLY in the granted band and the avoid-difficult flag
/// (`_execute_move` :4791-4805), so those two stay arguments and the rest lives
/// here instead of in a sixteen-parameter signature.
struct Charge<'a> {
    state: &'a State,
    t: &'a Terrain,
    si: usize,
    ci: usize,
    movers: Vec<Mover>,
    /// `_positions_of(models)` :4772, world metres, in `movers` order.
    pos: Vec<V3>,
    /// `_charge_move`'s aim, already bounds-clamped.
    goal: V3,
    /// `_move_base_radius_m(_moving_models(unit))` :5195.
    own_r_m: f64,
    avoid_dang: bool,
    flying: bool,
    ignores_difficult: bool,
    /// The table's half extents in METRES.
    half: [f64; 2],
    fast_planner: bool,
    guard: i64,
}

impl Charge<'_> {
/// `_plan_positions` :6136 — one `plan_unit_step` call, inputs only.
fn build_call(&self, delta_world: V3, reach_in: f64, avoid_diff: bool) -> MoveCall {
    let (state, t, si, ci) = (self.state, self.t, self.si, self.ci);
    let (movers, own_r_m, avoid_dang) = (&self.movers, self.own_r_m, self.avoid_dang);
    let board = t.board_in();
    let mpos: Vec<V2> = movers.iter().map(|m| t.to_inch(pos_of(state, *m))).collect();
    let mdelta: V2 = [(delta_world[0] as f64 / IN2M) as f32, (delta_world[2] as f64 / IN2M) as f32];
    let radii: Vec<f64> = movers.iter().map(|m| radius_of(state, *m) / IN2M).collect();
    let (grid, avoid_cells) = terrain_cells(t, board, avoid_diff, avoid_dang);
    let margin_in = own_r_m / IN2M + terrain::CELL_IN;
    // :5296 — the fine avoid set exists only when the route avoids something.
    let avoid_fine = if avoid_diff || avoid_dang {
        fine_cells(&mpos, mdelta, board, margin_in, t, &|w| {
            (avoid_diff && terrain::base_in_terrain(w, own_r_m, t, terrain::is_difficult))
                || (avoid_dang && terrain::base_in_terrain(w, own_r_m, t, terrain::is_dangerous))
        })
    } else {
        CellSet::new()
    };
    let forbid_cells = fine_cells(&mpos, mdelta, board, margin_in, t, &|w| {
        let ty = t.type_at(w);
        ty == terrain::CONTAINER || ty == terrain::RUINS || ty == terrain::DANGEROUS
    });
    let tgt_bases: Vec<(V2, f64)> = (0..state.positions[ci].len())
        .map(|m| {
            let mv = Mover { unit: ci, model: m };
            (t.to_inch(pos_of(state, mv)), radius_of(state, mv) / IN2M)
        })
        .collect();
    let charge_slots = if tgt_bases.is_empty() {
        Vec::new()
    } else {
        super::charge::charge_contact_slots(&mpos, &radii, &tgt_bases)
    };
    MoveCall {
        unit: state.key(si).to_string(),
        act: 0,
        round: state.round,
        rung: String::new(),
        model_pos: mpos,
        delta: mdelta,
        // p.13/p.14: Flying ignores walls while moving (:6157).
        walls: if self.flying { Vec::new() } else { t.walls_in().to_vec() },
        grid,
        allow_contact: true,
        board_in: board[0],
        opts: CallOpts {
            radii,
            clearance: own_r_m / IN2M + super::CLEARANCE_EPS_IN,
            zones: spacing_zones(state, t, si, ci, own_r_m),
            avoid_cells,
            avoid_fine,
            forbid_cells,
            board_y_in: board[1],
            difficult_cap_in: if self.ignores_difficult {
                None
            } else {
                Some(DIFFICULT_MOVE_CAP_IN)
            },
            zones_rest_only: state.profile(si).special_rules.iter().any(|r| r == "Traversal"),
            charge_allowance: Some(reach_in),
            charge_goal: Some(t.to_inch(unit_centre(state, ci))),
            charge_tgt_bases: tgt_bases,
            charge_slots,
        },
        planned: Vec::new(),
        trails: Vec::new(),
        flow_order: Vec::new(),
        trace: Default::default(),
    }
}

/// `_plan_move` :5132 — the rigid delta, bounds-clamped, then the solver. A
/// zero delta short-circuits to straight (zero-length) trails, :5136.
fn plan_once(&self, reach_in: f64, avoid_diff: bool) -> (Vec<V2>, Vec<Vec<V2>>, Option<MoveCall>) {
    let (state, t) = (self.state, self.t);
    let mpos: Vec<V2> = self.movers.iter().map(|m| t.to_inch(pos_of(state, *m))).collect();
    let delta =
        clamp_delta_to_bounds(&self.pos, plan_unit_move(&self.pos, self.goal, reach_in), self.half);
    if delta == [0.0, 0.0, 0.0] {
        let trails = mpos.iter().map(|p| vec![*p, *p]).collect();
        return (mpos, trails, None);
    }
    let call = self.build_call(delta, reach_in, avoid_diff);
    match plan_unit_step_call(&call, self.fast_planner, self.guard) {
        Ok(p) => {
            // :6288-6296 — the world trail always ends where the model ends, and
            // a degenerate one-point leg becomes the straight start->end pair.
            let mut trails = p.trails;
            trails.resize(mpos.len(), Vec::new());
            for (i, leg) in trails.iter_mut().enumerate() {
                let end = p.planned.get(i).copied().unwrap_or(mpos[i]);
                if leg.last().map(|b| g2::distance_to(*b, end) * IN2M > OVERLAP_EPS_M).unwrap_or(true)
                {
                    leg.push(end);
                }
                if leg.len() < 2 {
                    *leg = vec![mpos[i], end];
                }
            }
            (p.planned, trails, Some(call))
        }
        Err(_) => (mpos.clone(), mpos.iter().map(|p| vec![*p, *p]).collect(), Some(call)),
    }
}
}

/// `SoloController._retrace_to` :6912 — THE step the arc measure lives or dies
/// on. `last_move_paths` (:5062) does not publish the solver's routed polyline;
/// it publishes the route RETRACED to the gated endpoint, i.e. trimmed to the
/// STRAIGHT-LINE displacement plus one hop to the end. So the arc
/// `last_move_remaining_in` :8659 subtracts is bounded by twice the
/// displacement, not by the bent route's length — a charge that walked 16" of
/// arc to move 9" can still have budget left for the snap. Measuring the routed
/// arc instead starves every bent charge and is what an earlier draft of this
/// rung got wrong.
fn retrace_to(route: &[V2], start: V2, gated: V2) -> Vec<V2> {
    let straight = g2::distance_to(start, gated);
    if straight * IN2M < OVERLAP_EPS_M {
        return vec![start];
    }
    if route.len() < 2 {
        return vec![start, gated];
    }
    let mut trimmed = g2::trim_polyline(route, straight);
    if trimmed.is_empty() {
        trimmed = vec![start];
    }
    if g2::distance_to(*trimmed.last().unwrap(), gated) * IN2M > OVERLAP_EPS_M {
        trimmed.push(gated);
    }
    trimmed
}

/// `_trails_cross_difficult` :5174 over `_path_crosses_terrain` :6963 — the p.11
/// cap trigger, measured on the REAL polyline with the base edge included.
fn trails_cross_difficult(trails: &[Vec<V2>], radii_m: &[f64], t: &Terrain) -> bool {
    trails
        .iter()
        .enumerate()
        .any(|(i, leg)| leg_crosses(leg, radii_m.get(i).copied().unwrap_or(0.0), t, terrain::is_difficult))
}

/// ONE trail against ONE terrain class — `_path_crosses_terrain` :6963 leg by
/// leg, at half-cell steps, with the base EDGE included (`base_in_terrain`).
pub(crate) fn leg_crosses(leg: &[V2], r: f64, t: &Terrain, class: fn(i32) -> bool) -> bool {
    let cell_m = terrain::CELL_IN * IN2M;
    for w in leg.windows(2) {
        let (a, b) = (t.from_inch(w[0], 0.0), t.from_inch(w[1], 0.0));
        let span = g2::distance_to(w[0], w[1]) * IN2M;
        let steps = ((span / (cell_m * 0.5)).ceil() as i64).max(1);
        for k in 0..=steps {
            let f = k as f64 / steps as f64;
            if terrain::base_in_terrain(geom::add(a, geom::mul(geom::sub(b, a), f)), r, t, class) {
                return true;
            }
        }
    }
    false
}

/// `SoloController._charge_move` :8582 through `_execute_move` :4769, for ONE
/// charge. `None` = the port declines and the caller keeps its rigid move: no
/// board, no models on one side, or a target with nothing left to charge.
#[allow(clippy::too_many_arguments)]
pub fn charge_move(
    state: &State,
    t: &Terrain,
    si: usize,
    ci: usize,
    band_in: f64,
    hero_attach: bool,
    fast_planner: bool,
    guard: i64,
) -> Option<Landing> {
    let board = t.board_in();
    if !t.is_valid() || board[0] <= 0.0 || board[1] <= 0.0 {
        return None;
    }
    let half = [board[0] * 0.5 * IN2M, board[1] * 0.5 * IN2M];
    // The gate's model list is `_moving_models` (:5375) on BOTH sides; without
    // the hero_attach seam the port's own model arrays are host-only and the
    // hero must stay out of the plan too, or the landing and the engage gate
    // would measure two different units (D5-4 / G4).
    let mut movers = movers_of(state, si);
    let tgt = movers_of(state, ci);
    if !hero_attach {
        movers.retain(|m| m.unit == si);
    }
    if movers.is_empty() || tgt.is_empty() {
        return None;
    }
    let pos: Vec<V3> = movers.iter().map(|m| pos_of(state, *m)).collect();
    // :8582-8596 — aim the nearest model at the target's contact BOUNDARY; the
    // degenerate case (:8586) falls back to the old aim at the target centre.
    let (gap, dir) = nearest_charge_vector(state, &movers, &tgt);
    let goal = if !gap.is_finite() || dir == [0.0, 0.0] {
        unit_centre(state, ci)
    } else {
        let travel = band_in.min(gap);
        geom::add(unit_centre(state, si), geom::mul([dir[0], 0.0, dir[1]], travel * IN2M))
    };
    let goal = clamp_to_bounds(goal, half);
    let own_r_m = state
        .charge_probe_r
        .get(si)
        .copied()
        .filter(|r| *r > 0.0)
        .unwrap_or_else(|| pos.iter().enumerate().fold(DEFAULT_BASE_RADIUS_M, |acc, (i, _)| {
            acc.max(radius_of(state, movers[i]))
        }));
    let radii_m: Vec<f64> = movers.iter().map(|m| radius_of(state, *m)).collect();
    let flying = state.profile(si).special_rules.iter().any(|r| r == "Flying");
    let ignores_difficult = state.charge_no_difficult.get(si).copied().unwrap_or(flying);
    // :4791-4797 — pass 1 routes AROUND difficult/dangerous unless the targets
    // themselves lie in it (then going around is impossible).
    let mut reach = band_in;
    let avoid_diff = !ignores_difficult
        && !targets_in(&pos, goal, reach, own_r_m, t, half, terrain::is_difficult);
    let avoid_dang = !flying && !targets_in(&pos, goal, reach, own_r_m, t, half, terrain::is_dangerous);
    let ch = Charge {
        state,
        t,
        si,
        ci,
        movers,
        pos,
        goal,
        own_r_m,
        avoid_dang,
        flying,
        ignores_difficult,
        half,
        fast_planner,
        guard,
    };
    let (mut planned, mut trails, mut call) = ch.plan_once(reach, avoid_diff);
    // :4801-4805 — the ROUTE entered difficult terrain, so p.11 caps the whole
    // move at 6" and it is re-planned THROUGH (dangerous is still avoided).
    if !ignores_difficult && trails_cross_difficult(&trails, &radii_m, t) {
        reach = band_in.min(DIFFICULT_MOVE_CAP_IN);
        let re = ch.plan_once(reach, false);
        planned = re.0;
        trails = re.1;
        call = re.2;
    }
    // :4838-4847 — distance truth: no model's polyline may exceed the budget.
    let budget_in = reach;
    let mut arc_in = 0.0f64;
    let mut dangerous: Vec<bool> = Vec::with_capacity(trails.len());
    let starts: Vec<V2> = ch.movers.iter().map(|m| t.to_inch(pos_of(state, *m))).collect();
    for (i, leg) in trails.iter_mut().enumerate() {
        if g2::polyline_length(leg) * IN2M > budget_in * IN2M + OVERLAP_EPS_M {
            *leg = g2::trim_polyline(leg, budget_in);
            if let Some(fin) = leg.last() {
                if i < planned.len() {
                    planned[i] = *fin;
                }
            }
        }
        // :5036 — the p.12 crossing flag is read HERE, on the routed trail, and
        // not after the retrace below: the table counts the cells the model
        // actually traversed even when the gate nudges its resting spot.
        dangerous.push(!flying && leg_crosses(leg, radii_m.get(i).copied().unwrap_or(0.0), t, terrain::is_dangerous));
        // :4853-4855 — and THEN the trail is retraced to the endpoint, which is
        // the polyline `last_move_paths` publishes and :8659 measures.
        *leg = retrace_to(leg, starts[i], planned.get(i).copied().unwrap_or(starts[i]));
        arc_in = arc_in.max(g2::polyline_length(leg));
    }
    let end: Vec<V3> = ch
        .movers
        .iter()
        .enumerate()
        .map(|(i, m)| {
            let p = planned.get(i).copied().unwrap_or_else(|| t.to_inch(pos_of(state, *m)));
            let w = t.from_inch(p, 0.0);
            [w[0], ch.pos[i][1], w[2]]
        })
        .collect();
    Some(Landing { movers: ch.movers.clone(), end, budget_in, arc_in, dangerous, call })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::{Bands, Mods, MoveBands, Profile, Profiles, Roster};
    use crate::terrain::{CellParams, Obb, PlainTerrain};
    use std::collections::HashMap;
    use std::rc::Rc;

    /// The smallest two-unit `State` `nearest_charge_vector`/`charge_move` can
    /// read: unit 0 (the charger) at `pos_a`, unit 1 (the target) at `pos_b`,
    /// both 1"-radius bases, no attachment, no terrain gate reads.
    fn two_unit_state(pos_a: Vec<V3>, pos_b: Vec<V3>) -> State {
        let profile = Profile {
            unit_id: "u".into(),
            name: "u".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![],
            model_count: 1,
            weapons: vec![],
            special_rules: vec![],
            caster_value: 0,
            base_radius: 0.0,
            game_system: String::new(),
            faction_folder: String::new(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let profiles = Rc::new(Profiles { list: vec![profile], index: HashMap::new() });
        let roster = Rc::new(Roster {
            keys: vec!["a".into(), "b".into()],
            index: HashMap::new(),
            profile: vec![0, 0],
        });
        let na = pos_a.len();
        let nb = pos_b.len();
        State {
            roster,
            profiles,
            round: 0,
            rounds_total: 1,
            scoring: Rc::from(""),
            objectives: vec![],
            markers_meta: vec![],
            destroy_seq: vec![],
            vp: None,
            vp_flavour: None,
            vp_memo: None,
            cast_events: vec![],
            player: vec![0, 1],
            alive: vec![1, 1],
            activated: vec![false, false],
            shaken: vec![false, false],
            fatigued: vec![false, false],
            in_cover: vec![false, false],
            aircraft: vec![false, false],
            dormant: vec![false, false],
            casts: vec![0, 0],
            morale_bonus: vec![0, 0],
            ambush_arrived_round: vec![-1, -1],
            earliest_arrival_round: vec![-1, -1],
            wound_frac: vec![1.0, 1.0],
            positions: vec![
                pos_a.iter().map(|p| geom::to_f64(*p)).collect(),
                pos_b.iter().map(|p| geom::to_f64(*p)).collect(),
            ],
            wounds: vec![vec![1; na], vec![1; nb]],
            radii: vec![vec![IN2M; na], vec![IN2M; nb]],
            mods: vec![Mods::default(), Mods::default()],
            mods_base: vec![Rc::new(Mods::default()), Rc::new(Mods::default())],
            attached: Rc::new(vec![vec![], vec![]]),
            attached_to: Rc::new(vec![None, None]),
            los: vec![None, None],
            los_pairs: None,
            bands: vec![Bands::default(), Bands::default()],
            shroud: vec![None, None],
            charge_no_difficult: vec![false, false],
            charge_probe_r: vec![0.0, 0.0],
        }
    }

    /// A 6x4 ft board with no cells and the given wall segments (world metres).
    fn board(walls: Vec<[[f64; 2]; 2]>) -> Terrain {
        Terrain::build(&PlainTerrain {
            cells: vec![],
            sandbox: Vec::<Obb>::new(),
            walls,
            cell_params: CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    /// THE conversion the two wall sources disagree about. The act header writes
    /// `get_wall_segments_world()` in WORLD METRES centred on the origin;
    /// `plan_unit_step` wants the planner's 0-origin INCH frame. A segment from
    /// the board's centre to one inch along +x therefore lands at (36, 24) and
    /// (37, 24) on a 72"x48" table — and nowhere else.
    #[test]
    fn wall_segments_cross_the_metre_to_inch_frame_exactly_once() {
        let t = board(vec![[[0.0, 0.0], [IN2M, 0.0]], [[-36.0 * IN2M, -24.0 * IN2M], [0.0, 0.0]]]);
        assert_eq!(t.board_in(), [72.0, 48.0]);
        let w = t.walls_in();
        assert_eq!(w.len(), 2);
        assert!((w[0][0][0] - 36.0).abs() < 1e-4 && (w[0][0][1] - 24.0).abs() < 1e-4, "{w:?}");
        assert!((w[0][1][0] - 37.0).abs() < 1e-4 && (w[0][1][1] - 24.0).abs() < 1e-4, "{w:?}");
        // The board's corner is the frame's origin.
        assert!(w[1][0][0].abs() < 1e-3 && w[1][0][1].abs() < 1e-3, "{w:?}");
        // A board with no `walls` key has none — and that is NOT "no ruins".
        assert!(board(vec![]).walls_in().is_empty());
    }

    /// A 6x4 ft board with ONE painted DANGEROUS cell at the origin. `type_at`
    /// indexes `floor(x / cell_m + half_grid)`, and a 72"x48" table's grid is 30
    /// cells wide, so the cell holding world (0, 0) is (15, 15).
    fn dangerous_board() -> Terrain {
        Terrain::build(&PlainTerrain {
            cells: vec![[15.0, 15.0, terrain::DANGEROUS as f64]],
            sandbox: Vec::<Obb>::new(),
            walls: vec![],
            cell_params: CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    /// The p.12 trigger's CROSSING half, on the real polyline — `_path_crosses_
    /// terrain` :6963 with the base edge included. GREEN: a leg that walks over
    /// the painted cell is a crossing. RED: the same leg 12" to the side is not,
    /// so the flag is reading the board and not returning true on principle.
    #[test]
    fn a_trail_over_a_dangerous_cell_is_a_crossing_and_one_beside_it_is_not() {
        let t = dangerous_board();
        // The board's inch frame is 0-origin, so the painted centre cell is (36, 24).
        let over: Vec<V2> = vec![[30.0, 24.0], [42.0, 24.0]];
        let beside: Vec<V2> = vec![[30.0, 12.0], [42.0, 12.0]];
        assert!(leg_crosses(&over, 0.0, &t, terrain::is_dangerous));
        assert!(!leg_crosses(&beside, 0.0, &t, terrain::is_dangerous));
        // Edge-aware (`base_in_terrain`): the painted cell spans 36..39" x 24..27",
        // so a leg half an inch short of its edge is a crossing for a 1" base...
        let short = vec![[30.0, 23.5], [42.0, 23.5]];
        assert!(leg_crosses(&short, IN2M, &t, terrain::is_dangerous));
        // ...and the same leg for a POINT (radius 0) is not.
        assert!(!leg_crosses(&short, 0.0, &t, terrain::is_dangerous));
    }

    /// `_execute_move` :5033-5047 — WHAT the test rolls. THE FIXTURE the brief
    /// asks for: a 3-model unit whose route crossed one dangerous cell draws 3
    /// dice, and a Tough(3) model draws 3 on its own.
    #[test]
    fn the_dangerous_test_rolls_one_die_per_tough_point_of_every_affected_model() {
        use crate::sim::{dangerous_dice, dangerous_wounds};
        use crate::unit::UnitStatic;
        let t = dangerous_board();
        // Three models parked 12" off the painted cell — nobody is STANDING in it,
        // so every die below has to come from the route.
        let away = [0.0f32, 0.0, 12.0 * IN2M as f32];
        let st = two_unit_state(vec![away, away, away], vec![[1.0, 0.0, 0.0]]);
        let movers: Vec<Mover> = (0..3).map(|model| Mover { unit: 0, model }).collect();
        let land = |dang: Vec<bool>| Landing {
            movers: movers.clone(),
            end: vec![away; 3],
            budget_in: 6.0,
            arc_in: 0.0,
            dangerous: dang,
            call: None,
        };
        let tough1 = vec![UnitStatic { wounds_max: vec![1, 1, 1], ..Default::default() }];
        let mut shot = crate::dice::ShootResult::default();
        let seams = crate::io::Seams::default();
        let call = |statics: &[UnitStatic], l: &Landing, shot: &mut crate::dice::ShootResult| {
            dangerous_dice(statics, &st, &st, 0, seams, Some(l), crate::sim::Cover::Board(&t), shot)
        };
        // Tough(1) x 3, all three routes crossing: three dice.
        assert_eq!(call(&tough1, &land(vec![true, true, true]), &mut shot), 3);
        // One model crossed: one die. The count is per MODEL, not per unit.
        assert_eq!(call(&tough1, &land(vec![true, false, false]), &mut shot), 1);
        // RED: nobody crossed and nobody stands in it — no test at all.
        assert_eq!(call(&tough1, &land(vec![false, false, false]), &mut shot), 0);
        // Tough(3) weighting (p.12 "as many dice as Tough"): one crossing model
        // with 3 wounds rolls 3, which is `maxi(1, wounds_max)` and not `1`.
        let tough3 = vec![UnitStatic { wounds_max: vec![3, 3, 3], ..Default::default() }];
        assert_eq!(call(&tough3, &land(vec![true, false, false]), &mut shot), 3);
        // A profile that carries no per-model list still rolls the floor of one.
        let bare = vec![UnitStatic::default()];
        assert_eq!(call(&bare, &land(vec![true, true, false]), &mut shot), 2);
        // And the wound rule is the ONE, not the target: 6 is what the tray shows.
        assert_eq!(dangerous_wounds(&[1, 6, 3, 1]), 2);
        assert_ne!(dangerous_wounds(&[6, 6, 6]), 3, "counting 6s is the RED reading");
    }

    /// `_retrace_to` :6912 is the whole arc measure, so it gets its own red-green.
    /// GREEN: a route that walks 3" of arc to displace 1" is republished trimmed
    /// to that 1" plus ONE hop to the endpoint — strictly shorter than the route,
    /// which is why a bent charge can still have budget left for its snap.
    /// RED: measuring the polyline the solver returned instead reads the full 3",
    /// and that is NOT the number `last_move_remaining_in` subtracts.
    #[test]
    fn the_retrace_republishes_a_shorter_trail_than_the_route_it_walked() {
        let route: Vec<V2> = vec![[0.0, 0.0], [0.0, 1.0], [1.0, 1.0], [1.0, 0.0]];
        assert!((g2::polyline_length(&route) - 3.0).abs() < 1e-6, "the RED reading");
        let out = retrace_to(&route, [0.0, 0.0], [1.0, 0.0]);
        let arc = g2::polyline_length(&out);
        assert!(arc < 3.0 - 0.5, "the retraced trail is shorter than the route: {arc}");
        assert!(arc >= 1.0, "and never shorter than the straight line: {arc}");
        assert_eq!(*out.last().unwrap(), [1.0, 0.0], "it ends where the model ends");
        // A straight route is republished unchanged, hop and all.
        let straight: Vec<V2> = vec![[0.0, 0.0], [4.0, 0.0]];
        assert!((g2::polyline_length(&retrace_to(&straight, [0.0, 0.0], [4.0, 0.0])) - 4.0).abs()
            < 1e-6);
        // A model that did not move publishes no glide at all (:6914).
        assert_eq!(retrace_to(&route, [0.0, 0.0], [0.0, 0.0]), vec![[0.0, 0.0]]);
    }

    /// `nearest_charge_vector` :8550 — the smallest BASE-EDGE gap and the unit
    /// direction from that charger model toward that target model. Two 1"-radius
    /// bases 10" apart centre to centre are 8" apart edge to edge, and the
    /// direction points from the charger straight at the target.
    #[test]
    fn the_charge_aim_measures_base_edges_and_points_at_the_nearest_pair() {
        let a: V3 = [0.0, 0.0, 0.0];
        let b: V3 = [10.0 * IN2M as f32, 0.0, 0.0];
        let flat: V3 = [a[0] - b[0], 0.0, a[2] - b[2]];
        let want_gap = (geom::length(flat) as f64 - IN2M - IN2M) / IN2M;
        let state = two_unit_state(vec![a], vec![b]);
        let from = [Mover { unit: 0, model: 0 }];
        let to = [Mover { unit: 1, model: 0 }];
        let (gap, dir) = nearest_charge_vector(&state, &from, &to);
        assert!((gap - want_gap).abs() < 1e-6, "{gap} vs {want_gap}");
        assert!((gap - 8.0).abs() < 1e-4, "{gap}");
        assert!((dir[0] - 1.0).abs() < 1e-6 && dir[1].abs() < 1e-6, "{dir:?}");
    }

    /// `_clamp_delta_to_bounds` :8886 — a move that would carry a model off the
    /// table is scaled back for the WHOLE unit, not clipped per model.
    #[test]
    fn the_bounds_clamp_scales_the_whole_unit_back_onto_the_table() {
        let half = [36.0 * IN2M, 24.0 * IN2M];
        let pos: Vec<V3> = vec![[0.0, 0.0, 0.0], [(30.0 * IN2M) as f32, 0.0, 0.0]];
        let want: V3 = [(10.0 * IN2M) as f32, 0.0, 0.0];
        let got = clamp_delta_to_bounds(&pos, want, half);
        // The second model may only reach 36" less the 0.02 m margin.
        assert!(got[0] < want[0], "the delta shrank: {got:?}");
        assert!((pos[1][0] + got[0]) as f64 <= half[0] - BOUNDS_MARGIN_M + 1e-6, "{got:?}");
        // A move that stays on the table is untouched.
        let small: V3 = [(0.5 * IN2M) as f32, 0.0, 0.0];
        assert_eq!(clamp_delta_to_bounds(&pos, small, half), small);
    }

    /// The decline path: no board, no charge move — the caller keeps its rigid
    /// translation rather than planning on a table that does not exist.
    #[test]
    fn a_charge_declines_without_a_board() {
        assert_eq!(Terrain::absent().board_in(), [0.0, 0.0]);
        let state = two_unit_state(vec![[0.0, 0.0, 0.0]], vec![[5.0 * IN2M as f32, 0.0, 0.0]]);
        let land = charge_move(
            &state,
            &Terrain::absent(),
            0,
            1,
            12.0,
            false,
            true,
            crate::mv::FAST_PLANNER_GUARD,
        );
        assert!(land.is_none(), "no board, no charge move: {land:?}");
    }
}
