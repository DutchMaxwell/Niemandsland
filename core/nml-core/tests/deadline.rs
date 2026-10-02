//! `deadline_us`, the per-decision allowance in microseconds from the planner
//! call. Off (0) leaves every pool pick unstamped; 10^9 µs never fires and must
//! leave every pick byte-identical; 1 µs is spent before the first rollout, so
//! every pool pick is the prefilter's top row, stamped with the fallback.
use nml_core::plan::{seams_of, DeadlineTrace, Search};
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::Scratch;
use nml_core::{act_statics, load_acts, ActCorpus, Pick};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_wide_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

mod common;

fn corpus() -> ActCorpus {
    common::pin_legacy_no_cond_ap();
    load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

fn picks(c: &ActCorpus, deadline_us: i64) -> Vec<Pick> {
    let per_act = act_statics(c, REPO);
    let seams = seams_of(&c.knobs);
    let mut knobs = c.knobs;
    knobs.deadline_us = deadline_us;
    let mut sc = Scratch::default();
    let mut out = Vec::new();
    for (ai, act) in c.acts.iter().enumerate() {
        let roll = Rollout::new(Policy::new(&per_act[ai], &c.terrain, seams), knobs);
        if let Ok(p) = Search::new(roll, &act.statics).run(&act.state, act.player, &mut sc, None) {
            out.push(p);
        }
    }
    out
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
        let stamp = DeadlineTrace { completed: b.pool_idx.len(), cut: false, fallback: None };
        assert_eq!(h.deadline, Some(stamp), "act {i}");
    }
}

#[test]
fn a_one_us_deadline_answers_every_pool_pick_with_the_top_row() {
    let c = corpus();
    let cut = picks(&c, 1);
    assert_eq!(cut.len(), picks(&c, 0).len());
    for (i, p) in cut.iter().enumerate() {
        let stamp = DeadlineTrace { completed: 0, cut: true, fallback: Some("deadline_before_first_rollout") };
        assert_eq!(p.deadline, Some(stamp), "act {i}");
        let top = &p.scored[0];
        assert_eq!((&p.unit_key, p.action.kind, p.best_idx, p.rs.len()), (&top.1, top.2, 0, 0), "act {i}: top row");
        assert_eq!(p.expectation_after.to_bits(), top.3.to_bits(), "act {i}");
    }
}
