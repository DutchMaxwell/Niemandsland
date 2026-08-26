//! GATE G5 (NML-1073 M4-5) — `solve_formation`, `charge_contact_slots`, the
//! p.11 difficult cap and the whole `plan_unit_step` against the recorded
//! corpus.
//!
//! The in-repo fixture is the head of one seed-27 arena game; the fleet gate
//! runs the same four comparisons over all 16 games with
//! `cargo run --release --bin mvform -- <paths>`.
//!
//! WHAT IS JUDGED, per recorded `plan_unit_step` call:
//!
//!   solve    `solve_formation`'s positions AND score after EVERY sweep, against
//!            `trace.solve_passes` — an end-state comparison would let a pass
//!            reach the right answer by the wrong route
//!   slots    `charge_contact_slots` against `opts["charge_slots"]`, the value
//!            the CALLER computed and passed in (solo_controller.gd:6033)
//!   planned  the returned positions, f32-exact against `planned`
//!   trails   the returned polylines, f32-exact against `trails`
//!
//! WHAT THE RED PROOFS FOUND (16 games, 1 101 calls, 655 of which run the
//! solver, 11 849 recorded sweeps, 833 polylines trimmed by the cap):
//!
//!   * `SOLVE_PASSES` 23 instead of 24 — 450 calls' sweep lists and 43 calls'
//!     final positions diverge. The 24th sweep is not decoration: on 450 of the
//!     655 solving calls the solver never reaches a legal configuration at all,
//!     so it runs the full budget and the best-of rule can still adopt the very
//!     last pass.
//!   * `_project_separate` swept backwards — 290 sweep lists and 255 final
//!     position sets diverge. Gauss-Seidel is the algorithm, not an artefact:
//!     the pair loop reads the positions its earlier pairs already pushed.
//!   * the p.11 cap moved by ONE plan cell — +1" leaves 219 calls wrong (147
//!     polylines that should have been trimmed keep the full band), -1" leaves
//!     339 wrong (676 extra polylines cut). 6.0" is load-bearing to the inch.

use nml_core::mv::cap::{cap_difficult_polylines, trail_crosses_difficult_cells};
use nml_core::mv::charge::{charge_contact_slots, nearest_base_dist};
use nml_core::mv::cost::{Wall, Zone};
use nml_core::mv::form::{
    coherency_penalty, components_r, formation_score, max_edge_spread_r, project_separate,
    solve_formation, wall_zone_blocked, FormBend, SolveOpts,
};
use nml_core::mv::geom2::{distance_to, polyline_length, V2};
use nml_core::mv::plan::{plan_unit_step, plan_unit_step_cfg, PlanBend};
use nml_core::mv::theta::{board_extents, ThetaCfg};
use nml_core::mv::{load_moves, CellSet, Grid, MoveCorpus, EPS, SOLVE_PASSES, T_FOREST};

const FIXTURE: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/moves_v2_s27_head.jsonl");

const TOL: f64 = 1e-9;

fn corpus() -> MoveCorpus {
    load_moves(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

#[derive(Default, Debug)]
struct Tally {
    calls: usize,
    solving: usize,
    passes: usize,
    trimmed: usize,
    charges: usize,
    /// solve / slots / planned / trails / flow_order.
    ok: [usize; 5],
    bad: [usize; 5],
}

fn replay(c: &MoveCorpus, bend: PlanBend) -> Tally {
    let cfg = ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard);
    let mut t = Tally::default();
    for call in &c.calls {
        t.calls += 1;
        let got = plan_unit_step_cfg(call, cfg, bend);
        t.passes += got.solve.passes.len();
        if !got.solve.passes.is_empty() {
            t.solving += 1;
        }
        t.trimmed += got.cap.trimmed;
        let slots_ok = if call.allow_contact && !call.opts.charge_tgt_bases.is_empty() {
            t.charges += 1;
            charge_contact_slots(&call.model_pos, &call.opts.radii, &call.opts.charge_tgt_bases)
                == call.opts.charge_slots
        } else {
            true
        };
        let flags = [
            got.solve.passes.len() == call.trace.solve_passes.len()
                && got.solve.passes.iter().zip(&call.trace.solve_passes).all(|(m, r)| {
                    m.positions == r.positions && (m.score - r.score).abs() <= TOL
                }),
            slots_ok,
            got.planned == call.planned,
            got.trails == call.trails,
            got.flow_order == call.flow_order,
        ];
        for (k, ok) in flags.iter().enumerate() {
            if *ok {
                t.ok[k] += 1;
            } else {
                t.bad[k] += 1;
            }
        }
    }
    t
}

// === G5 — the corpus gate ===================================================

#[test]
fn g5_the_whole_pipeline_reproduces_every_recorded_call() {
    let c = corpus();
    c.header.constants.check().unwrap_or_else(|e| panic!("corpus constants: {e}"));
    let t = replay(&c, PlanBend::default());
    assert!(t.calls > 0, "the fixture carries no call");
    let names = ["solve sweeps", "charge slots", "planned", "trails", "flow order"];
    for k in 0..5 {
        assert_eq!(t.bad[k], 0, "{} diverges on {} of {} calls", names[k], t.bad[k], t.calls);
    }
    // Guard against a vacuous gate: the fixture must actually run the solver
    // (more than one sweep) and actually fire the difficult cap.
    assert!(t.solving > 0, "no fixture call ran solve_formation");
    assert!(t.passes > 1, "only {} solver sweeps replayed", t.passes);
    assert!(t.trimmed > 0, "the p.11 difficult cap never fired");
}

#[test]
fn g5_census() {
    let t = replay(&corpus(), PlanBend::default());
    println!(
        "G5 fixture: {} calls, {} ran solve_formation ({} sweeps), {} polylines capped, \
         {} charges; solve {} slots {} planned {} trails {} order {}",
        t.calls, t.solving, t.passes, t.trimmed, t.charges,
        t.ok[0], t.ok[1], t.ok[2], t.ok[3], t.ok[4]
    );
}

/// `plan_unit_step(call)` bakes in the SHIPPED search configuration
/// (`fast_planner`, guard 320 — main.gd:2269-2275). Every recorded header
/// carries exactly that, so the convenience entry and the header-driven one
/// must agree call for call; if a future corpus is recorded with another guard,
/// this is what catches it.
#[test]
fn the_shipped_theta_config_is_the_one_the_corpus_recorded() {
    let c = corpus();
    assert!(c.header.fast_planner, "the corpus was recorded without fast_planner");
    assert_eq!(c.header.fast_planner_guard, 320);
    let cfg = ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard);
    for call in &c.calls {
        let a = plan_unit_step(call);
        let b = plan_unit_step_cfg(call, cfg, PlanBend::default());
        assert_eq!(a.planned, b.planned);
        assert_eq!(a.trails, b.trails);
        assert_eq!(a.flow_order, b.flow_order);
    }
}

// === RED (l) — the 24th sweep ===============================================

#[test]
fn red_l_a_shorter_solver_budget_moves_recorded_calls() {
    let t = replay(&corpus(), PlanBend {
        form: FormBend { solve_passes: 23, ..Default::default() },
        ..Default::default()
    });
    let bad: usize = t.bad.iter().sum();
    assert!(bad > 0, "23 sweeps left all {} fixture calls intact", t.calls);
    println!(
        "RED l: solve_passes 23 -> solve {} planned {} trails {} of {} calls diverge \
         (16 games: 450 / 43 / 43 of 1101)",
        t.bad[0], t.bad[2], t.bad[3], t.calls
    );
}

// === RED (m) — the Gauss-Seidel sweep order =================================
//
// The fixture's two solving calls never contain an overlapping TRIPLE, so
// reversing the pair order leaves them alone (the 16-game corpus moves 255
// calls). This one is therefore HAND-BUILT: three 1"-radius bases in a row,
// each overlapping its neighbour, is the smallest configuration where the
// second pair reads what the first pair already wrote.

fn triple() -> (Vec<V2>, Vec<f64>) {
    (vec![[10.0, 10.0], [11.0, 10.0], [12.0, 10.0]], vec![1.0, 1.0, 1.0])
}

fn one_separation_sweep(reverse: bool) -> Vec<V2> {
    let (mut out, radii) = triple();
    let walls: Vec<Wall> = Vec::new();
    project_separate(&mut out, &radii, &walls, 0.0, &[], board_extents(40.0, 40.0), reverse);
    out
}

#[test]
fn red_m_reversing_the_gauss_seidel_pairs_changes_the_sweep() {
    let fwd = one_separation_sweep(false);
    let rev = one_separation_sweep(true);
    assert_ne!(fwd, rev, "the pair order made no difference — the sweep is not Gauss-Seidel");
    // Forward, pair (0,1) fires first and its push moves model 1 INTO model 2,
    // so pair (1,2) then pushes harder than it would have.
    assert!(fwd[1] < rev[1], "forward {fwd:?} vs reverse {rev:?}");
    assert!(fwd[2] > rev[2], "forward {fwd:?} vs reverse {rev:?}");
    // A Jacobi sweep (every pair reading the ORIGINAL positions) would be
    // symmetric about the centre model; neither of these is.
    assert!((fwd[1][0] - 11.0).abs() > 0.01 && (rev[1][0] - 11.0).abs() > 0.01);
    println!("RED m: forward {fwd:?}\n       reverse {rev:?} (16 games: 290 sweeps / 255 planned)");
}

// === RED (n) — the p.11 cap threshold =======================================

#[test]
fn red_n_moving_the_difficult_cap_by_one_cell_moves_recorded_calls() {
    for delta in [1.0f64, -1.0] {
        let t = replay(&corpus(), PlanBend { cap_delta_in: delta, ..Default::default() });
        let bad: usize = t.bad.iter().sum();
        assert!(bad > 0, "a cap shifted by {delta}\" left all {} fixture calls intact", t.calls);
        println!(
            "RED n: cap {delta:+}\" -> planned {} trails {} of {} calls diverge, {} polylines cut \
             (16 games: +1\" 219 calls / 686 cut, -1\" 339 calls / 1509 cut)",
            t.bad[2], t.bad[3], t.calls, t.trimmed
        );
    }
}

// === Unit tests — the hand-built 3-model formation ==========================

/// Three overlapping 1" bases in a row, nothing else on the table: the solver
/// must separate them, and it must STOP the moment the configuration is legal
/// rather than spending all 24 sweeps.
#[test]
fn a_three_model_formation_is_separated_and_the_solver_stops_early() {
    let (pos, radii) = triple();
    let walls: Vec<Wall> = Vec::new();
    let forbid = CellSet::new();
    let opts = SolveOpts { clearance: 0.0, zones: &[], forbid_cells: &forbid, board_y_in: 40.0 };
    // The desired formation is illegal: two overlaps of exactly 1" each.
    assert!((formation_score(&pos, &radii, &forbid, &[]) - 2.0 * 40.0).abs() < 1e-9);
    let got = solve_formation(&pos, &radii, &walls, &opts, 40.0, false, FormBend::default());
    assert!(!got.passes.is_empty(), "the solver short-circuited on an illegal formation");
    assert!(
        (got.passes.len() as i64) < SOLVE_PASSES,
        "the solver used all {SOLVE_PASSES} sweeps on a trivial row"
    );
    // Every pair is clear, and the unit is still one coherent chain.
    for i in 0..3 {
        for j in (i + 1)..3 {
            assert!(
                distance_to(got.best[i], got.best[j]) >= radii[i] + radii[j] - EPS,
                "models {i}/{j} still overlap in {:?}",
                got.best
            );
        }
    }
    assert_eq!(components_r(&got.best, &radii).len(), 1, "the row broke into pieces");
    assert!(coherency_penalty(&got.best, &radii) == 0.0);
    assert!(max_edge_spread_r(&got.best, &radii) <= 9.0);
    // The last sweep IS the adopted one here — it is the first legal sweep, and
    // the loop breaks on it.
    assert_eq!(got.best, got.passes.last().unwrap().positions);
    assert!(got.passes.last().unwrap().score <= EPS);
    // The scores fall monotonically on this configuration.
    for w in got.passes.windows(2) {
        assert!(w[1].score < w[0].score, "scores {:?}", got.passes);
    }
    println!(
        "3-model row: {} sweeps, final {:?}, score {}",
        got.passes.len(),
        got.best,
        got.passes.last().unwrap().score
    );
}

/// A legal formation is returned VERBATIM and not a single sweep is traced —
/// movement_planner.gd:1595-1596, the short-circuit the recorder's empty
/// `solve_passes` list marks on 446 of the corpus's 1 101 calls.
#[test]
fn a_legal_formation_short_circuits_before_the_first_sweep() {
    let pos: Vec<V2> = vec![[10.0, 10.0], [12.5, 10.0], [15.0, 10.0]];
    let radii = vec![1.0, 1.0, 1.0];
    let forbid = CellSet::new();
    let opts = SolveOpts { clearance: 0.0, zones: &[], forbid_cells: &forbid, board_y_in: 40.0 };
    assert_eq!(formation_score(&pos, &radii, &forbid, &[]), 0.0);
    let got = solve_formation(&pos, &radii, &[], &opts, 40.0, false, FormBend::default());
    assert!(got.passes.is_empty(), "a legal formation must not run a sweep");
    assert_eq!(got.best, pos);
}

/// `forbid_cells` is read HERE and nowhere else: a model resting in a forbidden
/// 1" cell costs `W_TERRAIN`, and the terrain projection walks it out in 0.5"
/// rings. A charge drops the set entirely (movement_planner.gd:1588).
#[test]
fn the_forbid_set_is_the_solvers_own_and_a_charge_ignores_it() {
    let pos: Vec<V2> = vec![[10.5, 10.5]];
    let radii = vec![0.5];
    let mut forbid = CellSet::new();
    forbid.insert((10, 10));
    let opts = SolveOpts { clearance: 0.0, zones: &[], forbid_cells: &forbid, board_y_in: 40.0 };
    assert_eq!(formation_score(&pos, &radii, &forbid, &[]), 100.0);
    let got = solve_formation(&pos, &radii, &[], &opts, 40.0, false, FormBend::default());
    assert!(!forbid.contains(&nml_core::mv::cell_of(got.best[0], 1.0)), "still in the forbidden cell");
    assert!(distance_to(got.best[0], pos[0]) <= 0.5 + EPS, "pushed further than one ring");
    // allow_contact = true drops `forbid` -> nothing to solve, nothing traced.
    let charge = solve_formation(&pos, &radii, &[], &opts, 40.0, true, FormBend::default());
    assert!(charge.passes.is_empty());
    assert_eq!(charge.best, pos);
}

/// `_wall_zone_blocked` is `step_blocked` MINUS the avoid-cell tests: a model
/// may legally REST in Difficult, so only walls and spacing discs veto a
/// projection (movement_planner.gd:1560-1571).
#[test]
fn a_projection_step_is_gated_by_walls_and_zones_only() {
    let walls: Vec<Wall> = vec![[[11.0, 0.0], [11.0, 20.0]]];
    assert!(wall_zone_blocked([10.0, 10.0], [12.0, 10.0], &walls, 0.0, &[]));
    assert!(!wall_zone_blocked([10.0, 10.0], [10.5, 10.0], &walls, 0.0, &[]));
    let zones = vec![Zone { c: [12.0, 10.0], r: 1.0 }];
    assert!(wall_zone_blocked([10.0, 10.0], [11.5, 10.0], &[], 0.0, &zones));
    // Starting INSIDE a disc, only an outward step is legal.
    assert!(!wall_zone_blocked([11.5, 10.0], [10.0, 10.0], &[], 0.0, &zones));
}

// === Unit tests — the hand-built 2-slot charge contact ======================

/// Two chargers, one 1" enemy base: each gets its OWN point on the contact
/// circle, both exactly at base contact, and the second is repelled off the
/// first by 95 % of the two base radii (movement_planner.gd:962-966).
#[test]
fn a_two_model_charge_takes_two_distinct_contact_slots() {
    let mpos: Vec<V2> = vec![[10.0, 4.0], [11.0, 4.0]];
    let radii = vec![0.5, 0.5];
    let bases = [([10.0f32, 10.0f32], 1.0f64)];
    let slots = charge_contact_slots(&mpos, &radii, &bases);
    assert_eq!(slots.len(), 2);
    for s in &slots {
        assert!(
            (distance_to(*s, bases[0].0) - (bases[0].1 + 0.5)).abs() < 1e-5,
            "slot {s:?} is not on the contact circle"
        );
    }
    assert!(
        distance_to(slots[0], slots[1]) >= (0.5 + 0.5) * 0.95,
        "the two slots collide: {slots:?}"
    );
    // Both slots are on the CHARGERS' side of the base (they approach from -y).
    assert!(slots[0][1] < 10.0 && slots[1][1] < 10.0, "{slots:?}");
    // Model 0 is the nearer one, so it picks first and lands on the face point.
    assert!(nearest_base_dist(mpos[0], &bases) < nearest_base_dist(mpos[1], &bases));
    println!("2-slot charge: {slots:?}");
}

/// The fan widens to ten points for a SINGLE base (or a slot-scarce target), so
/// a horde can ring a monster instead of losing contacts —
/// movement_planner.gd:955-958. Six chargers on one base all get a slot.
#[test]
fn a_single_base_target_can_be_ringed() {
    let mpos: Vec<V2> = (0..6).map(|i| [8.0 + i as f32, 4.0]).collect();
    let radii = vec![0.5; 6];
    let bases = [([10.0f32, 10.0f32], 1.0f64)];
    let slots = charge_contact_slots(&mpos, &radii, &bases);
    assert_eq!(slots.len(), 6);
    for i in 0..6 {
        for j in (i + 1)..6 {
            assert!(distance_to(slots[i], slots[j]) > 1e-3, "models {i}/{j} share a slot");
        }
    }
    // Somebody had to go round the back — the near face alone cannot hold six.
    assert!(slots.iter().any(|s| s[1] > 10.0), "nobody went round: {slots:?}");
}

/// No target base, no slots — the caller then never sets `opts["charge_slots"]`
/// and the flow falls back to the body goal (movement_planner.gd:940).
#[test]
fn no_target_base_means_no_slots() {
    assert!(charge_contact_slots(&[[0.0, 0.0]], &[0.5], &[]).is_empty());
}

/// THE UNGATED TIE. `charge_contact_slots`' pick order is a bare `<` on
/// `_nearest_base_dist` (movement_planner.gd:944-945) with NO index fallback,
/// and `Array.sort_custom` is an unstable introsort — so two EXACTLY
/// equidistant chargers could be ordered either way in Godot, and the one that
/// picks first takes the better slot. This port breaks the tie on the model
/// index, which is a total order.
///
/// The 16-game corpus contains ZERO such ties (11 charge calls, every mover at
/// a distinct distance), so the corpus cannot falsify either choice; this test
/// pins the behaviour the port ships.
#[test]
fn an_exact_tie_in_the_charge_pick_order_goes_to_the_lower_index() {
    // Both chargers on the SAME spot: they are exactly equidistant, and they
    // want exactly the same slot.
    let mpos: Vec<V2> = vec![[10.0, 4.0], [10.0, 4.0]];
    let radii = vec![0.5, 0.5];
    let bases = [([10.0f32, 10.0f32], 1.0f64)];
    assert_eq!(nearest_base_dist(mpos[0], &bases), nearest_base_dist(mpos[1], &bases));
    let slots = charge_contact_slots(&mpos, &radii, &bases);
    // Model 0 picked first and took the face point straight below the base.
    assert!((slots[0][0] - 10.0).abs() < 1e-5 && (slots[0][1] - 8.5).abs() < 1e-5, "{slots:?}");
    assert!(distance_to(slots[1], bases[0].0) > 1.4, "model 1 was not repelled: {slots:?}");
    assert_ne!(slots[0], slots[1]);
    // And the answer is stable across calls.
    assert_eq!(slots, charge_contact_slots(&mpos, &radii, &bases));
}

// === Unit tests — the p.11 difficult cap ====================================

fn forest_grid() -> Grid {
    // One 3" typed cell of forest: cell (4, 3) covers x in [12, 15), y in [9, 12).
    let mut g = Grid::new();
    g.insert((4, 3), T_FOREST);
    g
}

#[test]
fn the_cap_trims_only_a_polyline_that_actually_enters_difficult() {
    let grid = forest_grid();
    let radii = vec![0.0, 0.0];
    // Trail 0 runs 10" through the forest cell; trail 1 runs 10" beside it.
    let mut trails: Vec<Vec<V2>> = vec![
        vec![[8.0, 10.0], [18.0, 10.0]],
        vec![[8.0, 2.0], [18.0, 2.0]],
    ];
    let mut solved: Vec<V2> = vec![[18.0, 10.0], [18.0, 2.0]];
    assert!(trail_crosses_difficult_cells(&trails[0], &grid, 0.0));
    assert!(!trail_crosses_difficult_cells(&trails[1], &grid, 0.0));
    let rep = cap_difficult_polylines(&mut trails, &mut solved, &radii, &grid, 6.0);
    assert_eq!(rep.trimmed, 1);
    assert_eq!(rep.over_but_clear, 1, "the clear trail is over the cap but untouched");
    assert!((polyline_length(&trails[0]) - 6.0).abs() < 1e-5);
    assert_eq!(solved[0], [14.0, 10.0], "the endpoint follows the cut");
    assert_eq!(trails[1], vec![[8.0, 2.0], [18.0, 2.0]], "the clear trail keeps the full band");
    assert_eq!(solved[1], [18.0, 2.0]);
}

#[test]
fn a_short_route_through_a_forest_is_never_trimmed() {
    let grid = forest_grid();
    let mut trails: Vec<Vec<V2>> = vec![vec![[12.5, 10.5], [16.0, 10.5]]];
    let mut solved: Vec<V2> = vec![[16.0, 10.5]];
    assert!(trail_crosses_difficult_cells(&trails[0], &grid, 0.0));
    let rep = cap_difficult_polylines(&mut trails, &mut solved, &[0.0], &grid, 6.0);
    assert_eq!(rep.trimmed, 0, "3.5\" is inside the 6\" cap");
    assert_eq!(solved[0], [16.0, 10.5]);
}

/// EDGE-AWARE (Testspiel-Welle 3): a base whose EDGE grazes a difficult cell
/// counts, even when its centre never enters one.
#[test]
fn the_base_edge_grazing_a_forest_counts() {
    let grid = forest_grid();
    // The centre line runs at y = 8.4, a clear 0.6" short of the cell's y = 9
    // edge; a 1" base reaches it, a 0.25" base does not.
    let leg: Vec<V2> = vec![[12.5, 8.4], [14.5, 8.4]];
    assert!(!trail_crosses_difficult_cells(&leg, &grid, 0.25));
    assert!(trail_crosses_difficult_cells(&leg, &grid, 1.0));
}

#[test]
fn an_empty_grid_or_a_zero_cap_disables_the_cap_entirely() {
    let mut trails: Vec<Vec<V2>> = vec![vec![[8.0, 10.0], [18.0, 10.0]]];
    let mut solved: Vec<V2> = vec![[18.0, 10.0]];
    let empty = Grid::new();
    assert_eq!(cap_difficult_polylines(&mut trails, &mut solved, &[0.0], &empty, 6.0).trimmed, 0);
    assert_eq!(
        cap_difficult_polylines(&mut trails, &mut solved, &[0.0], &forest_grid(), 0.0).trimmed,
        0
    );
    assert_eq!(solved[0], [18.0, 10.0]);
    assert!(!trail_crosses_difficult_cells(&trails[0], &empty, 0.0));
}
