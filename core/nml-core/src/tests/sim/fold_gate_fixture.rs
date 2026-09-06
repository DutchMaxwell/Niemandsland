use super::*;

    // --- Wave 2 fold-gate fixture: one live grant of `rule` on unit 0. ---

    /// WAVE 3 — the Fortified family's live-grant leg: a spell granting one of
    /// the three Boost names folds the AP(-1) stamp at epoch 6 only (frozen
    /// `EPOCH_6_TABLE_RULES`; epoch 5 is the Gen-3 fleet's window), and a
    /// non-family grant folds nothing.
    #[test]
    fn fortified_boost_grants_fold_the_ap_stamp_at_epoch_6_only() {
        for rule in ["Guardian Boost", "Warden Boost", "Ossified Boost"] {
            let on = fold_leg(rule, 6);
            assert_eq!(on.fortified_boost_ap, 1, "{rule} folds its AP(-1) at 6");
        }
        let off = fold_leg("Guardian Boost", 5);
        assert_eq!(off.fortified_boost_ap, 0, "epoch 5 replays the Gen-0 set");
        let other = fold_leg("Self-Repair Boost", 6);
        assert_eq!(other.fortified_boost_ap, 0, "only the family's own names fold");
    }

    #[test]
    fn the_unpredictable_shooter_mark_sets_the_shooting_die_leg_at_epoch_5_only() {
        assert!(fold_leg("Unpredictable Shooter", 5).unpredictable_shooting);
        assert!(
            !fold_leg("Unpredictable Shooter", 4).unpredictable_shooting,
            "rules_epoch 4 is Gen-2b's stamping-gap window (acts::EPOCH_5_TABLE_RULES), RED before the fix"
        );
        let (statics, st) = fold_legs("Unpredictable Shooter");
        assert!(!ctx_live(statics[0].ctx.clone(), &statics, &st, 2, false, 5).unpredictable_shooting,
            "the leg rides the GRANT, not the bare bearer");
    }

    #[test]
    fn self_repair_boost_buff_folds_the_regen_target_at_epoch_5_only() {
        let on = fold_leg("Self-Repair Boost", 5);
        assert!(on.regeneration && on.regen_target == SELF_REPAIR_BOOST_TARGET);
        assert_eq!(on.regen_target_spell, SELF_REPAIR_BOOST_TARGET);
        let off = fold_leg("Self-Repair Boost", 4);
        assert!(
            !off.regeneration && off.regen_target == 0,
            "rules_epoch 4 (Gen-2b's stamping-gap window) replays the Gen-0 set, RED before the fix"
        );
        let (statics, st) = fold_legs("Self-Repair Boost");
        let mut regen6 = Ctx { regeneration: true, regen_target: 6, regen_target_spell: 6, ..statics[0].ctx.clone() };
        let mixed = ctx_live(regen6, &statics, &st, 0, false, 5);
        assert_eq!(mixed.regen_target, 5, "the running MIN picks the granted 5+");
        assert_eq!(mixed.regen_target_spell, 5);
    }

    #[test]
    fn cursed_undead_and_angelic_blessing_boost_buffs_fold_their_printed_legs() {
        let cursed = fold_leg("Cursed Undead Boost", 5);
        assert!(cursed.regeneration && cursed.regen_target == CURSED_UNDEAD_BOOST_TARGET);
        let angelic = fold_leg("Angelic Blessing Boost", 5);
        assert_eq!(angelic.regen_target_spell, ANGELIC_BLESSING_BOOST_TARGET_SPELL);
        assert!(!angelic.regeneration, "spell_only never touches the normal leg");
        let off = fold_leg("Cursed Undead Boost", 4);
        assert!(
            !off.regeneration && off.regen_target_spell == 0,
            "rules_epoch 4 is Gen-2b's stamping-gap window, RED before the fix"
        );
    }

    #[test]
    fn hold_the_line_boost_buff_joins_the_morale_net_at_epoch_5_only() {
        let (statics, mut st) = fold_legs("Hold the Line Boost");
        let mut tray = Tray::seeded(5);
        let mut mshot = ShootResult::default();
        tray_morale(&mut st.clone(), &statics[0], 0, false, 5, &mut tray, &mut mshot);
        let on = mshot.rolls[0].target;
        st.buffs[0].clear();
        let mut tray_b = Tray::seeded(5);
        let mut mshot_b = ShootResult::default();
        tray_morale(&mut st, &statics[0], 0, false, 5, &mut tray_b, &mut mshot_b);
        assert_eq!(on, (mshot_b.rolls[0].target - HOLD_THE_LINE_BOOST_MORALE_BONUS).clamp(2, 6),
            "epoch 5: the printed morale_bonus 2 joins the same [2,6]-clamped net");

        // RED before the fix: rules_epoch 4 (Gen-2b's stamping-gap window)
        // must NOT get the buff either, only 3 did before this change.
        let (statics2, mut st2) = fold_legs("Hold the Line Boost");
        let mut tray2 = Tray::seeded(5);
        let mut mshot2 = ShootResult::default();
        tray_morale(&mut st2.clone(), &statics2[0], 0, false, 4, &mut tray2, &mut mshot2);
        st2.buffs[0].clear();
        let mut tray2_b = Tray::seeded(5);
        let mut mshot2_b = ShootResult::default();
        tray_morale(&mut st2, &statics2[0], 0, false, 4, &mut tray2_b, &mut mshot2_b);
        assert_eq!(
            mshot2.rolls[0].target, mshot2_b.rolls[0].target,
            "rules_epoch 4 gets none of the buff — buffed and unbuffed targets match"
        );
    }
    #[test]
    fn the_unwieldy_debuff_strikes_the_granted_charger_last_at_epoch_5_only() {
        let (statics, st) = fold_legs("Unwieldy");
        let (st2, statics2) = buff_line();
        let s5 = Seams { rules_epoch: 5, ..Seams::default() };
        let s4 = Seams { rules_epoch: 4, ..Seams::default() };
        assert!(charger_strikes_last(&statics, &st, 0, s5));
        assert!(
            !charger_strikes_last(&statics, &st, 0, s4),
            "rules_epoch 4 is Gen-2b's stamping-gap window, RED before the fix"
        );
        assert!(!charger_strikes_last(&statics2, &st2, 0, s5), "no rule, no leg");
    }

    /// EPOCH GATES BY RECORDING SHA (05.09.): unlike Lacerate (merged BEFORE
    /// the Gen-2b fleet launched, `acts::EPOCH_4_TABLE_RULES`), the Shred
    /// Boost family (`#678`) merged AFTER the fleet closed — a record
    /// stamping `rules_epoch: 4` (Gen-2b included) must not get its widened
    /// save-fail window. RED on unfixed main: `resolve_with`'s call site
    /// still reads the literal `4`, so `shred_boost_active(4)` is `true`.
    #[test]
    fn shred_boost_active_needs_epoch_5_not_the_recorders_epoch_4() {
        assert!(shred_boost_active(5), "rules_epoch 5 (recorded after Shred merged) gets the widened window");
        assert!(
            !shred_boost_active(4),
            "rules_epoch 4 is Gen-2b's recording epoch: Shred merged after the fleet closed, RED before the fix"
        );
        assert!(!shred_boost_active(3), "epoch 3 predates the Shred Boost family entirely");
    }

    /// B2b — the two write-half names. Casting Buff picks by the
    /// `friendly_caster` filter (`a` is no caster, `ah` is) and records
    /// `casting_mod`; Primal Boost Buff records the rule GRANT on the
    /// best-value friendly. Neither has a consumer on this core's tray path —
    /// there is no cast die here at all, and a granted Surge cannot re-stamp a
    /// baked weapon profile — so the proof is the record, not a number.
    /// Without the rule on the bearer nothing is written at all.
    #[test]
    fn casting_and_primal_boost_buffs_land_their_records_on_the_right_pick() {
        let (st, mut statics) = buff_line();
        statics[1].is_caster = true;
        statics[0].utility_buffs = vec![UtilityBuff {
            casting_mod: 1,
            target: "friendly_caster".into(),
            ..ub("Casting Buff")
        }];
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(next.buffs[0].is_empty(), "the bearer is no caster — the filter refuses it");
        assert_eq!(next.buffs[1].len(), 1);
        assert_eq!(next.buffs[1][0].casting_mod, 1);

        statics[0].utility_buffs = vec![UtilityBuff {
            grants_rule: "Primal Boost".into(),
            ..ub("Primal Boost Buff")
        }];
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert_eq!(&*next.buffs[0][0].grants_rule, "Primal Boost");
        assert!(!crate::mods::granted(&next, 0, "Unstoppable"));

        // No rule on the bearer, no record — the ledger stays empty.
        statics[0].utility_buffs = vec![];
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(next.buffs.iter().all(|v| v.is_empty()));
    }
