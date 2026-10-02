//! `treebench [acts.jsonl ...] [repeats]` — tree plan step 14: what the tree
//! search knob costs per activation against today's one-ply search, on the
//! recorded acts fixtures (default: acts_25 + acts_wide_25).
//!
//! Per act: the one-ply at the corpus knobs, then `search_mode: tree` (EV
//! edges, Blend leaf) at budgets 32/64/128/256, every call through the shipped
//! entry `plan_with_rollout` (seams from the header via `seams_of`, never a
//! hand-built subset), so each number is the wall a player waits for that
//! activation. Printed per configuration: median and p90 wall, the median
//! ratio to the one-ply, the leaf evaluations completed, and at budget 256
//! with `tree_wall_ms` 500 the deadline-hit rate.
//!
//! It runs as a bin AND as a unit test (`cargo test --release --bin
//! treebench`), because the sanctioned cargo entry has no run mode.

use std::time::Instant;

use nml_core::{act_statics, load_acts, plan_with_rollout, Knobs, SearchMode, TreeDice, TreeLeaf};

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const BUDGETS: [i64; 4] = [32, 64, 128, 256];

/// One configuration's measurements over one corpus.
pub struct Row {
    pub name: String,
    pub wall_ms: Vec<f64>,
    pub leaves: Vec<f64>,
    pub deadline_hits: usize,
    pub picks: usize,
}

/// The `p` quantile of `v` (nearest rank); 0 for an empty list.
fn quantile(v: &[f64], p: f64) -> f64 {
    let mut s = v.to_vec();
    s.sort_by(|a, b| a.partial_cmp(b).unwrap());
    s.get(((s.len().max(1) - 1) as f64 * p).round() as usize).copied().unwrap_or(0.0)
}

/// Every act of `path`, `repeats` times, at the corpus knobs bent by `bend`.
fn measure(path: &str, name: String, bend: impl Fn(&mut Knobs), repeats: usize) -> Row {
    let c = load_acts(path).unwrap_or_else(|e| panic!("{e}"));
    let statics = act_statics(&c, REPO);
    let mut k = c.knobs;
    bend(&mut k);
    let mut row = Row { name, wall_ms: Vec::new(), leaves: Vec::new(), deadline_hits: 0, picks: 0 };
    for _ in 0..repeats {
        for (ai, act) in c.acts.iter().enumerate() {
            let t0 = Instant::now();
            let pick = plan_with_rollout(&act.state, &c.terrain, &statics[ai], &k, &act.statics, act.player)
                .unwrap_or_else(|u| panic!("{} act {ai}: declined {u:?}", row.name));
            row.wall_ms.push(t0.elapsed().as_secs_f64() * 1e3);
            if let Some(t) = &pick.tree {
                row.leaves.push(t.completed as f64);
                row.deadline_hits += usize::from(t.deadline_hit);
            }
            row.picks += 1;
        }
    }
    row
}

/// The one-ply, the four budgets and the 500 ms wall run over one corpus.
pub fn sweep(path: &str, repeats: usize) -> Vec<Row> {
    let tree = |k: &mut Knobs, budget: i64, wall: i64| {
        (k.search_mode, k.tree_leaf, k.tree_dice) = (SearchMode::Tree, TreeLeaf::Blend, TreeDice::Ev);
        (k.tree_budget, k.tree_wall_ms) = (budget, wall);
    };
    let mut rows = vec![measure(path, "one-ply (corpus knobs)".into(), |_| {}, repeats)];
    for b in BUDGETS {
        rows.push(measure(path, format!("tree ev/blend budget {b}"), |k| tree(k, b, 0), repeats));
    }
    rows.push(measure(path, "tree budget 256, wall 500 ms".into(), |k| tree(k, 256, 500), repeats));
    let base = quantile(&rows[0].wall_ms, 0.5);
    println!("== {path} ({} acts x {repeats})", rows[0].picks / repeats.max(1));
    for r in &rows {
        println!("{:30} median {:9.2} ms  p90 {:9.2} ms  x{:7.2} one-ply  leaves median {:5.0}  deadline {}/{}",
                 r.name, quantile(&r.wall_ms, 0.5), quantile(&r.wall_ms, 0.9), quantile(&r.wall_ms, 0.5) / base,
                 quantile(&r.leaves, 0.5), r.deadline_hits, r.picks);
    }
    rows
}

fn main() {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let repeats = args.last().and_then(|s| s.parse().ok()).inspect(|_| { args.pop(); }).unwrap_or(5);
    if args.is_empty() {
        let dir = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures");
        args = vec![format!("{dir}/acts_25.jsonl"), format!("{dir}/acts_wide_25.jsonl")];
    }
    for path in &args {
        sweep(path, repeats);
    }
}

#[cfg(test)]
mod tests {
    /// The smoke the gate runs: every configuration answers every act, a
    /// default pick carries no tree trace, and every tree pick at a plain
    /// budget completes at least that many leaf evaluations.
    #[test]
    fn treebench_smoke() {
        for f in ["acts_25.jsonl", "acts_wide_25.jsonl"] {
            let rows = super::sweep(&format!("{}/tests/fixtures/{f}", env!("CARGO_MANIFEST_DIR")), 1);
            assert_eq!(rows.len(), 6, "{f}: one-ply + 4 budgets + the wall run");
            let n = rows[0].picks;
            assert!(n > 0 && rows.iter().all(|r| r.picks == n), "{f}: every configuration answers every act");
            assert!(rows[0].leaves.is_empty(), "{f}: a default pick carries no tree trace");
            for (r, b) in rows[1..5].iter().zip(super::BUDGETS) {
                assert!(r.leaves.len() == n && r.leaves.iter().all(|&l| l >= b as f64),
                        "{f} {}: every tree pick completes its budget", r.name);
            }
            assert!(rows[5].leaves.len() == n && rows[5].deadline_hits <= n, "{f}: the wall run is stamped");
        }
    }
}
