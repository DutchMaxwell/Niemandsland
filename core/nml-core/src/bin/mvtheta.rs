//! GATE G2 (NML-1073 M4-2) — `mvtheta [flags] [moves_calls.jsonl ...]`
//!
//! Replays every Theta* search a recorded `plan_unit_step` call made and
//! compares the Rust path to the recorded one NODE FOR NODE. Positions are f32
//! on both sides (the corpus numbers are exactly-representable f32), so the
//! comparison is exact equality, not a tolerance.
//!
//! Searches whose inputs trace v1 cannot pin down are counted but not judged —
//! see `mv::replay` for which ones and why. They are reported as `undetermined`;
//! the gate is the `matched == determined` line.
//!
//! FLAGS (the red proofs; each must make the gate fail):
//!   --strict-open      the open list picks min-f by a strict `f < best_f`,
//!                      dropping the EPS rule and the `_cell_before` tie-break
//!   --diag-swap=i,j    swap two entries of THETA_DIAG
//!   --guard=N          run with `fast_planner_guard = N` (shipped: 320)
//!   --bench            micro-bench instead of the gate

use std::time::Instant;

use nml_core::mv::io::MoveCall;
use nml_core::mv::replay::{searches, ReplaySearch};
use nml_core::mv::theta::{ThetaBend, ThetaCfg};
use nml_core::mv::{load_moves, MoveCorpus};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/moves_s27.jsonl");

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

fn report_mismatch(file: &str, call: &MoveCall, s: &ReplaySearch, got: &[[f32; 2]], cfg: ThetaCfg) {
    println!("\n=== FIRST MISMATCH — {file} ===");
    println!(
        "call {} unit={:?} act={} round={} rung={:?} allow_contact={} models={}",
        s.call,
        call.unit,
        call.act,
        call.round,
        call.rung,
        call.allow_contact,
        call.model_pos.len()
    );
    println!(
        "flow entry {} model {} charge={} reach_closest={}",
        s.entry, s.model, s.charge, s.reach_closest
    );
    println!("start        ({}, {})", s.start[0], s.start[1]);
    println!("goal         ({}, {})", s.goal[0], s.goal[1]);
    println!("board        ({}, {})", call.board()[0], call.board()[1]);
    println!(
        "opts         clearance={} zones={} avoid_cells={} grid={} walls={}",
        call.opts.clearance,
        s.zones.len(),
        call.opts.avoid_cells.len(),
        call.grid.len(),
        call.walls.len()
    );
    println!("cfg          fast_planner={} guard={}", cfg.fast_planner, cfg.fast_planner_guard);
    println!("delta        ({}, {})", call.delta[0], call.delta[1]);
    for (i, z) in s.zones.iter().enumerate() {
        println!("  zone[{i:3}]  c=({}, {}) r={}", z.c[0], z.c[1], z.r);
    }
    println!("recorded {} nodes {}", s.expected.len(), fmt(&s.expected));
    println!("rust     {} nodes {}", got.len(), fmt(got));
    let n = s.expected.len().min(got.len());
    let first = (0..n).find(|i| s.expected[*i] != got[*i]);
    match first {
        Some(i) => println!(
            "first divergent node {i}: recorded ({}, {}) vs rust ({}, {})",
            s.expected[i][0], s.expected[i][1], got[i][0], got[i][1]
        ),
        None => println!("nodes agree up to {n}; the lengths differ"),
    }
}

struct Tally {
    total: usize,
    determined: usize,
    matched: usize,
    mismatched: usize,
    /// Determined searches whose RECORDED path has >= 3 nodes, i.e. the
    /// expansion loop provably ran and `_theta_reconstruct` produced the answer.
    expanded: usize,
    /// Searches (determined or not) whose path the active bend MOVES, against
    /// the same inputs. Zero here means the bend never bit — the red proof is
    /// vacuous, not passed.
    bend_moved: usize,
}

fn run_file(path: &str, bend: ThetaBend, guard: Option<i64>, shown: &mut bool) -> Tally {
    let c: MoveCorpus = load_moves(path).unwrap_or_else(|e| panic!("{e}"));
    c.header.constants.check().unwrap_or_else(|e| panic!("{path}: corpus constants: {e}"));
    let cfg = ThetaCfg::of(
        c.header.fast_planner,
        guard.unwrap_or(c.header.fast_planner_guard),
    );
    let bending = bend.strict_open || bend.diag_swap.is_some() || guard.is_some();
    let base_cfg = ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard);
    let mut t = Tally {
        total: 0,
        determined: 0,
        matched: 0,
        mismatched: 0,
        expanded: 0,
        bend_moved: 0,
    };
    for (ci, call) in c.calls.iter().enumerate() {
        for s in searches(ci, call, &c.header) {
            t.total += 1;
            if bending && s.run_bent(call, cfg, bend) != s.run(call, base_cfg) {
                t.bend_moved += 1;
            }
            if !s.determined {
                continue;
            }
            t.determined += 1;
            if s.expected.len() >= 3 {
                t.expanded += 1;
            }
            let got = s.run_bent(call, cfg, bend);
            if got == s.expected {
                t.matched += 1;
            } else {
                t.mismatched += 1;
                if !*shown {
                    *shown = true;
                    report_mismatch(&label(path), call, &s, &got, cfg);
                }
            }
        }
    }
    t
}

fn bench(paths: &[String]) {
    let mut corpora: Vec<(MoveCorpus, String)> = Vec::new();
    for p in paths {
        corpora.push((load_moves(p).unwrap_or_else(|e| panic!("{e}")), p.clone()));
    }
    let mut work: Vec<(usize, usize, ReplaySearch)> = Vec::new();
    for (i, (c, _)) in corpora.iter().enumerate() {
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
        .map(|(c, _)| ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard))
        .collect();

    // Per-search timings — the distribution is BIMODAL (a straight-shot
    // early-out costs a few microseconds, a guard-truncated 320-expansion
    // search costs milliseconds), so a bare mean hides the shape.
    let mut us: Vec<f64> = Vec::with_capacity(work.len());
    let mut nodes = 0usize;
    for (i, ci, s) in &work {
        let call = &corpora[*i].0.calls[*ci];
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
    let call = &corpora[*i].0.calls[*ci];
    let reps = 500usize;
    let t = Instant::now();
    for _ in 0..reps {
        std::hint::black_box(s.run(call, cfgs[*i]));
    }
    let one = t.elapsed().as_secs_f64() / reps as f64;

    println!("searches     {} determined, {nodes} path nodes total", work.len());
    println!("mean         {mean:9.1} us/search  (all)");
    println!(
        "mean         {mean_exp:9.1} us/search  ({} that ran the expansion loop)",
        expanded.len()
    );
    println!(
        "spread       p10 {:7.1}   p50 {:7.1}   p90 {:7.1}   max {:7.1} us",
        q(0.10),
        q(0.50),
        q(0.90),
        sorted[sorted.len() - 1]
    );
    println!(
        "typical      {:9.1} us/search  (median by time: unit {:?} model {}, {} recorded nodes, {reps} reps)",
        one * 1e6,
        call.unit,
        s.model,
        s.expected.len()
    );
}

fn main() {
    let mut bend = ThetaBend::default();
    let mut guard: Option<i64> = None;
    let mut do_bench = false;
    let mut paths: Vec<String> = Vec::new();
    for a in std::env::args().skip(1) {
        if a == "--strict-open" {
            bend.strict_open = true;
        } else if a == "--bench" {
            do_bench = true;
        } else if let Some(v) = a.strip_prefix("--diag-swap=") {
            let (i, j) = v.split_once(',').expect("--diag-swap=i,j");
            bend.diag_swap = Some((i.parse().unwrap(), j.parse().unwrap()));
        } else if let Some(v) = a.strip_prefix("--guard=") {
            guard = Some(v.parse().unwrap());
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
    println!("bend         strict_open={} diag_swap={:?} guard={:?}", bend.strict_open, bend.diag_swap, guard);
    println!(
        "{:<10} {:>9} {:>11} {:>9} {:>9} {:>11} {:>11}",
        "game", "searches", "determined", "expanded", "matched", "mismatched", "bend_moved"
    );
    let mut shown = false;
    let (mut tt, mut td, mut te, mut tm, mut tx, mut tb) =
        (0usize, 0usize, 0usize, 0usize, 0usize, 0usize);
    for p in &paths {
        let t = run_file(p, bend, guard, &mut shown);
        println!(
            "{:<10} {:>9} {:>11} {:>9} {:>9} {:>11} {:>11}",
            label(p),
            t.total,
            t.determined,
            t.expanded,
            t.matched,
            t.mismatched,
            t.bend_moved
        );
        tt += t.total;
        td += t.determined;
        te += t.expanded;
        tm += t.matched;
        tx += t.mismatched;
        tb += t.bend_moved;
    }
    println!(
        "{:<10} {:>9} {:>11} {:>9} {:>9} {:>11} {:>11}",
        "TOTAL", tt, td, te, tm, tx, tb
    );
    println!("undetermined by trace v1: {}", tt - td);
    if tx == 0 {
        println!("GATE GREEN — every determined recorded search is path-exact.");
    } else {
        println!("GATE RED — {tx} of {td} determined searches diverge.");
        std::process::exit(1);
    }
}
