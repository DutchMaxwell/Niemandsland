//! `SoloController._finalize_placement` solo_controller.gd:6371 — PASSES 1 AND
//! 2: the per-axis BOUNDS clamp (:6383-6390) and the base-OVERLAP push
//! (`_resolve_overlaps_world` :6716, itself `SeparationResolver.resolve_overlaps`
//! separation_resolver.gd:98 run per model), both spending the per-model
//! displacement budget `_gate_disp_caps_m` :6343 hands in.
//!
//! NOT here, so the seam is not read as more than it is: pass 3, the projection
//! out of forbidden terrain (:6402-6412), and pass 4, the straggler coherency
//! pull with the whole-unit shorten and the wall clamp (:6448-6465). Both slot
//! in around this file's one entry without moving it.
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

use super::geom2::V2;
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

/// `_finalize_placement` :6371, passes 1 and 2, over ONE unit's planned
/// endpoints. `external` is `_external_obstacle_shapes` :6676 — every OTHER
/// on-table unit's alive-model base. `caps_in` is `_gate_disp_caps_m`'s output;
/// a length other than `planned`'s means UNCAPPED, the same guard the GDScript
/// reads at :6398 (a charge passes none).
pub fn finalize_placement(
    planned: &[V2],
    radii_in: &[f64],
    external: &[Disc],
    caps_in: &[f64],
    board_in: [f64; 2],
) -> (Vec<V2>, GateReport) {
    let n = planned.len();
    let mut rep = GateReport {
        disp_in: vec![0.0; n],
        capped: vec![false; n],
        bounds_in: 0.0,
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
    // (overlap) :6716-6752 — Gauss-Seidel, slack-aware: the models with the most
    // band left resolve first, a model at its cap is FROZEN (it stays in every
    // neighbour's obstacle set, so the crowd walks around it), and each push is
    // truncated to the cap circle. Residual overlap between two capped models is
    // deliberately LEFT for the caller's ladder to settle at a shorter reach.
    let capped = caps_in.len() == n;
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
    let out = (0..n)
        .map(|i| {
            rep.disp_in[i] = dist(cfg[i].c, goal[i]);
            [cfg[i].c[0] as f32, cfg[i].c[1] as f32]
        })
        .collect();
    (out, rep)
}
