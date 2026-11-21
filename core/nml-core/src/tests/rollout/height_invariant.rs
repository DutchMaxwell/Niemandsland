//! Heightfield plan step 12: on a generated tier board a model stands on its surface at every step of a game. Twenty
//! hand-planner games (seeds 1..20, two small squads a side, the greedy `policy_step` brain, the move port on) are
//! played on `boardgen` boards at the height gate; after EVERY resolved activation each living model must stand at
//! `surface_y_m` of its own x/z. The whole board plays, so the test also reports what the games did (activations,
//! moves that ended on a raised tier) and fails if no game ever reached a tier (a vacuous run would prove nothing).
use super::*;
use crate::acts::EPOCH_94_PARITY_BATCH;
use crate::boardgen::{generate, plain::to_plain, Symmetry};
use crate::menu::Candidate;
use crate::playout::{other_player, Policy};
use crate::rollout::cross_round;
use crate::sight::surface_y_m;
use crate::sim::Scratch;

const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":1,
    "wounds_max":[1,1,1],"model_count":3,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":3,"count":3,"ap":0,"rules":[]}]},
  "p1_1_b":{"unit_id":"p1_1_b","name":"B","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "p2_0_x":{"unit_id":"p2_0_x","name":"X","quality":4,"defense":3,"tough":1,
    "wounds_max":[1,1,1],"model_count":3,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Blade","range":0,"attacks":3,"count":3,"ap":0,"rules":[]}]},
  "p2_1_y":{"unit_id":"p2_1_y","name":"Y","quality":4,"defense":3,"tough":1,
    "wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,
    "game_system":"gf","faction_folder":"human_defense_force","special_rules":[],
    "item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

/// One unit of the state JSON: `n` models in a row across the cell centre `(cx, cz)` metres, 0.9 in apart, on the ground.
fn unit_json(player: i64, n: usize, (cx, cz): (f64, f64)) -> String {
    let at = |k: usize| format!("[{},0.0,{}]", cx + (k as f64 - (n as f64 - 1.0) * 0.5) * 0.9 * crate::IN2M, cz);
    let (pos, ones, radii) = (
        (0..n).map(at).collect::<Vec<_>>().join(","),
        vec!["1"; n].join(","),
        vec!["0.016"; n].join(","),
    );
    format!(r#"{{"player":{player},"alive":{n},"wounds":[{ones}],"radii":[{radii}],"positions":[{pos}],"in_cover":false,
      "shaken":false,"fatigued":false,"activated":false,"casts":0,"morale_bonus":0,"aircraft":false,"dormant":false,
      "ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":0.0,"mods":{{}},"mods_base":{{}},
      "bands":{{"advance":6.0,"rush":12.0}}}}"#)
}

/// The world centre (metres) of the `k`-th ground cell (level 0) of the rows `rows`, in grid order.
fn ground_cell(l: &crate::boardgen::Layout, rows: std::ops::Range<usize>, k: usize) -> (f64, f64) {
    let c = l.cells.iter().filter(|c| c.level == 0 && rows.contains(&c.z)).nth(k).expect("a ground cell in the deployment rows");
    let half = |n: usize| n as f64 / 2.0;
    (((c.x as f64 + 0.5) - half(l.nx)) * f64::from(l.cell_in) * crate::IN2M, ((c.z as f64 + 0.5) - half(l.nz)) * f64::from(l.cell_in) * crate::IN2M)
}

/// The first model that does not stand on its surface, as a sentence, or `None`.
fn off_surface(st: &State, t: &Terrain, epoch: u32) -> Option<String> {
    (0..st.units()).find_map(|u| {
        st.positions[u].iter().enumerate().find_map(|(m, p)| {
            let want = surface_y_m(t, [p[0], p[2]], epoch);
            ((p[1] - want).abs() > 1e-6).then(|| format!("{} model {m} stands at y {:.4} m on a surface of {want:.4} m (x {:.3}, z {:.3})", st.key(u), p[1], p[0], p[2]))
        })
    })
}

/// Plays game `seed`; the first violation, and `(activations, raised ends, charges)`.
fn play(seed: i64) -> (Option<String>, (usize, usize, usize)) {
    let layout = generate(seed, Symmetry::Point180);
    let t = Terrain::build(&to_plain(&layout));
    let d = layout.deploy_depth_cells.max(2);
    let (c1, c2) = (|k| ground_cell(&layout, 0..d, k), |k| ground_cell(&layout, layout.nz - d..layout.nz, k));
    let mid = ground_cell(&layout, layout.nz / 2 - 1..layout.nz / 2 + 1, 0);
    let plain = format!(r#"{{"round":1,"rounds_total":3,"scoring":"end","objectives":[{{"pos":[{},0.0,{}],"owner":0}}],"units":{{
      "p1_0_a":{},"p1_1_b":{},"p2_0_x":{},"p2_1_y":{}}}}}"#,
        mid.0, mid.1, unit_json(1, 3, c1(0)), unit_json(1, 1, c1(3)), unit_json(2, 3, c2(0)), unit_json(2, 1, c2(3)));
    let header = read_act_header(HEADER).expect("header");
    let mut cache = ProfileCache::new(header.profiles);
    let mut roster = None;
    let mut cur = io::state_from_json(&plain, &mut cache, &mut roster).expect("state");
    let epoch = EPOCH_94_PARITY_BATCH;
    let statics = statics_of(&cur, epoch);
    let seams = Seams { rules_epoch: epoch, movement: true, moved_shoot: true, hero_attach: true, ..Seams::default() };
    let policy = Policy::new(&statics, &t, seams);
    if let Some(bad) = off_surface(&cur, &t, epoch) {
        return (Some(format!("the start is not settled: {bad}")), (0, 0, 0));
    }
    let (mut sc, mut turn, mut stats) = (Scratch::default(), 1, (0, 0, 0));
    for _ in 0..80 {
        let mut pick: Option<Candidate> = policy.policy_step(&cur, turn, false, &mut sc).expect("a step");
        if pick.is_none() {
            turn = other_player(&cur, turn);
            pick = policy.policy_step(&cur, turn, false, &mut sc).expect("a step");
        }
        let Some(pick) = pick else {
            if cur.round >= cur.rounds_total {
                break;
            }
            turn = cross_round(&statics, &mut cur, None);
            continue;
        };
        cur = policy.resolve(&cur, &pick).expect("the activation resolves");
        stats.0 += 1;
        stats.2 += usize::from(pick.kind == crate::sim::CHARGE);
        stats.1 += cur.positions.iter().flatten().filter(|p| p[1] > 0.0).count();
        if let Some(bad) = off_surface(&cur, &t, epoch) {
            return (Some(format!("seed {seed} activation {} ({} kind {}): {bad}", stats.0, pick.unit, pick.kind)), stats);
        }
        turn = other_player(&cur, turn);
    }
    (None, stats)
}

#[test]
fn every_living_model_stands_on_its_surface() {
    let mut bad = Vec::new();
    let mut total = (0, 0, 0);
    for seed in 1..=20 {
        let (violation, s) = play(seed);
        eprintln!("seed {seed:2}: {} activations, {} raised model-ends, {} charges{}", s.0, s.1, s.2, violation.as_deref().map_or(String::new(), |v| format!("  VIOLATION {v}")));
        bad.extend(violation);
        total = (total.0 + s.0, total.1 + s.1, total.2 + s.2);
    }
    assert!(bad.is_empty(), "{} of 20 games left a model off its surface:\n{}", bad.len(), bad.join("\n"));
    assert!(total.0 > 100 && total.1 > 0, "the games must move and some model must end on a tier, or the run proves nothing: {total:?}");
}
