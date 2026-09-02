//! NML-1073 — the MOVE as the TABLE executes it, over a `State`: `charge_move`
//! (M5 D5-2, aimed at a target's near face) and `plain_move` (aimed at a
//! destination the caller picked), both through the one `_execute_move` body.
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

use std::sync::atomic::{AtomicBool, Ordering};

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
/// `SoloController.GATE_SLACK_EPS_IN` :159 — the packed-contact epsilon every
/// gate displacement budget carries on top of its band slack.
const GATE_SLACK_EPS_IN: f64 = 0.05;

/// Test-only knob: forces the S6 gate-collapse ladder below off (RED proof).
pub static LADDER_DISABLED: AtomicBool = AtomicBool::new(false);

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
        let sc = state.base_shape(cm.unit);
        for em in to {
            let e = pos_of(state, *em);
            // D5-2b: :8573 asks `SeparationChecker.edge_distance`, i.e. the base
            // SHAPE. The circumscribing circle read an oval target 0.4-1.4"
            // closer than the table did, and `travel = min(band, gap)` below
            // aimed the whole charge that much short. Round bases delegate to
            // the arithmetic this line always ran.
            let gap =
                geom::pair_gap_m(c, rc, sc, e, radius_of(state, *em), state.base_shape(em.unit))
                    / IN2M;
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

/// `_spacing_zones_world` :5232, already in the planner's inch frame: one circle
/// per alive model of every OTHER on-table unit. The charge target and its
/// attached heroes get a BODY-ONLY zone (no 1" buffer) — a charge may end in
/// base contact with its own target but never move through it (p.7). A
/// non-charge move passes `None` (:6187 hands the planner `charge_target if
/// allow_contact else null`) and every unit keeps its full 1" buffer.
fn spacing_zones(
    state: &State,
    t: &Terrain,
    si: usize,
    ci: Option<usize>,
    own_r_m: f64,
) -> Vec<Zone> {
    let member = |u: usize, host: usize| u == host || state.attached_to[u] == Some(host);
    let mut zones = Vec::new();
    for gu in 0..state.units() {
        if member(gu, si) || state.dormant[gu] || state.aircraft[gu] {
            continue;
        }
        let buffer_m =
            if ci.is_some_and(|c| member(gu, c)) { 0.0 } else { UNIT_SPACING_IN * IN2M };
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

/// Everything one move's plan passes need that does not change between them —
/// the two passes differ ONLY in the granted band and the avoid-difficult flag
/// (`_execute_move` :4791-4805), so those two stay arguments and the rest lives
/// here instead of in a sixteen-parameter signature. `plan_once` (below) reads
/// none of this as charge-specific, so a future non-charge caller builds one of
/// these too — only `allow_contact` tells `build_call` which move it is.
struct Move<'a> {
    state: &'a State,
    t: &'a Terrain,
    si: usize,
    /// The charge target — `None` for a non-charge move, which has none
    /// (`_execute_move`'s `charge_target` argument defaults to `null`, :4785).
    ci: Option<usize>,
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
    /// A charge may end in base contact with `ci`'s target (p.7); a non-charge
    /// move may not (`MoveCall.allow_contact`, io.rs:339). Charge = true.
    allow_contact: bool,
}

impl Move<'_> {
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
    let tgt_bases: Vec<(V2, f64)> = ci.map_or_else(Vec::new, |c| {
        (0..state.positions[c].len())
            .map(|m| {
                let mv = Mover { unit: c, model: m };
                (t.to_inch(pos_of(state, mv)), radius_of(state, mv) / IN2M)
            })
            .collect()
    });
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
        allow_contact: self.allow_contact,
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
            // :6222 — the arc allowance and the body goal are CHARGE-only; a
            // plain move sends neither, so `allowance()` falls back to the
            // straight delta length (io.rs:512).
            charge_allowance: ci.map(|_| reach_in),
            charge_goal: ci.map(|c| t.to_inch(unit_centre(state, c))),
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

/// `_gate_disp_caps_m` :6343, in INCHES: how far the gate may still displace
/// each model past its planned endpoint before the RETRACED trail (which
/// appends the correction) would exceed the model's legal band. Budget = the
/// granted reach, p.11-capped for a model whose OWN leg entered difficult
/// terrain; slack = budget minus the walked arc, plus the packed-contact
/// epsilon a full-band mover in a deploy-packed line always needs.
fn gate_caps(&self, trails: &[Vec<V2>], radii_m: &[f64], reach_in: f64) -> Vec<f64> {
    trails
        .iter()
        .enumerate()
        .map(|(i, leg)| {
            let r = radii_m.get(i).copied().unwrap_or(0.0);
            let mut budget = reach_in;
            if !self.ignores_difficult && leg_crosses(leg, r, self.t, terrain::is_difficult) {
                budget = budget.min(DIFFICULT_MOVE_CAP_IN);
            }
            (budget - g2::polyline_length(leg)).max(0.0) + GATE_SLACK_EPS_IN
        })
        .collect()
}

/// `_external_obstacle_shapes` :6676 — every OTHER on-table unit's alive-model
/// base, in the planner's inch frame. Excluded exactly as the GDScript does it:
/// the moving unit and its attached heroes (coherency owns their spacing), any
/// Ambush reserve (off table) and any Aircraft (its base blocks nothing).
fn external_discs(&self) -> Vec<super::gate::Disc> {
    let state = self.state;
    let member = |u: usize| u == self.si || state.attached_to[u] == Some(self.si);
    let mut out = Vec::new();
    for gu in 0..state.units() {
        if member(gu) || state.dormant[gu] || state.aircraft[gu] {
            continue;
        }
        for model in 0..state.positions[gu].len() {
            let mv = Mover { unit: gu, model };
            let c = self.t.to_inch(pos_of(state, mv));
            out.push(super::gate::Disc {
                c: [c[0] as f64, c[1] as f64],
                r: radius_of(state, mv) / IN2M,
            });
        }
    }
    out
}

/// `_execute_move` :4813-4855 from the pass-1 plan onward — the p.11 cap
/// re-plan, the distance-truth trim, the p.12 crossing flags and the retrace.
/// The table runs ONE body here for a charge and for a plain move; everything
/// the two disagree about was already decided when `Move` was built, so the
/// two entries below must not each carry their own copy of this ordering.
fn execute(&self, band_in: f64, avoid_diff: bool, radii_m: &[f64]) -> Landing {
    let (state, t) = (self.state, self.t);
    let mut reach = band_in;
    let (mut planned, mut trails, mut call) = self.plan_once(reach, avoid_diff);
    // :4816-4820 — the ROUTE entered difficult terrain, so p.11 caps the whole
    // move at 6" and it is re-planned THROUGH (dangerous is still avoided).
    if !self.ignores_difficult && trails_cross_difficult(&trails, radii_m, t) {
        reach = band_in.min(DIFFICULT_MOVE_CAP_IN);
        let re = self.plan_once(reach, false);
        planned = re.0;
        trails = re.1;
        call = re.2;
    }
    // :4838-4847 — distance truth: no model's polyline may exceed the budget.
    let mut budget_in = reach; // `mut`: the ladder below may shorten it (:5075).
    let mut arc_in = 0.0f64;
    let mut dangerous: Vec<bool> = Vec::with_capacity(trails.len());
    let starts: Vec<V2> = self.movers.iter().map(|m| t.to_inch(pos_of(state, *m))).collect();
    for (i, leg) in trails.iter_mut().enumerate() {
        if g2::polyline_length(leg) * IN2M > budget_in * IN2M + OVERLAP_EPS_M {
            *leg = g2::trim_polyline(leg, budget_in);
            if let Some(fin) = leg.last() {
                if i < planned.len() {
                    planned[i] = *fin;
                }
            }
        }
        // :5051 — the p.12 crossing flag is read HERE, on the routed trail, and
        // not after the retrace below: the table counts the cells the model
        // actually traversed even when the gate nudges its resting spot.
        let r = radii_m.get(i).copied().unwrap_or(0.0);
        dangerous.push(!self.flying && leg_crosses(leg, r, t, terrain::is_dangerous));
    }
    // :4858-4866 — nothing actually moved: the table returns BEFORE the gate,
    // so a unit already stacked where it stands is not re-arranged for free.
    let stirred = planned
        .iter()
        .enumerate()
        .any(|(i, p)| g2::distance_to(*p, starts[i]) as f64 * IN2M > OVERLAP_EPS_M);
    // :4884-4885 — THE HARD FINAL PLACEMENT GATE, applied HERE, after the trim,
    // so the trim can never cut a gate-corrected endpoint off its trail. Only
    // passes 1-3 are ported (`mv::gate`). A CHARGE is deliberately left out of
    // this call even though the table gates one too: its gate is a different
    // animal — no band caps (the contact push owns the endpoint), the
    // contact-model exemption, `_clamp_gate_walls` on top — and none of that is
    // written yet. S5c widens this call; it does not move it.
    if !self.allow_contact && stirred {
        let planned_in = achieved_in(&starts, &planned);
        let radii_in: Vec<f64> = radii_m.iter().map(|r| r / IN2M).collect();
        let ext = self.external_discs();
        let caps = self.gate_caps(&trails, radii_m, budget_in);
        let (fixed, _rep) = super::gate::finalize_placement(
            &planned,
            &radii_in,
            &ext,
            &caps,
            t.board_in(),
            Some(t),
        );
        planned = fixed;
        // :4890-4931 GATE-COLLAPSE LADDER (S6): re-plan shorter when the gate
        // nearly erased pass 1 (`rescue_should_fire`); a coherent rung always
        // beats a torn one, and more distance wins within a class.
        let mut best_ach = achieved_in(&starts, &planned);
        let mut best_coherent = config_coherent(&planned, &radii_in);
        let start_coherent = config_coherent(&starts, &radii_in);
        let goal_gap_in = g2::distance_to(super::centroid(&starts), t.to_inch(self.goal));
        if !LADDER_DISABLED.load(Ordering::Relaxed)
            && rescue_should_fire(
                best_ach, planned_in, best_coherent, start_coherent, goal_gap_in, budget_in,
            )
        {
            let (mut best_pos, mut best_trails) = (planned.clone(), trails.clone());
            let (mut best_reach, mut best_call) = (budget_in, call.clone());
            for frac in [0.75, 0.5, 0.25] {
                let r3 = budget_in * frac;
                let (mut p3, mut t3, c3) = self.plan_once(r3, avoid_diff);
                for (i, leg) in t3.iter_mut().enumerate() {
                    if g2::polyline_length(leg) * IN2M > r3 * IN2M + OVERLAP_EPS_M {
                        *leg = g2::trim_polyline(leg, r3);
                        if let Some(fin) = leg.last() {
                            if i < p3.len() {
                                p3[i] = *fin;
                            }
                        }
                    }
                }
                let caps3 = self.gate_caps(&t3, radii_m, r3);
                let (p3, _rep3) =
                    super::gate::finalize_placement(&p3, &radii_in, &ext, &caps3, t.board_in(), Some(t));
                let a3 = achieved_in(&starts, &p3);
                let c3ok = config_coherent(&p3, &radii_in);
                // Lexicographic tie-break, same as the table: coherent beats
                // torn at ANY displacement; within a class more distance wins.
                if (c3ok && !best_coherent) || (c3ok == best_coherent && a3 > best_ach + 0.005 / IN2M)
                {
                    (best_pos, best_trails, best_reach) = (p3, t3, r3);
                    (best_call, best_ach, best_coherent) = (c3, a3, c3ok);
                }
                if a3 >= r3 * 0.75 && c3ok {
                    break;
                }
            }
            (planned, trails, budget_in, call) = (best_pos, best_trails, best_reach, best_call);
        }
    }
    for (i, leg) in trails.iter_mut().enumerate() {
        // :5068-5071 — and THEN the trail is retraced to the endpoint, which is
        // the polyline `last_move_paths` publishes and :8659 measures.
        *leg = retrace_to(leg, starts[i], planned.get(i).copied().unwrap_or(starts[i]));
        arc_in = arc_in.max(g2::polyline_length(leg));
    }
    let end: Vec<V3> = self
        .movers
        .iter()
        .enumerate()
        .map(|(i, m)| {
            let p = planned.get(i).copied().unwrap_or_else(|| t.to_inch(pos_of(state, *m)));
            let w = t.from_inch(p, 0.0);
            [w[0], self.pos[i][1], w[2]]
        })
        .collect();
    Landing { movers: self.movers.clone(), end, budget_in, arc_in, dangerous, call }
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

/// `_achieved_m` :5140 — centroid displacement, kept in INCHES like the rest
/// of this file (only the caller's absolute thresholds convert from metres).
fn achieved_in(before: &[V2], after: &[V2]) -> f64 {
    g2::distance_to(super::centroid(before), super::centroid(after))
}

/// `_config_coherent_world` :6832 — one 1"-link component spanning every
/// model (`components_r`, the same truth as the table's BFS-from-model-0)
/// AND every pair within `MAX_CHAIN_IN` (9", no Skirmish variant here).
fn config_coherent(pos: &[V2], radii_in: &[f64]) -> bool {
    pos.len() <= 1
        || (super::components_r(pos, radii_in).len() == 1
            && super::max_edge_spread_r(pos, radii_in) <= super::MAX_CHAIN_IN)
}

/// `rescue_should_fire` :1526 — collapse, a self-inflicted tear, or a
/// committed distant move that lost over 20% of its plan to the gate.
fn rescue_should_fire(
    ach_in: f64,
    planned_in: f64,
    post_coherent: bool,
    start_coherent: bool,
    goal_gap_in: f64,
    reach_in: f64,
) -> bool {
    if planned_in <= 0.01 / IN2M {
        return false;
    }
    if ach_in < planned_in * 0.25 || (!post_coherent && start_coherent) {
        return true;
    }
    ach_in < planned_in * 0.8 && goal_gap_in > reach_in
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
    let avoid_diff = !ignores_difficult
        && !targets_in(&pos, goal, band_in, own_r_m, t, half, terrain::is_difficult);
    let avoid_dang =
        !flying && !targets_in(&pos, goal, band_in, own_r_m, t, half, terrain::is_dangerous);
    let ch = Move {
        state,
        t,
        si,
        ci: Some(ci),
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
        allow_contact: true,
    };
    Some(ch.execute(band_in, avoid_diff, &radii_m))
}

/// `SoloController._move_toward` :4575 -> `_execute_move` :4784 for a NON-charge
/// move (ADVANCE, RUSH, the post-melee consolidation, Hit & Run's step): the
/// same two passes and the same distance truth as a charge, aimed at a
/// destination the caller already picked instead of at a target's near face.
/// `None` = the port declines and the caller keeps its rigid translation.
///
/// NOT here, and the landing is therefore the PRE-GATE plan rather than the
/// table's resting place: `_finalize_placement` :6371, the stall escalation
/// :4820, the gate-collapse ladder :4890 and the boxed/sidestep escape :4960.
/// A plain move really does enter all four on the table — unlike a charge,
/// which `not allow_contact` excludes from three of them.
#[allow(clippy::too_many_arguments)]
pub fn plain_move(
    state: &State,
    t: &Terrain,
    si: usize,
    dest: V3,
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
    let mut movers = movers_of(state, si);
    if !hero_attach {
        movers.retain(|m| m.unit == si);
    }
    if movers.is_empty() {
        return None;
    }
    let pos: Vec<V3> = movers.iter().map(|m| pos_of(state, *m)).collect();
    // :4579 / :4766 — every caller hands `_execute_move` a bounds-clamped goal.
    let goal = clamp_to_bounds(dest, half);
    // `_move_base_radius_m` :5209 — the LARGEST moving base is the clearance.
    let own_r_m =
        movers.iter().fold(DEFAULT_BASE_RADIUS_M, |acc, m| acc.max(radius_of(state, *m)));
    let radii_m: Vec<f64> = movers.iter().map(|m| radius_of(state, *m)).collect();
    let rules = &state.profile(si).special_rules;
    let flying = rules.iter().any(|r| r == "Flying");
    // :4790 — Strider ignores Difficult but NOT Dangerous (p.13/p.14).
    let ignores_difficult = flying || rules.iter().any(|r| r == "Strider");
    // :4805-4809 — pass 1 routes AROUND both classes unless the rigid targets
    // land in them, in which case going around is impossible.
    let avoid_diff = !ignores_difficult
        && !targets_in(&pos, goal, band_in, own_r_m, t, half, terrain::is_difficult);
    let avoid_dang =
        !flying && !targets_in(&pos, goal, band_in, own_r_m, t, half, terrain::is_dangerous);
    let mv = Move {
        state,
        t,
        si,
        ci: None,
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
        allow_contact: false,
    };
    Some(mv.execute(band_in, avoid_diff, &radii_m))
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
        let radii = vec![vec![IN2M; pos_a.len()], vec![IN2M; pos_b.len()]];
        units_state(vec![pos_a, pos_b], radii, vec![vec![], vec![]])
    }

    /// The same `State`, with as many units as the caller needs and a real base
    /// radius (METRES) per model — what a recorded call has to be rebuilt from.
    /// `attached[u]` lists the hero units riding with `u`.
    fn units_state(
        pos: Vec<Vec<V3>>,
        radii_m: Vec<Vec<f64>>,
        attached: Vec<Vec<usize>>,
    ) -> State {
        let n = pos.len();
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
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: String::new(),
            faction_folder: String::new(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let profiles = Rc::new(Profiles { list: vec![profile], index: HashMap::new() });
        let roster = Rc::new(Roster {
            keys: (0..n).map(|i| format!("u{i}")).collect(),
            index: HashMap::new(),
            profile: vec![0; n],
        });
        let mut attached_to = vec![None; n];
        for (host, hs) in attached.iter().enumerate() {
            for &h in hs {
                attached_to[h] = Some(host);
            }
        }
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
            player: (0..n).map(|i| i as i64).collect(),
            alive: vec![1; n],
            activated: vec![false; n],
            shaken: vec![false; n],
            fatigued: vec![false; n],
            in_cover: vec![false; n],
            aircraft: vec![false; n],
            dormant: vec![false; n],
            casts: vec![0; n],
            morale_bonus: vec![0; n],
            ambush_arrived_round: vec![-1; n],
            earliest_arrival_round: vec![-1; n],
            wound_frac: vec![1.0; n],
            wounds: pos.iter().map(|u| vec![1; u.len()]).collect(),
            positions: pos
                .iter()
                .map(|u| u.iter().map(|p| geom::to_f64(*p)).collect())
                .collect(),
            radii: radii_m,
            mods: vec![Mods::default(); n],
            mods_base: (0..n).map(|_| Rc::new(Mods::default())).collect(),
            attached: Rc::new(attached),
            attached_to: Rc::new(attached_to),
            los: vec![None; n],
            los_pairs: None,
            bands: vec![Bands::default(); n],
            shroud: vec![None; n],
            charge_no_difficult: vec![false; n],
            charge_probe_r: vec![0.0; n],
            buffs: (0..n).map(|_| Vec::new()).collect(),
            vs_mark_round: vec![-1; n],
            hit_and_run_round: vec![-1; n],
            growth_markers: vec![0; n],
            growth_round: vec![-1; n],
            second_wind_used: vec![false; n],
            second_wind_round: -1,
            second_wind_uses: 0,
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

    /// ONE recorded non-charge activation from the reference corpus, rebuilt
    /// from its inputs: the moving unit (3 models plus one attached hero), the
    /// 84 spacing zones the table saw, the board's cells and its ruin walls.
    /// The recorder wrote TWO `plan_unit_step` calls for it and no more — pass 1
    /// at the full 12" band routing AROUND difficult terrain, then the p.11
    /// re-plan at 6" going THROUGH it. So the act isolates the cap branch: no
    /// stall escalation ran (a third call would have been recorded) and every
    /// capped route fits inside the 6" budget, which makes the distance-truth
    /// trim a no-op here and lets the recorded plan BE the landing.
    ///
    /// RED: delete the cap branch in `Move::execute` and `plain_move` keeps
    /// pass 1, whose endpoints the last assertion measures at 8.56" from the
    /// recorded ones — 171 times the 0.05" this asserts within.
    #[test]
    fn the_p11_cap_replan_lands_the_recorded_plain_move() {
        use serde_json::Value;
        let raw = std::fs::read_to_string(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/fixtures/mv_plain_move_call.json"
        ))
        .expect("the recorded call");
        let fx: Value = serde_json::from_str(&raw).expect("valid JSON");
        let f = |v: &Value| v.as_f64().expect("number");
        let v2 = |v: &Value| -> V2 { [f(&v[0]) as f32, f(&v[1]) as f32] };
        let arr = |v: &Value| v.as_array().expect("array").clone();

        let tr = &fx["terrain"];
        let cp = &tr["cell_params"];
        let t = Terrain::build(&PlainTerrain {
            cells: arr(&tr["cells"]).iter().map(|c| [f(&c[0]), f(&c[1]), f(&c[2])]).collect(),
            sandbox: Vec::<Obb>::new(),
            walls: arr(&tr["walls"])
                .iter()
                .map(|w| [[f(&w[0][0]), f(&w[0][1])], [f(&w[1][0]), f(&w[1][1])]])
                .collect(),
            cell_params: CellParams {
                table_size_feet: [f(&cp["table_size_feet"][0]), f(&cp["table_size_feet"][1])],
                grid_rotation_degrees: f(&cp["grid_rotation_degrees"]),
                grid_size_inches: f(&cp["grid_size_inches"]),
                inches_to_meters: f(&cp["inches_to_meters"]),
            },
        });

        // `_moving_models` :5375 lists the unit's own models first and the
        // attached hero's last, and the hero here is the one 40 mm base.
        let mradii = arr(&fx["radii_in"]);
        let world: Vec<V3> =
            arr(&fx["model_pos_in"]).iter().map(|p| t.from_inch(v2(p), 0.0)).collect();
        let h = world.len() - 1;
        let others = arr(&fx["others"]);
        let state = units_state(
            vec![
                world[..h].to_vec(),
                vec![world[h]],
                others.iter().map(|o| t.from_inch(v2(&o["c"]), 0.0)).collect(),
            ],
            vec![
                mradii[..h].iter().map(|r| f(r) * IN2M).collect(),
                vec![f(&mradii[h]) * IN2M],
                others.iter().map(|o| f(&o["r_in"]) * IN2M).collect(),
            ],
            vec![vec![1], vec![], vec![]],
        );

        let land = plain_move(
            &state,
            &t,
            0,
            t.from_inch(v2(&fx["goal_in"]), 0.0),
            f(&fx["band_in"]),
            true,
            true,
            crate::mv::FAST_PLANNER_GUARD,
        )
        .expect("the board is real and the unit has models");

        // The band it kept is the CAPPED one: 6", not the granted 12".
        assert!((land.budget_in - f(&fx["budget_in"])).abs() < 1e-9, "{}", land.budget_in);
        // And it is a plain move, so the call carries no charge arc allowance.
        let call = land.call.as_ref().expect("a call was made");
        assert!(!call.allow_contact && call.opts.charge_allowance.is_none());
        assert!(call.opts.charge_goal.is_none() && call.opts.charge_slots.is_empty());

        let want: Vec<V2> = arr(&fx["planned_capped_in"]).iter().map(v2).collect();
        let pass1: Vec<V2> = arr(&fx["planned_pass1_in"]).iter().map(v2).collect();
        assert_eq!(land.end.len(), want.len());
        let worst = want.iter().enumerate().fold(0.0f64, |a, (i, w)| {
            a.max(g2::distance_to(t.to_inch(land.end[i]), *w) as f64)
        });
        assert!(worst < 0.05, "landing {worst}\" off the recorded plan");
        // The tolerance has teeth: the UNCAPPED plan is nowhere near it.
        let gap = want
            .iter()
            .zip(&pass1)
            .fold(0.0f64, |a, (w, p)| a.max(g2::distance_to(*w, *p)));
        assert!(gap > 0.05 * 20.0, "pass 1 only {gap}\" away — the fixture proves nothing");
    }

    /// ONE recorded RUSH from the reference corpus (`Hive Swarms` + its
    /// attached hero, 12" band) whose recorded reach COLLAPSED 12 -> 9 -> 6 ->
    /// 3": the full-band gate left the unit almost where it started, and only
    /// the smallest rung found a legal, coherent end state. `others` is the
    /// 61 spacing discs the move actually reads, reconstructed from the same
    /// call `Move::build_call` itself produces (so this fixture needs no
    /// terrain-frame reasoning beyond `others`' own inch-frame centres).
    ///
    /// RED: with `LADDER_DISABLED` forced on, `plain_move` keeps pass 1's own
    /// post-gate result, which the last assertion measures far outside the
    /// 0.05" bar every model lands within once the ladder runs.
    #[test]
    fn the_gate_collapse_ladder_lands_the_recorded_rush() {
        use serde_json::Value;
        let raw = std::fs::read_to_string(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/tests/fixtures/mv_ladder_move_call.json"
        ))
        .expect("the recorded call");
        let fx: Value = serde_json::from_str(&raw).expect("valid JSON");
        let f = |v: &Value| v.as_f64().expect("number");
        let v2 = |v: &Value| -> V2 { [f(&v[0]) as f32, f(&v[1]) as f32] };
        let v3 = |v: &Value| -> V3 { [f(&v[0]) as f32, 0.0, f(&v[2]) as f32] };
        let arr = |v: &Value| v.as_array().expect("array").clone();

        let tr = &fx["terrain"];
        let cp = &tr["cell_params"];
        let t = Terrain::build(&PlainTerrain {
            cells: arr(&tr["cells"]).iter().map(|c| [f(&c[0]), f(&c[1]), f(&c[2])]).collect(),
            sandbox: Vec::<Obb>::new(),
            walls: arr(&tr["walls"])
                .iter()
                .map(|w| [[f(&w[0][0]), f(&w[0][1])], [f(&w[1][0]), f(&w[1][1])]])
                .collect(),
            cell_params: CellParams {
                table_size_feet: [f(&cp["table_size_feet"][0]), f(&cp["table_size_feet"][1])],
                grid_rotation_degrees: f(&cp["grid_rotation_degrees"]),
                grid_size_inches: f(&cp["grid_size_inches"]),
                inches_to_meters: f(&cp["inches_to_meters"]),
            },
        });

        let mradii = arr(&fx["radii_in"]);
        let world: Vec<V3> = arr(&fx["model_pos_world"]).iter().map(v3).collect();
        let h = world.len() - 1;
        let others = arr(&fx["others"]);
        let mut state = units_state(
            vec![
                world[..h].to_vec(),
                vec![world[h]],
                others.iter().map(|o| t.from_inch(v2(&o["c"]), 0.0)).collect(),
            ],
            vec![
                mradii[..h].iter().map(|r| f(r) * IN2M).collect(),
                vec![f(&mradii[h]) * IN2M],
                others.iter().map(|o| f(&o["r_in"]) * IN2M).collect(),
            ],
            vec![vec![1], vec![], vec![]],
        );
        // `Hive Swarms`' own profile carries Strider (ignores the p.11 cap,
        // GF/AoF v3.5.1 p.13) — without it this fixture's route crosses
        // difficult terrain the real unit was exempt from.
        Rc::get_mut(&mut state.profiles).unwrap().list[0].special_rules = vec!["Strider".into()];
        let dest = v3(&fx["dest_world"]);
        let band = f(&fx["band_in"]);
        let want: Vec<V3> = arr(&fx["final_world"]).iter().map(v3).collect();

        let land = plain_move(&state, &t, 0, dest, band, true, true, crate::mv::FAST_PLANNER_GUARD)
            .expect("the board is real and the unit has models");
        assert!((land.budget_in - f(&fx["budget_in"])).abs() < 1e-6, "{}", land.budget_in);
        let worst = want.iter().enumerate().fold(0.0f64, |acc, (i, w)| {
            acc.max((geom::length(geom::sub(land.end[i], *w)) as f64) / IN2M)
        });
        assert!(worst < 0.05, "landing {worst}\" off the recorded final positions");

        LADDER_DISABLED.store(true, Ordering::Relaxed);
        let off = plain_move(&state, &t, 0, dest, band, true, true, crate::mv::FAST_PLANNER_GUARD)
            .expect("same inputs, same decline rule");
        LADDER_DISABLED.store(false, Ordering::Relaxed);
        let worst_off = want.iter().enumerate().fold(0.0f64, |acc, (i, w)| {
            acc.max((geom::length(geom::sub(off.end[i], *w)) as f64) / IN2M)
        });
        assert!(worst_off > 0.05 * 10.0, "ladder forced off should miss badly, got {worst_off}\"");
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
