use super::*;

    // ------------------------- wave 4 follow-up: Mind Control (displacement arm) ---

    /// The registry-built bearer: a gf/jackals profile whose ONLY rule is the
    /// named `Mind Control` entry (Tayra "Shipspeaker"'s own base rule), read
    /// off the REAL registry (`assets/solo/rules_mechanics_gf.json`). The REAL
    /// `build_for` product, read at `epoch`.
    fn mind_control_bearer(rules_epoch: u32) -> UnitStatic {
        let p = Profile {
            unit_id: "a".into(),
            name: "a".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec!["Mind Control".into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: "jackals".into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = crate::rules::Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, rules_epoch)
    }

    /// Bearer "a" vs a three-model target "b" 5" away (inside the printed
    /// 18", with LOS on the open line): the exact fixture shape
    /// `fatigue_line` uses, one bearer side, one target side.
    fn mind_control_line(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
        let (st, _) = storm_line("Storm of Change", "wormhole_daemons_of_change", rules_epoch);
        let bearer = mind_control_bearer(rules_epoch);
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.ctx.quality = 4;
        b.ctx.defense = 4;
        b.ctx.tough = 1;
        (st, vec![bearer, UnitStatic { name: "ah".into(), ..Default::default() }, b, UnitStatic { name: "bh".into(), ..Default::default() }])
    }

    /// The activation: the pre-attack Mind Control slot runs off the tray
    /// before any shooting, exactly as `run_storm` drives
    /// `resolve_stochastic_tray_on_board`.
    fn run_mc(
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

    /// The stamp: the REAL registry entry (name and primitive both
    /// "Mind Control", params `{"range_in":18,"move_in":6,"needs_los":true}`,
    /// no `effect`) lands on the statics behind the FROZEN
    /// `EPOCH_7_TABLE_RULES` — present at 7, absent at 6 (the fleet stamps 5
    /// today; a record below 7 must never carry the read).
    #[test]
    fn the_real_registry_stamps_mind_control_at_epoch_seven_not_six() {
        let on = mind_control_bearer(7);
        assert_eq!(on.mind_control.len(), 1, "epoch 7: the entry is stamped");
        let s = &on.mind_control[0];
        assert_eq!(s.name, "Mind Control");
        assert_eq!(s.range_in, 18.0, "the printed pick range (main.gd:17011 default)");
        assert!(s.needs_los, "the needs_los param rides the entry");
        assert_eq!(s.move_in, 6.0, "the printed displacement (main.gd:17037 default)");
        let off = mind_control_bearer(6);
        assert!(off.mind_control.is_empty(), "epoch 6: the record predates the wave");
    }

    /// The port: a failed morale test on the picked enemy (best alive+Tough
    /// within 18", in LOS) DISPLACES it — up to 6" in a straight line, no
    /// objective on the board so straight away from the bearer
    /// (main.gd:17031-17038). Seed 3: the mind-control die lands under the
    /// target's Quality 4. Epoch-6 control: no die, no move, no line.
    #[test]
    fn a_failed_morale_test_displaces_the_target_at_epoch_seven() {
        let (st, statics) = mind_control_line(7);
        let (next, shot) = run_mc(&st, &statics, 3, 7);
        let mc = shot
            .rolls
            .iter()
            .find(|r| r.count == 1 && r.owner == "a" && r.target == 4)
            .expect("one quality die on the tray for the morale test");
        assert!(
            mc.faces[0] < 4,
            "this seed must FAIL the quality-4 test or the test is blind: {mc:?}"
        );
        let before = &st.positions[2];
        let after = &next.positions[2];
        let moved: f64 = before
            .iter()
            .zip(after.iter())
            .map(|(a, b)| ((a[0] - b[0]).powi(2) + (a[2] - b[2]).powi(2)).sqrt())
            .fold(f64::INFINITY, f64::max);
        assert!(
            moved > 5.0 * IN2M,
            "the failed test moves the target up to 6\" straight away from the bearer — moved {moved:.3} m"
        );
        assert!(
            shot.log.iter().any(|l| l.contains("Mind Control") && l.contains("is moved")),
            "rules-must-log: the move line names the rule and the target — got {:#?}",
            shot.log
        );

        // The gate: a rules_epoch-6 record (the fleet stamps 5 today) replays
        // the pre-wave reading — no die, no move, no line.
        let (next6, shot6) = run_mc(&st, &statics, 3, 6);
        assert!(
            !shot6.rolls.iter().any(|r| r.owner == "a" && r.count == 1 && r.target == 4),
            "epoch 6: no mind-control die"
        );
        assert_eq!(next6.positions[2], st.positions[2], "epoch 6: nobody is moved");
        assert!(shot6.log.iter().all(|l| !l.contains("Mind Control")));
    }

    /// A PASSED morale test displaces nobody: seed with the die at 4+ leaves
    /// the target exactly where it stood (and no move line on the log).
    #[test]
    fn a_passed_morale_test_leaves_the_target_in_place() {
        let (st, statics) = mind_control_line(7);
        // Seed scan: the FIRST tray face must pass Quality 4; assert it so the
        // test is never blind to a tray change.
        let seed = (0..200)
            .find(|&s| Tray::seeded(s).roll(1)[0] >= 4)
            .expect("some seed passes") as i64;
        let (next, shot) = run_mc(&st, &statics, seed, 7);
        let mc = shot
            .rolls
            .iter()
            .find(|r| r.count == 1 && r.owner == "a" && r.target == 4)
            .expect("the morale die is drawn");
        assert!(mc.faces[0] >= 4, "this seed must PASS: {mc:?}");
        assert_eq!(next.positions[2], st.positions[2], "passed: the target holds");
        assert!(shot.log.iter().all(|l| !l.contains("is moved")));
    }

    /// Denial by displacement (main.gd:17031-17036): with a marker on the
    /// board the shift aims AWAY FROM THE NEAREST UNCONTROLLED OBJECTIVE —
    /// the AI pulls the holder off the marker it defends — not away from the
    /// bearer. The objective sits 2" behind the target, so away-from-bearer
    /// (+x) and away-from-marker (-z) point at right angles; the port must
    /// take the -z leg.
    #[test]
    fn the_displacement_aims_away_from_the_nearest_uncontrolled_objective() {
        let (mut st, statics) = mind_control_line(7);
        // Neutral marker (owner 0) 2" off the target's line: the target
        // contests it (within 3"), the bearer neither owns nor contests it.
        st.objectives = vec![crate::state::Objective {
            pos: [5.0 * IN2M, 0.0, 2.0 * IN2M],
            owner: 0,
        }];
        // Seed scan: the FIRST tray face must FAIL Quality 4.
        let seed = (0..200)
            .find(|&s| Tray::seeded(s).roll(1)[0] < 4)
            .expect("some seed fails") as i64;
        let (next, _) = run_mc(&st, &statics, seed, 7);
        let dz = next.positions[2][0][2] - st.positions[2][0][2];
        let dx = next.positions[2][0][0] - st.positions[2][0][0];
        assert!(
            dz < -4.0 * IN2M,
            "the shift runs away from the marker (the -z leg) — dz = {:.3} m",
            dz / IN2M
        );
        assert!(
            dx.abs() < 1.0 * IN2M,
            "away-from-bearer (+x) is the WRONG leg here — dx = {:.3} m",
            dx / IN2M
        );
    }
