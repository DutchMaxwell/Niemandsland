//! `mvbench [moves.jsonl] [repeats]` — what the movement planner's LEAF layer
//! costs in Rust.
//!
//! `step_blocked` and `_segment_cost` are what `_theta_star_b` evaluates per
//! edge: 8 neighbours per expansion, up to `fast_planner_guard` = 320
//! expansions per per-model search, plus the string pull and the walk. The M4
//! recon put the GDScript at ~300k predicate evaluations per `plan_unit_step`
//! and ~10 ns per evaluation as the Rust target, so this is the number the port
//! is judged on.
//!
//! Every accepted edge in the corpus's trace is replayed against the same zone
//! set the G1 gate uses (the base zones after the `fast_planner` cull, without
//! the per-model body discs), so the wall count (48) and the disc count are the
//! shipped ones.

use std::hint::black_box;
use std::time::Instant;

use nml_core::mv::cost::{segment_cost, step_blocked, CellSet, StepOpts, Zone};
use nml_core::mv::geom2::{distance_squared_to, length, V2};
use nml_core::mv::{load_moves, PLAN_CELL_IN};

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().unwrap_or_else(|| {
        concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/moves_s27.jsonl").to_string()
    });
    let repeats: usize = args.next().and_then(|s| s.parse().ok()).unwrap_or(200);
    let c = load_moves(&path).unwrap_or_else(|e| panic!("{e}"));

    let empty = CellSet::new();
    let mut edges: Vec<(usize, V2, V2)> = Vec::new();
    let mut zones_of: Vec<Vec<Zone>> = Vec::new();
    for (ci, call) in c.calls.iter().enumerate() {
        let mut z = call.opts.zones.clone();
        if c.header.fast_planner && z.len() > 8 {
            let reach = length(call.delta).max(call.opts.charge_allowance.unwrap_or(0.0))
                + call.opts.clearance
                + PLAN_CELL_IN;
            z.retain(|zz| {
                let r2 = (reach + zz.r).powf(2.0);
                call.model_pos.iter().any(|m| distance_squared_to(*m, zz.c) <= r2)
            });
        }
        zones_of.push(z);
        for f in &call.trace.flow {
            if f.theta.len() < 3 {
                continue;
            }
            for w in f.theta.windows(2) {
                edges.push((ci, w[0], w[1]));
            }
        }
    }

    let walls_n = c.header.walls.len();
    let discs: f64 =
        zones_of.iter().map(|z| z.len() as f64).sum::<f64>() / zones_of.len().max(1) as f64;

    let t = Instant::now();
    let mut hits = 0usize;
    for _ in 0..repeats {
        for (ci, a, b) in &edges {
            let call = &c.calls[*ci];
            let o = StepOpts {
                clearance: call.opts.clearance,
                zones: &zones_of[*ci],
                avoid_cells: &call.opts.avoid_cells,
                avoid_fine: &empty,
            };
            if black_box(step_blocked(*a, *b, &call.walls, &o)) {
                hits += 1;
            }
        }
    }
    let sb = t.elapsed().as_secs_f64() / (repeats * edges.len()) as f64;

    let t = Instant::now();
    let mut acc = 0.0f64;
    for _ in 0..repeats {
        for (ci, a, b) in &edges {
            let call = &c.calls[*ci];
            let o = StepOpts {
                clearance: call.opts.clearance,
                zones: &zones_of[*ci],
                avoid_cells: &call.opts.avoid_cells,
                avoid_fine: &empty,
            };
            acc += black_box(segment_cost(*a, *b, &call.grid, &o));
        }
    }
    let sc = t.elapsed().as_secs_f64() / (repeats * edges.len()) as f64;

    println!("corpus       {} calls, {} accepted edges, {repeats} repeats", c.calls.len(), edges.len());
    println!("shape        {walls_n} walls, {discs:.1} zone discs per call (after the cull)");
    println!("step_blocked {:8.1} ns/call   ({hits} blocked)", sb * 1e9);
    println!("segment_cost {:8.1} ns/call   (sum {acc:.3})", sc * 1e9);
    println!(
        "theta budget {:8.3} ms  = 320 expansions x 8 neighbours x (step_blocked + segment_cost)",
        320.0 * 8.0 * (sb + sc) * 1e3
    );
}
