//! GATE G2 (NML-1073 M4-2) — `theta_star` against the recorded corpus.
//!
//! The in-repo fixture is one seed-27 arena game; the fleet gate runs the same
//! comparison over all 16 games with `cargo run --release --bin mvtheta -- <paths>`.
//!
//! WHAT IS JUDGED. `MoveRecorder.trace_model` (move_recorder.gd:198) records the
//! polyline `_theta_star_b` returned, so every trace entry is a search whose
//! ANSWER is known. Its INPUTS are rebuilt by `mv::replay`, which marks the
//! entries trace v1 cannot pin down (the body discs of a model that
//! `_pull_into_placed` may have moved) — those are counted, never guessed at.
//! Positions are f32 on both sides, so the comparison is exact equality.
//!
//! WHAT THE RED PROOFS FOUND. Only ONE of the three bends moves a recorded path
//! often enough to fail the corpus gate: raising `fast_planner_guard` from 320
//! to 640 (14 mismatches over the 16-game corpus, 229 paths moved). The other
//! two are load-bearing but almost never DECIDE anything on real boards — a
//! strict open-list compare moves 2 paths in 11 758, swapping THETA_DIAG entries
//! moves none — so they are proven here on hand-built boards that force the tie
//! instead, which is the only place the rule is reachable at all. That is a
//! finding about the corpus, not a licence to simplify: both rules DO decide,
//! and the two tests below are the falsification.

use nml_core::mv::cost::{empty_cells, step_blocked, CellSet, Grid, StepOpts, Wall, Zone};
use nml_core::mv::geom2::{polyline_length, V2};
use nml_core::mv::replay::searches;
use nml_core::mv::theta::{
    board_extents, cell_before, cell_center_fine, theta_star_b, theta_star_bent, ThetaBend,
    ThetaCfg, ThetaOpts,
};
use nml_core::mv::{load_moves, MoveCorpus, EPS, PLAN_CELL_IN};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/moves_s27.jsonl");

fn corpus() -> MoveCorpus {
    load_moves(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

struct Tally {
    total: usize,
    determined: usize,
    expanded: usize,
    matched: usize,
    moved: usize,
}

/// Replays every recorded search under `bend` (and an optional guard override),
/// counting matches against the recording and paths the bend MOVED.
fn replay(c: &MoveCorpus, bend: ThetaBend, guard: Option<i64>) -> Tally {
    let shipped = ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard);
    let cfg = ThetaCfg::of(c.header.fast_planner, guard.unwrap_or(c.header.fast_planner_guard));
    // The shipped run is only needed to measure what a BEND moved.
    let bending = bend.strict_open || bend.diag_swap.is_some() || guard.is_some();
    let mut t = Tally { total: 0, determined: 0, expanded: 0, matched: 0, moved: 0 };
    for (ci, call) in c.calls.iter().enumerate() {
        for s in searches(ci, call, &c.header) {
            t.total += 1;
            let got = s.run_bent(call, cfg, bend);
            if bending && got != s.run(call, shipped) {
                t.moved += 1;
            }
            if !s.determined {
                continue;
            }
            t.determined += 1;
            if s.expected.len() >= 3 {
                t.expanded += 1;
            }
            if got == s.expected {
                t.matched += 1;
            }
        }
    }
    t
}

// === G2 — the corpus gate ===================================================

#[test]
fn g2a_theta_star_reproduces_every_determined_recorded_search_node_for_node() {
    let c = corpus();
    c.header.constants.check().unwrap_or_else(|e| panic!("corpus constants: {e}"));
    assert!(c.header.fast_planner, "the arena corpus must be a fast_planner recording");
    assert_eq!(c.header.fast_planner_guard, 320, "the recorded guard is the shipped 320");
    let t = replay(&c, ThetaBend::default(), None);
    assert_eq!(
        t.matched, t.determined,
        "{} of {} determined searches diverge (run the mvtheta binary for the first one)",
        t.determined - t.matched,
        t.determined
    );
    // Guard against a vacuous gate: a two-node answer can come from four
    // unchecked fallbacks, so demand that the EXPANSION LOOP is what produced a
    // large share of the judged answers.
    assert!(
        t.expanded >= 50,
        "only {} of {} determined searches ran the expansion loop",
        t.expanded,
        t.determined
    );
}

#[test]
fn g2_census() {
    let c = corpus();
    let t = replay(&c, ThetaBend::default(), None);
    println!(
        "G2 fixture: {} calls, {} recorded searches, {} determined ({} of them expanded), \
         {} matched, {} undetermined by trace v1",
        c.calls.len(),
        t.total,
        t.determined,
        t.expanded,
        t.matched,
        t.total - t.determined
    );
}

// === RED (c) — the guard is load-bearing ====================================

#[test]
fn red_c_raising_the_fast_planner_guard_moves_recorded_paths() {
    let c = corpus();
    let t = replay(&c, ThetaBend::default(), Some(640));
    assert!(
        t.moved > 0,
        "guard 640 moved no path at all — the truncation is not being reproduced"
    );
    println!("RED c: guard 640 moves {} of {} replayed searches", t.moved, t.total);
}

// === A hand-built board where the two near-tie rules are reachable ==========
//
// 8x8 inches, no walls, no terrain. Two discs: one on the start→goal diagonal
// so the straight-shot early-out cannot fire, one on the (1,1) neighbour so the
// first expansion has exactly TWO legal successors, which are EQUIDISTANT from
// the goal — the only situation in which either near-tie rule decides anything.

fn tie_board() -> (Vec<Wall>, Grid, Vec<Zone>, V2, V2, V2) {
    let walls: Vec<Wall> = Vec::new();
    let grid: Grid = Grid::new();
    let zones = vec![
        Zone { c: [3.0, 3.0], r: 0.4 },  // blocks the straight start→goal line
        Zone { c: [1.5, 1.5], r: 0.3 },  // blocks the (1,1) diagonal successor
    ];
    (walls, grid, zones, [0.5, 0.5], [5.5, 5.5], board_extents(8.0, 0.0))
}

fn tie_opts<'a>(zones: &'a [Zone], fine: &'a CellSet) -> ThetaOpts<'a> {
    ThetaOpts {
        step: StepOpts { clearance: 0.0, zones, avoid_cells: fine, avoid_fine: fine },
        reach_closest: false,
    }
}

#[test]
fn red_b_swapping_two_theta_diag_entries_picks_a_different_reach_node() {
    let (walls, grid, zones, start, goal, board) = tie_board();
    let fine = CellSet::new();
    let o = tie_opts(&zones, &fine);
    // One expansion only: the loop relaxes (1,0) and (0,1), whose distances to
    // the goal are BIT-IDENTICAL (4²+5² == 5²+4²), so `rd < best_reach_d - EPS`
    // keeps whichever THETA_DIAG offered FIRST.
    let cfg = ThetaCfg::of(true, 1);
    let shipped = theta_star_b(start, goal, &walls, &grid, board, &o, cfg);
    assert_eq!(shipped, vec![start, cell_center_fine((1, 0))], "THETA_DIAG[0] is (1,0)");
    // THETA_DIAG[2] is (0,1): swap it to the front and the other one wins.
    let bent = theta_star_bent(
        start,
        goal,
        &walls,
        &grid,
        board,
        &o,
        cfg,
        ThetaBend { diag_swap: Some((0, 2)), ..Default::default() },
    );
    assert_eq!(bent, vec![start, cell_center_fine((0, 1))]);
    assert_ne!(shipped, bent, "the neighbour order decided this path");
}

#[test]
fn red_a_the_open_list_eps_rule_breaks_an_exact_tie_by_cell_order() {
    let (walls, grid, zones, start, goal, board) = tie_board();
    let fine = CellSet::new();
    let o = tie_opts(&zones, &fine);
    // Two expansions: the second pop chooses between (1,0) and (0,1), which now
    // carry an EXACTLY equal f. The shipped rule takes the `_cell_before`
    // smaller one — (0,1) — even though (1,0) was found first; a strict
    // `f < best_f` keeps (1,0).
    let cfg = ThetaCfg::of(true, 2);
    let shipped = theta_star_b(start, goal, &walls, &grid, board, &o, cfg);
    let bent = theta_star_bent(
        start,
        goal,
        &walls,
        &grid,
        board,
        &o,
        cfg,
        ThetaBend { strict_open: true, ..Default::default() },
    );
    assert_ne!(
        shipped, bent,
        "the EPS rule + _cell_before tie-break decided which node was expanded"
    );
    // The shipped run expanded (0,1) and reached up the Y axis; the strict one
    // expanded (1,0) and reached along X.
    assert!(shipped.last().unwrap()[1] > shipped.last().unwrap()[0]);
    assert!(bent.last().unwrap()[0] > bent.last().unwrap()[1]);
}

// === Unit tests =============================================================

#[test]
fn cell_before_is_the_world_frame_cell_order() {
    assert!(cell_before((0, 5), (1, -5)), "x wins before y is even read");
    assert!(!cell_before((1, -5), (0, 5)));
    assert!(cell_before((2, 3), (2, 4)), "equal x falls through to y");
    assert!(!cell_before((2, 4), (2, 3)));
    assert!(!cell_before((2, 3), (2, 3)), "it is a STRICT order — no self-tie");
    // Negative cells order the same way (the planner frame is 0-origin, but
    // `cell_of` floors, so a point just off the board yields -1).
    assert!(cell_before((-1, 0), (0, 0)));
}

#[test]
fn cell_center_fine_and_board_extents_mirror_godot() {
    assert_eq!(cell_center_fine((0, 0)), [0.5 * PLAN_CELL_IN as f32, 0.5]);
    assert_eq!(cell_center_fine((3, 7)), [3.5, 7.5]);
    assert_eq!(cell_center_fine((-1, -2)), [-0.5, -1.5]);
    // board_y_in 0 (or below EPS) means "square", #215.
    assert_eq!(board_extents(72.0, 0.0), [72.0, 72.0]);
    assert_eq!(board_extents(72.0, 48.0), [72.0, 48.0]);
    assert_eq!(board_extents(72.0, EPS), [72.0, 72.0], "EPS itself is not > EPS");
}

/// A hand-built 3x3" board: one disc in the middle cell. The straight line is
/// blocked, so the search runs, and the answer must be a legal bent path.
#[test]
fn theta_on_a_hand_built_3x3_grid_bends_around_the_middle_cell() {
    let walls: Vec<Wall> = Vec::new();
    let grid: Grid = Grid::new();
    let start: V2 = [0.5, 0.5];
    let goal: V2 = [2.5, 2.5];
    let board = board_extents(3.0, 3.0);
    let fine = CellSet::new();
    let cfg = ThetaCfg::default();

    // No obstacle at all: the early-out returns the straight line untouched.
    let clear = theta_star_b(
        start,
        goal,
        &walls,
        &grid,
        board,
        &ThetaOpts::new(StepOpts::new(0.0, &[])),
        cfg,
    );
    assert_eq!(clear, vec![start, goal], "a clear straight shot never enters the loop");

    let zones = vec![Zone { c: [1.5, 1.5], r: 0.6 }];
    let o = tie_opts(&zones, &fine);
    let path = theta_star_b(start, goal, &walls, &grid, board, &o, cfg);
    assert!(path.len() >= 3, "the path must bend, got {path:?}");
    assert_eq!(path[0], start);
    assert_eq!(*path.last().unwrap(), goal, "an unbounded search reaches the goal cell");
    for w in path.windows(2) {
        assert!(!step_blocked(w[0], w[1], &walls, &o.step), "leg {:?}->{:?} is blocked", w[0], w[1]);
    }
    assert!(
        polyline_length(&path) > nml_core::mv::distance_to(start, goal) + EPS,
        "going around costs more than the blocked straight line"
    );
    // Deterministic: same inputs, same answer.
    assert_eq!(path, theta_star_b(start, goal, &walls, &grid, board, &o, cfg));
    // `empty_cells()` is the shared empty set the flow's `oi` implies.
    assert!(empty_cells().is_empty());
}
