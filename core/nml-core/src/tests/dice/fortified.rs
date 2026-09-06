use super::*;

    // --------------------- Fortified-family DATA-ALIAS leg (epoch 6) --------

    /// Guardian's shape (`incoming_ap_reduction: 1, over_in: 9`) past its own
    /// gate: the AP(1) volley's save target is one better (main.gd:6447-6462's
    /// alias loop, `gate_in > 0.0 and not over9`), and the arm reports itself
    /// for the rules-must-log line.
    #[test]
    fn fortified_alias_lowers_the_save_target_past_nine_inches() {
        let guardian = Ctx { fortified_alias_ap: 1, fortified_alias_over_in: 9.0, ..defender(4, 5) };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[ap_rifle(64)], &[0], &[64], &shooter(4), &guardian, 12.0, &mut tray,
        );
        assert_eq!(out.rolls[1].target, 4, "AP(1) volley past 9\": Guardian saves on 4+ instead of 5+");
        assert!(out.fortified_fired, "rules-must-log: the arm must report itself");
    }

    /// At exactly 9" the gate is closed — `dist_in > gate`, not `>=`
    /// (main.gd:6415's `dist_in > AiCombatMath.LONG_RANGE_IN`).
    #[test]
    fn fortified_alias_does_nothing_at_or_under_nine_inches() {
        let guardian = Ctx { fortified_alias_ap: 1, fortified_alias_over_in: 9.0, ..defender(4, 5) };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[ap_rifle(64)], &[0], &[64], &shooter(4), &guardian, 9.0, &mut tray,
        );
        assert_eq!(out.rolls[1].target, 5, "at exactly 9\" the gate has not fired: plain AP(1) save");
        assert!(!out.fortified_fired, "nothing fired, nothing logs");
    }

    /// The Boost shape (`incoming_ap_reduction: 1`, NO `over_in` — the table's
    /// `gate_in <= 0.0` branch) has no distance to clear: it applies on the
    /// MELEE leg too, where the gated aliases never reach (main.gd:6119 passes
    /// `dist_in: -1.0`).
    #[test]
    fn fortified_boost_lowers_the_melee_saves_without_a_distance() {
        let boost = Ctx { fortified_boost_ap: 1, ..defender(4, 5) };
        let att = shooter(4);
        let profiles = [ShootProfile { name: "CCW".into(), ap: 1, attacks: 64, count: 1, range: 0, ..Default::default() }];
        let strikers = [Shooter { profiles: &profiles, keep: &[0], attacks: &[64], att: &att, owner: "att" }];
        let mut tray = Tray::seeded(27);
        let out = resolve_melee_with_tray(&strikers, &boost, "def", false, true, false, &mut tray);
        assert_eq!(out.rolls[1].target, 4, "AP(1) melee vs the Boost: saves on 4+ instead of 5+");
        assert!(out.fortified_fired, "rules-must-log: the arm must report itself");
    }

    /// Plain Fortified keeps its precedence (main.gd:6440-6447's `else`): when
    /// the exact name is on all models the alias arm never runs — same target
    /// as plain Fortified alone, and the ALIAS arm reports nothing.
    #[test]
    fn plain_fortified_wins_and_the_alias_arm_never_stacks() {
        let both = Ctx {
            fortified: true, fortified_boost_ap: 1,
            fortified_alias_ap: 1, fortified_alias_over_in: 9.0,
            ..defender(4, 5)
        };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[ap_rifle(64)], &[0], &[64], &shooter(4), &both, 12.0, &mut tray,
        );
        assert_eq!(out.rolls[1].target, 4, "plain Fortified's own (ap-1).max(0): saves on 4+");
        assert!(!out.fortified_fired, "the alias arm is the ELSE branch — it never ran");
    }

    /// A weapon that scores nothing draws NO save batch — the table `continue`s
    /// at main.gd:3210. Drawing an empty one would burn a die (`maxi(1, count)`)
    /// and shift every later activation.
    #[test]
    fn a_volley_that_misses_everything_draws_no_save_batch() {
        // Quality 6+ against a single die: seed 12345's first face is not a 6.
        let first = Tray::seeded(12345).roll(1)[0];
        assert!(first < 6, "fixture seed no longer misses — pick another");
        let mut tray = Tray::seeded(12345);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(6), &defender(4, 5), 12.0, &mut tray,
        );
        assert_eq!(out.rolls.len(), 1, "a miss must not roll saves: {:?}", out.rolls);
        assert_eq!(out.wounds, 0);
        assert_eq!(out.rolls[0].count, 1, "and exactly one die left the cup");
        let mut one = Tray::seeded(12345);
        one.roll(1);
        assert_eq!(tray.state_i64(), one.state_i64(), "the tray advanced by exactly one draw");
    }

    /// RED-GREEN on Blast(X): the save batch is `hits * min(X, models)` dice
    /// (AiCombatMath.blast_hits :370-375). Drop the multiply and the batch is
    /// `hits` — a different die COUNT, so every face after it shifts. Both
    /// counts are computed here so the red half cannot silently become green.
    #[test]
    fn blast_multiplies_the_save_batch_and_dropping_it_shifts_the_stream() {
        let p = [ShootProfile { blast: 3, ..rifle(2) }];
        let mut tray = Tray::seeded(27);
        let faces = Tray::seeded(27).roll(2);
        let hits = faces_to_hits(&faces, 2) as i64;
        assert!(hits > 0, "fixture seed no longer hits — pick another");
        let out = resolve_shooting_with_tray(
            &p, &[0], &[2], &shooter(2), &defender(4, 5), 12.0, &mut tray,
        );
        assert_eq!(out.rolls[1].count, hits * 3, "Blast(3) vs 5 models multiplies by 3");
        assert_ne!(out.rolls[1].count, hits, "the un-multiplied count is a DIFFERENT stream");
        // The cap: never more than there are models to spill onto.
        let mut tray2 = Tray::seeded(27);
        let capped = resolve_shooting_with_tray(
            &p, &[0], &[2], &shooter(2), &defender(4, 2), 12.0, &mut tray2,
        );
        assert_eq!(capped.rolls[1].count, hits * 2, "capped by the 2 models in the target");
    }

    /// Bane re-rolls the defender's unmodified 6s as a SEPARATE tray roll after
    /// the batch is fully read (main.gd:6463) — a third roll in the stream, and
    /// a Bane weapon's wounds bypass Regeneration entirely (:6927-6933).
    #[test]
    fn bane_draws_its_re_roll_after_the_save_batch_and_bypasses_regeneration() {
        let p = [ShootProfile { bane: true, ..rifle(8) }];
        let mut tray = Tray::seeded(27);
        let def = Ctx { regeneration: true, regen_target: 5, ..defender(4, 8) };
        let out = resolve_shooting_with_tray(&p, &[0], &[8], &shooter(2), &def, 12.0, &mut tray);
        let saves = &out.rolls[1];
        let sixes = saves.faces.iter().filter(|&&f| f == 6).count() as i64;
        assert!(sixes > 0, "fixture seed rolls no Defense 6 — pick another");
        assert_eq!(out.rolls.len(), 3, "hit dice, saves, Bane re-roll: {:?}", out.rolls);
        assert_eq!(out.rolls[2].kind, "defense");
        assert_eq!(out.rolls[2].count, sixes, "one re-roll die per unmodified 6");
        assert_eq!(out.rolls[2].target, saves.target, "at the same save target");
        assert!(
            !out.rolls.iter().any(|r| r.target == 5 && r.kind == "attack" && r.count == out.wounds),
            "Bane bypasses Regeneration — no ignore roll may be drawn"
        );
    }

    /// Precise (+1 to hit) is applied when the hits are COUNTED, not when the
    /// dice leave the cup: the table rolls at the plain `to_hit` (main.gd:3200)
    /// and `_solo_hits` scores them one better (:4405-4406). Recording the
    /// improved target instead would part company with `dice.jsonl` on every
    /// Precise weapon while the faces themselves still matched.
    #[test]
    fn precise_rolls_at_the_plain_to_hit_and_scores_one_better() {
        let faces = Tray::seeded(27).roll(6);
        let plain = faces_to_hits(&faces, 4) as i64;
        let better = faces_to_hits(&faces, 3) as i64;
        assert!(better > plain, "fixture seed cannot tell the two targets apart");
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[ShootProfile { precise: true, ..rifle(6) }],
            &[0], &[6], &shooter(4), &defender(4, 6), 12.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 4, "the RECORDED target is the raw to-hit");
        assert_eq!(out.rolls[0].faces, faces);
        assert_eq!(out.rolls[1].count, better, "but the hits are scored at 3+");
        assert_ne!(out.rolls[1].count, plain, "rolling at the improved target is a DIFFERENT stream");
    }

    /// Sergeant's bonus hits (`AiCombatMath.sergeant_bonus_hits` :493-494): the
    /// bearer's unmodified 6s, capped at its own attack share. The EV path
    /// already values these (combat.rs:339-342), so a dice path that dropped
    /// them would be the poorer twin of the thing it replaces.
    #[test]
    fn sergeant_adds_its_capped_share_of_unmodified_sixes() {
        let faces = Tray::seeded(5).roll(6);
        let sixes = faces.iter().filter(|&&f| f == 6).count() as i64;
        assert_eq!(sixes, 3, "seed 5 rolls [6, 2, 6, 1, 5, 6] — three unmodified 6s");
        let base = {
            let mut t = Tray::seeded(5);
            resolve_shooting_with_tray(&[rifle(6)], &[0], &[6], &shooter(4), &defender(4, 6), 12.0, &mut t)
                .rolls[1].count
        };
        let mut tray = Tray::seeded(5);
        let out = resolve_shooting_with_tray(
            &[ShootProfile { sergeant_attacks: 1, ..rifle(6) }],
            &[0], &[6], &shooter(4), &defender(4, 6), 12.0, &mut tray,
        );
        assert_eq!(out.rolls[1].count, base + 1, "the bearer's share is 1 attack");
        // And the cap is real: an uncapped share adds EVERY unmodified 6.
        let mut wide = Tray::seeded(5);
        let all = resolve_shooting_with_tray(
            &[ShootProfile { sergeant_attacks: 99, ..rifle(6) }],
            &[0], &[6], &shooter(4), &defender(4, 6), 12.0, &mut wide,
        );
        assert_eq!(all.rolls[1].count, base + sixes, "uncapped: one bonus hit per 6");
    }

    /// A Deadly weapon still resolves, and it says so: the table lands Deadly
    /// per model with its own Regeneration roll, which this port does not
    /// reproduce, so the activation is FLAGGED rather than quietly counted.
    #[test]
    fn an_unported_branch_is_reported_not_skipped() {
        let p = [ShootProfile { deadly: 3, hazardous: true, ..rifle(4) }];
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &p, &[0], &[4], &shooter(3), &defender(4, 3), 12.0, &mut tray,
        );
        assert!(out.unported.contains(&"deadly"), "{:?}", out.unported);
        assert!(out.unported.contains(&"hazardous"), "{:?}", out.unported);
        assert!(!out.rolls.is_empty(), "a flagged activation still resolves");
    }

    /// D1-B4b — the ATTACHED HERO fires its own shots inside the host's volley
    /// (main.gd:2954-2990): the host's rolls first, then the hero's, at the
    /// HERO's own Quality and with its own name on the dice. RED half: drop the
    /// hero's group and the stream is one roll and 24 faces short — a different
    /// game from the first hero onward.
    #[test]
    fn an_attached_hero_fires_its_own_shots_after_the_host() {
        let host_p = [rifle(6)];
        let hero_p = [ShootProfile { name: "Hero Gun".into(), ..rifle(2) }];
        let (host_q, hero_q) = (shooter(5), shooter(2));
        let def = defender(4, 5);
        let host = Shooter {
            profiles: &host_p, keep: &[0], attacks: &[6], att: &host_q, owner: "Shooter Grunts",
        };
        let hero = Shooter {
            profiles: &hero_p, keep: &[0], attacks: &[2], att: &hero_q, owner: "Vradhez",
        };
        let mut tray = Tray::seeded(27);
        let out =
            resolve_volley_with_tray(&[host, hero], &def, "Pathfinders", 12.0, 12.0, true, true, true, true, &mut tray);
        let attacks: Vec<_> = out.rolls.iter().filter(|r| r.kind == "attack").collect();
        assert_eq!(attacks.len(), 2, "host then hero: {:?}", out.rolls);
        assert_eq!((attacks[0].count, attacks[0].target, attacks[0].owner.as_str()),
                   (6, 5, "Shooter Grunts"), "the host fires first, at its own Quality");
        assert_eq!((attacks[1].count, attacks[1].target, attacks[1].owner.as_str()),
                   (2, 2, "Vradhez"), "then the hero, at ITS Quality — not the host's");
        assert!(out.rolls.iter().all(|r| r.kind != "defense" || r.owner == "Pathfinders"),
                "every save batch is signed by the DEFENDER");
        // RED: the host alone draws strictly fewer dice, so every later
        // activation reads different faces.
        let mut solo = Tray::seeded(27);
        let host_only = resolve_shooting_with_tray(
            &host_p, &[0], &[6], &host_q, &def, 12.0, &mut solo,
        );
        assert!(host_only.rolls.len() < out.rolls.len(), "the hero's rolls are missing");
        assert_ne!(solo.state_i64(), tray.state_i64(), "and the tray stands elsewhere");
    }
