//! `SoloController._finalize_placement` solo_controller.gd:6371 — PASSES 1 AND
//! 2: the per-axis BOUNDS clamp (:6383-6390) and the base-OVERLAP push
//! (`_resolve_overlaps_world` :6716, itself `SeparationResolver.resolve_overlaps`
//! separation_resolver.gd:98 run per model), both spending the per-model
//! displacement budget `_gate_disp_caps_m` :6343 hands in.
//!
//! S5b adds PASS 3 in between, in the table's own order: the projection out of
//! forbidden rest ground (:6402-6412, `_project_out_forbidden_world` :6807),
//! spending the same budget. S5c adds PASS 4, the straggler coherency pull
//! (`_pull_stragglers_coherent_world` :6563).
//!
//! NOT here, so the seam is not read as more than it is, each its own rung:
//!   * the pull's CLOSING overlap push (:6636), which clears whatever the
//!     inward pulls stacked. It wants `_resolve_overlaps_world` as a function
//!     of its own; measured, it is worth 53 models on qag_ref and 6 the other
//!     way on qbg_ref, so it waits rather than inflating this one.
//!   * the WHOLE-UNIT SHORTEN (:6465), the fallback that fires only when pass 4
//!     leaves an illegal config. It blends the unit back toward `start_world`,
//!     a fourth configuration this signature does not carry, so its cases stay
//!     the caller ladder's to settle at a shorter reach.
//!   * `_clamp_gate_walls` (:6477), the anti-tunnel revert the table runs on
//!     every return path of the gate: it reads two unit rules (Flying,
//!     Traversal) this signature does not carry either.
//!   * skirmish's 6" chain (`CoherencyChecker` :18), corpus-absent and unported
//!     with the regiments, exactly as `deployment.rs:1783` says.
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
//! BASES. `State` carries one radius per model, so every base here is the round
//! one `SeparationChecker._edge_distance_meters` :294 handles exactly; an
//! oval/rect base is its circumscribed circle, which is what the escape scan
//! (:160, `bounding_radius`) uses on the table anyway.

use super::geom2::{point_seg_distance, V2};
use crate::terrain::{self, Terrain};
use crate::IN2M;

/// One base as the gate sees it: centre in the planner's INCH frame, radius in
/// inches — `SeparationChecker.BaseShape` of kind ROUND.
#[derive(Clone, Copy, Debug)]
pub struct Disc {
    pub c: [f64; 2],
    pub r: f64,
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
            let overlap = -(dist(s.c, o.c) - s.r - o.r);
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

/// `SeparationChecker.edge_distance` :294 for two ROUND bases — the one measure
/// both the coherency link and the no-stack test are written in.
fn edge(a: &Disc, b: &Disc) -> f64 {
    dist(a.c, b.c) - a.r - b.r
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

/// Everything a pass-4 sweep needs that does not change between nudges: the RAW
/// plan the band-slack circles are centred on, those caps, and the board and
/// terrain every correction is spent against.
struct Pull<'a> {
    goal: &'a [[f64; 2]],
    caps_in: &'a [f64],
    capped: bool,
    board_in: [f64; 2],
    terrain: Option<&'a Terrain>,
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
    /// (:6636) is the next rung, not this one.
    fn run(&self, cfg: &mut [Disc], rep: &mut GateReport) -> bool {
        let (n, max_chain) = (cfg.len(), super::MAX_CHAIN_IN);
        for _ in 0..COH_REPAIR_PASSES {
            if config_coherent(cfg, max_chain) {
                return true;
            }
            let main = largest_component(cfg);
            let mut moved = false;
            // (a) reconnect — nearest in-component neighbour by EDGE distance,
            // the FIRST winner on a tie (the component's own BFS order).
            for i in (0..n).filter(|i| !main.contains(i)) {
                let (mut nd, mut near) = (f64::INFINITY, usize::MAX);
                for &m in &main {
                    if edge(&cfg[i], &cfg[m]) < nd {
                        nd = edge(&cfg[i], &cfg[m]);
                        near = m;
                    }
                }
                if near == usize::MAX {
                    continue;
                }
                let (to, len) = (cfg[near].c, (nd - COH_LINK_IN).min(COH_LINK_IN));
                moved |= self.nudge(cfg, i, to, len, rep);
            }
            // (b) over-spread — pull the model furthest from the centroid in.
            if overspread(cfg, max_chain) {
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
        config_coherent(cfg, max_chain)
    }
}

/// `_finalize_placement` :6371, passes 1 to 4, over ONE unit's planned
/// endpoints. `external` is `_external_obstacle_shapes` :6676 — every OTHER
/// on-table unit's alive-model base. `caps_in` is `_gate_disp_caps_m`'s output;
/// a length other than `planned`'s means UNCAPPED, the same guard the GDScript
/// reads at :6398 (a charge passes none). `terrain` switches pass 3 on; `None`
/// is the board the recorder never wrote a terrain line for.
pub fn finalize_placement(
    planned: &[V2],
    radii_in: &[f64],
    external: &[Disc],
    caps_in: &[f64],
    board_in: [f64; 2],
    terrain: Option<&Terrain>,
) -> (Vec<V2>, GateReport) {
    let n = planned.len();
    let mut rep = GateReport {
        disp_in: vec![0.0; n],
        capped: vec![false; n],
        bounds_in: 0.0,
        pulled: vec![false; n],
        coherent: true,
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
            }
        })
        .collect();
    let capped = caps_in.len() == n;
    // (terrain) :6402-6412 — project every model out of forbidden rest ground
    // BEFORE the overlap push, so the crowd resolves around spots that are
    // already legal. A projection costing MORE than the model's band slack is
    // refused WHOLE, never truncated: a half hop would still rest inside the
    // container. The route-true spot is kept, the model is marked, and the debt
    // goes to the caller's ladder at a shorter reach — route truth wins.
    if let Some(t) = terrain {
        for i in 0..n {
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
    // (coherency) :6444-6465 — PASS 4. The table keeps the full move when the
    // config is coherent AND overlap-free AND terrain-clear, and otherwise runs
    // the straggler repair before falling back to the whole-unit shorten. The
    // repair itself returns AT ONCE on a coherent config, so for everything
    // ported here those three predicates reduce to the coherency one; the other
    // two only ever decide whether the unported shorten fires.
    if !config_coherent(&cfg, super::MAX_CHAIN_IN) {
        let pull = Pull { goal: &goal, caps_in, capped, board_in, terrain };
        rep.coherent = pull.run(&mut cfg, &mut rep);
    }
    let out = (0..n)
        .map(|i| {
            rep.disp_in[i] = dist(cfg[i].c, goal[i]);
            [cfg[i].c[0] as f32, cfg[i].c[1] as f32]
        })
        .collect();
    (out, rep)
}
