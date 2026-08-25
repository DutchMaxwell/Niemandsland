//! The NML-1073 M1-2 gates, replayed over a recorded node corpus.
//!
//! GATE A — score parity: `score(state_after, player, reply_threat(state_after,
//! player))` must equal the score the GDScript planner wrote for that node,
//! within 1e-9, on EVERY node. The threat is computed in Rust; nothing about it
//! is read from the corpus.
//!
//! GATE B — resolve parity: for every HOLD and ADVANCE node,
//! `resolve(state_before, action)` must reproduce `state_after` field by field
//! (positions/wounds/radii/wound_frac within 1e-9, ints and bools exact).
//!
//! Usage: `cargo run --release --bin parity -- <nodes.jsonl> [repo_root]`

use std::collections::BTreeMap;
use std::time::Instant;

use nml_core::sim::Unsupported;
use nml_core::{build_statics, load_nodes, reply_threat, resolve, score, State};

const EPS: f64 = 1e-9;

fn kind_name(k: i64) -> &'static str {
    match k {
        0 => "HOLD",
        1 => "ADVANCE",
        2 => "RUSH",
        3 => "CHARGE",
        4 => "KITE",
        _ => "?",
    }
}

/// Field-by-field comparison of a resolved state against the recorded one.
/// Returns the names of every field that differs, most specific first.
fn diff_states(got: &State, want: &State) -> Vec<String> {
    let mut out = Vec::new();
    if got.units() != want.units() {
        out.push("unit count".into());
        return out;
    }
    if got.round != want.round {
        out.push("round".into());
    }
    if got.rounds_total != want.rounds_total {
        out.push("rounds_total".into());
    }
    if got.objectives.len() != want.objectives.len() {
        out.push("objectives.len".into());
    } else {
        for (a, b) in got.objectives.iter().zip(&want.objectives) {
            if a.owner != b.owner || a.pos.iter().zip(&b.pos).any(|(x, y)| (x - y).abs() > EPS) {
                out.push("objectives".into());
                break;
            }
        }
    }
    macro_rules! cmp_int {
        ($f:ident) => {
            if got.$f != want.$f {
                out.push(stringify!($f).into());
            }
        };
    }
    cmp_int!(player);
    cmp_int!(alive);
    cmp_int!(activated);
    cmp_int!(shaken);
    cmp_int!(fatigued);
    cmp_int!(in_cover);
    cmp_int!(aircraft);
    cmp_int!(dormant);
    cmp_int!(casts);
    cmp_int!(morale_bonus);
    cmp_int!(ambush_arrived_round);
    cmp_int!(earliest_arrival_round);
    cmp_int!(wounds);
    for i in 0..got.units() {
        if (got.wound_frac[i] - want.wound_frac[i]).abs() > EPS {
            out.push("wound_frac".into());
            break;
        }
    }
    'pos: for i in 0..got.units() {
        if got.positions[i].len() != want.positions[i].len() {
            out.push("positions.len".into());
            break;
        }
        for (a, b) in got.positions[i].iter().zip(&want.positions[i]) {
            for k in 0..3 {
                if (a[k] - b[k]).abs() > EPS {
                    out.push("positions".into());
                    break 'pos;
                }
            }
        }
    }
    'rad: for i in 0..got.units() {
        if got.radii[i].len() != want.radii[i].len() {
            out.push("radii.len".into());
            break;
        }
        for (a, b) in got.radii[i].iter().zip(&want.radii[i]) {
            if (a - b).abs() > EPS {
                out.push("radii".into());
                break 'rad;
            }
        }
    }
    for i in 0..got.units() {
        let (a, b) = (&got.mods[i], &want.mods[i]);
        if a.hit != b.hit
            || a.def != b.def
            || a.morale != b.morale
            || (a.range_in - b.range_in).abs() > EPS
            || (a.advance - b.advance).abs() > EPS
            || (a.rush - b.rush).abs() > EPS
        {
            out.push("mods".into());
            break;
        }
    }
    out
}

fn main() {
    let mut args = std::env::args().skip(1);
    let path = args.next().unwrap_or_else(|| {
        eprintln!("usage: parity <nodes.jsonl> [repo_root]");
        std::process::exit(2);
    });
    // Default: the repo this crate lives in (core/nml-core -> ../..).
    let repo_root = args.next().unwrap_or_else(|| {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    });

    let corpus = match load_nodes(&path) {
        Ok(c) => c,
        Err(e) => {
            eprintln!("load failed: {e}");
            std::process::exit(2);
        }
    };
    let statics = build_statics(&corpus, &repo_root);
    let n = corpus.nodes.len();

    // ---------------- GATE A ----------------
    let mut within_9 = 0usize;
    let mut max_abs = 0.0f64;
    let mut by_leaf: BTreeMap<&'static str, (usize, usize)> = BTreeMap::new();
    let mut worst: Vec<(usize, i64, f64, f64)> = Vec::new();
    for (i, node) in corpus.nodes.iter().enumerate() {
        // The RICH leaf prices with the reply threat, the CHEAP one without —
        // ai_planner.gd:508-510. The recorder stamps which one ran.
        let incoming = if node.rich {
            reply_threat(&statics, &node.state_after, node.player)
        } else {
            Vec::new()
        };
        let got = score(&node.state_after, node.player, &incoming);
        let diff = (got - node.score).abs();
        max_abs = max_abs.max(diff);
        let e = by_leaf
            .entry(if node.rich { "rich " } else { "cheap" })
            .or_insert((0, 0));
        e.0 += 1;
        if diff <= EPS {
            within_9 += 1;
            e.1 += 1;
        } else if worst.len() < 5 {
            worst.push((i + 1, node.player, got, node.score));
        }
    }
    println!("=== GATE A — score parity (incoming = reply_threat, computed in Rust) ===");
    println!("nodes                {n}");
    println!("within 1e-9          {within_9}/{n}");
    println!("max abs diff         {max_abs:.17e}");
    for (leaf, (tot, ok)) in &by_leaf {
        println!("  {leaf} leaf           {ok}/{tot}");
    }
    for (idx, p, got, rec) in &worst {
        println!("  MISS #{idx} player={p} rust={got:.17} recorded={rec:.17}");
    }
    // Red-green in the open: a threat that is always zero would pass GATE A
    // for free, so count the rich nodes that BREAK when it is dropped.
    let (mut rich_n, mut rich_breaks) = (0usize, 0usize);
    for node in corpus.nodes.iter().filter(|n| n.rich) {
        rich_n += 1;
        if (score(&node.state_after, node.player, &[]) - node.score).abs() > EPS {
            rich_breaks += 1;
        }
    }
    println!("  threat is load-bearing: {rich_breaks}/{rich_n} rich nodes redden without it");

    // ---------------- GATE B ----------------
    let mut per_kind: BTreeMap<i64, (usize, usize)> = BTreeMap::new(); // total, exact
    let mut fields: BTreeMap<String, usize> = BTreeMap::new();
    let mut unsupported: BTreeMap<String, usize> = BTreeMap::new();
    let mut first_bad: Vec<(usize, i64, Vec<String>)> = Vec::new();
    for (i, node) in corpus.nodes.iter().enumerate() {
        match resolve(&statics, &node.state_before, &node.action, node.cover_dest) {
            Ok(got) => {
                let e = per_kind.entry(node.action.kind).or_insert((0, 0));
                e.0 += 1;
                let d = diff_states(&got, &node.state_after);
                if d.is_empty() {
                    e.1 += 1;
                } else {
                    for f in &d {
                        *fields.entry(f.clone()).or_insert(0) += 1;
                    }
                    if first_bad.len() < 5 {
                        first_bad.push((i + 1, node.action.kind, d));
                    }
                }
            }
            Err(u) => {
                let label = match u {
                    Unsupported::ActionKind(k) => {
                        format!("action kind {k} ({}) — plan step M1-3", kind_name(k))
                    }
                    Unsupported::UnknownUnit => "action names an unknown unit".to_string(),
                    Unsupported::MovedShootLos => {
                        "moved unit also shoots — post-move LOS answer not recorded".to_string()
                    }
                };
                *unsupported.entry(label).or_insert(0) += 1;
            }
        }
    }
    println!("\n=== GATE B — resolve parity (HOLD + ADVANCE) ===");
    let mut tot = 0;
    let mut ok = 0;
    for (k, (t, e)) in &per_kind {
        println!("{:<8} {e}/{t} exact", kind_name(*k));
        tot += t;
        ok += e;
    }
    println!("TOTAL    {ok}/{tot} exact, {} mismatched", tot - ok);
    if !fields.is_empty() {
        println!("mismatching fields (node counts):");
        for (f, c) in &fields {
            println!("  {f:<22} {c}");
        }
    }
    for (idx, k, d) in &first_bad {
        println!("  MISS #{idx} {} fields={:?}", kind_name(*k), d);
    }
    println!("not resolved by this port:");
    for (l, c) in &unsupported {
        println!("  {c:>5}  {l}");
    }
    // Coverage of the shoot path: a green GATE B on volleys that all deal zero
    // would prove nothing, so count the ones that actually move the defender.
    let mut shoot_nodes = 0usize;
    let mut shoot_landed = 0usize;
    for node in &corpus.nodes {
        let Some(t) = node.action.shoot.as_deref() else { continue };
        if node.action.kind != 0 && node.action.kind != 1 {
            continue;
        }
        shoot_nodes += 1;
        let Some(&ti) = node.state_before.roster.index.get(t) else { continue };
        if node.state_after.wounds[ti] != node.state_before.wounds[ti]
            || (node.state_after.wound_frac[ti] - node.state_before.wound_frac[ti]).abs() > EPS
        {
            shoot_landed += 1;
        }
    }
    println!("shoot nodes          {shoot_nodes}, of which {shoot_landed} land expected wounds");

    // ---------------- unimplemented rules ----------------
    println!("\n=== unimplemented rules (name — reason — units, nodes) ===");
    let mut by_rule: BTreeMap<(String, String), (Vec<usize>, usize)> = BTreeMap::new();
    for (pi, us) in statics.iter().enumerate() {
        for u in &us.unimplemented {
            by_rule
                .entry((u.rule.clone(), u.why.clone()))
                .or_insert((Vec::new(), 0))
                .0
                .push(pi);
        }
    }
    if by_rule.is_empty() {
        println!("  none — every rule the corpus fields is modelled");
    } else {
        for ((_r, _w), (pis, count)) in by_rule.iter_mut() {
            for node in &corpus.nodes {
                let hit = (0..node.state_before.units()).any(|i| {
                    pis.contains(&node.state_before.roster.profile[i])
                        && node.state_before.alive[i] > 0
                });
                if hit {
                    *count += 1;
                }
            }
        }
        for ((r, w), (pis, count)) in &by_rule {
            println!("  {r} — {w} — units {} , nodes {count}", pis.len());
        }
    }

    // ---------------- timing (information; M1-4 owns the benchmark) ----------------
    let hold: Vec<usize> = (0..n).filter(|&i| corpus.nodes[i].action.kind == 0).collect();
    if !hold.is_empty() {
        let mut best = f64::INFINITY;
        let mut sink = 0usize;
        for _ in 0..5 {
            let t0 = Instant::now();
            for &i in &hold {
                let node = &corpus.nodes[i];
                if let Ok(s) = resolve(&statics, &node.state_before, &node.action, node.cover_dest) {
                    sink += s.alive[0] as usize;
                }
            }
            let ns = t0.elapsed().as_nanos() as f64 / hold.len() as f64;
            best = best.min(ns);
        }
        println!("\nresolve() HOLD       {best:.0} ns/call ({} nodes, best of 5)", hold.len());
        let rich: Vec<usize> = (0..n).filter(|&i| corpus.nodes[i].rich).collect();
        let mut best_t = f64::INFINITY;
        for _ in 0..5 {
            let t0 = Instant::now();
            for &i in &rich {
                let node = &corpus.nodes[i];
                sink += reply_threat(&statics, &node.state_after, node.player).len();
            }
            best_t = best_t.min(t0.elapsed().as_nanos() as f64 / rich.len().max(1) as f64);
        }
        println!(
            "reply_threat()       {best_t:.0} ns/call ({} rich nodes, best of 5)",
            rich.len()
        );
        if sink == usize::MAX {
            std::process::exit(3);
        }
    }

    let gate_a = within_9 == n;
    let gate_b = tot > 0 && ok == tot;
    println!("\nGATE A {}   GATE B {}", if gate_a { "GREEN" } else { "RED" }, if gate_b { "GREEN" } else { "RED" });
}
