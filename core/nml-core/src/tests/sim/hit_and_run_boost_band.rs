use super::*;

    // ------------------------------------- BLOCK B5 boost: the 6" BAND (w4) ---

    /// Wave 4 (rules-wave4-boostbases) — the "Guerrilla Boost" carrier (gf/
    /// rebel_guerrillas, the entry's own `move_in: 6`) steps 6" after its
    /// shot and names its own spelling in the battle-log twin; the epoch-5
    /// build of the same carrier keeps the base 3" band and the base line,
    /// byte-exact. RED if the fold keeps the shared const.
    #[test]
    fn guerrilla_boost_carrier_steps_six_inches_at_epoch_6() {
        let terrain = crate::terrain::Terrain::default();
        let (st, statics) =
            boost_line("gf", "rebel_guerrillas", &["Guerrilla", "Guerrilla Boost"], 6);
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.hit_and_run_round[0], next.round, "the Boost carrier still hit-and-runs");
        for (got, before) in next.positions[0].iter().zip(st.positions[0].iter()) {
            assert!(
                (got[0] - (before[0] - 6.0 * IN2M as f64)).abs() < 1e-6,
                "the Boost band is 6\", got {got:?}"
            );
        }
        assert!(
            shot.log.iter().any(|l| l.contains("Guerrilla Boost: a steps up to 6\"")),
            "rules-must-log: the Boost names itself (RED before the fix)"
        );

        // The epoch-5 build of the same carrier: the base band, byte-exact.
        let (st5, statics5) =
            boost_line("gf", "rebel_guerrillas", &["Guerrilla", "Guerrilla Boost"], 5);
        let mut tray5 = Tray::seeded(11);
        let mut rng5 = crate::rng::GodotRng::new(0);
        let (next5, shot5) = resolve_stochastic_tray_on_board(
            &statics5, &st5, &buff_action(Some("b")), &terrain, Seams::default(), &mut rng5, &mut tray5,
        )
        .unwrap();
        for (got, before) in next5.positions[0].iter().zip(st5.positions[0].iter()) {
            assert!((got[0] - (before[0] - 3.0 * IN2M as f64)).abs() < 1e-6, "got {got:?}");
        }
        assert!(
            shot5.log.iter().any(|l| l.contains("Hit & Run: a steps up to 3\"")),
            "epoch 5: the base line, byte-exact"
        );
    }

    /// The "Harassing Boost" spelling (gf/dark_elf_raiders): the same 6" band
    /// at epoch 6; WITHOUT the Boost the base "Harassing" carrier keeps the
    /// shared 3" const — the Boost band only lands on a real Boost carrier.
    #[test]
    fn harassing_boost_carrier_steps_six_inches_at_epoch_6() {
        let terrain = crate::terrain::Terrain::default();
        let (st, statics) =
            boost_line("gf", "dark_elf_raiders", &["Harassing", "Harassing Boost"], 6);
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.hit_and_run_round[0], next.round, "the Boost carrier still hit-and-runs");
        for (got, before) in next.positions[0].iter().zip(st.positions[0].iter()) {
            assert!(
                (got[0] - (before[0] - 6.0 * IN2M as f64)).abs() < 1e-6,
                "the Boost band is 6\", got {got:?}"
            );
        }
        assert!(
            shot.log.iter().any(|l| l.contains("Harassing Boost: a steps up to 6\"")),
            "rules-must-log: the Boost names itself (RED before the fix)"
        );

        // Without the Boost: the base 3" const (still a Hit & Run carrier).
        let (stb, staticsb) = boost_line("gf", "dark_elf_raiders", &["Harassing"], 6);
        let mut trayb = Tray::seeded(11);
        let mut rngb = crate::rng::GodotRng::new(0);
        let (nextb, shotb) = resolve_stochastic_tray_on_board(
            &staticsb, &stb, &buff_action(Some("b")), &terrain, Seams::default(), &mut rngb, &mut trayb,
        )
        .unwrap();
        for (got, before) in nextb.positions[0].iter().zip(stb.positions[0].iter()) {
            assert!((got[0] - (before[0] - 3.0 * IN2M as f64)).abs() < 1e-6, "got {got:?}");
        }
        assert!(
            shotb.log.iter().any(|l| l.contains("Hit & Run: a steps up to 3\"")),
            "no Boost: the base line, byte-exact"
        );
    }

    /// RED for the fire gate, all built on the falls-short charge above (so
    /// `hnr_attacked` is true throughout and only the gate under test differs):
    /// without the rule, already spent this round, or no living enemy at all —
    /// every one leaves the bearer exactly where it started.
    #[test]
    fn hit_and_run_negative_cases() {
        let terrain = crate::terrain::Terrain::default();
        let charge = Action {
            kind: CHARGE, unit: "a".into(), dest: None, shoot: None,
            charge: Some("b".into()), patient: false, split: None, traced: None,
        };

        // No bearer.
        let (st, statics) = buff_line();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[0], st.positions[0]);

        // Already spent this round.
        let (mut st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        st.hit_and_run_round[0] = st.round;
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[0], st.positions[0]);

        // No living enemy: "b" and "bh" both down.
        let (mut st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        st.alive[2] = 0;
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &charge, &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[0], st.positions[0]);

        // HOLD with no shoot key: `hnr_attacked` is false, the function is
        // never even called (unlike the cases above, which reach it and bail).
        let (st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(None), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[0], st.positions[0]);
    }

    /// The board clamp, wired end-to-end (not just `axis_scale`'s own pure-math
    /// proof, `the_reposition_axis_scale_clamps_to_the_board_edge`): a bearer
    /// 1" short of the board's left edge, kiting further left, lands EXACTLY on
    /// the edge instead of running 2" off it.
    #[test]
    fn hit_and_run_clamps_the_kiting_step_to_the_board_edge() {
        let (mut st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        st.positions[0] = vec![[-35.0 * IN2M, 0.0, 0.0], [-35.0 * IN2M, 0.0, 0.0]];
        st.positions[1] = vec![[-35.0 * IN2M, 0.0, 0.0]];
        st.positions[2] = vec![[0.0, 0.0, 0.0], [0.02 * IN2M, 0.0, 0.0], [0.04 * IN2M, 0.0, 0.0]];
        let board = small_board();
        tray_hit_and_run(&statics, &mut st, 0, Seams::default(), Cover::Board(&board), false);
        assert!((st.positions[0][0][0] - (-36.0 * IN2M)).abs() < 1e-6, "got {:?}", st.positions[0]);
        assert_eq!(st.hit_and_run_round[0], st.round);
    }

    /// S11 — under `movement=table` the Hit & Run carrier lands through the
    /// SOLVER: on the mirrored forest the routed detour rests the models
    /// somewhere the rigid 3" translation never puts them, and the move names
    /// itself in the rules-must-log lines.
    #[test]
    fn hit_and_run_lands_through_the_solver_under_the_movement_seam() {
        let (st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        let t = kiting_forest_board();
        let action = buff_action(Some("b"));

        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (rigid, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &t, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (solved, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &t,
            Seams { movement: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert!(shot.log.iter().any(|l| l.contains("Hit & Run")), "rules-must-log: {:?}", shot.log);

        let gap_in = solved.positions[0]
            .iter()
            .zip(rigid.positions[0].iter())
            .map(|(a, b)| ((a[0] - b[0]).powi(2) + (a[2] - b[2]).powi(2)).sqrt() / IN2M as f64)
            .fold(0.0f64, f64::max);
        assert!(gap_in > 0.5, "the solver landed on the rigid answer, gap {gap_in}\"");
    }

    /// The RED for that routing: `move_rigid` puts the Hit & Run step back on
    /// the rigid arm with `movement` still on — the straight 3" translation to
    /// the digit, byte-identical to the seam-off run.
    #[test]
    fn the_move_rigid_red_returns_a_hit_and_run_step_to_the_straight_line() {
        let (st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        let t = kiting_forest_board();
        let action = buff_action(Some("b"));
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (rigid, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &t, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (red, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &t,
            Seams { movement: true, move_rigid: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(red.positions, rigid.positions);
    }

    /// The kiting anchor under the seam is the table's `_nearest_enemy_of`
    /// pick — plain nearest, NO activated preference: with an ACTIVATED enemy
    /// at 6" and an un-activated one at 12" the carrier steps away from the
    /// near one (the rigid arm keeps #485's pick and steps the other way).
    #[test]
    fn hit_and_run_kites_away_from_the_plain_nearest_enemy_under_the_seam() {
        let (mut st, mut statics) = buff_line();
        statics[0].hit_and_run_active = true;
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        st.alive[3] = 1;
        st.positions[2] =
            vec![[6.0 * IN2M, 0.0, 0.0], [6.02 * IN2M, 0.0, 0.0], [6.04 * IN2M, 0.0, 0.0]];
        st.positions[3] = vec![[-12.0 * IN2M, 0.0, 0.0]];
        st.activated[2] = true;
        let board = small_board();
        let action = buff_action(Some("b"));
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (rigid, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &board, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let (solved, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &action, &board,
            Seams { movement: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        // Rigid: away from the un-activated "bh" at -12" -> +3" along +x.
        // Solved: away from the plain-nearest "b" at +6" -> 3" along -x.
        assert!((rigid.positions[0][0][0] - (st.positions[0][0][0] + 3.0 * IN2M as f64)).abs()
            < 1e-6, "rigid {:?}", rigid.positions[0]);
        assert!((solved.positions[0][0][0] - (st.positions[0][0][0] - 3.0 * IN2M as f64)).abs()
            < 1e-6, "solved {:?}", solved.positions[0]);
        assert_eq!(solved.hit_and_run_round[0], solved.round);
    }
