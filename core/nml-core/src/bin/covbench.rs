//! `covbench [acts.jsonl] [rounds] [epoch]` — PLAN_COVER_36 step 10: what one `sight::screen_of` (cover from sight blockers)
//! costs. For every act state of the corpus and every ordered pair of living, deployed units of different seats, one call
//! on the corpus board's sight volumes (free shelf pieces included). The played volley pays one call per target group, so
//! the per-call numbers are the per-volley numbers. Also prints the share of pairs that come out `screened`.

use std::time::Instant;

use nml_core::load_acts;
use nml_core::sight::{screen_of, zones_of_with_at};

fn pct(sorted: &[f64], p: f64) -> f64 {
    sorted.get(((sorted.len().max(1) - 1) as f64 * p).round() as usize).copied().unwrap_or(0.0)
}

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().unwrap_or_else(|| concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_wide_25.jsonl").into());
    let rounds: usize = args.next().and_then(|s| s.parse().ok()).unwrap_or(5);
    let epoch: u32 = args.next().and_then(|s| s.parse().ok()).unwrap_or(nml_core::acts::PENDING_EPOCH_COVER_SCREEN);
    let c = load_acts(&path).unwrap_or_else(|e| panic!("{e}"));
    let zones = zones_of_with_at(&c.terrain, true, epoch);
    let (mut ns, mut screened, mut hidden_models, mut models) = (Vec::new(), 0usize, 0usize, 0usize);
    for _ in 0..rounds {
        for act in &c.acts {
            let st = &act.state;
            for i in 0..st.units() {
                for j in 0..st.units() {
                    if st.player[i] == st.player[j] || st.alive[i] <= 0 || st.alive[j] <= 0 || st.dormant[i] || st.dormant[j] {
                        continue;
                    }
                    let t0 = Instant::now();
                    let s = screen_of(st, &zones, i, j, epoch);
                    ns.push(t0.elapsed().as_nanos() as f64);
                    screened += s.screened as usize;
                    hidden_models += s.hidden.iter().filter(|&&h| h).count();
                    models += s.hidden.len();
                }
            }
        }
    }
    let n = ns.len().max(1) as f64;
    let mean = ns.iter().sum::<f64>() / n;
    ns.sort_by(|a, b| a.total_cmp(b));
    println!("{} screen_of calls ({} acts x {rounds} rounds, {} sight volumes, epoch {epoch})", ns.len(), c.acts.len(), zones.len());
    println!("per call = per volley: mean {mean:.0} ns  median {:.0} ns  p95 {:.0} ns  max {:.0} ns",
        pct(&ns, 0.5), pct(&ns, 0.95), pct(&ns, 1.0));
    println!("screened pairs {:.1} %  hidden models {:.1} %", 100.0 * screened as f64 / n,
        100.0 * hidden_models as f64 / models.max(1) as f64);
}
