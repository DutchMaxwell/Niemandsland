//! grid-search step 10 — the ANYTIME widen (`grid_batch`). The grid judge prices its widened cells
//! in batches and stops at the call's wall-clock deadline, keeping the best so far.
//!
//! Header-only knobs, so the RED compiles before the knob is read: main ignores `grid_batch` and
//! prices every widened cell in one batch.
use nml_core::acts::Knobs;
use nml_core::plan::{seams_of, LeafValue, Search};
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::{Scratch, Unsupported};
use nml_core::{build_act_statics, load_acts, ActCorpus};

mod common;

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl");
const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

fn corpus() -> ActCorpus {
    common::pin_legacy_no_cond_ap();
    load_acts(FIXTURE).unwrap_or_else(|e| panic!("{e}"))
}

fn grid_head(knobs: &str) -> String {
    format!(r#"{{"kind":"header","profiles":{{}},"knobs":{{{knobs}}}}}"#)
}

/// A seat-aware counting hook: every call is logged, every leaf answers 0.0, so the widened cell
/// values equal the hand 1-ply score and batching never moves a value.
struct SeatLog {
    root_seat: bool,
    calls: std::cell::RefCell<Vec<(i64, bool, usize)>>,
}

impl SeatLog {
    fn new(root_seat: bool) -> SeatLog {
        SeatLog { root_seat, calls: std::cell::RefCell::new(Vec::new()) }
    }
}

impl LeafValue for SeatLog {
    fn value(&self, leaves: &[&nml_core::State], side: i64) -> Result<Vec<f64>, Unsupported> {
        self.calls.borrow_mut().push((side, self.root_seat, leaves.len()));
        Ok(vec![0.0; leaves.len()])
    }
}

/// grid-search step 10 identity — an EXPLICIT `grid_batch` 0 is the absent knob: today's single
/// batch, same rows, grid trace and pick.
#[test]
fn grid_batch_zero_is_todays_one_batch() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();
    let base = nml_core::read_act_header(&grid_head(r#""grid_k":4,"grid_units":1"#)).unwrap().knobs;
    let zero = nml_core::read_act_header(&grid_head(r#""grid_k":4,"grid_units":1,"grid_batch":0"#)).unwrap().knobs;
    let mut checked = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let hook = SeatLog::new(act.statics.opener_seat);
        let mk = |k: Knobs, sc: &mut Scratch| {
            let mut s = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c.knobs)), k), &act.statics);
            s.leaf_value = Some(&hook); s.leaf_value_w = 0.0;
            s.run(&act.state, act.player, sc, None)
        };
        let (Ok(a), Ok(b)) = (mk(base, &mut sc), mk(zero, &mut sc)) else { continue };
        assert_eq!(a.scored, b.scored, "act {ai}: grid_batch 0 moved the rows");
        assert_eq!(a.grid, b.grid, "act {ai}: grid_batch 0 moved the grid trace");
        assert_eq!((a.unit_key.clone(), a.pool_idx.clone()), (b.unit_key.clone(), b.pool_idx.clone()),
            "act {ai}: grid_batch 0 moved the pick");
        checked += 1;
    }
    assert!(checked > 0, "the corpus declined everywhere — the gate proves nothing");
}

/// grid-search step 10 RED — an expired CALL-START deadline stops the widen before it prices a single
/// cell, so the decision is the grid-off pick with `grid.cut`. Main ignores `grid_batch` and prices
/// every widened cell, so it fails here.
#[test]
fn grid_batch_stops_at_the_call_start_deadline() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();
    // The call-start clock (0.5 s) is gone when the widen runs: a 1 s preselection seam outlasts it
    // while `deadline_after_preselect` restarts the POOL's clock only. The restarted 0.5 s is far
    // more than the pool needs, so it always completes — a pool cut is wall-clock noise and would
    // move the compared pick on its own (the 40 ms/100 ms pair flaked under parallel test load).
    const POOL_US: &str = r#""deadline_us":500000,"deadline_after_preselect":true"#;
    let cut_k = nml_core::read_act_header(&grid_head(&format!(
        r#""grid_k":4,"grid_units":1,"grid_batch":1,{POOL_US}"#))).unwrap().knobs;
    let off_k = nml_core::read_act_header(&grid_head(&format!(
        r#""grid_k":0,{POOL_US}"#))).unwrap().knobs;
    let base = nml_core::read_act_header(&grid_head(r#""grid_k":4,"grid_units":1"#)).unwrap().knobs;
    let mut widened = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let hb = SeatLog::new(act.statics.opener_seat);
        let mut b = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c.knobs)), base), &act.statics);
        b.leaf_value = Some(&hb); b.leaf_value_w = 0.0;
        let Ok(w) = b.run(&act.state, act.player, &mut sc, None) else { continue };
        if w.grid.as_ref().is_none_or(|g| g.completed == 0) {
            continue; // this act widens nothing — it cannot prove the deadline gate
        }
        widened += 1;
        let hc = SeatLog::new(act.statics.opener_seat);
        let mut s = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c.knobs)), cut_k), &act.statics);
        s.leaf_value = Some(&hc); s.leaf_value_w = 0.0;
        s.bend.preselect_delay_us = 1_000_000;
        let got = s.run(&act.state, act.player, &mut sc, None).unwrap();
        let g = got.grid.as_ref().expect("a grid_k pick carries a trace");
        assert_eq!(g.completed, 0, "act {ai}: the gone deadline still priced {} cells", g.completed);
        assert!(g.cut, "act {ai}: a deadline stop must stamp grid.cut");
        let ho = SeatLog::new(act.statics.opener_seat);
        let mut o = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c.knobs)), off_k), &act.statics);
        o.leaf_value = Some(&ho); o.leaf_value_w = 0.0;
        o.bend.preselect_delay_us = 1_000_000;
        let off = o.run(&act.state, act.player, &mut sc, None).unwrap();
        assert_eq!((got.unit_key.clone(), format!("{:?}", got.action)),
                   (off.unit_key.clone(), format!("{:?}", off.action)),
                   "act {ai}: a deadline-cut grid left the grid-off pick");
    }
    assert!(widened > 0, "the corpus widened nowhere — the gate proves nothing");
}
