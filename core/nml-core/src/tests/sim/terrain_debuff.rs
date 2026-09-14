use super::*;

    // ---- STANDALONE_SWEEP_A_2026-09-14, rows `Dangerous Terrain Debuff` /
    //      `Difficult Terrain Debuff`: the debuffs promise a hazard that never
    //      happens ------------------------------------------------------------

    /// One recorded "Dangerous/Difficult Terrain Debuff" runtime record — the
    /// Utility-Buff shape whose `grants_rule` lands on the TARGET's ledger
    /// (`record_buff`, sim.rs) and as the suffix-marked name on the table's
    /// chain (`_solo_apply_grant`, main.gd). The debuffs carry NO modifier:
    /// the grant is the whole payload, which is exactly why nothing ever read
    /// it — the record landed, nothing folded.
    fn terrain_grant(rule: &str) -> mods::LiveMod {
        mods::LiveMod {
            hit_mod: 0,
            casting_mod: 0,
            morale_mod: 0,
            ap_mod: 0,
            def_mod: 0,
            defense_mod: 0,
            move_mod: 0,
            grants_rule: Rc::from(rule),
            scope: Rc::from(""),
            attackers: false,
            once: true,
            name: Rc::from(""),
        }
    }

    /// An EMPTY but valid board — every cell NONE, no walls, no sandbox
    /// shapes. No cell anywhere can trigger a dangerous test or price a
    /// difficult move, so the ONLY possible trigger left is the rule the unit
    /// itself carries.
    fn open_board() -> crate::terrain::Terrain {
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells: vec![],
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

    /// The dangerous debuff's NEW leg, epoch literals 20/19 (NOT
    /// `CURRENT_RULES_EPOCH`): a unit carrying the granted "Dangerous Terrain
    /// (spell)" rule — ONLY via the recorded grant, no dangerous cell anywhere
    /// on the board — takes its once-per-move dangerous test when it advances
    /// over open ground (GF v3.5.1 p.12, the log's own "counts as being in
    /// Dangerous Terrain" promise). One test per model, the model's TOUGH in
    /// dice, exactly the count the cell-crossing trigger rolls.
    #[test]
    fn the_granted_dangerous_terrain_debuff_tests_on_open_ground() {
        let (mut st, statics) = dangerous_line();
        st.buffs[0] = vec![terrain_grant("Dangerous Terrain (spell)")];
        let t = open_board();
        let mut tray = Tray::seeded(1);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(6.0), &t,
            Seams { rules_epoch: 20, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        let a_rolls: Vec<&crate::dice::Roll> =
            shot.rolls.iter().filter(|r| r.owner == "a").collect();
        assert_eq!(
            a_rolls.len(),
            1,
            "the debuffed unit's move rolled no dangerous test at all: {:?}",
            shot.rolls
        );
        assert_eq!(a_rolls[0].count, 4, "one die per model: {:?}", shot.rolls);
    }

    /// The OLD leg, epoch 19 (one below the debuff's own gate): a record
    /// stamped before the fix replays unchanged — the grant stays inert on
    /// open ground, no dangerous test is drawn, byte for byte what every
    /// recorded game played like.
    #[test]
    fn below_epoch_20_the_dangerous_debuff_stays_inert() {
        let (mut st, statics) = dangerous_line();
        st.buffs[0] = vec![terrain_grant("Dangerous Terrain (spell)")];
        let t = open_board();
        let mut tray = Tray::seeded(1);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(6.0), &t,
            Seams { rules_epoch: 19, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        assert!(
            shot.rolls.iter().all(|r| r.owner != "a"),
            "no dangerous test below the gate: {:?}",
            shot.rolls
        );
    }

    /// The difficult debuff's NEW leg, epoch literals 20/19: a unit carrying
    /// the granted "Difficult Terrain (spell)" rule moves as if in difficult
    /// terrain — the p.11 cap ("may not move more than 6\"") bites the same
    /// way it bites for a unit whose ROUTE crossed a difficult cell. Before
    /// the fix the marked unit crossed open ground at full speed.
    #[test]
    fn the_granted_difficult_terrain_debuff_caps_the_move() {
        let (mut st, statics) = dangerous_line();
        // The movement-seam path reads EVERY unit's recorded profile
        // (`state.profile`, step.rs's base shapes), so the harness needs four
        // slots — dangerous_line's shared single slot is a sim-only shape.
        let mut prof_list = st.profiles.list.clone();
        prof_list.resize(4, prof_list[0].clone());
        st.profiles = Rc::new(Profiles { list: prof_list, index: HashMap::new() });
        st.bands[0].advance = 12.0;
        st.buffs[0] = vec![terrain_grant("Difficult Terrain (spell)")];
        // Park the far units out of the lane so the move is pure open ground.
        st.positions[2] = vec![[60.0 * IN2M, 0.0, 0.0]];
        st.positions[3] = vec![[61.0 * IN2M, 0.0, 0.0]];
        let t = open_board();
        let mut tray = Tray::seeded(1);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(12.0), &t,
            Seams { movement: true, rules_epoch: 20, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        let moved_in = (next.positions[0][0][0] - st.positions[0][0][0]) / IN2M;
        assert!(
            moved_in <= 6.0 + 0.05,
            "the difficult debuff must cap the move at 6\", moved {moved_in}\""
        );
    }

    /// The OLD leg, epoch 19: the full band stands — the debuff must not
    /// re-date the uncapped move every recorded game made.
    #[test]
    fn below_epoch_20_the_difficult_debuff_leaves_the_full_band() {
        let (mut st, statics) = dangerous_line();
        // The movement-seam path reads every unit's recorded profile (see the
        // NEW leg above).
        let mut prof_list = st.profiles.list.clone();
        prof_list.resize(4, prof_list[0].clone());
        st.profiles = Rc::new(Profiles { list: prof_list, index: HashMap::new() });
        st.bands[0].advance = 12.0;
        st.buffs[0] = vec![terrain_grant("Difficult Terrain (spell)")];
        st.positions[2] = vec![[60.0 * IN2M, 0.0, 0.0]];
        st.positions[3] = vec![[61.0 * IN2M, 0.0, 0.0]];
        let t = open_board();
        let mut tray = Tray::seeded(1);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(12.0), &t,
            Seams { movement: true, rules_epoch: 19, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        let moved_in = (next.positions[0][0][0] - st.positions[0][0][0]) / IN2M;
        assert!(
            (moved_in - 12.0).abs() < 0.5,
            "epoch 19 keeps the full band: {moved_in}\""
        );
    }
