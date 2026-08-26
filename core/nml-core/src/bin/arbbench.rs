//! `arbbench [acts_arb.jsonl] [repeats]` — what the PLAYOUT ARBITRATION costs.
//!
//! Two numbers, because they answer two different questions:
//!   * ONE `full_playout` — the atom: a branch played to the end of the game
//!     under the cheap policy, with stochastic wound rounding on every activation;
//!   * ONE arbitrated `plan_with_rollout` — the whole activation, i.e. the same
//!     work `planbench` times PLUS `2 * n` playouts (n = 3, 5 or 7 per branch).
//!
//! The second is what the game pays when the top two come out close, and it is
//! the reason `playout_search` is a preset switch rather than the default: it is
//! the most expensive thing the solo brain can do per activation. The recorded
//! GDScript side is in the corpus for once — `AiActRecorder` does not time the
//! search, but the arena log does, and act_recheck prints a per-act millisecond
//! figure for the SAME 15 activations (8.7-26.7 s each).

use std::time::Instant;

use nml_core::arbitration::full_playout;
use nml_core::plan::Search;
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::Scratch;
use nml_core::{build_act_statics, load_acts, GodotRng, Seams};

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

fn pct(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    sorted[((sorted.len() as f64 - 1.0) * p).round() as usize]
}

fn report(name: &str, us: &mut Vec<f64>) {
    let n = us.len() as f64;
    let mean = us.iter().sum::<f64>() / n;
    us.sort_by(|a, b| a.partial_cmp(b).unwrap());
    println!(
        "{name:<26}: mean {mean:.0} us  median {:.0} us  min {:.0}  p90 {:.0}  max {:.0}  (n = {})",
        pct(us, 0.5),
        pct(us, 0.0),
        pct(us, 0.90),
        pct(us, 1.0),
        us.len()
    );
}

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().unwrap_or_else(|| {
        concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_arb.jsonl").to_string()
    });
    let repeats: usize = args.next().and_then(|s| s.parse().ok()).unwrap_or(5);
    let c = load_acts(&path).unwrap_or_else(|e| panic!("{e}"));
    let statics = build_act_statics(&c, REPO);
    let seams = Seams { spacing: c.knobs.seam_spacing, cast: c.knobs.seam_cast };
    let roll = Rollout::new(Policy::new(&statics, &c.terrain, seams), c.knobs);
    let mut sc = Scratch::default();

    let mut play_us: Vec<f64> = Vec::new();
    let mut plan_us: Vec<f64> = Vec::new();
    let mut sink = 0i64;
    let mut playouts = 0usize;
    let mut rounds = 0i64;
    for _ in 0..repeats {
        for (ai, act) in c.acts.iter().enumerate() {
            let Some(arb) = act.arbitration_rec() else { continue };
            // The ATOM, on the branch the recording actually picked, with the
            // recorded seed of its first playout.
            let pick = act.pick.as_ref().and_then(|p| p.action.clone());
            if let Some(action) = pick {
                let mut rng = GodotRng::new(arb.sig.wrapping_mul(31));
                let t0 = Instant::now();
                let r = full_playout(&roll, &act.state, &action, act.player, &mut rng, &mut sc)
                    .unwrap_or_else(|u| panic!("act {ai}: full_playout declined {u:?}"));
                play_us.push(t0.elapsed().as_nanos() as f64 / 1000.0);
                sink += r.p1 - r.p2;
                rounds += r.rounds_played;
                playouts += 1;
            }
            // The WHOLE arbitrated activation.
            let mut search = Search::new(roll, &act.statics);
            search.sig = Some(arb.sig);
            let t0 = Instant::now();
            let p = search
                .run(&act.state, act.player, &mut sc)
                .unwrap_or_else(|u| panic!("act {ai}: the search declined {u:?}"));
            plan_us.push(t0.elapsed().as_nanos() as f64 / 1000.0);
            sink += p.arbitration.map(|a| a.n).unwrap_or(0);
        }
    }
    let per_branch: f64 = c.acts.iter().filter_map(|a| a.arbitration_rec()).map(|a| a.n as f64).sum::<f64>()
        / c.acts.iter().filter(|a| a.arbitration_rec().is_some()).count() as f64;
    println!(
        "{} arbitrated acts x {repeats} repeats; {per_branch:.1} playouts per branch on average \
         ({:.1} rounds played per playout)",
        c.acts.iter().filter(|a| a.arbitration_rec().is_some()).count(),
        rounds as f64 / playouts.max(1) as f64
    );
    report("full_playout", &mut play_us);
    report("arbitrated plan_with_rollout", &mut plan_us);
    println!("(checksum {sink})");
}
