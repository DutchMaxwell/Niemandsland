//! GATE G2/G3 (NML-1073 M4-2 + M4-3) — `mvtheta [flags] [moves_calls.jsonl ...]`
//!
//! Replays the three per-model stages the flow's trace records and compares
//! each against the recording:
//!
//!   theta  `_theta_star_b`  (movement_planner.gd:1341) -> `trace.flow[].theta`
//!   pull   `string_pull`    (:1464, charge append :1117) -> `.taut`
//!   walk   `_walk_offset`   (:1497) -> `.walked`
//!
//! EVERY STAGE IS FED ITS OWN RECORDED INPUT — the pull replays the recorded
//! Theta* path, the walk replays the recorded taut path — so a regression in one
//! stage cannot hide or fake one in the next. Positions are f32 on both sides,
//! so the comparison is exact equality, not a tolerance.
//!
//! Searches whose inputs trace v1 cannot pin down are counted but not judged —
//! see `mv::replay`. The gate is `matched == determined` on all three stages.
//!
//! FLAGS (the red proofs; each must make its gate fail):
//!   --strict-open      open list picks min-f by a strict `f < best_f`
//!   --diag-swap=i,j    swap two entries of THETA_DIAG
//!   --guard=N          run with `fast_planner_guard = N` (shipped: 320)
//!   --pull-break       `string_pull` BREAKS on a too-dear shortcut instead of
//!                      skipping it
//!   --bisect=N         `_furthest_clear` bisection steps (shipped: 14)
//!   --walk-eps-swap    `spent + leg + EPS <= allowance` instead of
//!                      `spent + leg <= allowance + EPS`
//!   --bench            micro-bench instead of the gate

use std::time::Instant;

use nml_core::mv::io::MoveCall;
use nml_core::mv::pull::{PullBend, WalkBend};
use nml_core::mv::replay::{searches, ReplaySearch};
use nml_core::mv::theta::{ThetaBend, ThetaCfg};
use nml_core::mv::{load_moves, MoveCorpus};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/moves_s27.jsonl");

#[derive(Clone, Copy)]
struct Bends {
    theta: ThetaBend,
    pull: PullBend,
    walk: WalkBend,
    guard: Option<i64>,
}

impl Bends {
    fn active(&self) -> bool {
        self.theta.strict_open
            || self.theta.diag_swap.is_some()
            || self.pull.cost_break
            || self.guard.is_some()
            || self.walk.bisect_steps != WalkBend::default().bisect_steps
            || self.walk.eps_swapped
    }
}

fn label(path: &str) -> String {
    let p = std::path::Path::new(path);
    let parent = p.parent().and_then(|d| d.file_name()).and_then(|s| s.to_str()).unwrap_or("");
    if parent.is_empty() || parent == "fixtures" {
        p.file_stem().and_then(|s| s.to_str()).unwrap_or(path).to_string()
    } else {
        parent.to_string()
    }
}

fn fmt(path: &[[f32; 2]]) -> String {
    let v: Vec<String> = path.iter().map(|p| format!("({}, {})", p[0], p[1])).collect();
    format!("[{}]", v.join(", "))
}

fn report_mismatch(
    stage: &str,
    file: &str,
    call: &MoveCall,
    s: &ReplaySearch,
    want: &[[f32; 2]],
    got: &[[f32; 2]],
    cfg: ThetaCfg,
) {
    println!("\n=== FIRST {stage} MISMATCH — {file} ===");
    println!(
        "call {} unit={:?} act={} round={} rung={:?} allow_contact={} models={}",
        s.call, call.unit, call.act, call.round, call.rung, call.allow_contact,
        call.model_pos.len()
    );
    println!(
        "flow entry {} model {} charge={} reach_closest={} allowance={}",
        s.entry, s.model, s.charge, s.reach_closest, s.allowance
    );
    println!("start        ({}, {})", s.start[0], s.start[1]);
    println!("goal         ({}, {})", s.goal[0], s.goal[1]);
    println!("board        ({}, {})", call.board()[0], call.board()[1]);
    println!(
        "opts         clearance={} zones={} avoid_cells={} grid={} walls={}",
        call.opts.clearance, s.zones.len(), call.opts.avoid_cells.len(), call.grid.len(),
        call.walls.len()
    );
    println!("cfg          fast_planner={} guard={}", cfg.fast_planner, cfg.fast_planner_guard);
    println!("delta        ({}, {})", call.delta[0], call.delta[1]);
    for (i, z) in s.zones.iter().enumerate() {
        println!("  zone[{i:3}]  c=({}, {}) r={}", z.c[0], z.c[1], z.r);
    }
    println!("stage input  {} nodes {}", 
        if stage == "pull" { s.expected.len() } else { s.taut_expected.len() },
        fmt(if stage == "pull" { &s.expected } else { &s.taut_expected }));
    println!("recorded     {} nodes {}", want.len(), fmt(want));
    println!("rust         {} nodes {}", got.len(), fmt(got));
    let n = want.len().min(got.len());
    match (0..n).find(|i| want[*i] != got[*i]) {
        Some(i) => println!(
            "first divergent node {i}: recorded ({}, {}) vs rust ({}, {})",
            want[i][0], want[i][1], got[i][0], got[i][1]
        ),
        None => println!("nodes agree up to {n}; the lengths differ"),
    }
}

#[derive(Default)]
struct Tally {
    total: usize,
    determined: usize,
    expanded: usize,
    ok: [usize; 3],
    bad: [usize; 3],
    moved: [usize; 3],
}

const STAGES: [&str; 3] = ["theta", "pull", "walk"];

fn run_file(path: &str, b: Bends, shown: &mut [bool; 3]) -> Tally {
    let c: MoveCorpus = load_moves(path).unwrap_or_else(|e| panic!("{e}"));
    c.header.constants.check().unwrap_or_else(|e| panic!("{path}: corpus constants: {e}"));
    let shipped = ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard);
    let cfg = ThetaCfg::of(
        c.header.fast_planner,
        b.guard.unwrap_or(c.header.fast_planner_guard),
    );
    let bending = b.active();
    let mut t = Tally::default();
    for (ci, call) in c.calls.iter().enumerate() {
        for s in searches(ci, call, &c.header) {
            t.total += 1;
            let got = [
                s.run_bent(call, cfg, b.theta),
                s.run_pull_bent(call, b.pull),
                s.run_walk_bent(call, b.walk),
            ];
            if bending {
                let base = [s.run(call, shipped), s.run_pull(call), s.run_walk(call)];
                for k in 0..3 {
                    if got[k] != base[k] {
                        t.moved[k] += 1;
                    }
                }
            }
            if !s.determined {
                continue;
            }
            t.determined += 1;
            if s.expected.len() >= 3 {
                t.expanded += 1;
            }
            let want = [&s.expected, &s.taut_expected, &s.walked_expected];
            for k in 0..3 {
                if &got[k] == want[k] {
                    t.ok[k] += 1;
                } else {
                    t.bad[k] += 1;
                    if !shown[k] {
                        shown[k] = true;
                        report_mismatch(STAGES[k], &label(path), call, &s, want[k], &got[k], cfg);
                    }
                }
            }
        }
    }
    t
}

fn bench(paths: &[String]) {
    let mut corpora: Vec<MoveCorpus> = Vec::new();
    for p in paths {
        corpora.push(load_moves(p).unwrap_or_else(|e| panic!("{e}")));
    }
    let mut work: Vec<(usize, usize, ReplaySearch)> = Vec::new();
    for (i, c) in corpora.iter().enumerate() {
        for (ci, call) in c.calls.iter().enumerate() {
            for s in searches(ci, call, &c.header) {
                if s.determined {
                    work.push((i, ci, s));
                }
            }
        }
    }
    let cfgs: Vec<ThetaCfg> = corpora
        .iter()
        .map(|c| ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard))
        .collect();

    // Per-search timings — the distribution is BIMODAL (a straight-shot
    // early-out costs a few microseconds, a guard-truncated 320-expansion
    // search costs milliseconds), so a bare mean hides the shape.
    let mut us: Vec<f64> = Vec::with_capacity(work.len());
    let mut nodes = 0usize;
    for (i, ci, s) in &work {
        let call = &corpora[*i].calls[*ci];
        let t = Instant::now();
        let p = s.run(call, cfgs[*i]);
        us.push(t.elapsed().as_secs_f64() * 1e6);
        nodes += std::hint::black_box(p).len();
    }
    let mean: f64 = us.iter().sum::<f64>() / us.len() as f64;
    let expanded: Vec<f64> =
        work.iter().zip(&us).filter(|(w, _)| w.2.expected.len() >= 3).map(|(_, t)| *t).collect();
    let mean_exp: f64 = expanded.iter().sum::<f64>() / expanded.len().max(1) as f64;
    let mut sorted = us.clone();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let q = |f: f64| sorted[((sorted.len() - 1) as f64 * f) as usize];

    // "One typical search", re-timed on its own: the median BY TIME.
    let mut by_time: Vec<usize> = (0..work.len()).collect();
    by_time.sort_by(|a, b| us[*a].partial_cmp(&us[*b]).unwrap());
    let mid = by_time[by_time.len() / 2];
    let (i, ci, s) = &work[mid];
    let call = &corpora[*i].calls[*ci];
    let reps = 500usize;
    let t = Instant::now();
    for _ in 0..reps {
        std::hint::black_box(s.run(call, cfgs[*i]));
    }
    let one = t.elapsed().as_secs_f64() / reps as f64;

    // The two M4-3 stages, over the whole determined set.
    let reps3 = 20usize;
    let t = Instant::now();
    for _ in 0..reps3 {
        for (i, ci, s) in &work {
            std::hint::black_box(s.run_pull(&corpora[*i].calls[*ci]));
        }
    }
    let pull = t.elapsed().as_secs_f64() / (reps3 * work.len()) as f64;
    let t = Instant::now();
    for _ in 0..reps3 {
        for (i, ci, s) in &work {
            std::hint::black_box(s.run_walk(&corpora[*i].calls[*ci]));
        }
    }
    let walk = t.elapsed().as_secs_f64() / (reps3 * work.len()) as f64;

    println!("searches     {} determined, {nodes} path nodes total", work.len());
    println!("theta mean   {mean:9.1} us/search  (all)");
    println!(
        "theta mean   {mean_exp:9.1} us/search  ({} that ran the expansion loop)",
        expanded.len()
    );
    println!(
        "theta spread p10 {:7.1}   p50 {:7.1}   p90 {:7.1}   max {:7.1} us",
        q(0.10), q(0.50), q(0.90), sorted[sorted.len() - 1]
    );
    println!(
        "theta typical{:9.1} us/search  (median by time: unit {:?} model {}, {} recorded nodes, {reps} reps)",
        one * 1e6, call.unit, s.model, s.expected.len()
    );
    println!("string_pull  {:9.2} us/call    ({reps3} reps over the whole set)", pull * 1e6);
    println!("_walk_offset {:9.2} us/call    ({reps3} reps over the whole set)", walk * 1e6);
}

fn main() {
    let mut b = Bends {
        theta: ThetaBend::default(),
        pull: PullBend::default(),
        walk: WalkBend::default(),
        guard: None,
    };
    let mut do_bench = false;
    let mut paths: Vec<String> = Vec::new();
    for a in std::env::args().skip(1) {
        if a == "--strict-open" {
            b.theta.strict_open = true;
        } else if a == "--pull-break" {
            b.pull.cost_break = true;
        } else if a == "--walk-eps-swap" {
            b.walk.eps_swapped = true;
        } else if a == "--bench" {
            do_bench = true;
        } else if let Some(v) = a.strip_prefix("--diag-swap=") {
            let (i, j) = v.split_once(',').expect("--diag-swap=i,j");
            b.theta.diag_swap = Some((i.parse().unwrap(), j.parse().unwrap()));
        } else if let Some(v) = a.strip_prefix("--guard=") {
            b.guard = Some(v.parse().unwrap());
        } else if let Some(v) = a.strip_prefix("--bisect=") {
            b.walk.bisect_steps = v.parse().unwrap();
        } else {
            paths.push(a);
        }
    }
    if paths.is_empty() {
        paths.push(FIXTURE.to_string());
    }
    if do_bench {
        bench(&paths);
        return;
    }
    println!(
        "bend         strict_open={} diag_swap={:?} guard={:?} pull_break={} bisect={} walk_eps_swap={}",
        b.theta.strict_open, b.theta.diag_swap, b.guard, b.pull.cost_break,
        b.walk.bisect_steps, b.walk.eps_swapped
    );
    println!(
        "{:<8} {:>8} {:>10} {:>8} {:>8} {:>4} {:>7} {:>4} {:>7} {:>4}",
        "game", "searches", "determined", "expanded", "theta_ok", "x", "pull_ok", "x", "walk_ok", "x"
    );
    let mut shown = [false; 3];
    let mut tot = Tally::default();
    for p in &paths {
        let t = run_file(p, b, &mut shown);
        println!(
            "{:<8} {:>8} {:>10} {:>8} {:>8} {:>4} {:>7} {:>4} {:>7} {:>4}",
            label(p), t.total, t.determined, t.expanded,
            t.ok[0], t.bad[0], t.ok[1], t.bad[1], t.ok[2], t.bad[2]
        );
        tot.total += t.total;
        tot.determined += t.determined;
        tot.expanded += t.expanded;
        for k in 0..3 {
            tot.ok[k] += t.ok[k];
            tot.bad[k] += t.bad[k];
            tot.moved[k] += t.moved[k];
        }
    }
    println!(
        "{:<8} {:>8} {:>10} {:>8} {:>8} {:>4} {:>7} {:>4} {:>7} {:>4}",
        "TOTAL", tot.total, tot.determined, tot.expanded,
        tot.ok[0], tot.bad[0], tot.ok[1], tot.bad[1], tot.ok[2], tot.bad[2]
    );
    println!("undetermined by trace v1: {}", tot.total - tot.determined);
    if b.active() {
        println!(
            "bend moved:  theta {}  pull {}  walk {}  (of {} replayed)",
            tot.moved[0], tot.moved[1], tot.moved[2], tot.total
        );
    }
    let bad: usize = tot.bad.iter().sum();
    if bad == 0 {
        println!("GATE GREEN — every determined recorded stage is polyline-exact.");
    } else {
        println!(
            "GATE RED — theta {} / pull {} / walk {} of {} determined diverge.",
            tot.bad[0], tot.bad[1], tot.bad[2], tot.determined
        );
        std::process::exit(1);
    }
}
