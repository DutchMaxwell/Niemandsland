//! `planbench [acts.jsonl] [repeats]` — what ONE activation of the solo brain
//! costs in Rust.
//!
//! `rolloutbench` times a single rollout; this times the whole of
//! `AiPlanner.plan_with_rollout`: the 1-ply prefilter over every candidate of
//! every un-activated unit (each one a full `resolve` + reply-threat leaf), the
//! sort, the four pool guarantees, and one round rollout per pool candidate.
//! That is the unit of work the game pays per AI unit that steps onto the table,
//! so it is the number the port is judged on.
//!
//! Every act is timed on its own and the distribution is reported (mean, median,
//! max), because the cost tracks the pool size and the pool ranges from a
//! handful of candidates late in a round to a dozen at its start.

use std::time::Instant;

use nml_core::plan::Search;
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::Scratch;
use nml_core::{build_act_statics, load_acts, Seams};

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

fn pct(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    let i = ((sorted.len() as f64 - 1.0) * p).round() as usize;
    sorted[i]
}

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().unwrap_or_else(|| {
        concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl").to_string()
    });
    let repeats: usize = args.next().and_then(|s| s.parse().ok()).unwrap_or(20);
    let c = load_acts(&path).unwrap_or_else(|e| panic!("{e}"));
    let statics = build_act_statics(&c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing, sighting: false,
        movement: c.knobs.movement, no_dangerous: false };
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();

    let mut us: Vec<f64> = Vec::new();
    let mut sink = 0.0f64;
    let mut rollouts = 0usize;
    let mut cands = 0usize;
    for _ in 0..repeats {
        for (ai, act) in c.acts.iter().enumerate() {
            let search = Search::new(roll, &act.statics);
            let t0 = Instant::now();
            let pick = search
                .run(&act.state, act.player, &mut sc)
                .unwrap_or_else(|u| panic!("act {ai}: the search declined {u:?}"));
            us.push(t0.elapsed().as_nanos() as f64 / 1000.0);
            sink += pick.expectation_after;
            rollouts += pick.pool_idx.len();
            cands += pick.scored.len();
        }
    }
    let n = us.len() as f64;
    let mean = us.iter().sum::<f64>() / n;
    us.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let total_ms = us.iter().sum::<f64>() / 1000.0;
    println!(
        "{} activations ({} acts x {repeats} repeats): {:.1} prefilter candidates and \
         {:.1} rollouts per activation",
        us.len(),
        c.acts.len(),
        cands as f64 / n,
        rollouts as f64 / n
    );
    println!(
        "plan_with_rollout : mean {mean:.0} us  median {:.0} us  min {:.0}  p90 {:.0}  max {:.0}",
        pct(&us, 0.5),
        pct(&us, 0.0),
        pct(&us, 0.90),
        pct(&us, 1.0)
    );
    println!("total wall time for the sweep: {total_ms:.1} ms  (checksum {sink:.6})");
    // The GDScript side is NOT in the corpus: `AiActRecorder` records the search
    // input and the search answer, not how long the search took. The comparison
    // therefore cites the profile note for the same brain (8.5-16 s per round-1
    // activation at 1000 points) and states it as a cited number, not a measured
    // one.
    for gd_s in [8.5f64, 16.0] {
        println!(
            "vs the cited GDScript {gd_s:.1} s per round-1 activation at 1000 pts: {:.0}x",
            gd_s * 1.0e6 / mean
        );
    }
}
