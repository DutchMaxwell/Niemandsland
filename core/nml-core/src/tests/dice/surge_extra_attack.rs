use super::*;

    // ------------------------------ block B6: the extra-ATTACK-DIE family ---

    /// Seed 9 rolls exactly two unmodified 6s in an 8-die attack — the shape
    /// of the worked corpus act (`qag_ref` s28#19: 10@5+ then a separate
    /// 2@5+ `[6,3]`, exactly its two 6s). One extra roll of TWO dice, at the
    /// SAME target as the primary roll (the "right slot"), and its hits fold
    /// into the save batch.
    #[test]
    fn two_unmodified_sixes_draw_one_extra_roll_of_two_dice_at_the_same_target() {
        let want_primary = Tray::seeded(9).roll(8);
        assert_eq!(want_primary.iter().filter(|&&f| f == 6).count(), 2, "fixture: seed 9 must roll two 6s");
        let want_extra = {
            let mut t = Tray::seeded(9);
            t.roll(8);
            t.roll(2)
        };
        let p = [ShootProfile { surge_attack: true, ..rifle(8) }];
        let mut tray = Tray::seeded(9);
        let out = resolve_shooting_with_tray(&p, &[0], &[8], &shooter(4), &defender(4, 5), 12.0, &mut tray);
        assert_eq!(out.rolls.len(), 3, "hit roll, one extra roll, one save batch: {:?}", out.rolls);
        assert_eq!(out.rolls[0].faces, want_primary);
        assert_eq!(out.rolls[1].kind, "attack");
        assert_eq!(out.rolls[1].count, 2, "one extra die per unmodified 6");
        assert_eq!(out.rolls[1].target, 4, "the same to-hit target as the primary roll");
        assert_eq!(out.rolls[1].faces, want_extra);
        let want_hits = faces_to_hits(&want_primary, 4) as i64 + faces_to_hits(&want_extra, 4) as i64;
        assert_eq!(out.rolls[2].kind, "defense");
        assert_eq!(out.rolls[2].count, want_hits, "the extras' hits are in the save batch's die count");
    }

    /// Zero unmodified 6s (seed 4) draws nothing extra — the same rifle as
    /// above, just an unlucky roll.
    #[test]
    fn zero_unmodified_sixes_draws_nothing() {
        let want_primary = Tray::seeded(4).roll(8);
        assert_eq!(want_primary.iter().filter(|&&f| f == 6).count(), 0, "fixture: seed 4 must roll no 6s");
        // `surge_attack_low: 6` (unboosted) matters here: seed 4 also rolls one
        // unmodified 5, which the fixture's `rifle()` would otherwise leave at
        // the raw i64 default 0 (< 6, silently "boosted") — the same trap
        // `base_profile` guards against on the real construction path.
        let p = [ShootProfile { surge_attack: true, surge_attack_low: 6, ..rifle(8) }];
        let mut tray = Tray::seeded(4);
        let out = resolve_shooting_with_tray(&p, &[0], &[8], &shooter(4), &defender(4, 5), 12.0, &mut tray);
        assert_eq!(out.rolls.len(), 2, "hit roll and save batch only, no extra draw: {:?}", out.rolls);
    }

    /// NEGATIVE: the same two-six seed (9), but the weapon does not carry the
    /// rule — `surge_attack` defaults to false, so the two 6s draw nothing.
    #[test]
    fn without_the_rule_two_sixes_draw_nothing() {
        let p = [rifle(8)];
        let mut tray = Tray::seeded(9);
        let out = resolve_shooting_with_tray(&p, &[0], &[8], &shooter(4), &defender(4, 5), 12.0, &mut tray);
        assert_eq!(out.rolls.len(), 2, "no `surge_attack` flag, no extra roll: {:?}", out.rolls);
    }

    /// Primal Boost et al. (`surge_attack_low: 5`): a successful unmodified 5
    /// ALSO draws an extra die. Seed 6 at Quality 5+ rolls one 6 and two 5s
    /// (both `>= to_hit`) — unboosted that is one extra die, boosted three.
    #[test]
    fn primal_boost_also_spawns_an_extra_die_on_a_successful_unmodified_five() {
        let primary = Tray::seeded(6).roll(8);
        assert_eq!(primary.iter().filter(|&&f| f == 6).count(), 1, "fixture: seed 6 must roll one 6");
        assert_eq!(primary.iter().filter(|&&f| f == 5).count(), 2, "fixture: seed 6 must roll two 5s");
        let unboosted = [ShootProfile { surge_attack: true, surge_attack_low: 6, ..rifle(8) }];
        let mut t1 = Tray::seeded(6);
        let out1 = resolve_shooting_with_tray(&unboosted, &[0], &[8], &shooter(5), &defender(4, 5), 12.0, &mut t1);
        assert_eq!(out1.rolls[1].count, 1, "unboosted: only the one unmodified 6");
        let boosted = [ShootProfile { surge_attack: true, surge_attack_low: 5, ..rifle(8) }];
        let mut t2 = Tray::seeded(6);
        let out2 = resolve_shooting_with_tray(&boosted, &[0], &[8], &shooter(5), &defender(4, 5), 12.0, &mut t2);
        assert_eq!(out2.rolls[1].count, 3, "boosted: the 6 plus both successful 5s");
    }

    /// The extras NEVER re-trigger, even when one of them rolls its own
    /// unmodified 6 (seed 75: one 6 in the primary roll, and the one extra die
    /// that draws is itself a 6). Exactly one extra roll, never a second.
    #[test]
    fn the_extra_dice_never_retrigger_on_their_own_sixes() {
        let p = [ShootProfile { surge_attack: true, ..rifle(8) }];
        let mut tray = Tray::seeded(75);
        let out = resolve_shooting_with_tray(&p, &[0], &[8], &shooter(4), &defender(4, 5), 12.0, &mut tray);
        assert_eq!(out.rolls.len(), 3, "hit roll, ONE extra roll, save batch — never a second extra roll: {:?}", out.rolls);
        assert_eq!(out.rolls[1].count, 1);
        assert_eq!(out.rolls[1].faces, vec![6], "fixture: the one extra die is itself a natural 6");
    }

    /// Melee strikes draw their own extra attack die too (`_solo_hits` is
    /// shared by both call sites) — the same two-six seed as the shooting
    /// case, through `resolve_melee_with_tray` instead.
    #[test]
    fn melee_strikes_draw_their_own_extra_attack_die_too() {
        let p = [ShootProfile { surge_attack: true, ..blade(8) }];
        let att = Ctx { quality: 4, models: 1, ..Default::default() };
        let mut tray = Tray::seeded(9);
        let out = resolve_melee_with_tray(&[striker(&p, &[0], &[8], &att)], &defender(4, 5), "Target", false, true, true, &mut tray);
        assert_eq!(out.rolls.len(), 3, "hit roll, one extra roll, one save batch: {:?}", out.rolls);
        assert_eq!(out.rolls[1].kind, "attack");
        assert_eq!(out.rolls[1].count, 2, "the same two unmodified 6s as the shooting case");
        assert_eq!(out.rolls[1].target, 4);
    }
