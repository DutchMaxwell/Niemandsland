//! NML-1073 M4-5 — `MovementPlanner.solve_formation` (movement_planner.gd:1583),
//! the four projections it sweeps, the weighted `_formation_score` (:1615) and
//! the radii-aware coherency leaves (:1653-1704). A LITERAL transcription.
//!
//! THE SOLVER IS THE SAFETY NET, not the placer. It starts from the sequential
//! flow's already-mostly-legal endpoints and runs `SOLVE_PASSES` = 24 sweeps of
//! four projections — zones, separation, terrain, coherency — keeping the
//! LEAST-VIOLATING configuration it ever saw. Three details decide parity:
//!
//!   * THE BEST-OF RULE (:1594-1607). The score is taken ONCE before the loop;
//!     a score of `<= EPS` returns `desired` untouched, and inside the loop a
//!     pass is only adopted when it beats the incumbent by MORE than EPS. So
//!     the returned array is not "the last pass" — it is the best pass, and on
//!     a corpus where 450 of 655 solving calls run all 24 sweeps the difference
//!     is routine.
//!   * GAUSS-SEIDEL (:1712-1737). `_project_separate` writes `out[i]` and
//!     `out[j]` in the middle of the pair loop, so every later pair reads the
//!     already-pushed positions; `_project_out_of_zones` likewise carries `p`
//!     forward through the zone list. Reversing either order changes the
//!     answer — see the red proof in `tests/mv_form.rs`.
//!   * `forbid_cells` (:1588) IS READ HERE AND NOWHERE ELSE. The step layer
//!     prices `avoid_cells` / `avoid_fine`; the REST constraint (a model may
//!     not finish inside Impassable/Dangerous) lives only in this file, in
//!     `formation_score` and `project_out_of_terrain`. A charge drops the set
//!     entirely (`{} if allow_contact`).
//!
//! PRECISION. Positions are `Vector2` = f32; every score term, radius sum,
//! penalty and distance is a GDScript `float` = f64. `_wall_zone_blocked`
//! (:1560) is `step_blocked` MINUS the avoid-cell tests — a model may legally
//! REST in Difficult, so only walls and spacing discs are inviolable here.

use super::cost::{cell_of, wall_blocks, zone_blocks, CellSet, Wall, Zone};
use super::geom2::{
    add, distance_to, div, length, mul, normalized, path_crosses_wall, sub, world_before, V2,
};
use super::io::MoveCall;
use super::pull::board_clamp;
use super::theta::board_extents;
use super::{
    COH_PULL_IN, EPS, LINK_IN, MAX_CHAIN_IN, PLAN_CELL_IN, RADIAL_DIRS, SOLVE_PASSES,
    SPREAD_IN, TERRAIN_PUSH_MAX_IN, TERRAIN_PUSH_STEP_IN, W_COHERENCY, W_OVERLAP, W_TERRAIN, W_ZONE,
};

/// `TAU` — Godot's `Math_TAU`, the value `_nearest_clear_of_terrain` (:1822) and
/// `_difficult_at_point` (:889) both step around a circle with.
pub const TAU: f64 = std::f64::consts::TAU;

/// The `opts` keys `solve_formation` and its projections read —
/// solo_controller.gd:5979-6033. NOTE `zones` is the FULL recorded list: the
/// sequential flow's `fast_planner` reach cull (movement_planner.gd:1058) is a
/// flow-local variable and never reaches the solver.
#[derive(Clone, Copy, Debug)]
pub struct SolveOpts<'a> {
    /// `opts["clearance"]` — read by `_wall_zone_blocked` (:1561).
    pub clearance: f64,
    /// `opts["zones"]` (:1589) — scored AND projected out of.
    pub zones: &'a [Zone],
    /// `opts["forbid_cells"]` (:1588) — the REST-position set, this file only.
    pub forbid_cells: &'a CellSet,
    /// `opts["board_y_in"]` (#215) — folded into `board_extents` at :1590.
    pub board_y_in: f64,
}

impl<'a> SolveOpts<'a> {
    /// The options one recorded call was made with.
    pub fn of(call: &'a MoveCall) -> SolveOpts<'a> {
        SolveOpts {
            clearance: call.opts.clearance,
            zones: &call.opts.zones,
            forbid_cells: &call.opts.forbid_cells,
            board_y_in: call.opts.board_y_in,
        }
    }
}

/// DELIBERATE DAMAGE, for the red proofs — every field at its shipped value is
/// the shipped solver, byte for byte. Same convention as `FlowBend`.
#[derive(Clone, Copy, Debug)]
pub struct FormBend {
    /// `SOLVE_PASSES` — movement_planner.gd:74. Shipped: 24.
    pub solve_passes: i64,
    /// RED: sweep `_project_separate`'s pairs from the far end, so the
    /// Gauss-Seidel chain runs backwards (movement_planner.gd:1716-1717).
    pub reverse_pairs: bool,
}

impl Default for FormBend {
    fn default() -> Self {
        FormBend { solve_passes: SOLVE_PASSES, reverse_pairs: false }
    }
}

impl FormBend {
    pub fn active(&self) -> bool {
        self.solve_passes != SOLVE_PASSES || self.reverse_pairs
    }
}

/// One recorded sweep — `MoveRecorder.trace_solve_pass` (move_recorder.gd:208):
/// the positions AFTER that pass's four projections and its violation score.
#[derive(Clone, Debug)]
pub struct FormPass {
    pub positions: Vec<V2>,
    pub score: f64,
}

/// What `solve_formation` produced, plus the trace channel the corpus recorded.
#[derive(Clone, Debug, Default)]
pub struct FormResult {
    /// The returned array — the LEAST-VIOLATING configuration seen.
    pub best: Vec<V2>,
    /// One entry per executed sweep, in order. EMPTY when the desired formation
    /// already scored `<= EPS` and the solver returned at :1596.
    pub passes: Vec<FormPass>,
}

/// `MovementPlanner._wall_zone_blocked` — movement_planner.gd:1560. `step_blocked`
/// minus the avoid-cell tests: a model may legally REST in Difficult, so only
/// walls (base-inflated when a clearance is given) and no-go discs may veto a
/// projection step.
pub fn wall_zone_blocked(p: V2, c: V2, walls: &[Wall], clearance: f64, zones: &[Zone]) -> bool {
    if clearance > 0.0 {
        for w in walls {
            if wall_blocks(p, c, w[0], w[1], clearance) {
                return true;
            }
        }
    } else if path_crosses_wall(p, c, walls) {
        return true;
    }
    for z in zones {
        if zone_blocks(p, c, z.c, z.r) {
            return true;
        }
    }
    false
}

// === the radii-aware coherency leaves (movement_planner.gd:1648-1704) ========

/// `MovementPlanner._linked_r` — movement_planner.gd:1648. Re-exported from
/// `flow` so both stages read one truth.
pub use super::flow::linked_r;

/// `MovementPlanner._are_linked` — movement_planner.gd:287, the POINT-SPACE
/// fallback used when the radii array does not align with the positions.
#[inline]
pub fn are_linked(a: V2, b: V2) -> bool {
    distance_to(a, b) <= LINK_IN
}

/// `MovementPlanner._components_r` — movement_planner.gd:1653. A stack walk
/// (`queue.pop_back()`), so this is a DFS despite the name; only the component
/// SIZES leave the function, but the traversal is transcribed as written.
pub fn components_r(out: &[V2], radii: &[f64]) -> Vec<Vec<usize>> {
    components_inner(out, Some(radii))
}

/// `MovementPlanner._components` — movement_planner.gd:293, the point-space twin.
pub fn components(out: &[V2]) -> Vec<Vec<usize>> {
    components_inner(out, None)
}

fn components_inner(out: &[V2], radii: Option<&[f64]>) -> Vec<Vec<usize>> {
    let n = out.len();
    let mut visited = vec![false; n];
    let mut comps: Vec<Vec<usize>> = Vec::new();
    for start in 0..n {
        if visited[start] {
            continue;
        }
        let mut comp = vec![start];
        let mut queue = vec![start];
        visited[start] = true;
        while let Some(cur) = queue.pop() {
            for other in 0..n {
                if visited[other] || other == cur {
                    continue;
                }
                let link = match radii {
                    Some(r) => linked_r(out[cur], out[other], r[cur], r[other]),
                    None => are_linked(out[cur], out[other]),
                };
                if link {
                    visited[other] = true;
                    queue.push(other);
                    comp.push(other);
                }
            }
        }
        comps.push(comp);
    }
    comps
}

/// `MovementPlanner._largest` — movement_planner.gd:318. FIRST largest wins.
pub fn largest(comps: &[Vec<usize>]) -> &Vec<usize> {
    let mut best = &comps[0];
    for c in comps {
        if c.len() > best.len() {
            best = c;
        }
    }
    best
}

/// `MovementPlanner._max_edge_spread_r` — movement_planner.gd:1679. The widest
/// EDGE-to-edge gap of any pair; `maxf` over f64.
pub fn max_edge_spread_r(out: &[V2], radii: &[f64]) -> f64 {
    let mut worst = 0.0f64;
    for i in 0..out.len() {
        for j in (i + 1)..out.len() {
            let edge = distance_to(out[i], out[j]) - radii[i] - radii[j];
            worst = worst.max(edge);
        }
    }
    worst
}

/// `MovementPlanner._spread` — movement_planner.gd:327, the point-space twin.
pub fn spread(out: &[V2]) -> f64 {
    let mut worst = 0.0f64;
    for i in 0..out.len() {
        for j in (i + 1)..out.len() {
            worst = worst.max(distance_to(out[i], out[j]));
        }
    }
    worst
}

/// `MovementPlanner._coherency_penalty` — movement_planner.gd:1690. Models
/// outside the largest link component count ONE each; an over-spread adds the
/// inches over `MAX_CHAIN_IN`.
pub fn coherency_penalty(out: &[V2], radii: &[f64]) -> f64 {
    if out.len() <= 1 {
        return 0.0;
    }
    let use_r = radii.len() == out.len();
    let mut pen = 0.0f64;
    let comps = if use_r { components_r(out, radii) } else { components(out) };
    if comps.len() > 1 {
        pen += (out.len() - largest(&comps).len()) as f64;
    }
    let over = if use_r {
        max_edge_spread_r(out, radii) - MAX_CHAIN_IN
    } else {
        spread(out) - SPREAD_IN
    };
    if over > 0.0 {
        pen += over;
    }
    pen
}

// === the score (movement_planner.gd:1615) ===================================

/// `MovementPlanner._formation_score` — movement_planner.gd:1615. The weighted
/// violation sum, accumulated in f64 IN THIS ORDER: terrain rests, then the
/// coherency penalty, then every overlapping own pair, then every zone dip.
/// Zero means fully legal, and `solve_formation` short-circuits on it.
pub fn formation_score(out: &[V2], radii: &[f64], forbid: &CellSet, zones: &[Zone]) -> f64 {
    let mut score = 0.0f64;
    if !forbid.is_empty() {
        for p in out {
            if forbid.contains(&cell_of(*p, PLAN_CELL_IN)) {
                score += W_TERRAIN;
            }
        }
    }
    score += coherency_penalty(out, radii) * W_COHERENCY;
    if radii.len() == out.len() {
        for i in 0..out.len() {
            for j in (i + 1)..out.len() {
                let overlap = radii[i] + radii[j] - distance_to(out[i], out[j]);
                if overlap > EPS {
                    score += overlap * W_OVERLAP;
                }
            }
        }
    }
    for z in zones {
        for p in out {
            let pen = z.r - distance_to(*p, z.c);
            if pen > EPS {
                score += pen * W_ZONE;
            }
        }
    }
    score
}

// === the four projections ===================================================

/// `MovementPlanner._project_out_of_zones` — movement_planner.gd:1706. Radially
/// out to the zone edge. `p` is CARRIED through the zone list, so a model
/// pushed out of one disc is tested against the next from its new spot.
pub fn project_out_of_zones(
    out: &mut [V2],
    zones: &[Zone],
    walls: &[Wall],
    clearance: f64,
    opt_zones: &[Zone],
    board: V2,
) {
    if zones.is_empty() {
        return;
    }
    for i in 0..out.len() {
        let mut p = out[i];
        for z in zones {
            let d = distance_to(p, z.c);
            if d >= z.r - EPS {
                continue;
            }
            let dir = sub(p, z.c);
            let dir = if length(dir) > EPS { normalized(dir) } else { [1.0, 0.0] };
            let cand = board_clamp(add(z.c, mul(dir, z.r + EPS)), board);
            if !wall_zone_blocked(p, cand, walls, clearance, opt_zones) {
                p = cand;
            }
        }
        out[i] = p;
    }
}

/// `MovementPlanner._project_separate` — movement_planner.gd:1712. ONE
/// Gauss-Seidel sweep: each pair reads `out[i]`/`out[j]` fresh, so a push made
/// earlier in the sweep is visible to every later pair. Both halves of a push
/// are wall/zone-gated INDEPENDENTLY — one model may move while the other stays.
pub fn project_separate(
    out: &mut [V2],
    radii: &[f64],
    walls: &[Wall],
    clearance: f64,
    opt_zones: &[Zone],
    board: V2,
    reverse_pairs: bool,
) {
    let n = out.len();
    if n <= 1 || radii.len() != n {
        return;
    }
    let mut pairs: Vec<(usize, usize)> = Vec::with_capacity(n * (n - 1) / 2);
    for i in 0..n {
        for j in (i + 1)..n {
            pairs.push((i, j));
        }
    }
    if reverse_pairs {
        pairs.reverse();
    }
    for (i, j) in pairs {
        let pi = out[i];
        let pj = out[j];
        let min_gap = radii[i] + radii[j];
        let d = distance_to(pi, pj);
        if d >= min_gap - EPS {
            continue;
        }
        let dir = sub(pj, pi);
        let dir = if length(dir) > EPS { normalized(dir) } else { [1.0, 0.0] };
        let push = (min_gap - d) * 0.5 + EPS;
        let ci = board_clamp(sub(pi, mul(dir, push)), board);
        let cj = board_clamp(add(pj, mul(dir, push)), board);
        if !wall_zone_blocked(pi, ci, walls, clearance, opt_zones) {
            out[i] = ci;
        }
        if !wall_zone_blocked(pj, cj, walls, clearance, opt_zones) {
            out[j] = cj;
        }
    }
}

/// `MovementPlanner._project_coherency` — movement_planner.gd:1740. One sweep:
/// pull every model outside the largest link component 1" toward its NEAREST
/// in-component neighbour, then, if the unit over-spreads, pull the model
/// furthest from the centroid 1" inward.
pub fn project_coherency(
    out: &mut [V2],
    radii: &[f64],
    walls: &[Wall],
    clearance: f64,
    opt_zones: &[Zone],
    board: V2,
) {
    let n = out.len();
    if n <= 1 || radii.len() != n {
        return;
    }
    let comps = components_r(out, radii);
    if comps.len() > 1 {
        let main = largest(&comps).clone();
        let in_main: Vec<bool> = {
            let mut v = vec![false; n];
            for &idx in &main {
                v[idx] = true;
            }
            v
        };
        for i in 0..n {
            if in_main[i] {
                continue;
            }
            let mut nearest: i64 = -1;
            let mut nd = f64::INFINITY;
            for &m in &main {
                let d = distance_to(out[i], out[m]);
                if d < nd {
                    nd = d;
                    nearest = m as i64;
                }
            }
            if nearest < 0 {
                continue;
            }
            let to_n = sub(out[nearest as usize], out[i]);
            let dn = length(to_n);
            if dn < EPS {
                continue;
            }
            let cand = board_clamp(add(out[i], mul(div(to_n, dn), COH_PULL_IN.min(dn))), board);
            if !wall_zone_blocked(out[i], cand, walls, clearance, opt_zones) {
                out[i] = cand;
            }
        }
    }
    if max_edge_spread_r(out, radii) > MAX_CHAIN_IN + EPS {
        let c = super::flow::centroid(out);
        let mut far: i64 = -1;
        let mut fd = -1.0f64;
        for i in 0..n {
            let d = distance_to(out[i], c);
            if d > fd {
                fd = d;
                far = i as i64;
            }
        }
        if far >= 0 {
            let f = far as usize;
            let to_c = sub(c, out[f]);
            let d = length(to_c);
            if d >= EPS {
                let cand = board_clamp(add(out[f], mul(div(to_c, d), COH_PULL_IN.min(d))), board);
                if !wall_zone_blocked(out[f], cand, walls, clearance, opt_zones) {
                    out[f] = cand;
                }
            }
        }
    }
}

/// `MovementPlanner._project_out_of_terrain` — movement_planner.gd:1806.
pub fn project_out_of_terrain(
    out: &mut [V2],
    forbid: &CellSet,
    walls: &[Wall],
    clearance: f64,
    opt_zones: &[Zone],
    board: V2,
) {
    if forbid.is_empty() {
        return;
    }
    for i in 0..out.len() {
        let p = out[i];
        if !forbid.contains(&cell_of(p, PLAN_CELL_IN)) {
            continue;
        }
        out[i] = nearest_clear_of_terrain(p, forbid, walls, clearance, opt_zones, board);
    }
}

/// `MovementPlanner._nearest_clear_of_terrain` — movement_planner.gd:1816.
/// Rings of `TERRAIN_PUSH_STEP_IN` out to `TERRAIN_PUSH_MAX_IN`, `RADIAL_DIRS`
/// compass points per ring, nearest ring first and `_world_before` inside a
/// ring. A boxed model is returned unmoved — the least-violating fallback then
/// keeps the configuration.
pub fn nearest_clear_of_terrain(
    p: V2,
    forbid: &CellSet,
    walls: &[Wall],
    clearance: f64,
    opt_zones: &[Zone],
    board: V2,
) -> V2 {
    let mut dist = TERRAIN_PUSH_STEP_IN;
    while dist <= TERRAIN_PUSH_MAX_IN + EPS {
        let mut found = false;
        let mut best_c = p;
        for k in 0..RADIAL_DIRS {
            let ang = TAU * k as f64 / RADIAL_DIRS as f64;
            // `Vector2(cos(ang), sin(ang))` narrows the two f64 results to f32
            // BEFORE the multiply, exactly as the Vector2 constructor does.
            let unit: V2 = [ang.cos() as f32, ang.sin() as f32];
            let c = board_clamp(add(p, mul(unit, dist)), board);
            if forbid.contains(&cell_of(c, PLAN_CELL_IN)) {
                continue;
            }
            if wall_zone_blocked(p, c, walls, clearance, opt_zones) {
                continue;
            }
            if !found || world_before(c, best_c) {
                best_c = c;
                found = true;
            }
        }
        if found {
            return best_c;
        }
        dist += TERRAIN_PUSH_STEP_IN;
    }
    p
}

// === the solver (movement_planner.gd:1583) ==================================

/// `MovementPlanner.solve_formation` — movement_planner.gd:1583.
///
/// Returns the BEST configuration, plus every executed sweep so a gate can
/// compare pass by pass against `trace.solve_passes`.
pub fn solve_formation(
    desired: &[V2],
    radii: &[f64],
    walls: &[Wall],
    opts: &SolveOpts,
    board_in: f64,
    allow_contact: bool,
    bend: FormBend,
) -> FormResult {
    let mut out = desired.to_vec();
    let mut res = FormResult { best: out.clone(), passes: Vec::new() };
    if out.is_empty() {
        return res;
    }
    // :1588 — a charge drops the rest-position set entirely.
    let empty: CellSet = CellSet::new();
    let forbid: &CellSet = if allow_contact { &empty } else { opts.forbid_cells };
    let zones = opts.zones;
    let board = board_extents(board_in, opts.board_y_in);
    let mut best = out.clone();
    let mut best_score = formation_score(&out, radii, forbid, zones);
    if best_score <= EPS {
        // :1596 — `return out`, i.e. `desired` verbatim, and NOT a single sweep
        // is traced.
        res.best = out;
        return res;
    }
    for _pass in 0..bend.solve_passes {
        project_out_of_zones(&mut out, zones, walls, opts.clearance, zones, board);
        project_separate(&mut out, radii, walls, opts.clearance, zones, board, bend.reverse_pairs);
        project_out_of_terrain(&mut out, forbid, walls, opts.clearance, zones, board);
        if !allow_contact {
            project_coherency(&mut out, radii, walls, opts.clearance, zones, board);
        }
        let s = formation_score(&out, radii, forbid, zones);
        res.passes.push(FormPass { positions: out.clone(), score: s });
        if s < best_score - EPS {
            best_score = s;
            best = out.clone();
        }
        if best_score <= EPS {
            break;
        }
    }
    res.best = best;
    res
}
