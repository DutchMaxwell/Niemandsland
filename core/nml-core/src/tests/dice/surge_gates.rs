use super::*;

    // ------------- epoch 3: the plain auto-hit Surge's own gates ---

    /// Point-Blank Surge's `surge_within_in` (main.gd:4465-4467): past 12" the
    /// whole bonus stays behind the gate at the current epoch; epoch 0 keeps
    /// the ungated read; exactly 12" opens it; no stamped gate fires at any
    /// range. Seed 9: two unmodified 6s in 8 dice.
    #[test]
    fn point_blank_surge_keeps_its_sixes_behind_the_within_gate_past_twelve_inches() {
        use crate::acts::{rule_on, CURRENT_RULES_EPOCH};
        let want = Tray::seeded(9).roll(8);
        assert_eq!(want.iter().filter(|&&f| f == 6).count(), 2, "fixture: seed 9 must roll two 6s");
        let base = faces_to_hits(&want, 4) as i64;
        let pb = [ShootProfile { surge: true, surge_within_in: 12.0, surge_low: 6, ..rifle(8) }];
        let plain = [ShootProfile { surge: true, surge_low: 6, ..rifle(8) }];
        let fresh = rule_on(CURRENT_RULES_EPOCH, CURRENT_RULES_EPOCH);
        let legacy = rule_on(0, CURRENT_RULES_EPOCH);
        let mut t = Tray::seeded(9);
        assert_eq!(surge_volley(&pb, 4, 13.0, fresh, &mut t).rolls[1].count, base,
            "past 12\": the sixes stay behind the gate");
        let mut t = Tray::seeded(9);
        assert_eq!(surge_volley(&pb, 4, 13.0, legacy, &mut t).rolls[1].count, base + 2,
            "epoch 0: the ungated read still fires");
        let mut t = Tray::seeded(9);
        assert_eq!(surge_volley(&pb, 4, 12.0, fresh, &mut t).rolls[1].count, base + 2,
            "exactly 12\": the gate is open (dist <= within)");
        let mut t = Tray::seeded(9);
        assert_eq!(surge_volley(&plain, 4, 13.0, fresh, &mut t).rolls[1].count, base + 2,
            "no gate stamped: Surge fires at any range");
    }

    /// Devout Boost (gf blessed_sisters: `surge_low: 5`, `over_in: 9`, upgrades
    /// "Devout", main.gd:4469): successful unmodified 5s count only past 9" at
    /// the current epoch; epoch 0 keeps the unboosted read; `surge_low` 6 never
    /// counts 5s. Seed 6: one 6 plus two 5s in 8 dice.
    #[test]
    fn devout_boost_counts_successful_fives_only_past_nine_inches() {
        use crate::acts::{rule_on, CURRENT_RULES_EPOCH};
        let want = Tray::seeded(6).roll(8);
        assert_eq!(want.iter().filter(|&&f| f == 6).count(), 1, "fixture: seed 6 must roll one 6");
        assert_eq!(want.iter().filter(|&&f| f == 5).count(), 2, "fixture: seed 6 must roll two 5s");
        let base = faces_to_hits(&want, 4) as i64;
        let boosted = [ShootProfile { surge: true, surge_low: 5, surge_over_in: 9.0, ..rifle(8) }];
        let unboosted = [ShootProfile { surge: true, surge_low: 6, ..rifle(8) }];
        let fresh = rule_on(CURRENT_RULES_EPOCH, CURRENT_RULES_EPOCH);
        let legacy = rule_on(0, CURRENT_RULES_EPOCH);
        let mut t = Tray::seeded(6);
        assert_eq!(surge_volley(&boosted, 4, 10.0, fresh, &mut t).rolls[1].count, base + 3,
            "past 9\": the 6 plus both successful 5s");
        let mut t = Tray::seeded(6);
        assert_eq!(surge_volley(&boosted, 4, 10.0, legacy, &mut t).rolls[1].count, base + 1,
            "epoch 0: the boost is unread, the 6 alone");
        let mut t = Tray::seeded(6);
        assert_eq!(surge_volley(&unboosted, 4, 10.0, fresh, &mut t).rolls[1].count, base + 1,
            "no Devout Boost (`surge_low` 6): the 5s count for nothing");
        let mut t = Tray::seeded(6);
        assert_eq!(surge_volley(&boosted, 4, 9.0, fresh, &mut t).rolls[1].count, base + 1,
            "exactly 9\" is not over 9\": the gate stays shut");
    }

    /// Ferocious Boost (gf/aof orcs, the same boost shape): its 5s never fire
    /// in MELEE — the table resolves melee at dist 0.0 (main.gd:6103), never
    /// "over 9"" — and a 5 below the to-hit target is never a "successful" hit
    /// (main.gd:4471's `5 >= to_hit`).
    #[test]
    fn ferocious_boosts_fives_never_fire_in_melee_or_below_their_target() {
        use crate::acts::{rule_on, CURRENT_RULES_EPOCH};
        let want = Tray::seeded(6).roll(8);
        assert_eq!(want.iter().filter(|&&f| f == 5).count(), 2, "fixture: seed 6 must roll two 5s");
        let boosted = [ShootProfile { surge: true, surge_low: 5, surge_over_in: 9.0, ..rifle(8) }];
        let fresh = rule_on(CURRENT_RULES_EPOCH, CURRENT_RULES_EPOCH);
        let att = Ctx { quality: 4, models: 1, ..Default::default() };
        let mut t = Tray::seeded(6);
        let melee = resolve_melee_with_tray(
            &[striker(&boosted, &[0], &[8], &att)], &defender(4, 5), "Target", false, true, true, &mut t);
        assert_eq!(melee.rolls[1].count, faces_to_hits(&want, 4) as i64 + 1,
            "melee resolves at 0.0\": sixes only, the boost's 5s stay shut");
        let mut t = Tray::seeded(6);
        assert_eq!(surge_volley(&boosted, 6, 10.0, fresh, &mut t).rolls[1].count, 2,
            "a 5 never beats a 6+ target: the one unmodified 6 alone");
    }

    /// Lucky Boost (aof halflings, the third boost twin): the 9" gate is the
    /// strict `dist_in > surge_over_in` — exactly 9" stays shut, 9.5" opens.
    #[test]
    fn lucky_boosts_five_bonus_opens_only_strictly_past_nine_inches() {
        use crate::acts::{rule_on, CURRENT_RULES_EPOCH};
        let want = Tray::seeded(6).roll(8);
        assert_eq!(want.iter().filter(|&&f| f == 6).count(), 1, "fixture: seed 6 must roll one 6");
        let base = faces_to_hits(&want, 4) as i64;
        let boosted = [ShootProfile { surge: true, surge_low: 5, surge_over_in: 9.0, ..rifle(8) }];
        let fresh = rule_on(CURRENT_RULES_EPOCH, CURRENT_RULES_EPOCH);
        let legacy = rule_on(0, CURRENT_RULES_EPOCH);
        let mut t = Tray::seeded(6);
        assert_eq!(surge_volley(&boosted, 4, 9.0, fresh, &mut t).rolls[1].count, base + 1,
            "exactly 9.0\": strictly-past fails, the 6 alone");
        let mut t = Tray::seeded(6);
        assert_eq!(surge_volley(&boosted, 4, 9.5, fresh, &mut t).rolls[1].count, base + 3,
            "9.5\": the gate opens, the 6 plus both 5s");
        let mut t = Tray::seeded(6);
        assert_eq!(surge_volley(&boosted, 4, 9.5, legacy, &mut t).rolls[1].count, base + 1,
            "epoch 0: the ungated read never counts 5s");
    }
