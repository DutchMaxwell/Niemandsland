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
//!   * non-charge skirmish's 6" chain (`CoherencyChecker` :18); charge gates
//!     select the table's system-specific chain through GateFlags.
//!
//! THE BOUNDED FIXED POINT. There is no outer `repeat` in the table: the
//! iteration lives INSIDE the passes and each bound is its own constant —
//! `OVERLAP_GATE_PASSES` 4 (:149) for the push, `COH_REPAIR_PASSES` 12 (:6555)
//! for the pull. Both loops also stop the moment a sweep moves nobody, so the
//! gate terminates on any input, pathological configurations included.
//!
//! FRAME. The table gates in world METRES; this gates in the planner's INCH
//! frame, where the endpoints already live, so a model the gate does not touch
//! keeps its endpoint bit for bit instead of picking up a metre round trip.
//! The geometry is scale-free; the four metre constants are converted once.
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

/// `SeparationResolver.RESOLVE_EPSILON_INCHES` separation_resolver.gd:46.
const RESOLVE_EPS_IN: f64 = 0.01;
/// `SeparationResolver.MAX_OVERLAP_ITERATIONS` separation_resolver.gd:55.
const MAX_OVERLAP_ITERS: usize = 24;
/// `SeparationResolver.ESCAPE_SCAN_DIRECTIONS` separation_resolver.gd:59.
const ESCAPE_DIRS: usize = 24;
/// `SeparationZone.EPSILON_M` separation_zone.gd:44 — the concentric guard.
const EPSILON_IN: f64 = 0.00001 / IN2M;
/// `SoloController.OVERLAP_GATE_PASSES` solo_controller.gd:149.
const OVERLAP_GATE_PASSES: usize = 4;
/// `SoloController.OVERLAP_EPS_M` solo_controller.gd:154 — sub-0.5 mm is noise.
const OVERLAP_EPS_IN: f64 = 0.0005 / IN2M;
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
    /// Charge coherency is 6 inches for skirmish systems, otherwise 9.
    pub charge_chain_in: f64,
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
}

fn dist(a: [f64; 2], b: [f64; 2]) -> f64 {
    ((a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2)).sqrt()
}

/// `SeparationResolver._travel_to_clear_along` separation_resolver.gd:156 — the
/// shortest slide along unit direction `u` that clears every obstacle.
fn travel_to_clear(s: &Disc, obs: &[Disc], u: [f64; 2]) -> f64 {
    let mut travel = 0.0f64;
    for o in obs {
        let r_sum = s.r + o.r;
        let e = [s.c[0] - o.c[0], s.c[1] - o.c[1]];
        let sq = e[0] * e[0] + e[1] * e[1];
        if sq >= r_sum * r_sum {
            continue;
        }
        let ed = e[0] * u[0] + e[1] * u[1];
        travel = travel.max(-ed + (ed * ed - sq + r_sum * r_sum).max(0.0).sqrt());
    }
    travel
}

/// `SeparationResolver.resolve_overlaps` separation_resolver.gd:98 for ONE item
/// base: the summed-penetration relaxation, then `_escape_to_clear` (:136), the
/// 24-ray scan that makes clearing a finite obstacle set guaranteed. Mutates
/// `s`; returns whether its centre moved at all.
fn resolve_overlaps(s: &mut Disc, obs: &[Disc]) -> bool {
    if obs.is_empty() {
        return false;
    }
    let start = s.c;
    let mut relaxed = false;
    for _ in 0..MAX_OVERLAP_ITERS {
        let (mut res, mut deepest) = ([0.0f64, 0.0], 0.0f64);
        for o in obs {
            let overlap = -edge(s, o);
            if overlap <= RESOLVE_EPS_IN {
                continue;
            }
            let mut axis = [s.c[0] - o.c[0], s.c[1] - o.c[1]];
            if axis[0] * axis[0] + axis[1] * axis[1] < EPSILON_IN * EPSILON_IN {
                axis = [1.0, 0.0]; // concentric: Vector2.RIGHT, the stable escape
            }
            let l = (axis[0] * axis[0] + axis[1] * axis[1]).sqrt();
            res = [
                res[0] + axis[0] / l * overlap,
                res[1] + axis[1] / l * overlap,
            ];
            deepest = deepest.max(overlap);
        }
        if deepest <= RESOLVE_EPS_IN {
            return relaxed; // cleared inside the relaxation cap
        }
        if (res[0] * res[0] + res[1] * res[1]).sqrt() < RESOLVE_EPS_IN {
            break; // symmetric wedge: straight to the escape scan (:118-121)
        }
        s.c = [s.c[0] + res[0], s.c[1] + res[1]];
        relaxed = true;
    }
    let mut best = (f64::INFINITY, [0.0f64, 0.0]);
    for k in 0..ESCAPE_DIRS {
        let ang = std::f64::consts::TAU * k as f64 / ESCAPE_DIRS as f64;
        let u = [ang.cos(), ang.sin()];
        let travel = travel_to_clear(s, obs, u);
        if travel < best.0 {
            best = (travel, u);
        }
    }
    if best.0 > 0.0 && best.0.is_finite() {
        s.c = [s.c[0] + best.1[0] * best.0, s.c[1] + best.1[1] * best.0];
    }
    s.c != start
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
fn cap_disp(cand: [f64; 2], goal: [f64; 2], cap: f64, i: usize, rep: &mut GateReport) -> [f64; 2] {
    let off = [cand[0] - goal[0], cand[1] - goal[1]];
    let l = (off[0] * off[0] + off[1] * off[1]).sqrt();
    if l <= cap {
        return cand;
    }
    rep.capped[i] = true;
    [goal[0] + off[0] / l * cap, goal[1] + off[1] / l * cap]
}

/// `_resolve_overlaps_world` :6716 — the slack-aware Gauss-Seidel push, its own
/// function because the table runs it TWICE: once as pass 2 and once more to
/// clear whatever pass 4's inward pulls stacked (:6636).
fn overlap_pass(cfg: &mut [Disc], goal: &[[f64; 2]], caps_in: &[f64], capped: bool,
                external: &[Disc], rep: &mut GateReport) {
    let n = cfg.len();
    for _ in 0..OVERLAP_GATE_PASSES {
        let mut order: Vec<usize> = (0..n).collect();
        if capped {
            let rem: Vec<f64> = (0..n)
                .map(|i| caps_in[i] - dist(cfg[i].c, goal[i]))
                .collect();
            // `order.sort_custom` :6737. Hand-rolled (insertion, stable, n is a
            // unit's model count) because that comparator's epsilon tie-break is
            // not a strict total order and Rust's own sort may panic on one.
            for a in 1..n {
                let v = order[a];
                let mut j = a;
                while j > 0 && {
                    let w = order[j - 1];
                    if (rem[v] - rem[w]).abs() > OVERLAP_EPS_IN {
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
        for i in order {
            if capped && caps_in[i] - dist(cfg[i].c, goal[i]) <= OVERLAP_EPS_IN {
                continue; // band-frozen (:6742)
            }
            let mut obs: Vec<Disc> = external.to_vec();
            obs.extend((0..n).filter(|&j| j != i).map(|j| cfg[j]));
            let mut s = cfg[i];
            if resolve_overlaps(&mut s, &obs) {
                moved = true;
                if capped {
                    let off = [s.c[0] - goal[i][0], s.c[1] - goal[i][1]];
                    let l = (off[0] * off[0] + off[1] * off[1]).sqrt();
                    if l > caps_in[i] {
                        s.c = [
                            goal[i][0] + off[0] / l * caps_in[i],
                            goal[i][1] + off[1] / l * caps_in[i],
                        ];
                        rep.capped[i] = true;
                    }
                }
            }
            cfg[i] = s;
        }
        if !moved {
            break;
        }
    }
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
            cand = cap_disp(cand, self.goal[i], self.caps_in[i], i, rep);
            if dist(cand, cfg[i].c) <= OVERLAP_EPS_IN {
                return false;
            }
        }
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
        overlap_pass(cfg, self.goal, self.caps_in, self.capped, self.external, rep);
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
    let max_chain = if charge && flags.charge_chain_in > 0.0 {
        flags.charge_chain_in
    } else { super::MAX_CHAIN_IN };
    let capped = !charge && caps_in.len() == n;
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
    overlap_pass(&mut cfg, &goal, caps_in, capped, external, &mut rep);
    // (coherency) :6444-6465 — PASS 4. The table keeps the full move when the
    // config is coherent AND overlap-free AND terrain-clear, and otherwise runs
    // the straggler repair before falling back to the whole-unit shorten. The
    // repair itself returns at once on a coherent config. The whole-unit
    // fallback below also checks overlap and forbidden rest ground.
    if !config_coherent(&cfg, max_chain) {
        let pull = Pull { max_chain, rules_epoch: flags.rules_epoch, goal: &goal, caps_in, capped, board_in, terrain, external };
        rep.coherent = pull.run(&mut cfg, &mut rep);
    }
    if !charge && n > 1 && flags.start_world.len() == n
        && rule_on(flags.rules_epoch, EPOCH_6_TABLE_RULES)
        && !config_legal(&cfg, external, terrain)
    {
        cfg = shorten_to_legal(flags.start_world, &cfg, external, board_in, terrain);
        rep.coherent = config_coherent(&cfg, super::MAX_CHAIN_IN);
    }
    clamp_gate_walls(&mut cfg, &goal, external, flags, terrain, &mut rep);
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
fn config_legal(cfg: &[Disc], external: &[Disc], terrain: Option<&Terrain>) -> bool {
    config_coherent(cfg, super::MAX_CHAIN_IN)
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
                    board_in: [f64; 2], terrain: Option<&Terrain>) -> Vec<Disc> {
    if config_legal(cfg, external, terrain) {
        return cfg.to_vec();
    }
    let (mut lo, mut hi) = (0.0, 1.0);
    for _ in 0..16 {
        let mid = (lo + hi) * 0.5;
        let candidate = blend_from_start(start_world, cfg, mid, board_in);
        if config_legal(&candidate, external, terrain) { lo = mid; } else { hi = mid; }
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
        let got = shorten_to_legal(&start, &cfg, &external, board, Some(&terrain));
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
