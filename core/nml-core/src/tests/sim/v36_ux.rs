//! Rules 3.6 lane ux tests for the sim module; owned by lane ux.
use super::*;

    // ---- UX-17 (rules 3.6): Bounding / Nimble / Dash MOVE the rolled inches ----
    //
    // Up to EPOCH_72 a fresh core sim rolls the carrier's D3(+X) and re-PLACES
    // the whole unit before its move (`place_d3_hop`): the landing scan never
    // looks at the path, so a wall in the way does not matter. From
    // EPOCH_73_V36 the same roll is a MOVE: it widens every move band this
    // activation (the table's own band model) and the move keeps the normal
    // path rules. Both legs draw the same dice from the seeded stream.

    /// The carrier: a gf/eternal_dynasty profile whose only rule is the named
    /// "Bounding" (one D3, plus 1), read off the REAL registry at `epoch`.
    fn ux17_bounder(epoch: u32) -> UnitStatic {
        let p = Profile {
            cost: 0,
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec!["Bounding".into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: "eternal_dynasty".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands { advance: 6.0, rush: 12.0, charge: None },
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch)
    }

    /// A 6x4 ft board with ONE wall at x = 1.5", running z = -20" .. 20":
    /// right across the straight line from the carrier to its objective and
    /// too long to walk around inside one activation's band. `walls: []`
    /// gives the same board without it.
    fn ux17_board(walls: Vec<[[f64; 2]; 2]>) -> crate::terrain::Terrain {
        crate::terrain::Terrain::build(&crate::terrain::PlainTerrain {
            cells: vec![],
            sandbox: vec![],
            pieces: vec![],
            walls,
            cell_params: crate::terrain::CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    fn ux17_wall() -> Vec<[[f64; 2]; 2]> {
        vec![[[1.5 * IN2M, -20.0 * IN2M], [1.5 * IN2M, 20.0 * IN2M]]]
    }

    /// The carrier "a" as ONE model (0.5" radius) at the origin, the
    /// objective 10" up +x behind the wall; the other roster slots leave the
    /// board.
    fn ux17_line(epoch: u32) -> (State, Vec<UnitStatic>) {
        let (mut st, _) = dangerous_line();
        st.positions[0] = vec![[0.0, 0.0, 0.0]];
        Rc::make_mut(&mut st.radii)[0] = vec![0.5 * IN2M];
        st.wounds[0] = vec![1];
        st.alive[0] = 1;
        for j in 1..4 {
            st.positions[j] = vec![];
            Rc::make_mut(&mut st.radii)[j] = vec![];
            st.wounds[j] = vec![];
            st.alive[j] = 0;
        }
        st.objectives = vec![crate::state::Objective { pos: [10.0 * IN2M, 0.0, 0.0], owner: 0 }];
        (st, vec![ux17_bounder(epoch), UnitStatic { name: "ah".into(), ..Default::default() },
            UnitStatic { name: "b".into(), ..Default::default() },
            UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    /// Seeds are searched, not guessed: the first seeded stream whose first
    /// D3 is a 3, so the roll is D3+1 = 4" (a hop that long clears the wall).
    fn ux17_seed() -> i64 {
        (0i64..).find(|&s| crate::rng::GodotRng::new(s).randi_range(1, 3) == 3).unwrap()
    }

    /// One fresh-sim ADVANCE toward x = 20" (no recorded trace), the seeded
    /// stream live; returns the landing x in inches, the log and the stream
    /// as the activation left it.
    fn ux17_run(epoch: u32, board: &crate::terrain::Terrain, movement: bool)
        -> (f64, Vec<String>, crate::rng::GodotRng) {
        let (st, statics) = ux17_line(epoch);
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(ux17_seed());
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(20.0), board,
            Seams { rules_epoch: epoch, movement, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        (next.positions[0][0][0] / IN2M, shot.log, rng)
    }

    /// The OLD leg: the hop places the carrier on the far side of the wall
    /// before the move, and the log says it was placed.
    #[test]
    fn bounding_hops_over_a_wall_at_epoch_72() {
        let (x_in, log, _) = ux17_run(crate::acts::EPOCH_72_PLAYTEST_RULES, &ux17_board(ux17_wall()), true);
        assert!(x_in > 1.5, "the hop placed the unit past the wall: x = {x_in}\"");
        assert!(
            log.iter().any(|l| l.contains("Bounding") && l.contains("placed")),
            "the 72 wording stays: {log:?}"
        );
    }

    /// The NEW leg: the rolled inches are a move, so the wall stops the
    /// carrier on its own side, and the log says it moves (rule name in the
    /// line, rules-must-log), never that it was placed.
    #[test]
    fn bounding_cannot_cross_a_wall_at_epoch_73() {
        let (x_in, log, _) = ux17_run(crate::acts::EPOCH_73_V36, &ux17_board(ux17_wall()), true);
        assert!(x_in < 1.5, "the move stays on its side of the wall: x = {x_in}\"");
        assert!(
            log.iter().any(|l| l.contains("Bounding") && l.contains("moves up to") && l.contains("rolled 4\"")),
            "rules-must-log names the rule and the rolled move: {log:?}"
        );
        assert!(!log.iter().any(|l| l.contains("placed")), "no placement at 73: {log:?}");
    }

    /// The NEW leg on an open board: the ADVANCE band grows by exactly the
    /// rolled 4" (6" + D3 3 + 1), the table's band model.
    #[test]
    fn bounding_widens_the_advance_band_by_the_roll_at_epoch_73() {
        let (x_in, _, _) = ux17_run(crate::acts::EPOCH_73_V36, &ux17_board(vec![]), false);
        assert!((x_in - 10.0).abs() < 1e-6, "band 6\" + the rolled 4\": {x_in}\"");
    }

    /// Both legs take the same dice from the seeded stream: the stream after
    /// the activation is the same at 72 and at 73.
    #[test]
    fn bounding_draws_the_same_dice_at_epoch_72_and_at_epoch_73() {
        let board = ux17_board(ux17_wall());
        let (_, _, mut rng72) = ux17_run(crate::acts::EPOCH_72_PLAYTEST_RULES, &board, true);
        let (_, _, mut rng73) = ux17_run(crate::acts::EPOCH_73_V36, &board, true);
        assert_eq!(rng72.randi_range(1, 1_000_000), rng73.randi_range(1, 1_000_000));
    }
