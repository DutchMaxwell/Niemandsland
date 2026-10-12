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

/// A leaf hook that stalls on the first GRID batch (call #2: call #1 is the pool's single leaf
/// batch), so the call-start clock is gone before the SECOND batch is checked, and prices grid
/// leaves with a huge first leaf so the first priced cell is the unique argmax against the hand.
struct StallLeaf {
    calls: std::cell::Cell<usize>,
    stall: bool,
}

impl LeafValue for StallLeaf {
    fn value(&self, leaves: &[&nml_core::State], _side: i64) -> Result<Vec<f64>, Unsupported> {
        let call = self.calls.get();
        self.calls.set(call + 1);
        if self.stall && call == 1 {
            std::thread::sleep(std::time::Duration::from_millis(4000));
        }
        let mut vals = vec![0.0; leaves.len()];
        if call > 0 && !vals.is_empty() {
            vals[0] = 1.0e9;
        }
        Ok(vals)
    }
}

/// grid-search step 10 — the PRICING loop is the ANYTIME clock too (lead review): a call-start
/// deadline that expires DURING the first pricing batch prices exactly `grid_batch` cells, drops the
/// collected-but-unpriced tail (it must not enter the trace or the ranking) and leaves the pick = the
/// argmax over the hand rows plus those first cells.
#[test]
fn grid_batch_stops_after_the_first_pricing_batch() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();
    const BATCH: usize = 2;
    // 2 s call-start clock; the first grid batch stalls 4 s, so the check before the SECOND batch is
    // the first one to see the clock gone. Pool + collection are far under 2 s even on a loaded box.
    let cut_k = nml_core::read_act_header(&grid_head(
        r#""grid_k":6,"grid_units":1,"grid_batch":2,"deadline_us":2000000"#)).unwrap().knobs;
    let one_k = nml_core::read_act_header(&grid_head(r#""grid_k":1,"grid_units":1"#)).unwrap().knobs;
    let base_k = nml_core::read_act_header(&grid_head(r#""grid_k":6,"grid_units":1"#)).unwrap().knobs;
    let mut widened = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        let hb = StallLeaf { calls: std::cell::Cell::new(0), stall: false };
        let mut b = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c.knobs)), base_k), &act.statics);
        b.leaf_value = Some(&hb); b.leaf_value_w = 1.0;
        let Ok(full) = b.run(&act.state, act.player, &mut sc, None) else { continue };
        if full.grid.as_ref().is_none_or(|g| g.completed <= BATCH) {
            continue; // needs a second batch to cut
        }
        widened += 1;
        let hc = StallLeaf { calls: std::cell::Cell::new(0), stall: true };
        let mut s = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c.knobs)), cut_k), &act.statics);
        s.leaf_value = Some(&hc); s.leaf_value_w = 1.0;
        let got = s.run(&act.state, act.player, &mut sc, None).unwrap();
        let g = got.grid.as_ref().expect("a grid_k pick carries a trace");
        assert_eq!(g.completed, BATCH, "act {ai}: the cut priced {} cells, not {BATCH}", g.completed);
        assert!(g.cut, "act {ai}: a pricing stop must stamp grid.cut");
        assert_eq!(g.rows.len(), BATCH, "act {ai}: unpriced cells leaked into the trace");
        let hr = StallLeaf { calls: std::cell::Cell::new(0), stall: false };
        let mut r = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c.knobs)), one_k), &act.statics);
        r.leaf_value = Some(&hr); r.leaf_value_w = 1.0;
        let refp = r.run(&act.state, act.player, &mut sc, None).unwrap();
        assert_eq!((got.unit_key.clone(), format!("{:?}", got.action)),
                   (refp.unit_key.clone(), format!("{:?}", refp.action)),
                   "act {ai}: the cut pick is not the argmax over the first priced cells");
    }
    assert!(widened > 0, "the corpus widened nowhere — the gate proves nothing");
}

/// grid-search step 10 — the replay seam: `grid_budget n` forces exactly n priced cells with the
/// clock off, so a deadline-cut decision replays identically from its stamped `grid.completed`.
#[test]
fn grid_budget_replays_a_cut_decision() {
    let c = corpus();
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();
    const N: usize = 1;
    // A cut at one priced cell: `grid_batch` 1 + a 2 s clock, the first grid batch stalled 4 s.
    let cut_k = nml_core::read_act_header(&grid_head(
        r#""grid_k":6,"grid_units":1,"grid_batch":1,"deadline_us":2000000"#)).unwrap().knobs;
    // The replay: the SAME grid, forced to one priced cell, clock off.
    let budget_k = nml_core::read_act_header(&grid_head(
        r#""grid_k":6,"grid_units":1,"grid_budget":1"#)).unwrap().knobs;
    let base_k = nml_core::read_act_header(&grid_head(r#""grid_k":6,"grid_units":1"#)).unwrap().knobs;
    let mut widened = 0usize;
    for (ai, act) in c.acts.iter().enumerate() {
        // find acts that widen more than N cells
        let hb = StallLeaf { calls: std::cell::Cell::new(0), stall: false };
        let mut b = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c.knobs)), base_k), &act.statics);
        b.leaf_value = Some(&hb); b.leaf_value_w = 1.0;
        let Ok(full) = b.run(&act.state, act.player, &mut sc, None) else { continue };
        if full.grid.as_ref().is_none_or(|g| g.completed <= N) {
            continue;
        }
        widened += 1;
        let ha = StallLeaf { calls: std::cell::Cell::new(0), stall: true };
        let mut a = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c.knobs)), cut_k), &act.statics);
        a.leaf_value = Some(&ha); a.leaf_value_w = 1.0;
        let cut = a.run(&act.state, act.player, &mut sc, None).unwrap();
        let ga = cut.grid.as_ref().expect("a grid_k pick carries a trace");
        assert_eq!(ga.completed, N, "act {ai}: the clock did not cut at {N}");
        assert!(ga.cut, "act {ai}: a deadline stop must stamp grid.cut");
        let hc = StallLeaf { calls: std::cell::Cell::new(0), stall: false };
        let mut z = Search::new(Rollout::new(Policy::new(&statics, &c.terrain, seams_of(&c.knobs)), budget_k), &act.statics);
        z.leaf_value = Some(&hc); z.leaf_value_w = 1.0;
        let rep = z.run(&act.state, act.player, &mut sc, None).unwrap();
        let gz = rep.grid.as_ref().expect("a grid_k pick carries a trace");
        assert_eq!(gz.completed, N, "act {ai}: grid_budget did not force the count");
        assert!(gz.cut, "act {ai}: a forced-budget cut must stamp grid.cut");
        assert_eq!(gz.rows.len(), N, "act {ai}: the replay trace moved");
        assert_eq!((cut.unit_key.clone(), format!("{:?}", cut.action)),
                   (rep.unit_key.clone(), format!("{:?}", rep.action)),
                   "act {ai}: the replay moved the pick");
    }
    assert!(widened > 0, "the corpus widened nowhere — the gate proves nothing");
}
