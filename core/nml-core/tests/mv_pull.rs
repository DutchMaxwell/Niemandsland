//! GATE G3 (NML-1073 M4-3) — `string_pull`, `_walk_offset` and
//! `_furthest_clear` against the recorded corpus.
//!
//! Each stage is replayed on ITS OWN recorded input — the pull on the recorded
//! Theta* path, the walk on the recorded taut path — so an M4-2 regression can
//! neither hide nor fake an M4-3 one. Positions are f32 on both sides, so the
//! comparison is exact equality.
//!
//! The fleet gate is `cargo run --release --bin mvtheta -- <16 corpora>`; the
//! in-repo fixture is one seed-27 game.

use nml_core::mv::cost::{cspace_blocked, CellSet, Grid, StepOpts, Wall, Zone};
use nml_core::mv::geom2::V2;
use nml_core::mv::pull::{
    board_clamp, furthest_clear, furthest_clear_steps, string_pull, string_pull_bent, walk_offset,
    walk_offset_bent, PullBend, WalkBend,
};
use nml_core::mv::replay::searches;
use nml_core::mv::{load_moves, MoveCorpus, COHERENCY_BISECT_STEPS, EPS, T_DANGEROUS};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/moves_s27.jsonl");

fn corpus() -> MoveCorpus {
    load_moves(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

#[derive(Default)]
struct Tally {
    determined: usize,
    pull_ok: usize,
    walk_ok: usize,
    pull_moved: usize,
    walk_moved: usize,
}

fn replay(c: &MoveCorpus, pull: PullBend, walk: WalkBend) -> Tally {
    let bending = pull.cost_break
        || walk.eps_swapped
        || walk.bisect_steps != WalkBend::default().bisect_steps;
    let mut t = Tally::default();
    for (ci, call) in c.calls.iter().enumerate() {
        for s in searches(ci, call, &c.header) {
            let got_pull = s.run_pull_bent(call, pull);
            let got_walk = s.run_walk_bent(call, walk);
            if bending {
                if got_pull != s.run_pull(call) {
                    t.pull_moved += 1;
                }
                if got_walk != s.run_walk(call) {
                    t.walk_moved += 1;
                }
            }
            if !s.determined {
                continue;
            }
            t.determined += 1;
            if got_pull == s.taut_expected {
                t.pull_ok += 1;
            }
            if got_walk == s.walked_expected {
                t.walk_ok += 1;
            }
        }
    }
    t
}

// === G3 — the corpus gate ===================================================

#[test]
fn g3a_string_pull_and_walk_reproduce_every_determined_recorded_polyline() {
    let c = corpus();
    c.header.constants.check().unwrap_or_else(|e| panic!("corpus constants: {e}"));
    let t = replay(&c, PullBend::default(), WalkBend::default());
    assert_eq!(t.pull_ok, t.determined, "string_pull diverges on {} polylines", t.determined - t.pull_ok);
    assert_eq!(t.walk_ok, t.determined, "_walk_offset diverges on {} polylines", t.determined - t.walk_ok);
    println!("G3 fixture: {} determined stages, pull {} ok, walk {} ok", t.determined, t.pull_ok, t.walk_ok);
}

#[test]
fn red_d_a_thirteen_step_bisection_moves_recorded_walks() {
    let c = corpus();
    let t = replay(&c, PullBend::default(), WalkBend { bisect_steps: 13, ..Default::default() });
    assert!(t.walk_ok < t.determined, "13 bisection steps changed nothing — _furthest_clear is not being reached");
    println!("RED d: bisect 13 -> {} of {} walks diverge, {} moved", t.determined - t.walk_ok, t.determined, t.walk_moved);
}

#[test]
fn red_e_swapping_the_walk_eps_order_moves_recorded_walks() {
    let c = corpus();
    let t = replay(&c, PullBend::default(), WalkBend { eps_swapped: true, ..Default::default() });
    assert!(t.walk_ok < t.determined, "the allowance EPS order changed nothing");
    println!("RED e: eps swapped -> {} of {} walks diverge, {} moved", t.determined - t.walk_ok, t.determined, t.walk_moved);
}

// === Hand-built cases =======================================================

fn no_cells() -> CellSet {
    CellSet::new()
}

fn opts<'a>(zones: &'a [Zone], none: &'a CellSet) -> StepOpts<'a> {
    StepOpts { clearance: 0.0, zones, avoid_cells: none, avoid_fine: none }
}

/// Two 3" cells of Dangerous ground on the diagonal only — cell (1,1) is the
/// square [3,6) x [3,6).
fn dangerous_grid() -> Grid {
    let mut g = Grid::new();
    g.insert((1, 1), T_DANGEROUS);
    g
}

#[test]
fn string_pull_collapses_a_clear_zigzag_to_its_endpoints() {
    let walls: Vec<Wall> = Vec::new();
    let grid = Grid::new();
    let none = no_cells();
    let o = opts(&[], &none);
    let path: Vec<V2> = vec![[0.0, 0.0], [1.0, 1.0], [2.0, 0.0], [3.0, 1.0]];
    assert_eq!(string_pull(&path, &walls, &grid, &o), vec![[0.0, 0.0], [3.0, 1.0]]);
    // Two nodes or fewer come back as a copy, untouched.
    let two: Vec<V2> = vec![[0.0, 0.0], [3.0, 1.0]];
    assert_eq!(string_pull(&two, &walls, &grid, &o), two);
    assert_eq!(string_pull(&two[..1], &walls, &grid, &o), vec![[0.0, 0.0]]);
}

#[test]
fn string_pull_keeps_the_unchecked_first_leg_even_when_it_is_blocked() {
    // The scan's `farthest` DEFAULTS to `anchor + 1` and that leg is never
    // visibility-tested (movement_planner.gd:1470), so a taut path can carry a
    // leg `_cspace_blocked` rejects — which is why `_walk_offset` needs its
    // blocked branch at all.
    let walls: Vec<Wall> = Vec::new();
    let grid = Grid::new();
    let none = no_cells();
    let zones = vec![Zone { c: [2.5, 0.9], r: 0.4 }];
    let o = opts(&zones, &none);
    let path: Vec<V2> = vec![[0.0, 0.0], [1.0, 1.0], [2.0, 0.0], [3.0, 1.0]];
    let taut = string_pull(&path, &walls, &grid, &o);
    assert_eq!(taut, vec![[0.0, 0.0], [2.0, 0.0], [3.0, 1.0]]);
    assert!(
        cspace_blocked(taut[1], taut[2], &walls, &grid, &o),
        "the kept anchor+1 leg is exactly the one the pull never checked"
    );
}

#[test]
fn red_f_string_pull_must_skip_a_dear_shortcut_not_stop_at_it() {
    // A path that doubles back: the middle shortcut crosses Dangerous ground and
    // is far dearer than the legs it would replace, but the FARTHEST one is
    // cheap. The shipped `continue` finds it; a `break` never looks.
    let walls: Vec<Wall> = Vec::new();
    let grid = dangerous_grid();
    let none = no_cells();
    let o = opts(&[], &none);
    let path: Vec<V2> = vec![[0.5, 0.5], [0.5, 7.5], [7.5, 7.5], [7.5, 0.5]];
    assert_eq!(
        string_pull(&path, &walls, &grid, &o),
        vec![[0.5, 0.5], [7.5, 0.5]],
        "the cheap far shortcut is taken"
    );
    assert_eq!(
        string_pull_bent(&path, &walls, &grid, &o, PullBend { cost_break: true }),
        path,
        "breaking on cost throws the whole pull away"
    );
}

#[test]
fn furthest_clear_bisects_fourteen_times_onto_the_free_side() {
    let walls: Vec<Wall> = Vec::new();
    let grid = Grid::new();
    let none = no_cells();
    let zones = vec![Zone { c: [5.0, 0.0], r: 1.0 }];
    let o = opts(&zones, &none);
    let (a, b): (V2, V2) = ([0.0, 0.0], [10.0, 0.0]);
    // A clear segment is returned as-is, without a single bisection.
    assert_eq!(furthest_clear(a, [3.0, 0.0], &walls, &grid, &o), [3.0, 0.0]);
    // The disc's free boundary sits at x = 4.0; `lo` converges from BELOW, so
    // the answer is inside the free side by at most one 2^-14 interval.
    let p = furthest_clear(a, b, &walls, &grid, &o);
    let step = 10.0 / (1u32 << COHERENCY_BISECT_STEPS) as f32;
    assert!(p[0] <= 4.0 && p[0] > 4.0 - step, "got {p:?}, step {step}");
    assert!(!cspace_blocked(a, p, &walls, &grid, &o), "the returned point must be clear");
    assert_eq!(p[1], 0.0);
    // One step fewer lands on a different dyadic point (0.4 is not dyadic).
    assert_ne!(furthest_clear_steps(a, b, &walls, &grid, &o, 13), p);
}

#[test]
fn walk_offset_spends_arc_length_and_clips_the_last_leg() {
    let walls: Vec<Wall> = Vec::new();
    let grid = Grid::new();
    let none = no_cells();
    let o = opts(&[], &none);
    let board: V2 = [10.0, 10.0];
    let start: V2 = [0.0, 0.0];
    let taut: Vec<V2> = vec![[0.0, 0.0], [3.0, 0.0]];
    // Single point in, single point out.
    assert_eq!(walk_offset(start, &taut[..1], [0.0, 0.0], 9.0, &walls, &grid, &o, board), vec![start]);
    // Inside the budget: the leg is taken whole.
    assert_eq!(
        walk_offset(start, &taut, [0.0, 0.0], 5.0, &walls, &grid, &o, board),
        vec![[0.0, 0.0], [3.0, 0.0]]
    );
    // Over budget: clipped by the fraction.
    assert_eq!(
        walk_offset(start, &taut, [0.0, 0.0], 2.0, &walls, &grid, &o, board),
        vec![[0.0, 0.0], [2.0, 0.0]]
    );
    // A zero budget appends nothing at all (`frac > EPS` fails).
    assert_eq!(walk_offset(start, &taut, [0.0, 0.0], 0.0, &walls, &grid, &o, board), vec![start]);
    // A zero-length leg is skipped, not appended.
    let dup: Vec<V2> = vec![[0.0, 0.0], [0.0, 0.0], [3.0, 0.0]];
    assert_eq!(
        walk_offset(start, &dup, [0.0, 0.0], 9.0, &walls, &grid, &o, board),
        vec![[0.0, 0.0], [3.0, 0.0]]
    );
    // The target is board-clamped per axis before the leg is measured.
    let off: Vec<V2> = vec![[0.0, 0.0], [20.0, 0.0]];
    assert_eq!(
        walk_offset(start, &off, [0.0, 0.0], 20.0, &walls, &grid, &o, board),
        vec![[0.0, 0.0], [10.0, 0.0]]
    );
    assert_eq!(board_clamp([-3.0, 12.0], board), [0.0, 10.0]);
}

#[test]
fn walk_offset_stops_at_the_furthest_clear_point_of_a_blocked_leg() {
    let walls: Vec<Wall> = Vec::new();
    let grid = Grid::new();
    let none = no_cells();
    let zones = vec![Zone { c: [5.0, 0.0], r: 1.0 }];
    let o = opts(&zones, &none);
    let board: V2 = [10.0, 10.0];
    let taut: Vec<V2> = vec![[0.0, 0.0], [10.0, 0.0]];
    let out = walk_offset([0.0, 0.0], &taut, [0.0, 0.0], 20.0, &walls, &grid, &o, board);
    assert_eq!(out.len(), 2);
    let stop = furthest_clear([0.0, 0.0], [10.0, 0.0], &walls, &grid, &o);
    assert_eq!(out[1], stop, "the walk stops exactly where _furthest_clear says");
    // 13 steps instead of 14 moves that stop — the count is load-bearing.
    assert_ne!(
        walk_offset_bent(
            [0.0, 0.0], &taut, [0.0, 0.0], 20.0, &walls, &grid, &o, board,
            WalkBend { bisect_steps: 13, ..Default::default() }
        ),
        out
    );
}

#[test]
fn red_g_the_allowance_eps_order_decides_a_hair_long_leg() {
    let walls: Vec<Wall> = Vec::new();
    let grid = Grid::new();
    let none = no_cells();
    let o = opts(&[], &none);
    let board: V2 = [10.0, 10.0];
    let taut: Vec<V2> = vec![[0.0, 0.0], [3.0, 0.0]];
    // The leg overshoots the allowance by less than EPS. The shipped order
    // (`spent + leg <= allowance + EPS`) lets it through WHOLE; moving the
    // epsilon to the other side clips it.
    let allowance = 3.0 - 0.5 * EPS;
    let shipped = walk_offset([0.0, 0.0], &taut, [0.0, 0.0], allowance, &walls, &grid, &o, board);
    assert_eq!(shipped, vec![[0.0, 0.0], [3.0, 0.0]]);
    let bent = walk_offset_bent(
        [0.0, 0.0], &taut, [0.0, 0.0], allowance, &walls, &grid, &o, board,
        WalkBend { eps_swapped: true, ..Default::default() },
    );
    assert_ne!(bent, shipped);
    assert!(bent[1][0] < 3.0 && bent[1][0] > 2.999, "clipped by a hair: {bent:?}");
}
