use super::*;

    // ---- One-core P3 step 5: a supplied tray's per-model placement IS the move ----

    /// A supplied placement (each start + 3" in x) replaces the move port: the models land
    /// exactly there and the unit is stamped as moved this round (RED: drop the
    /// `if let Some(p)` block in `resolve_with` and they stay where they started). The SAME
    /// call on a seeded tray ignores `place`, so the old rigid move spends the full 6" band.
    #[test]
    fn a_supplied_placement_is_the_move_and_a_seeded_tray_ignores_it() {
        let mut st = four_unit_line();
        let r = &*st.roster;
        let index = r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
        st.roster = Rc::new(Roster { keys: r.keys.clone(), index, profile: r.profile.clone() });
        let statics = vec![UnitStatic { name: "a".into(), ..Default::default() }];
        let terrain = crate::terrain::Terrain::default();
        let placed: Vec<[f64; 3]> = st.positions[0].iter().map(|p| [p[0] + 3.0 * IN2M, p[1], p[2]]).collect();
        let run = |mut tray: Tray| {
            tray.place(placed.clone(), Vec::new());
            let mut rng = crate::rng::GodotRng::new(0);
            resolve_stochastic_tray_on_board(&statics, &st, &advance_to(20.0), &terrain, Seams::default(), &mut rng, &mut tray)
                .unwrap()
                .0
        };
        let supplied = run(Tray::supplied(vec![]));
        assert_eq!(supplied.positions[0], placed);
        assert_eq!(supplied.moved_round[0], supplied.round);
        let seeded = run(Tray::seeded(11));
        assert_ne!(seeded.positions[0], placed, "the seeded tray must run the old move");
        assert!((seeded.positions[0][0][0] - (st.positions[0][0][0] + 6.0 * IN2M)).abs() < 1e-6, "{:?}", seeded.positions[0]);
    }

    /// A supplied tray hands the placement's walked paths back unchanged; a seeded tray keeps
    /// none (RED: `Tray::place` ignores the trails -> `placed_trails()` is None).
    #[test]
    fn a_supplied_placement_keeps_its_trails() {
        let trails = vec![vec![[0.0, 0.0], [0.1, 0.0], [0.1, 0.05]], vec![[0.5, 0.0], [0.6, 0.0]]];
        let mut tray = Tray::supplied(vec![]);
        assert_eq!(tray.placed_trails(), None, "nothing placed yet");
        tray.place(vec![[0.1, 0.0, 0.05], [0.6, 0.0, 0.0]], trails.clone());
        assert_eq!(tray.placed_trails(), Some(&trails[..]));
        let mut seeded = Tray::seeded(11);
        seeded.place(vec![[0.1, 0.0, 0.05], [0.6, 0.0, 0.0]], trails);
        assert_eq!(seeded.placed_trails(), None);
    }

    /// One-core P3 step 61: a placed move tests Dangerous terrain on its WALKED path. Unit "a"'s model A walks
    /// 4" east into `dangerous_bar_board`'s cells (x 3..9", z -3..3"), 5" north and back west, and ends in the
    /// open; B walks 1" in the open. With the trails the unit takes one test of its 2 dice (rules 3.6: the whole
    /// unit); without them the end-only reading sees open ground and nothing is rolled (RED: do not set
    /// `landing` -> zero records).
    #[test]
    fn a_placed_move_rolls_dangerous_terrain_from_its_walked_path() {
        let (mut st, statics) = buff_line();
        st.positions[0] = vec![[0.0, 0.0, 0.0], [-2.0 * IN2M, 0.0, 0.0]];
        let placed = vec![[0.0, 0.0, 5.0 * IN2M], [-2.0 * IN2M, 0.0, -IN2M]];
        let w = |p: &[[f64; 2]]| p.iter().map(|q| [q[0] * IN2M, q[1] * IN2M]).collect::<Vec<_>>();
        let trails = vec![w(&[[0.0, 0.0], [4.0, 0.0], [4.0, 5.0], [0.0, 5.0]]), w(&[[-2.0, 0.0], [-2.0, -1.0]])];
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let run = |trails: Vec<Vec<[f64; 2]>>| {
            let mut tray = Tray::supplied(vec![vec![6, 6]]);
            tray.place(placed.clone(), trails);
            resolve_stochastic_tray_on_board(&statics, &st, &advance_to(20.0), &dangerous_bar_board(), seams, &mut GodotRng::new(0), &mut tray).unwrap()
        };
        let dangerous = |shot: &ShootResult| shot.rolls.iter().filter(|r| r.target == DANGEROUS_TARGET).map(|r| r.count).collect::<Vec<_>>();
        let (after, shot) = run(trails);
        assert_eq!(after.positions[0], placed, "fixture: the placement is the move");
        assert_eq!(dangerous(&shot), vec![2], "one test for the whole unit: {:?}", shot.rolls);
        assert_eq!(dangerous(&run(Vec::new()).1), Vec::<i64>::new(), "no trails: the ends are in the open");
    }

