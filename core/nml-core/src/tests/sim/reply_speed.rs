    use super::*;
    use crate::sim::{reply_threat_opts, ReplyOpts};

    // -------- inventory T03-T06: the enemy's reply threat by its real speed ----

    fn off() -> ReplyOpts {
        ReplyOpts { v2: true, ..ReplyOpts::default() }
    }

    fn on() -> ReplyOpts {
        ReplyOpts { v2: true, by_speed: true, ..ReplyOpts::default() }
    }

    /// The wounds the enemy (unit 0) threatens on my unit (unit 1).
    fn threat(st: &State, statics: &[UnitStatic], o: ReplyOpts) -> f64 {
        reply_threat_opts(statics, st, 1, o)[1]
    }

    fn with_bands(st: &mut State, advance: f64, rush: f64) {
        st.bands[0] = Bands { advance, rush, charge: None };
    }

    /// T03: a Fast melee enemy (charge 16") 14" away IS a charge threat; a Slow one (8") 9.5" away is NOT.
    #[test]
    fn a_fast_charger_threatens_at_14_inches_and_a_slow_one_does_not_at_9_5() {
        let (mut st, statics) = vr_charge_line(14.0);
        with_bands(&mut st, 8.0, 16.0);
        assert_eq!(threat(&st, &statics, off()), 0.0, "off: the fixed 12\" says safe");
        assert!(threat(&st, &statics, on()) > 0.0, "on: Fast charge 16\" reaches 14\"");

        let (mut st, statics) = vr_charge_line(9.5);
        with_bands(&mut st, 4.0, 8.0);
        assert!(threat(&st, &statics, off()) > 0.0, "off: a Slow unit inside the fixed 12\" counts");
        assert_eq!(threat(&st, &statics, on()), 0.0, "on: Slow charge 8\" does not reach 9.5\"");
    }

    /// T04: a Fast shooter (advance 8") with a 24" gun 31" away (centre) IS in reach; the fixed 6" says no.
    #[test]
    fn a_fast_shooter_advances_8_inches_to_reach_a_gun_range_target() {
        let (mut st, mut statics) = vr_charge_line(29.0);
        statics[0].melee = Vec::new();
        statics[0].shoot = vec![ShootProfile { name: "Gun".into(), attacks: 8, count: 1, range: 24, ..Default::default() }];
        with_bands(&mut st, 8.0, 16.0);
        assert_eq!(threat(&st, &statics, off()), 0.0, "off: 31 - 6 = 25 > 24");
        assert!(threat(&st, &statics, on()) > 0.0, "on: 31 - 8 = 23 <= 24");
    }

    /// T05: two 32 mm units with an 11.5" base gap (about 12.8" between centres) ARE within a 12" charge.
    #[test]
    fn a_charge_reads_the_base_gap_not_the_centre_distance() {
        let (mut st, statics) = vr_charge_line(5.0);
        st.radii = vec![vec![0.016], vec![0.016]];
        st.positions[1] = vec![[(11.5 + 0.032 / IN2M) * IN2M, 0.0, 0.0]];
        assert_eq!(threat(&st, &statics, off()), 0.0, "off: the centre distance is over 12\"");
        assert!(threat(&st, &statics, on()) > 0.0, "on: the base gap is under 12\"");
    }

    /// T06: an Aircraft cannot be charged; the melee unit 8" away adds no threat on it.
    #[test]
    fn an_aircraft_is_never_a_charge_target() {
        let (mut st, statics) = vr_charge_line(8.0);
        st.aircraft[1] = true;
        assert!(threat(&st, &statics, off()) > 0.0, "off: today the Aircraft is charged");
        assert_eq!(threat(&st, &statics, on()), 0.0, "on: no melee threat against an Aircraft");
    }

    /// The knob parses from a header, defaults off, and rides into the seams and the reply opts.
    #[test]
    fn the_knob_parses_from_a_header_and_reaches_seams_and_reply_opts() {
        let head = |knobs: &str| format!(r#"{{"kind":"header","profiles":{{}},"knobs":{{{knobs}}}}}"#);
        let on = crate::read_act_header(&head(r#""reply_threat_by_speed":true"#)).unwrap().knobs;
        let off = crate::read_act_header(&head("")).unwrap().knobs;
        assert!(on.reply_threat_by_speed && !off.reply_threat_by_speed);
        assert!(crate::plan::seams_of(&on).reply_threat_by_speed && !crate::plan::seams_of(&off).reply_threat_by_speed);
        assert!(crate::plan::seams_of(&on).reply_opts().by_speed && !crate::plan::seams_of(&off).reply_opts().by_speed);
    }
