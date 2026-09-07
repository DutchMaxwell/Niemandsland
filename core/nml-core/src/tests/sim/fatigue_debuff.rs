use super::*;

    // ------------------------- wave 4 follow-up: Fatigue Debuff (Mind Control) ---

    /// The registry-built bearer: a gf/wormhole_daemons_of_war profile whose
    /// ONLY rule is the named Mind Control entry, read off the REAL registry
    /// (`assets/solo/rules_mechanics_gf.json`). The REAL `build_for` product,
    /// read at `epoch`.
    fn fatigue_bearer(rules_epoch: u32) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec!["Fatigue Debuff".into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: "wormhole_daemons_of_war".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// Bearer "a" vs a single-model target "b" 12" away (inside the printed
    /// 18", with LOS on the open line): the exact fixture shape `storm_line`
    /// uses, one model per side.
    fn fatigue_line(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
        let (mut st, _) = storm_line("Storm of Change", "wormhole_daemons_of_change", rules_epoch);
        let bearer = fatigue_bearer(rules_epoch);
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.ctx.quality = 4;
        b.ctx.defense = 4;
        b.ctx.tough = 1;
        (st, vec![bearer, UnitStatic { name: "ah".into(), ..Default::default() }, b, UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    /// The activation: the pre-attack Mind Control slot runs off the tray
    /// before any shooting, exactly as `run_storm` drives `resolve_stochastic_
    /// tray_on_board`.
    fn run_fatigue(
        st: &State,
        statics: &[UnitStatic],
        seed: i64,
        rules_epoch: u32,
    ) -> (State, ShootResult) {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(
            statics, st, &storm_action(), &terrain, seams, &mut rng, &mut tray,
        )
        .unwrap()
    }

    /// The stamp: the REAL registry entry (primitive "Mind Control", params
    /// `{"effect":"fatigue","needs_los":true}`) lands on the statics behind
    /// the FROZEN `EPOCH_7_TABLE_RULES` — present at 7, absent at 6 (the
    /// fleet stamps 5 today; a record below 7 must never carry the read).
    #[test]
    fn the_real_registry_stamps_fatigue_debuff_at_epoch_seven_not_six() {
        let on = fatigue_bearer(7);
        assert_eq!(on.mind_control.len(), 1, "epoch 7: the entry is stamped");
        let s = &on.mind_control[0];
        assert_eq!(s.name, "Fatigue Debuff");
        assert_eq!(s.range_in, 18.0, "the printed pick range (main.gd:17011 default)");
        assert!(s.needs_los, "the needs_los param rides the entry");
        assert_eq!(s.effect, "fatigue");
        let off = fatigue_bearer(6);
        assert!(off.mind_control.is_empty(), "epoch 6: the record predates the wave");
    }

    /// The port: a failed morale test on the picked enemy (highest
    /// alive+Tough within 18", in LOS) FATIGUES it instead of displacing —
    /// the target strikes on unmodified 6s until it next activates
    /// (main.gd:17014-17025). Seed 3: the mind-control die lands under the
    /// target's Quality 4. Epoch-6 control: no die, no fatigue, no line.
    #[test]
    fn a_failed_morale_test_fatigues_the_target_at_epoch_seven() {
        let (st, statics) = fatigue_line(7);
        let (next, shot) = run_fatigue(&st, &statics, 3, 7);
        let mc = shot
            .rolls
            .iter()
            .find(|r| r.count == 1 && r.owner == "a" && r.target == 4)
            .expect("one quality die on the tray for the morale test");
        assert!(
            mc.faces[0] < 4,
            "this seed must FAIL the quality-4 test or the test is blind: {mc:?}"
        );
        assert!(next.fatigued[2], "the failed test fatigues the target");
        assert!(
            shot.log.iter().any(|l| l.contains("Fatigue Debuff") && l.contains("FATIGUED")),
            "rules-must-log: the fatigue line names the rule and the target — got {:#?}",
            shot.log
        );

        // The gate: a rules_epoch-6 record (the fleet stamps 5 today) replays
        // the pre-wave reading — no die, no fatigue, no line.
        let (next6, shot6) = run_fatigue(&st, &statics, 3, 6);
        assert!(
            !shot6.rolls.iter().any(|r| r.owner == "a" && r.count == 1 && r.target == 4),
            "epoch 6: no mind-control die"
        );
        assert!(!next6.fatigued[2], "epoch 6: nobody is fatigued");
        assert!(shot6.log.iter().all(|l| !l.contains("Fatigue Debuff")));
    }

    /// A PASSED morale test fatigues nobody: seed with the die at 4+ leaves
    /// the target clean (and no fatigue line on the log).
    #[test]
    fn a_passed_morale_test_leaves_the_target_clean() {
        let (st, statics) = fatigue_line(7);
        // Seed scan: the FIRST tray face must pass Quality 4; assert it so the
        // test is never blind to a tray change.
        let mut seed = 0;
        let face = (0..200)
            .find(|&s| Tray::seeded(s).roll(1)[0] >= 4)
            .expect("some seed passes");
        seed = face as i64;
        let (next, shot) = run_fatigue(&st, &statics, seed, 7);
        let mc = shot
            .rolls
            .iter()
            .find(|r| r.count == 1 && r.owner == "a" && r.target == 4)
            .expect("the morale die is drawn");
        assert!(mc.faces[0] >= 4, "this seed must PASS: {mc:?}");
        assert!(!next.fatigued[2], "passed: the target fights normally");
        assert!(shot.log.iter().all(|l| !l.contains("FATIGUED")));
    }

    /// Out of reach is out of mind: an enemy beyond 18" is no legal pick, so
    /// no die is drawn at all (the table's `_solo_utility_target` returns
    /// null and the resolver skips, main.gd:17012-17013).
    #[test]
    fn no_enemy_in_reach_draws_no_die() {
        let (mut st, statics) = fatigue_line(7);
        st.positions[2] = vec![[19.0 * IN2M, 0.0, 0.0]];
        let (_, shot) = run_fatigue(&st, &statics, 3, 7);
        assert!(
            !shot.rolls.iter().any(|r| r.owner == "a" && r.count == 1 && r.target == 4),
            "beyond 18\": the once-per-activation pick never fires"
        );
    }
