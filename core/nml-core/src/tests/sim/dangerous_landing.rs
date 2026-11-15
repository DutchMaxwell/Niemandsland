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

    /// P4.0-2: the table remembers a landing by its index in the list, so every step's list must be the one before it with
    /// more at the end. A Dangerous test that kills one of "a"'s models (landing 0) and a volley that kills one of "b"'s two
    /// (landing 1, then b's morale die starves), driven one supplied group at a time: each step's landings are a prefix of
    /// the next step's, a starved step shows both landings, and the last step lists both, in order. RED: `landings_upto`
    /// newest first, or `>=` the stamp, and a step's list is no prefix.
    #[test]
    fn every_step_s_landings_are_a_prefix_of_the_next() {
        let (mut st, mut statics) = buff_line();
        st.positions[0] = vec![[4.0 * IN2M, 0.0, 0.0], [4.02 * IN2M, 0.0, 0.0]];
        st.positions[2].truncate(2); // "b" has two models: losing one puts it at half, so it tests morale
        (st.wounds[2], st.alive[2]) = (vec![1; 2], 2);
        Rc::make_mut(&mut st.radii)[2] = vec![IN2M; 2];
        (statics[2].model_count, statics[2].wounds_max) = (2, vec![1, 1]);
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let script = [vec![1, 6], vec![6], vec![1], vec![6]]; // Dangerous: one 1; hit; failed save; morale pass
        let mut steps: Vec<(bool, Vec<Landing>)> = Vec::new();
        for k in 0..=script.len() {
            let mut tray = Tray::supplied(script[..k].to_vec());
            let _ = resolve_stochastic_tray_on_board(&statics, &st, &buff_action(Some("b")), &dangerous_bar_board(),
                seams, &mut GodotRng::new(0), &mut tray).unwrap();
            let starved = tray.feed().and_then(|f| f.starved_at);
            steps.push((starved.is_some(), starved.map_or_else(|| tray.all_landings(), |(i, _)| tray.landings_upto(i))));
            if starved.is_none() {
                break;
            }
        }
        let (done, last) = steps.last().expect("a step");
        assert!(!*done && steps.len() == 5, "the fixture must starve at four rolls and finish on the fifth: {steps:?}");
        assert_eq!(last.iter().map(|l| l.unit).collect::<Vec<_>>(), vec![0, 2], "Dangerous on \"a\", then the volley on \"b\": {last:?}");
        assert!(steps.iter().any(|(starved, l)| *starved && l.len() == 2), "a starved step must show both landings: {steps:?}");
        for pair in steps.windows(2) {
            assert!(pair[1].1.starts_with(&pair[0].1), "a step's landings are no prefix of the next step's: {pair:?}");
        }
    }
