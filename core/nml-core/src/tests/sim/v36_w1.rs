//! Rules 3.6 lane w1 tests for the sim module; owned by lane w1.
use super::*;

    // ---- W1.5a (D-GATE6): the charge distance and the Screened charge leg's 6" gate ----

    /// The `vr_charge_line` duel (Quality 4 charger, one 8-attack Blade) against a Screened target,
    /// placed so the two measures disagree: `centre_in` between the two models' centres, `radius_in`
    /// per base, so the closest-model base-edge gap is `centre_in - 2 * radius_in`.
    fn screened_duel(centre_in: f64, radius_in: f64) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = vr_charge_line(0.0);
        st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[centre_in * IN2M, 0.0, 0.0]]];
        st.radii = Rc::new(vec![vec![radius_in * IN2M], vec![radius_in * IN2M]]);
        statics[1].ctx.stealth_alias_penalty = 1;
        statics[1].ctx.stealth_alias_over_in = 9.0;
        statics[1].ctx.stealth_alias_applies_charged = true;
        (st, statics)
    }

    /// The charger's first melee to-hit target after a real charge on the board: 4 = no penalty,
    /// 5 = the Screened -1.
    fn charge_hit_target(centre_in: f64, radius_in: f64, rules_epoch: u32) -> i64 {
        let (st, statics) = screened_duel(centre_in, radius_in);
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let shot = resolve_stochastic_tray_on_board(
            &statics,
            &st,
            &vr_charge(),
            &small_board(),
            Seams { movement: true, rules_epoch, ..Seams::default() },
            &mut rng,
            &mut tray,
        )
        .unwrap()
        .1;
        assert!(!shot.rolls.is_empty(), "the charge must connect and strike: {:?}", shot.log);
        shot.rolls[0].target
    }

    /// The measure itself, both legs: the core has read the closest-model base-edge gap since
    /// `EPOCH_66_DISTANCE_TRUTH`, so the record leg below the wave (72) already gives 7", not the 8"
    /// between the centres, and the wave keeps it.
    #[test]
    fn the_pre_charge_measure_is_the_closest_edge_gap_at_epoch_72_and_at_epoch_73() {
        let (st, _) = screened_duel(8.0, 0.5);
        for epoch in [crate::acts::EPOCH_72_PLAYTEST_RULES, crate::acts::EPOCH_73_V36] {
            let d = modifier_distance_in(&st, 0, 1, Seams { rules_epoch: epoch, ..Seams::default() });
            assert!((d - 7.0).abs() < 1e-6, "epoch {epoch}: the edge gap is 7\", got {d}");
        }
    }

    /// Centres 8", edges 7": below the wave the Screened charge leg still needs over 9", so no -1.
    #[test]
    fn screened_charged_from_seven_inches_is_unpenalised_at_epoch_72() {
        assert_eq!(charge_hit_target(8.0, 0.5, crate::acts::EPOCH_72_PLAYTEST_RULES), 4);
    }

    /// Centres 8", edges 7": from the wave the charge leg reads the shared 6" charge threshold, so the
    /// charge from 7" costs the charger 1 (Quality 4+ rolls 5+).
    #[test]
    fn screened_charged_from_seven_inches_costs_the_hit_at_epoch_73() {
        assert_eq!(charge_hit_target(8.0, 0.5, crate::acts::EPOCH_73_V36), 5);
    }

    /// Centres 9.5", edges 5.5": the core measured edges already, so the record leg gives no -1 (5.5" is
    /// not over 9"), and the wave's 6" gate gives none either (5.5" is not over 6").
    #[test]
    fn screened_charged_from_five_and_a_half_inches_is_unpenalised_at_epoch_72() {
        assert_eq!(charge_hit_target(9.5, 2.0, crate::acts::EPOCH_72_PLAYTEST_RULES), 4);
    }

    #[test]
    fn screened_charged_from_five_and_a_half_inches_is_unpenalised_at_epoch_73() {
        assert_eq!(charge_hit_target(9.5, 2.0, crate::acts::EPOCH_73_V36), 4);
    }

    /// Control: centres 7", edges 5" never clears either gate.
    #[test]
    fn screened_charged_from_five_inches_is_unpenalised_at_epoch_72_and_at_epoch_73() {
        assert_eq!(charge_hit_target(7.0, 1.0, crate::acts::EPOCH_72_PLAYTEST_RULES), 4);
        assert_eq!(charge_hit_target(7.0, 1.0, crate::acts::EPOCH_73_V36), 4);
    }

    /// The scope cut: an alias with no distance gate of its own (`over_in` 0, the Changebound Boost
    /// shape) keeps firing on any measured charge; the wave's 6" gate only replaces a real `over_in`.
    #[test]
    fn an_ungated_charge_alias_keeps_firing_at_epoch_73() {
        let (st, mut statics) = screened_duel(7.0, 1.0);
        statics[1].ctx.stealth_alias_over_in = 0.0;
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let shot = resolve_stochastic_tray_on_board(
            &statics,
            &st,
            &vr_charge(),
            &small_board(),
            Seams { movement: true, rules_epoch: crate::acts::EPOCH_73_V36, ..Seams::default() },
            &mut rng,
            &mut tray,
        )
        .unwrap()
        .1;
        assert_eq!(shot.rolls[0].target, 5, "an ungated alias fires at 5\": {:?}", shot.rolls);
    }
