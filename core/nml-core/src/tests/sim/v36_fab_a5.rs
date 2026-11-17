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
