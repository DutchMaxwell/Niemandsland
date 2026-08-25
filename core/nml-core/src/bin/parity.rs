//! Gate for NML-1073 M1-1: replay a recorded node corpus and compare
//! `nml_core::score(state_after, player)` against the score the GDScript
//! planner wrote for that same node.
//!
//! Usage: `cargo run --release --bin parity -- <nodes.jsonl>`

use std::time::Instant;

use nml_core::{load_nodes, score, NO_INCOMING};

fn main() {
    let path = std::env::args().nth(1).unwrap_or_else(|| {
        eprintln!("usage: parity <nodes.jsonl>");
        std::process::exit(2);
    });
    let corpus = match load_nodes(&path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("load failed: {e}");
            std::process::exit(2);
        }
    };
    let n = corpus.nodes.len();
    let mut within_9 = 0usize;
    let mut within_6 = 0usize;
    let mut max_abs = 0.0f64;
    let mut max_abs_matching = 0.0f64;
    let mut first: Vec<(usize, i64, f64, f64)> = Vec::new();
    // per player: (total, within 1e-9)
    let mut by_player: Vec<(i64, usize, usize)> = Vec::new();

    for (i, node) in corpus.nodes.iter().enumerate() {
        let got = score(&node.state_after, node.player, NO_INCOMING);
        let diff = (got - node.score).abs();
        if diff > max_abs {
            max_abs = diff;
        }
        if diff <= 1e-9 {
            within_9 += 1;
            if diff > max_abs_matching {
                max_abs_matching = diff;
            }
        } else if first.len() < 5 {
            first.push((i + 1, node.player, got, node.score));
        }
        if diff <= 1e-6 {
            within_6 += 1;
        }
        match by_player.iter_mut().find(|e| e.0 == node.player) {
            Some(e) => {
                e.1 += 1;
                if diff <= 1e-9 {
                    e.2 += 1;
                }
            }
            None => by_player.push((node.player, 1, usize::from(diff <= 1e-9))),
        }
    }
    by_player.sort_by_key(|e| e.0);

    println!("nodes            {n}");
    println!("within 1e-9      {within_9}/{n}");
    println!("within 1e-6      {within_6}/{n}");
    println!("max abs diff     {max_abs:.17e}");
    println!("max abs diff (matching nodes only) {max_abs_matching:.17e}");
    for (p, tot, ok) in &by_player {
        println!("player {p}         {ok}/{tot} within 1e-9");
    }
    if first.is_empty() {
        println!("mismatches       none");
    } else {
        println!("first mismatches (node, player, rust, recorded):");
        for (idx, p, got, rec) in &first {
            println!("  #{idx} player={p} rust={got:.17} recorded={rec:.17} diff={:.3e}", got - rec);
        }
    }

    // Timing, information only — the real benchmark is M1-4 (clone+resolve+score).
    let mut best = f64::INFINITY;
    let mut sink = 0.0f64;
    for _ in 0..5 {
        let t0 = Instant::now();
        for node in &corpus.nodes {
            sink += score(&node.state_after, node.player, NO_INCOMING);
        }
        let ns = t0.elapsed().as_nanos() as f64 / n as f64;
        if ns < best {
            best = ns;
        }
    }
    println!("score() timing   {best:.0} ns/call (best of 5 passes over {n} nodes)");
    if sink.is_nan() {
        std::process::exit(3);
    }
}
