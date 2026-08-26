//! `menubench <acts.jsonl> [--diff]` — the cost and the diff of the candidate
//! menu on a recorded ACT corpus.
//!
//! Default: builds every pool unit's menu N times and reports nanoseconds per
//! `candidates()` call. With `--diff`: prints every candidate that differs from
//! the recorded `trace.menus`, which is what a red proof needs to be COUNTED
//! rather than merely observed to fail.

use std::time::Instant;

use nml_core::menu::{candidates_in, Candidate};
use nml_core::sim::Scratch;
use nml_core::{build_act_statics, load_acts};

const REPO: &str = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
const ROUNDS: usize = 200;

fn dest_s(c: &Candidate) -> String {
    match &c.dest {
        None => "-".to_string(),
        Some(d) => format!("[{:.9}, {:.9}, {:.9}]", d[0], d[1], d[2]),
    }
}

fn line(c: &Candidate) -> String {
    format!(
        "kind={} dest={} shoot={:?} charge={:?} patient={} wave={:?}",
        c.kind,
        dest_s(c),
        c.shoot,
        c.charge,
        c.patient,
        c.wave
    )
}

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().unwrap_or_else(|| {
        concat!(env!("CARGO_MANIFEST_DIR"), "/tests/fixtures/acts_25.jsonl").to_string()
    });
    let diff = args.any(|a| a == "--diff");
    let c = load_acts(&path).unwrap_or_else(|e| panic!("{e}"));
    let statics = build_act_statics(&c, REPO);
    let mut sc = Scratch::default();

    if diff {
        let (mut n, mut bad) = (0usize, 0usize);
        for (ai, act) in c.acts.iter().enumerate() {
            for key in &act.pool {
                let i = act.state.roster.index[key.as_str()];
                let got = candidates_in(&act.state, &c.terrain, &statics, i, &mut sc);
                let want = &act.menus[key];
                if got.len() != want.len() {
                    println!("act {ai} {key}: LENGTH {} != {}", got.len(), want.len());
                    for (k, g) in got.iter().enumerate() {
                        println!("   got [{k}] {}", line(g));
                    }
                    for (k, w) in want.iter().enumerate() {
                        println!("  want [{k}] {}", line(w));
                    }
                    bad += want.len().max(got.len());
                    n += want.len();
                    continue;
                }
                n += want.len();
                for (k, (g, w)) in got.iter().zip(want).enumerate() {
                    let same = g.kind == w.kind
                        && g.shoot == w.shoot
                        && g.charge == w.charge
                        && g.patient == w.patient
                        && g.wave == w.wave
                        && match (&g.dest, &w.dest) {
                            (None, None) => true,
                            (Some(a), Some(b)) => {
                                (0..3).all(|z| (a[z] - b[z]).abs() <= 1e-9)
                            }
                            _ => false,
                        };
                    if !same {
                        bad += 1;
                        println!("act {ai} {key} [{k}]");
                        println!("   got {}", line(g));
                        println!("  want {}", line(w));
                    }
                }
            }
        }
        println!("--- {} of {} candidates differ", bad, n);
        return;
    }

    let mut calls = 0usize;
    let mut sink = 0usize;
    let t0 = Instant::now();
    for _ in 0..ROUNDS {
        for act in &c.acts {
            for key in &act.pool {
                let i = act.state.roster.index[key.as_str()];
                sink += candidates_in(&act.state, &c.terrain, &statics, i, &mut sc).len();
                calls += 1;
            }
        }
    }
    let ns = t0.elapsed().as_nanos() as f64 / calls as f64;
    println!("{calls} candidates() calls, {ns:.0} ns/call (checksum {sink})");
}
