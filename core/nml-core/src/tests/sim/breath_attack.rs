use super::*;

    // ------------------------------------------------- BLOCK B3: Breath Attack ---

    /// One fixture act through the tray: the pre-attack Breath Attack slot
    /// draws the trigger die (kind "attack", target `BREATH_TRIGGER`, signed
    /// by the ACTING unit) and, on a hit, the table's own save batch — Blast(3)
    /// capped at the target's 3 alive models, at AP(1)'s worsened save target.
    #[test]
    fn breath_attack_fires_the_trigger_die_then_the_tables_save_batch_on_a_hit() {
        let (st, statics) = breath_line();
        let terrain = crate::terrain::Terrain::default();
        // Seed 7's first face is an unmodified 6 — an automatic trigger success.
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &breath_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot.rolls.len(), 2);
        let trig = &shot.rolls[0];
        assert_eq!(
            (trig.kind, trig.count, trig.target, trig.owner.as_str()),
            ("attack", 1, BREATH_TRIGGER, "a")
        );
        let save = &shot.rolls[1];
        assert_eq!((save.kind, save.count, save.target, save.owner.as_str()), ("defense", 3, 5, "b"));
        let blocks = crate::dice::faces_to_hits(&save.faces, 5) as i64;
        let unsaved = (3 - blocks).max(0);
        let removed: i64 = 3 - next.wounds[2].iter().sum::<i64>();
        assert_eq!(removed, unsaved);
        assert_eq!(next.alive[2], 3 - unsaved);
        let mut probe = Tray::seeded(7);
        probe.roll(1);
        probe.roll(3);
        assert_eq!(tray.state_i64(), probe.state_i64());
    }

    /// RED for the pre-attack slot: a trigger face of 1 always fails and
    /// draws NOTHING else; a target beyond the 6" range, or the rule inactive
    /// on the only bearer, draws not even the trigger die.
    #[test]
    fn breath_attack_fizzles_on_a_1_and_draws_nothing_out_of_range_or_without_the_rule() {
        let terrain = crate::terrain::Terrain::default();
        // Seed 3's first face is a 1 — an automatic trigger failure.
        let (st, statics) = breath_line();
        let mut tray = Tray::seeded(3);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &breath_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot.rolls.len(), 1);
        assert_eq!(shot.rolls[0].faces, vec![1]);
        assert_eq!(next.wounds[2].iter().sum::<i64>(), 3);
        let mut probe = Tray::seeded(3);
        probe.roll(1);
        assert_eq!(tray.state_i64(), probe.state_i64());

        // Out of range: b pushed 20" out (edge gap 18" > the 6" reach).
        let (mut st2, statics2) = breath_line();
        st2.positions[2] =
            vec![[20.0 * IN2M, 0.0, 0.0], [20.02 * IN2M, 0.0, 0.0], [20.04 * IN2M, 0.0, 0.0]];
        let mut tray2 = Tray::seeded(7);
        let mut rng2 = crate::rng::GodotRng::new(0);
        let (_, shot2) = resolve_stochastic_tray_on_board(
            &statics2, &st2, &breath_action(), &terrain, Seams::default(), &mut rng2, &mut tray2,
        )
        .unwrap();
        assert!(shot2.rolls.is_empty());
        let probe2 = Tray::seeded(7);
        assert_eq!(tray2.state_i64(), probe2.state_i64());

        // No bearer: the rule inactive on the only candidate.
        let (st3, mut statics3) = breath_line();
        statics3[0].breath_attack_active = false;
        let mut tray3 = Tray::seeded(7);
        let mut rng3 = crate::rng::GodotRng::new(0);
        let (_, shot3) = resolve_stochastic_tray_on_board(
            &statics3, &st3, &breath_action(), &terrain, Seams::default(), &mut rng3, &mut tray3,
        )
        .unwrap();
        assert!(shot3.rolls.is_empty());
    }

    /// Blast(3) scales DOWN to the target's own alive count when it fields
    /// fewer than 3 models — never floors below the models actually there —
    /// and AP(1) worsens the save target the same way whatever the count.
    #[test]
    fn breath_attack_scales_blast_to_the_targets_alive_count() {
        let (mut st, statics) = breath_line();
        st.wounds[2] = vec![1]; // b down to 1 alive model
        st.positions[2] = vec![[5.0 * IN2M, 0.0, 0.0]];
        st.radii[2] = vec![IN2M];
        st.alive[2] = 1;
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(7);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &breath_action(), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot.rolls.len(), 2);
        let save = &shot.rolls[1];
        assert_eq!((save.count, save.target), (1, 5));
    }
