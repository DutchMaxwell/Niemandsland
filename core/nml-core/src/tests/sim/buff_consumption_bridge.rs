use super::*;

    // ------------------------------- BLOCK B2b: THE BUFF-CONSUMPTION BRIDGE ---

    /// WAVE 3 — the family's rules-must-log line on the volley leg: the alias
    /// arm actually lowered a save target (AP(1) rifle at 12", past Guardian's
    /// own 9" gate) and the report names the rule off the defender's stamp.
    /// The control (no alias) stays silent.
    #[test]
    fn a_guardian_save_one_better_past_nine_inches_logs_the_rule() {
        let (st, statics) = fortified_line(true);
        let (_, shot) = run_buff(&st, &statics, &buff_action(Some("b")), 27);
        assert!(
            shot.log.iter().any(|l| l.contains("Guardian") && l.contains("AP(-1)")),
            "rules-must-log: {:?}",
            shot.log
        );
        let (st2, plain) = fortified_line(false);
        let (_, plain_shot) = run_buff(&st2, &plain, &buff_action(Some("b")), 27);
        assert!(
            plain_shot.log.iter().all(|l| !l.contains("Guardian")),
            "no alias, no line: {:?}",
            plain_shot.log
        );
    }

    /// B2b — Precision Attacks Buff (`hit_mod: 1`, no scope): the bearer buffs
    /// itself at the pre-attack slot and the volley that follows in the SAME
    /// activation rolls at 3+ instead of the unit's plain Quality 4+. The
    /// control (no rule) and the scope negative (the same +1 printed
    /// `scope: "melee"`, which is Precision Fighter Buff) both stay at 4+ —
    /// so the number moves for the rule and for nothing else.
    #[test]
    fn precision_attacks_buff_improves_the_bearers_own_to_hit_target_by_one() {
        let (st, mut statics) = buff_line();
        let (_, plain) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!((plain.rolls[0].kind, plain.rolls[0].count, plain.rolls[0].target), ("attack", 1, 4));

        statics[0].utility_buffs = vec![UtilityBuff { hit_mod: 1, ..ub("Precision Attacks Buff") }];
        let (next, buffed) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!((buffed.rolls[0].kind, buffed.rolls[0].count, buffed.rolls[0].target), ("attack", 1, 3));
        // "once": the exchange that used it spends it (main.gd:3244).
        assert!(next.buffs.iter().all(|v| v.is_empty()));

        statics[0].utility_buffs =
            vec![UtilityBuff { hit_mod: 1, scope: "melee".into(), ..ub("Precision Fighter Buff") }];
        let (next, melee_only) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!(melee_only.rolls[0].target, 4, "a melee-scoped record is not a shooting bonus");
        // It was recorded, it just did not apply — and a shooting exchange does
        // not spend a melee record either (`mods_for`'s scope filter runs in
        // `spend_once` too).
        assert_eq!(next.buffs[0].len(), 1);
    }

    /// B2b — the stacking precedence: several live records SUM, and the sum
    /// meets the situational modifier in ONE `modified_hit_target`. Two +1s
    /// give 2+; a +1 against an Evasive defender nets 0 and leaves 4+, which
    /// clamping twice could never produce.
    #[test]
    fn two_live_hit_mods_sum_before_the_single_to_hit_clamp() {
        let (st, mut statics) = buff_line();
        statics[0].utility_buffs = vec![
            UtilityBuff { hit_mod: 1, ..ub("Precision Attacks Buff") },
            UtilityBuff { hit_mod: 1, ..ub("Precision Fighter Buff") },
        ];
        let (_, r) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!(r.rolls[0].target, 2);

        statics[0].utility_buffs = vec![UtilityBuff { hit_mod: 1, ..ub("Precision Attacks Buff") }];
        statics[2].ctx.evasive = true;
        let (_, r) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!(r.rolls[0].target, 4, "Evasive -1 and the buff +1 net to zero");
    }

    /// B2b — Precision Fighter Buff (`hit_mod: 1`, `scope: "melee"`) reaches the
    /// MELEE to-hit target of the charge it precedes: 3+ where the bare fixture
    /// strikes at 4+.
    #[test]
    fn precision_fighter_buff_reaches_the_melee_to_hit_target() {
        let (mut st, mut statics) = buff_line();
        st.positions[2] = vec![[2.5 * IN2M, 0.0, 0.0]];
        st.radii[2] = vec![IN2M];
        st.wounds[2] = vec![1];
        st.alive[2] = 1;
        statics[2].model_count = 1;
        statics[2].wounds_max = vec![1];
        let charge = Action {
            kind: CHARGE,
            unit: "a".into(),
            dest: None,
            shoot: None,
            charge: Some("b".into()),
            patient: false,
            split: None,
            traced: None,
        };
        let (_, plain) = run_buff(&st, &statics, &charge, 11);
        assert_eq!(plain.rolls[0].target, 4);

        statics[0].utility_buffs =
            vec![UtilityBuff { hit_mod: 1, scope: "melee".into(), ..ub("Precision Fighter Buff") }];
        let (_, buffed) = run_buff(&st, &statics, &charge, 11);
        assert_eq!(buffed.rolls[0].target, 3);
    }

    /// B2b — Morale Debuff (`morale_mod: -1`, `target: "enemy"`, 18",
    /// `needs_los`): the record lands on the enemy pick and worsens ITS morale
    /// target by one (`morale_target(4, -1)` = 5+), then the test spends it.
    /// Out of the printed range, and with sight blocked, nothing is recorded.
    #[test]
    fn morale_debuff_worsens_the_enemys_morale_target_and_is_spent_by_that_test() {
        let (st, mut statics) = buff_line();
        let debuff = UtilityBuff {
            morale_mod: -1,
            range_in: 18.0,
            target: "enemy".into(),
            needs_los: true,
            ..ub("Morale Debuff")
        };
        statics[0].utility_buffs = vec![debuff.clone()];
        let (mut next, shot) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(shot.rolls.is_empty(), "the buff arm is dice-free");
        assert_eq!(next.buffs[2].len(), 1);
        assert_eq!(next.buffs[2][0].morale_mod, -1);

        let mut tray = Tray::seeded(5);
        let mut mshot = ShootResult::default();
        tray_morale(&mut next, &statics[2], 2, false, 4, &mut tray, &mut mshot);
        assert_eq!(mshot.rolls[0].target, 5, "Quality 4+ tested at 5+ under the debuff");
        assert!(next.buffs[2].is_empty(), "main.gd:8303 — the test die spends it");

        // Out of the printed 18" range: no pick, no record.
        let mut far = st.clone();
        far.positions[2] = vec![[30.0 * IN2M, 0.0, 0.0]];
        far.alive[2] = 1;
        far.wounds[2] = vec![1];
        far.radii[2] = vec![IN2M];
        let (next, _) = run_buff(&far, &statics, &buff_action(None), 11);
        assert!(next.buffs.iter().all(|v| v.is_empty()));

        // In range, sight blocked: `needs_los` refuses the pick.
        let mut dark = st.clone();
        let mut m = vec![true; 16];
        m[2] = false; // los_pairs[0 * 4 + 2] — a to b
        dark.los_pairs = Some(Rc::new(m));
        let (next, _) = run_buff(&dark, &statics, &buff_action(None), 11);
        assert!(next.buffs.iter().all(|v| v.is_empty()));
    }

    /// B2b — Unstoppable Mark: at the ATTACK seam the bearer marks the volley's
    /// committed target and the base rule lands on itself as a once-grant, so
    /// this volley's wounds cut through the defender's Regeneration — no
    /// regeneration die is drawn at all. A bearer that already marked this
    /// round draws one.
    #[test]
    fn unstoppable_mark_grants_the_regeneration_bypass_for_one_exchange() {
        let (st, mut statics) = buff_line();
        statics[0].shoot = vec![gun("Rifle", 4, 24)]; // enough dice to land a wound
        statics[2].ctx.defense = 6;
        statics[2].ctx.regeneration = true;
        statics[2].ctx.regen_target = 5;
        statics[0].utility_buffs =
            vec![UtilityBuff { vs_target: true, needs_los: true, range_in: 18.0, ..ub("Unstoppable Mark") }];

        // Seed 13: 4 hit dice at 4+ draw [4,3,6,6], the three saves at 6+ all
        // fail — three wounds, which is exactly what a Regeneration roll would
        // otherwise be handed.
        let (next, marked) = run_buff(&st, &statics, &buff_action(Some("b")), 13);
        let landed: i64 = 3 - next.wounds[2].iter().sum::<i64>();
        assert!(landed > 0, "the fixture has to land a wound for the bypass to be visible");
        assert_eq!(regen_rolls(&marked), 0, "Unstoppable ignores Regeneration");
        assert!(next.buffs.iter().all(|v| v.is_empty()), "the exchange spends the grant");
        assert_eq!(next.vs_mark_round[0], st.round);

        // Already marked this round (main.gd:16752): no grant, and the wounds
        // go through the Regeneration roll like anyone else's.
        let mut used = st.clone();
        used.vs_mark_round[0] = used.round;
        let (_, plain) = run_buff(&used, &statics, &buff_action(Some("b")), 13);
        assert_eq!(regen_rolls(&plain), 1);
    }
