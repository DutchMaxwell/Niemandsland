use super::*;
use crate::mv::legal::{beyond_allowance, rest_illegal, Illegal};

    // ------------------- PLAN_FIRST_DELETION step 3a: the legality checker, one planted fixture per rule ---

    /// Up to four units on `buff_line`'s roster, each `(player, base radius in, model centres in)`; the rest stay off the table.
    fn placed(units: &[(i64, f64, &[[f64; 2]])]) -> State {
        let (mut st, _) = buff_line();
        st.attached = Rc::new(vec![vec![]; 4]);
        st.attached_to = Rc::new(vec![None; 4]);
        let (mut pos, mut radii) = (vec![vec![]; 4], vec![vec![]; 4]);
        st.alive = vec![0; 4];
        for (u, (side, r, pts)) in units.iter().enumerate() {
            pos[u] = pts.iter().map(|p| [p[0] * IN2M, 0.0, p[1] * IN2M]).collect();
            radii[u] = vec![r * IN2M; pts.len()];
            st.alive[u] = pts.len() as i64;
            st.player[u] = *side;
        }
        st.positions = pos;
        st.radii = Rc::new(radii);
        st
    }

    fn kinds(found: &[Illegal]) -> Vec<&'static str> {
        let mut k: Vec<_> = found.iter().map(|i| i.kind).collect();
        k.dedup();
        k
    }

    /// A unit of two linked models, a friend far off, an enemy 4" away: nothing to report. Every planted variant below
    /// starts from this board and changes one thing, so each rule is shown able to fail on its own.
    const OWN: [[f64; 2]; 2] = [[0.0, 0.0], [0.0, 2.2]];
    const FOE: [[f64; 2]; 3] = [[6.0, -1.1], [6.0, 1.1], [6.0, 3.3]];

    #[test]
    fn a_legal_board_reads_empty() {
        let st = placed(&[(0, 1.0, &OWN), (0, 1.0, &[[30.0, 20.0]]), (1, 1.0, &FOE)]);
        assert_eq!(rest_illegal(&st, &small_board(), &[0, 1, 2]), vec![]);
        assert_eq!(beyond_allowance(&st, 0, &st.positions[0].clone(), 0.0), vec![]);
    }

    #[test]
    fn an_overlap_with_another_unit_or_inside_the_own_unit_is_reported_once() {
        let st = placed(&[(0, 1.0, &OWN), (0, 1.0, &[[-1.5, 0.0]]), (1, 1.0, &FOE)]);
        let found = rest_illegal(&st, &small_board(), &[0, 1]);
        assert_eq!(found.len(), 1, "{found:?}");
        assert_eq!((found[0].kind, found[0].other), ("overlap", Some((1, 0))));
        assert!((found[0].by_in - 0.5).abs() < 1e-4, "{found:?}");
        let own = placed(&[(0, 1.0, &[[0.0, 0.0], [0.0, 1.5]]), (1, 1.0, &FOE)]);
        assert_eq!(kinds(&rest_illegal(&own, &small_board(), &[0])), vec!["overlap"]);
    }

    #[test]
    fn a_base_on_a_container_or_a_solid_cell_rests_on_forbidden_ground() {
        let t = crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells: vec![[13.0, 14.0, crate::terrain::CONTAINER as f64], [13.0, 15.0, crate::terrain::CONTAINER as f64]],
            sandbox: vec![], pieces: vec![], containers: Vec::new(), walls: vec![],
            cell_params: crate::terrain::CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: IN2M },
            ..Default::default()
        });
        let on = placed(&[(0, 1.0, &[[-3.0, 0.0], [-3.0, 2.2]]), (1, 1.0, &FOE)]);
        assert_eq!(kinds(&rest_illegal(&on, &t, &[0])), vec!["forbidden_rest"]);
        assert_eq!(rest_illegal(&placed(&[(0, 1.0, &OWN), (1, 1.0, &FOE)]), &t, &[0]), vec![], "beside the block");
        // A 1 ft board, 4 x 4 tier cells of 3": cell 5 spans x, z in [-3", 0") and is an intact house.
        let mut p: crate::terrain::PlainTerrain = serde_json::from_value(serde_json::json!({"cells": [], "sandbox": [],
            "cell_params": {"table_size_feet": [1.0, 1.0], "grid_rotation_degrees": 0.0, "grid_size_inches": 3.0,
                "inches_to_meters": IN2M}})).unwrap();
        p.tiers = Some(crate::terrain::TierGrid { nx: 4, nz: 4, cell_in: 3.0, level_in: vec![0.0; 16], ladders: vec![], stairs: vec![] });
        p.solid_cells = vec![5];
        let house = crate::terrain::Terrain::build(&p);
        assert_eq!(kinds(&rest_illegal(&placed(&[(0, 0.5, &[[-1.5, -1.5]])]), &house, &[0])), vec!["forbidden_rest"]);
        assert_eq!(rest_illegal(&placed(&[(0, 0.5, &[[4.5, 4.5]])]), &house, &[0]), vec![], "a free cell");
    }

    #[test]
    fn a_base_past_the_table_edge_is_off_board() {
        let st = placed(&[(0, 1.0, &[[35.5, 0.0], [35.5, 2.2]]), (1, 1.0, &FOE)]);
        let found = rest_illegal(&st, &small_board(), &[0]);
        assert_eq!(kinds(&found), vec!["off_board"]);
        assert!((found[0].by_in - 0.5).abs() < 1e-4, "{found:?}");
    }

    #[test]
    fn a_model_beyond_the_one_inch_chain_breaks_coherency() {
        let st = placed(&[(0, 1.0, &[[0.0, 0.0], [0.0, 2.2], [0.0, 6.0]]), (1, 1.0, &[[12.0, 0.0]])]);
        let found = rest_illegal(&st, &small_board(), &[0]);
        assert_eq!(found, vec![Illegal { unit: 0, model: 2, kind: "coherency", other: None, by_in: 0.0 }]);
    }

    #[test]
    fn an_enemy_within_one_inch_is_reported_unless_the_units_are_in_base_contact() {
        let near = placed(&[(0, 1.0, &OWN), (1, 1.0, &[[2.5, 0.0]])]);
        assert_eq!(kinds(&rest_illegal(&near, &small_board(), &[0])), vec!["enemy_within_1in"]);
        let fighting = placed(&[(0, 1.0, &OWN), (1, 1.0, &[[2.0, 0.0]])]);
        assert_eq!(rest_illegal(&fighting, &small_board(), &[0]), vec![], "base contact = melee");
    }

    #[test]
    fn a_model_moved_past_its_allowance_is_reported() {
        let from = placed(&[(0, 1.0, &OWN)]).positions[0].clone();
        let st = placed(&[(0, 1.0, &[[-3.5, 0.0], [-2.9, 2.2]])]);
        let found = beyond_allowance(&st, 0, &from, 3.0);
        assert_eq!(found.len(), 1, "{found:?}");
        assert_eq!((found[0].model, found[0].kind), (0, "distance"));
        assert!((found[0].by_in - 0.5).abs() < 1e-4);
    }

    /// The real case (ds/shootpos.md, gate-12 shoot soak game 3, Dark Shooters r4 -> Deep-Sea Artillery; board rebuilt from the
    /// shootfix probe's dump of that step, 25 mm bases): the core's rigid 3" Harassing kite ends five of the seven models inside
    /// the friendly Corsairs, the deepest 0.75". The table's end of the same step (the gate row's `table` list) reads clean.
    #[test]
    fn the_game_3_harassing_kite_ends_inside_the_corsairs() {
        let r = 0.492126;
        let core = [[12.053220, -7.489779], [13.605719, -6.289386], [12.982194, -7.164660], [12.605718, -5.289386],
            [11.718017, -6.085439], [11.605716, -4.289386], [12.098351, -3.289385]];
        let table = [[14.6123, -5.296053], [14.9475, -6.700394], [15.5, -4.5], [15.94721, -5.394427], [16.46354, -9.317274],
            [16.5, -7.500001], [16.5, -6.5]];
        let corsairs = [[10.500001, -6.500000], [12.500000, -4.500000], [12.516530, -6.498777], [12.500000, -7.500001],
            [13.898001, -8.544861], [11.137508, -4.862494], [11.534771, -6.571534], [12.500000, -5.500001]];
        let artillery = [[31.499999, -0.485201]];
        let found = rest_illegal(&placed(&[(0, r, &core), (0, r, &corsairs), (1, 1.181102, &artillery)]), &small_board(), &[0]);
        assert_eq!(kinds(&found), vec!["overlap"], "{found:?}");
        let mut inside: Vec<usize> = found.iter().filter(|i| i.other.is_some_and(|o| o.0 == 1)).map(|i| i.model).collect();
        inside.dedup();
        assert_eq!(inside, vec![0, 2, 3, 4, 5], "{found:?}");
        let deepest = found.iter().map(|i| i.by_in).fold(0.0, f64::max);
        assert!((deepest - 0.749).abs() < 0.002, "deepest {deepest}");
        assert_eq!(rest_illegal(&placed(&[(0, r, &table), (0, r, &corsairs), (1, 1.181102, &artillery)]), &small_board(), &[0]), vec![]);
    }

    /// SEPARATE-1IN (ds/meleepos.md sweep row B, seed 3, Heavy Gunners -> Reapers, 32 mm bases): after the 1" back-step
    /// neither side's charger ends 1" clear of the two surviving defenders - both read `enemy_within_1in`. Moved 0.5" further
    /// back, the same models read clean.
    #[test]
    fn the_separation_short_of_one_inch_reads_illegal_on_both_sides() {
        let r = 0.016 / IN2M;
        let foe = [[6.612481, 1.624002], [6.942574, 0.045562]];
        let table = [[4.951879, 0.667729], [5.232725, -0.560408], [5.297877, -1.860167], [5.349883, -3.119135]];
        let core = [[4.821950, 0.923135], [5.012427, -0.322224], [5.349667, -3.113927], [5.423549, -1.627735]];
        for side in [table, core] {
            assert_eq!(kinds(&rest_illegal(&placed(&[(0, r, &side), (1, r, &foe)]), &small_board(), &[0])), vec!["enemy_within_1in"]);
            let back: Vec<[f64; 2]> = side.iter().map(|p| [p[0] - 0.5, p[1]]).collect();
            assert_eq!(rest_illegal(&placed(&[(0, r, &back), (1, r, &foe)]), &small_board(), &[0]), vec![]);
        }
    }

    /// 3b: the `done` step's `illegal` list reads only the units whose surviving models moved. A unit that only lost a
    /// model is not listed even when the loss broke its chain (the checker itself does read it); a moved unit is.
    #[test]
    fn the_landing_list_reads_the_moved_units_only() {
        let before = placed(&[(0, 1.0, &OWN), (0, 1.0, &[[-6.0, 6.0], [-6.0, 8.2], [-6.0, 10.4]]), (1, 1.0, &FOE)]);
        let mut after = before.clone();
        after.positions[1].remove(1);
        after.alive[1] = 2;
        assert_eq!(kinds(&rest_illegal(&after, &small_board(), &[1])), vec!["coherency"], "the fixture: the loss broke the chain");
        assert_eq!(crate::mv::legal::landing_illegal(&before, &after, &small_board()), vec![], "a casualty alone moves nobody");
        after.positions[0][0] = [5.0 * IN2M, 0.0, -1.1 * IN2M];
        let found = crate::mv::legal::landing_illegal(&before, &after, &small_board());
        assert!(!found.is_empty() && found.iter().all(|i| i.unit == 0), "{found:?}");
        assert!(found.iter().any(|i| i.kind == "overlap" && i.other == Some((2, 0))), "{found:?}");
    }
