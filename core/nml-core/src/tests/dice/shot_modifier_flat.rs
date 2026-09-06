use super::*;

    // ------------- block C3: Shot Modifier, the flat / over-9" siblings ---

    /// Buccaneer's `over_in: 9` routes its +1 into `hit_bonus_over9` —
    /// `stamp_shot_modifier`'s own `param_f("over_in", 0.0) > 0.0` branch, no
    /// new code — so the bonus helps strictly past 9" and is absent at or
    /// under it. RED (drop the `over_in` branch): the +1 becomes flat and the
    /// 6" rifle flips to 3+.
    #[test]
    fn a_buccaneer_carrier_improves_past_nine_inches_and_not_at_or_under() {
        let us = c3_static("buccaneer");
        assert_eq!(us.shoot[0].hit_bonus_over9, 1, "stamped into the over-9\" bucket");
        assert_eq!(us.shoot[0].hit_bonus, 0, "and never into the flat one");
        let mut t_over = Tray::seeded(27);
        let over = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &us.ctx, &defender(4, 5), 12.0, &mut t_over);
        assert_eq!(over.rolls[0].target, 3, "past 9\": Quality 4+ -> 3+");
        let mut t_at = Tray::seeded(27);
        let at = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &us.ctx, &defender(4, 5), 9.0, &mut t_at);
        assert_eq!(at.rolls[0].target, 4, "exactly 9\" is not \"over\" (main.gd's own wording)");
        let mut t_under = Tray::seeded(27);
        let under = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &us.ctx, &defender(4, 5), 6.0, &mut t_under);
        assert_eq!(under.rolls[0].target, 4, "under 9\": no bonus");
    }

    /// Targeting Visor Boost carries no `over_in`, so it lands in the flat
    /// bucket and improves the to-hit at EVERY range. RED (drop the name from
    /// `stamp_shot_modifier`'s array): the rifle stays at Quality 4+.
    #[test]
    fn a_targeting_visor_boost_carrier_improves_at_every_range() {
        let us = c3_static("visor_boost");
        assert_eq!(us.shoot[0].hit_bonus, 1, "flat bucket");
        assert_eq!(us.shoot[0].hit_bonus_over9, 0);
        for dist in [6.0, 9.0, 12.0] {
            let mut tray = Tray::seeded(27);
            let out = resolve_shooting_with_tray(
                &us.shoot, &[0], &[1], &us.ctx, &defender(4, 5), dist, &mut tray);
            assert_eq!(out.rolls[0].target, 3, "{dist}\": the flat +1 applies everywhere");
        }
    }
