use super::*;

    // ------------- Wave 2: the Shred BOOST family (unit.rs::stamp's arm 6b

    #[test]
    fn a_warbound_boost_carrier_widens_the_save_window_over_nine_inches_at_epoch_4() {
        use crate::acts::rule_on;
        let us = shred_static("warbound_boost");
        let p = [us.shoot[0].clone()];
        let def = defender(4, 5);
        // epoch 4, 12" out: failed 1s AND 2s each take the extra wound.
        let mut t4 = Tray::seeded(SHRED_BOOST_SEED);
        let on = resolve_volley_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, rule_on(4, 4), &mut t4);
        // epoch 3: the boost is not born yet — the base window (1s only).
        let mut t3 = Tray::seeded(SHRED_BOOST_SEED);
        let off = resolve_volley_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, rule_on(3, 4), &mut t3);
        assert_eq!(on.rolls, off.rolls, "the gate moves no die");
        let twos = on.rolls[1].faces.iter().filter(|&&f| f == 2).count() as i64;
        assert!(twos > 0, "this seed must land 2s among the saves or the test is blind");
        assert_eq!(on.wounds - off.wounds, twos,
            "the delta is exactly the failing 2s ({} -> {})", off.wounds, on.wounds);
        // exactly 9" is not "over": the window stays the base 1s.
        let mut t9 = Tray::seeded(SHRED_BOOST_SEED);
        let at9 = resolve_volley_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            9.0, 9.0, true, true, true, rule_on(4, 4), &mut t9);
        assert_eq!(at9.wounds, off.wounds, "exactly 9\" stays shut");
    }

    #[test]
    fn an_infected_boost_carrier_widens_the_save_window_over_nine_inches_at_epoch_4() {
        use crate::acts::rule_on;
        let us = shred_static("infected_boost");
        let base = shred_static("infected");
        let p = [us.shoot[0].clone()];
        let def = defender(4, 5);
        // epoch 4, 12" out: the widened window (the save_fail_max spelling).
        let mut t4 = Tray::seeded(SHRED_BOOST_SEED);
        let on = resolve_volley_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, rule_on(4, 4), &mut t4);
        // epoch 3 and the base-only carrier: the base window either way.
        let mut t3 = Tray::seeded(SHRED_BOOST_SEED);
        let off = resolve_volley_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, rule_on(3, 4), &mut t3);
        assert_eq!(on.rolls, off.rolls, "the gate moves no die");
        let pb = [base.shoot[0].clone()];
        let mut tc = Tray::seeded(SHRED_BOOST_SEED);
        let without = resolve_volley_with_tray(&[striker(&pb, &[0], &[6], &base.ctx)], &def,
            "Target", 12.0, 12.0, true, true, true, rule_on(4, 4), &mut tc);
        assert_eq!(on.rolls, without.rolls, "the rule moves no die either");
        let twos = on.rolls[1].faces.iter().filter(|&&f| f == 2).count() as i64;
        assert!(twos > 0, "this seed must land 2s among the saves or the test is blind");
        assert!(on.wounds > off.wounds,
            "epoch 4 widens the window ({} -> {})", off.wounds, on.wounds);
        assert_eq!(on.wounds - off.wounds, twos, "the delta is exactly the failing 2s");
        assert_eq!(without.wounds, off.wounds,
            "without the Boost the base carrier keeps the 1s window");
    }

    #[test]
    fn a_destroyer_boost_carrier_widens_the_save_window_over_nine_inches_at_epoch_4() {
        use crate::acts::rule_on;
        let us = shred_static("destroyer_boost");
        let p = [us.shoot[0].clone()];
        let def = defender(4, 5);
        // epoch 4, 12" out: failed 1s AND 2s (aof ogres, save_fail_max).
        let mut t4 = Tray::seeded(SHRED_BOOST_SEED);
        let on = resolve_volley_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, rule_on(4, 4), &mut t4);
        let mut t3 = Tray::seeded(SHRED_BOOST_SEED);
        let off = resolve_volley_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, rule_on(3, 4), &mut t3);
        assert_eq!(on.rolls, off.rolls, "the gate moves no die");
        let twos = on.rolls[1].faces.iter().filter(|&&f| f == 2).count() as i64;
        assert!(twos > 0, "this seed must land 2s among the saves or the test is blind");
        assert_eq!(on.wounds - off.wounds, twos,
            "the delta is exactly the failing 2s ({} -> {})", off.wounds, on.wounds);
        let mut t9 = Tray::seeded(SHRED_BOOST_SEED);
        let at9 = resolve_volley_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            9.0, 9.0, true, true, true, rule_on(4, 4), &mut t9);
        assert_eq!(at9.wounds, off.wounds, "exactly 9\" stays shut");
    }

    /// The `upgrades` gate: "If this model has Warbound, …" — a Boost entry
    /// carried WITHOUT its base rule still shreds 1s (its own alias half,
    /// arm 6) but never widens: the same seed gives the bare carrier the
    /// base-window wounds while the full carrier takes the failing 2s too.
    #[test]
    fn the_upgrades_gate_keeps_a_boost_without_its_base_rule_at_the_base_window() {
        use crate::acts::rule_on;
        let us = shred_static("warbound_boost");
        let bare = shred_static("warbound_boost_only");
        let plain = shred_static("plain_gf");
        let def = defender(4, 5);
        let pb = [us.shoot[0].clone()];
        let mut t1 = Tray::seeded(SHRED_BOOST_SEED);
        let boosted = resolve_volley_with_tray(&[striker(&pb, &[0], &[6], &us.ctx)], &def,
            "Target", 12.0, 12.0, true, true, true, rule_on(4, 4), &mut t1);
        let po = [bare.shoot[0].clone()];
        let mut t2 = Tray::seeded(SHRED_BOOST_SEED);
        let without_base = resolve_volley_with_tray(&[striker(&po, &[0], &[6], &bare.ctx)], &def,
            "Target", 12.0, 12.0, true, true, true, rule_on(4, 4), &mut t2);
        let pp = [plain.shoot[0].clone()];
        let mut t3 = Tray::seeded(SHRED_BOOST_SEED);
        let plain_out = resolve_volley_with_tray(&[striker(&pp, &[0], &[6], &plain.ctx)], &def,
            "Target", 12.0, 12.0, true, true, true, rule_on(4, 4), &mut t3);
        assert_eq!(boosted.rolls, without_base.rolls, "the same dice both ways");
        let twos = boosted.rolls[1].faces.iter().filter(|&&f| f == 2).count() as i64;
        assert!(twos > 0, "this seed must land 2s among the saves or the test is blind");
        assert!(without_base.wounds > plain_out.wounds,
            "the bare Boost entry still rides its own 1s alias ({} -> {})",
            plain_out.wounds, without_base.wounds);
        assert_eq!(boosted.wounds - without_base.wounds, twos,
            "without the base rule the boost widens nothing");
    }
