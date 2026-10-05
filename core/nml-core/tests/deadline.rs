//! `deadline_us`, the per-decision allowance in microseconds from the planner
//! call. Off (0) leaves every pool pick unstamped; 10^9 µs never fires and must
//! leave every pick byte-identical; 1 µs is spent before the first rollout, so
//! every pool pick is the prefilter's top row, stamped with the fallback.
use nml_core::plan::{seams_of, Search};
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::Scratch;
use nml_core::{act_statics, load_acts, ActCorpus, Pick, SearchMode};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_wide_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

mod common;

fn corpus() -> ActCorpus {
    common::pin_legacy_no_cond_ap();
    load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

fn picks(c: &ActCorpus, deadline_us: i64) -> Vec<Pick> {
    picks_in(c, deadline_us, false)
}

/// `tree`: the same acts under `search_mode: tree` with a 32-leaf budget.
fn picks_in(c: &ActCorpus, deadline_us: i64, tree: bool) -> Vec<Pick> {
    picks_a3(c, deadline_us, tree, false, 0)
}

/// `picks_in` plus the A3 knob `deadline_after_preselect` (`after`) and the
/// `preselect_delay_us` seam that stretches every root preselection.
fn picks_a3(c: &ActCorpus, deadline_us: i64, tree: bool, after: bool, delay_us: u64) -> Vec<Pick> {
    let per_act = act_statics(c, REPO);
    let seams = seams_of(&c.knobs);
    let mut knobs = c.knobs;
    (knobs.deadline_us, knobs.deadline_after_preselect) = (deadline_us, after);
    if tree {
        (knobs.search_mode, knobs.tree_budget) = (SearchMode::Tree, 32);
    }
    let mut sc = Scratch::default();
    let mut out = Vec::new();
    for (ai, act) in c.acts.iter().enumerate() {
        let roll = Rollout::new(Policy::new(&per_act[ai], &c.terrain, seams), knobs);
        let mut search = Search::new(roll, &act.statics);
        search.bend.preselect_delay_us = delay_us;
        if let Ok(p) = search.run(&act.state, act.player, &mut sc, None) {
            out.push(p);
        }
    }
    out
}

/// The pool stamp without its clock: (completed, cut, fallback).
fn stamp(p: &Pick) -> Option<(usize, bool, Option<&'static str>)> {
    p.deadline.as_ref().map(|d| (d.completed, d.cut, d.fallback))
}

#[test]
fn a_deadline_that_never_fires_moves_no_pool_pick() {
    let c = corpus();
    let base = picks(&c, 0);
    assert!(base.len() >= 10, "enough answerable acts: {} picks", base.len());
    assert!(base.iter().all(|p| p.deadline.is_none()), "knob off must not stamp");
    let huge = picks(&c, 1_000_000_000);
    assert_eq!(base.len(), huge.len());
    for (i, (b, h)) in base.iter().zip(&huge).enumerate() {
        assert_eq!((&b.unit_key, &b.pool_idx, &b.rs), (&h.unit_key, &h.pool_idx, &h.rs), "act {i}");
        assert_eq!(b.expectation_after.to_bits(), h.expectation_after.to_bits(), "act {i}");
        assert_eq!(stamp(h), Some((b.pool_idx.len(), false, None)), "act {i}");
        assert!(h.deadline.as_ref().is_some_and(|d| d.elapsed_us > 0), "act {i}: the clock ran");
    }
}

#[test]
fn a_one_us_deadline_answers_every_pool_pick_with_the_top_row() {
    let c = corpus();
    let cut = picks(&c, 1);
    assert_eq!(cut.len(), picks(&c, 0).len());
    for (i, p) in cut.iter().enumerate() {
        assert_eq!(stamp(p), Some((0, true, Some("deadline_before_first_rollout"))), "act {i}");
        let top = &p.scored[0];
        assert_eq!((&p.unit_key, p.action.kind, p.best_idx, p.rs.len()), (&top.1, top.2, 0, 0), "act {i}: top row");
        assert_eq!(p.expectation_after.to_bits(), top.3.to_bits(), "act {i}");
    }
}

#[test]
fn the_tree_checks_before_its_first_batch_and_falls_back_to_the_top_row() {
    let c = corpus();
    let (base, huge, cut) = (picks_in(&c, 0, true), picks_in(&c, 1_000_000_000, true), picks_in(&c, 1, true));
    assert_eq!((base.len(), huge.len()), (cut.len(), cut.len()));
    assert!(base.len() >= 10, "enough answerable acts: {} picks", base.len());
    for (i, ((b, h), p)) in base.iter().zip(&huge).zip(&cut).enumerate() {
        let same = |x: &Pick| (x.unit_key.clone(), x.rs.clone(), x.tree.as_ref().map(|t| (t.completed, t.root.clone())));
        assert_eq!(same(b), same(h), "act {i}: a deadline that never fires");
        assert!(b.tree.as_ref().is_some_and(|t| t.elapsed_us > 0), "act {i}: the clock ran from the planner call");
        let t = p.tree.as_ref().unwrap_or_else(|| panic!("act {i}: a tree pick carries its trace"));
        assert_eq!((t.completed, t.deadline_hit, t.fallback), (0, true, Some("deadline_before_first_batch")), "act {i}");
        assert_eq!((&p.unit_key, p.action.kind, p.best_idx), (&p.scored[0].1, p.scored[0].2, 0), "act {i}: top row");
    }
}

/// A3: the root preselection outlasts the allowance (a 100 ms delay seam against a 40 ms deadline). With the
/// call-start clock every pick falls back before it searched; with `deadline_after_preselect` the allowance starts
/// after the preselection, so every pick searches, and its trace carries the preselection time. Tree and pool alike.
#[test]
fn with_the_clock_after_the_preselection_a_slow_preselection_no_longer_eats_the_allowance() {
    let c = corpus();
    for tree in [true, false] {
        let (off, on) = (picks_a3(&c, 40_000, tree, false, 100_000), picks_a3(&c, 40_000, tree, true, 100_000));
        assert!(off.len() >= 10 && on.len() == off.len(), "tree {tree}: {} vs {} picks", off.len(), on.len());
        for (i, (a, b)) in off.iter().zip(&on).enumerate() {
            if tree {
                let (ta, tb) = (a.tree.as_ref().expect("tree trace"), b.tree.as_ref().expect("tree trace"));
                assert_eq!((ta.completed, ta.fallback, ta.preselect_us), (0, Some("deadline_before_first_batch"), None), "act {i}");
                assert!(tb.completed > 0 && tb.batches > 0 && tb.fallback.is_none(), "act {i}: the tree searched: {tb:?}");
                let pre = tb.preselect_us.expect("knob on: the preselection time rides the trace");
                assert!(pre >= 100_000 && tb.elapsed_us >= pre, "act {i}: preselection {pre} us, elapsed {}", tb.elapsed_us);
            } else {
                let (da, db) = (a.deadline.as_ref().expect("deadline stamp"), b.deadline.as_ref().expect("deadline stamp"));
                assert_eq!((da.completed, da.fallback, da.preselect_us), (0, Some("deadline_before_first_rollout"), None), "act {i}");
                assert!(db.completed > 0 && db.fallback.is_none(), "act {i}: the pool rolled: {db:?}");
                assert!(db.preselect_us.is_some_and(|us| us >= 100_000 && db.elapsed_us >= us), "act {i}: {db:?}");
            }
        }
    }
}

/// A3, the other half: when the allowance never binds, the knob moves no pick, and the preselection time is
/// stamped only with the knob on (and only where a deadline runs at all).
#[test]
fn the_knob_moves_no_pick_when_the_allowance_never_binds_and_stamps_only_when_on() {
    let c = corpus();
    let pre = |p: &Pick| (p.tree.as_ref().and_then(|t| t.preselect_us), p.deadline.as_ref().and_then(|d| d.preselect_us));
    for tree in [true, false] {
        let (off, on) = (picks_a3(&c, 1_000_000_000, tree, false, 0), picks_a3(&c, 1_000_000_000, tree, true, 0));
        assert!(off.len() >= 10 && on.len() == off.len());
        for (i, (a, b)) in off.iter().zip(&on).enumerate() {
            assert_eq!((&a.unit_key, &a.pool_idx, &a.rs), (&b.unit_key, &b.pool_idx, &b.rs), "act {i}");
            assert_eq!(a.expectation_after.to_bits(), b.expectation_after.to_bits(), "act {i}");
            assert_eq!(a.tree.as_ref().map(|t| (t.completed, t.root.clone())), b.tree.as_ref().map(|t| (t.completed, t.root.clone())));
            assert_eq!(pre(a), (None, None), "act {i}: knob off stamps nothing");
            assert!(if tree { pre(b).0.is_some() } else { pre(b).1.is_some() }, "act {i}: knob on stamps");
        }
        assert!(picks_a3(&c, 0, tree, true, 0).iter().all(|p| pre(p) == (None, None)), "no deadline, no stamp");
    }
}
