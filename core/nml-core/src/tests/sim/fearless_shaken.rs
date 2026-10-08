    use super::*;

    // -------- inventory C08: a Shaken Fearless unit keeps its 4+ roll in the imagined morale ----------
    // p.10: Shaken units always fail morale tests; p.13 Fearless: a unit whose models all have it, on a FAILED test,
    // rolls one die and passes on a 4+. The table (`dice::resolve_morale_with_tray`) rolls it for a Shaken unit; the imagination
    // priced the fail at 100 %.

    /// Unit 0 shaken, at half strength; `fearless` sets the rule on the unit.
    fn shaken_line(fearless: bool, shaken: bool) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = hero_line();
        statics[0].model_count = 4;
        statics[0].fearless = fearless;
        statics[0].fearless_own = fearless;
        st.alive[0] = 2;
        st.shaken[0] = shaken;
        (st, statics)
    }

    fn seams(on: bool) -> Seams {
        Seams { fearless_roll_when_shaken: on, ..Seams::default() }
    }

    /// Share of 300 rounds in which the imagined test fails.
    fn fail_rate(st: &State, statics: &[UnitStatic], on: bool) -> f64 {
        (1..=300)
            .filter(|&r| {
                let mut s = st.clone();
                s.round = r;
                morale_fails_expected(&s, statics, 0, seams(on))
            })
            .count() as f64
            / 300.0
    }

    /// RED on unmodified behaviour: knob on must NOT price the rout at 100 %.
    #[test]
    fn a_shaken_fearless_unit_breaks_half_the_time_with_the_knob() {
        let (st, statics) = shaken_line(true, true);
        let on = fail_rate(&st, &statics, true);
        assert!((on - 0.5).abs() < 0.05, "knob on: the Fearless 4+ roll leaves a 50 % fail chance, got {on}");
        assert_eq!(fail_rate(&st, &statics, false), 1.0, "knob off: today's certain fail");
    }

    /// The lost melee at half strength: a passing die keeps the unit, a failing die routs it.
    #[test]
    fn a_lost_melee_at_half_strength_routs_a_shaken_fearless_unit_only_on_a_failed_die() {
        let (st, statics) = shaken_line(true, true);
        let sm = seams(true);
        let alive_after = |round: i64, sm: Seams| {
            let mut s = st.clone();
            s.round = round;
            s.wounds[0] = vec![5];
            s.wounds[2] = vec![9];
            s.roster = Rc::new(Roster { keys: s.roster.keys.clone(), index: HashMap::new(), profile: vec![0, 1, 1, 1] });
            let mut statics = statics.clone();
            statics[0].model_count = 4;
            expected_melee_morale(&mut s, &statics, 0, 10, 2, 10, sm);
            s.alive[0]
        };
        let routed = (1..=40).filter(|&r| alive_after(r, sm) == 0).count();
        assert!(routed > 5 && routed < 35, "knob on: some rounds rout, some keep the unit ({routed} of 40)");
        assert!((1..=40).all(|r| alive_after(r, seams(false)) == 0), "knob off: always routs");
    }

    /// A Shaken unit without Fearless fails for certain with or without the knob.
    #[test]
    fn a_shaken_plain_unit_still_fails_for_certain() {
        let (st, statics) = shaken_line(false, true);
        assert_eq!(fail_rate(&st, &statics, true), 1.0);
        assert_eq!(fail_rate(&st, &statics, false), 1.0);
    }

    /// Not Shaken: the knob changes nothing, Fearless or not.
    #[test]
    fn a_unit_that_is_not_shaken_reads_the_same_with_the_knob() {
        for fearless in [true, false] {
            let (st, statics) = shaken_line(fearless, false);
            assert_eq!(fail_rate(&st, &statics, true), fail_rate(&st, &statics, false), "fearless {fearless}");
        }
    }

    /// The knob parses from a header and reaches the seams; absent = off.
    #[test]
    fn the_knob_parses_and_reaches_the_seams() {
        let on: crate::acts::Knobs = serde_json::from_str(r#"{"fearless_roll_when_shaken": true}"#).unwrap();
        assert!(on.fearless_roll_when_shaken);
        assert!(crate::plan::seams_of(&on).fearless_roll_when_shaken);
        let off: crate::acts::Knobs = serde_json::from_str("{}").unwrap();
        assert!(!off.fearless_roll_when_shaken);
        assert!(!crate::plan::seams_of(&off).fearless_roll_when_shaken);
    }
