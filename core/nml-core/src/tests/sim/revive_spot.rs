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

    /// The covfix2-dice container: at 95 the model stands inside it (`pin95_a_revive_lands_in_a_container` is the
    /// red), at 96 it is not restored and the line says so. Planted: the open board restores at 96 too.
    #[test]
    fn a_revive_never_lands_in_a_container() {
        let (st, statics) = rean_line(4, 1, &L3);
        let (next, shot) = rean_run(&st, &statics, &container_board(true), E96, 1, false);
        assert_eq!(next.alive[0], 3, "{:?}", shot.log);
        assert!(refused(&shot), "rules-must-log: {:?}", shot.log);
        let (open, shot) = rean_run(&st, &statics, &container_board(false), E96, 1, false);
        assert_eq!(open.alive[0], 4, "planted: {:?}", shot.log);
    }

    /// The town house: at 96 no revive over a solid cell; planted: the same board without it restores.
    #[test]
    fn a_revive_never_lands_in_a_house() {
        let (st, statics) = rean_line(4, 1, &L3);
        let (next, shot) = rean_run(&st, &statics, &town_board(vec![cell_at(3.34, 4.5)]), E96, 1, false);
        assert_eq!(next.alive[0], 3, "{:?}", shot.log);
        assert!(refused(&shot), "rules-must-log: {:?}", shot.log);
        let (open, _) = rean_run(&st, &statics, &town_board(vec![]), E96, 1, false);
        assert_eq!(open.alive[0], 4, "planted");
    }

    /// The whole base stays on the table: at 95 the one spot hangs over the east edge, at 96 it is refused.
    #[test]
    fn a_revive_never_leaves_the_table() {
        let edge = [[33.5, 3.5], [33.5, 5.5], [34.5, 4.5]]; // the one spot is at 35.84 in, its base reaches 36.47 > 36
        let (st, statics) = rean_line(4, 1, &edge);
        let (old, _) = rean_run(&st, &statics, &town_board(vec![]), 95, 1, false);
        assert_eq!(old.alive[0], 4, "red: at 95 the base hangs over the table edge");
        let (next, shot) = rean_run(&st, &statics, &town_board(vec![]), E96, 1, false);
        assert_eq!(next.alive[0], 3, "{:?}", shot.log);
        assert!(refused(&shot), "{:?}", shot.log);
    }

    /// Own bases count at 96: the candidate on a unit mate is refused (at 95 they stack, see the fact pin).
    #[test]
    fn a_revive_never_stacks_on_its_own_unit() {
        let own = [[1.0, 3.5], [1.0, 5.5], [2.0, 4.5], [2.0 + 0.034 / IN2M, 4.5]];
        let (st, statics) = rean_line(5, 1, &own);
        let (next, shot) = rean_run(&st, &statics, &town_board(vec![]), E96, 1, false);
        assert_eq!(next.alive[0], 4, "{:?}", shot.log);
        assert!(refused(&shot), "{:?}", shot.log);
    }

    /// Difference 5: at 96 the returning model keeps its unit's own base radius; at 95 the default is pinned.
    #[test]
    fn a_restored_model_keeps_its_own_base() {
        let (mut st, mut statics) = rean_line(4, 1, &L3);
        st.radii = Rc::new(vec![vec![0.025; 3], vec![0.016], vec![0.016], vec![0.016]]);
        statics[0].base_radius = 0.025;
        let (next, _) = rean_run(&st, &statics, &town_board(vec![]), E96, 1, false);
        assert_eq!(next.alive[0], 4);
        assert_eq!(next.radii[0][0], 0.025);
        let b = next.positions[0][0];
        assert!(((b[0] - 2.0 * IN2M) - (0.025 + 0.025 + 0.002)).abs() < 1e-9, "the spot uses the real radius: {b:?}");
        let (old, _) = rean_run(&st, &statics, &town_board(vec![]), 95, 1, false);
        assert_eq!(old.radii[0][0], DEFAULT_BASE_RADIUS_M, "95 pin");
    }

    /// The guard draws no die: the same state at 95 and 96 on the open board ends in the same state, log and roll faces,
    /// and an unrelated unit's whole activation is untouched (its digest is identical at both epochs).
    #[test]
    fn revive_spot_changes_nothing_on_an_open_board_and_draws_no_die() {
        let (st, statics) = rean_line(4, 1, &L3);
        let (a, sa) = rean_run(&st, &statics, &town_board(vec![]), 95, 1, false);
        let (b, sb) = rean_run(&st, &statics, &town_board(vec![]), E96, 1, false);
        assert_eq!((a.positions.clone(), a.wounds.clone(), sa.log.clone()), (b.positions.clone(), b.wounds.clone(), sb.log.clone()));
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
