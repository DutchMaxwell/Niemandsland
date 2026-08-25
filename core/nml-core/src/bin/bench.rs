//! NML-1073 M1-4 — the PROBE BENCHMARK behind gate KERN-P.
//!
//! The unit of comparison is ONE ROLLOUT NODE, exactly what
//! `AiPlanner._policy_step` (ai_planner.gd:462-467) costs per candidate:
//!
//! ```text
//! next     = BattleSim.resolve(state, action)          // clone_state is INSIDE resolve
//! incoming = BattleSim.reply_threat(next, player)      // rich leaf only
//! s        = AiMissionEval.score(next, player, incoming)
//! ```
//!
//! Nothing here tunes anything: the crate is used exactly as the parity binary
//! uses it, on the same recorded corpus. The GDScript side (`tools/node_bench.gd`)
//! replays the SAME nodes through the real engine.
//!
//! MEASUREMENT NOTES, stated rather than hidden:
//! * `resolve()` takes the recorded terrain answer (`cover_dest`) instead of
//!   calling the `terrain_at` Callable, and reads line of sight off the recorded
//!   `los_pairs` matrix instead of calling `los_blocked`. The GDScript bench is
//!   therefore given the SAME recorded LOS answers (as each unit's `los` dict,
//!   which `sees()` reads before `_los_clear`) and also has no terrain Callable —
//!   so both sides take the same branches. Neither side pays the terrain/LOS
//!   Callable the real trainer pays; the factor is measured on the rest.
//! * `reply_threat` is priced on the state `resolve` produced, whose `los_pairs`
//!   is the PARENT's matrix (stale by one move). The GDScript bench gets the same
//!   parent matrix, so the two sides gate the same pairs.
//!
//! Usage:
//!   cargo run --release --bin bench -- <nodes.jsonl> [repo_root]
//!       [--passes N] [--exclude <file>] [--out-exclude <file>] [--out <file>]

use std::hint::black_box;
use std::time::Instant;

use nml_core::{build_statics, load_nodes, reply_threat, resolve, score};

fn pct(sorted: &[f64], p: f64) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    let i = ((sorted.len() as f64 - 1.0) * p).round() as usize;
    sorted[i]
}

fn median(sorted: &[f64]) -> f64 {
    if sorted.is_empty() {
        return 0.0;
    }
    let n = sorted.len();
    if n % 2 == 1 {
        sorted[n / 2]
    } else {
        0.5 * (sorted[n / 2 - 1] + sorted[n / 2])
    }
}

fn main() {
    let mut argv = std::env::args().skip(1);
    let mut path = String::new();
    let mut repo_root = format!("{}/../..", env!("CARGO_MANIFEST_DIR"));
    let mut passes = 7usize;
    let mut exclude_path = String::new();
    let mut out_exclude = String::new();
    let mut out_path = String::new();
    let mut positional = 0;
    while let Some(a) = argv.next() {
        match a.as_str() {
            "--passes" => passes = argv.next().and_then(|v| v.parse().ok()).unwrap_or(7),
            "--exclude" => exclude_path = argv.next().unwrap_or_default(),
            "--out-exclude" => out_exclude = argv.next().unwrap_or_default(),
            "--out" => out_path = argv.next().unwrap_or_default(),
            _ => {
                if positional == 0 {
                    path = a;
                } else if positional == 1 {
                    repo_root = a;
                }
                positional += 1;
            }
        }
    }
    if path.is_empty() {
        eprintln!("usage: bench <nodes.jsonl> [repo_root] [--passes N] [--exclude f] [--out-exclude f] [--out f]");
        std::process::exit(2);
    }

    let corpus = match load_nodes(&path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("load failed: {e}");
            std::process::exit(2);
        }
    };
    let statics = build_statics(&corpus, &repo_root);
    let n_all = corpus.nodes.len();

    // ---- the excluded node set (1-based indices, the corpus line order) ----
    let mut excluded = vec![false; n_all];
    let mut n_ext = 0usize;
    if !exclude_path.is_empty() {
        match std::fs::read_to_string(&exclude_path) {
            Ok(t) => {
                for tok in t.split_whitespace() {
                    if let Ok(i) = tok.parse::<usize>() {
                        if i >= 1 && i <= n_all && !excluded[i - 1] {
                            excluded[i - 1] = true;
                            n_ext += 1;
                        }
                    }
                }
            }
            Err(e) => {
                eprintln!("exclude file {exclude_path}: {e}");
                std::process::exit(2);
            }
        }
    }
    // Nodes this port cannot resolve are excluded on BOTH sides.
    let mut n_rust_err = 0usize;
    for i in 0..n_all {
        if excluded[i] {
            continue;
        }
        let node = &corpus.nodes[i];
        if resolve(
            &statics,
            &node.state_before,
            &node.action,
            node.cover_dest,
            corpus.seams,
            node.cast_los(),
        )
        .is_err()
        {
            excluded[i] = true;
            n_rust_err += 1;
        }
    }
    let idx: Vec<usize> = (0..n_all).filter(|&i| !excluded[i]).collect();
    let n = idx.len();
    if !out_exclude.is_empty() {
        let lines: Vec<String> = (0..n_all)
            .filter(|&i| excluded[i])
            .map(|i| (i + 1).to_string())
            .collect();
        let _ = std::fs::write(&out_exclude, lines.join("\n"));
    }

    // ---- instrument cost: two Instant::now() around nothing ----
    let mut clock_ns = f64::INFINITY;
    for _ in 0..5 {
        let mut acc = 0.0f64;
        for _ in 0..n.max(1) {
            let t0 = Instant::now();
            let d = t0.elapsed();
            acc += d.as_nanos() as f64;
        }
        clock_ns = clock_ns.min(acc / n.max(1) as f64);
    }

    // ---- the whole-node passes ----
    let mut sink = 0.0f64;
    let mut pass_mean: Vec<f64> = Vec::new();
    let mut best_pass: Vec<f64> = Vec::new();
    let mut best_mean = f64::INFINITY;
    for _ in 0..passes {
        let mut per_node: Vec<f64> = Vec::with_capacity(n);
        let t_pass = Instant::now();
        for &i in &idx {
            let node = &corpus.nodes[i];
            let t0 = Instant::now();
            let next = resolve(
                &statics,
                &node.state_before,
                &node.action,
                node.cover_dest,
                corpus.seams,
                node.cast_los(),
            )
            .expect("excluded above");
            let incoming = if node.rich {
                reply_threat(&statics, &next, node.player)
            } else {
                Vec::new()
            };
            let s = score(&next, node.player, &incoming);
            let dt = t0.elapsed().as_nanos() as f64;
            sink += black_box(s);
            per_node.push(dt);
        }
        let wall = t_pass.elapsed().as_nanos() as f64;
        let mean = wall / n as f64;
        pass_mean.push(mean);
        let inst_mean: f64 = per_node.iter().sum::<f64>() / n as f64;
        if inst_mean < best_mean {
            best_mean = inst_mean;
            best_pass = per_node;
        }
    }
    best_pass.sort_by(|a, b| a.partial_cmp(b).unwrap());

    // ---- breakdown: clone / resolve / reply_threat / score, best of `passes` ----
    let mut t_clone = f64::INFINITY;
    let mut t_resolve = f64::INFINITY;
    let mut t_threat = f64::INFINITY;
    let mut t_score = f64::INFINITY;
    let rich: Vec<usize> = idx.iter().copied().filter(|&i| corpus.nodes[i].rich).collect();
    let mut nexts: Vec<_> = Vec::with_capacity(n);
    for &i in &idx {
        let node = &corpus.nodes[i];
        nexts.push(
            resolve(
                &statics,
                &node.state_before,
                &node.action,
                node.cover_dest,
                corpus.seams,
                node.cast_los(),
            )
            .expect("excluded above"),
        );
    }
    let incomings: Vec<Vec<f64>> = idx
        .iter()
        .enumerate()
        .map(|(k, &i)| {
            if corpus.nodes[i].rich {
                reply_threat(&statics, &nexts[k], corpus.nodes[i].player)
            } else {
                Vec::new()
            }
        })
        .collect();
    let mut sink2 = 0usize;
    for _ in 0..passes {
        let t0 = Instant::now();
        for &i in &idx {
            sink2 += black_box(corpus.nodes[i].state_before.clone()).alive.len();
        }
        t_clone = t_clone.min(t0.elapsed().as_nanos() as f64 / n as f64);

        let t0 = Instant::now();
        for &i in &idx {
            let node = &corpus.nodes[i];
            sink2 += black_box(
                resolve(
                    &statics,
                    &node.state_before,
                    &node.action,
                    node.cover_dest,
                    corpus.seams,
                    node.cast_los(),
                )
                .unwrap(),
            )
            .alive
            .len();
        }
        t_resolve = t_resolve.min(t0.elapsed().as_nanos() as f64 / n as f64);

        if !rich.is_empty() {
            let t0 = Instant::now();
            for (k, &i) in idx.iter().enumerate() {
                if corpus.nodes[i].rich {
                    sink2 += black_box(reply_threat(&statics, &nexts[k], corpus.nodes[i].player)).len();
                }
            }
            // per NODE (not per rich node), so the parts add up to the whole
            t_threat = t_threat.min(t0.elapsed().as_nanos() as f64 / n as f64);
        }

        let t0 = Instant::now();
        for (k, &i) in idx.iter().enumerate() {
            sink += black_box(score(&nexts[k], corpus.nodes[i].player, &incomings[k]));
        }
        t_score = t_score.min(t0.elapsed().as_nanos() as f64 / n as f64);
    }
    if sink2 == usize::MAX {
        std::process::exit(3);
    }

    // ---- fairness counter: how often the cast sub-phase actually fired ----
    let mut cast_nodes = 0usize;
    let mut cast_ids: Vec<usize> = Vec::new();
    for (k, &i) in idx.iter().enumerate() {
        // The port does not keep `cast_events` (outside the M1-3 parity
        // contract), so the firing signal is the TOKEN SPEND — the same one the
        // GDScript bench counts (battle_sim.gd:893 `su["casts"] = tokens - cost`).
        let node = &corpus.nodes[i];
        if let Some(&si) = node.state_before.roster.index.get(node.action.unit.as_str()) {
            if nexts[k].casts[si] != node.state_before.casts[si] {
                cast_nodes += 1;
                cast_ids.push(i + 1);
            }
        }
    }

    // ---- fairness counter: how many volley pairs pass the LOS gate ----
    // (the GDScript bench prints the same number; if they differ, the two sides
    // are not doing the same work and the factor is not a factor)
    let mut threat_pairs = 0usize;
    for (k, &i) in idx.iter().enumerate() {
        let node = &corpus.nodes[i];
        if !node.rich {
            continue;
        }
        let s = &nexts[k];
        let un = s.units();
        for e in 0..un {
            if s.player[e] == node.player || s.alive[e] <= 0 {
                continue;
            }
            for m in 0..un {
                if s.player[m] != node.player || s.alive[m] <= 0 {
                    continue;
                }
                let ok = match &s.los_pairs {
                    None => true,
                    Some(mm) => mm[e * un + m],
                };
                if s.sees(e, s.key(m)) && ok {
                    threat_pairs += 1;
                }
            }
        }
    }

    let mut out = String::new();
    macro_rules! p {
        ($($t:tt)*) => {{ let s = format!($($t)*); println!("{s}"); out.push_str(&s); out.push('\n'); }};
    }
    p!("corpus            {path}");
    p!("seams             spacing={} cast={}", corpus.seams.spacing, corpus.seams.cast);
    p!("nodes in corpus   {n_all}");
    p!("excluded          {} (file {n_ext}, rust-unresolvable {n_rust_err})", n_all - n);
    p!("nodes measured    {n}");
    p!("rich nodes        {} (score prices the reply threat)", rich.len());
    p!("clock overhead    {clock_ns:.0} ns per Instant::now() pair (included in every per-node time)");
    p!("passes            {passes}");
    for (k, m) in pass_mean.iter().enumerate() {
        p!("  pass {:>2} mean    {m:.0} ns/node (wall/n)", k + 1);
    }
    p!("BEST PASS  mean   {best_mean:.0} ns/node");
    p!("BEST PASS  MEDIAN {:.0} ns/node", median(&best_pass));
    p!("BEST PASS  p90    {:.0} ns/node", pct(&best_pass, 0.90));
    p!("BEST PASS  p99    {:.0} ns/node", pct(&best_pass, 0.99));
    p!("BEST PASS  max    {:.0} ns/node", best_pass.last().copied().unwrap_or(0.0));
    p!("BEST PASS  min    {:.0} ns/node", best_pass.first().copied().unwrap_or(0.0));
    p!("breakdown (best of {passes} whole-corpus passes, ns per MEASURED node):");
    p!("  clone_state         {t_clone:.0}");
    p!("  resolve (incl clone){t_resolve:.0}   -> resolve minus clone {:.0}", t_resolve - t_clone);
    p!("  reply_threat        {t_threat:.0}   (rich nodes only, amortised over all)");
    p!("  score               {t_score:.0}");
    p!("  sum of parts        {:.0}", t_resolve + t_threat + t_score);
    p!("cast sub-phase    fired on {cast_nodes}/{n} nodes");
    p!("LOS-gate check    reply_threat volley pairs that pass sees()+los_clear: {threat_pairs}");
    if sink == f64::MAX {
        std::process::exit(3);
    }
    if !out_path.is_empty() {
        let _ = std::fs::write(&out_path, out);
        let ids: Vec<String> = cast_ids.iter().map(|i| i.to_string()).collect();
        let _ = std::fs::write(format!("{out_path}.castids"), ids.join("\n"));
    }
}
