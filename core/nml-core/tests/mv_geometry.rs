//! GATE G1 (NML-1073 M4-1) — the movement solver's LEAF layer, pinned on the
//! recorded move corpus `tests/fixtures/moves_s27.jsonl` (one seed-27 arena
//! game: 1 header + 64 `MovementPlanner.plan_unit_step` calls, each with the
//! per-stage trace `NML_MOVE_TRACE=1` writes).
//!
//! WHAT THE TRACE CAN PROVE, AND HOW.
//!
//! The trace carries no predicate results and no costs — it carries the
//! GEOMETRY the GDScript produced. Every recorded artefact is therefore read as
//! an ORACLE for the predicate that produced it:
//!
//!   * `trace.flow[*].theta` with >= 3 nodes can only come from
//!     `_theta_reconstruct` (movement_planner.gd:1443), i.e. every consecutive
//!     node pair is an edge the search ACCEPTED. Both relaxation branches
//!     (movement_planner.gd:1408-1415) run `step_blocked` — the grid step
//!     directly, the parent shortcut through `_cspace_blocked` — so
//!     `step_blocked` MUST be false on every one of them. Two-node paths are
//!     excluded: `_theta_star_b` also returns a bare `[start, goal]` from four
//!     unchecked fallbacks (:1353, :1357, :1437, :1439).
//!   * `trace.flow[*].taut` is `string_pull` (movement_planner.gd:1461) of that
//!     path: each output segment is either an accepted Theta* edge or a
//!     shortcut `_cspace_blocked` cleared. Also `step_blocked`-false.
//!   * the SAME string pull decided which shortcuts to take by COST
//!     (movement_planner.gd:1476-1479): the taken one is no dearer than the legs
//!     it replaces, and every later candidate before the visibility break IS
//!     dearer. That inequality pair is the only cost oracle the corpus carries —
//!     see `g1d_*`, and the note at the bottom of this file on what the recorder
//!     would have to add for an EXACT cost gate.
//!   * `trace.flow[*].walked` is `_walk_offset` (movement_planner.gd:1494),
//!     which spends arc length against the flow's allowance — so
//!     `polyline_length` of it may not exceed that allowance.
//!
//! THE ORACLE'S OPTS. `plan_sequential_flow` rebuilds a fresh option dict per
//! model (movement_planner.gd:1091): `{clearance, avoid_cells, zones}` — note
//! it carries NO `avoid_fine`, and its `zones` are the (possibly culled) base
//! zones PLUS one body disc per other own model, whose centres depend on the
//! placement order. The oracle below reconstructs the base zones exactly (cull
//! included, movement_planner.gd:1058-1069) and omits the per-model body discs.
//! That makes the oracle's zone set a strict SUBSET of the real one, and a
//! subset can only ever block LESS — so "the real planner accepted this edge"
//! still implies "step_blocked is false here". The gate is sound; it just does
//! not exercise the body discs, which belong to M4-3 anyway.

use std::collections::HashSet;

use nml_core::mv::cost::{
    cspace_blocked, segment_cost, segment_cost_at, step_blocked, CellSet, Grid, StepOpts, Wall,
    Zone,
};
use nml_core::mv::geom2::{
    add, distance_squared_to, distance_to, length, lerp, polyline_length, sub, trim_polyline, V2,
};
use nml_core::mv::io::{MoveCall, MoveCorpus, MoveHeader};
use nml_core::mv::{load_moves, CONTACT_SLIDE_EPS_IN, EPS, PLAN_CELL_IN};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/moves_s27.jsonl");

fn corpus() -> MoveCorpus {
    load_moves(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

fn no_cells() -> CellSet {
    CellSet::new()
}

/// `plan_sequential_flow`'s `base_zones` — movement_planner.gd:1050 plus the
/// `fast_planner` reach cull at :1058-1069. Reproduced here (not in the module)
/// because it belongs to the flow stage, M4-3; the gate only needs it to build a
/// SOUND subset of each edge's real zone set.
fn base_zones(call: &MoveCall, header: &MoveHeader) -> Vec<Zone> {
    if call.opts.zones_rest_only {
        return Vec::new();
    }
    let zones = call.opts.zones.clone();
    if !(header.fast_planner && zones.len() > 8) {
        return zones;
    }
    let cull_reach = length(call.delta).max(call.opts.charge_allowance.unwrap_or(0.0))
        + call.opts.clearance
        + PLAN_CELL_IN;
    let mut kept = Vec::new();
    for z in &zones {
        let keep_r2 = (cull_reach + z.r).powf(2.0);
        for m in &call.model_pos {
            if distance_squared_to(*m, z.c) <= keep_r2 {
                kept.push(*z);
                break;
            }
        }
    }
    kept
}

/// The per-model routing options of the sequential flow, minus the body discs —
/// see the module note on why dropping them keeps the gate sound.
struct Oracle {
    zones: Vec<Zone>,
    avoid_cells: CellSet,
    fine: CellSet,
    clearance: f64,
}

impl Oracle {
    fn of(call: &MoveCall, header: &MoveHeader) -> Oracle {
        Oracle {
            zones: base_zones(call, header),
            avoid_cells: call.opts.avoid_cells.clone(),
            // movement_planner.gd:1091 — `oi` has no "avoid_fine" key.
            fine: no_cells(),
            clearance: call.opts.clearance,
        }
    }
    fn opts(&self) -> StepOpts<'_> {
        StepOpts {
            clearance: self.clearance,
            zones: &self.zones,
            avoid_cells: &self.avoid_cells,
            avoid_fine: &self.fine,
        }
    }
    fn opts_clearance(&self, clearance: f64) -> StepOpts<'_> {
        StepOpts {
            clearance,
            zones: &self.zones,
            avoid_cells: &self.avoid_cells,
            avoid_fine: &self.fine,
        }
    }
}

/// Every accepted edge in the corpus: (call index, walls, the edge, the oracle
/// opts owner). Theta* path edges only come from paths of >= 3 nodes.
struct Edge {
    call: usize,
    a: V2,
    b: V2,
}

fn accepted_edges(c: &MoveCorpus) -> (Vec<Edge>, usize, usize) {
    let mut out = Vec::new();
    let mut theta_n = 0usize;
    let mut taut_n = 0usize;
    for (ci, call) in c.calls.iter().enumerate() {
        for f in &call.trace.flow {
            if f.theta.len() < 3 {
                continue;
            }
            for w in f.theta.windows(2) {
                out.push(Edge { call: ci, a: w[0], b: w[1] });
                theta_n += 1;
            }
            // A charge appends its goal point to the taut path UNCHECKED
            // (movement_planner.gd:1119), so its last segment is not an oracle.
            let n = if call.allow_contact { f.taut.len().saturating_sub(1) } else { f.taut.len() };
            for w in f.taut[..n].windows(2) {
                out.push(Edge { call: ci, a: w[0], b: w[1] });
                taut_n += 1;
            }
        }
    }
    (out, theta_n, taut_n)
}

// === G1a/G1b — step_blocked is FALSE on every accepted edge ==================

#[test]
fn g1a_step_blocked_is_false_on_every_edge_the_recorded_search_accepted() {
    let c = corpus();
    c.header.constants.check().unwrap_or_else(|e| panic!("corpus constants: {e}"));
    let (edges, theta_n, taut_n) = accepted_edges(&c);
    assert!(
        theta_n + taut_n >= 1000,
        "the gate needs >= 1000 accepted edges, the corpus offered {}",
        theta_n + taut_n
    );
    let oracles: Vec<Oracle> =
        c.calls.iter().map(|call| Oracle::of(call, &c.header)).collect();
    let mut checked = 0usize;
    for e in &edges {
        let call = &c.calls[e.call];
        let o = oracles[e.call].opts();
        assert!(
            !step_blocked(e.a, e.b, &call.walls, &o),
            "call {} ({} act {}): the search accepted {:?}->{:?} but step_blocked says blocked",
            e.call,
            call.unit,
            call.act,
            e.a,
            e.b
        );
        checked += 1;
    }
    eprintln!(
        "G1a/G1b: {checked} accepted edges clear ({theta_n} Theta* path edges, {taut_n} string-pulled), \
         over {} calls / {} traced flow attempts",
        c.calls.len(),
        c.calls.iter().map(|x| x.trace.flow.len()).sum::<usize>()
    );
}

// === G1c — the NEGATIVE oracle: the same edge inside a zone disc is blocked ==

#[test]
fn g1c_an_accepted_edge_shifted_into_the_nearest_zone_disc_is_blocked() {
    let c = corpus();
    let (edges, _, _) = accepted_edges(&c);
    let oracles: Vec<Oracle> =
        c.calls.iter().map(|call| Oracle::of(call, &c.header)).collect();
    let mut shifted = 0usize;
    let mut skipped = 0usize;
    for e in &edges {
        let call = &c.calls[e.call];
        let or = &oracles[e.call];
        let mid = lerp(e.a, e.b, 0.5);
        let near = or
            .zones
            .iter()
            .filter(|z| z.r > 0.0)
            .min_by(|x, y| {
                distance_squared_to(mid, x.c)
                    .partial_cmp(&distance_squared_to(mid, y.c))
                    .unwrap()
            });
        let Some(z) = near else {
            skipped += 1;
            continue;
        };
        // Translate the whole edge so its MIDPOINT lands on the disc centre:
        // both endpoints then sit at |edge|/2 from it, which `_zone_blocks`
        // (movement_planner.gd:203) rejects either as an entry or as a
        // non-escaping step inside.
        let off = sub(z.c, mid);
        let o = or.opts();
        assert!(
            step_blocked(add(e.a, off), add(e.b, off), &call.walls, &o),
            "call {}: edge {:?}->{:?} centred on zone {:?} r={} is NOT blocked",
            e.call,
            e.a,
            e.b,
            z.c,
            z.r
        );
        shifted += 1;
    }
    eprintln!("G1c: {shifted} edges blocked when centred on their nearest zone disc ({skipped} edges had no zone disc in reach)");
    assert!(shifted >= 1000, "only {shifted} negative cases");
}

// === G1d — the string-pull cost oracle ======================================

/// Maps every taut point back to its index in the Theta* path. `string_pull`
/// only ever re-emits `path[j]` values, so the match is by exact f32 identity.
fn taut_indices(theta: &[V2], taut: &[V2]) -> Option<Vec<usize>> {
    let mut idx = Vec::with_capacity(taut.len());
    let mut k = 0usize;
    for t in taut {
        let mut found = None;
        for (j, p) in theta.iter().enumerate().skip(k) {
            if p == t {
                found = Some(j);
                break;
            }
        }
        let j = found?;
        idx.push(j);
        k = j + 1;
    }
    Some(idx)
}

fn legs_cost_at(path: &[V2], i0: usize, i1: usize, grid: &Grid, o: &StepOpts, s: f64) -> f64 {
    let mut total = 0.0;
    for k in i0..i1 {
        total += segment_cost_at(path[k], path[k + 1], grid, o, s);
    }
    total
}

/// The flow attempts whose per-model zone set is EXACTLY reconstructable —
/// movement_planner.gd:1080-1090: the base zones plus one body disc per OTHER
/// own model, centred on `result[j]` when j is already placed and on its start
/// otherwise.
///
/// The window closes after the SECOND placement. `result[j]` is the traced
/// `walked` endpoint only while `_pull_into_placed` (:1148) did not move it, and
/// that pull is skipped exactly once — for the first model placed, whose
/// `placed` set is still empty (:1147). So the discs are known while at most one
/// model has been placed, and unknowable after that (the trace is taken BEFORE
/// the pull, movement_planner.gd:1139-1140).
///
/// This matters for the REJECTED half of the string-pull oracle only: dropping a
/// zone makes `_cspace_blocked` say "clear" where the GDScript said "blocked",
/// which moves the loop's break point and would invent candidates the shipped
/// code never priced. Costs themselves are zone-independent — `_terrain_cost_at`
/// (:1259) reads only the grid and the avoid sets — so the ACCEPTED half is
/// sound on every attempt.
fn exact_zone_attempts(call: &MoveCall, header: &MoveHeader) -> Vec<(usize, Vec<Zone>)> {
    let n = call.model_pos.len();
    let have_r = call.opts.radii.len() == n;
    let base = base_zones(call, header);
    let mut out = Vec::new();
    let mut placed: Vec<(usize, V2)> = Vec::new();
    for (k, f) in call.trace.flow.iter().enumerate() {
        if placed.len() > 1 {
            break;
        }
        let idx = f.model as usize;
        let mut zones = base.clone();
        if have_r && idx < n {
            for j in 0..n {
                if j == idx {
                    continue;
                }
                let c = placed
                    .iter()
                    .find(|(pj, _)| *pj == j)
                    .map(|(_, p)| *p)
                    .unwrap_or(call.model_pos[j]);
                zones.push(Zone {
                    c,
                    r: (call.opts.radii[j] + call.opts.radii[idx] - CONTACT_SLIDE_EPS_IN).max(0.0),
                });
            }
        }
        out.push((k, zones));
        if !f.deferred {
            let end = *f.walked.last().unwrap_or(&call.model_pos[idx]);
            placed.push((idx, end));
        }
    }
    out
}

/// The string-pull inequality at resample length `s`.
///
/// `taken` counts shortcuts `string_pull` accepted — priced on EVERY traced
/// attempt, because the price does not depend on the zones. `rejected` counts
/// candidates it priced and threw away — only on the attempts whose zone set is
/// exactly reconstructable, because those need the loop's break point to be the
/// GDScript's break point.
fn string_pull_cost_census(c: &MoveCorpus, s: f64) -> (usize, usize, usize, usize) {
    let oracles: Vec<Oracle> =
        c.calls.iter().map(|call| Oracle::of(call, &c.header)).collect();
    let (mut acc, mut rej, mut bad, mut unmapped) = (0usize, 0usize, 0usize, 0usize);
    for (ci, call) in c.calls.iter().enumerate() {
        let o = oracles[ci].opts();
        for f in &call.trace.flow {
            if f.theta.len() < 3 {
                continue;
            }
            let Some(idx) = taut_indices(&f.theta, &f.taut) else {
                unmapped += 1;
                continue;
            };
            for m in 0..idx.len().saturating_sub(1) {
                let (i0, i1) = (idx[m], idx[m + 1]);
                if i1 > i0 + 1 {
                    let cheap = segment_cost_at(f.theta[i0], f.theta[i1], &call.grid, &o, s)
                        <= legs_cost_at(&f.theta, i0, i1, &call.grid, &o, s) + EPS;
                    let clear = !cspace_blocked(f.theta[i0], f.theta[i1], &call.walls, &call.grid, &o);
                    if !(cheap && clear) {
                        bad += 1;
                    }
                    acc += 1;
                }
            }
        }
        for (k, zones) in exact_zone_attempts(call, &c.header) {
            let f = &call.trace.flow[k];
            if f.theta.len() < 3 {
                continue;
            }
            let Some(idx) = taut_indices(&f.theta, &f.taut) else {
                continue;
            };
            let oe = StepOpts {
                clearance: call.opts.clearance,
                zones: &zones,
                avoid_cells: &call.opts.avoid_cells,
                avoid_fine: oracles[ci].opts().avoid_fine,
            };
            for m in 0..idx.len().saturating_sub(1) {
                let (i0, i1) = (idx[m], idx[m + 1]);
                for j in (i1 + 1)..f.theta.len() {
                    if cspace_blocked(f.theta[i0], f.theta[j], &call.walls, &call.grid, &oe) {
                        break;
                    }
                    let dearer = segment_cost_at(f.theta[i0], f.theta[j], &call.grid, &oe, s)
                        > legs_cost_at(&f.theta, i0, j, &call.grid, &oe, s) + EPS;
                    if !dearer {
                        bad += 1;
                    }
                    rej += 1;
                }
            }
        }
    }
    (acc, rej, bad, unmapped)
}

#[test]
fn g1d_segment_cost_reproduces_every_string_pull_decision() {
    let c = corpus();
    let (acc, rej, bad, unmapped) = string_pull_cost_census(&c, PLAN_CELL_IN * 0.5);
    eprintln!(
        "G1d: {acc} taken shortcuts (cost <= legs, every attempt) + {rej} rejected candidates \
         (cost > legs, exact-zone attempts only) = {} cost decisions, {bad} violations, \
         {unmapped} taut paths unmappable",
        acc + rej
    );
    assert_eq!(unmapped, 0, "taut points must be Theta* path points");
    assert_eq!(bad, 0, "{bad} string-pull cost decisions the port does not reproduce");
    assert!(acc + rej >= 80, "only {} cost decisions", acc + rej);
}

// === G1e/G1f — polyline_length and trim_polyline =============================

#[test]
fn g1e_polyline_length_of_every_walked_leg_stays_inside_its_allowance() {
    let c = corpus();
    let mut legs = 0usize;
    let mut worst = f64::NEG_INFINITY;
    for call in &c.calls {
        let allowance = call.allowance();
        for f in &call.trace.flow {
            let l = polyline_length(&f.walked);
            worst = worst.max(l - allowance);
            assert!(
                l <= allowance + 1e-4,
                "{} act {}: walked {l} > allowance {allowance}",
                call.unit,
                call.act
            );
            legs += 1;
        }
    }
    eprintln!("G1e: {legs} walked legs within their allowance, worst overshoot {worst:.3e} in");
}

#[test]
fn g1f_trim_polyline_cuts_at_the_exact_budget() {
    let c = corpus();
    let mut lines = 0usize;
    let mut cuts = 0usize;
    let mut worst = 0.0f64;
    let mut check = |p: &[V2]| {
        if p.len() < 2 {
            return;
        }
        let l = polyline_length(p);
        if l <= EPS {
            return;
        }
        lines += 1;
        // a budget above the arc keeps every node.
        let full = trim_polyline(p, l + 1.0);
        assert_eq!(full.len(), p.len(), "trim above the arc length dropped a node");
        for (x, y) in full.iter().zip(p.iter()) {
            assert_eq!(x, y, "trim above the arc length moved a node");
        }
        // a budget inside the arc cuts to exactly that budget, and the cut is a
        // PREFIX of the input plus one interpolated point.
        for frac in [0.25, 0.5, 0.75] {
            let m = l * frac;
            let cut = trim_polyline(p, m);
            let cl = polyline_length(&cut);
            worst = worst.max((cl - m).abs());
            assert!((cl - m).abs() <= 1e-4, "trim to {m} produced {cl}");
            for (k, x) in cut.iter().enumerate().take(cut.len() - 1) {
                assert_eq!(x, &p[k], "trim broke the prefix at {k}");
            }
            cuts += 1;
        }
    };
    for call in &c.calls {
        for f in &call.trace.flow {
            check(&f.walked);
        }
        for t in &call.trails {
            check(t);
        }
    }
    eprintln!("G1f: {lines} polylines, {cuts} trims, worst arc error {worst:.3e} in");
}

// === RED PROOFS =============================================================

#[test]
fn red_a_clearance_plus_one_tenth_inch_flips_step_blocked() {
    let c = corpus();
    let (edges, _, _) = accepted_edges(&c);
    let oracles: Vec<Oracle> =
        c.calls.iter().map(|call| Oracle::of(call, &c.header)).collect();
    let mut flipped = 0usize;
    for e in &edges {
        let call = &c.calls[e.call];
        let o = oracles[e.call].opts_clearance(oracles[e.call].clearance + 0.1);
        if step_blocked(e.a, e.b, &call.walls, &o) {
            flipped += 1;
        }
    }
    eprintln!(
        "RED A: clearance + 0.1\" blocks {flipped} of {} accepted edges — the wall inflation is load-bearing",
        edges.len()
    );
    assert!(flipped > 0, "a fatter base blocked nothing: the clearance is dead code");
}

#[test]
fn red_b_a_coarser_resample_moves_the_costs_and_breaks_the_cost_gate() {
    let c = corpus();
    let oracles: Vec<Oracle> =
        c.calls.iter().map(|call| Oracle::of(call, &c.header)).collect();
    let (mut n, mut differ) = (0usize, 0usize);
    let mut seen: HashSet<usize> = HashSet::new();
    for (ci, call) in c.calls.iter().enumerate() {
        if call.grid.is_empty() {
            continue;
        }
        let o = oracles[ci].opts();
        for f in &call.trace.flow {
            for w in f.theta.windows(2) {
                let a = segment_cost(w[0], w[1], &call.grid, &o);
                let b = segment_cost_at(w[0], w[1], &call.grid, &o, 0.6);
                n += 1;
                if a != b {
                    differ += 1;
                    seen.insert(ci);
                }
            }
        }
    }
    let (acc, rej, bad, _) = string_pull_cost_census(&c, 0.6);
    eprintln!(
        "RED B: resample 0.5\" -> 0.6\" moves {differ} of {n} segment costs (across {} calls); \
         the G1d cost gate then fails {bad} of its {} decisions",
        seen.len(),
        acc + rej
    );
    assert!(differ > 0, "the 0.5\" step count is not load-bearing");
    assert!(bad > 0, "the G1d cost gate cannot fail: it is not a gate");
}

// === census =================================================================

#[test]
fn g1_census() {
    let c = corpus();
    let mut flow = 0usize;
    let mut ge3 = 0usize;
    let mut deferred = 0usize;
    let mut charges = 0usize;
    let mut zones_before = 0usize;
    let mut zones_after = 0usize;
    for call in &c.calls {
        if call.allow_contact {
            charges += 1;
        }
        zones_before += call.opts.zones.len();
        zones_after += base_zones(call, &c.header).len();
        for f in &call.trace.flow {
            flow += 1;
            if f.theta.len() >= 3 {
                ge3 += 1;
            }
            if f.deferred {
                deferred += 1;
            }
        }
    }
    let (_, theta_n, taut_n) = accepted_edges(&c);
    eprintln!(
        "CENSUS  calls={} models={} flow_attempts={flow} deferred={deferred} charges={charges}\n\
         CENSUS  theta paths >=3 nodes={ge3}  accepted edges: theta={theta_n} taut={taut_n} total={}\n\
         CENSUS  zones {zones_before} -> {zones_after} after the fast_planner cull; \
         untangle swaps={} solve passes={}\n\
         CENSUS  walls={} board={:?} fast_planner={} guard={}",
        c.calls.len(),
        c.calls.iter().map(|x| x.model_pos.len()).sum::<usize>(),
        theta_n + taut_n,
        c.calls.iter().map(|x| x.trace.untangle_swaps.len()).sum::<usize>(),
        c.calls.iter().map(|x| x.trace.solve_passes.len()).sum::<usize>(),
        c.header.walls.len(),
        c.header.board_in,
        c.header.fast_planner,
        c.header.fast_planner_guard,
    );
    assert_eq!(c.calls.len(), 64);
}

// === unit checks on the primitives ==========================================

#[test]
fn geometry_primitives_mirror_godot() {
    // Vector2::normalized() on the zero vector returns ZERO, it does not divide.
    assert_eq!(nml_core::mv::normalized([0.0, 0.0]), [0.0, 0.0]);
    // distance_to is an f32 sqrt: the f64 answer for (1,1) would be 1.4142135623730951.
    let d = distance_to([0.0, 0.0], [1.0, 1.0]);
    assert_eq!(d, 2.0f32.sqrt() as f64);
    assert_ne!(d, 2.0f64.sqrt());
    // segments_cross counts touching as crossing (the safe side).
    assert!(nml_core::mv::segments_cross(
        [0.0, 0.0],
        [1.0, 0.0],
        [1.0, 0.0],
        [1.0, 1.0]
    ));
    // trim_polyline of an empty budget keeps only the first point.
    assert_eq!(trim_polyline(&[[0.0, 0.0], [3.0, 0.0]], 0.0), vec![[0.0, 0.0]]);
    // cell_of floors, so it is correct on the negative side of the origin.
    assert_eq!(nml_core::mv::cell_of([-0.5, -3.5], 3.0), (-1, -2));
    // an empty grid short-circuits _terrain_cost_at to 1.0 before the avoid sets.
    let empty: Grid = Grid::new();
    let mut avoid = CellSet::new();
    avoid.insert((0, 0));
    let none = no_cells();
    let o = StepOpts { clearance: 0.0, zones: &[], avoid_cells: &avoid, avoid_fine: &none };
    assert_eq!(nml_core::mv::terrain_cost_at([0.5, 0.5], &empty, &o), 1.0);
    // with a grid, that same avoided cell is a hard block.
    let mut grid: Grid = Grid::new();
    grid.insert((0, 0), nml_core::mv::T_NONE);
    assert!(nml_core::mv::terrain_cost_at([0.5, 0.5], &grid, &o).is_infinite());
    // a zero-length wall list with clearance 0 is the legacy path_crosses_wall.
    let walls: Vec<Wall> = vec![[[1.0, -1.0], [1.0, 1.0]]];
    let o2 = StepOpts::new(0.0, &[]);
    assert!(step_blocked([0.0, 0.0], [2.0, 0.0], &walls, &o2));
    assert!(!step_blocked([0.0, 0.0], [0.5, 0.0], &walls, &o2));
}

// === WHAT THE TRACE COULD NOT GATE =========================================
//
// 1. AN EXACT COST GATE. `MoveRecorder.trace_model` (move_recorder.gd:198)
//    records the Theta* path as WORLD POINTS only — no `g` per node, no edge
//    cost. So `_segment_cost` and `_terrain_cost_at` can only be pinned through
//    the string pull's cost COMPARISONS (g1d, 103 decisions), never against a
//    recorded number. The recorder fix is small: `_theta_reconstruct`
//    (movement_planner.gd:1443) already walks the parent chain, so passing `g`
//    down and emitting one `"g": [f, …]` array beside `"theta"` is a ~10-line
//    addition. With it, M4-2 gets `_segment_cost` to 1e-12 on ~1000 edges
//    instead of 103 inequalities.
//
// 2. THE PER-MODEL ZONE SET beyond the second placement. The flow's body discs
//    sit on `result[j]`, and `trace_model` fires BEFORE `_pull_into_placed`
//    (movement_planner.gd:1139-1148) can move that point — so from the second
//    placement on, the zone set the edge was really judged against is not
//    reconstructable. Emitting the POST-pull endpoint (or the pull delta) in the
//    trace entry would open the rejected half of g1d to the whole corpus, and it
//    is what M4-3's flow gate will need anyway.
//
// 3. THE `_walk_offset` BUDGET. The trace carries the walked polyline but not
//    its `spent` (movement_planner.gd:1499), so g1e can only assert the
//    allowance BOUND, not the exact arc. One float per entry fixes it.
//
// 4. CHARGES. This corpus (seed 27) contains 64 calls and NOT ONE with
//    `allow_contact` — so the charge branch (movement_planner.gd:1096-1126:
//    `reach_closest`, the target's bases as no-through zones, the appended body
//    goal) is entirely ungated here. M4-2 needs a corpus from a game with
//    charges.
//
// 5. THE f32/f64 BOUNDARY ITSELF. Measured against this corpus (one-off probe,
//    not kept as code): swapping `_orient` to f32 changes NONE of the 47 856
//    edge/wall crossing tests, and running the whole of `step_blocked` on an
//    all-f64 geometry flips NONE of the 1 980 accepted edges — while 44 324 of
//    those 47 856 `point_seg_distance` values do differ from their f64 twin by
//    more than 1e-9. So the precision discipline in `geom2` rests on READING the
//    engine (`real_t` is 32-bit), not on this gate: a boolean predicate is too
//    coarse to see it. It starts to bite in M4-2, where Theta* node POSITIONS
//    and `g` values are compared to 1e-9 — which is also the moment the gate can
//    finally falsify the choice. Do not "simplify" `geom2` to f64 on the
//    strength of G1 being green.
