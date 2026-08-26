//! GATE G4 (NML-1073 M4-4) — `mvflow [flags] [moves_calls.jsonl ...]`
//!
//! Replays `plan_sequential_flow` + `untangle_endpoints` whole, per recorded
//! `plan_unit_step` call, and judges FIVE things against the recording:
//!
//!   order    the flow's processing order         -> `flow_order`
//!   entry    every attempt's post-pull endpoint  -> `trace.flow[].pull`
//!   swap     the 2-opt swap list                 -> `trace.untangle_swaps`
//!   end      the endpoints after untangle        -> rebuilt from the trace
//!   search   every Theta* pop list, RE-ROUTES INCLUDED -> `trace.theta_searches`
//!
//! `search` is the sharpest of the five: the recorder writes one list per
//! search that entered the expansion loop, in invocation order, so the COUNT
//! alone pins how many searches the flow made — the deferral retries and the
//! untangle re-routes among them — and every list is then compared node by node
//! (`g` at 1e-9, the parent's pop index, the open-list size).
//!
//! WHY `planned` IS NOT THE MAIN GATE. The recorded `planned` is post-
//! `solve_formation` and post-`_cap_difficult_polylines`, two stages M4-5/M4-6
//! still owe. It IS reported: on the calls where those stages were inert
//! (`solve_passes` empty and the cap silent) the trace-rebuilt endpoints equal
//! `planned`, and there the port is judged end-to-end at 1e-9 as well.
//!
//! FLAGS (the red proofs; each must make the gate fail):
//!   --untangle-passes=N   UNTANGLE_PASSES (shipped: 4)
//!   --no-defer            the lead-stall deferral rule never fires
//!   --slide-eps=X         CONTACT_SLIDE_EPS_IN (shipped: 0.05)
//!   --strict-open --diag-swap=i,j --pull-break --walk-eps-swap --bisect=N
//!                         the M4-2/M4-3 knobs, passed through
//!   --bench               per-call timing instead of the gate

use std::time::Instant;

use nml_core::mv::flow::{recorded_endpoints, run_call, FlowBend, FlowResult};
use nml_core::mv::io::{MoveCall, ThetaPop};

use nml_core::mv::theta::ThetaCfg;
use nml_core::mv::{load_moves, MoveCorpus, V2};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/moves_v2_s27_head.jsonl");

/// The tolerance for the f64 quantities the JSON carries (`g`, `planned`).
const TOL: f64 = 1e-9;

const STAGES: [&str; 5] = ["order", "entry", "swap", "end", "search"];

#[derive(Default, Clone, Copy)]
struct Tally {
    calls: usize,
    charge_calls: usize,
    entries: usize,
    searches: usize,
    reroutes: usize,
    pops: usize,
    /// Per stage: judged / matched / mismatched.
    seen: [usize; 5],
    ok: [usize; 5],
    bad: [usize; 5],
    /// Same five, restricted to the `allow_contact` calls.
    c_ok: [usize; 5],
    c_bad: [usize; 5],
    /// Calls a bend moved (any of the five).
    moved: usize,
    /// Calls where the recorded `planned` still equals the flow's own endpoints.
    inert: usize,
    inert_ok: usize,
}

impl Tally {
    fn add(&mut self, o: &Tally) {
        self.calls += o.calls;
        self.charge_calls += o.charge_calls;
        self.entries += o.entries;
        self.searches += o.searches;
        self.reroutes += o.reroutes;
        self.pops += o.pops;
        self.moved += o.moved;
        self.inert += o.inert;
        self.inert_ok += o.inert_ok;
        for k in 0..5 {
            self.seen[k] += o.seen[k];
            self.ok[k] += o.ok[k];
            self.bad[k] += o.bad[k];
            self.c_ok[k] += o.c_ok[k];
            self.c_bad[k] += o.c_bad[k];
        }
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

fn fmt(path: &[V2]) -> String {
    let v: Vec<String> = path.iter().map(|p| format!("({}, {})", p[0], p[1])).collect();
    format!("[{}]", v.join(", "))
}

fn pops_same(rec: &[ThetaPop], mine: &[ThetaPop]) -> bool {
    rec.len() == mine.len()
        && rec
            .iter()
            .zip(mine)
            .all(|(r, m)| (r.g - m.g).abs() <= TOL && r.parent == m.parent && r.open == m.open)
}

fn header(call: &MoveCall, ci: usize) {
    println!(
        "call {ci} unit={:?} act={} round={} rung={:?} allow_contact={} models={} allowance={}",
        call.unit,
        call.act,
        call.round,
        call.rung,
        call.allow_contact,
        call.model_pos.len(),
        call.allowance()
    );
}

/// Reports the first divergence of one stage, in full.
fn report(stage: usize, file: &str, ci: usize, call: &MoveCall, got: &FlowResult) {
    println!("\n=== FIRST {} MISMATCH — {file} ===", STAGES[stage]);
    header(call, ci);
    match stage {
        0 => {
            println!("recorded flow_order {:?}", call.flow_order);
            println!("rust     flow_order {:?}", got.order);
        }
        1 => {
            println!(
                "recorded {} attempts, rust {}",
                call.trace.flow.len(),
                got.entries.len()
            );
            for k in 0..call.trace.flow.len().min(got.entries.len()) {
                let (r, m) = (&call.trace.flow[k], &got.entries[k]);
                let rp = r.pulled.unwrap_or([f32::NAN, f32::NAN]);
                if r.model as usize != m.model || r.deferred != m.deferred || rp != m.pulled {
                    println!(
                        "attempt {k}: recorded model={} deferred={} pull=({}, {})",
                        r.model, r.deferred, rp[0], rp[1]
                    );
                    println!(
                        "             rust     model={} deferred={} pull=({}, {})",
                        m.model, m.deferred, m.pulled[0], m.pulled[1]
                    );
                    println!("  recorded theta  {}", fmt(&r.theta));
                    println!("  rust     theta  {}", fmt(&m.theta));
                    println!("  recorded taut   {}", fmt(&r.taut));
                    println!("  rust     taut   {}", fmt(&m.taut));
                    println!("  recorded walked {}", fmt(&r.walked));
                    println!("  rust     walked {}", fmt(&m.walked));
                    return;
                }
            }
            println!("every shared attempt agrees; only the attempt COUNT differs");
        }
        2 => {
            println!("recorded swaps {:?}", call.trace.untangle_swaps);
            println!("rust     swaps {:?}", got.swaps);
        }
        3 => {
            let want = recorded_endpoints(call).unwrap();
            println!("recorded endpoints {}", fmt(&want));
            println!("rust     endpoints {}", fmt(&got.result));
            if let Some(i) = (0..want.len()).find(|i| want[*i] != got.result[*i]) {
                println!(
                    "first divergent model {i}: recorded ({}, {}) vs rust ({}, {})",
                    want[i][0], want[i][1], got.result[i][0], got.result[i][1]
                );
            }
        }
        _ => {
            println!(
                "recorded {} pop lists, rust {}",
                call.trace.theta_searches.len(),
                got.searches.len()
            );
            for k in 0..call.trace.theta_searches.len().min(got.searches.len()) {
                let (r, m) = (&call.trace.theta_searches[k], &got.searches[k]);
                if !pops_same(r, m) {
                    println!("search {k}: recorded {} pops, rust {} pops", r.len(), m.len());
                    for i in 0..r.len().min(m.len()) {
                        if (r[i].g - m[i].g).abs() > TOL
                            || r[i].parent != m[i].parent
                            || r[i].open != m[i].open
                        {
                            println!(
                                "  pop {i}: recorded g={} parent={} open={}   rust g={} parent={} open={}",
                                r[i].g, r[i].parent, r[i].open, m[i].g, m[i].parent, m[i].open
                            );
                            return;
                        }
                    }
                    println!("  every shared pop agrees; only the pop COUNT differs");
                    return;
                }
            }
            println!("every shared list agrees; only the LIST COUNT differs");
        }
    }
}

fn run_file(path: &str, bend: FlowBend, shown: &mut [bool; 5]) -> Tally {
    let c: MoveCorpus = load_moves(path).unwrap_or_else(|e| panic!("{e}"));
    c.header.constants.check().unwrap_or_else(|e| panic!("{path}: corpus constants: {e}"));
    let cfg = ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard);
    let bending = bend.active();
    let mut t = Tally::default();
    for (ci, call) in c.calls.iter().enumerate() {
        if call.trace.flow.is_empty() && !call.model_pos.is_empty() {
            continue; // an untraced line carries no stage truth
        }
        t.calls += 1;
        let charge = call.allow_contact;
        if charge {
            t.charge_calls += 1;
        }
        let got = run_call(call, cfg, bend);
        if bending && got.result != run_call(call, cfg, FlowBend::default()).result {
            t.moved += 1;
        }
        t.entries += got.entries.len();
        t.searches += got.searches.len();
        t.reroutes += got.searches.len() - got.flow_searches;

        // (0) the flow order.
        let order_ok = got.order == call.flow_order;
        // (1) every attempt: which model, whether it deferred, and its post-pull
        //     endpoint. f32 on both sides -> exact equality.
        let entry_ok = got.entries.len() == call.trace.flow.len()
            && got.entries.iter().zip(&call.trace.flow).all(|(m, r)| {
                m.model as i64 == r.model
                    && m.deferred == r.deferred
                    && r.pulled.map(|p| p == m.pulled).unwrap_or(false)
            });
        // (2) the 2-opt swap list, in order.
        let swap_ok = got.swaps == call.trace.untangle_swaps;
        // (3) the endpoints after untangle.
        let want_end = recorded_endpoints(call);
        let end_ok = want_end.as_ref().map(|w| *w == got.result);
        // (4) every pop list, re-routes included.
        let search_ok = got.searches.len() == call.trace.theta_searches.len()
            && got
                .searches
                .iter()
                .zip(&call.trace.theta_searches)
                .all(|(m, r)| pops_same(r, m));
        for r in &call.trace.theta_searches {
            t.pops += r.len();
        }

        let flags = [Some(order_ok), Some(entry_ok), Some(swap_ok), end_ok, Some(search_ok)];
        for (k, f) in flags.iter().enumerate() {
            let Some(ok) = f else { continue };
            t.seen[k] += 1;
            if *ok {
                t.ok[k] += 1;
                if charge {
                    t.c_ok[k] += 1;
                }
            } else {
                t.bad[k] += 1;
                if charge {
                    t.c_bad[k] += 1;
                }
                if !shown[k] {
                    shown[k] = true;
                    report(k, &label(path), ci, call, &got);
                }
            }
        }

        // The end-to-end tie: where the later stages were inert, the recorded
        // `planned` IS the flow's own answer.
        if let Some(w) = &want_end {
            if w.len() == call.planned.len()
                && w.iter().zip(&call.planned).all(|(a, b)| {
                    (a[0] as f64 - b[0] as f64).abs() <= TOL
                        && (a[1] as f64 - b[1] as f64).abs() <= TOL
                })
            {
                t.inert += 1;
                if got.result.iter().zip(&call.planned).all(|(a, b)| {
                    (a[0] as f64 - b[0] as f64).abs() <= TOL
                        && (a[1] as f64 - b[1] as f64).abs() <= TOL
                }) {
                    t.inert_ok += 1;
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
    let bend = FlowBend::default();
    let mut ms: Vec<f64> = Vec::new();
    let mut models = 0usize;
    let mut sink = 0usize;
    for c in &corpora {
        let cfg = ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard);
        for call in &c.calls {
            let t = Instant::now();
            let r = run_call(call, cfg, bend);
            ms.push(t.elapsed().as_secs_f64() * 1e3);
            models += call.model_pos.len();
            sink += std::hint::black_box(r).result.len();
        }
    }
    let mean: f64 = ms.iter().sum::<f64>() / ms.len() as f64;
    let mut sorted = ms.clone();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let q = |f: f64| sorted[((sorted.len() - 1) as f64 * f) as usize];
    println!("flow calls   {} ({} models, sink {sink})", ms.len(), models);
    println!("flow mean    {mean:9.3} ms/call");
    println!(
        "flow spread  p10 {:7.3}   p50 {:7.3}   p90 {:7.3}   max {:7.3} ms",
        q(0.10),
        q(0.50),
        q(0.90),
        sorted[sorted.len() - 1]
    );
    println!("flow total   {:9.3} s over the whole corpus", ms.iter().sum::<f64>() / 1e3);
}

fn main() {
    let mut bend = FlowBend::default();
    let mut do_bench = false;
    let mut paths: Vec<String> = Vec::new();
    for a in std::env::args().skip(1) {
        if a == "--no-defer" {
            bend.no_defer = true;
        } else if a == "--strict-open" {
            bend.theta.strict_open = true;
        } else if a == "--pull-break" {
            bend.pull.cost_break = true;
        } else if a == "--walk-eps-swap" {
            bend.walk.eps_swapped = true;
        } else if a == "--bench" {
            do_bench = true;
        } else if let Some(v) = a.strip_prefix("--untangle-passes=") {
            bend.untangle_passes = v.parse().unwrap();
        } else if let Some(v) = a.strip_prefix("--slide-eps=") {
            bend.contact_slide_eps_in = v.parse().unwrap();
        } else if let Some(v) = a.strip_prefix("--bisect=") {
            bend.walk.bisect_steps = v.parse().unwrap();
        } else if let Some(v) = a.strip_prefix("--diag-swap=") {
            let (i, j) = v.split_once(',').expect("--diag-swap=i,j");
            bend.theta.diag_swap = Some((i.parse().unwrap(), j.parse().unwrap()));
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
        "bend         untangle_passes={} no_defer={} slide_eps={} strict_open={} diag_swap={:?} \
         pull_break={} bisect={} walk_eps_swap={}",
        bend.untangle_passes,
        bend.no_defer,
        bend.contact_slide_eps_in,
        bend.theta.strict_open,
        bend.theta.diag_swap,
        bend.pull.cost_break,
        bend.walk.bisect_steps,
        bend.walk.eps_swapped
    );
    println!(
        "{:<8} {:>6} {:>7} {:>4} {:>7} {:>4} {:>6} {:>4} {:>6} {:>4} {:>8} {:>4}",
        "game", "calls", "order", "x", "entry", "x", "swap", "x", "end", "x", "search", "x"
    );
    let mut shown = [false; 5];
    let mut tot = Tally::default();
    for p in &paths {
        let t = run_file(p, bend, &mut shown);
        println!(
            "{:<8} {:>6} {:>7} {:>4} {:>7} {:>4} {:>6} {:>4} {:>6} {:>4} {:>8} {:>4}",
            label(p),
            t.calls,
            t.ok[0],
            t.bad[0],
            t.ok[1],
            t.bad[1],
            t.ok[2],
            t.bad[2],
            t.ok[3],
            t.bad[3],
            t.ok[4],
            t.bad[4]
        );
        tot.add(&t);
    }
    println!(
        "{:<8} {:>6} {:>7} {:>4} {:>7} {:>4} {:>6} {:>4} {:>6} {:>4} {:>8} {:>4}",
        "TOTAL",
        tot.calls,
        tot.ok[0],
        tot.bad[0],
        tot.ok[1],
        tot.bad[1],
        tot.ok[2],
        tot.bad[2],
        tot.ok[3],
        tot.bad[3],
        tot.ok[4],
        tot.bad[4]
    );
    println!(
        "volume:      {} calls, {} attempts, {} Theta* searches ({} of them untangle re-routes; \
         {} popped nodes recorded)",
        tot.calls, tot.entries, tot.searches, tot.reroutes, tot.pops
    );
    println!(
        "charges:     {} allow_contact calls — order {}/{} entry {}/{} swap {}/{} end {}/{} search {}/{}",
        tot.charge_calls,
        tot.c_ok[0], tot.c_ok[0] + tot.c_bad[0],
        tot.c_ok[1], tot.c_ok[1] + tot.c_bad[1],
        tot.c_ok[2], tot.c_ok[2] + tot.c_bad[2],
        tot.c_ok[3], tot.c_ok[3] + tot.c_bad[3],
        tot.c_ok[4], tot.c_ok[4] + tot.c_bad[4],
    );
    println!(
        "end-to-end:  {} of {} calls where solve_formation + the difficult cap were inert; \
         {} of those match the recorded `planned` at {TOL:e}",
        tot.inert, tot.calls, tot.inert_ok
    );
    if tot.seen[3] < tot.calls {
        println!("endpoints unjudged (no trace v2 `pull`): {}", tot.calls - tot.seen[3]);
    }
    if bend.active() {
        println!("bend moved:  {} of {} calls' endpoint sets", tot.moved, tot.calls);
    }
    let bad: usize = tot.bad.iter().sum::<usize>() + (tot.inert - tot.inert_ok);
    if bad == 0 {
        println!("GATE GREEN — every recorded flow stage is reproduced.");
    } else {
        println!(
            "GATE RED — order {} / entry {} / swap {} / end {} / search {} of {} calls diverge; \
             {} inert calls miss `planned`.",
            tot.bad[0], tot.bad[1], tot.bad[2], tot.bad[3], tot.bad[4], tot.calls,
            tot.inert - tot.inert_ok
        );
        std::process::exit(1);
    }
}
