//! GATE G4 (NML-1073 M4-4) — the sequential flow, the progressive-coherency
//! pull, the charge branch and the endpoint 2-opt against the recorded corpus.
//!
//! The in-repo fixture is the head of one seed-27 arena game; the fleet gate
//! runs the same five comparisons over all 16 games with
//! `cargo run --release --bin mvflow -- <paths>`.
//!
//! WHAT IS JUDGED, per recorded `plan_unit_step` call:
//!
//!   order   the PLACEMENT order (`opts["flow_order"]`) — deferrals move a
//!           model to the back of it, so this is not just the initial sort
//!   entry   every attempt: which model, whether it deferred, and its endpoint
//!           AFTER `_pull_into_placed` (trace v2's `pull`)
//!   swap    `untangle_endpoints`' accepted swaps, in sweep order
//!   end     the endpoints after untangle, rebuilt from the trace
//!   search  every Theta* pop list the call produced, the untangle RE-ROUTES
//!           included — the count alone pins how many searches ran
//!
//! `search` is what makes the re-routes falsifiable at all: M4-2 aligned only
//! the flow's own searches and left the tail (86 lists over the 16 games)
//! unjudged, because a re-route has no trace entry of its own to hang off.
//! Here the whole list is compared, in order, node by node.
//!
//! WHAT THE RED PROOFS FOUND (16 games, 1 101 calls, 11 758 attempts,
//! 9 991 searches of which 86 are untangle re-routes):
//!
//!   * `UNTANGLE_PASSES` 3 instead of 4 — 10 calls' swap lists and endpoint
//!     sets diverge. Four sweeps is not decoration: a swap made late in one
//!     sweep can make an earlier pair worth swapping in the next, and the
//!     cascade runs three deep in the corpus.
//!   * the deferral rule disabled — 294 of 1 101 calls diverge (282 flow
//!     orders, 254 endpoint sets). This is the single most load-bearing rule in
//!     the stage.
//!   * `CONTACT_SLIDE_EPS_IN` 0 instead of 0.05 — 902 of 1 101 calls' search
//!     sets and 522 endpoint sets diverge. The GDScript's own comment at
//!     :1075-1081 says a zone of exactly the radii sum makes a packed model's
//!     every outgoing tangent step read as blocked; the corpus agrees loudly.

use nml_core::mv::cost::{empty_cells, StepOpts, Wall, Zone};
use nml_core::mv::flow::{
    centroid, flow_order, linked_r, plan_sequential_flow, pull_into_placed, recorded_endpoints,
    run_call, untangle_endpoints, FlowBend, FlowOpts,
};
use nml_core::mv::geom2::{distance_squared_to, distance_to, V2};
use nml_core::mv::io::MoveCall;
use nml_core::mv::theta::{board_extents, ThetaCfg};
use nml_core::mv::{load_moves, Grid, MoveCorpus, CONTACT_SLIDE_EPS_IN, EPS, UNTANGLE_PASSES};

const FIXTURE: &str =
    concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/moves_v2_s27_head.jsonl");

const TOL: f64 = 1e-9;

fn corpus() -> MoveCorpus {
    load_moves(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

#[derive(Default, Debug)]
struct Tally {
    calls: usize,
    entries: usize,
    searches: usize,
    reroutes: usize,
    pops: usize,
    /// order / entry / swap / end / search.
    ok: [usize; 5],
    bad: [usize; 5],
    /// Calls where the later stages were inert, so `planned` IS the flow's answer.
    inert: usize,
    inert_ok: usize,
}

fn near(a: V2, b: V2) -> bool {
    (a[0] as f64 - b[0] as f64).abs() <= TOL && (a[1] as f64 - b[1] as f64).abs() <= TOL
}

/// Replays every traced call of the fixture under `bend`.
fn replay(c: &MoveCorpus, bend: FlowBend) -> Tally {
    let cfg = ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard);
    let mut t = Tally::default();
    for call in &c.calls {
        if call.trace.flow.is_empty() && !call.model_pos.is_empty() {
            continue;
        }
        t.calls += 1;
        let got = run_call(call, cfg, bend);
        t.entries += got.entries.len();
        t.searches += got.searches.len();
        t.reroutes += got.searches.len() - got.flow_searches;
        for r in &call.trace.theta_searches {
            t.pops += r.len();
        }
        let want_end = recorded_endpoints(call).expect("trace v2 carries every `pull`");
        let flags = [
            got.order == call.flow_order,
            got.entries.len() == call.trace.flow.len()
                && got.entries.iter().zip(&call.trace.flow).all(|(m, r)| {
                    m.model as i64 == r.model
                        && m.deferred == r.deferred
                        && r.pulled.map(|p| p == m.pulled).unwrap_or(false)
                }),
            got.swaps == call.trace.untangle_swaps,
            got.result == want_end,
            got.searches.len() == call.trace.theta_searches.len()
                && got.searches.iter().zip(&call.trace.theta_searches).all(|(m, r)| {
                    m.len() == r.len()
                        && m.iter().zip(r).all(|(a, b)| {
                            (a.g - b.g).abs() <= TOL && a.parent == b.parent && a.open == b.open
                        })
                }),
        ];
        for (k, ok) in flags.iter().enumerate() {
            if *ok {
                t.ok[k] += 1;
            } else {
                t.bad[k] += 1;
            }
        }
        if want_end.len() == call.planned.len()
            && want_end.iter().zip(&call.planned).all(|(a, b)| near(*a, *b))
        {
            t.inert += 1;
            if got.result.iter().zip(&call.planned).all(|(a, b)| near(*a, *b)) {
                t.inert_ok += 1;
            }
        }
    }
    t
}

// === G4 — the corpus gate ===================================================

#[test]
fn g4_the_flow_reproduces_every_recorded_stage() {
    let c = corpus();
    c.header.constants.check().unwrap_or_else(|e| panic!("corpus constants: {e}"));
    let t = replay(&c, FlowBend::default());
    assert!(t.calls > 0, "the fixture carries no traced call");
    let names = ["flow order", "attempt/pull", "untangle swaps", "endpoints", "pop lists"];
    for k in 0..5 {
        assert_eq!(t.bad[k], 0, "{} diverges on {} of {} calls", names[k], t.bad[k], t.calls);
    }
    // Guard against a vacuous gate: the fixture must actually exercise the
    // deferral rule, the untangle re-routes and a real search population.
    assert!(t.entries > t.calls, "no call recorded more than one attempt per model");
    assert!(t.reroutes > 0, "no untangle re-route was replayed");
    assert!(t.pops > 1000, "only {} popped nodes over {} searches", t.pops, t.searches);
    assert_eq!(t.inert_ok, t.inert, "an inert call misses the recorded `planned`");
    assert!(t.inert > 0, "no call where solve_formation was inert — nothing ties to `planned`");
}

#[test]
fn g4_census() {
    let c = corpus();
    let t = replay(&c, FlowBend::default());
    println!(
        "G4 fixture: {} calls, {} attempts, {} searches ({} untangle re-routes, {} popped nodes); \
         order {} entry {} swap {} end {} search {}; {} calls tie to `planned`",
        t.calls, t.entries, t.searches, t.reroutes, t.pops,
        t.ok[0], t.ok[1], t.ok[2], t.ok[3], t.ok[4], t.inert
    );
}

// === RED (i) — the fourth untangle pass ======================================
//
// The fixture never needs a fourth sweep, so this one is HAND-BUILT: eight
// models on a line, endpoints shuffled across them, no walls. The cascade runs
// three sweeps deep and the FOURTH still swaps, so cutting the count to 3
// leaves two endpoints crossed. (Found by exhaustive search over small integer
// configurations; the corpus red proof is `mvflow --untangle-passes=3`, which
// moves 10 of the 1 101 recorded calls.)

fn cascade() -> (Vec<V2>, Vec<V2>, Vec<f64>) {
    let starts: Vec<V2> =
        [4.0, 1.0, 9.0, 7.0, 3.0, 8.0, 0.0, 0.0].iter().map(|x| [*x, 0.0]).collect();
    let ends: Vec<V2> =
        [3.0, 0.0, 0.0, 5.0, 7.0, 6.0, 8.0, 9.0].iter().map(|x| [*x, 5.0]).collect();
    (starts, ends, vec![0.5; 8])
}

fn run_untangle(passes: i64) -> (Vec<V2>, Vec<[i64; 2]>) {
    let (starts, ends, radii) = cascade();
    let walls: Vec<Wall> = Vec::new();
    let opts = StepOpts::new(0.0, &[]);
    let mut result = ends;
    let mut swaps = Vec::new();
    untangle_endpoints(&starts, &mut result, &radii, 100.0, &walls, &opts, passes, &mut swaps);
    (result, swaps)
}

#[test]
fn red_i_a_fourth_untangle_pass_still_swaps() {
    let (four, swaps4) = run_untangle(UNTANGLE_PASSES);
    let (three, swaps3) = run_untangle(3);
    assert_ne!(four, three, "three sweeps reached the same endpoints as four");
    assert_eq!(swaps4.len(), swaps3.len() + 1, "exactly one swap belongs to the fourth sweep");
    assert_eq!(*swaps4.last().unwrap(), [0, 3], "the fourth sweep swaps models 0 and 3");
    // Four sweeps is enough here: an eighth changes nothing.
    let (eight, _) = run_untangle(8);
    assert_eq!(four, eight, "the shipped four sweeps have converged");
    // And the swap really did shorten the two chords.
    let (starts, ends, _) = cascade();
    let total = |e: &[V2]| -> f64 {
        starts.iter().zip(e).map(|(s, t)| distance_to(*s, *t)).sum()
    };
    assert!(total(&four) < total(&three), "the fourth swap must shorten the chord sum");
    assert!(total(&three) < total(&ends));
    println!("RED i: 4 sweeps {swaps4:?}\n       3 sweeps {swaps3:?}");
}

// === RED (j)/(k) — the deferral rule and the contact epsilon =================

fn diverging_calls(bend: FlowBend) -> Tally {
    replay(&corpus(), bend)
}

#[test]
fn red_j_disabling_the_deferral_rule_moves_recorded_calls() {
    let t = diverging_calls(FlowBend { no_defer: true, ..Default::default() });
    let bad: usize = t.bad.iter().sum();
    assert!(bad > 0, "the deferral rule left all {} fixture calls intact", t.calls);
    println!(
        "RED j: no_defer -> order {} entry {} swap {} end {} search {} of {} calls diverge \
         (16 games: 282 / 294 / 133 / 254 / 294 of 1101)",
        t.bad[0], t.bad[1], t.bad[2], t.bad[3], t.bad[4], t.calls
    );
}

#[test]
fn red_k_a_zero_contact_slide_eps_moves_recorded_calls() {
    let t = diverging_calls(FlowBend { contact_slide_eps_in: 0.0, ..Default::default() });
    let bad: usize = t.bad.iter().sum();
    assert!(bad > 0, "CONTACT_SLIDE_EPS_IN left all {} fixture calls intact", t.calls);
    println!(
        "RED k: slide_eps 0 -> order {} entry {} swap {} end {} search {} of {} calls diverge \
         (16 games: 238 / 531 / 216 / 522 / 902 of 1101)",
        t.bad[0], t.bad[1], t.bad[2], t.bad[3], t.bad[4], t.calls
    );
}

// === Unit tests — the flow order ============================================

#[test]
fn flow_order_is_nearest_to_the_destination_first() {
    // `goal_anchor` is the CENTROID plus delta, not any one model's slot.
    let pos: Vec<V2> = vec![[0.0, 0.0], [3.0, 0.0], [10.0, 0.0]];
    assert_eq!(centroid(&pos), [13.0 / 3.0, 0.0]);
    assert_eq!(flow_order(&pos, [0.0, 0.0]), vec![1, 0, 2]);
    // Push the anchor past the far model and the order reverses.
    assert_eq!(flow_order(&pos, [20.0, 0.0]), vec![2, 1, 0]);
}

#[test]
fn a_flow_order_tie_goes_to_the_lower_index() {
    // Two models, so the centroid sits exactly between them: every delta of 0
    // leaves both EXACTLY equidistant, and the tie-break is the model index.
    let pos: Vec<V2> = vec![[0.0, 0.0], [2.0, 0.0]];
    assert_eq!(flow_order(&pos, [0.0, 0.0]), vec![0, 1]);
    // The mirror image orders the same way — the tie-break is the INDEX, not
    // the geometry.
    let mirrored: Vec<V2> = vec![[2.0, 0.0], [0.0, 0.0]];
    assert_eq!(flow_order(&mirrored, [0.0, 0.0]), vec![0, 1]);
}

#[test]
fn the_flow_order_tie_band_is_eps_on_the_squared_distance() {
    // anchor = centroid + delta = [1 + d, 0]; da - db = 4d, so d = 2e-5 lands
    // INSIDE the EPS band (8e-5) and d = 5e-5 falls outside it (2e-4). Model 1
    // is genuinely nearer in both cases; only the second one gets to go first.
    let pos: Vec<V2> = vec![[0.0, 0.0], [2.0, 0.0]];
    let anchor = |d: f32| -> V2 { [1.0 + d, 0.0] };
    let gap = |d: f32| -> f64 {
        distance_squared_to(pos[0], anchor(d)) - distance_squared_to(pos[1], anchor(d))
    };
    assert!(gap(2.0e-5) > 0.0 && gap(2.0e-5) <= EPS, "gap {} is not inside the band", gap(2.0e-5));
    assert!(gap(5.0e-5) > EPS, "gap {} is not outside the band", gap(5.0e-5));
    assert_eq!(flow_order(&pos, [2.0e-5, 0.0]), vec![0, 1], "a near-tie keeps the index order");
    assert_eq!(flow_order(&pos, [5.0e-5, 0.0]), vec![1, 0], "outside the band, distance decides");
}

// === Unit tests — the progressive-coherency pull =============================

#[test]
fn pull_into_placed_steps_a_lone_model_into_its_neighbours_link() {
    let radii = vec![0.5, 0.5];
    let result: Vec<V2> = vec![[0.0, 0.0], [10.0, 0.0]];
    let walls: Vec<Wall> = Vec::new();
    let board = board_extents(40.0, 40.0);
    // 10" apart, link distance 0.5 + 0.5 + 1.0 = 2.0: eight 1" steps.
    assert!(!linked_r(result[1], result[0], 0.5, 0.5));
    let got = pull_into_placed(
        result[1], 1, &radii, &[0], &result, &walls, 0.0, &[], empty_cells(), board,
    );
    assert_eq!(got, [2.0, 0.0], "the pull stops the instant the bases link");
    assert!(linked_r(got, result[0], 0.5, 0.5));
    // Already linked: `pos` comes back untouched, no step taken.
    let close: Vec<V2> = vec![[0.0, 0.0], [2.0, 0.0]];
    assert_eq!(
        pull_into_placed(close[1], 1, &radii, &[0], &close, &walls, 0.0, &[], empty_cells(), board),
        [2.0, 0.0]
    );
}

#[test]
fn pull_into_placed_stops_at_the_first_blocked_step() {
    let radii = vec![0.5, 0.5];
    let result: Vec<V2> = vec![[0.0, 0.0], [10.0, 0.0]];
    let walls: Vec<Wall> = Vec::new();
    let board = board_extents(40.0, 40.0);
    // Another unit's disc sits on the lane at 5": the step INTO it is refused,
    // and the pull breaks rather than sliding around — the neighbour's own body
    // is deliberately not a zone, but everyone else's is.
    let zones = vec![Zone { c: [5.0, 0.0], r: 0.6 }];
    let got = pull_into_placed(
        result[1], 1, &radii, &[0], &result, &walls, 0.0, &zones, empty_cells(), board,
    );
    assert_eq!(got, [6.0, 0.0], "the pull halts one step short of the disc");
    assert!(!linked_r(got, result[0], 0.5, 0.5), "and the models stay unlinked");
}

/// A hand-built two-model flow: the rear model walks its full 8" budget, is
/// still 8" behind the leader, and the coherency pull then drags it another 6"
/// forward — the pull is NOT allowance-bounded, which is exactly why the
/// caller trims the polyline afterwards (solo_controller.gd:4636-4646).
#[test]
fn a_two_model_flow_places_the_leader_then_pulls_the_straggler_in() {
    let pos: Vec<V2> = vec![[4.0, 10.0], [12.0, 10.0]];
    let radii = vec![0.5, 0.5];
    let delta: V2 = [8.0, 0.0];
    let walls: Vec<Wall> = Vec::new();
    let grid = Grid::new();
    let opts = FlowOpts {
        clearance: 0.0,
        zones: &[],
        zones_rest_only: false,
        avoid_cells: empty_cells(),
        board_y_in: 40.0,
        charge_allowance: None,
        charge_goal: None,
        charge_tgt_bases: &[],
        charge_slots: &[],
    };
    let got = plan_sequential_flow(
        &pos, delta, &radii, &walls, &grid, &opts, 40.0, false, ThetaCfg::default(),
        FlowBend::default(),
    );
    assert_eq!(got.order, vec![1, 0], "the model nearer the destination files first");
    assert_eq!(got.result[1], [20.0, 10.0], "the leader spends its whole 8\" budget");
    assert_eq!(got.result[0], [18.0, 10.0], "the straggler walks 8\" and is pulled 6\" more");
    assert!(linked_r(got.result[0], got.result[1], 0.5, 0.5), "the pull restored the link");
    // The pull appended its endpoint to the trail, so the drawn corridor is
    // truthful even though it is now longer than the move budget.
    assert_eq!(got.trails[0], vec![[4.0, 10.0], [12.0, 10.0], [18.0, 10.0]]);
    assert_eq!(got.trails[1], vec![[12.0, 10.0], [20.0, 10.0]]);
    assert_eq!(got.entries.len(), 2, "nobody deferred");
    assert!(got.entries.iter().all(|e| !e.deferred));
    assert_eq!(got.entries[1].walked.last(), Some(&[12.0, 10.0]), "walked is the PRE-pull leg");
    assert_eq!(got.entries[1].pulled, [18.0, 10.0], "and `pulled` is what the trace records");
    assert!(got.swaps.is_empty(), "a swap would need both new chords inside the 8\" allowance");
    assert!(got.searches.is_empty(), "both straight shots took the early-out");
}

// === Unit tests — the leaves ================================================

#[test]
fn linked_r_is_the_radii_aware_one_inch_link() {
    // 1" of clear air between the two BASES, plus the shared EPS.
    assert!(linked_r([0.0, 0.0], [3.0, 0.0], 1.0, 1.0), "edge gap exactly 1.0 links");
    assert!(!linked_r([0.0, 0.0], [3.01, 0.0], 1.0, 1.0));
    assert!(linked_r([0.0, 0.0], [2.0, 0.0], 0.5, 0.5));
    assert!(!linked_r([0.0, 0.0], [2.5, 0.0], 0.5, 0.5));
}

#[test]
fn centroid_of_nothing_is_the_origin() {
    assert_eq!(centroid(&[]), [0.0, 0.0]);
    assert_eq!(centroid(&[[3.0, -1.0]]), [3.0, -1.0]);
    assert_eq!(centroid(&[[0.0, 0.0], [4.0, 2.0]]), [2.0, 1.0]);
}

#[test]
fn untangle_needs_both_new_chords_inside_the_allowance() {
    // A textbook crossing: the swap halves the chord sum, but only if the
    // allowance can pay for both new chords.
    let starts: Vec<V2> = vec![[0.0, 0.0], [4.0, 0.0]];
    let ends: Vec<V2> = vec![[4.0, 3.0], [0.0, 3.0]];
    let radii = vec![0.5, 0.5];
    let walls: Vec<Wall> = Vec::new();
    let so = StepOpts::new(0.0, &[]);

    let mut r = ends.clone();
    let mut swaps = Vec::new();
    assert!(untangle_endpoints(&starts, &mut r, &radii, 5.0, &walls, &so, UNTANGLE_PASSES, &mut swaps));
    assert_eq!(r, vec![[0.0, 3.0], [4.0, 3.0]], "the crossing is undone");
    assert_eq!(swaps, vec![[0, 1]]);

    // Same geometry, an allowance that only the CROSSED chords fit: no swap.
    let mut r = ends.clone();
    let mut swaps = Vec::new();
    assert!(!untangle_endpoints(&starts, &mut r, &radii, 2.9, &walls, &so, UNTANGLE_PASSES, &mut swaps));
    assert_eq!(r, ends, "a swap may never grant an illegal move length");
    assert!(swaps.is_empty());

    // Different radii: the pair is skipped whatever the geometry says.
    let mut r = ends.clone();
    let mut swaps = Vec::new();
    let mixed = vec![0.5, 1.0];
    assert!(!untangle_endpoints(&starts, &mut r, &mixed, 5.0, &walls, &so, UNTANGLE_PASSES, &mut swaps));
    assert_eq!(r, ends, "endpoints of unequal bases are not interchangeable");
}

/// A hand-built one-model charge. The fixture carries no `allow_contact` call
/// (there are 11 in the 16 games), so the branch would otherwise be untested by
/// `cargo test`: the charge aims at its own contact SLOT, not at the body goal,
/// treats the target's base as a no-through disc, and skips both the deferral
/// rule and the coherency pull.
fn charge_flow(slot: V2, allowance: f64) -> nml_core::mv::FlowResult {
    let pos: Vec<V2> = vec![[10.0, 10.0]];
    let radii = vec![0.5];
    let walls: Vec<Wall> = Vec::new();
    let grid = Grid::new();
    let bases = [([20.0f32, 10.0f32], 1.0f64)];
    let slots = [slot];
    let opts = FlowOpts {
        clearance: 0.0,
        zones: &[],
        zones_rest_only: false,
        avoid_cells: empty_cells(),
        board_y_in: 40.0,
        charge_allowance: Some(allowance),
        charge_goal: Some([20.0, 10.0]),
        charge_tgt_bases: &bases,
        charge_slots: &slots,
    };
    plan_sequential_flow(
        &pos, [8.0, 0.0], &radii, &walls, &grid, &opts, 40.0, true, ThetaCfg::default(),
        FlowBend::default(),
    )
}

#[test]
fn a_charge_walks_up_to_its_contact_slot_and_stops_at_the_base() {
    // The near face: 20 - (1.0 + 0.5) = 18.5, a clear straight shot.
    let got = charge_flow([18.5, 10.0], 12.0);
    assert_eq!(got.order, vec![0]);
    assert_eq!(got.result[0], [18.5, 10.0], "the charge closes to base contact");
    assert_eq!(got.trails[0], vec![[10.0, 10.0], [18.5, 10.0]]);
    assert!(got.searches.is_empty(), "a clear lane takes the straight-shot early-out");
    assert!(got.swaps.is_empty(), "a charge is exempt from the untangle");
    assert_eq!(got.entries[0].pulled, got.result[0], "a charge never runs the coherency pull");
}

#[test]
fn a_charge_bends_around_the_targets_own_base_instead_of_cutting_through() {
    // A slot on the FAR face: the straight line would cross the target's body,
    // which is a hard no-through zone, so reach_closest has to bend the route.
    let got = charge_flow([21.5, 10.0], 24.0);
    assert!(!got.searches.is_empty(), "the blocked lane must run a real search");
    let end = got.result[0];
    // r = 1.0 + 0.5 - CONTACT_SLIDE_EPS_IN: the boundary IS the legal kiss.
    let r = 1.0 + 0.5 - CONTACT_SLIDE_EPS_IN;
    assert!(
        distance_to(end, [20.0, 10.0]) >= r - 1e-6,
        "the endpoint {end:?} is inside the target's base"
    );
    assert!(end[1] != 10.0 || end[0] > 20.0, "the route did not go around: {end:?}");
    assert!(got.swaps.is_empty());
}

#[test]
fn the_charge_branch_is_the_thin_one() {
    // 11 of the 16 games' 1 101 calls are charges; the fixture may carry none,
    // so this only asserts the SHAPE the loader gives them.
    let c = corpus();
    for call in &c.calls {
        if !call.allow_contact {
            continue;
        }
        assert!(call.opts.charge_goal.is_some(), "a charge call without a body goal");
        assert!(call.opts.charge_allowance.is_some(), "a charge call without its own band");
        let cfg = ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard);
        let got = run_call(call, cfg, FlowBend::default());
        assert!(got.swaps.is_empty(), "a charge is exempt from the untangle");
        assert_eq!(got.order.len(), call.model_pos.len(), "a charge never defers");
    }
}

#[test]
fn the_recorded_endpoints_helper_needs_a_final_entry_per_model() {
    let c = corpus();
    for call in &c.calls {
        let end = recorded_endpoints(call);
        if call.trace.flow.is_empty() {
            continue;
        }
        let end = end.expect("trace v2 supplies a `pull` for every attempt");
        assert_eq!(end.len(), call.model_pos.len());
    }
    // A call with no trace at all cannot supply endpoints.
    let mut blank: MoveCall = c.calls[0].clone();
    blank.trace.flow.clear();
    assert!(recorded_endpoints(&blank).is_none() || blank.model_pos.is_empty());
    assert_eq!(CONTACT_SLIDE_EPS_IN, 0.05);
}
