use super::*;

    // ---- One-core P3 step 59: a Dangerous terrain landing is recorded on the tray ----

    /// `buff_line`'s unit "a" (two one-wound models) HOLDS without a shot, both bases on
    /// `dangerous_bar_board`'s Dangerous cells: a unit that activates in it takes the test (rules 3.6).
    /// The supplied test rolls one 1 and the rest 6, so one model dies, and the tray records that as one
    /// landing on "a" (RED: drop `tray.land`, or take the snapshot after `land_pool_wounds`).
    #[test]
    fn a_supplied_dangerous_test_records_its_landing() {
        let (mut st, statics) = buff_line();
        st.positions[0] = vec![[4.0 * IN2M, 0.0, 0.0], [4.02 * IN2M, 0.0, 0.0]];
        let start = st.positions[0].clone();
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let mut tray = Tray::supplied(vec![vec![1, 6]]);
        let (after, shot) = resolve_stochastic_tray_on_board(&statics, &st, &buff_action(None), &dangerous_bar_board(),
            seams, &mut GodotRng::new(0), &mut tray).unwrap();
        let r = &shot.rolls[0];
        assert_eq!((r.kind, r.target, r.count, r.faces.as_slice()), ("attack", DANGEROUS_TARGET, 2, &[1, 6][..]),
            "fixture: the Dangerous test is the first roll: {:?}", shot.rolls);
        assert_eq!(after.alive[0], 1, "fixture: the one 1 kills one model");
        let all = tray.all_landings();
        assert_eq!(all.iter().map(|l| l.unit).collect::<Vec<_>>(), vec![0], "one landing, on \"a\": {all:?}");
        let dead: Vec<_> = all[0].models.iter().filter(|m| m.dead).collect();
        assert_eq!(dead.len(), 1, "{all:?}");
        assert!(start.contains(&dead[0].at), "the dead model sits where it started: {all:?} vs {start:?}");
        assert_eq!(start[dead[0].slot], dead[0].at, "P4.0-1: its slot is its capture index: {all:?} vs {start:?}");
        // Step 27: the core says no loss line for a Dangerous test, so the table's removal funnel still says it.
        assert!(!all[0].loss_line, "{all:?}");
    }
