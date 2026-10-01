//! Tree plan step 9 — `pool_wall_ms`, the one-ply search's wall-clock fallback.
//!
//! Off (0, the default) and a huge value must leave every pick byte-identical to
//! the plain search; a 1 ms wall on `acts_wide_25` must stop the rollout pass
//! early, stamp `pool_completed`, and pick among the rollouts that finished.
use nml_core::plan::{seams_of, Search};
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

fn picks(c: &ActCorpus, pool_wall_ms: i64) -> Vec<Pick> {
    let per_act = act_statics(c, REPO);
    let seams = seams_of(&c.knobs);
    let mut knobs = c.knobs;
    knobs.pool_wall_ms = pool_wall_ms;
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

fn same(a: &Pick, b: &Pick) -> bool {
    a.unit_key == b.unit_key
        && format!("{:?}", a.action) == format!("{:?}", b.action)
        && a.pool_idx == b.pool_idx
        && a.rs == b.rs
        && a.expectation_after.to_bits() == b.expectation_after.to_bits()
}

#[test]
fn pool_wall_off_and_huge_are_byte_identical() {
    let c = corpus();
    let base = picks(&c, 0);
    assert!(base.len() >= 10, "enough answerable acts: {} picks", base.len());
    assert!(base.iter().all(|p| p.pool_completed.is_none()), "knob off must not stamp");
    let huge = picks(&c, 3_600_000);
    assert_eq!(base.len(), huge.len());
    for (i, (b, h)) in base.iter().zip(&huge).enumerate() {
        assert!(same(b, h), "act {i}: a wall that never fires moved the pick");
        assert_eq!(h.pool_completed, Some((b.pool_idx.len(), false)), "act {i}");
    }
}

#[test]
fn a_one_ms_pool_wall_stops_early_and_picks_among_the_completed() {
    let c = corpus();
    let base = picks(&c, 0);
    let cut = picks(&c, 1);
    assert_eq!(base.len(), cut.len());
    let mut short = 0usize;
    for (i, (b, p)) in base.iter().zip(&cut).enumerate() {
        let (n, hit) = p.pool_completed.unwrap_or_else(|| panic!("act {i}: knob on, no stamp"));
        assert!(n >= 1 && n <= b.pool_idx.len(), "act {i}: completed {n} of {}", b.pool_idx.len());
        assert_eq!((p.pool_idx.len(), p.rs.len()), (n, n), "act {i}: the trace must cover only the completed rollouts");
        assert_eq!(hit, n < b.pool_idx.len(), "act {i}: deadline_hit must say whether the pool was cut");
        assert_eq!(p.pool_idx[..], b.pool_idx[..n], "act {i}: the completed rollouts are the pool's prefix");
        let pos = p.rs.iter().position(|&(_, v)| v.to_bits() == p.expectation_after.to_bits());
        assert!(pos.is_some(), "act {i}: the pick must come from a completed rollout");
        if hit {
            short += 1;
        }
    }
    assert!(short > 0, "1 ms never cut a single pool on acts_wide_25");
}
