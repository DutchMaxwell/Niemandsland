use super::*;

    // ------------------------------------ block B4: Shot Modifier family ---

    /// Good Shot (+1) and Bad Shot (-1) — main.gd:5681-5701 — are flat, no
    /// range gate: both move the target by exactly one at 6" (well inside 9").
    #[test]
    fn good_shot_and_bad_shot_move_the_to_hit_target_by_one() {
        let good = [ShootProfile { hit_bonus: 1, ..rifle(1) }];
        let mut t1 = Tray::seeded(27);
        let out_good = resolve_shooting_with_tray(
            &good, &[0], &[1], &shooter(4), &defender(4, 5), 6.0, &mut t1,
        );
        assert_eq!(out_good.rolls[0].target, 3, "Good Shot +1 lowers Quality 4+ to 3+");

        let bad = [ShootProfile { hit_bonus: -1, ..rifle(1) }];
        let mut t2 = Tray::seeded(27);
        let out_bad = resolve_shooting_with_tray(
            &bad, &[0], &[1], &shooter(4), &defender(4, 5), 6.0, &mut t2,
        );
        assert_eq!(out_bad.rolls[0].target, 5, "Bad Shot -1 raises Quality 4+ to 5+");
    }

    /// Targeting Visor (+1) is gated behind `over_in: 9` — main.gd:5693-5694 —
    /// so it does nothing at or under 9" and only helps strictly past it.
    #[test]
    fn targeting_visor_only_helps_strictly_past_nine_inches() {
        let p = [ShootProfile { hit_bonus_over9: 1, ..rifle(1) }];
        let mut under = Tray::seeded(27);
        let out_under = resolve_shooting_with_tray(
            &p, &[0], &[1], &shooter(4), &defender(4, 5), 6.0, &mut under,
        );
        assert_eq!(out_under.rolls[0].target, 4, "under 9\": no bonus");

        let mut exactly = Tray::seeded(27);
        let out_exactly = resolve_shooting_with_tray(
            &p, &[0], &[1], &shooter(4), &defender(4, 5), 9.0, &mut exactly,
        );
        assert_eq!(out_exactly.rolls[0].target, 4, "exactly 9\" is not \"over\" (main.gd's own wording)");

        let mut over = Tray::seeded(27);
        let out_over = resolve_shooting_with_tray(
            &p, &[0], &[1], &shooter(4), &defender(4, 5), 12.0, &mut over,
        );
        assert_eq!(out_over.rolls[0].target, 3, "past 9\": the +1 lowers Quality 4+ to 3+");
    }

    /// Good Shot's flat +1 stacks with the target's Stealth -1 (both apply past
    /// 9", `AiCombatMath.shooting_hit_modifier` :230-243) — here they exactly
    /// cancel, so the carrier's Good Shot buys back Stealth's own penalty.
    #[test]
    fn good_shot_stacks_with_and_can_offset_the_stealth_penalty() {
        let stealthy = Ctx { stealth: true, ..defender(4, 5) };
        let mut plain = Tray::seeded(27);
        let out_plain = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &stealthy, 12.0, &mut plain,
        );
        assert_eq!(out_plain.rolls[0].target, 5, "Stealth alone: -1 raises Quality 4+ to 5+");

        let good = [ShootProfile { hit_bonus: 1, ..rifle(1) }];
        let mut offset = Tray::seeded(27);
        let out_offset = resolve_shooting_with_tray(
            &good, &[0], &[1], &shooter(4), &stealthy, 12.0, &mut offset,
        );
        assert_eq!(out_offset.rolls[0].target, 4, "Good Shot +1 cancels Stealth's -1, back to 4+");
    }

    /// NML-1152 — the over-9" modifier gate is `mod_dist_in` (unit centre to
    /// unit centre, main.gd:3029), never `dist_in` (the range-VALIDITY edge
    /// gap, B11). Numbers are the corpus find (qag_ref act 24, PLAN NML-1152):
    /// edge gap 7.95" (<= 9", range gate) but centre gap 14.30" (> 9",
    /// modifier gate) — Stealth must fire off the WIDER centre gap even
    /// though the closer edge gap is the one that let the shot reach at all.
    #[test]
    fn the_modifier_gate_fires_off_the_centre_gap_even_when_the_range_gap_is_closer() {
        let p = [rifle(1)];
        let stealthy = Ctx { stealth: true, ..defender(4, 5) };
        let att = shooter(4);
        let sh = [Shooter { profiles: &p, keep: &[0], attacks: &[1], att: &att, owner: "" }];
        let mut tray = Tray::seeded(27);
        let out = resolve_volley_with_tray(&sh, &stealthy, "Target", 7.95, 14.30, true, true, true, true, &mut tray);
        assert_eq!(out.rolls[0].target, 5, "Stealth -1 off the 14.30\" centre gap");
    }

    /// The flip's other direction: the range gap alone is over 9" (12") but
    /// the centre gap is not (6") — the table stays silent, RED for a bug
    /// that read the range gap for the modifier (it would fire here).
    #[test]
    fn the_modifier_gate_stays_silent_when_only_the_range_gap_is_over_nine() {
        let p = [rifle(1)];
        let stealthy = Ctx { stealth: true, ..defender(4, 5) };
        let att = shooter(4);
        let sh = [Shooter { profiles: &p, keep: &[0], attacks: &[1], att: &att, owner: "" }];
        let mut tray = Tray::seeded(27);
        let out = resolve_volley_with_tray(&sh, &stealthy, "Target", 12.0, 6.0, true, true, true, true, &mut tray);
        assert_eq!(out.rolls[0].target, 4, "no Stealth penalty: the 6\" centre gap is not over 9\"");
    }

    /// The book's floor and ceiling (`AiCombatMath.modified_hit_target` :222-223,
    /// clamped to [2, 6]) still hold once Shot Modifier stacks with the other
    /// modifiers in this function — real combinations, not synthetic numbers.
    #[test]
    fn shot_modifier_stacking_never_breaks_the_book_bounds() {
        // Floor: Quality 2+ (best already) + attacker Artillery (+1, past 9")
        // + Good Shot (+1 flat) would be target -2 unclamped; the book floors
        // it at 2+.
        let artillery_att = Ctx { artillery: true, ..shooter(2) };
        let good = [ShootProfile { hit_bonus: 1, ..rifle(1) }];
        let mut floor = Tray::seeded(27);
        let out_floor = resolve_shooting_with_tray(
            &good, &[0], &[1], &artillery_att, &defender(4, 5), 12.0, &mut floor,
        );
        assert_eq!(out_floor.rolls[0].target, 2, "clamped at the 2+ floor");

        // Ceiling: Quality 6+ (worst already) into Stealth (-1, past 9") +
        // Evasive (-1, any range) + Bad Shot (-1 flat) would be target 9+
        // unclamped; the book ceilings it at 6+.
        let bad = [ShootProfile { hit_bonus: -1, ..rifle(1) }];
        let hard_target = Ctx { stealth: true, evasive: true, ..defender(4, 5) };
        let mut ceiling = Tray::seeded(27);
        let out_ceiling = resolve_shooting_with_tray(
            &bad, &[0], &[1], &shooter(6), &hard_target, 12.0, &mut ceiling,
        );
        assert_eq!(out_ceiling.rolls[0].target, 6, "clamped at the 6+ ceiling");
    }

    /// NO BEARER: a unit carrying none of Good Shot / Bad Shot / Targeting
    /// Visor stamps a default `ShootProfile` (`hit_bonus`/`hit_bonus_over9`
    /// both 0, `unit.rs::stamp_shot_modifier`'s no-op case) and must resolve
    /// exactly like the pre-B4 baseline — the first shooting-order test above.
    #[test]
    fn no_bearer_leaves_the_to_hit_target_unmodified() {
        let p = [rifle(1)];
        assert_eq!(p[0].hit_bonus, 0);
        assert_eq!(p[0].hit_bonus_over9, 0);
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &p, &[0], &[1], &shooter(4), &defender(4, 5), 12.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 4, "Quality 4+ at 12\", no Shot Modifier carrier");
    }
