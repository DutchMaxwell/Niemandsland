//! `SoloController._finalize_placement` solo_controller.gd:6371 — PASSES 1 AND
//! 2: the per-axis BOUNDS clamp (:6383-6390) and the base-OVERLAP push
//! (`_resolve_overlaps_world` :6716, itself `SeparationResolver.resolve_overlaps`
//! separation_resolver.gd:98 run per model), both spending the per-model
//! displacement budget `_gate_disp_caps_m` :6343 hands in.
//!
//! S5b adds PASS 3 in between, in the table's own order: the projection out of
//! forbidden rest ground (:6402-6412, `_project_out_forbidden_world` :6807),
//! spending the same budget. S5c adds PASS 4, the straggler coherency pull
//! (`_pull_stragglers_coherent_world` :6563), and S5c-2 closes the chain with
//! `_clamp_gate_walls` (:6477), the anti-tunnel revert the table runs on EVERY
//! return path of `_finalize_placement`, the charge arm included (:6443), and
//! with the pull's own CLOSING overlap push (:6636) — which is why
//! `_resolve_overlaps_world` is a function here rather than an inline block.
//!
//! Whole-unit shortening follows pass 4 at EPOCH_6_TABLE_RULES, before the
//! wall clamp. GateFlags carries the original world positions and replay epoch.
//!
//! Remaining gap:
//! Both gate arms and the caller's ladder select the acting unit's chain
//! (`CoherencyChecker` :18) through GateFlags, at the table-rules epoch.
//!
//! THE BOUNDED FIXED POINT. There is no outer `repeat` in the table: the
//! iteration lives INSIDE the passes and each bound is its own constant —
//! `OVERLAP_GATE_PASSES` 4 (:149) for the push, `COH_REPAIR_PASSES` 12 (:6555)
//! for the pull. Both loops also stop the moment a sweep moves nobody, so the
//! gate terminates on any input, pathological configurations included.
//!
//! FRAME. The table gates in float32 world METRES; the passes here still hold
//! the config in the planner's f64 INCH frame, where the endpoints already
//! live, so a model the gate does not touch keeps its endpoint bit for bit
//! instead of picking up a metre round trip. `to_world_f32` / `from_world_f32`
//! and `WorldDisc` carry the table's own frame in its own operation order; the
//! passes move onto it one at a time (the endpoint-localisation ledger says
//! which residue each closes). The OVERLAP PUSH runs on it whole — the inner
//! solver (parity-frame 3, B1) and the pass order, the band-frozen read and
//! the cap circle around it (parity-frame 4, B2) — through `overlap_pass`.
//!
//! BASES. Overlap relaxation and coherency use the real footprint through the
//! shared `geom::pair_gap_m`. Terrain rest, wall chords and the escape scan
//! retain bounding radii, exactly where the table uses them.

use super::geom2::{point_seg_distance, seg_seg_distance, V2};
use crate::terrain::{self, Terrain};
use crate::IN2M;
use crate::acts::{rule_on, EPOCH_6_TABLE_RULES};
use crate::geom::{self, BaseShape};

/// One base as the gate sees it: centre in the planner's INCH frame, radius in
/// inches, with the footprint read from the same base data as the table.
#[derive(Clone, Copy, Debug, Default)]
pub struct Disc {
    pub c: [f64; 2],
    pub r: f64,
    pub shape: BaseShape,
}

/// `INCHES_TO_METERS` as the engine's `real_t`. `Vector2 * float` and
/// `Vector2 / float` narrow the scalar to f32 BEFORE the operation, so the
/// table never multiplies by 0.0254 — it multiplies by this.
const IN2M_F32: f32 = IN2M as f32;

/// `_table_half_extents` (position_parity.gd:33) — `board_in * IN2M * 0.5`,
/// three float32 operations in that order on a `Vector2` board. A recorded
/// board of 71.99999854 in narrows back to the 72 it was printed from.
fn half_extents_f32(board_in: [f64; 2]) -> [f32; 2] {
    [(board_in[0] as f32 * IN2M_F32) * 0.5, (board_in[1] as f32 * IN2M_F32) * 0.5]
}

/// `_plan_move` :6247 — a world point (x, z) into the planner's inch frame,
/// `(Vector2(p.x, p.z) + off) / INCHES_TO_METERS`: a float32 add, THEN a
/// float32 divide. Dividing first, or doing either in f64 and casting at the
/// end, lands a float32 ULP off on a third of the recorded positions.
pub fn from_world_f32(w: [f32; 2], board_in: [f64; 2]) -> [f32; 2] {
    let off = half_extents_f32(board_in);
    [(w[0] + off[0]) / IN2M_F32, (w[1] + off[1]) / IN2M_F32]
}

/// `_plan_move` :6378 — the planner's inch point back into world metres,
/// `(pi * INCHES_TO_METERS) - off`: a float32 multiply, THEN a float32 subtract.
pub fn to_world_f32(p: [f32; 2], board_in: [f64; 2]) -> [f32; 2] {
    let off = half_extents_f32(board_in);
    [p[0] * IN2M_F32 - off[0], p[1] * IN2M_F32 - off[1]]
}

/// One base as the TABLE sees it: centre in float32 WORLD METRES (x, z) —
/// the `Vector3` every gate pass of `_finalize_placement` reads and writes —
/// and the radius as `model_base_radius_m` hands it over (a GDScript float).
#[derive(Clone, Copy, Debug, Default)]
pub struct WorldDisc {
    pub c: [f32; 2],
    pub r_m: f64,
    pub shape: BaseShape,
}

impl WorldDisc {
    /// The gate's inch-frame disc in the table's frame. An inch coordinate
    /// that IS an f32 came out of the planner and is read in the table's own
    /// order (`to_world_f32`, pinned bit for bit above). Any other was written
    /// by f64 arithmetic — a pass moved it, or a world value came in through
    /// `w / IN2M + board / 2` — and is read with ONE rounding, which inverts
    /// that write exactly (28,548 fixture coordinates, 0 off). Narrowing such
    /// a coordinate to f32 INCH first would put it on a third grid, 1.6-3x
    /// coarser than the world's (docs/plans/PARITY_FRAME_PR3_DESIGN).
    pub fn from_disc(d: &Disc, board_in: [f64; 2]) -> WorldDisc {
        WorldDisc { c: world_pt(d.c, board_in), r_m: d.r * IN2M, shape: d.shape }
    }

    /// Back into the planner's inch frame, where the endpoints live.
    pub fn to_disc(&self, board_in: [f64; 2]) -> Disc {
        let p = from_world_f32(self.c, board_in);
        Disc { c: [p[0] as f64, p[1] as f64], r: self.r_m / IN2M, shape: self.shape }
    }
}

/// One inch-frame point in the table's frame, by `from_disc`'s rule.
fn world_pt(p: [f64; 2], board_in: [f64; 2]) -> [f32; 2] {
    let read = |k: usize| if p[k] as f32 as f64 == p[k] {
        to_world_f32([p[0] as f32, p[1] as f32], board_in)[k]
    } else {
        ((p[k] - board_in[k] * 0.5) * IN2M) as f32
    };
    [read(0), read(1)]
}

/// `Vector2::distance_to` — `sqrt((x-p.x)*(x-p.x) + (y-p.y)*(y-p.y))` in
/// float32; `(a - b).length()` is the same five operations.
fn dist_f32(a: [f32; 2], b: [f32; 2]) -> f32 {
    let d = [a[0] - b[0], a[1] - b[1]];
    (d[0] * d[0] + d[1] * d[1]).sqrt()
}

/// `_moving_shapes_at` :6780 — a config as the table's shapes, radii from the
/// metre truth where the caller carries it (`GateFlags::radii_m`).
fn world(cfg: &[Disc], radii_m: &[f64], board_in: [f64; 2]) -> Vec<WorldDisc> {
    cfg.iter().enumerate().map(|(i, d)| {
        let mut w = WorldDisc::from_disc(d, board_in);
        if let Some(r) = radii_m.get(i) { w.r_m = *r; }
        w
    }).collect()
}

/// `SeparationResolver.RESOLVE_EPSILON_INCHES` separation_resolver.gd:46.
const RESOLVE_EPS_IN: f64 = 0.01;
/// `SeparationResolver.MAX_OVERLAP_ITERATIONS` separation_resolver.gd:55.
const MAX_OVERLAP_ITERS: usize = 24;
/// `SeparationResolver.ESCAPE_SCAN_DIRECTIONS` separation_resolver.gd:59.
const ESCAPE_DIRS: usize = 24;
/// `SeparationZone.EPSILON_M` separation_zone.gd:44 — the concentric guard.
const EPSILON_M: f64 = 0.00001;
/// `SoloController.OVERLAP_GATE_PASSES` solo_controller.gd:149.
const OVERLAP_GATE_PASSES: usize = 4;
/// `SoloController.OVERLAP_EPS_M` solo_controller.gd:154 — sub-0.5 mm is noise.
const OVERLAP_EPS_M: f64 = 0.0005;
const OVERLAP_EPS_IN: f64 = OVERLAP_EPS_M / IN2M;
/// `SoloController.BOUNDS_MARGIN_M` solo_controller.gd:16 — a hair inside.
const BOUNDS_MARGIN_IN: f64 = 0.02 / IN2M;
/// `SoloController.TERRAIN_OUT_STEP_M` :151 — the projection's ring spacing.
const TERRAIN_OUT_STEP_IN: f64 = 0.01 / IN2M;
/// `SoloController.TERRAIN_OUT_MAX_M` :152 — its radial reach, ~7.9".
const TERRAIN_OUT_MAX_IN: f64 = 0.20 / IN2M;
/// `SoloController.TERRAIN_OUT_DIRS` :153 — compass points per ring.
const TERRAIN_OUT_DIRS: usize = 16;
/// `SoloController.WALL_REST_CLEARANCE_M` :6779 — 2 mm beyond the base radius.
const WALL_REST_CLEARANCE_IN: f64 = 0.002 / IN2M;
/// `CoherencyChecker.COHERENCY_DISTANCE_INCHES` coherency_checker.gd:10 — two
/// models LINK when their bases are within 1" EDGE to edge.
const COH_LINK_IN: f64 = 1.0;
/// `SeparationChecker.BASE_CONTACT_EPSILON_INCHES` separation_checker.gd:77 —
/// x4 is `gate_chord_crosses_base`'s slack (:6537).
const BASE_CONTACT_EPS_IN: f64 = 0.05;
/// `_clamp_gate_walls` :6487 — under half a millimetre is not a displacement.
const WALL_CLAMP_SKIP_IN: f64 = 0.0005 / IN2M;
/// `_clamp_gate_walls` :6497 — 1 mm of slack past the base radius.
const WALL_CLAMP_SLACK_IN: f64 = 0.001 / IN2M;
/// `SoloController.COH_REPAIR_PASSES` :6555 — pass 4's sweep bound.
const COH_REPAIR_PASSES: usize = 12;

/// What the gate did — for the caller's log line (`rules-must-log`), never for
/// its geometry.
#[derive(Clone, Debug, Default)]
pub struct GateReport {
    /// Per model, the gate's own displacement (planned -> final) in inches.
    pub disp_in: Vec<f64>,
    /// `_gate_clamped_models` :6363 — this model's push hit its band cap.
    pub capped: Vec<bool>,
    /// The largest correction pass 1 applied (`clamped_by_m` :6386), inches.
    pub bounds_in: f64,
    /// Pass 4 nudged this model back into the unit's link chain.
    pub pulled: Vec<bool>,
    /// The coherency the gate leaves behind (`_config_coherent_world` :6832).
    pub coherent: bool,
    /// `_clamp_gate_walls` reverted this model to its route-true endpoint.
    pub reverted: Vec<bool>,
}

/// The two unit-level exemptions `_clamp_gate_walls` reads before it reverts
/// anything (:6392-6393, handed down from `_finalize_placement`).
#[derive(Clone, Copy, Debug, Default)]
pub struct GateFlags<'a> {
    /// Optional chain limit for the boxed candidate comparison; zero keeps the existing ladder.
    pub coherent_chain_in: f64,
    /// Some selects the charge arm; target centres/radii use the table contact test.
    pub charge_targets: Option<&'a [(geom::V3, f64)]>,
    /// The ACTING unit's coherency chain: 6 inches for a skirmish system,
    /// otherwise 9. The table reads it on both arms of `_finalize_placement`
    /// (:6491 charge, :6503 plain); zero keeps the 9 inch default.
    pub chain_in: f64,
    /// Original world positions for the table whole-unit fallback. Empty disables it.
    pub start_world: &'a [geom::V3],
    /// Replays below the table-rules epoch retain the original gate.
    pub rules_epoch: u32,
    /// Footprints in moving-model order, including attached heroes. Empty is round.
    pub shapes: &'a [BaseShape],
    /// `unit.has_special_rule("Flying")` — Flying crosses walls legally, so a
    /// wall-crossing gate push is no tunnel and the clamp is skipped whole.
    pub flying: bool,
    /// `is_traversal(unit)` :5586 — may move THROUGH bases, so only the wall
    /// half of the clamp binds.
    pub traversal: bool,
    /// The moving models' base radii in METRES, `model_base_radius_m`'s own
    /// value: the inch radius is one f64 ULP short of it for some bases. Empty
    /// falls back to `radii_in * IN2M`.
    pub radii_m: &'a [f64],
}

fn dist(a: [f64; 2], b: [f64; 2]) -> f64 {
    ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2)).sqrt()
}

// DIAGNOSTIC (test builds only): a per-thread gate trace, switched on by the
// test that wants it, printed to the process's stderr past the harness capture.
#[cfg(test)]
thread_local! { pub(crate) static TRACE: std::cell::Cell<bool> = std::cell::Cell::new(false); }
#[cfg(test)]
fn tr(s: String) {
    use std::io::Write;
    TRACE.with(|t| if t.get() {
        // Into the file NML_GATE_TRACE_FILE names — past libtest's capture and
        // past the box log's tail window. Unset (the default): no output.
        if let Some(path) = std::env::var_os("NML_GATE_TRACE_FILE") {
            if let Ok(mut f) = std::fs::OpenOptions::new().append(true).create(true).open(path) {
                let _ = writeln!(f, "GT {s}");
            }
        }
    })
}

/// `SeparationResolver._travel_to_clear_along` separation_resolver.gd:156 — the
/// shortest slide along unit direction `u` that clears every obstacle's
/// bounding circle. `e`, its squared length and its dot product are float32
/// `Vector2` reads (:161-165); the quadratic is GDScript f64 (:167-169).
fn travel_to_clear(s: &WorldDisc, obs: &[WorldDisc], u: [f32; 2]) -> f64 {
    let mut travel = 0.0f64;
    for o in obs {
        let r_sum = s.r_m + o.r_m;
        let e = [s.c[0] - o.c[0], s.c[1] - o.c[1]];
        let sq = (e[0] * e[0] + e[1] * e[1]) as f64;
        if sq >= r_sum * r_sum {
            continue;
        }
        let ed = (e[0] * u[0] + e[1] * u[1]) as f64;
        travel = travel.max(-ed + (ed * ed - sq + r_sum * r_sum).max(0.0).sqrt());
    }
    travel
}

/// `SeparationResolver.resolve_overlaps` separation_resolver.gd:98 for ONE item
/// base, in the table's own float32 WORLD frame: the summed-penetration
/// relaxation, then `_escape_to_clear` (:136), the 24-ray scan that makes
/// clearing a finite obstacle set guaranteed. Every `Vector2` operation is a
/// float32 one in the table's loop order — the resultant is SUMMED in f32
/// (:113) and the scalar of every `Vector2 * float` is narrowed first (:113,
/// :122, :148) — while every GDScript `float` (`overlap`, `deepest`, the
/// travel) is f64. Summing in f64 and casting at the end is tidier and wrong:
/// it left recorded-037's push 0.0000022 in off the table. Mutates `s`; returns
/// the table's own "moved" (:6832), the applied translation's non-zero f32
/// squared length.
fn resolve_overlaps(s: &mut WorldDisc, obs: &[WorldDisc]) -> bool {
    if obs.is_empty() {
        return false;
    }
    let mut applied = [0.0f32, 0.0];
    let moved = |a: [f32; 2]| a[0] * a[0] + a[1] * a[1] > 0.0;
    for _ in 0..MAX_OVERLAP_ITERS {
        let (mut res, mut deepest) = ([0.0f32, 0.0], 0.0f64);
        for o in obs {
            let overlap = -edge_w(s, o);
            if overlap <= RESOLVE_EPS_IN {
                continue;
            }
            let mut axis = [s.c[0] - o.c[0], s.c[1] - o.c[1]];
            if ((axis[0] * axis[0] + axis[1] * axis[1]) as f64) < EPSILON_M * EPSILON_M {
                axis = [1.0, 0.0]; // concentric: Vector2.RIGHT, the stable escape
            }
            // `Vector2::normalized` — the f32 length, then two f32 divisions.
            let l = (axis[0] * axis[0] + axis[1] * axis[1]).sqrt();
            let ov = overlap as f32;
            res = [res[0] + axis[0] / l * ov, res[1] + axis[1] / l * ov];
            deepest = deepest.max(overlap);
        }
        #[cfg(test)] { tr(format!("    iter deepest={deepest:.9} res={res:?} c={:?}", s.c)); }
        if deepest <= RESOLVE_EPS_IN {
            return moved(applied); // cleared inside the relaxation cap
        }
        if ((res[0] * res[0] + res[1] * res[1]).sqrt() as f64) < RESOLVE_EPS_IN {
            break; // symmetric wedge: straight to the escape scan (:118-121)
        }
        let step = [res[0] * IN2M_F32, res[1] * IN2M_F32];
        s.c = [s.c[0] + step[0], s.c[1] + step[1]];
        applied = [applied[0] + step[0], applied[1] + step[1]];
    }
    let mut best = (f64::INFINITY, [0.0f32, 0.0]);
    for k in 0..ESCAPE_DIRS {
        // `TAU * k / float(24)` in f64; `Vector2(cos, sin)` narrows to f32.
        let ang = std::f64::consts::TAU * k as f64 / ESCAPE_DIRS as f64;
        let u = [ang.cos() as f32, ang.sin() as f32];
        let travel = travel_to_clear(s, obs, u);
        if travel < best.0 {
            best = (travel, u);
        }
    }
    #[cfg(test)] { tr(format!("    escape travel={} u={:?}", best.0, best.1)); }
    if best.0 > 0.0 && best.0.is_finite() {
        let t = best.0 as f32;
        let step = [best.1[0] * t, best.1[1] * t];
        s.c = [s.c[0] + step[0], s.c[1] + step[1]];
        applied = [applied[0] + step[0], applied[1] + step[1]];
    }
    moved(applied)
}

/// `SoloController._world_forbidden` :6790 — may this base REST here? Two
/// clauses, the table's own: the edge-aware containment test against the
/// impassable class (`TerrainRules.base_in_terrain` x `is_forbidden_rest`, i.e.
/// CONTAINER — a base dipping in by any amount counts), and a ruin/container
/// WALL segment nearer than the base radius plus 2 mm. A model may stand IN a
/// ruin, never ON its wall.
fn rest_forbidden(c: [f64; 2], r_in: f64, t: &Terrain) -> bool {
    let p: V2 = [c[0] as f32, c[1] as f32];
    if terrain::base_in_terrain(t.from_inch(p, 0.0), r_in * IN2M, t, terrain::is_forbidden_rest) {
        return true;
    }
    let lim = r_in + WALL_REST_CLEARANCE_IN;
    t.walls_in().iter().any(|w| point_seg_distance(p, w[0], w[1]) <= lim)
}

/// `SoloController._project_out_forbidden_world` :6807 — the shortest hop to a
/// spot whose WHOLE base is clear: 1 cm rings out to 20 cm, sixteen compass
/// directions each, nearest ring first and, inside one ring, the world-frame
/// `x`-then-`z` order (`to_inch` is monotone on both axes, so the inch frame
/// orders the candidates identically). Candidates are bounds-clamped exactly as
/// pass 1 clamps. A boxed model is returned UNMOVED — the overlap push and the
/// caller's ladder still act on it.
fn project_out_forbidden(p: [f64; 2], r_in: f64, t: &Terrain, board_in: [f64; 2]) -> [f64; 2] {
    if !rest_forbidden(p, r_in, t) {
        return p;
    }
    let mut ring = TERRAIN_OUT_STEP_IN;
    while ring <= TERRAIN_OUT_MAX_IN + OVERLAP_EPS_IN {
        let (mut best, mut found) = (p, false);
        for k in 0..TERRAIN_OUT_DIRS {
            let ang = std::f64::consts::TAU * k as f64 / TERRAIN_OUT_DIRS as f64;
            let c = [
                (p[0] + ang.cos() * ring).clamp(BOUNDS_MARGIN_IN, board_in[0] - BOUNDS_MARGIN_IN),
                (p[1] + ang.sin() * ring).clamp(BOUNDS_MARGIN_IN, board_in[1] - BOUNDS_MARGIN_IN),
            ];
            if rest_forbidden(c, r_in, t) {
                continue;
            }
            if !found
                || c[0] < best[0] - OVERLAP_EPS_IN
                || ((c[0] - best[0]).abs() <= OVERLAP_EPS_IN && c[1] < best[1] - OVERLAP_EPS_IN)
            {
                best = c;
                found = true;
            }
        }
        if found {
            return best;
        }
        ring += TERRAIN_OUT_STEP_IN;
    }
    p
}

/// `SeparationChecker.edge_distance` :294 — the shared footprint measure
/// both the coherency link and the no-stack test are written in.
fn edge(a: &Disc, b: &Disc) -> f64 {
    if a.shape == BaseShape::Round && b.shape == BaseShape::Round {
        // Keep the established all-round planner arithmetic bit for bit.
        return dist(a.c, b.c) - a.r - b.r;
    }
    let pos = |c: [f64; 2]| [(c[0] * IN2M) as f32, 0.0, (c[1] * IN2M) as f32];
    geom::pair_gap_m(pos(a.c), a.r * IN2M, a.shape,
        pos(b.c), b.r * IN2M, b.shape) / IN2M
}

/// `edge` in the table's own frame — `_edge_distance_meters` :290 on float32
/// world centres and f64 radii, over `INCHES_TO_METERS` (:150). The overlap
/// push reads this; the coherency predicates still read `edge` on the inch
/// config (no verdict differs between the two on the recorded corpus).
fn edge_w(a: &WorldDisc, b: &WorldDisc) -> f64 {
    geom::pair_gap_m([a.c[0], 0.0, a.c[1]], a.r_m, a.shape,
        [b.c[0], 0.0, b.c[1]], b.r_m, b.shape) / IN2M
}

/// `_config_overspread_world` :6650 — the widest EDGE-to-edge spread exceeds
/// the chain cap (p.7).
fn overspread(cfg: &[Disc], max_chain: f64) -> bool {
    (0..cfg.len()).any(|i| (i + 1..cfg.len()).any(|j| edge(&cfg[i], &cfg[j]) > max_chain))
}

/// `_largest_link_component_world` :6604 — the indices of the largest 1"-link
/// component, in the table's own BFS discovery order (LIFO queue, ascending
/// neighbour scan). The order is load-bearing: pass 4's nearest-neighbour
/// search keeps the FIRST winner on a tie, so it reads this order.
fn largest_component(cfg: &[Disc]) -> Vec<usize> {
    let n = cfg.len();
    let (mut best, mut seen) = (Vec::new(), vec![false; n]);
    for start in 0..n {
        if seen[start] {
            continue;
        }
        seen[start] = true;
        let (mut comp, mut queue) = (vec![start], vec![start]);
        while let Some(cur) = queue.pop() {
            for o in 0..n {
                if !seen[o] && edge(&cfg[cur], &cfg[o]) <= COH_LINK_IN {
                    seen[o] = true;
                    queue.push(o);
                    comp.push(o);
                }
            }
        }
        if comp.len() > best.len() {
            best = comp;
        }
    }
    best
}

/// `_config_coherent_world` :6832 — ONE 1"-link component holding every model,
/// spread within `max_chain`. Same graph as the component walk above, so it is
/// asked of that walk rather than of a second BFS.
fn config_coherent(cfg: &[Disc], max_chain: f64) -> bool {
    cfg.len() <= 1 || (largest_component(cfg).len() == cfg.len() && !overspread(cfg, max_chain))
}

/// Shape-aware wrapper for the collapse ladder's start/end predicates. The
/// footprint is geometry and therefore has no rules-epoch switch.
pub(crate) fn coherent_placement(planned: &[V2], radii_in: &[f64], flags: GateFlags<'_>) -> bool {
    let chain = if flags.coherent_chain_in > 0.0 { flags.coherent_chain_in } else { super::MAX_CHAIN_IN };
    if flags.shapes.iter().all(|s| *s == BaseShape::Round) {
        // The original ladder's round-only float32 predicates stay unchanged.
        return planned.len() <= 1 || (super::components_r(planned, radii_in).len() == 1
            && super::max_edge_spread_r(planned, radii_in) <= chain);
    }
    let cfg: Vec<Disc> = planned.iter().enumerate().map(|(i, p)| Disc {
        c: [p[0] as f64, p[1] as f64],
        r: radii_in.get(i).copied().unwrap_or(0.0),
        shape: flags.shapes.get(i).copied().unwrap_or_default(),
        ..Default::default()
    }).collect();
    config_coherent(&cfg, chain)
}

/// `_cap_gate_disp` :6360 — truncate one gate correction to the model's
/// band-slack circle around its RAW planned endpoint, marking it when it bit.
fn cap_disp(cand: [f64; 2], goal: [f64; 2], cap: f64, i: usize, rep: &mut GateReport,
            board: [f64; 2], rules_epoch: u32) -> [f64; 2] {
    if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        // `_cap_gate_disp` reads Vector2 world offsets. An inch-space cap
        // can move a point by one world ULP and change a shortening probe.
        let (at, origin) = (world_pt(cand, board), world_pt(goal, board));
        let off = [at[0] - origin[0], at[1] - origin[1]];
        let len = (off[0] * off[0] + off[1] * off[1]).sqrt();
        if len as f64 <= cap * IN2M {
            return cand;
        }
        rep.capped[i] = true;
        let cap_m = (cap * IN2M) as f32;
        let end = [origin[0] + off[0] / len * cap_m,
                   origin[1] + off[1] / len * cap_m];
        return [end[0] as f64 / IN2M + board[0] * 0.5,
                end[1] as f64 / IN2M + board[1] * 0.5];
    }
    let off = [cand[0] - goal[0], cand[1] - goal[1]];
    let l = (off[0] * off[0] + off[1] * off[1]).sqrt();
    if l <= cap {
        return cand;
    }
    rep.capped[i] = true;
    [goal[0] + off[0] / l * cap, goal[1] + off[1] / l * cap]
}

/// `_resolve_overlaps_world` :6795 — the slack-aware Gauss-Seidel push, its own
/// function because the table runs it TWICE: once as pass 2 and once more to
/// clear whatever pass 4's inward pulls stacked (:6636).
///
/// THE SEAM (parity-frame 3 B1, 4 B2). The table builds its shapes once per
/// call (:6800), every push moves them in float32 world metres, and only at
/// the end are the centres written back (:6841). This holds the same world
/// config `w` across all passes, so a centre the solver moved never
/// round-trips through the inch frame between passes; the slack order, the
/// band-frozen read and the cap circle read that config and the RAW plan in
/// the table's frame too (B2), so a capped model lands on the table's own
/// float32 point. The inch config `cfg` is the MIRROR written after every
/// move for the passes downstream: the world point's f64 preimage
/// `w / IN2M + board / 2`, which `from_disc` inverts bit for bit, so every
/// later world read sees this very point; narrowed ONCE at the output it is
/// the nearest f32 inch, which lands on the table's point whenever the
/// f32-inch grid holds one. (The `_plan_move` :6247 read, two float32
/// roundings, lost the world point on every second moved model and the
/// output on one in seven that had a preimage — a 200,000-point probe.)
/// Returns the world config the passes ended on.
fn overlap_pass(cfg: &mut [Disc], goal: &[[f64; 2]], caps_in: &[f64], capped: bool,
                external: &[Disc], radii_m: &[f64], board_in: [f64; 2], rep: &mut GateReport)
                -> Vec<WorldDisc> {
    let n = cfg.len();
    let mut w = world(cfg, radii_m, board_in);
    let ext = world(external, &[], board_in);
    // `planned_world` (:6824, never rewritten) and `disp_caps_m` as
    // `_gate_disp_caps_m` :6431 hands them over: the inch value times
    // INCHES_TO_METERS, a GDScript float. `rem` :6815 is that float minus a
    // float32 `distance_to`.
    let goal_w: Vec<[f32; 2]> = goal.iter().map(|g| world_pt(*g, board_in)).collect();
    let caps_m: Vec<f64> = caps_in.iter().map(|c| c * IN2M).collect();
    let slack = |i: usize, w: &[WorldDisc]| caps_m[i] - dist_f32(w[i].c, goal_w[i]) as f64;
    #[cfg(test)] { for (i, d) in w.iter().enumerate() { tr(format!("push in {i} w={:?} r_m={} c={:?}", d.c, d.r_m, cfg[i].c)); } }
    for _ in 0..OVERLAP_GATE_PASSES {
        let mut order: Vec<usize> = (0..n).collect();
        if capped {
            let rem: Vec<f64> = (0..n).map(|i| slack(i, &w)).collect();
            // `order.sort_custom` :6737. Hand-rolled (insertion, stable, n is a
            // unit's model count) because that comparator's epsilon tie-break is
            // not a strict total order and Rust's own sort may panic on one.
            for a in 1..n {
                let v = order[a];
                let mut j = a;
                while j > 0 && {
                    let w = order[j - 1];
                    if (rem[v] - rem[w]).abs() > OVERLAP_EPS_M {
                        rem[v] > rem[w]
                    } else {
                        v < w
                    }
                } {
                    order[j] = order[j - 1];
                    j -= 1;
                }
                order[j] = v;
            }
        }
        let mut moved = false;
        #[cfg(test)] { tr(format!("pass order={order:?}")); }
        for i in order {
            if capped && slack(i, &w) <= OVERLAP_EPS_M {
                continue; // band-frozen (:6825)
            }
            let mut obs: Vec<WorldDisc> = ext.clone();
            obs.extend((0..n).filter(|&j| j != i).map(|j| w[j]));
            let mut s = w[i];
            #[cfg(test)] { tr(format!("  model {i} at {:?}", s.c)); }
            if resolve_overlaps(&mut s, &obs) {
                moved = true;
                if capped {
                    // `_cap_gate_disp` on the shape (:6836-6839): a float32
                    // `off`, its float32 length widened against the f64 cap,
                    // then `normalized() * float(cap)` — two float32 divides,
                    // the cap narrowed, two multiplies, two adds.
                    let off = [s.c[0] - goal_w[i][0], s.c[1] - goal_w[i][1]];
                    let l = (off[0] * off[0] + off[1] * off[1]).sqrt();
                    if l as f64 > caps_m[i] {
                        let cap = caps_m[i] as f32;
                        s.c = [goal_w[i][0] + off[0] / l * cap, goal_w[i][1] + off[1] / l * cap];
                        rep.capped[i] = true;
                    }
                }
                #[cfg(test)] { tr(format!("  moved {i} {:?} -> {:?}", w[i].c, s.c)); }
                w[i] = s;
                cfg[i].c = [s.c[0] as f64 / IN2M + board_in[0] * 0.5,
                            s.c[1] as f64 / IN2M + board_in[1] * 0.5];
            }
        }
        if !moved {
            break;
        }
    }
    w
}

/// Everything a pass-4 sweep needs that does not change between nudges: the RAW
/// plan the band-slack circles are centred on, those caps, and the board and
/// terrain every correction is spent against.
struct Pull<'a> {
    max_chain: f64,
    rules_epoch: u32,
    goal: &'a [[f64; 2]],
    caps_in: &'a [f64],
    capped: bool,
    board_in: [f64; 2],
    terrain: Option<&'a Terrain>,
    external: &'a [Disc],
    radii_m: &'a [f64],
}

impl Pull<'_> {
    /// ONE straggler nudge (:6608-6616 and :6628-6634 share it): step model `i`
    /// at most `len` inches toward `to`, then spend the same three corrections
    /// every gate pass spends — bounds clamp, projection out of forbidden rest
    /// ground and the band-slack cap. A nudge the cap erases is not taken at
    /// all: the band leaves no room, and the caller's ladder settles the model
    /// at a shorter reach. Returns whether the model actually moved.
    fn nudge(&self, cfg: &mut [Disc], i: usize, to: [f64; 2], len: f64, rep: &mut GateReport) -> bool {
        let d = [to[0] - cfg[i].c[0], to[1] - cfg[i].c[1]];
        let l = (d[0] * d[0] + d[1] * d[1]).sqrt();
        if l < OVERLAP_EPS_IN || len <= OVERLAP_EPS_IN {
            return false;
        }
        let (step, b) = (len.min(l), self.board_in);
        let mut cand = [
            (cfg[i].c[0] + d[0] / l * step).clamp(BOUNDS_MARGIN_IN, b[0] - BOUNDS_MARGIN_IN),
            (cfg[i].c[1] + d[1] / l * step).clamp(BOUNDS_MARGIN_IN, b[1] - BOUNDS_MARGIN_IN),
        ];
        if let Some(t) = self.terrain {
            cand = project_out_forbidden(cand, cfg[i].r, t, b);
        }
        if self.capped {
            cand = cap_disp(cand, self.goal[i], self.caps_in[i], i, rep,
                self.board_in, self.rules_epoch);
            if dist(cand, cfg[i].c) <= OVERLAP_EPS_IN {
                return false;
            }
        }
        #[cfg(test)] { tr(format!("nudge i={i} from={:?} to={:?} len={len} cand={:?}", cfg[i].c, to, cand)); }
        cfg[i].c = cand;
        rep.pulled[i] = true;
        true
    }

    /// `_pull_stragglers_coherent_world` :6563 — PASS 4, the MINIMAL coherency
    /// repair. Each model outside the unit's largest 1"-link component steps
    /// toward its nearest in-component neighbour, at most one link per sweep and
    /// stopping AT the 1" link so the step never manufactures the overlap it is
    /// trying to avoid; and when the unit over-spreads, the single model
    /// furthest from the centroid is pulled inward. Minimal is the point: the
    /// models that advanced correctly keep their FULL move, where the whole-unit
    /// shorten would drag the entire unit back and leave it short of its own
    /// shooting range.
    ///
    /// The sweep IS the bounded fixed point: `COH_REPAIR_PASSES` at the most,
    /// and it stops the moment a sweep moves nobody or the config comes out
    /// coherent, so it terminates on any input. The table's CLOSING overlap push
    /// A final overlap push clears whatever the inward pulls stacked (:6636) —
    /// skipped on the early exit above, exactly as the table skips it.
    fn run(&self, cfg: &mut [Disc], rep: &mut GateReport) -> bool {
        let (n, max_chain) = (cfg.len(), self.max_chain);
        for _ in 0..COH_REPAIR_PASSES {
            if config_coherent(cfg, max_chain) {
                return true;
            }
            let table_rules = rule_on(self.rules_epoch, EPOCH_6_TABLE_RULES);
            // The table takes one shape snapshot per sweep. Later nudges do
            // not change the nearest-neighbour or over-spread reads this pass.
            let snapshot = cfg.to_vec();
            let main = largest_component(&snapshot);
            #[cfg(test)] { tr(format!("pull sweep main={main:?} overspread={}", overspread(&snapshot, max_chain))); }
            let mut moved = false;
            // (a) reconnect — nearest in-component neighbour by EDGE distance,
            // the FIRST winner on a tie (the component's own BFS order).
            for i in (0..n).filter(|i| !main.contains(i)) {
                let (mut nd, mut near) = (f64::INFINITY, usize::MAX);
                for &m in &main {
                    let shapes = if table_rules { &snapshot[..] } else { &cfg[..] };
                    if edge(&shapes[i], &shapes[m]) < nd {
                        nd = edge(&shapes[i], &shapes[m]);
                        near = m;
                    }
                }
                if near == usize::MAX {
                    continue;
                }
                // Preserve the table expression literally: nd is in inches,
                // while its subtrahend and caps are in world metres. This is
                // the repair whose remaining illegality triggers shortening.
                let len = if table_rules {
                    ((nd - COH_LINK_IN * IN2M) / IN2M).min(COH_LINK_IN)
                } else { (nd - COH_LINK_IN).min(COH_LINK_IN) };
                let to = cfg[near].c;
                #[cfg(test)] { tr(format!("pull i={i} near={near} nd={nd} len={len}")); }
                moved |= self.nudge(cfg, i, to, len, rep);
            }
            // (b) over-spread — pull the model furthest from the centroid in.
            if overspread(if table_rules { &snapshot } else { cfg }, max_chain) {
                let sum = |k: usize| cfg.iter().map(|d| d.c[k]).sum::<f64>() / n as f64;
                let c = [sum(0), sum(1)];
                // `_furthest_from_world` :6672 keeps the FIRST strict maximum.
                let far = (1..n).fold(0, |b, i| if dist(cfg[i].c, c) > dist(cfg[b].c, c) { i } else { b });
                moved |= self.nudge(cfg, far, c, COH_LINK_IN, rep);
            }
            if !moved {
                break;
            }
        }
        overlap_pass(cfg, self.goal, self.caps_in, self.capped, self.external, self.radii_m,
            self.board_in, rep);
        config_coherent(cfg, max_chain)
    }
}

/// `_clamp_gate_walls` :6477 — the LAST word on every return path of the table's
/// gate, the charge arm included (:6443). No gate step may TUNNEL: a model whose
/// gate displacement (RAW planned -> final) grazes a ruin/container wall inside
/// its own base radius, or cuts THROUGH an external base
/// (`gate_chord_crosses_base` :6535), is reverted WHOLE to its planned,
/// route-true endpoint. The residual overlap/coherency debt is then the caller
/// ladder's to settle at a shorter reach — route truth wins.
fn clamp_gate_walls(cfg: &mut [Disc], goal: &[[f64; 2]], external: &[Disc], flags: GateFlags,
                    terrain: Option<&Terrain>, rep: &mut GateReport) {
    if flags.flying {
        return; // Flying crosses walls legally; its push is no tunnel (:6479)
    }
    let walls: &[[V2; 2]] = terrain.map_or(&[][..], |t| t.walls_in());
    if walls.is_empty() && external.is_empty() {
        return;
    }
    let slack = BASE_CONTACT_EPS_IN * 4.0;
    for i in 0..cfg.len() {
        let (a, b) = (goal[i], cfg[i].c);
        if dist(a, b) <= WALL_CLAMP_SKIP_IN {
            continue;
        }
        let (a2, b2): (V2, V2) = ([a[0] as f32, a[1] as f32], [b[0] as f32, b[1] as f32]);
        // EDGE-AWARE (:6493): crossing alone missed the last leg SLIDING ALONG a
        // wall inside the base radius, so the segment must keep the radius clear.
        let lim = cfg[i].r + WALL_CLAMP_SLACK_IN;
        let grazed = walls.iter().any(|w| seg_seg_distance(a2, b2, w[0], w[1]) < lim);
        // A chord STARTING inside a base is the overlap push ESCAPING it, and
        // outward motion is exactly the gate's job — never a tunnel (:6543).
        // Traversal may move through bases, so only the wall half binds (:6503).
        let cut = !flags.traversal
            && external.iter().any(|o| {
                let l = cfg[i].r + o.r - slack;
                l > 0.0
                    && dist(a, o.c) >= l
                    && point_seg_distance([o.c[0] as f32, o.c[1] as f32], a2, b2) < l
            });
        if grazed || cut {
            cfg[i].c = a;
            rep.reverted[i] = true;
        }
    }
}

/// `_finalize_placement` :6371, passes 1 to 4 plus the wall clamp, over ONE unit's planned
/// endpoints. `external` is `_external_obstacle_shapes` :6676 — every OTHER
/// on-table unit's alive-model base. `caps_in` is `_gate_disp_caps_m`'s output;
/// a length other than `planned`'s means UNCAPPED, the same guard the GDScript
/// reads at :6398 (a charge passes none). `terrain` switches pass 3 on; `None`
/// is the board the recorder never wrote a terrain line for. `flags` carries the
/// two unit rules only the wall clamp asks about.
pub fn finalize_placement(
    planned: &[V2],
    radii_in: &[f64],
    external: &[Disc],
    caps_in: &[f64],
    board_in: [f64; 2],
    terrain: Option<&Terrain>,
    flags: GateFlags,
) -> (Vec<V2>, GateReport) {
    let n = planned.len();
    let mut rep = GateReport {
        disp_in: vec![0.0; n],
        capped: vec![false; n],
        bounds_in: 0.0,
        pulled: vec![false; n],
        coherent: true,
        reverted: vec![false; n],
    };
    // (bounds) :6383-6390 — clamp per axis FIRST, so every later correction
    // starts from a legal configuration. The cap circles below stay anchored on
    // the RAW plan (`planned_world` is never rewritten, :6373).
    let goal: Vec<[f64; 2]> = planned.iter().map(|p| [p[0] as f64, p[1] as f64]).collect();
    let mut cfg: Vec<Disc> = (0..n)
        .map(|i| {
            let c = [
                goal[i][0].clamp(BOUNDS_MARGIN_IN, board_in[0] - BOUNDS_MARGIN_IN),
                goal[i][1].clamp(BOUNDS_MARGIN_IN, board_in[1] - BOUNDS_MARGIN_IN),
            ];
            rep.bounds_in = rep.bounds_in.max(dist(c, goal[i]));
            Disc {
                c,
                r: radii_in.get(i).copied().unwrap_or(0.0),
                shape: flags.shapes.get(i).copied().unwrap_or_default(),
            }
        })
        .collect();
    let charge = flags.charge_targets.is_some() && rule_on(flags.rules_epoch, EPOCH_6_TABLE_RULES);
    // :6491 and :6503 read the SAME `is_skirmish_system(unit)` answer. The
    // plain arm used to fall back to 9 inches, which kept a placement the table
    // shortens away for a skirmish unit.
    let max_chain = if flags.chain_in > 0.0 && rule_on(flags.rules_epoch, EPOCH_6_TABLE_RULES) {
        flags.chain_in
    } else { super::MAX_CHAIN_IN };
    let capped = !charge && caps_in.len() == n;
    #[cfg(test)] {
        tr(format!("gate n={n} charge={charge} capped={capped} ext={} chain={max_chain} flying={} board={board_in:?}", external.len(), flags.flying));
        for (i, e) in external.iter().enumerate() { tr(format!("ext {i} c={:?} r={} shape={:?}", e.c, e.r, e.shape)); }
        for i in 0..n { tr(format!("gate in {i} c={:?} r={} r_m={:?} shape={:?} start={:?} cap={:?}", cfg[i].c, cfg[i].r, flags.radii_m.get(i), cfg[i].shape, flags.start_world.get(i), caps_in.get(i))); }
        if let Some(t) = flags.charge_targets { for (p, r) in t { tr(format!("target {p:?} r={r}")); } }
    }
    // (terrain) :6402-6412 — project every model out of forbidden rest ground
    // BEFORE the overlap push, so the crowd resolves around spots that are
    // already legal. A projection costing MORE than the model's band slack is
    // refused WHOLE, never truncated: a half hop would still rest inside the
    // container. The route-true spot is kept, the model is marked, and the debt
    // goes to the caller's ladder at a shorter reach — route truth wins.
    if let Some(t) = terrain {
        for i in 0..n {
            if charge {
                let y = flags.start_world.get(i).map_or(0.0, |p| p[1]);
                let at = t.from_inch([cfg[i].c[0] as f32, cfg[i].c[1] as f32], y);
                let contact = flags.charge_targets.unwrap_or(&[]).iter().any(|(p, r)|
                    geom::length(geom::sub(at, *p)) as f64 - cfg[i].r * IN2M - r
                        <= BASE_CONTACT_EPS_IN * IN2M * 4.0);
                if contact { continue; }
            }
            let proj = project_out_forbidden(cfg[i].c, cfg[i].r, t, board_in);
            if capped && dist(proj, goal[i]) > caps_in[i] {
                rep.capped[i] = true;
            } else {
                cfg[i].c = proj;
            }
        }
    }
    // (overlap) :6716-6752 — Gauss-Seidel, slack-aware: the models with the most
    // band left resolve first, a model at its cap is FROZEN (it stays in every
    // neighbour's obstacle set, so the crowd walks around it), and each push is
    // truncated to the cap circle. Residual overlap between two capped models is
    // deliberately LEFT for the caller's ladder to settle at a shorter reach.
    #[cfg(test)] { for i in 0..n { tr(format!("gate proj {i} c={:?} capped={}", cfg[i].c, rep.capped[i])); } }
    let _w = overlap_pass(&mut cfg, &goal, caps_in, capped, external, flags.radii_m, board_in, &mut rep);
    #[cfg(test)] {
        for i in 0..n { tr(format!("gate push {i} w={:?} c={:?}", _w[i].c, cfg[i].c)); }
        tr(format!("gate coherent={} largest={:?} overspread={}", config_coherent(&cfg, max_chain), largest_component(&cfg), overspread(&cfg, max_chain)));
    }
    // (coherency) :6444-6465 — PASS 4. The table keeps the full move when the
    // config is coherent AND overlap-free AND terrain-clear, and otherwise runs
    // the straggler repair before falling back to the whole-unit shorten. The
    // repair itself returns at once on a coherent config. The whole-unit
    // fallback below also checks overlap and forbidden rest ground.
    if !config_coherent(&cfg, max_chain) {
        let pull = Pull { max_chain, rules_epoch: flags.rules_epoch, goal: &goal, caps_in, capped,
            board_in, terrain, external, radii_m: flags.radii_m };
        rep.coherent = pull.run(&mut cfg, &mut rep);
        #[cfg(test)] { tr(format!("gate after pull coherent={} pulled={:?}", rep.coherent, rep.pulled)); }
    }
    if !charge && n > 1 && flags.start_world.len() == n
        && rule_on(flags.rules_epoch, EPOCH_6_TABLE_RULES)
        && !config_legal(&cfg, external, terrain, max_chain)
    {
        cfg = shorten_to_legal(flags.start_world, &cfg, external, board_in, terrain, max_chain);
        rep.coherent = config_coherent(&cfg, max_chain);
    }
    clamp_gate_walls(&mut cfg, &goal, external, flags, terrain, &mut rep);
    #[cfg(test)] { for i in 0..n { tr(format!("gate out {i} c={:?} reverted={}", cfg[i].c, rep.reverted[i])); } }
    let out = (0..n)
        .map(|i| {
            rep.disp_in[i] = dist(cfg[i].c, goal[i]);
            [cfg[i].c[0] as f32, cfg[i].c[1] as f32]
        })
        .collect();
    (out, rep)
}

#[cfg(test)]
mod shape_tests {
    use super::*;
    use serde_json::Value;

    #[test]
    fn pinned_base_shapes_fixture_uses_real_footprint() {
        let fixtures: Value = serde_json::from_str(include_str!(
            "../../../../test/fixtures/position_parity/cases.json")).unwrap();
        let pin: Value = serde_json::from_str(include_str!(
            "../../../../test/fixtures/position_parity/base_shapes.json")).unwrap();
        let case = fixtures["cases"].as_array().unwrap().iter()
            .find(|c| c["id"] == pin["source_case"]).unwrap();
        let discs: Vec<Disc> = case["units"].as_array().unwrap().iter().map(|u| {
            let p = &u["positions"][0];
            Disc { c: [p[0].as_f64().unwrap() / IN2M, p[2].as_f64().unwrap() / IN2M],
                r: u["radii"][0].as_f64().unwrap() / IN2M,
                shape: if u["base_shape"] == "oval" {
                    BaseShape::Oval { w_mm: u["base_w_mm"].as_f64().unwrap(),
                        d_mm: u["base_d_mm"].as_f64().unwrap(), yaw: 0.0 }
                } else { BaseShape::Round }, ..Default::default() }
        }).collect();
        let got = edge(&discs[0], &discs[1]);
        let expected = pin["edge_in"].as_f64().unwrap();
        assert!((got - expected).abs() <= pin["tolerance_in"].as_f64().unwrap(),
            "generated-oval-large: gate edge={got:.9}in table={expected:.9}in");
        // Axis/contact probes reuse this bucket fixture's bases. Pin both the
        // moving oval and an oval obstacle; only the centres are translated.
        for probe in pin["probes"].as_array().unwrap() {
            for swap in [false, true] {
                let (moving, mut other) = if swap { (discs[1], discs[0]) } else { (discs[0], discs[1]) };
                other.c = [36.0 + probe["obstacle_offset_m"][0].as_f64().unwrap() / IN2M,
                    24.0 + probe["obstacle_offset_m"][1].as_f64().unwrap() / IN2M];
                let shapes = [moving.shape];
                let (got, _) = finalize_placement(&[[36.0, 24.0]], &[moving.r], &[other], &[],
                    [72.0, 48.0], None, GateFlags { shapes: &shapes, ..Default::default() });
                for axis in 0..2 {
                    let expected = [36.0, 24.0][axis] + probe["expected_push_m"][axis].as_f64().unwrap() / IN2M;
                    assert!((got[0][axis] as f64 - expected).abs() < 0.00001,
                        "shape-aware final placement: swap={swap} got={got:?} expected axis={expected}");
                }
            }
        }
    }
}

/// The table's three final predicates, shared by each bisection probe.
fn config_legal(cfg: &[Disc], external: &[Disc], terrain: Option<&Terrain>, chain: f64) -> bool {
    config_coherent(cfg, chain)
        && (0..cfg.len()).all(|i| {
            (i + 1..cfg.len()).all(|j| edge(&cfg[i], &cfg[j]) >= -RESOLVE_EPS_IN)
                && external.iter().all(|o| edge(&cfg[i], o) >= -RESOLVE_EPS_IN)
                && terrain.is_none_or(|t| !rest_forbidden(cfg[i].c, cfg[i].r, t))
        })
}

/// `_blend_world`: lerpf promotes coordinates to f64, then constructing the
/// Vector3 rounds each result to f32. Preserve that rounding before testing it.
fn blend_from_start(start_world: &[geom::V3], cfg: &[Disc], factor: f64,
                    board_in: [f64; 2]) -> Vec<Disc> {
    cfg.iter().enumerate().map(|(i, d)| {
        let mut blended = *d;
        for axis in 0..2 {
            let start = start_world[i][axis * 2] as f64;
            let end = ((d.c[axis] - board_in[axis] * 0.5) * IN2M) as f32 as f64;
            let world = (start + (end - start) * factor) as f32;
            blended.c[axis] = world as f64 / IN2M + board_in[axis] * 0.5;
        }
        blended
    }).collect()
}

/// `_shorten_world_to_legal`: the largest tested legal whole-unit blend toward
/// the original start. The table assumes t=0 is legal and retains that fallback
/// even for an invalid start; it does not search a different direction here.
fn shorten_to_legal(start_world: &[geom::V3], cfg: &[Disc], external: &[Disc],
                    board_in: [f64; 2], terrain: Option<&Terrain>, chain: f64) -> Vec<Disc> {
    if config_legal(cfg, external, terrain, chain) {
        return cfg.to_vec();
    }
    let (mut lo, mut hi) = (0.0, 1.0);
    for _ in 0..16 {
        let mid = (lo + hi) * 0.5;
        let candidate = blend_from_start(start_world, cfg, mid, board_in);
        if config_legal(&candidate, external, terrain, chain) { lo = mid; } else { hi = mid; }
    }
    blend_from_start(start_world, cfg, lo, board_in)
}

#[cfg(test)]
mod shorten_tests {
    #[test]
    fn whole_unit_shorten_uses_the_table_straggler_repair() {
        let pin: serde_json::Value = serde_json::from_str(include_str!(
            "../../../../test/fixtures/position_parity/whole_unit_shorten.json")).unwrap();
        let pin = &pin["repair_probe"];
        let n = |v: &serde_json::Value| v.as_f64().unwrap();
        let start: Vec<geom::V3> = pin["planned_world"].as_array().unwrap().iter()
            .map(|p| [n(&p[0]) as f32, 0.0, n(&p[2]) as f32]).collect();
        let planned: Vec<V2> = start.iter().map(|p|
            [(p[0] as f64 / IN2M + 36.0) as f32, (p[2] as f64 / IN2M + 24.0) as f32]).collect();
        let run = |rules_epoch| finalize_placement(&planned, &[n(&pin["radius_m"]) / IN2M; 2],
            &[], &[], [72.0,48.0], None, GateFlags { start_world:&start,
                rules_epoch, ..Default::default() }).0;
        let got = run(6);
        let want = n(&pin["expected_world"][1][0]);
        let gap = (((got[1][0] as f64 - 36.0) * IN2M - want) / IN2M).abs();
        assert!(gap <= n(&pin["tolerance_in"]), "table repair differs by {gap:.9}in");
        assert_eq!(run(0),run(5));
        assert_ne!(run(5),got);
    }

    #[test]
    fn whole_unit_shorten_is_gated_at_the_table_rules_epoch() {
        let board = [72.0, 48.0];
        let start = [[(40.0 - 36.0) as f32 * IN2M as f32, 0.0, 0.0],
            [(41.5 - 36.0) as f32 * IN2M as f32, 0.0, 0.0]];
        let planned = [[45.0, 24.0], [49.0, 24.0]];
        let run = |rules_epoch| finalize_placement(&planned, &[0.5, 0.5], &[],
            &[0.0, 0.0], board, None, GateFlags { start_world: &start,
                rules_epoch, ..Default::default() }).0;
        assert_eq!(run(0), planned);
        assert_eq!(run(5), planned);
        let epoch6 = run(6);
        assert_eq!(epoch6, run(7));
        assert!(epoch6[0][0] < 42.0 && epoch6[1][0] < 44.0, "{epoch6:?}");
        assert!(epoch6[1][0] - epoch6[0][0] <= 2.00001, "{epoch6:?}");
        // An old caller with no start positions cannot silently change behavior.
        let absent = finalize_placement(&planned, &[0.5, 0.5], &[], &[0.0, 0.0],
            board, None, GateFlags { rules_epoch: 6, ..Default::default() }).0;
        assert_eq!(absent, planned);
    }

    use super::*;
    use serde_json::Value;

    #[test]
    fn pinned_whole_unit_shorten_reaches_the_table_placement() {
        let pin: Value = serde_json::from_str(include_str!(
            "../../../../test/fixtures/position_parity/whole_unit_shorten.json")).unwrap();
        let n = |v: &Value| v.as_f64().unwrap();
        let board = [n(&pin["board_in"][0]), n(&pin["board_in"][1])];
        let start: Vec<geom::V3> = pin["start_world"].as_array().unwrap().iter()
            .map(|p| [n(&p[0]) as f32, n(&p[1]) as f32, n(&p[2]) as f32]).collect();
        let body = |v: &Value, c: [f64; 2]| Disc {
            c: [c[0] / IN2M + board[0] * 0.5, c[1] / IN2M + board[1] * 0.5],
            r: n(&v["radius"]) / IN2M,
            shape: if v["oval"].as_bool().unwrap() {
                BaseShape::Oval { w_mm: n(&v["semi_x"]) * 2000.0,
                    d_mm: n(&v["semi_z"]) * 2000.0, yaw: n(&v["yaw"]) as f32 }
            } else { BaseShape::Round },
            ..Default::default()
        };
        let cfg: Vec<Disc> = pin["moving"].as_array().unwrap().iter().enumerate()
            .map(|(i, v)| body(v, [n(&pin["planned_world"][i][0]), n(&pin["planned_world"][i][2])])).collect();
        let external: Vec<Disc> = pin["external"].as_array().unwrap().iter()
            .map(|v| body(v, [n(&v["center"][0]), n(&v["center"][1])])).collect();
        let plain: terrain::PlainTerrain = serde_json::from_value(pin["terrain"].clone()).unwrap();
        let terrain = Terrain::build(&plain);
        let got = shorten_to_legal(&start, &cfg, &external, board, Some(&terrain),
            crate::mv::MAX_CHAIN_IN);
        let mut worst = 0.0f64;
        for (i, d) in got.iter().enumerate() {
            let delta = [
                (d.c[0] - board[0] * 0.5) * IN2M - n(&pin["expected_world"][i][0]),
                (d.c[1] - board[1] * 0.5) * IN2M - n(&pin["expected_world"][i][2]),
            ];
            worst = worst.max(delta[0].hypot(delta[1]) / IN2M);
        }
        assert!(worst <= n(&pin["tolerance_in"]),
            "recorded-003: whole-unit shorten differs from table by {worst:.9}in");
    }
}

/// Where the Stage A endpoints that the harness ACCEPTS still differ from the
/// table. Each pinned case replays the reference table's own first gate,
/// overlap and whole-unit-shorten call through this module with the table's own
/// input, so a difference can be attributed to one stage instead of to the
/// accumulated result. The bounds are measurements, not targets: they may only
/// ever shrink.
#[cfg(test)]
mod endpoint_localisation {
    use super::*;
    use serde_json::Value;

    fn conv(points: &Value, board: [f64; 2]) -> Vec<[f64; 2]> {
        points.as_array().unwrap().iter()
            .map(|p| [p[0].as_f64().unwrap() / IN2M + board[0] * 0.5,
                      p[2].as_f64().unwrap() / IN2M + board[1] * 0.5])
            .collect()
    }

    fn worst(got: &[[f64; 2]], want: &[[f64; 2]]) -> f64 {
        assert_eq!(got.len(), want.len(), "model count");
        got.iter().zip(want).map(|(a, b)| dist(*a, *b)).fold(0.0, f64::max)
    }

    fn shape_of(unit: &Value) -> BaseShape {
        if unit["base_shape"] == "oval" {
            BaseShape::Oval { w_mm: unit["base_w_mm"].as_f64().unwrap(),
                d_mm: unit["base_d_mm"].as_f64().unwrap(), yaw: 0.0 }
        } else {
            BaseShape::Round
        }
    }

    #[test]
    fn accepted_non_equal_endpoints_are_localised_to_one_stage() {
        let fixtures: Value = serde_json::from_str(include_str!(
            "../../../../test/fixtures/position_parity/cases.json")).unwrap();
        let pins: Value = serde_json::from_str(include_str!(
            "../../../../test/fixtures/position_parity/endpoint_localisation.json")).unwrap();
        // id, gate bound, overlap bound, shorten bound — inches, measured.
        let bounds = [
            ("recorded-037", 0.00000304, 1e-9, 1e-9),
            ("recorded-128", 0.0000024, 1e-9, 1e-9),
            ("recorded-162", 0.00000046, 1e-9, 1e-9),
        ];
        // Straight to the process's stderr, past the harness capture, so a
        // GREEN box run still leaves every measured residue in its cargo log.
        let say = |line: String| { use std::io::Write; let _ = writeln!(std::io::stderr(), "{line}"); };
        // Every bound is measured before any is asserted: one run shows the
        // whole ledger, not just the first row that fails.
        let mut fails: Vec<String> = Vec::new();
        for (id, gate_bound, overlap_bound, shorten_bound) in bounds {
            let pin = &pins["cases"][id];
            let case = fixtures["cases"].as_array().unwrap().iter()
                .find(|c| c["id"] == id).unwrap();
            let board = [case["board_in"][0].as_f64().unwrap(),
                         case["board_in"][1].as_f64().unwrap()];
            let units: Vec<&Value> = case["units"].as_array().unwrap().iter().collect();
            let unit_of = |key: &Value| *units.iter().find(|u| u["id"] == *key).unwrap();
            let actor = unit_of(&case["action"]["unit"]);
            let mut movers: Vec<&Value> = vec![actor];
            movers.extend(actor["attached"].as_array().unwrap().iter().map(unit_of));
            let (mut radii, mut radii_m) = (Vec::new(), Vec::new());
            let mut shapes = Vec::new();
            for m in &movers {
                for r in m["radii"].as_array().unwrap() {
                    radii.push(r.as_f64().unwrap() / IN2M);
                    radii_m.push(r.as_f64().unwrap());
                    shapes.push(shape_of(m));
                }
            }
            // `_external_obstacle_shapes` :6676 — every other on-table unit.
            let mut ext = Vec::new();
            for u in &units {
                if movers.iter().any(|m| m["id"] == u["id"])
                    || u["dormant"] == true || u["aircraft"] == true {
                    continue;
                }
                for (i, p) in u["positions"].as_array().unwrap().iter().enumerate() {
                    ext.push(Disc {
                        c: [p[0].as_f64().unwrap() / IN2M + board[0] * 0.5,
                            p[2].as_f64().unwrap() / IN2M + board[1] * 0.5],
                        r: u["radii"][i].as_f64().unwrap() / IN2M,
                        shape: shape_of(u),
                    });
                }
            }
            let rule = |name: &str| actor["rules"].as_array().unwrap().iter()
                .any(|r| r.as_str().unwrap_or("").starts_with(name));
            let terrain = Terrain::build(&serde_json::from_value(case["terrain"].clone()).unwrap());
            let gate = &pin["gate"];
            let planned_in = conv(&gate["in"], board);
            let planned: Vec<V2> = planned_in.iter().map(|p| [p[0] as f32, p[1] as f32]).collect();
            let start_world: Vec<geom::V3> = gate["start"].as_array().unwrap().iter()
                .map(|p| [p[0].as_f64().unwrap() as f32, p[1].as_f64().unwrap() as f32,
                          p[2].as_f64().unwrap() as f32]).collect();
            let caps: Vec<f64> = gate["caps"].as_array().unwrap().iter()
                .map(|c| c.as_f64().unwrap() / IN2M).collect();
            let flags = GateFlags { start_world: &start_world, rules_epoch: EPOCH_6_TABLE_RULES,
                shapes: &shapes, flying: rule("Flying"), traversal: rule("Traversal"),
                radii_m: &radii_m, ..Default::default() };
            let (got, _) = finalize_placement(&planned, &radii, &ext, &caps, board,
                Some(&terrain), flags);
            let got: Vec<[f64; 2]> = got.iter().map(|p| [p[0] as f64, p[1] as f64]).collect();
            let want = conv(&gate["out"], board);
            for i in 0..got.len() {
                let d = dist(got[i], want[i]);
                if d > 1e-6 {
                    say(format!("{id}:   model {i}: whole gate residue {d:.9}in"));
                }
            }
            let delta = worst(&got, &want);
            say(format!("{id}: whole gate residue {delta:.9}in (bound {gate_bound})"));
            if delta > gate_bound {
                fails.push(format!("{id}: whole gate differs by {delta:.9}in (bound {gate_bound})"));
            }
            // The overlap push, replayed on the table's own post-projection config.
            let mut cfg: Vec<Disc> = conv(&pin["overlap"]["in"], board).iter().enumerate()
                .map(|(i, c)| Disc { c: *c, r: radii[i], shape: shapes[i] }).collect();
            let mut rep = GateReport { disp_in: vec![0.0; radii.len()],
                capped: vec![false; radii.len()], bounds_in: 0.0,
                pulled: vec![false; radii.len()], coherent: true,
                reverted: vec![false; radii.len()] };
            let w = overlap_pass(&mut cfg, &planned_in, &caps, true, &ext, &radii_m, board, &mut rep);
            // The push's own output is a world config; measure it in the
            // table's frame (float32 against float32), and report the inch
            // mirror the gate carries on separately (the f32-inch API floor).
            let out_w: Vec<[f64; 2]> = pin["overlap"]["out"].as_array().unwrap().iter()
                .map(|p| [p[0].as_f64().unwrap() as f32 as f64, p[2].as_f64().unwrap() as f32 as f64])
                .collect();
            let got_w: Vec<[f64; 2]> = w.iter().map(|d| [d.c[0] as f64, d.c[1] as f64]).collect();
            for i in 0..got_w.len() {
                let dw = dist(got_w[i], out_w[i]) / IN2M;
                let dm = dist(cfg[i].c, conv(&pin["overlap"]["out"], board)[i]);
                if dw > 1e-9 || dm > 1e-9 || rep.capped[i] {
                    say(format!("{id}:   model {i}: push residue world {dw:.9}in mirror {dm:.9}in capped={}", rep.capped[i]));
                }
            }
            let delta = worst(&got_w, &out_w) / IN2M;
            say(format!("{id}: overlap push residue {delta:.9}in (bound {overlap_bound})"));
            if delta > overlap_bound {
                fails.push(format!("{id}: overlap push differs by {delta:.9}in (bound {overlap_bound})"));
            }
            // The whole-unit shorten, replayed on the table's own input.
            if let Some(shorten) = pin["shorten"].as_object() {
                let cfg: Vec<Disc> = conv(&shorten["in"], board).iter().enumerate()
                    .map(|(i, c)| Disc { c: *c, r: radii[i], shape: shapes[i] }).collect();
                let out = shorten_to_legal(&start_world, &cfg, &ext, board, Some(&terrain),
                    crate::mv::MAX_CHAIN_IN);
                let out: Vec<[f64; 2]> = out.iter().map(|d| d.c).collect();
                let delta = worst(&out, &conv(&shorten["out"], board));
                say(format!("{id}: whole-unit shorten residue {delta:.9}in (bound {shorten_bound})"));
                if delta > shorten_bound {
                    fails.push(format!("{id}: whole-unit shorten differs by {delta:.9}in (bound {shorten_bound})"));
                }
            }
        }
        assert!(fails.is_empty(), "{}", fails.join("\n"));
    }
}

/// The skirmish systems' 6" chain (`CoherencyChecker` :18) on the PLAIN gate
/// arm, pinned on the fixture the Stage A harness measures that bucket with.
#[cfg(test)]
mod skirmish_chain {
    use super::*;
    use serde_json::Value;

    /// `generated-skirmish-chain`'s acting unit: six 32 mm bases 1.7 in apart,
    /// 7.24 in of EDGE spread — inside the 9 in chain, over the 6 in one.
    fn pinned_line() -> (Vec<V2>, Vec<f64>, Vec<geom::V3>) {
        let fixtures: Value = serde_json::from_str(include_str!(
            "../../../../test/fixtures/position_parity/cases.json")).unwrap();
        let case = fixtures["cases"].as_array().unwrap().iter()
            .find(|c| c["id"] == "generated-skirmish-chain").unwrap();
        let unit = &case["units"][0];
        assert_eq!(unit["game_system"], "gff", "fixture must stay a skirmish system");
        let board = [case["board_in"][0].as_f64().unwrap(),
                     case["board_in"][1].as_f64().unwrap()];
        let points = unit["positions"].as_array().unwrap();
        let planned = points.iter()
            .map(|p| [(p[0].as_f64().unwrap() / IN2M + board[0] * 0.5) as f32,
                      (p[2].as_f64().unwrap() / IN2M + board[1] * 0.5) as f32])
            .collect();
        let world = points.iter()
            .map(|p| [p[0].as_f64().unwrap() as f32, 0.0, p[2].as_f64().unwrap() as f32])
            .collect();
        let radii = unit["radii"].as_array().unwrap().iter()
            .map(|r| r.as_f64().unwrap() / IN2M).collect();
        (planned, radii, world)
    }

    #[test]
    fn the_ladder_reads_the_acting_unit_chain() {
        let (planned, radii, _) = pinned_line();
        let shapes = vec![BaseShape::Round; planned.len()];
        let flags = |chain| GateFlags { shapes: &shapes, coherent_chain_in: chain,
            rules_epoch: EPOCH_6_TABLE_RULES, ..Default::default() };
        assert!(coherent_placement(&planned, &radii, flags(0.0)), "9 in holds this spread");
        assert!(!coherent_placement(&planned, &radii, flags(crate::mv::SKIRMISH_CHAIN_IN)),
            "a skirmish unit is over-spread at 6 in");
    }

    #[test]
    fn a_banded_skirmish_advance_collapses_to_the_start() {
        // The reference table's own answer for this fixture: the unit is
        // over-spread at every reach, the band leaves no slack for the
        // straggler pull, so the whole-unit shorten falls back to t = 0.
        let (start, radii, world) = pinned_line();
        let shapes = vec![BaseShape::Round; start.len()];
        let advanced: Vec<V2> = start.iter().map(|p| [p[0] + 6.0, p[1]]).collect();
        // `SoloController.GATE_SLACK_EPS_IN` :159 — all a spent band leaves.
        let caps = vec![0.05; start.len()];
        let gate = |rules_epoch| {
            let flags = GateFlags { start_world: &world, shapes: &shapes,
                chain_in: crate::mv::SKIRMISH_CHAIN_IN, rules_epoch, ..Default::default() };
            finalize_placement(&advanced, &radii, &[], &caps, [72.0, 48.0], None, flags).0
        };
        for (i, (got, want)) in gate(EPOCH_6_TABLE_RULES).iter().zip(&start).enumerate() {
            let gap = ((got[0] as f64 - want[0] as f64).powi(2)
                + (got[1] as f64 - want[1] as f64).powi(2)).sqrt();
            assert!(gap < 0.0001, "model {i} must hold at its start: {gap:.6}in off");
        }
        // Replays below the table-rules epoch keep the 9 in chain and the move.
        let below = gate(EPOCH_6_TABLE_RULES - 1);
        assert!((below[0][0] as f64 - advanced[0][0] as f64).abs() < 0.0001,
            "the earlier epoch must keep the full advance");
    }
}

/// The table's frame operations, pinned on values the reference table itself
/// printed. Every recorded case carries the acting unit's models in BOTH
/// frames: `units[].positions` are the node positions (world metres) that
/// `_plan_move` :6247 turned into the planner input `formation_call.model_pos`
/// (inches), and `endpoint_localisation`'s `gate.in` is :6378's world output of
/// the recorded `formation_call.planned` for every model the distance-truth
/// trim (:4901) left alone. Both must agree BIT FOR BIT: the frame is the
/// table's arithmetic, not an approximation of it. An f64 conversion cast at
/// the end lands a float32 unit in the last place off on a third of them.
#[cfg(test)]
mod frame_tests {
    use super::*;
    use serde_json::Value;

    fn n(v: &Value) -> f64 { v.as_f64().unwrap() }

    fn fixtures() -> Value {
        serde_json::from_str(include_str!(
            "../../../../test/fixtures/position_parity/cases.json")).unwrap()
    }

    fn board_of(case: &Value) -> [f64; 2] {
        [n(&case["board_in"][0]), n(&case["board_in"][1])]
    }

    /// `_moving_models`: the actor's models, then each attached hero's.
    fn mover_world(case: &Value) -> Vec<[f32; 2]> {
        let units: Vec<&Value> = case["units"].as_array().unwrap().iter().collect();
        let unit_of = |key: &Value| *units.iter().find(|u| u["id"] == *key).unwrap();
        let actor = unit_of(&case["action"]["unit"]);
        let mut movers = vec![actor];
        movers.extend(actor["attached"].as_array().unwrap().iter().map(unit_of));
        movers.iter().flat_map(|m| m["positions"].as_array().unwrap().iter()
            .map(|p| [n(&p[0]) as f32, n(&p[2]) as f32])).collect()
    }

    #[test]
    fn world_to_inch_reproduces_the_recorded_planner_input() {
        let fixtures = fixtures();
        let (mut total, mut off) = (0usize, Vec::new());
        for case in fixtures["cases"].as_array().unwrap() {
            let Some(call) = case.get("formation_call") else { continue };
            let (board, world) = (board_of(case), mover_world(case));
            let recorded = call["model_pos"].as_array().unwrap();
            assert_eq!(world.len(), recorded.len(), "{}: mover count", case["id"]);
            for (i, (w, q)) in world.iter().zip(recorded).enumerate() {
                total += 1;
                let want = [n(&q[0]) as f32, n(&q[1]) as f32];
                let got = from_world_f32(*w, board);
                if got != want {
                    off.push(format!("{} model {i}: got {got:?} want {want:?}", case["id"]));
                }
            }
        }
        assert!(total >= 1000, "the recorded half must be present: {total} models");
        assert!(off.is_empty(), "{} of {total} recorded planner inputs differ from \
            world->inch; first: {}", off.len(), off[0]);
    }

    #[test]
    fn inch_to_world_reproduces_the_table_gate_input() {
        let fixtures = fixtures();
        let pins: Value = serde_json::from_str(include_str!(
            "../../../../test/fixtures/position_parity/endpoint_localisation.json")).unwrap();
        let (mut total, mut off) = (0usize, Vec::new());
        // recorded-162's first gate call is the 6 in difficult-terrain re-plan,
        // not the recorded full-band call (the ledger's pre-gate stage).
        for id in ["recorded-037", "recorded-128"] {
            let case = fixtures["cases"].as_array().unwrap().iter()
                .find(|c| c["id"] == id).unwrap();
            let (board, call) = (board_of(case), &case["formation_call"]);
            let band_in = n(&case["action"]["band_in"]);
            let gate_in = pins["cases"][id]["gate"]["in"].as_array().unwrap();
            let planned = call["planned"].as_array().unwrap();
            assert_eq!(planned.len(), gate_in.len(), "{id}: model count");
            let mut pinned = 0;
            for (i, (p, g)) in planned.iter().zip(gate_in).enumerate() {
                // :4901 — a leg longer than the budget is trimmed and its
                // endpoint rewritten; only the untouched legs pin the frame.
                let leg = call["trails"][i].as_array().unwrap();
                let len_in: f64 = leg.windows(2).map(|w|
                    (n(&w[1][0]) - n(&w[0][0])).hypot(n(&w[1][1]) - n(&w[0][1]))).sum();
                if len_in * IN2M > band_in * IN2M + 0.0005 {
                    continue;
                }
                pinned += 1;
                let want = [n(&g[0]) as f32, n(&g[2]) as f32];
                let got = to_world_f32([n(&p[0]) as f32, n(&p[1]) as f32], board);
                if got != want {
                    off.push(format!("{id} model {i}: got {got:?} want {want:?}"));
                }
            }
            assert!(pinned >= 10, "{id}: only {pinned} untrimmed models");
            total += pinned;
        }
        assert!(off.is_empty(), "{} of {total} gate inputs differ from inch->world; \
            first: {}", off.len(), off[0]);
    }

    #[test]
    fn world_disc_keeps_footprint_and_lands_within_one_ulp() {
        let fixtures = fixtures();
        let mut worst = 0.0f64;
        for case in fixtures["cases"].as_array().unwrap() {
            let board = board_of(case);
            for u in case["units"].as_array().unwrap() {
                let shape = if u["base_shape"] == "oval" {
                    BaseShape::Oval { w_mm: n(&u["base_w_mm"]), d_mm: n(&u["base_d_mm"]), yaw: 0.0 }
                } else { BaseShape::Round };
                for (i, p) in u["positions"].as_array().unwrap().iter().enumerate() {
                    let w = [n(&p[0]) as f32, n(&p[2]) as f32];
                    let d = WorldDisc { c: w, r_m: n(&u["radii"][i]), shape }.to_disc(board);
                    let back = WorldDisc::from_disc(&d, board);
                    assert_eq!(back.shape, shape);
                    // The inch radius is not an exact carrier for the metre one:
                    // 0.03 / IN2M * IN2M is one f64 ULP short. Metres stay the truth.
                    assert!((back.r_m - n(&u["radii"][i])).abs() <= 1e-16, "{}", back.r_m);
                    worst = worst.max(((back.c[0] - w[0]) as f64).hypot((back.c[1] - w[1]) as f64));
                }
            }
        }
        // ~1 float32 ULP of a world metre at board scale; the inverse is not exact.
        assert!(worst <= 2.5e-7, "world -> inch -> world moved a centre by {worst:.3e} m");
    }
}

// DIAGNOSTIC (test builds only) — replay recorded-026 with the gate trace on.
// Inert unless NML_GATE_TRACE_FILE names a file; then every gate input, push
// iteration, escape, pull sweep and nudge of the case is appended to it.
#[cfg(test)]
mod push_trace_026 {
    use super::*;
    use serde_json::{json, Value};
    use std::{collections::HashMap, rc::Rc};

    #[test]
    fn trace_recorded_026_charge() {
        let fixtures: Value = serde_json::from_str(include_str!(
            "../../../../test/fixtures/position_parity/cases.json")).unwrap();
        let case = fixtures["cases"].as_array().unwrap().iter()
            .find(|c| c["id"] == "recorded-026").unwrap();
        let mut profiles = crate::state::Profiles { list: vec![], index: HashMap::new() };
        let mut units = serde_json::Map::new();
        for spec in case["units"].as_array().unwrap() {
            let key = spec["id"].as_str().unwrap().to_string();
            let mut profile = spec.clone();
            profile["unit_id"] = json!(key);
            profile["name"] = json!(key);
            profile["quality"] = json!(4);
            profile["defense"] = json!(4);
            profile["model_count"] = json!(spec["positions"].as_array().unwrap().len());
            profile["special_rules"] = spec["rules"].clone();
            profiles.index.insert(key.clone(), profiles.list.len());
            profiles.list.push(serde_json::from_value(profile).unwrap());
            let mut unit = spec.clone();
            unit["alive"] = json!(spec["positions"].as_array().unwrap().len());
            units.insert(key, unit);
        }
        let mut cache = crate::state::ProfileCache::new(Rc::new(profiles));
        let state = crate::io::state_from_json(&json!({"units": units, "round": case["round"],
            "rounds_total": 4}).to_string(), &mut cache, &mut None).unwrap();
        let terrain = Terrain::build(&serde_json::from_value(case["terrain"].clone()).unwrap());
        let actor = state.roster.index["u01"];
        let target = state.roster.index["u17"];
        TRACE.with(|t| t.set(true));
        let mut land = crate::mv::step::MoveRules { rules_epoch: 6 }
            .charge_move(&state, &terrain, actor, target, 16.0, true, true, 320).unwrap();
        let snap = land.snap_charge(&state, target, 6);
        tr(format!("snap {snap:?} budget={} arc={}", land.budget_in, land.arc_in));
        for (i, e) in land.end.iter().enumerate() {
            tr(format!("end {i} {e:?}"));
        }
        TRACE.with(|t| t.set(false));
    }
}
