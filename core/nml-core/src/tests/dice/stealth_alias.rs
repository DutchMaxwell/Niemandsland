use super::*;

    // ------------------------ Stealth DATA-ALIAS leg (Changebound et al.) ---

    /// Changebound (`hit_penalty:1, over_in:9`, assets/solo/rules_mechanics_
    /// aof.json) is a Stealth-primitive alias, not the literal "Stealth" name
    /// — main.gd:5588-5610/5698-5701. Past 9" it penalizes the to-hit target
    /// by exactly its own `hit_penalty`, same direction as plain Stealth.
    #[test]
    fn changebound_penalizes_the_to_hit_target_past_nine_inches() {
        let changebound = Ctx { stealth_alias_penalty: 1, stealth_alias_over_in: 9.0, ..defender(4, 5) };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &changebound, 12.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 5, "Changebound -1 past 9\" raises Quality 4+ to 5+");
    }

    /// The SAME defender at or under 9" — Changebound's own `over_in` gate is
    /// closed, so the target is unmodified (main.gd's `gate <= 0.0 or dist_in
    /// > gate` reading; here `gate` is 9, `dist_in` is 9, not "over").
    #[test]
    fn changebound_does_nothing_at_or_under_nine_inches() {
        let changebound = Ctx { stealth_alias_penalty: 1, stealth_alias_over_in: 9.0, ..defender(4, 5) };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &changebound, 9.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 4, "at exactly 9\", Changebound has not fired");
    }

    /// Plain Stealth (the literal name) is unaffected by the new alias fields
    /// staying at their zero default — the pre-existing fixed-constant path
    /// (`Ctx.stealth` + `STEALTH_HIT_PENALTY`/`LONG_RANGE_IN`) stays exactly
    /// as before this leg was added. And when BOTH the literal flag and an
    /// alias are somehow set on the same Ctx, the alias must NOT also apply
    /// on top — "at most one" penalty (main.gd's `not (stealth and over_nine)`
    /// guard), so the net target is identical to plain Stealth alone.
    #[test]
    fn plain_stealth_is_unchanged_and_never_stacks_with_an_alias() {
        let plain = Ctx { stealth: true, ..defender(4, 5) };
        let mut t1 = Tray::seeded(27);
        let out_plain = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &plain, 12.0, &mut t1,
        );
        assert_eq!(out_plain.rolls[0].target, 5, "plain Stealth -1 past 9\" raises 4+ to 5+");

        let both = Ctx { stealth: true, stealth_alias_penalty: 1, stealth_alias_over_in: 9.0, ..defender(4, 5) };
        let mut t2 = Tray::seeded(27);
        let out_both = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &both, 12.0, &mut t2,
        );
        assert_eq!(out_both.rolls[0].target, 5, "no double-dip: same target as plain Stealth alone");
    }

    /// The reported corpus finding itself: a Good Shot bearer (+1, block B4)
    /// shooting a Changebound-carrying target (-1, this leg) past 9" nets to
    /// UNMODIFIED — Quality stands as printed. This is the exact stack
    /// `dice_gate.py --only-rule "Good Shot"` found diverging against
    /// `qag_ref` before this fix (Chameleons, quality 5, vs Rift Daemons of
    /// Change's Changebound).
    #[test]
    fn good_shot_and_changebound_cancel_past_nine_inches() {
        let good = [ShootProfile { hit_bonus: 1, ..rifle(1) }];
        let changebound = Ctx { stealth_alias_penalty: 1, stealth_alias_over_in: 9.0, ..defender(5, 5) };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &good, &[0], &[1], &shooter(5), &changebound, 12.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 5, "Good Shot +1 and Changebound -1 cancel: Quality 5+ stands");
    }
