use super::*;

    // ------------- REVIVE-SPOT (PLAN_REVIVE_SPOT.md): where a Reanimation brings a model back -----------------

    /// The plan's facts first: what the core does TODAY (rules epoch 95), measured, not read. Unit 0 is the
    /// Reanimation carrier: `n` models of Tough(`tough`), the first `standing.len()` of them standing at `standing`
    /// (world inches, x / z) with a 32 mm base; the rest fell. Units 1-3 stand far away and are not joined, unless a
    /// test moves them. `target` 1 makes every die a success.
    fn rean_line(n: usize, tough: i64, standing: &[[f64; 2]]) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let mut carrier = st.profiles.list[0].clone();
        carrier.wounds_max = vec![tough; n];
        carrier.model_count = n as i64;
        let mut plain = st.profiles.list[0].clone();
        plain.wounds_max = vec![1];
        st.profiles = Rc::new(Profiles { list: vec![carrier, plain], index: HashMap::new() });
        st.roster = Rc::new(Roster { keys: st.roster.keys.clone(), index: st.roster.keys.iter().cloned().zip(0..).collect(), profile: vec![0, 1, 1, 1] });
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None; 4]);
        st.positions = vec![standing.iter().map(|p| [p[0] * IN2M, 0.0, p[1] * IN2M]).collect(),
            vec![[-20.0 * IN2M, 0.0, -15.0 * IN2M]], vec![[20.0 * IN2M, 0.0, -15.0 * IN2M]], vec![[25.0 * IN2M, 0.0, -15.0 * IN2M]]];
        st.wounds = vec![vec![tough; standing.len()], vec![1], vec![1], vec![1]];
        st.alive = vec![standing.len() as i64, 1, 1, 1];
        st.radii = Rc::new(vec![vec![0.016; standing.len()], vec![0.016], vec![0.016], vec![0.016]]);
        let a = UnitStatic { name: "Rean".into(), reanimation: Some(crate::unit::ReanimationSpec { target: 1 }), ..Default::default() };
        (st, vec![a, UnitStatic { name: "plain".into(), ..Default::default() }]) // statics are per PROFILE
    }

    /// A HOLD for unit 0 on `t`, through the real tray resolve.
    fn rean_run(st: &State, statics: &[UnitStatic], t: &crate::terrain::Terrain, epoch: u32, seed: i64, heroes: bool) -> (State, ShootResult) {
        let act = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: None, charge: None, patient: false, split: None,
            traced: None, teleport: None };
        resolve_stochastic_tray_on_board(statics, st, &act, t, Seams { rules_epoch: epoch, hero_attach: heroes, ..Seams::default() },
            &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(seed)).unwrap()
    }

    /// The covfix2-dice lane's container (aig_l6_container_end.rs): x 3..9 in, z 3..6 in (world), four edge walls.
    fn container_board(with: bool) -> crate::terrain::Terrain {
        let walls = [[[0.0762, 0.0762], [0.0762, 0.1524]], [[0.0762, 0.1524], [0.2286, 0.1524]],
            [[0.2286, 0.1524], [0.2286, 0.0762]], [[0.2286, 0.0762], [0.0762, 0.0762]]];
        let (cells, walls) = if with { (serde_json::json!([[16, 16, crate::terrain::CONTAINER], [17, 16, crate::terrain::CONTAINER]]), serde_json::json!(walls)) }
            else { (serde_json::json!([]), serde_json::json!([])) };
        crate::terrain::Terrain::build(&serde_json::from_value(serde_json::json!({"cell_params": {"grid_rotation_degrees": 0,
            "grid_size_inches": 3, "inches_to_meters": IN2M, "table_size_feet": [6, 4]}, "cells": cells, "sandbox": [], "walls": walls})).unwrap())
    }

    /// A town board: a flat 24 x 16 tier grid (3 in cells), `solid` listing the intact-house cells (#3329's board).
    fn town_board(solid: Vec<u16>) -> crate::terrain::Terrain {
        let mut p: crate::terrain::PlainTerrain = serde_json::from_value(serde_json::json!({"cells": [], "sandbox": [],
            "cell_params": {"table_size_feet": [6.0, 4.0], "grid_rotation_degrees": 0.0, "grid_size_inches": 3.0, "inches_to_meters": IN2M}})).unwrap();
        p.tiers = Some(crate::terrain::TierGrid { nx: 24, nz: 16, cell_in: 3.0, level_in: vec![0.0; 384], ladders: vec![], stairs: vec![] });
        p.solid_cells = solid;
        crate::terrain::Terrain::build(&p)
    }

    /// The tier cell under a world point (inches).
    fn cell_at(x_in: f64, z_in: f64) -> u16 {
        ((z_in / 3.0 + 8.0).floor() as u16) * 24 + (x_in / 3.0 + 12.0).floor() as u16
    }

    /// The 0-origin inch frame `rest_forbidden` reads, from a world position.
    fn rest_bad(t: &crate::terrain::Terrain, p: V3d, r_m: f64) -> bool {
        let c = t.to_inch([p[0] as f32, p[1] as f32, p[2] as f32]);
        crate::mv::gate::rest_forbidden([c[0] as f64, c[1] as f64], r_m / IN2M, t)
    }

    type V3d = [f64; 3];

    /// Three standing in an L, the 4th fell. Centre (1.33, 4.5) in; the model nearest it is (2.0, 4.5), so today's one
    /// candidate is 34 mm further along +X: (3.34, 4.5) in.
    const L3: [[f64; 2]; 3] = [[1.0, 3.5], [1.0, 5.5], [2.0, 4.5]];

    /// FACT (b), the covfix2-dice proof as a core test: today a revive lands inside an impassable container.
    #[test]
    fn pin95_a_revive_lands_in_a_container() {
        let (st, statics) = rean_line(4, 1, &L3);
        let t = container_board(true);
        let (next, shot) = rean_run(&st, &statics, &t, 95, 1, false);
        assert_eq!(next.alive[0], 4, "restored: {:?}", shot.log);
        let back = next.positions[0][0];
        assert!(rest_bad(&t, back, 0.016), "the restored base stands in the container: {back:?}");
        assert!(!rest_bad(&container_board(false), back, 0.016), "planted: the open board is legal there");
    }

    /// FACT (c): a town board, the same spot inside an intact house (solid tier cell) - today it lands there.
    #[test]
    fn pin95_a_revive_lands_in_a_house() {
        let (st, statics) = rean_line(4, 1, &L3);
        let t = town_board(vec![cell_at(3.34, 4.5)]);
        let (next, shot) = rean_run(&st, &statics, &t, 95, 1, false);
        assert_eq!(next.alive[0], 4, "restored: {:?}", shot.log);
        let back = next.positions[0][0];
        assert!(t.solid_at(back[0] / IN2M, back[2] / IN2M), "the restored base stands over the solid cell: {back:?}");
    }

    /// FACT (a) / difference 6: two dead Tough(3) models and exactly 2 successes - the core brings ONE back at 2 wounds.
    #[test]
    fn pin95_two_successes_on_two_dead_tough3_bring_one_model() {
        let (st, mut statics) = rean_line(4, 3, &L3[..2]);
        statics[0].reanimation = Some(crate::unit::ReanimationSpec { target: 5 });
        let seed = (0..200).find(|&s| rean_run(&st, &statics, &town_board(vec![]), 95, s, false).1.log.iter()
            .any(|l| l.contains("rolls 6 dice") && l.contains("— 2 success(es)"))).expect("a seed with exactly 2 of 6");
        let (next, shot) = rean_run(&st, &statics, &town_board(vec![]), 95, seed, false);
        assert_eq!((next.alive[0], next.wounds[0].clone()), (3, vec![2, 3, 3]), "{:?}", shot.log);
    }

    /// FACT difference 1 + 2: ONE candidate, away from the unit centre; a foe base on it and nobody returns, though the
    /// other side of the same anchor is open.
    #[test]
    fn pin95_one_candidate_and_a_foe_on_it_blocks_the_revive() {
        let (st, statics) = rean_line(4, 1, &L3);
        let t = town_board(vec![]);
        let (next, _) = rean_run(&st, &statics, &t, 95, 1, false);
        let back = next.positions[0][0];
        assert!((back[0] / IN2M - (2.0 + 0.034 / IN2M)).abs() < 1e-6 && (back[2] / IN2M - 4.5).abs() < 1e-6, "{back:?}");
        let mut blocked = st.clone();
        blocked.positions[2] = vec![[back[0], 0.0, back[2]]];
        let (next, shot) = rean_run(&blocked, &statics, &t, 95, 1, false);
        assert_eq!(next.alive[0], 3, "no second candidate: {:?}", shot.log);
        assert!(shot.log.iter().any(|l| l.contains("no placeable spot")), "{:?}", shot.log);
    }

    /// FACT difference 3: the one candidate may sit on the carrier's OWN model - the core stacks the bases.
    #[test]
    fn pin95_a_revive_can_stack_on_its_own_unit() {
        let own = [[1.0, 3.5], [1.0, 5.5], [2.0, 4.5], [2.0 + 0.034 / IN2M, 4.5]];
        let (st, statics) = rean_line(5, 1, &own);
        let (next, _) = rean_run(&st, &statics, &town_board(vec![]), 95, 1, false);
        assert_eq!(next.alive[0], 5);
        let (a, b) = (next.positions[0][0], next.positions[0][4]);
        assert!((a[0] - b[0]).hypot(a[2] - b[2]) < 0.032, "bases overlap: {a:?} {b:?}");
    }

    /// FACT difference 4a: a host with no standing model but a standing joined hero restores nobody.
    #[test]
    fn pin95_a_joined_hero_does_not_anchor() {
        let (mut st, mut statics) = rean_line(2, 1, &[]);
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        st.positions[1] = vec![[0.0, 0.0, 0.0]];
        statics[0].reanimation = Some(crate::unit::ReanimationSpec { target: 1 });
        let (next, shot) = rean_run(&st, &statics, &town_board(vec![]), 95, 1, true);
        assert_eq!(next.alive[0], 0, "{:?}", shot.log);
    }

    /// FACT (lone anchor): one standing model is the unit centre, so the one candidate is ON it - both casualties come
    /// back stacked on the survivor.
    #[test]
    fn pin95_the_lone_anchor_spot_is_on_the_anchor() {
        let (st, statics) = rean_line(3, 1, &[[0.0, 0.0]]);
        let (next, shot) = rean_run(&st, &statics, &town_board(vec![]), 95, 1, false);
        assert_eq!(next.alive[0], 3, "{:?}", shot.log);
        assert!(next.positions[0].iter().all(|p| *p == [0.0, 0.0, 0.0]), "{:?}", next.positions[0]);
    }

    /// FACT difference 5: the restored model gets the default radius, not the unit's own base.
    #[test]
    fn pin95_the_restored_radius_is_the_default() {
        let (mut st, statics) = rean_line(4, 1, &L3);
        st.radii = Rc::new(vec![vec![0.025; 3], vec![0.016], vec![0.016], vec![0.016]]);
        let (next, _) = rean_run(&st, &statics, &town_board(vec![]), 95, 1, false);
        assert_eq!(next.radii[0][0], DEFAULT_BASE_RADIUS_M);
    }

    // ------------- Step 1: the placement guard at PENDING_EPOCH_REVIVE_SPOT ------------------------------------------

    const E96: u32 = crate::acts::PENDING_EPOCH_REVIVE_SPOT;

    fn refused(shot: &ShootResult) -> bool {
        shot.log.iter().any(|l| l == "Reanimation: 1 success but no placeable spot — coherency missing")
    }

    /// The restored model `k` (slot order) on `t`: whole base on the table, no rest refusal, not over or against a house,
    /// clear of every other standing base, and within 1 in (edge to edge) of one of `originals` (world inches, 32 mm bases).
    fn legal_and_coherent(t: &crate::terrain::Terrain, next: &State, k: usize, originals: &[[f64; 2]]) -> bool {
        let (p, r) = (next.positions[0][k], next.radii[0][k]);
        let on_table = p[0].abs() + r <= 36.0 * IN2M && p[2].abs() + r <= 24.0 * IN2M;
        let clear = (0..next.units()).all(|u| next.positions[u].iter().enumerate().all(|(j, q)| {
            (u == 0 && j == k) || (q[0] - p[0]).hypot(q[2] - p[2]) >= r + next.radii[u][j] + 0.0009
        }));
        let coherent = originals.iter().any(|o| (o[0] * IN2M - p[0]).hypot(o[1] * IN2M - p[2]) - r - 0.016 <= IN2M + 1e-9);
        on_table && clear && coherent && !rest_bad(t, p, r) && !t.solid_at(p[0] / IN2M, p[2] / IN2M)
    }

    /// The covfix2-dice container: at 95 the model stands inside it (`pin95_a_revive_lands_in_a_container` is the red),
    /// at 96 the ring finds a legal spot outside it.
    #[test]
    fn a_revive_never_lands_in_a_container() {
        let (st, statics) = rean_line(4, 1, &L3);
        let t = container_board(true);
        let (next, shot) = rean_run(&st, &statics, &t, E96, 1, false);
        assert_eq!(next.alive[0], 4, "{:?}", shot.log);
        assert!(legal_and_coherent(&t, &next, 0, &L3), "{:?}", next.positions[0][0]);
    }

    /// The town house (`pin95_a_revive_lands_in_a_house` is the red): at 96 the spot is off the solid cell.
    #[test]
    fn a_revive_never_lands_in_a_house() {
        let (st, statics) = rean_line(4, 1, &L3);
        let t = town_board(vec![cell_at(3.34, 4.5)]);
        let (next, shot) = rean_run(&st, &statics, &t, E96, 1, false);
        assert_eq!(next.alive[0], 4, "{:?}", shot.log);
        assert!(legal_and_coherent(&t, &next, 0, &L3), "{:?}", next.positions[0][0]);
        let w = t.solid_walls_world_m();
        let p = next.positions[0][0];
        assert!(w.iter().all(|s| crate::mv::geom2::point_seg_distance([p[0] as f32, p[2] as f32], s[0], s[1]) >= 0.016 + 0.001), "clear of the house walls");
    }

    /// The whole base stays on the table: at 95 the one spot hangs over the east edge, at 96 the ring stays on.
    #[test]
    fn a_revive_never_leaves_the_table() {
        let edge = [[33.5, 3.5], [33.5, 5.5], [34.5, 4.5]]; // the 95 spot is at 35.84 in, its base reaches 36.47 > 36
        let (st, statics) = rean_line(4, 1, &edge);
        let (old, _) = rean_run(&st, &statics, &town_board(vec![]), 95, 1, false);
        assert!(old.positions[0][0][0] + 0.016 > 36.0 * IN2M, "red: at 95 the base hangs over the table edge");
        let t = town_board(vec![]);
        let (next, shot) = rean_run(&st, &statics, &t, E96, 1, false);
        assert_eq!(next.alive[0], 4, "{:?}", shot.log);
        assert!(legal_and_coherent(&t, &next, 0, &edge), "{:?}", next.positions[0][0]);
    }

    /// Own bases count at 96 (at 95 they stack, `pin95_a_revive_can_stack_on_its_own_unit`).
    #[test]
    fn a_revive_never_stacks_on_its_own_unit() {
        let own = [[1.0, 3.5], [1.0, 5.5], [2.0, 4.5], [2.0 + 0.034 / IN2M, 4.5]];
        let (st, statics) = rean_line(5, 1, &own);
        let t = town_board(vec![]);
        let (next, shot) = rean_run(&st, &statics, &t, E96, 1, false);
        assert_eq!(next.alive[0], 5, "{:?}", shot.log);
        assert!(legal_and_coherent(&t, &next, 0, &own), "{:?}", next.positions[0][0]);
    }

    /// Difference 5: at 96 the returning model keeps its unit's own base radius; at 95 the default is pinned.
    #[test]
    fn a_restored_model_keeps_its_own_base() {
        let (mut st, mut statics) = rean_line(4, 1, &[[0.0, 0.0], [-2.0, 0.0], [-4.0, 0.0]]);
        st.radii = Rc::new(vec![vec![0.025; 3], vec![0.016], vec![0.016], vec![0.016]]);
        statics[0].base_radius = 0.025;
        let (next, _) = rean_run(&st, &statics, &town_board(vec![]), E96, 1, false);
        assert_eq!(next.alive[0], 4);
        assert_eq!(next.radii[0][0], 0.025);
        assert_eq!(next.positions[0][0], [0.025 + 0.025 + 0.002, 0.0, 0.0], "anchor 0, gap 2 mm, +X, with the real radius");
        let (old, _) = rean_run(&st, &statics, &town_board(vec![]), 95, 1, false);
        assert_eq!(old.radii[0][0], DEFAULT_BASE_RADIUS_M, "95 pin");
    }

    // ------------- Step 2: the ring search ---------------------------------------------------------------------------

    /// Plain board: anchor 0, gap 2 mm, heading +X. A small foe base that blocks only that spot: heading k = 1.
    #[test]
    fn the_ring_takes_the_first_free_heading() {
        let line = [[0.0, 0.0], [-1.5, 0.0]];
        let (st, statics) = rean_line(3, 1, &line);
        let d = 0.016 + 0.016 + 0.002;
        let (next, _) = rean_run(&st, &statics, &town_board(vec![]), E96, 1, false);
        assert_eq!(next.positions[0][0], [d, 0.0, 0.0]);
        let mut foe = st.clone();
        foe.positions[2] = vec![[d + 0.012, 0.0, -0.004]]; // 12.6 mm from k = 0, 22.4 mm from k = 1
        Rc::make_mut(&mut foe.radii)[2] = vec![0.001];
        let (next, _) = rean_run(&foe, &statics, &town_board(vec![]), E96, 1, false);
        let a = std::f64::consts::TAU / 16.0;
        let p = next.positions[0][0];
        assert!((p[0] - a.cos() * d).abs() < 1e-12 && (p[2] - a.sin() * d).abs() < 1e-12, "{p:?}");
    }

    /// Two successes: the second model never anchors on the first - both stand within 1 in of an ORIGINAL model, and
    /// the second takes anchor 0's next free heading (k = 3), not a spot beside the first.
    #[test]
    fn a_restored_model_is_no_anchor() {
        let line = [[0.0, 0.0], [-1.5, 0.0]];
        let (st, statics) = rean_line(4, 1, &line);
        let t = town_board(vec![]);
        let (next, shot) = rean_run(&st, &statics, &t, E96, 1, false);
        assert_eq!(next.alive[0], 4, "{:?}", shot.log);
        assert!(legal_and_coherent(&t, &next, 0, &line) && legal_and_coherent(&t, &next, 1, &line));
        let (d, a) = (0.034, 3.0 * std::f64::consts::TAU / 16.0);
        let p = next.positions[0][0];
        assert!((p[0] - a.cos() * d).abs() < 1e-12 && (p[2] - a.sin() * d).abs() < 1e-12, "{p:?}");
    }

    /// Nowhere legal: the lone anchor's 32 ring spots are all taken by foe bases - nobody returns, the line is logged.
    /// Planted: the same board without the ring of foes restores.
    #[test]
    fn no_legal_spot_restores_nobody() {
        let (mut st, statics) = rean_line(2, 1, &[[0.0, 0.0]]);
        let mut ring = Vec::new();
        for gap in [0.002, 0.5 * IN2M + 0.002] {
            for k in 0..16 {
                let a = std::f64::consts::TAU * f64::from(k) / 16.0;
                ring.push([a.cos() * (0.032 + gap), 0.0, a.sin() * (0.032 + gap)]);
            }
        }
        let planted = st.clone();
        st.positions[2] = ring.clone();
        st.wounds[2] = vec![1; ring.len()];
        Rc::make_mut(&mut st.radii)[2] = vec![0.001; ring.len()];
        let (next, shot) = rean_run(&st, &statics, &town_board(vec![]), E96, 1, false);
        assert_eq!(next.alive[0], 1, "{:?}", shot.log);
        assert!(refused(&shot), "rules-must-log: {:?}", shot.log);
        assert_eq!(rean_run(&planted, &statics, &town_board(vec![]), E96, 1, false).0.alive[0], 2, "planted");
    }

    /// Ruling 4a: a host with no standing model and a standing joined hero that carries the rule (the Aura reaches
    /// "this model and its unit") - the hero anchors, the host's casualties come back (at 95: none, see the pin).
    /// Plain Reanimation on the host only and a hero WITHOUT it: the hero is not a Reanimation member, so it anchors
    /// nobody and nothing returns - the table's `reanimation_members`.
    #[test]
    fn a_standing_joined_hero_with_the_rule_anchors_the_host() {
        let (mut st, mut statics) = rean_line(2, 1, &[]);
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        st.positions[1] = vec![[0.0, 0.0, 0.0]];
        let mut hero_profile = st.profiles.list[1].clone();
        hero_profile.unit_id = "ah".into();
        st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(), st.profiles.list[1].clone(), hero_profile], index: HashMap::new() });
        st.roster = Rc::new(Roster { keys: st.roster.keys.clone(), index: st.roster.index.clone(), profile: vec![0, 2, 1, 1] });
        statics.push(UnitStatic { name: "hero".into(), reanimation: Some(crate::unit::ReanimationSpec { target: 1 }), ..Default::default() });
        let (next, shot) = rean_run(&st, &statics, &town_board(vec![]), E96, 1, true);
        assert_eq!(next.alive[0], 2, "{:?}", shot.log);
        assert_eq!(next.positions[0][1], [0.034, 0.0, 0.0], "the first one at the hero, gap 2 mm, +X");
        statics[2].reanimation = None;
        let (next, shot) = rean_run(&st, &statics, &town_board(vec![]), E96, 1, true);
        assert_eq!(next.alive[0], 0, "a hero without the rule anchors nobody: {:?}", shot.log);
    }

    /// The ring draws no die and leaves everything else alone: the Reanimation roll's faces are the same at 95 and 96,
    /// and an unrelated unit's whole activation is identical at both epochs.
    #[test]
    fn revive_spot_draws_no_die_and_leaves_other_units_alone() {
        let (st, statics) = rean_line(4, 1, &L3);
        let (_, sa) = rean_run(&st, &statics, &town_board(vec![]), 95, 1, false);
        let (_, sb) = rean_run(&st, &statics, &town_board(vec![]), E96, 1, false);
        assert_eq!(sa.rolls.iter().map(|r| r.faces.clone()).collect::<Vec<_>>(), sb.rolls.iter().map(|r| r.faces.clone()).collect::<Vec<_>>());
        let other = |e: u32| {
            let act = Action { kind: HOLD, unit: "b".into(), dest: None, shoot: None, charge: None, patient: false, split: None,
                traced: None, teleport: None };
            let (n, s) = resolve_stochastic_tray_on_board(&statics, &st, &act, &container_board(true), Seams { rules_epoch: e, ..Seams::default() },
                &mut crate::rng::GodotRng::new(3), &mut Tray::seeded(9)).unwrap();
            format!("{:?}|{:?}|{:?}|{:?}", n.positions, n.wounds, s.log, s.rolls.iter().map(|r| r.faces.clone()).collect::<Vec<_>>())
        };
        assert_eq!(other(95), other(E96), "an unrelated unit's activation is identical");
    }

    // ------------- Review of #3383: no candidate beyond a wall or a tier step; the roof pin ----------------------------

    /// A board with one thin wall (world metres) and nothing else.
    fn wall_board(walls: serde_json::Value) -> crate::terrain::Terrain {
        crate::terrain::Terrain::build(&serde_json::from_value(serde_json::json!({"cell_params": {"grid_rotation_degrees": 0,
            "grid_size_inches": 3, "inches_to_meters": IN2M, "table_size_feet": [6, 4]}, "cells": [], "sandbox": [], "walls": walls})).unwrap())
    }

    /// A lone anchor at the origin, a thin wall 28 mm east of it (x = 0.028 m, z -0.05..0.05). The wall band refuses the inner ring's
    /// east headings (k = -3..3), 1 mm foe bases fill its other headings (and so block the outer ring there too); outer k = +-1..3
    /// sit in the wall band. The one rest-legal candidate left is the outer ring's +X spot (46.7 mm, 18.7 mm past the wall) - BEHIND
    /// the wall. Red before the rule: restored there. Planted: the same board without the wall restores (not behind anything).
    #[test]
    fn a_revive_never_comes_back_behind_a_wall() {
        let (mut st, statics) = rean_line(2, 1, &[[0.0, 0.0]]);
        let foes: Vec<[f64; 3]> = (4..13).map(|k| {
            let a = std::f64::consts::TAU * f64::from(k) / 16.0;
            [a.cos() * 0.034, 0.0, a.sin() * 0.034]
        }).collect();
        st.positions[2] = foes.clone();
        st.wounds[2] = vec![1; foes.len()];
        Rc::make_mut(&mut st.radii)[2] = vec![0.001; foes.len()];
        let t = wall_board(serde_json::json!([[[0.028, -0.05], [0.028, 0.05]]]));
        let (next, shot) = rean_run(&st, &statics, &t, E96, 1, false);
        assert_eq!(next.alive[0], 1, "nothing on this side of the wall is free: {:?} {:?}", next.positions[0], shot.log);
        assert!(refused(&shot), "{:?}", shot.log);
        let (open, _) = rean_run(&st, &statics, &wall_board(serde_json::json!([])), E96, 1, false);
        assert_eq!(open.alive[0], 2, "planted");
    }

    /// A 3 in raised tier cell east of the anchor (world x 0..3 in, z 0..3 in): the inner ring's +X spot is 18.8 mm past the cliff,
    /// outside its wall band - red before the rule: the model came back ON the raised cell. Now the spot is on the anchor's level.
    #[test]
    fn a_revive_never_comes_back_across_a_tier_step() {
        let (st, statics) = rean_line(2, 1, &[[-0.6, 1.5]]);
        let mut p: crate::terrain::PlainTerrain = serde_json::from_value(serde_json::json!({"cells": [], "sandbox": [],
            "cell_params": {"table_size_feet": [6.0, 4.0], "grid_rotation_degrees": 0.0, "grid_size_inches": 3.0, "inches_to_meters": IN2M}})).unwrap();
        let mut level = vec![0.0; 384];
        level[8 * 24 + 12] = 3.0;
        p.tiers = Some(crate::terrain::TierGrid { nx: 24, nz: 16, cell_in: 3.0, level_in: level, ladders: vec![], stairs: vec![] });
        let t = crate::terrain::Terrain::build(&p);
        let (next, shot) = rean_run(&st, &statics, &t, E96, 1, false);
        assert_eq!(next.alive[0], 2, "{:?}", shot.log);
        let b = next.positions[0][0];
        assert_eq!(t.tier_in_at(b[0] / IN2M, b[2] / IN2M), 0.0, "on the anchor's level: {b:?}");
    }

    /// TICKET REVIVE-ROOF (pinned, not fixed): a unit standing on a container ROOF gets nobody back - every ring spot near it is
    /// `rest_forbidden` (the container class refuses a rest from the ground's point of view). The pin breaks when the ticket lands.
    #[test]
    fn pin_a_unit_on_a_container_roof_gets_nobody_back() {
        let roof = [[5.0, 4.5], [7.0, 4.5]];
        let (st, statics) = rean_line(3, 1, &roof);
        let (next, shot) = rean_run(&st, &statics, &container_board(true), E96, 1, false);
        assert_eq!(next.alive[0], 2, "{:?}", shot.log);
        assert!(refused(&shot), "{:?}", shot.log);
    }

    // ------------- Step 3: the spend order (lead ruling (a) = the table's order, as a convention) -----------------------

    /// A seed whose Reanimation roll at target 5 shows exactly `hits` successes (the roll is the same at 95 and 96).
    fn seed_with(st: &State, statics: &[UnitStatic], t: &crate::terrain::Terrain, heroes: bool, dice: usize, hits: usize) -> i64 {
        (0..500).find(|&s| rean_run(st, statics, t, 95, s, heroes).1.log.iter()
            .any(|l| l.contains(&format!("rolls {dice} dice")) && l.contains(&format!("— {hits} success(es)"))))
            .expect("a seed with the wanted hit count")
    }

    /// Two dead Tough(3) and 2 successes: at 96 both stand up at one wound (95: one model at 2 wounds, the pin); with 4
    /// successes the first is topped up to 3 and the second stays at 1 - casualties first, top-ups after, in that order.
    #[test]
    fn casualties_stand_up_at_one_wound_before_any_top_up() {
        let (st, mut statics) = rean_line(4, 3, &L3[..2]);
        statics[0].reanimation = Some(crate::unit::ReanimationSpec { target: 5 });
        let t = town_board(vec![]);
        let two = seed_with(&st, &statics, &t, false, 6, 2);
        let (next, shot) = rean_run(&st, &statics, &t, E96, two, false);
        assert_eq!((next.alive[0], next.wounds[0].clone()), (4, vec![1, 1, 3, 3]), "{:?}", shot.log);
        let (old, _) = rean_run(&st, &statics, &t, 95, two, false);
        assert_eq!((old.alive[0], old.wounds[0].clone()), (3, vec![2, 3, 3]), "95 pin");
        let four = seed_with(&st, &statics, &t, false, 6, 4);
        let (next, shot) = rean_run(&st, &statics, &t, E96, four, false);
        assert_eq!((next.alive[0], next.wounds[0].clone()), (4, vec![1, 3, 3, 3]), "{:?}", shot.log);
    }

    /// An entry with no legal spot EXPIRES: the host's casualty (a 100 mm base) fits nowhere in a 6 in square walled by
    /// houses, the joined hero's (32 mm) does. 2 successes on 4 dice: the plan gives one to each casualty; the host's is
    /// lost, so the hero stands up at ONE wound, not two.
    #[test]
    fn an_unplaceable_casualty_s_success_is_lost() {
        let (mut st, mut statics) = rean_line(3, 1, &[[2.25, 3.0], [3.75, 3.0]]);
        let mut hero = st.profiles.list[1].clone();
        hero.unit_id = "ah".into();
        hero.wounds_max = vec![3];
        st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(), st.profiles.list[1].clone(), hero], index: HashMap::new() });
        st.roster = Rc::new(Roster { keys: st.roster.keys.clone(), index: st.roster.index.clone(), profile: vec![0, 2, 1, 1] });
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        st.positions[1] = vec![];
        st.wounds[1] = vec![];
        st.alive[1] = 0;
        Rc::make_mut(&mut st.radii)[1] = vec![];
        statics[0].base_radius = 0.05; // the returning host model's base; the two standing ones are 32 mm
        statics[0].reanimation = Some(crate::unit::ReanimationSpec { target: 5 });
        statics.push(UnitStatic { name: "hero".into(), base_radius: 0.016, reanimation: Some(crate::unit::ReanimationSpec { target: 5 }), ..Default::default() });
        let mut walls = Vec::new();
        for x in 11..=14u16 {
            for z in 7..=10u16 {
                if !((12..=13).contains(&x) && (8..=9).contains(&z)) {
                    walls.push(z * 24 + x);
                }
            }
        }
        let t = town_board(walls);
        let s = seed_with(&st, &statics, &t, true, 4, 2);
        let (next, shot) = rean_run(&st, &statics, &t, E96, s, true);
        assert_eq!(next.alive[0], 2, "the host's casualty has no spot: {:?}", shot.log);
        assert!(refused(&shot), "{:?}", shot.log);
        assert_eq!((next.alive[1], next.wounds[1].clone()), (1, vec![1]), "the host's success is gone: {:?}", shot.log);
    }

    // ------------- Step 4: inert below 96 -----------------------------------------------------------------------------

    /// Below 96 nothing moves: at epochs 7 (the rule's port), 73 and 95 the container board gives the old single
    /// away-from-centre spot, the default radius and the same log at every epoch; a Tough(3) pair keeps the old spend.
    #[test]
    fn revive_spot_is_inert_below_96() {
        let (st, statics) = rean_line(4, 1, &L3);
        let t = container_board(true);
        let old_spot = [2.0 * IN2M + 0.034, 0.0, 4.5 * IN2M];
        let (base, base_log) = rean_run(&st, &statics, &t, 95, 1, false);
        let p = base.positions[0][0];
        assert!((0..3).all(|i| (p[i] - old_spot[i]).abs() < 1e-6) && base.radii[0][0] == DEFAULT_BASE_RADIUS_M, "{p:?}");
        for e in [crate::acts::EPOCH_7_TABLE_RULES, crate::acts::EPOCH_73_V36] {
            let (next, shot) = rean_run(&st, &statics, &t, e, 1, false);
            assert_eq!((&next.positions, &next.radii, &next.wounds), (&base.positions, &base.radii, &base.wounds), "epoch {e}");
            assert_eq!(shot.log, base_log.log, "epoch {e}");
        }
        let (st, mut statics) = rean_line(4, 3, &L3[..2]);
        statics[0].reanimation = Some(crate::unit::ReanimationSpec { target: 1 });
        for e in [crate::acts::EPOCH_7_TABLE_RULES, crate::acts::EPOCH_73_V36, 95] {
            assert_eq!(rean_run(&st, &statics, &t, e, 1, false).0.wounds[0], vec![3, 3, 3, 3], "epoch {e}: 6 successes fill both");
        }
    }
