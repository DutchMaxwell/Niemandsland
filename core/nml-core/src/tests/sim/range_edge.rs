    use super::*;
    use crate::menu::{best_shoot, Tuning};
    use crate::sim::{fold_dist_in, range_gap_in, reply_threat_opts, ReplyOpts};

    // -------- inventory C01 / C27: shooting range base edge to base edge ----

    /// Two 32 mm-base models (radius 0.016 m each): `centre_in` apart on x. The base-edge gap is
    /// `centre_in - 2 * 0.016 / IN2M` (about 1.26" less). Unit 0 carries a 24" rifle; the stealth flag
    /// goes on the target. Unit 1 (the joined hero) is unarmed and unit 3 is parked far away.
    fn rifle_duel(centre_in: f64, stealth: bool) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = hero_line();
        statics[0].ctx = Ctx { quality: 4, defense: 4, models: 1, ..Default::default() };
        statics[1].shoot.clear();
        statics[2].ctx = Ctx { quality: 4, defense: 4, models: 1, stealth, ..Default::default() };
        st.positions[0] = vec![[0.0, 0.0, 0.0]];
        st.positions[1] = vec![[0.0, 0.0, 0.0]];
        st.positions[2] = vec![[centre_in * IN2M, 0.0, 0.0]];
        st.positions[3] = vec![[500.0 * IN2M, 0.0, 0.0]];
        for u in 0..4 {
            st.radii[u] = vec![0.016];
        }
        (st, statics)
    }

    /// Centre distance that puts the two 32 mm bases `edge_in` apart edge to edge.
    fn centre_for_edge(edge_in: f64) -> f64 {
        edge_in + 0.032 / IN2M
    }

    fn shoot_pick(st: &State, statics: &[UnitStatic], range_edge: bool) -> Option<usize> {
        let mut sc = Scratch::default();
        let tuning = Tuning { range_edge, ..Tuning::default() };
        best_shoot(st, statics, 0, &mut sc, tuning, crate::acts::CURRENT_RULES_EPOCH, None)
    }

    /// RED on a build that measures centre to centre: edge gap 23.0", centre gap 24.26" (> 24"), a 24"
    /// weapon. With the knob on the shooter IS in range and the menu offers the shot.
    #[test]
    fn a_24_inch_rifle_reaches_a_target_whose_base_edge_is_23_inches_away() {
        let (st, statics) = rifle_duel(centre_for_edge(23.0), false);
        assert_eq!(shoot_pick(&st, &statics, true), Some(2), "knob on: in range by the base edge");
        assert!((range_gap_in(&st, &st.positions[0], 0, 2) - 23.0).abs() < 1e-3);
        assert!(geom::dist_in(&st.positions[0], &st.positions[2]) > 24.0, "the centre ruler says out of range");
        assert_eq!(shoot_pick(&st, &statics, false), None, "knob off: today's centre ruler drops the weapon");
    }

    /// The over-9" modifier reads the same gap: edge 8.8", centre 10.06". Knob on, the Stealth penalty
    /// does not apply (the EV equals the EV at a plain 8.8"); knob off it does (the EV at the centre gap).
    #[test]
    fn the_over_nine_modifier_reads_the_base_edge_gap() {
        let (st, statics) = rifle_duel(centre_for_edge(8.8), true);
        let on = Seams { range_by_base_edge: true, ..Seams::default() };
        let d_on = fold_dist_in(&st, 0, 2, on);
        let d_off = fold_dist_in(&st, 0, 2, Seams::default());
        assert!((d_on - 8.8).abs() < 1e-3 && d_off > 10.0, "gaps {d_on} / {d_off}");
        let ev_at = |d: f64| {
            let mut sc = Scratch::default();
            let us = &statics[0];
            profiles_of(us, st.alive[0], d, &mut sc);
            let att = ctx_of(us, &st, 0);
            let def = ctx_of(&statics[2], &st, 2);
            shoot_ev(&us.shoot, &sc.keep, &sc.attacks, &att, &def, d)
        };
        assert!(ev_at(d_on) > ev_at(d_off), "stealth must bite only at the centre gap: {} vs {}", ev_at(d_on), ev_at(d_off));
        assert!((ev_at(d_on) - ev_at(8.8)).abs() < 1e-9, "knob on: exactly the 8.8\" number");
    }

    /// Identity: with the knob off every distance and every pick is the old path's, bit for bit.
    #[test]
    fn the_knob_off_changes_nothing() {
        for (edge, stealth) in [(23.0, false), (8.8, true), (30.0, false), (0.5, true)] {
            let (st, statics) = rifle_duel(centre_for_edge(edge), stealth);
            let old = geom::dist_in(&st.positions[0], &st.positions[2]);
            assert_eq!(fold_dist_in(&st, 0, 2, Seams::default()), old);
            assert_eq!(fold_dist_in(&st, 0, 2, Seams { hero_attach: true, ..Seams::default() }),
                fold_dist_in(&st, 0, 2, Seams { hero_attach: true, range_by_base_edge: false, ..Seams::default() }));
            assert_eq!(shoot_pick(&st, &statics, false), {
                let mut sc = Scratch::default();
                best_shoot(&st, &statics, 0, &mut sc, Tuning::default(), crate::acts::CURRENT_RULES_EPOCH, None)
            });
            let threat = |o: ReplyOpts| reply_threat_opts(&statics, &st, 1, o);
            assert_eq!(threat(ReplyOpts::default()), threat(ReplyOpts { range_edge: false, ..ReplyOpts::default() }));
        }
        // and the knob is not a no-op: the reply volley of the 24" rifle also reaches by the edge
        let (st, statics) = rifle_duel(centre_for_edge(23.0), false);
        let off = reply_threat_opts(&statics, &st, 1, ReplyOpts::default());
        let on = reply_threat_opts(&statics, &st, 1, ReplyOpts { range_edge: true, ..ReplyOpts::default() });
        assert_eq!(off.iter().sum::<f64>(), 0.0, "off: out of range by the centre ruler");
        assert!(on.iter().sum::<f64>() > 0.0, "on: the reply volley reaches");
    }

    /// The knob parses from a header, defaults off, and rides into the seams and the menu tuning.
    #[test]
    fn the_knob_parses_from_a_header_and_reaches_seams_and_tuning() {
        let head = |knobs: &str| format!(r#"{{"kind":"header","profiles":{{}},"knobs":{{{knobs}}}}}"#);
        let on = crate::read_act_header(&head(r#""range_by_base_edge":true"#)).unwrap().knobs;
        let off = crate::read_act_header(&head("")).unwrap().knobs;
        assert!(on.range_by_base_edge && !off.range_by_base_edge);
        assert!(crate::plan::seams_of(&on).range_by_base_edge && !crate::plan::seams_of(&off).range_by_base_edge);
        assert!(crate::plan::tuning_of(&on).range_edge && !crate::plan::tuning_of(&off).range_edge);
    }
