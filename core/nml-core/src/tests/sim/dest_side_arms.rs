use super::*;

    // ---------------------------------------------- S10: dest-side arms ----

    /// S10-a — the in-range shooter's kite: 20" from a 24" gun with a 6"
    /// Advance grants exactly min(6, 24 - 20 - 0.25) = 3.75", aimed at the
    /// enemy centre MIRRORED through the mover; an enemy inside the 0.25"
    /// range-edge margin floors the step and the table stands still.
    #[test]
    fn s10_kite_grants_the_tables_distance_and_aims_away() {
        let (st, statics) = s10_line();
        let centre = geom::centre(&st.positions[0]);
        // 100" due west OF THE UNIT: the retreat candidate's own dest shape
        let dest = [(30.0 - RETREAT_GOAL_IN) * IN2M, 0.0, 24.0 * IN2M];
        let mut hold = false;
        let (goal, band) = s10_dest_arms(&statics, &st, 0, ADVANCE, dest, 6.0, &mut hold);
        assert!(!hold);
        assert!((band - 3.75).abs() < 1e-4);
        assert!((goal[0] - (centre[0] as f64 - 20.0 * IN2M)).abs() < 1e-5);
        let mut st2 = st.clone();
        st2.positions[2] = vec![[(30.0 + 23.9) * IN2M, 0.0, 24.0 * IN2M]];
        let mut hold2 = false;
        let (_, band2) = s10_dest_arms(&statics, &st2, 0, ADVANCE, dest, 6.0, &mut hold2);
        assert!(hold2 && band2 == 0.0);
    }

    /// S10-b — the goal stop: a RUSH whose dest IS a marker is granted
    /// min(band, goal_dist) (12" band, marker 5" away -> 5"); a dest that is
    /// no marker (the toward-enemy else-branch) keeps the full band.
    #[test]
    fn s10_goal_stop_ends_the_move_at_the_marker() {
        let (st, statics) = s10_line();
        let marker = st.objectives[0].pos;
        let mut hold = false;
        let (dest, band) = s10_dest_arms(&statics, &st, 0, RUSH, marker, 12.0, &mut hold);
        assert!(!hold);
        assert!((band - 5.0).abs() < 1e-4);
        assert_eq!(dest, marker);
        let enemy_centre = [(30.0 + 20.0) * IN2M, 0.0, 24.0 * IN2M];
        let (_, band_far) = s10_dest_arms(&statics, &st, 0, RUSH, enemy_centre, 12.0, &mut hold);
        assert!((band_far - 12.0).abs() < 1e-4);
    }

    /// S10-a through the routing (movement=table): the in-range shooter's
    /// ADVANCE with the 100" retreat dest moves exactly the table's 3.75"
    /// kite step, not the full band.
    #[test]
    fn s10_kite_routing_moves_the_shooter_the_tables_distance() {
        let (st, statics) = s10_line();
        let board = crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells: vec![],
            sandbox: Vec::<crate::terrain::Obb>::new(),
            pieces: vec![],
            walls: vec![],
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        });
        let dest = [(30.0 - RETREAT_GOAL_IN) * IN2M, 0.0, 24.0 * IN2M];
        let action = Action {
            kind: ADVANCE,
            unit: "a".into(),
            dest: Some(dest),
            shoot: None,
            charge: None,
            patient: false,
            split: None,
            traced: None,
        };
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { movement: true, ..Seams::default() };
        let next = resolve_stochastic_on_board(
            &statics, &st, &action, &board, seams, &mut rng,
        )
        .unwrap();
        let dx = st.positions[0][0][0] - next.positions[0][0][0];
        assert!((dx / IN2M - 3.75).abs() < 0.05, "moved {} in", dx / IN2M);
    }
