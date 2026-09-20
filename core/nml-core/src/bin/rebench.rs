//! `rebench [acts.jsonl] [repeats]` — the epoch-62 re-measurement of the solo
//! search (brief REBENCH 2026-09-20), replacing the db29a18d numbers of record.
//!
//! What each number IS, stated rather than hidden:
//! * `Search::plan` = the prefilter exactly (root score + every menu row
//!   resolved and rich-scored, plan.rs:431-473) + the argmax walk. Timed on its
//!   own this is the PREFILTER share; the argmax is O(n) compares and noise.
//! * `Search::run` = the whole activation: prefilter AGAIN, sort, pool, one
//!   rollout per pool candidate, blend, arbitration if it fires.
//! * the pool rollouts are then RE-TIMED one by one (`rollout_boundaries` +
//!   `blend_score_leaf`, same candidates, same order, fresh scratch) — the
//!   direct ROLLOUT share. `plan + retimed-rollouts ≈ run` is the consistency
//!   check; the remainder is sort/pool/bookkeeping.
//! * menu sizes come from the prefilter's own builder `candidates_tuned`
//!   (shaken units: the recovery hold, 1 row); leaf counts are the measured
//!   `ends.len()` values, at the corpus knob and at explicit horizon 2 vs 3.
//!
//! The seams are taken from the corpus header itself (`seams_of(&c.knobs)`),
//! so the acts fixture must be recorded under the SAME `rules_epoch` as the
//! corpus it is run against: an epoch-0 seam set against an epoch-62 corpus
//! panicked 115 of 144 acts (the 2026-09-20 incident).
//!
//! It runs as a bin AND as a unit test (`cargo test --release --bin rebench`),
//! because the sanctioned cargo entry (`nml-cargo`) has no run/build mode.

use std::time::Instant;

use nml_core::menu::{candidates_tuned, Candidate};
use nml_core::plan::{seams_of, tuning_of, Search};
use nml_core::playout::Policy;
use nml_core::rollout::Rollout;
use nml_core::sim::Scratch;
use nml_core::{build_act_statics, load_acts, Act};

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");

fn pct(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    let i = ((sorted.len() as f64 - 1.0) * p).round() as usize;
    sorted[i]
}

/// (min, mean, median, p90, max) — sorts in place.
fn stats(v: &mut Vec<f64>) -> (f64, f64, f64, f64, f64) {
    assert!(!v.is_empty(), "empty distribution");
    let mean = v.iter().sum::<f64>() / v.len() as f64;
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    (v[0], mean, pct(v, 0.5), pct(v, 0.90), v[v.len() - 1])
}

fn line(name: &str, v: &mut Vec<f64>, unit: &str) {
    let (min, mean, med, p90, max) = stats(v);
    println!(
        "{name:38} min {min:9.2}  mean {mean:9.2}  median {med:9.2}  p90 {p90:9.2}  max {max:11.2}  {unit}  (n {})",
        v.len()
    );
}

/// `plan_with_rollout`'s prefilter build order over the RECORDED menus — see
/// `rolloutbench` and `tests/rollout.rs`.
fn flat_build_order(act: &Act) -> Vec<&Candidate> {
    let st = &act.state;
    let mut out = Vec::new();
    for i in 0..st.units() {
        if !st.can_activate(i, act.player, false) {
            continue;
        }
        for c in &act.menus[st.key(i)] {
            out.push(c);
        }
    }
    out
}

fn sweep(path: &str, repeats: usize) {
    let c = load_acts(path).unwrap_or_else(|e| panic!("{e}"));
    let statics = build_act_statics(&c, REPO);
    // The header knobs are the ONLY source of the resolve/menu seams — the old
    // hand-built subset predates W1 (`moved_shoot`) and the epoch gate
    // (`rules_epoch`), and an epoch-62 corpus declines every ADVANCE+shoot
    // rollout with `Unsupported::MovedShootLos` before the first sweep line.
    // `seams_of` is the canonical knobs→seams mapping `plan_with_rollout` uses.
    let seams = seams_of(&c.knobs);
    println!(
        "corpus: {} acts, knobs top_k={} horizon={} (recorded)",
        c.acts.len(),
        c.knobs.top_k,
        c.knobs.horizon
    );

    // Menu-size census — config-independent, so one pass. This is the
    // prefilter's own builder (`candidates_tuned` with the policy's tuning);
    // a SHAKEN unit's prefilter menu is the recovery hold, 1 row.
    let tuning = tuning_of(&c.knobs);
    let mut menu_rows: Vec<f64> = Vec::new();
    let mut sc_menu = Scratch::default();
    for act in &c.acts {
        for i in 0..act.state.units() {
            if !act.state.can_activate(i, act.player, c.knobs.hero_attach) {
                continue;
            }
            let rows = if act.state.shaken[i] {
                1
            } else {
                candidates_tuned(&act.state, &c.terrain, &statics, i, &mut sc_menu, tuning).len()
            };
            menu_rows.push(rows as f64);
        }
    }
    line("menu rows per activatable unit", &mut menu_rows, "rows");

    // Per-rollout cost at an EXPLICIT horizon (the corpus knob applies only
    // through `-1`): the same recorded pool candidates `rolloutbench` replays,
    // once at 2 rounds, once at 3. This is the leaf-count instrument.
    let mut pol0 = Policy::new(&statics, &c.terrain, seams);
    pol0.tuning = tuning_of(&c.knobs);
    let roll0 = Rollout::new(pol0, c.knobs);
    let mut sc_h = Scratch::default();
    for h in [2i64, 3] {
        let (mut pr, mut lr) = (Vec::new(), Vec::new());
        let mut sink = 0.0f64;
        for _ in 0..5 {
            for act in &c.acts {
                let flat = flat_build_order(act);
                for rv in &act.rs {
                    let cand = flat[rv.idx as usize];
                    let t0 = Instant::now();
                    let ends = roll0
                        .rollout_boundaries(&act.state, cand, act.player, h, &mut sc_h)
                        .expect("the corpus resolves");
                    sink += roll0.blend_score(&ends, act.player, act.statics.opener_seat);
                    pr.push(t0.elapsed().as_nanos() as f64 / 1000.0);
                    lr.push(ends.len() as f64);
                }
            }
        }
        println!("--- explicit horizon {h} ---");
        line("rollout_boundaries us", &mut pr, "us");
        line("leaves (boundaries) per rollout", &mut lr, "leaves");
        println!("    checksum {sink:.6}");
    }

    // The three search configurations. Shipped: top_k 6, corpus horizon (2).
    // Proposed (RETIME 2026-09-20): top_k 8, horizon 3. Record: top_k 32,
    // horizon 3.
    for (name, top_k, horizon) in [("shipped top_k=6 horizon=knob", 6i64, None),
                                   ("proposed top_k=8 horizon=3", 8i64, Some(3i64)),
                                   ("record  top_k=32 horizon=3", 32i64, Some(3i64))] {
        let mut kn = c.knobs;
        if let Some(h) = horizon {
            kn.horizon = h;
        }
        let mut pol = Policy::new(&statics, &c.terrain, seams);
        pol.tuning = tuning_of(&c.knobs);
        let roll = Rollout::new(pol, kn);
        let mut sc = Scratch::default();
        let mut sc_re = Scratch::default();
        let (mut t_plan, mut t_run, mut t_rolls) = (Vec::new(), Vec::new(), Vec::new());
        let (mut per_roll, mut leaves_roll, mut leaves_act) = (Vec::new(), Vec::new(), Vec::new());
        let (mut rows, mut pool) = (Vec::new(), Vec::new());
        let (mut arbs, mut sink, mut skipped) = (0usize, 0.0f64, 0usize);
        for _ in 0..repeats {
            for act in &c.acts {
                let mut search = Search::new(roll, &act.statics);
                search.bend.top_k = Some(top_k);
                let t0 = Instant::now();
                let one = search
                    .plan(&act.state, act.player, &mut sc)
                    .unwrap_or_else(|u| panic!("plan declined {u:?}"));
                t_plan.push(t0.elapsed().as_nanos() as f64 / 1000.0);
                if one.is_none() {
                    skipped += 1;
                    continue;
                }
                let t1 = Instant::now();
                let pick = search
                    .run(&act.state, act.player, &mut sc, None)
                    .unwrap_or_else(|u| panic!("run declined {u:?}"));
                t_run.push(t1.elapsed().as_nanos() as f64 / 1000.0);
                sink += pick.expectation_after;
                rows.push(pick.scored.len() as f64);
                pool.push(pick.pool_idx.len() as f64);
                if pick.arbitration.is_some() {
                    arbs += 1;
                }
                let mut sum = 0.0f64;
                let mut lv = 0usize;
                for &i in &pick.pool_idx {
                    let t2 = Instant::now();
                    let ends = roll
                        .rollout_boundaries(&act.state, &pick.cands[i], act.player, -1, &mut sc_re)
                        .expect("the corpus resolves");
                    let v = roll.blend_score_leaf(
                        &ends,
                        act.player,
                        act.statics.opener_seat,
                        &[],
                        0.0,
                    );
                    sum += t2.elapsed().as_nanos() as f64 / 1000.0;
                    lv += ends.len();
                    per_roll.push(t2.elapsed().as_nanos() as f64 / 1000.0);
                    leaves_roll.push(ends.len() as f64);
                    sink += v * 1e-9; // keep the blend in the checksum, off the timings
                }
                t_rolls.push(sum);
                leaves_act.push(lv as f64);
            }
        }
        println!("=== {name} — {} acts x {repeats} repeats ===", c.acts.len());
        line("PREFILTER  Search::plan us", &mut t_plan, "us");
        line("TOTAL      Search::run  us", &mut t_run, "us");
        line("ROLLOUTS   re-timed sum/act", &mut t_rolls, "us");
        line("rollout single", &mut per_roll, "us");
        line("leaves per rollout", &mut leaves_roll, "leaves");
        line("leaves per activation (pool)", &mut leaves_act, "leaves");
        line("prefilter rows per activation", &mut rows, "rows");
        line("pool size per activation", &mut pool, "cands");
        let med_plan = pct(
            &{
                let mut v = t_plan.clone();
                v.sort_by(|a, b| a.partial_cmp(b).unwrap());
                v
            },
            0.5,
        );
        let med_run = pct(
            &{
                let mut v = t_run.clone();
                v.sort_by(|a, b| a.partial_cmp(b).unwrap());
                v
            },
            0.5,
        );
        let med_roll = pct(
            &{
                let mut v = t_rolls.clone();
                v.sort_by(|a, b| a.partial_cmp(b).unwrap());
                v
            },
            0.5,
        );
        println!(
            "split of the MEDIAN activation: prefilter {:.1}%  rollouts {:.1}%  other {:.1}%  (arbitrations fired: {arbs}, one-ply skips: {skipped})",
            100.0 * med_plan / med_run,
            100.0 * med_roll / med_run,
            100.0 * (med_run - med_plan - med_roll).max(0.0) / med_run
        );
        println!("checksum {sink:.6}");
    }
}

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args
        .next()
        .unwrap_or_else(|| {
            concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl").to_string()
        });
    let repeats: usize = args.next().and_then(|s| s.parse().ok()).unwrap_or(20);
    sweep(&path, repeats);
}

#[cfg(test)]
mod tests {
    #[test]
    fn rebench_epoch62() {
        let manifest = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl");
        super::sweep(manifest, 40);
    }
}
