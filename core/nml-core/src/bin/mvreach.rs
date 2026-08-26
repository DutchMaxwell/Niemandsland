//! GATE G7 (NML-1073 M4-7) — `mvreach [flags] [moves_calls.jsonl ...]`
//!
//! Tier 2 (`mv::reach::reach_query`) judged against TIER 1 (`mv::plan::
//! plan_unit_step`, the exact solver, output-identical to the GDScript) on the
//! recorded move corpus. Tier 2 is an APPROXIMATION, so this gate measures
//! AGREEMENT, not identity, and the bar was fixed before the first number:
//!
//!   >= 97 %  boolean agreement (reachable / not)
//!   >= 90 %  of the agreed calls placing the end centre within 1.0"
//!
//! HOW A RECORDED CALL BECOMES A QUERY (all pre-registered):
//!   start   `centroid(model_pos)`             — the unit centre
//!   target  `start + delta`                   — the recorded intent
//!   radius  `opts["clearance"]`               — the largest base + CLEARANCE_EPS
//!   band    `call.allowance()`                — charge_allowance, else |delta|
//!   cap_in  `opts["difficult_cap_in"]`        — the p.11 6" cap of this rung
//!   index   this call's walls, typed grid, `avoid_cells` (the rung's hard set)
//!           and `opts["zones"]`
//!
//! AND WHAT TIER 1 ANSWERS:
//!   end centre  `centroid(plan_unit_step(call).planned)`
//!   reachable   that centroid within `ARRIVE_IN` = BASE_CONTACT_IN = 2.0" of
//!               the target. Two inches, not zero: the exact solver's formation
//!               and spacing passes legitimately shift an ARRIVED unit's
//!               centroid by a base, and a threshold of 1.0" would make the
//!               end-centre metric below a tautology (tier 2's reachable end IS
//!               the target). The 1.0" variant is printed alongside so the
//!               choice is auditable rather than convenient.
//!
//! FLAGS:
//!   --cell=X    the coarse cell, inches (shipped 2.0). RED PROOF: 4.0 moves
//!               every number, so the cell is load-bearing.
//!   --cap=N     the expansion cap (shipped 192). MEASURED INERT at 96 and 24 —
//!               the band bound binds long before the cap does (22.6 expansions
//!               a search); 16 finally moves the end centres. Reported as a
//!               finding, not hidden: a red proof that does not redden is a
//!               statement about the knob, not about the gate.
//!   --pull=N    the string-pull lookahead (shipped 6).
//!   --picks=P   gate (c)'s information half: how many acts of an ACT corpus
//!               change their pick with the path seam ON.
//!   --why       the disagreement cross-tab (route, blocker, which exact stage
//!               ran), for the failure profile.
//!   --bench     per-query timing with a warm index instead of the gate
//!   --quiet     numbers only

use std::time::Instant;

use nml_core::mv::flow::centroid;
use nml_core::mv::geom2::{add, distance_to};
use nml_core::mv::io::MoveCall;
use nml_core::mv::plan::plan_unit_step;
use nml_core::mv::reach::{ReachIndex, ReachQuery, NO_OWNER};
use nml_core::mv::{load_moves, BASE_CONTACT_IN, REACH_CAP, REACH_CELL_IN};

const FIXTURE: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/moves_v2_s27_head.jsonl");

/// How close tier 1's centroid must land to the destination to count as
/// "reached". See the header.
const ARRIVE_IN: f64 = BASE_CONTACT_IN;
/// The end-centre bar.
const END_IN: f64 = 1.0;

fn query_of(call: &MoveCall) -> ReachQuery {
    let start = centroid(&call.model_pos);
    ReachQuery {
        start,
        target: add(start, call.delta),
        radius: call.opts.clearance,
        band: call.allowance(),
        cap_in: call.opts.difficult_cap_in.unwrap_or(0.0),
        mover: NO_OWNER,
        foe: NO_OWNER,
    }
}

#[derive(Default, Clone)]
struct Tally {
    n: usize,
    agree: usize,
    both_reach: usize,
    both_reach_end_ok: usize,
    agreed: usize,
    agreed_end_ok: usize,
    /// Tier 1 says yes, tier 2 says no — the OVER-REFUSAL, the failure mode the
    /// imagination actually suffers from today.
    refuse: usize,
    /// Tier 2 says yes, tier 1 says no.
    over: usize,
    ends: Vec<f64>,
    /// Where the disagreements sit.
    near_wall: usize,
    graze_wall: usize,
    in_difficult: usize,
    near_disc: usize,
    long_path: usize,
}

impl Tally {
    fn pct(a: usize, b: usize) -> f64 {
        if b == 0 {
            return 100.0;
        }
        100.0 * a as f64 / b as f64
    }
    fn line(&self, label: &str) -> String {
        let mut e = self.ends.clone();
        e.sort_by(|a, b| a.partial_cmp(b).unwrap());
        let med = if e.is_empty() { 0.0 } else { e[e.len() / 2] };
        let p90 = if e.is_empty() { 0.0 } else { e[(e.len() * 9 / 10).min(e.len() - 1)] };
        format!(
            "{label:<8} n={:<5} bool={:6.2}%  end<=1\" (both-reach)={:6.2}%  \
             end<=1\" (all agreed)={:6.2}%  med={:.2}\" p90={:.2}\"  refuse={} over={}",
            self.n,
            Tally::pct(self.agree, self.n),
            Tally::pct(self.both_reach_end_ok, self.both_reach),
            Tally::pct(self.agreed_end_ok, self.agreed),
            med,
            p90,
            self.refuse,
            self.over,
        )
    }
}

fn main() {
    let mut cell = REACH_CELL_IN;
    let mut cap = REACH_CAP;
    let mut pull = nml_core::mv::REACH_PULL_AHEAD;
    let mut bench = false;
    let mut why = false;
    let mut picks: Option<String> = None;
    let mut quiet = false;
    let mut paths: Vec<String> = Vec::new();
    for a in std::env::args().skip(1) {
        if let Some(v) = a.strip_prefix("--cell=") {
            cell = v.parse().expect("--cell");
        } else if let Some(v) = a.strip_prefix("--cap=") {
            cap = v.parse().expect("--cap");
        } else if let Some(v) = a.strip_prefix("--pull=") {
            pull = v.parse().expect("--pull");
        } else if let Some(v) = a.strip_prefix("--picks=") {
            picks = Some(v.to_string());
        } else if a == "--why" {
            why = true;
        } else if a == "--bench" {
            bench = true;
        } else if a == "--quiet" {
            quiet = true;
        } else if a.starts_with("--") {
            panic!("unknown flag {a}");
        } else {
            paths.push(a);
        }
    }
    if let Some(acts) = picks {
        picks_report(&acts);
        return;
    }
    if paths.is_empty() {
        paths.push(FIXTURE.to_string());
    }

    let mut calls: Vec<MoveCall> = Vec::new();
    for p in &paths {
        let c = load_moves(p).unwrap_or_else(|e| panic!("{e}"));
        c.header.constants.check().unwrap_or_else(|e| panic!("{p}: {e}"));
        calls.extend(c.calls);
    }
    println!("corpus {} file(s), {} calls, cell={cell}\" cap={cap} pull={pull}", paths.len(), calls.len());

    // The index is STATIC per call's obstacle set; build them all first so the
    // gate and the bench both run against a WARM index.
    let t0 = Instant::now();
    let index: Vec<ReachIndex> =
        calls.iter().map(|c| ReachIndex::from_move_call(c, cell, cap, pull)).collect();
    let build_us = t0.elapsed().as_secs_f64() * 1e6 / calls.len().max(1) as f64;
    let queries: Vec<ReachQuery> = calls.iter().map(query_of).collect();

    if bench {
        let repeats = 200usize;
        let t = Instant::now();
        let mut sink = 0.0f64;
        for _ in 0..repeats {
            for (ix, q) in index.iter().zip(&queries) {
                sink += ix.query(q).arc_in;
            }
        }
        let n = repeats * queries.len();
        let per = t.elapsed().as_secs_f64() * 1e9 / n as f64;
        // The memoised path, which is what the sim actually calls.
        index.iter().for_each(|ix| ix.clear_memo());
        let t = Instant::now();
        for _ in 0..repeats {
            for (ix, q) in index.iter().zip(&queries) {
                sink += ix.query_memo(q).arc_in;
            }
        }
        let per_memo = t.elapsed().as_secs_f64() * 1e9 / n as f64;
        let st = index.iter().fold((0u64, 0u64, 0u64, 0u64), |a, ix| {
            let s = ix.stats();
            (a.0 + s.queries, a.1 + s.memo_hits, a.2 + s.searches, a.3 + s.expansions)
        });
        println!(
            "BENCH  query {:.3} us   query_memo {:.3} us   index build {:.1} us/round \
             ({} cells)\n       {} queries, {} straight-line, {} searches, {} expansions ({:.1}/search), {} memo hits  [sink {sink:.3}]",
            per / 1000.0,
            per_memo / 1000.0,
            build_us,
            index.first().map(|i| i.cells()).unwrap_or(0),
            st.0,
            st.0 - st.1 - st.2,
            st.2,
            st.3,
            st.3 as f64 / st.2.max(1) as f64,
            st.1,
        );
        return;
    }

    if why {
        let mut buckets: std::collections::BTreeMap<String, (usize, usize)> =
            std::collections::BTreeMap::new();
        for (i, call) in calls.iter().enumerate() {
            let q = &queries[i];
            let exact = plan_unit_step(call);
            let exact_end = centroid(&exact.planned);
            let t1 = distance_to(exact_end, q.target) <= ARRIVE_IN;
            let t2 = index[i].query(q);
            let st0 = index[i].stats();
            let searched = st0.searches > 0;
            index[i].clear_memo();
            let mut why_bits = if searched { index[i].block_reason(q.start, q.target, q) } else { 0 };
            if searched
                && nml_core::mv::geom2::path_crosses_wall(q.start, q.target, &call.walls)
            {
                why_bits |= 32;
            }
            let arrived2 = distance_to(t2.end_centre, q.target) <= ARRIVE_IN;
            let k = format!(
                "t2={:<5} arrived2={:<5} route={:<8} block={:<3} cap={:<5} solve={:<5}",
                if t2.reachable { "yes" } else { "no" },
                arrived2,
                if searched { "search" } else { "straight" },
                why_bits,
                exact.cap.trimmed > 0,
                !exact.solve.passes.is_empty(),
            );
            let e = buckets.entry(k).or_default();
            e.0 += 1;
            if t1 != t2.reachable {
                e.1 += 1;
            }
        }
        for (k, v) in &buckets {
            println!("{k}  n={:<5} disagree={:<5} ({:.1}%)", v.0, v.1, 100.0 * v.1 as f64 / v.0 as f64);
        }
        return;
    }

    let mut all = Tally::default();
    let mut charges = Tally::default();
    let mut worst: Vec<(f64, String)> = Vec::new();
    // The BASELINE the imagination runs today: a straight line, full delta, no
    // obstacle of any kind — end centre = the target. Tier 2 only earns its
    // place if its end centre is closer to tier 1's than that.
    let mut base_err: Vec<f64> = Vec::new();
    let mut t2_err: Vec<f64> = Vec::new();
    for (i, call) in calls.iter().enumerate() {
        let q = &queries[i];
        let exact = plan_unit_step(call);
        let exact_end = centroid(&exact.planned);
        let t1 = distance_to(exact_end, q.target) <= ARRIVE_IN;
        let t2 = index[i].query(q);
        let d_end = distance_to(t2.end_centre, exact_end);
        base_err.push(distance_to(q.target, exact_end));
        t2_err.push(d_end);
        let push = |t: &mut Tally| {
            t.n += 1;
            if t1 == t2.reachable {
                t.agree += 1;
                t.agreed += 1;
                t.ends.push(d_end);
                if d_end <= END_IN {
                    t.agreed_end_ok += 1;
                }
                if t1 {
                    t.both_reach += 1;
                    if d_end <= END_IN {
                        t.both_reach_end_ok += 1;
                    }
                }
            } else if t1 {
                t.refuse += 1;
            } else {
                t.over += 1;
            }
        };
        push(&mut all);
        if call.allow_contact {
            push(&mut charges);
        }
        if t1 != t2.reachable {
            let bits = index[i].block_reason(q.start, q.target, q);
            let crossing = nml_core::mv::geom2::path_crosses_wall(q.start, q.target, &call.walls);
            if bits & 2 != 0 {
                if crossing {
                    all.near_wall += 1;
                } else {
                    all.graze_wall += 1;
                }
            }
            if bits & 1 != 0 {
                all.in_difficult += 1;
            }
            if bits & 4 != 0 {
                all.near_disc += 1;
            }
            if bits == 0 {
                all.long_path += 1;
            }
            worst.push((
                d_end,
                format!(
                    "  {} r{} act{} band={:.2} t1={} t2={} d_end={:.2} block={} cross={} solve={}",
                    call.unit, call.round, call.act, q.band, t1, t2.reachable, d_end, bits,
                    crossing, !exact.solve.passes.is_empty()
                ),
            ));
        }
    }

    let pctl = |v: &mut Vec<f64>, f: f64| {
        v.sort_by(|a, b| a.partial_cmp(b).unwrap());
        v[(((v.len() - 1) as f64) * f) as usize]
    };
    println!("{}", all.line("ALL"));
    println!("{}", charges.line("CHARGE"));
    println!(
        "END CENTRE vs tier 1, ALL {} calls:  tier 2  p50={:.2}\" p90={:.2}\" mean={:.2}\"   \
         straight-line baseline  p50={:.2}\" p90={:.2}\" mean={:.2}\"",
        all.n,
        pctl(&mut t2_err, 0.50),
        pctl(&mut t2_err, 0.90),
        t2_err.iter().sum::<f64>() / all.n as f64,
        pctl(&mut base_err, 0.50),
        pctl(&mut base_err, 0.90),
        base_err.iter().sum::<f64>() / all.n as f64,
    );
    println!(
        "disagreement profile ({} calls): wall CROSSING {} | wall clearance graze {} | hard terrain {} | unit disc {} | nothing blocked (tier 1 fell short) {}",
        all.refuse + all.over,
        all.near_wall,
        all.graze_wall,
        all.in_difficult,
        all.near_disc,
        all.long_path
    );
    let green =
        Tally::pct(all.agree, all.n) >= 97.0 && Tally::pct(all.agreed_end_ok, all.agreed) >= 90.0;
    println!(
        "GATE G7: {} (bar: bool >= 97.00 %, end <= 1\" >= 90.00 % of agreed)",
        if green { "GREEN" } else { "RED" }
    );
    if !quiet {
        worst.sort_by(|a, b| b.0.partial_cmp(&a.0).unwrap());
        for (_, s) in worst.iter().take(10) {
            println!("{s}");
        }
    }
}


/// GATE (c), the INFORMATION half: how many recorded activations change their
/// pick when `NML_SIM_PATH` is ON. Never a pass/fail — this is the number the
/// fleet A/B is there to judge.
fn picks_report(acts_path: &str) {
    use nml_core::plan::plan_with_rollout;
    use nml_core::{build_act_statics, load_acts};
    const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
    let c = load_acts(acts_path).unwrap_or_else(|e| panic!("{e}"));
    let statics = build_act_statics(&c, REPO);
    let mut off_k = c.knobs;
    off_k.seam_path = false;
    let mut on_k = c.knobs;
    on_k.seam_path = true;
    let (mut n, mut same, mut moved, mut declined) = (0, 0, 0, 0);
    let mut lines: Vec<String> = Vec::new();
    for (ai, act) in c.acts.iter().enumerate() {
        n += 1;
        let a = plan_with_rollout(&act.state, &c.terrain, &statics, &off_k, &act.statics, act.player);
        let b = plan_with_rollout(&act.state, &c.terrain, &statics, &on_k, &act.statics, act.player);
        match (a, b) {
            (Ok(a), Ok(b)) => {
                let ka = (a.unit_key.clone(), a.action.kind, a.action.dest);
                let kb = (b.unit_key.clone(), b.action.kind, b.action.dest);
                if ka == kb {
                    same += 1;
                } else {
                    moved += 1;
                    lines.push(format!(
                        "  act {ai} R{} p{}: {} kind {} -> {} kind {}",
                        act.round, act.player, ka.0, ka.1, kb.0, kb.1
                    ));
                }
            }
            _ => declined += 1,
        }
    }
    println!("PICKS with NML_SIM_PATH: {n} activations, {same} unchanged, {moved} changed, {declined} declined");
    for l in lines.iter().take(10) {
        println!("{l}");
    }
}
