//! Organic plan C5 (measure, no production code): what the free solids cost the AI. On one town board, hand-planner games
//! (the `height_invariant` set-up: two small squads a side, `policy_step`, the move port on) are played on the board as the
//! core gets it (houses = turned free boxes) and on the same board with the houses painted back as cells; the mean
//! wall-clock time of one `policy_step` and of 10 000 `type_at` probes is printed per board, `NML_RUNS` runs each.
//! `NML_SEED=<seed> NML_RUNS=5 cargo test --release --lib organic_turn_cost -- --ignored --nocapture`
use super::height_invariant::{unit_json, HEADER};
use super::*;
use crate::acts::CURRENT_RULES_EPOCH;
use crate::boardgen::{generate_themed, plain::to_plain, LotKind, Symmetry, Theme};
use crate::menu::Candidate;
use crate::playout::{other_player, Policy};
use crate::rollout::cross_round;
use crate::sim::Scratch;
use crate::terrain::{PlainTerrain, CONTAINER};
use std::time::Instant;

fn cell_board(l: &crate::boardgen::Layout, p: &PlainTerrain) -> PlainTerrain {
    let m = ((f64::from(l.board_in[0]).hypot(f64::from(l.board_in[1])) / f64::from(l.cell_in)).ceil() as i64 + 1) / 2 * 2;
    let m = ((m - l.nx as i64) / 2) as f64;
    let mut q = PlainTerrain { sandbox: Vec::new(), containers: Vec::new(), ..p.clone() };
    q.cells.extend(l.cells.iter().filter(|c| c.lot_kind == LotKind::Roofed).map(|c| [c.x as f64 + m, c.z as f64 + m, f64::from(CONTAINER)]));
    q
}

/// (ms per policy step, steps, ms per 10 000 type_at probes)
fn run(l: &crate::boardgen::Layout, p: &PlainTerrain) -> (f64, usize, f64) {
    let t = Terrain::build(p);
    let cell = |rows: std::ops::Range<usize>, k: usize| {
        let c = l.cells.iter().filter(|c| c.level == 0 && rows.contains(&c.z) && !matches!(c.lot_kind, LotKind::Roofed | LotKind::Hazard)).nth(k).expect("ground");
        (((c.x as f64 + 0.5) - 8.0) * 3.0 * crate::IN2M, ((c.z as f64 + 0.5) - 8.0) * 3.0 * crate::IN2M)
    };
    let (c1, c2, mid) = (|k| cell(0..4, k), |k| cell(12..16, k), cell(7..9, 0));
    let plain = format!(r#"{{"round":1,"rounds_total":3,"scoring":"end","objectives":[{{"pos":[{},0.0,{}],"owner":0}}],"units":{{
      "p1_0_a":{},"p1_1_b":{},"p2_0_x":{},"p2_1_y":{}}}}}"#,
        mid.0, mid.1, unit_json(1, 3, c1(0)), unit_json(1, 1, c1(3)), unit_json(2, 3, c2(0)), unit_json(2, 1, c2(3)));
    let header = read_act_header(HEADER).expect("header");
    let mut cache = ProfileCache::new(header.profiles);
    let mut roster = None;
    let mut cur = io::state_from_json(&plain, &mut cache, &mut roster).expect("state");
    let epoch = CURRENT_RULES_EPOCH;
    let statics = statics_of(&cur, epoch);
    let seams = Seams { rules_epoch: epoch, movement: true, moved_shoot: true, hero_attach: true, ..Seams::default() };
    let policy = Policy::new(&statics, &t, seams);
    let (mut sc, mut turn, mut steps, mut spent) = (Scratch::default(), 1, 0, 0.0);
    for _ in 0..60 {
        let t0 = Instant::now();
        let mut pick: Option<Candidate> = policy.policy_step(&cur, turn, false, &mut sc).expect("a step");
        if pick.is_none() {
            turn = other_player(&cur, turn);
            pick = policy.policy_step(&cur, turn, false, &mut sc).expect("a step");
        }
        spent += t0.elapsed().as_secs_f64();
        let Some(pick) = pick else {
            if cur.round >= cur.rounds_total { break; }
            turn = cross_round(&statics, &mut cur, None);
            continue;
        };
        steps += 1;
        cur = policy.resolve(&cur, &pick).expect("the activation resolves");
        turn = other_player(&cur, turn);
    }
    let t0 = Instant::now();
    let mut hits = 0;
    for k in 0..10_000 {
        let (x, z) = ((k % 100) as f64 / 100.0 * 1.2 - 0.6, (k / 100) as f64 / 100.0 * 1.2 - 0.6);
        hits += usize::from(t.type_at([x as f32, 0.0, z as f32]) == CONTAINER);
    }
    let probe = t0.elapsed().as_secs_f64() * 1000.0;
    assert!(hits > 0);
    (spent * 1000.0 / steps.max(1) as f64, steps, probe)
}

#[test]
#[ignore = "measurement: NML_SEED=<seed> NML_RUNS=5 cargo test --release --lib organic_turn_cost -- --ignored --nocapture"]
fn organic_turn_cost() {
    let seed: i64 = std::env::var("NML_SEED").ok().and_then(|v| v.parse().ok()).unwrap_or(41);
    let runs: usize = std::env::var("NML_RUNS").ok().and_then(|v| v.parse().ok()).unwrap_or(5);
    let l = generate_themed(seed, Symmetry::Point180, Theme::RuinTown);
    let free = to_plain(&l);
    let cells = cell_board(&l, &free);
    for r in 0..runs {
        let (a, b) = (run(&l, &cells), run(&l, &free));
        eprintln!("ORGANIC_COST seed {seed} run {r}: cell board {:.3} ms/step ({} steps), {:.3} ms/10k type_at | free board {:.3} ms/step ({} steps), {:.3} ms/10k type_at",
            a.0, a.1, a.2, b.0, b.1, b.2);
    }
}
