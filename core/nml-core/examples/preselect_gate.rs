//! Pick-identity gate + timing for the planner's candidate pre-selection (aifix preselect-speed lane).
//!
//! Replays every recorded decision position of the given game directories (`<dir>/acts.jsonl`)
//! through `plan_with_rollout` at the SHIPPED grade (top_k 10, horizon 3 by default), and writes
//! one record per act: the chosen unit/action, the ranked prefilter scores, the pool, the rollout
//! values. `--compare <baseline.json>` re-reads such a file and exits non-zero when ANY pick
//! differs (unit, action, pool, best index) — the RED of the lane — and reports the largest
//! score drift separately (float tolerance 1e-9 relative).
//!
//!   cargo run --release --example preselect_gate -- --games <dir>... [--max-games N] [--top-k 10]
//!        [--horizon 3] [--shipped] [--reply-by-net] [--out file.json] [--compare baseline.json]
//!
//! Timing: the planner runs with a never-hit `deadline_us` + `deadline_after_preselect`, which
//! only makes the pick carry `preselect_us` (phases 0-3); picks do not depend on it.

use std::path::PathBuf;
use std::time::Instant;

use nml_core::{act_statics, load_acts, plan_with_rollout};
use serde_json::{json, Value};

fn pct(v: &mut [f64], q: f64) -> f64 {
    if v.is_empty() {
        return 0.0;
    }
    v.sort_by(|a, b| a.partial_cmp(b).unwrap());
    v[((v.len() - 1) as f64 * q).round() as usize]
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let (mut games, mut out, mut cmp): (Vec<PathBuf>, Option<String>, Option<String>) = (vec![], None, None);
    let (mut max_games, mut top_k, mut horizon) = (usize::MAX, 10i64, 3i64);
    let mut shipped = false;
    let mut all_targets = 0usize;
    let mut adv_obj = false;
    let mut reply_net = false;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--games" => {
                i += 1;
                while i < args.len() && !args[i].starts_with("--") {
                    games.push(PathBuf::from(&args[i]));
                    i += 1;
                }
                continue;
            }
            "--out" => { i += 1; out = Some(args[i].clone()); }
            "--compare" => { i += 1; cmp = Some(args[i].clone()); }
            "--max-games" => { i += 1; max_games = args[i].parse().unwrap(); }
            "--top-k" => { i += 1; top_k = args[i].parse().unwrap(); }
            "--horizon" => { i += 1; horizon = args[i].parse().unwrap(); }
            "--shipped" => shipped = true,
            "--adv-obj" => adv_obj = true,
            "--reply-by-net" => reply_net = true,
            "--all-targets" => { i += 1; all_targets = args[i].parse().unwrap(); }
            other => panic!("unknown arg {other}"),
        }
        i += 1;
    }
    games.sort();
    games.truncate(max_games);
    let repo = concat!(env!("CARGO_MANIFEST_DIR"), "/../..");
    let mut records: Vec<Value> = Vec::new();
    let (mut pre_ms, mut tot_ms): (Vec<f64>, Vec<f64>) = (vec![], vec![]);
    let mut menu_w: Vec<f64> = vec![];
    for g in &games {
        let c = load_acts(g.join("acts.jsonl").to_str().unwrap()).unwrap_or_else(|e| panic!("{}: {e}", g.display()));
        let per_act = act_statics(&c, repo);
        let mut knobs = c.knobs;
        knobs.top_k = top_k;
        knobs.horizon = horizon;
        if shipped {
            // The table's stamped seams (act_recorder.gd `_header_line`, E10 inventory): table movement and
            // route_root, wide menu, per-model sighting and sight lines, hero fold, the dangerous end test.
            knobs.charge_gate = true;
            knobs.charge_landing = true;
            knobs.sighting = nml_core::acts::Sighting::Model;
            knobs.movement = true;
            knobs.los_model = true;
            knobs.menu_los = true;
            knobs.menu_wide = true;
            knobs.route_root = true;
            knobs.hero_attach = true;
            knobs.engage_fold = true;
            knobs.dangerous_end_morale = true;
            knobs.rules_epoch = nml_core::acts::CURRENT_RULES_EPOCH;
        }
        knobs.menu_all_targets = all_targets;
        knobs.menu_advance_obj_shoot = adv_obj;
        knobs.reply_by_net = reply_net;
        knobs.deadline_us = 3_600_000_000;
        knobs.deadline_after_preselect = true;
        let name = g.file_name().unwrap().to_string_lossy().to_string();
        for (ai, act) in c.acts.iter().enumerate() {
            let t = Instant::now();
            let pick = match plan_with_rollout(&act.state, &c.terrain, &per_act[ai], &knobs, &act.statics, act.player) {
                Ok(p) => p,
                Err(e) => {
                    records.push(json!({"game": name, "ai": ai, "declined": format!("{e:?}")}));
                    continue;
                }
            };
            tot_ms.push(t.elapsed().as_secs_f64() * 1e3);
            menu_w.push(pick.cands.len() as f64);
            if let Some(us) = pick.deadline.as_ref().and_then(|d| d.preselect_us) {
                pre_ms.push(us as f64 / 1e3);
            }
            records.push(json!({
                "game": name, "ai": ai,
                "unit": pick.unit_key, "action": format!("{:?}", pick.action),
                "before": pick.expectation_before, "after": pick.expectation_after,
                "scored": pick.scored.iter().map(|s| json!([s.0, s.1, s.2, s.3])).collect::<Vec<_>>(),
                "pool": pick.pool_idx, "rs": pick.rs.iter().map(|r| json!([r.0, r.1])).collect::<Vec<_>>(),
                "best": pick.best_idx, "runner": pick.runner_idx,
            }));
        }
    }
    let n = records.iter().filter(|r| r.get("declined").is_none()).count();
    println!(
        "PRESELECT_GATE acts={} answered={n} games={} preselect_ms median={:.1} p90={:.1} | decision_ms median={:.1} p90={:.1}",
        records.len(), games.len(), pct(&mut pre_ms.clone(), 0.5), pct(&mut pre_ms.clone(), 0.9),
        pct(&mut tot_ms.clone(), 0.5), pct(&mut tot_ms.clone(), 0.9)
    );
    println!("PRESELECT_GATE menu width median={:.0} p90={:.0} max={:.0}", pct(&mut menu_w.clone(), 0.5), pct(&mut menu_w.clone(), 0.9), pct(&mut menu_w.clone(), 1.0));
    if let Some(p) = out {
        std::fs::write(&p, serde_json::to_vec(&records).unwrap()).unwrap();
    }
    if let Some(p) = cmp {
        let base_all: Vec<Value> = serde_json::from_slice(&std::fs::read(&p).unwrap()).unwrap();
        // Compare by (game, act): a run over a subset of the baseline's games is valid.
        let key = |v: &Value| format!("{}#{}", v["game"], v["ai"]);
        let by_key: std::collections::HashMap<String, &Value> = base_all.iter().map(|v| (key(v), v)).collect();
        let base: Vec<&Value> = records.iter().map(|r| *by_key.get(&key(r)).unwrap_or_else(|| panic!("{} not in the baseline", key(r)))).collect();
        let (mut bad, mut drift) = (0usize, 0.0f64);
        for (b, r) in base.iter().copied().zip(&records) {
            let same = ["game", "ai", "unit", "action", "pool", "best", "runner", "declined"]
                .iter()
                .all(|k| b.get(*k) == r.get(*k));
            if !same {
                bad += 1;
                if bad <= 3 {
                    println!("PICK DIFFERS {} act {}: {} vs {}", r["game"], r["ai"], b["action"], r["action"]);
                }
            }
            for k in ["before", "after"] {
                if let (Some(x), Some(y)) = (b[k].as_f64(), r[k].as_f64()) {
                    drift = drift.max((x - y).abs() / x.abs().max(1e-12));
                }
            }
            if let (Some(bs), Some(rs)) = (b["scored"].as_array(), r["scored"].as_array()) {
                for (x, y) in bs.iter().zip(rs) {
                    let (x, y) = (x[3].as_f64().unwrap(), y[3].as_f64().unwrap());
                    drift = drift.max((x - y).abs() / x.abs().max(1e-12));
                }
            }
        }
        println!("PRESELECT_GATE compare: picks_different={bad}/{} max_relative_score_drift={drift:.3e}", records.len());
        if bad > 0 || drift > 1e-9 {
            std::process::exit(1);
        }
    }
}
