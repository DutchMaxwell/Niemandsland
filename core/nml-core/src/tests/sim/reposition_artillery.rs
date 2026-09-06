use super::*;

    // ------------------------------ BLOCK B2: RE-POSITION ARTILLERY ---

    /// BLOCK B2 — no dice ride Re-Position Artillery at all, and the picked
    /// artillery is forced 9" straight toward `e1`, the FARTHER but
    /// not-yet-activated enemy, never toward the nearer `e2` who already
    /// acted this round.
    #[test]
    fn reposition_moves_the_undefended_artillery_toward_the_not_yet_activated_enemy() {
        let (st, statics) = reposition_line();
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &reposition_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert!(shot.rolls.is_empty(), "Re-Position Artillery is dice-free");
        let probe = Tray::seeded(7);
        assert_eq!(tray.state_i64(), probe.state_i64());
        let g_pos = next.positions[1][0];
        assert!((g_pos[0] - 13.0 * IN2M).abs() < 1e-6, "g at {g_pos:?}");
        assert_eq!(g_pos[2], 0.0);
    }

    /// RED for the pick: a shoot target already in range skips the move
    /// entirely; out of the 6" pick range there is no artillery to move at
    /// all; without the rule the bearer stays mute.
    #[test]
    fn reposition_skips_with_a_shoot_target_out_of_range_or_without_the_rule() {
        let terrain = crate::terrain::Terrain::default();
        let (st, mut statics) = reposition_line();
        statics[1].shoot = vec![ShootProfile { range: 30, ..Default::default() }];
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &reposition_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[1][0], st.positions[1][0]);

        let (mut st, statics) = reposition_line();
        st.positions[1] = vec![[20.0 * IN2M, 0.0, 0.0]]; // g walked out of the 6" pick ring
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &reposition_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[1][0], st.positions[1][0]);

        let (st, mut statics) = reposition_line();
        statics[0].reposition_artillery_active = false;
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &reposition_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next.positions[1][0], st.positions[1][0]);
    }

    /// `SoloController._axis_scale` solo_controller.gd:8911-8915, the pure
    /// board-edge clamp: inside the limit (or a zero step) the scale stays
    /// 1.0; stepping past it scales back to land EXACTLY on the edge.
    #[test]
    fn the_reposition_axis_scale_clamps_to_the_board_edge() {
        assert_eq!(axis_scale(0.0, 5.0, 10.0), 1.0);
        assert_eq!(axis_scale(0.0, 0.0, 10.0), 1.0);
        let s = axis_scale(8.0, 9.0, 10.0);
        assert!((8.0 + 9.0 * s - 10.0).abs() < 1e-4, "scale {s} overshoots the edge");
    }
