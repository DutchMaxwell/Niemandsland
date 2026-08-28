//! `rolloutbench [acts.jsonl] [rounds]` — what one full round rollout costs.
//!
//! It replays exactly the work `AiPlanner.plan_with_rollout` pays per pool
//! candidate (ai_planner.gd:200-202): `rollout_boundaries` from the act's own
//! state, then `_blend_score` over the boundaries it returned. Every recorded
//! pool candidate of the corpus is timed individually, so the report can give a
//! MEDIAN as well as a mean — the distribution is wide (a rollout that ends in
//! one boundary is roughly half the work of one that crosses a round), and a
//! mean alone would hide that.

use std::time::Instant;

use nml_core::menu::Candidate;
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::Scratch;
use nml_core::{build_act_statics, load_acts, Act, Seams};

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

/// `plan_with_rollout`'s prefilter build order — see `tests/rollout.rs`.
fn flat_build_order(act: &Act) -> Vec<&Candidate> {
    let st = &act.state;
    let mut out = Vec::new();
    for i in 0..st.units() {
        // The recorded acts of this bench are all `hero_attach="off"` corpora,
        // where the seam changes nothing; `false` is the recorded reading.
        if !st.can_activate(i, act.player, false) {
            continue;
        }
        for c in &act.menus[st.key(i)] {
            out.push(c);
        }
    }
    out
}

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
    let rounds: usize = args.next().and_then(|s| s.parse().ok()).unwrap_or(20);
    let c = load_acts(&path).unwrap_or_else(|e| panic!("{e}"));
    let statics = build_act_statics(&c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast, path: c.knobs.seam_path,
        hero_attach: c.knobs.hero_attach, charge_landing: c.knobs.charge_landing, sighting: false,
        movement: c.knobs.movement, no_dangerous: false, no_engage_fold: !c.knobs.engage_fold };
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();

    let mut boundaries_ns: Vec<f64> = Vec::new();
    let mut full_ns: Vec<f64> = Vec::new();
    let mut sink = 0.0f64;
    let mut leaves = 0usize;
    for _ in 0..rounds {
        for act in &c.acts {
            let flat = flat_build_order(act);
            for rv in &act.rs {
                let cand = flat[rv.idx as usize];
                let t0 = Instant::now();
                let ends = roll
                    .rollout_boundaries(&act.state, cand, act.player, -1, &mut sc)
                    .expect("the corpus resolves");
                let t1 = Instant::now();
                sink += roll.blend_score(&ends, act.player, act.statics.opener_seat);
                let t2 = Instant::now();
                boundaries_ns.push(t1.duration_since(t0).as_nanos() as f64);
                full_ns.push(t2.duration_since(t0).as_nanos() as f64);
                leaves += ends.len();
            }
        }
    }
    let n = boundaries_ns.len() as f64;
    let mean_b = boundaries_ns.iter().sum::<f64>() / n;
    let mean_f = full_ns.iter().sum::<f64>() / n;
    boundaries_ns.sort_by(|a, b| a.partial_cmp(b).unwrap());
    full_ns.sort_by(|a, b| a.partial_cmp(b).unwrap());
    println!(
        "{} rollouts ({} acts x {rounds} rounds), {:.2} boundaries per rollout",
        boundaries_ns.len(),
        c.acts.len(),
        leaves as f64 / n
    );
    println!(
        "rollout_boundaries : mean {:.0} ns  median {:.0} ns  p10 {:.0}  p90 {:.0}",
        mean_b,
        pct(&boundaries_ns, 0.5),
        pct(&boundaries_ns, 0.10),
        pct(&boundaries_ns, 0.90)
    );
    println!(
        "  + blend_score    : mean {:.0} ns  median {:.0} ns  p10 {:.0}  p90 {:.0}",
        mean_f,
        pct(&full_ns, 0.5),
        pct(&full_ns, 0.10),
        pct(&full_ns, 0.90)
    );
    println!("(checksum {sink:.6})");
}
