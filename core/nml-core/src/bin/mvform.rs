//! GATE G5 (NML-1073 M4-5) — `mvform [flags] [moves_calls.jsonl ...]`
//!
//! Runs the WHOLE `plan_unit_step` pipeline per recorded call and judges four
//! things against the recording:
//!
//!   solve    `solve_formation`'s positions AND score after EVERY sweep
//!            -> `trace.solve_passes` (the recorder writes one entry per pass,
//!            move_recorder.gd:208), so this is not an end-state comparison:
//!            a pass that lands on the right answer by the wrong route fails.
//!   slots    `charge_contact_slots(model_pos, radii, charge_tgt_bases)`
//!            -> `opts["charge_slots"]`, the value the CALLER computed and
//!            passed in (solo_controller.gd:6033). 11 charge calls.
//!   planned  the returned per-model positions   -> `planned`
//!   trails   the returned per-model polylines    -> `trails`
//!            (and `flow_order` alongside, which M4-4 already gated)
//!
//! The difficult cap has no recorded channel of its own; it is reported as a
//! census (how many polylines it trimmed, how many were over the cap but clear)
//! and it is falsified through `planned`/`trails` — shifting the threshold by
//! one plan cell moves both.
//!
//! FLAGS (the red proofs; each must make the gate fail):
//!   --solve-passes=N    SOLVE_PASSES (shipped: 24)
//!   --reverse-pairs     sweep `_project_separate` backwards
//!   --cap-delta=X       shift the p.11 cap by X inches (one plan cell = 1.0)
//!   plus every M4-2/M4-3/M4-4 knob, passed through
//!   --bench             per-call timing of the whole pipeline instead

use std::time::Instant;

use nml_core::mv::charge::charge_contact_slots;
use nml_core::mv::io::MoveCall;
use nml_core::mv::plan::{plan_unit_step, plan_unit_step_cfg, PlanBend, Planned};
use nml_core::mv::theta::ThetaCfg;
use nml_core::mv::{load_moves, MoveCorpus, V2};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/moves_v2_s27_head.jsonl");

/// The tolerance for the f64 quantities the JSON carries (the pass score).
const TOL: f64 = 1e-9;

const STAGES: [&str; 4] = ["solve", "slots", "planned", "trails"];

#[derive(Default, Clone, Copy)]
struct Tally {
    calls: usize,
    charge_calls: usize,
    solving: usize,
    passes: usize,
    trimmed: usize,
    over_clear: usize,
    order_ok: usize,
    order_bad: usize,
    /// Per stage: judged / matched / mismatched.
    seen: [usize; 4],
    ok: [usize; 4],
    bad: [usize; 4],
    /// Calls a bend moved (`planned` or `trails`).
    moved: usize,
    /// Calls where `plan_unit_step(call)` (the shipped-cfg convenience entry)
    /// disagrees with the header-driven one.
    cfg_split: usize,
}

impl Tally {
    fn add(&mut self, o: &Tally) {
        self.calls += o.calls;
        self.charge_calls += o.charge_calls;
        self.solving += o.solving;
        self.passes += o.passes;
        self.trimmed += o.trimmed;
        self.over_clear += o.over_clear;
        self.order_ok += o.order_ok;
        self.order_bad += o.order_bad;
        self.moved += o.moved;
        self.cfg_split += o.cfg_split;
        for k in 0..4 {
            self.seen[k] += o.seen[k];
            self.ok[k] += o.ok[k];
            self.bad[k] += o.bad[k];
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

fn header(call: &MoveCall, ci: usize) {
    println!(
        "call {ci} unit={:?} act={} round={} rung={:?} allow_contact={} models={} \
         cap={:?} forbid={} zones={}",
        call.unit,
        call.act,
        call.round,
        call.rung,
        call.allow_contact,
        call.model_pos.len(),
        call.opts.difficult_cap_in,
        call.opts.forbid_cells.len(),
        call.opts.zones.len()
    );
}

/// Reports the first divergence of one stage, in full.
fn report(stage: usize, file: &str, ci: usize, call: &MoveCall, got: &Planned) {
    println!("\n=== FIRST {} MISMATCH — {file} ===", STAGES[stage]);
    header(call, ci);
    match stage {
        0 => {
            println!(
                "recorded {} sweeps, rust {}",
                call.trace.solve_passes.len(),
                got.solve.passes.len()
            );
            for k in 0..call.trace.solve_passes.len().min(got.solve.passes.len()) {
                let (r, m) = (&call.trace.solve_passes[k], &got.solve.passes[k]);
                if r.positions != m.positions || (r.score - m.score).abs() > TOL {
                    println!("sweep {k} (recorded pass index {})", r.pass);
                    println!("  recorded score {}   rust score {}", r.score, m.score);
                    println!("  recorded {}", fmt(&r.positions));
                    println!("  rust     {}", fmt(&m.positions));
                    if let Some(i) = (0..r.positions.len().min(m.positions.len()))
                        .find(|i| r.positions[*i] != m.positions[*i])
                    {
                        println!(
                            "  first divergent model {i}: recorded ({}, {}) vs rust ({}, {})",
                            r.positions[i][0], r.positions[i][1], m.positions[i][0],
                            m.positions[i][1]
                        );
                    }
                    return;
                }
            }
            println!("every shared sweep agrees; only the SWEEP COUNT differs");
        }
        1 => {
            let mine =
                charge_contact_slots(&call.model_pos, &call.opts.radii, &call.opts.charge_tgt_bases);
            println!("recorded slots {}", fmt(&call.opts.charge_slots));
            println!("rust     slots {}", fmt(&mine));
        }
        2 => {
            println!("recorded planned {}", fmt(&call.planned));
            println!("rust     planned {}", fmt(&got.planned));
            if let Some(i) =
                (0..call.planned.len().min(got.planned.len())).find(|i| call.planned[*i] != got.planned[*i])
            {
                println!(
                    "first divergent model {i}: recorded ({}, {}) vs rust ({}, {})",
                    call.planned[i][0], call.planned[i][1], got.planned[i][0], got.planned[i][1]
                );
            }
            println!(
                "solver sweeps: recorded {} rust {}; cap trimmed {}",
                call.trace.solve_passes.len(),
                got.solve.passes.len(),
                got.cap.trimmed
            );
        }
        _ => {
            println!("recorded {} trails, rust {}", call.trails.len(), got.trails.len());
            for i in 0..call.trails.len().min(got.trails.len()) {
                if call.trails[i] != got.trails[i] {
                    println!("trail {i}: recorded {}", fmt(&call.trails[i]));
                    println!("         rust     {}", fmt(&got.trails[i]));
                    return;
                }
            }
            println!("every shared trail agrees; only the TRAIL COUNT differs");
        }
    }
}

fn run_file(path: &str, bend: PlanBend, shown: &mut [bool; 4]) -> Tally {
    let c: MoveCorpus = load_moves(path).unwrap_or_else(|e| panic!("{e}"));
    c.header.constants.check().unwrap_or_else(|e| panic!("{path}: corpus constants: {e}"));
    let cfg = ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard);
    let bending = bend.active();
    let mut t = Tally::default();
    for (ci, call) in c.calls.iter().enumerate() {
        t.calls += 1;
        let got = plan_unit_step_cfg(call, cfg, bend);
        if bending && (got.planned != plan_unit_step_cfg(call, cfg, PlanBend::default()).planned) {
            t.moved += 1;
        }
        if !bending && plan_unit_step(call).planned != got.planned {
            t.cfg_split += 1;
        }
        t.passes += got.solve.passes.len();
        if !got.solve.passes.is_empty() {
            t.solving += 1;
        }
        t.trimmed += got.cap.trimmed;
        t.over_clear += got.cap.over_but_clear;

        // (0) every solver sweep, positions f32-exact and score at 1e-9. Judged
        //     only on a TRACED line (an untraced call carries no sweeps at all).
        let traced = !call.trace.flow.is_empty() || call.model_pos.is_empty();
        let solve_ok = if traced {
            Some(
                got.solve.passes.len() == call.trace.solve_passes.len()
                    && got.solve.passes.iter().zip(&call.trace.solve_passes).all(|(m, r)| {
                        m.positions == r.positions && (m.score - r.score).abs() <= TOL
                    }),
            )
        } else {
            None
        };
        // (1) the caller-side contact slots, on the charge calls only.
        let slots_ok = if call.allow_contact && !call.opts.charge_tgt_bases.is_empty() {
            t.charge_calls += 1;
            Some(
                charge_contact_slots(
                    &call.model_pos,
                    &call.opts.radii,
                    &call.opts.charge_tgt_bases,
                ) == call.opts.charge_slots,
            )
        } else {
            None
        };
        // (2)/(3) end to end. Both sides are f32 -> exact equality.
        let planned_ok = Some(got.planned == call.planned);
        let trails_ok = Some(got.trails == call.trails);
        if got.flow_order == call.flow_order {
            t.order_ok += 1;
        } else {
            t.order_bad += 1;
        }

        let flags = [solve_ok, slots_ok, planned_ok, trails_ok];
        for (k, f) in flags.iter().enumerate() {
            let Some(ok) = f else { continue };
            t.seen[k] += 1;
            if *ok {
                t.ok[k] += 1;
            } else {
                t.bad[k] += 1;
                if !shown[k] {
                    shown[k] = true;
                    report(k, &label(path), ci, call, &got);
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
    let bend = PlanBend::default();
    let mut ms: Vec<f64> = Vec::new();
    let mut models = 0usize;
    let mut sink = 0usize;
    for c in &corpora {
        let cfg = ThetaCfg::of(c.header.fast_planner, c.header.fast_planner_guard);
        for call in &c.calls {
            let t = Instant::now();
            let r = plan_unit_step_cfg(call, cfg, bend);
            ms.push(t.elapsed().as_secs_f64() * 1e3);
            models += call.model_pos.len();
            sink += std::hint::black_box(r).planned.len();
        }
    }
    let mean: f64 = ms.iter().sum::<f64>() / ms.len() as f64;
    let mut sorted = ms.clone();
    sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
    let q = |f: f64| sorted[((sorted.len() - 1) as f64 * f) as usize];
    let total = ms.iter().sum::<f64>() / 1e3;
    println!("plan calls   {} ({} models, sink {sink})", ms.len(), models);
    println!("plan mean    {mean:9.3} ms/call");
    println!(
        "plan spread  p10 {:7.3}   p50 {:7.3}   p90 {:7.3}   max {:7.3} ms",
        q(0.10),
        q(0.50),
        q(0.90),
        sorted[sorted.len() - 1]
    );
    println!("plan total   {total:9.3} s over the whole corpus ({} games)", corpora.len());
    println!(
        "per game     {:9.3} s  (GDScript profile: ~2.6 s per call, ~{:.0} s per game)",
        total / corpora.len() as f64,
        2.6 * ms.len() as f64 / corpora.len() as f64
    );
}

fn main() {
    let mut bend = PlanBend::default();
    let mut do_bench = false;
    let mut paths: Vec<String> = Vec::new();
    for a in std::env::args().skip(1) {
        if a == "--no-defer" {
            bend.flow.no_defer = true;
        } else if a == "--strict-open" {
            bend.flow.theta.strict_open = true;
        } else if a == "--pull-break" {
            bend.flow.pull.cost_break = true;
        } else if a == "--walk-eps-swap" {
            bend.flow.walk.eps_swapped = true;
        } else if a == "--reverse-pairs" {
            bend.form.reverse_pairs = true;
        } else if a == "--bench" {
            do_bench = true;
        } else if let Some(v) = a.strip_prefix("--untangle-passes=") {
            bend.flow.untangle_passes = v.parse().unwrap();
        } else if let Some(v) = a.strip_prefix("--slide-eps=") {
            bend.flow.contact_slide_eps_in = v.parse().unwrap();
        } else if let Some(v) = a.strip_prefix("--bisect=") {
            bend.flow.walk.bisect_steps = v.parse().unwrap();
        } else if let Some(v) = a.strip_prefix("--solve-passes=") {
            bend.form.solve_passes = v.parse().unwrap();
        } else if let Some(v) = a.strip_prefix("--cap-delta=") {
            bend.cap_delta_in = v.parse().unwrap();
        } else if let Some(v) = a.strip_prefix("--diag-swap=") {
            let (i, j) = v.split_once(',').expect("--diag-swap=i,j");
            bend.flow.theta.diag_swap = Some((i.parse().unwrap(), j.parse().unwrap()));
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
        "bend         solve_passes={} reverse_pairs={} cap_delta={} | untangle_passes={} \
         no_defer={} slide_eps={}",
        bend.form.solve_passes,
        bend.form.reverse_pairs,
        bend.cap_delta_in,
        bend.flow.untangle_passes,
        bend.flow.no_defer,
        bend.flow.contact_slide_eps_in
    );
    println!(
        "{:<8} {:>6} {:>7} {:>4} {:>6} {:>4} {:>8} {:>4} {:>7} {:>4}",
        "game", "calls", "solve", "x", "slots", "x", "planned", "x", "trails", "x"
    );
    let mut shown = [false; 4];
    let mut tot = Tally::default();
    for p in &paths {
        let t = run_file(p, bend, &mut shown);
        println!(
            "{:<8} {:>6} {:>7} {:>4} {:>6} {:>4} {:>8} {:>4} {:>7} {:>4}",
            label(p),
            t.calls,
            t.ok[0], t.bad[0],
            t.ok[1], t.bad[1],
            t.ok[2], t.bad[2],
            t.ok[3], t.bad[3]
        );
        tot.add(&t);
    }
    println!(
        "{:<8} {:>6} {:>7} {:>4} {:>6} {:>4} {:>8} {:>4} {:>7} {:>4}",
        "TOTAL",
        tot.calls,
        tot.ok[0], tot.bad[0],
        tot.ok[1], tot.bad[1],
        tot.ok[2], tot.bad[2],
        tot.ok[3], tot.bad[3]
    );
    println!(
        "volume:      {} calls, {} of them ran solve_formation ({} sweeps traced); \
         {} allow_contact calls",
        tot.calls, tot.solving, tot.passes, tot.charge_calls
    );
    println!(
        "difficult cap: trimmed {} polylines; {} were over the cap but crossed no difficult cell",
        tot.trimmed, tot.over_clear
    );
    println!("flow_order:  {} ok / {} bad", tot.order_ok, tot.order_bad);
    if !bend.active() && tot.cfg_split > 0 {
        println!(
            "WARNING: plan_unit_step()'s shipped ThetaCfg disagrees with the header on {} calls",
            tot.cfg_split
        );
    }
    if bend.active() {
        println!("bend moved:  {} of {} calls' planned positions", tot.moved, tot.calls);
    }
    let bad: usize = tot.bad.iter().sum::<usize>() + tot.order_bad + tot.cfg_split;
    if bad == 0 {
        println!("GATE GREEN — solve_formation, the charge slots, the cap and the whole pipeline reproduce the recording.");
    } else {
        println!(
            "GATE RED — solve {} / slots {} / planned {} / trails {} / flow_order {} of {} calls diverge.",
            tot.bad[0], tot.bad[1], tot.bad[2], tot.bad[3], tot.order_bad, tot.calls
        );
        std::process::exit(1);
    }
}
