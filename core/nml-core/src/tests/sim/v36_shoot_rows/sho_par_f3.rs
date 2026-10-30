use super::super::*;

    // ---- SHO-PAR-F3: a moved shooter's target gate asks the per-model 3D sight ----

    /// A 6x4 board (30x30 grid of 3" cells, school cell 15 = world cell 0) with FOREST in school column 18
    /// (x 9..12") on the school rows `z`.
    fn sho_par_f3_board(z: std::ops::RangeInclusive<i64>) -> crate::terrain::Terrain {
        use crate::terrain::{CellParams, PlainTerrain, FOREST};
        crate::terrain::Terrain::build(&PlainTerrain {
            cells: z.map(|r| [18.0, r as f64, FOREST as f64]).collect(),
            sandbox: vec![],
            pieces: vec![],
            walls: vec![],
            cell_params: CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    /// "a" (two models 18" apart across the line of fire) advances 3" east to x = 0, z = -9 / +9 and fires
    /// its rifles at "b", 18" further east with models at z = -9, 0 and +9.
    fn sho_par_f3_volley(terrain: &crate::terrain::Terrain, epoch: u32) -> (State, ShootResult) {
        let (mut st, statics) = buff_line();
        st.positions[0] = vec![[-3.0 * IN2M, 0.0, 9.0 * IN2M], [-3.0 * IN2M, 0.0, -9.0 * IN2M]];
        st.positions[2] = vec![
            [18.0 * IN2M, 0.0, 9.0 * IN2M], [18.0 * IN2M, 0.0, 0.0], [18.0 * IN2M, 0.0, -9.0 * IN2M],
        ];
        let mut act = advance_shoot("b");
        act.dest = Some([0.0, 0.0, 0.0]);
        let seams = Seams { moved_shoot: true, rules_epoch: epoch, ..Default::default() };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(&statics, &st, &act, terrain, seams, &mut rng, &mut tray)
            .expect("the moved volley resolves")
    }

    fn sho_par_f3_attack_dice(shot: &ShootResult) -> i64 {
        shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "a").map(|r| r.count).sum()
    }

    /// The premise: after the move a wood on school rows 14..=15 (z -3..3") sits on the grid line between the
    /// two unit centres, while the z = +9 model pair looks past it in 3D.
    #[test]
    fn a_wood_between_the_centres_blocks_only_the_grid_line() {
        let terrain = sho_par_f3_board(14..=15);
        let (next, _) = sho_par_f3_volley(&terrain, crate::acts::EPOCH_72_PLAYTEST_RULES);
        assert!((next.positions[0][0][0] / IN2M).abs() < 1e-6, "the shooter advanced to x = 0");
        assert!(terrain.los_blocked(geom::centre(&next.positions[0]), geom::centre(&next.positions[2])));
        assert!(crate::sight::unit_sees(&next, &crate::sight::zones_of(&terrain), 0, 2));
    }

    /// RED on main: the moved shooter rolled nothing, although two of its models see the target past the wood.
    #[test]
    fn a_moved_shooter_fires_past_a_wood_it_sees_beside_at_epoch_73() {
        let (_, shot) = sho_par_f3_volley(&sho_par_f3_board(14..=15), crate::acts::EPOCH_73_V36);
        assert_eq!(sho_par_f3_attack_dice(&shot), 2, "both rifles fire after the advance (RED on main: 0)");
    }

    /// The old leg: epoch 72 keeps the coarse grid centre line, so the same advance rolls nothing.
    #[test]
    fn a_moved_shooter_keeps_the_grid_line_at_epoch_72() {
        let (_, shot) = sho_par_f3_volley(&sho_par_f3_board(14..=15), crate::acts::EPOCH_72_PLAYTEST_RULES);
        assert!(shot.rolls.is_empty(), "epoch 72 replays the grid gate: no shot");
    }

    /// The 3D test can still refuse: a wood across every model line (z -12..12") leaves the moved shooter
    /// without a target at epoch 73 too (control: passes with and without the change).
    #[test]
    fn a_moved_shooter_behind_a_wide_wood_still_has_no_shot_at_epoch_73() {
        let (_, shot) = sho_par_f3_volley(&sho_par_f3_board(11..=18), crate::acts::EPOCH_73_V36);
        assert!(shot.rolls.is_empty(), "no model sees the target through the wood");
    }
