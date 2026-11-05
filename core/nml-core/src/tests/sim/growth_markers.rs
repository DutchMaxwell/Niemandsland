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

    // ---- AIG-G2 R2: a JOINED hero's own Growth marker (EPOCH_73_V36) ----
    //
    // The core ticks growth lazily at the ACTIVATING unit only and credits the kill to the wiping side's own
    // index, so a hero joined to the host (his own roster row, `attached[host]`) never ticked or got the kill
    // credit. From epoch 73 the host's activation ticks each living attached hero who carries a per-round rule
    // (same Shaken block as the host), and the wiping side's kill credits each living attached hero who carries
    // an on_kill rule. The table twin is `test/v36/aig2_r2_growth_hero_test.gd`.

    const V36: u32 = crate::acts::EPOCH_73_V36;

    fn hero_seams(epoch: u32) -> Seams {
        Seams { hero_attach: true, rules_epoch: epoch, ..Default::default() }
    }

    /// Row 0 = host `a` (no Growth rule), row 1 = its joined hero `ah` carrying `rule`.
    fn joined_hero_line(rule: GrowthRule) -> (State, Vec<UnitStatic>) {
        let (st, mut statics) = buff_line();
        statics[1].growth = vec![rule];
        (st, statics)
    }

    fn run_growth(st: &State, statics: &[UnitStatic], action: &Action, seams: Seams, seed: i64) -> State {
        let terrain = crate::terrain::Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = crate::rng::GodotRng::new(0);
        resolve_stochastic_tray_on_board(statics, st, action, &terrain, seams, &mut rng, &mut tray).unwrap().0
    }

    /// Piercing Growth on the hero: the host's activation ticks HIS marker, never the host's.
    #[test]
    fn a_joined_heros_round_marker_ticks_at_the_hosts_activation_from_epoch_73() {
        let rule = GrowthRule { per_round: true, max_markers: 4, ap_per_two: 1, ..Default::default() };
        let (mut st, statics) = joined_hero_line(rule);
        st.round = 1;
        let next = run_growth(&st, &statics, &buff_action(None), hero_seams(V36), 11);
        assert_eq!((next.growth_markers[1], next.growth_round[1]), (1, 1), "the hero's own marker ticked");
        assert_eq!(next.growth_markers[0], 0, "the host never inherits the hero's rule");
    }

    /// Below epoch 73 the lazy host-only tick stands byte for byte: the hero's row is never touched.
    #[test]
    fn below_epoch_73_a_joined_hero_does_not_tick() {
        let rule = GrowthRule { per_round: true, max_markers: 4, ap_per_two: 1, ..Default::default() };
        let (mut st, statics) = joined_hero_line(rule);
        st.round = 1;
        let next = run_growth(&st, &statics, &buff_action(None), hero_seams(V36 - 1), 11);
        assert_eq!((next.growth_markers[1], next.growth_round[1]), (0, -1));
    }

    /// A Shaken host blocks the round's marker for the hero too (the round is consumed, only the marker is not).
    #[test]
    fn a_shaken_host_blocks_its_joined_heros_marker() {
        let rule = GrowthRule { per_round: true, max_markers: 4, ap_per_two: 1, ..Default::default() };
        let (mut st, statics) = joined_hero_line(rule);
        st.round = 1;
        st.shaken[0] = true;
        let next = run_growth(&st, &statics, &buff_action(None), hero_seams(V36), 11);
        assert_eq!((next.growth_markers[1], next.growth_round[1]), (0, 1));
    }

    /// Defensive Frenzy on the hero: the host's volley wipes `b` (three one-wound models, a 40-attack rifle) and the
    /// kill credits the hero who carries the rule; the host, carrying none, gets nothing.
    #[test]
    fn a_joined_heros_on_kill_marker_is_credited_by_the_hosts_wipe_from_epoch_73() {
        let rule = GrowthRule { on_kill: true, max_markers: 2, hit_per_marker: 1, ..Default::default() };
        let (mut st, mut statics) = joined_hero_line(rule);
        statics[0].shoot = vec![gun("Rifle", 40, 24)];
        st.round = 1;
        let on = run_growth(&st, &statics, &buff_action(Some("b")), hero_seams(V36), 27);
        assert!(on.alive[2] <= 0, "fixture: the volley wiped the target (alive {:?})", on.alive);
        assert_eq!(on.growth_markers[1], 1, "the kill reached the hero's rule");
        assert_eq!(on.growth_markers[0], 0);
        let off = run_growth(&st, &statics, &buff_action(Some("b")), hero_seams(V36 - 1), 27);
        assert_eq!(off.growth_markers[1], 0, "below 73 the credit stays host-only");
    }
