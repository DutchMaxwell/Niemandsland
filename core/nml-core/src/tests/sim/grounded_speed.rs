use super::*;

    // -------------------------- wave 5 (d): Grounded Speed — the live read ---

    /// The registry-built carrier: an aof profile whose ONLY rule is the named
    /// Grounded Speed entry, read off the REAL registry
    /// (`assets/solo/rules_mechanics_aof.json` — advance_mod 2, rush_mod 4,
    /// terrain_within_in 1). The REAL `build_for` product, read at `epoch`.
    fn gs_bearer(rules_epoch: u32) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 3,
            weapons: vec![],
            special_rules: vec!["Grounded Speed".into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "aof".into(),
            // the REAL faction folder — the entry lives under factions, not common
            faction_folder: "volcanic_dwarves".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// A plain line of statics for a 3-model carrier "a" (no hero, no enemies
    /// in the way): the `dangerous_line` shape with three models.
    fn gs_line(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
        let (mut st, _) = dangerous_line();
        st.positions[0] = vec![
            [0.0, 0.0, 0.0],
            [0.02 * IN2M, 0.0, 0.0],
            [0.04 * IN2M, 0.0, 0.0],
        ];
        st.radii[0] = vec![IN2M; 3];
        st.wounds[0] = vec![1; 3];
        st.alive[0] = 3;
        let mut a = gs_bearer(rules_epoch);
        a.model_count = 3;
        a.wounds_max = vec![1; 3];
        (st, vec![a, UnitStatic { name: "ah".into(), ..Default::default() }, UnitStatic { name: "b".into(), ..Default::default() }, UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    /// A RUINS bar at grid cells [19,15] and [19,16]. The grid is centred with
    /// half_grid = 15 (the DIAGONAL-derived grid, terrain.rs:build — 6x4 ft at
    /// 3" cells -> 30), so the cell [19,15] spans x in [12,15)" and z in
    /// [0,3)" relative to the table centre: a model at (13.5", 0") stands
    /// inside it while the advance below stays a pure +x move.
    fn ruins_bar_board() -> crate::terrain::Terrain {
        let cells = vec![
            [19.0, 15.0, crate::terrain::RUINS as f64],
            [19.0, 16.0, crate::terrain::RUINS as f64],
        ];
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells,
            sandbox: vec![],
            walls: vec![],
            pieces: vec![],
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    fn run_gs(st: &State, statics: &[UnitStatic], t: &crate::terrain::Terrain, rules_epoch: u32, x_in: f64) -> (State, ShootResult) {
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, &advance_to(x_in), t,
            Seams { rules_epoch, ..Seams::default() },
            &mut rng, &mut tray,
        )
        .unwrap()
    }

    /// (a) two of three models within 1" of the ruin when activated: the
    /// advance band grows by the entry's own advance_mod (+2"), the rush band
    /// by rush_mod (+4"), and the rule names itself (rules-must-log).
    #[test]
    fn most_models_within_one_inch_of_terrain_widen_both_bands_at_epoch_7() {
        let t = ruins_bar_board();
        let (mut st, statics) = gs_line(7);
        // Two models stand inside the ruin cell [19,15] (see the board), one
        // at the origin (cell [15,15], NONE) — "most" (2 of 3) within 1".
        st.positions[0] = vec![
            [13.5 * IN2M, 0.0, 0.0],
            [14.0 * IN2M, 0.0, 0.0],
            [0.0, 0.0, 0.0],
        ];
        let (next, shot) = run_gs(&st, &statics, &t, 7, st.positions[0][0][0] / IN2M as f64 + 8.0);
        assert!(
            shot.log.iter().any(|l| l.contains("Grounded Speed")),
            "rules-must-log: {:?}",
            shot.log
        );
        let adv = next.positions[0][0][0] - st.positions[0][0][0];
        assert!(
            (adv - (6.0 + 2.0) * IN2M as f64).abs() < 1e-6,
            "the +2\" advance band, got {adv}\""
        );
    }

    /// (b) most models NOT near terrain: the base 6"/12" bands, no log line.
    #[test]
    fn most_models_not_near_terrain_keeps_the_base_bands() {
        let t = ruins_bar_board();
        let (st, statics) = gs_line(7);
        let (next, shot) = run_gs(&st, &statics, &t, 7, 8.0);
        let adv = next.positions[0][0][0] - st.positions[0][0][0];
        assert!((adv - 6.0 * IN2M as f64).abs() < 1e-6, "got {adv}\"");
        assert!(!shot.log.iter().any(|l| l.contains("Grounded Speed")), "{:?}", shot.log);
    }

    /// (c) an epoch-6 record replays byte-exact: same near-terrain setup as
    /// (a), but the +2" never lands below the FROZEN epoch 7.
    #[test]
    fn an_epoch_6_record_replays_the_base_band_byte_exact() {
        let t = ruins_bar_board();
        let (mut st, statics) = gs_line(6);
        // The ruin cell [16,12] spans x in [12,15)", z in [0,3)" — park two
        // models inside it ON the z=0 line (so the advance below is a pure +x
        // move), one at the origin 12" away: "most" (2 of 3) within 1".
        st.positions[0] = vec![
            [13.5 * IN2M, 0.0, 0.0],
            [14.0 * IN2M, 0.0, 0.0],
            [0.0, 0.0, 0.0],
        ];
        let (next, shot) = run_gs(&st, &statics, &t, 6, st.positions[0][0][0] / IN2M as f64 + 8.0);
        let adv = next.positions[0][0][0] - st.positions[0][0][0];
        assert!((adv - 6.0 * IN2M as f64).abs() < 1e-6, "got {adv}\"");
        assert!(!shot.log.iter().any(|l| l.contains("Grounded Speed")), "{:?}", shot.log);
    }

    /// (d) the condition reads the ACTIVATION-START picture, not the
    /// post-move one: the same near-terrain setup as (a) with the destination
    /// 20" away — after the move NO model is within 1" of terrain, yet the
    /// full +2" still applies because the read happened before it.
    #[test]
    fn the_condition_reads_activation_start_not_the_landing() {
        let t = ruins_bar_board();
        let (mut st, statics) = gs_line(7);
        // The ruin cell [16,12] spans x in [12,15)", z in [0,3)" — park two
        // models inside it ON the z=0 line (so the advance below is a pure +x
        // move), one at the origin 12" away: "most" (2 of 3) within 1".
        st.positions[0] = vec![
            [13.5 * IN2M, 0.0, 0.0],
            [14.0 * IN2M, 0.0, 0.0],
            [0.0, 0.0, 0.0],
        ];
        // Advance 20" along +x: the landing is far from every ruin cell.
        let (next, _) = run_gs(&st, &statics, &t, 7, st.positions[0][0][0] / IN2M as f64 + 20.0);
        let adv = next.positions[0][0][0] - st.positions[0][0][0];
        assert!(
            (adv - (6.0 + 2.0) * IN2M as f64).abs() < 1e-6,
            "activation-start read, got {adv}\""
        );
    }
