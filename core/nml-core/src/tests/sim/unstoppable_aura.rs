use super::*;

    // ---------------- EPOCH 37 UNSTOPPABLE AURA: THE GRANT'S SCOPE -------------

    /// `buff_consumption_bridge.rs`'s `run_buff_epoch`, local copy: the record's
    /// OWN rules_epoch, so the two legs of the same fixture answer separately.
    fn run_aura_epoch(
        st: &State,
        statics: &[UnitStatic],
        action: &Action,
        seed: i64,
        epoch: u32,
    ) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(
            statics, st, action, &terrain,
            Seams { rules_epoch: epoch, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap()
    }

    /// EPOCH 37 UNSTOPPABLE AURA (sweep C row `Unstoppable when Shooting Aura`)
    /// — the aura's Utility-Buff record carries its scope
    /// (`{grants_rule: "Unstoppable", scope: "shooting"}`), and the grant must
    /// honour it.
    ///
    /// The SHOOTING leg: the aura-granted shooter hits an Evasive (-1 to hit)
    /// target at the unmodified Quality 4+, and the clamp line names the AURA —
    /// not a once-grant, which the aura is not. The MELEE leg: the same
    /// activation's charge strikes at the MODIFIED 5+, logs no Unstoppable line,
    /// and its wounds go through the target's Regeneration like anyone else's —
    /// "when shooting" is the printed rule's own limit.
    ///
    /// DIVERGED on main: the grant overlay is scope-blind on both layers, so the
    /// melee strike clamped its negatives and cut through Regeneration while the
    /// shooting clamp logged "(once)" for a persistent aura. The old leg is
    /// pinned at 34, the epoch immediately below the bump: the recorded
    /// behavior — the scope-blind union arms both clamps and bypasses melee
    /// Regeneration — replays exactly.
    #[test]
    fn granted_unstoppable_aura_shoots_an_evasive_target_at_the_unmodified_quality_and_stays_out_of_melee() {
        let (st, mut statics) = buff_line();
        statics[0].utility_buffs = vec![UtilityBuff {
            grants_rule: "Unstoppable".into(),
            scope: "shooting".into(),
            ..ub("Unstoppable when Shooting Aura")
        }];
        statics[2].ctx.evasive = true;

        // --- SHOOTING leg at 37: the clamp half, named as the aura's. ---
        let (next, shot) = run_aura_epoch(&st, &statics, &buff_action(Some("b")), 13, 37);
        assert_eq!(shot.rolls[0].target, 4, "the granted aura ignores the Evasive -1");
        assert!(
            shot.log.iter().any(|l| l.contains("Unstoppable")
                && l.contains("to-hit") && l.contains("aura")),
            "rules-must-log: the clamp line names the aura (the grant is not a once-record): {:?}",
            shot.log
        );
        assert!(next.buffs.iter().all(|v| v.is_empty()), "the exchange spends the once-record");

        // --- MELEE leg at 37: the scope keeps the aura out of the strike. ---
        let (mut mst, mut mstatics) = buff_line();
        mstatics[0].utility_buffs = statics[0].utility_buffs.clone();
        mst.positions[2] = vec![[2.5 * IN2M, 0.0, 0.0]];
        mst.radii[2] = vec![IN2M];
        mst.wounds[2] = vec![1];
        mst.alive[2] = 1;
        mstatics[2].model_count = 1;
        mstatics[2].wounds_max = vec![1];
        mstatics[2].ctx.evasive = true;
        mstatics[2].ctx.regeneration = true;
        mstatics[2].ctx.regen_target = 5;
        let charge = Action {
            kind: CHARGE,
            unit: "a".into(),
            dest: None,
            shoot: None,
            charge: Some("b".into()),
            patient: false,
            split: None,
            traced: None, teleport: None, };
        let (mnext, strike) = run_aura_epoch(&mst, &mstatics, &charge, 13, 37);
        assert_eq!(
            strike.rolls[0].target, 5,
            "a shooting-scoped aura does not arm the MELEE clamp");
        assert!(
            strike.log.iter().all(|l| !l.contains("Unstoppable")),
            "rules-must-log: no Unstoppable line in melee at 37: {:?}",
            strike.log
        );
        let landed: i64 = 1 - mnext.wounds[2].iter().sum::<i64>();
        if landed > 0 {
            assert_eq!(
                regen_rolls(&strike), 1,
                "the melee wounds go through Regeneration — the shooting-scoped aura does not bypass it");
        }

        // --- The old leg, pinned at 34 (the epoch immediately below the bump):
        // the recorded behavior replays — the scope-blind union arms BOTH
        // clamps and the melee Regeneration bypass leaks. ---
        let (_, old_shot) = run_aura_epoch(
            &st, &statics, &buff_action(Some("b")), 13, crate::acts::EPOCH_34_UNSTOPPABLE_MARK);
        assert_eq!(
            old_shot.rolls[0].target, 4,
            "below 37 the scope-blind union arms the shooting clamp (recorded)");
        let (old_next, old_strike) = run_aura_epoch(
            &mst, &mstatics, &charge, 13, crate::acts::EPOCH_34_UNSTOPPABLE_MARK);
        assert_eq!(
            old_strike.rolls[0].target, 4,
            "below 37 the melee clamp leaks (recorded)");
        let old_landed: i64 = 1 - old_next.wounds[2].iter().sum::<i64>();
        if old_landed > 0 {
            assert_eq!(
                regen_rolls(&old_strike), 0,
                "below 37 the melee Regeneration bypass leaks (recorded)");
        }
    }
