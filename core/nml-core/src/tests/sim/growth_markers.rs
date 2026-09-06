use super::*;

    // -------------------------------------- block B7: Growth Markers ---

    /// `_solo_growth_round_start` main.gd:16984: +1 marker at this unit's own
    /// next activation, once per ROUND (a second call the same round is a
    /// no-op), blocked while Shaken (main.gd:17005-17009 — the round is still
    /// consumed, only the marker is not), capped at `max_markers`.
    #[test]
    fn growth_round_start_ticks_once_per_round_caps_and_blocks_while_shaken() {
        let mut st = four_unit_line();
        let mut statics = vec![UnitStatic::default()];
        statics[0].growth =
            vec![GrowthRule { per_round: true, max_markers: 2, ap_per_two: 1, ..Default::default() }];
        st.round = 1;
        growth_round_start(&statics, &mut st, 0, false);
        assert_eq!((st.growth_markers[0], st.growth_round[0]), (1, 1));

        growth_round_start(&statics, &mut st, 0, false); // same round: no-op
        assert_eq!(st.growth_markers[0], 1);

        st.round = 2;
        growth_round_start(&statics, &mut st, 0, true); // Shaken: round consumed, no marker
        assert_eq!((st.growth_markers[0], st.growth_round[0]), (1, 2));

        st.round = 3;
        growth_round_start(&statics, &mut st, 0, false);
        assert_eq!(st.growth_markers[0], 2, "cap reached");
        st.round = 4;
        growth_round_start(&statics, &mut st, 0, false);
        assert_eq!(st.growth_markers[0], 2, "capped: a further round earns nothing more");
    }

    /// `_solo_growth_on_kill` main.gd:17021: +1 marker per call, capped; a
    /// unit with no "on_kill" Growth Markers rule at all is untouched — the
    /// no-bearer negative.
    #[test]
    fn growth_on_kill_caps_and_ignores_a_non_carrier() {
        let mut st = four_unit_line();
        let mut statics = vec![UnitStatic::default()];
        statics[0].growth =
            vec![GrowthRule { on_kill: true, max_markers: 2, hit_per_marker: 1, ..Default::default() }];
        growth_on_kill(&statics, &mut st, 0);
        growth_on_kill(&statics, &mut st, 0);
        growth_on_kill(&statics, &mut st, 0);
        assert_eq!(st.growth_markers[0], 2, "capped at max_markers");

        let mut st2 = four_unit_line();
        let bare = vec![UnitStatic::default()];
        growth_on_kill(&bare, &mut st2, 0);
        assert_eq!(st2.growth_markers[0], 0, "no Growth Markers rule at all: untouched");
    }

    /// Integration, end to end through `resolve_with`/`resolve_stochastic_
    /// tray_on_board`: two HOLD activations bank a marker each (the per-round
    /// tick fires on the bearer's OWN activation, `growth_round` proving each
    /// round only ticked once), and the THIRD round's real shot already
    /// carries the AP those two rounds banked — the round/ledger replay proof.
    #[test]
    fn growth_ticks_through_resolve_with_and_then_shifts_the_next_shots_save() {
        let (mut st, mut statics) = buff_line();
        statics[0].growth =
            vec![GrowthRule { per_round: true, max_markers: 4, ap_per_two: 1, ..Default::default() }];
        let terrain = crate::terrain::Terrain::default();
        let mut rng = crate::rng::GodotRng::new(0);
        st.round = 1;
        let mut tray = Tray::seeded(11);
        let (next1, _) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(None), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!((next1.growth_markers[0], next1.growth_round[0]), (1, 1));

        let mut st2 = next1;
        st2.round = 2;
        let mut tray = Tray::seeded(12);
        let (next2, _) = resolve_stochastic_tray_on_board(
            &statics, &st2, &buff_action(None), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(next2.growth_markers[0], 2, "each round ticks once — growth_round gates a repeat");

        let mut st3 = next2;
        st3.round = 3;
        // More attacks than `buff_line`'s plain 1 — guarantees at least one
        // hit lands (matching `a_volley_draws_hit_dice_then_one_save_batch_
        // of_exactly_the_hits`'s own seed-27/6-attack pairing), so the save
        // roll this assertion reads actually gets drawn.
        statics[0].shoot = vec![gun("Rifle", 20, 24)];
        let mut tray = Tray::seeded(27);
        let (_, shot) = resolve_stochastic_tray_on_board(
            &statics, &st3, &buff_action(Some("b")), &terrain, Seams::default(), &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot.rolls[1].target, 5,
            "2 markers banked over 2 rounds -> AP(+1) on this round's shot (Defense 4+ becomes 5+)");
    }
