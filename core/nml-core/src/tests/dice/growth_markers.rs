use super::*;

    // -------------------------------------- block B7: Growth Markers ---

    /// Piercing Growth: main.gd:4287's marker-driven AP delta (folded into
    /// `Ctx.growth_ap_mod` by `sim::ctx_live`) lands on the SAVE target the
    /// table's own arithmetic reads (`save_target`, defense + max(ap, 0)) —
    /// shooting and melee both, since `_solo_attack_groups` adds it to `prof
    /// ["ap"]` regardless of which the caller built profiles for.
    #[test]
    fn piercing_growth_raises_the_ap_on_both_the_shooting_and_the_melee_save() {
        let plain_att = shooter(4);
        let grown_att = Ctx { growth_ap_mod: 1, ..shooter(4) };
        let mut t1 = Tray::seeded(27);
        let plain = resolve_shooting_with_tray(
            &[rifle(6)], &[0], &[6], &plain_att, &defender(4, 5), 12.0, &mut t1,
        );
        assert_eq!(plain.rolls[1].target, 4, "Defense 4+, AP(0)");
        let mut t2 = Tray::seeded(27);
        let grown = resolve_shooting_with_tray(
            &[rifle(6)], &[0], &[6], &grown_att, &defender(4, 5), 12.0, &mut t2,
        );
        assert_eq!(grown.rolls[1].target, 5, "Defense 4+, AP(+1) from the marker");

        let ccw = [ShootProfile { name: "CCW".into(), attacks: 6, count: 1, range: 0, ..Default::default() }];
        let strikers = [Shooter { profiles: &ccw, keep: &[0], attacks: &[6], att: &grown_att, owner: "" }];
        let mut t3 = Tray::seeded(27);
        let melee = resolve_melee_with_tray(&strikers, &defender(4, 5), "", false, true, true, &mut t3);
        assert_eq!(melee.rolls[1].target, 5, "the SAME AP delta reaches the melee save too");
    }

    /// Precision Frenzy: main.gd:5677-5680's marker-driven hit bonus is
    /// SHOOTING ONLY — `_solo_hit_mod_info`'s melee branch (main.gd:5608-5648)
    /// returns before that code runs, so `melee_hit_target` never reads
    /// `growth_hit_mod` even though the SAME live `Ctx` carries it.
    #[test]
    fn precision_frenzy_raises_the_shooting_hit_target_and_never_the_melee_one() {
        let grown = Ctx { growth_hit_mod: 1, ..shooter(4) };
        let mut t1 = Tray::seeded(27);
        let shot = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &grown, &defender(4, 5), 12.0, &mut t1,
        );
        assert_eq!(shot.rolls[0].target, 3, "Precision Frenzy +1 lowers Quality 4+ to 3+");

        let ccw = [ShootProfile { name: "CCW".into(), attacks: 1, count: 1, range: 0, ..Default::default() }];
        let strikers = [Shooter { profiles: &ccw, keep: &[0], attacks: &[1], att: &grown, owner: "" }];
        let mut t2 = Tray::seeded(27);
        let melee = resolve_melee_with_tray(&strikers, &defender(4, 5), "", false, true, true, &mut t2);
        assert_eq!(melee.rolls[0].target, 4,
            "the hit facet is shooting-only: melee_hit_target never reads growth_hit_mod");
    }
