use super::*;

    /// FAB-A5 (`EPOCH_79_EV_MOVED_ROUND`, table twin `BattleSim._held_for`): the sim's shoot EV reads the target's
    /// Hold state. An Artillery target that MOVED this round hands the shooter no -1 to hit past 9"; one that held
    /// still does. Below 79 the EV built the defender without the stamp and always applied the -1.
    fn artillery_volley(rules_epoch: u32, target_moved: bool) -> i64 {
        let (mut st, mut statics) = buff_line();
        statics[0].shoot = vec![gun("Rifle", 12, 24)];
        statics[2].ctx.artillery_target_over_in = 9.0;
        statics[2].ctx.artillery_target_most_models = true;
        statics[2].ctx.moved_round = -1; // the `ctx_for` template: never moved, round 0
        st.wounds[2] = vec![3, 3, 3];
        statics[2].wounds_max = vec![3, 3, 3];
        st.moved_round[2] = if target_moved { st.round } else { -1 };
        let seams = Seams { rules_epoch, ..Default::default() };
        let next = resolve(&statics, &st, &buff_action(Some("b")), None, seams, None).expect("a plain volley");
        next.wounds[2].iter().sum()
    }

    #[test]
    fn a_moved_artillery_target_gives_the_shooter_no_minus_one_from_epoch_79() {
        let ep = crate::acts::EPOCH_79_EV_MOVED_ROUND;
        let (held, moved) = (artillery_volley(ep, false), artillery_volley(ep, true));
        assert!(moved < held, "a moved Artillery target is hit without the -1: {moved} vs {held} wounds left");
        // RED leg (the rule off): at 78 the moved target still hands the shooter its -1, exactly like a held one.
        assert_eq!(artillery_volley(ep - 1, true), artillery_volley(ep - 1, false), "78 keeps the old reading");
        assert_eq!(artillery_volley(ep - 1, false), held, "a held target is priced the same at both epochs");
    }

    /// The 15" volley line: 10 Quality-4 shots into five Defence-4 models with 2 wounds each.
    fn artillery_line() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = buff_line();
        statics[0].shoot = vec![gun("Gun", 10, 24)];
        statics[2].model_count = 5;
        statics[2].wounds_max = vec![2; 5];
        (statics[2].ctx.tough, statics[2].ctx.moved_round) = (0, -1); // the `ctx_for` template: round 0
        st.positions[2] = (0..5).map(|i| [(15.0 + i as f64) * IN2M, 0.0, 0.0]).collect();
        st.radii = Rc::new(vec![vec![IN2M; 2], vec![IN2M], vec![IN2M; 5], vec![]]);
        st.wounds = vec![vec![1; 2], vec![1], vec![2; 5], vec![]];
        (st.alive, st.wound_frac) = (vec![2, 1, 5, 0], vec![0.0; 4]);
        (st, statics)
    }

    fn wounds_left(st: &State) -> i64 {
        st.wounds[2].iter().sum()
    }

    /// Case 4 (Fable F5): the ATTACKER's Hold is the SIMULATED action. A live read of the unit
    /// priced an ADVANCE+shoot as a Hold and paid the +1; the action itself must decide it.
    #[test]
    fn a_simulated_advance_and_shoot_pays_no_artillery_hold_bonus() {
        let (st, mut statics) = artillery_line();
        statics[0].ctx.artillery = true;
        statics[0].ctx.artillery_shooter_over_in = 12.0;
        statics[0].ctx.artillery_shooter_needs_hold = true;
        let seams = Seams { rules_epoch: crate::acts::EPOCH_79_EV_MOVED_ROUND, moved_shoot: true, ..Default::default() };
        let advance = Action { kind: ADVANCE, dest: Some([2.0 * IN2M, 0.0, 0.0]), ..buff_action(Some("b")) };
        let held = resolve(&statics, &st, &buff_action(Some("b")), None, seams, None).expect("a plain volley");
        let moved = resolve(&statics, &st, &advance, None, seams, None).expect("an advance and shoot");
        assert_eq!(wounds_left(&held), 7, "a HOLD keeps the +1: 3 wounds into 10");
        assert_eq!(wounds_left(&moved), 8, "an ADVANCE+shoot pays no +1: 2 wounds into 10");
    }

    /// Case 5: the defender leg through the SIM STATE. A gun that advanced EARLIER in the same
    /// imagined round carries the state's move stamp, so the second resolve hands no -1; a Hold keeps it.
    #[test]
    fn a_defender_that_moved_earlier_in_the_sim_round_gives_no_minus_one() {
        let (st, mut statics) = artillery_line();
        statics[2].ctx.artillery_target_over_in = 9.0;
        statics[2].ctx.artillery_target_most_models = true;
        let seams = Seams { rules_epoch: crate::acts::EPOCH_79_EV_MOVED_ROUND, ..Default::default() };
        let advance = Action { kind: ADVANCE, unit: "b".into(), dest: Some([15.04 * IN2M, 0.0, 2.0 * IN2M]), ..buff_action(None) };
        let moved = resolve(&statics, &st, &advance, None, seams, None).expect("the gun advances");
        let after = resolve(&statics, &moved, &buff_action(Some("b")), None, seams, None).expect("the rifle shoots it");
        let still = resolve(&statics, &st, &buff_action(Some("b")), None, seams, None).expect("the gun holds");
        assert_eq!(wounds_left(&after), 8, "a gun that moved in this sim round hands no -1");
        assert_eq!(wounds_left(&still), 9, "a held gun still hands the -1");
    }
