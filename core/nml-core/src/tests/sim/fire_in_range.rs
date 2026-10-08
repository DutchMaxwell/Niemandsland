    use super::*;
    use crate::sim::{member_profiles_reach, reply_threat_opts, ReplyOpts};

    // -------- inventory C02: only models within a weapon's range fire ----

    /// Unit 0 = a ten-model squad with the given weapons; its models stand on the x axis at the given
    /// distances (inches) from the one-model target (unit 2, at the origin).
    fn squad(shoot: Vec<ShootProfile>, model_x_in: &[f64]) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = hero_line();
        statics[0].model_count = 10;
        statics[0].shoot = shoot;
        statics[0].ctx = Ctx { quality: 4, defense: 4, models: 10, ..Default::default() };
        statics[1].shoot.clear();
        statics[2].ctx = Ctx { quality: 4, defense: 4, models: 1, ..Default::default() };
        st.alive[0] = 10;
        st.positions[0] = model_x_in.iter().map(|x| [x * IN2M, 0.0, 0.0]).collect();
        st.positions[1] = vec![[0.0, 0.0, 0.0]];
        st.positions[2] = vec![[0.0, 0.0, 0.0]];
        st.positions[3] = vec![[500.0 * IN2M, 0.0, 0.0]];
        (st, statics)
    }

    fn rifle() -> ShootProfile {
        ShootProfile { name: "Rifle".into(), attacks: 10, count: 10, range: 24, ..Default::default() }
    }

    fn heavy() -> ShootProfile {
        ShootProfile { name: "Heavy".into(), attacks: 1, count: 1, range: 36, ..Default::default() }
    }

    fn volley(st: &State, statics: &[UnitStatic], on: bool) -> (Vec<String>, Vec<i64>) {
        let seams = Seams { fire_in_range_only: on, ..Seams::default() };
        let d = crate::geom::dist_in(&st.positions[0], &st.positions[2]);
        let mut sc = Scratch::default();
        member_profiles_reach(statics, st, 0, 2, d, seams, &mut sc);
        let names = sc.keep.iter().map(|&i| statics[0].shoot[i].name.clone()).collect();
        (names, sc.attacks.clone())
    }

    /// RED on unmodified code: ten riflemen in a line, only the front one within 24" -> one model's attacks.
    #[test]
    fn ten_riflemen_in_a_line_only_the_front_one_in_range_fires_once() {
        let xs: Vec<f64> = (0..10).map(|k| 20.0 + 5.0 * k as f64).collect();
        let (st, statics) = squad(vec![rifle()], &xs);
        assert_eq!(volley(&st, &statics, true).1, vec![1], "knob on: one model within 24 inches fires");
        assert_eq!(volley(&st, &statics, false).1, vec![10], "knob off: today's nearest-pair reading, all ten");
    }

    /// Identity: every model within range -> on == off.
    #[test]
    fn all_models_in_range_the_knob_changes_nothing() {
        let xs: Vec<f64> = (0..10).map(|k| 10.0 + 0.5 * k as f64).collect();
        let (st, statics) = squad(vec![rifle(), heavy()], &xs);
        assert_eq!(volley(&st, &statics, true), volley(&st, &statics, false));
        assert_eq!(volley(&st, &statics, true).1, vec![10, 1]);
    }

    /// Nine rifles (24") plus a heavy (36"), every model at 30": the heavy fires, the rifles do not.
    /// One model at 20" and nine at 30": the rifles count the one model, the heavy still fires once.
    #[test]
    fn a_mixed_unit_the_heavy_fires_at_thirty_inches_and_the_rifles_do_not() {
        let (st, statics) = squad(vec![rifle(), heavy()], &[30.0; 10]);
        for on in [true, false] {
            let (names, atts) = volley(&st, &statics, on);
            assert_eq!((names, atts), (vec!["Heavy".to_string()], vec![1]), "knob {on}");
        }
        let mut xs = vec![30.0; 9];
        xs.push(20.0);
        let (st, statics) = squad(vec![rifle(), heavy()], &xs);
        assert_eq!(volley(&st, &statics, true).1, vec![1, 1], "on: one rifle in reach, the heavy in reach");
        assert_eq!(volley(&st, &statics, false).1, vec![10, 1], "off: all ten rifles");
    }

    /// The reply threat prices the same reading, and knob off is today's number.
    #[test]
    fn the_reply_threat_prices_only_the_models_in_range() {
        let xs: Vec<f64> = (0..10).map(|k| 20.0 + 5.0 * k as f64).collect();
        let (st, statics) = squad(vec![rifle()], &xs);
        let sum = |o: ReplyOpts| reply_threat_opts(&statics, &st, 1, o).iter().sum::<f64>();
        let (off, on) = (sum(ReplyOpts::default()), sum(ReplyOpts { reach_only: true, ..ReplyOpts::default() }));
        assert!(off > 0.0 && on > 0.0 && (off / on - 10.0).abs() < 1e-9, "off {off} on {on}");
    }

    /// The knob parses from a header, defaults off, and rides into the seams and the menu tuning.
    #[test]
    fn the_knob_parses_from_a_header_and_reaches_seams_and_tuning() {
        let head = |knobs: &str| format!(r#"{{"kind":"header","profiles":{{}},"knobs":{{{knobs}}}}}"#);
        let on = crate::read_act_header(&head(r#""fire_in_range_only":true"#)).unwrap().knobs;
        let off = crate::read_act_header(&head("")).unwrap().knobs;
        assert!(on.fire_in_range_only && !off.fire_in_range_only);
        assert!(crate::plan::seams_of(&on).fire_in_range_only && !crate::plan::seams_of(&off).fire_in_range_only);
        assert!(crate::plan::tuning_of(&on).reach_only && !crate::plan::tuning_of(&off).reach_only);
    }
