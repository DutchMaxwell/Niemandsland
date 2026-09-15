use super::*;

    // ------------------------------------------------- block B8: Second Wind ---

    /// The table's own moment: the round would otherwise CLOSE right after
    /// this activation (`ah`/`b`/`bh` are all already spent), and the bearer
    /// carries the rule — it re-opens its OWN activation and clears fatigue,
    /// exactly `spend_second_wind` solo_controller.gd:10471-10479.
    #[test]
    fn second_wind_grants_a_second_activation_when_the_round_closes() {
        let (mut st, mut statics) = buff_line();
        statics[0].second_wind_active = true;
        st.activated = vec![false, true, true, true];
        st.fatigued[0] = true;
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(!next.activated[0], "Second Wind re-opens the bearer's own activation");
        assert!(!next.fatigued[0], "stops being fatigued when activated for the second time");
        assert!(next.second_wind_used[0]);
        assert_eq!((next.second_wind_round, next.second_wind_uses), (next.round, 1));
    }

    /// Negative: the round is NOT over yet ("b", alive, still un-activated) —
    /// no grant, even though the bearer would otherwise qualify.
    #[test]
    fn second_wind_does_not_fire_while_any_unit_can_still_activate() {
        let (mut st, mut statics) = buff_line();
        statics[0].second_wind_active = true;
        st.activated = vec![false, true, false, true]; // "b" (alive) still open
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(next.activated[0], "no second wind: 'a' stays activated from its own move alone");
        assert!(!next.second_wind_used[0]);
    }

    /// Negative: nobody on the table carries the rule — the round closes but
    /// nothing is granted.
    #[test]
    fn second_wind_no_candidate_without_the_rule() {
        let (mut st, statics) = buff_line();
        st.activated = vec![false, true, true, true];
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(next.activated[0]);
        assert!(!next.second_wind_used.iter().any(|&u| u));
    }

    /// Negative: ONCE PER GAME, not once per round — a bearer that already
    /// spent its Second Wind earlier is skipped even when it is the only
    /// carrier and the round genuinely closes.
    #[test]
    fn second_wind_is_once_per_game_not_once_per_round() {
        let (mut st, mut statics) = buff_line();
        statics[0].second_wind_active = true;
        st.second_wind_used[0] = true;
        st.activated = vec![false, true, true, true];
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(next.activated[0], "already spent — no second grant");
    }

    /// The army cap (`ceil(carriers / army_cap_fraction)`, solo_controller.gd:
    /// 10464): 2 unattached carriers on one side, `army_cap_fraction: 3` ->
    /// cap 1. The higher-`alive` carrier is picked first (the `_plan_ev_of +
    /// alive*0.1` stand-in), and a SECOND grant the same round is refused even
    /// though the other carrier is still eligible and unused.
    #[test]
    fn second_wind_caps_grants_per_round_at_ceil_carriers_over_the_fraction() {
        let (mut st, mut statics) = buff_line();
        st.player[2] = st.player[0]; // "b" joins "a"'s side for this fixture
        statics[0].second_wind_active = true;
        statics[2].second_wind_active = true;
        st.activated[0] = true;
        st.activated[2] = true;
        let picked = second_wind_candidate(&statics, &st, st.player[0]).expect("a candidate exists");
        assert_eq!(picked, 2, "\"b\" (alive 3) outranks \"a\" (alive 2)");
        spend_second_wind(&mut st, picked);
        assert!(
            second_wind_candidate(&statics, &st, st.player[0]).is_none(),
            "cap reached this round — \"a\" is still eligible and unused, but capped"
        );
    }

    /// The army cap resets on a NEW round: the same two carriers as above,
    /// "a" already spent in round 0 — round 1 opens a fresh cap and finds
    /// "b" (still unused).
    #[test]
    fn second_wind_round_cap_resets_on_a_new_round() {
        let (mut st, mut statics) = buff_line();
        st.player[2] = st.player[0];
        statics[0].second_wind_active = true;
        statics[2].second_wind_active = true;
        st.activated[0] = true;
        spend_second_wind(&mut st, 0); // round 0's one grant (cap = ceil(2/3) = 1)
        st.round += 1;
        st.activated[2] = true; // "b" enters round 1 already-activated, unused
        assert_eq!(second_wind_candidate(&statics, &st, st.player[0]), Some(2));
    }

    // --- TEST WAVE (2026-09-14, D-PROOF) — the alias's NUMBER pin: the
    // EXACT name read (`unit_rule_active`'s own literal, gf
    // human_inquisition) stamps `second_wind_active` through the REAL
    // `build_for`, and the stamp earns exactly ONE grant per game.

    /// "Inquisitorial Agent" (gf/human_inquisition, primitive Second Wind):
    /// the alias carrier re-opens its own activation when the round closes,
    /// the uses counter lands on 1, and the once-per-game gate refuses a
    /// second grant.
    #[test]
    fn an_inquisitorial_agent_carrier_earns_its_one_second_wind_by_name() {
        let mut reg = crate::rules::Registries::new(&repo_root());
        let built = UnitStatic::build_for(
            &mut reg,
            &boost_carrier("gf", "human_inquisition", &["Inquisitorial Agent"]),
            crate::acts::CURRENT_RULES_EPOCH,
        );
        assert!(built.second_wind_active, "the exact name is registry-backed");
        let bare = UnitStatic::build_for(
            &mut reg,
            &boost_carrier("gf", "human_inquisition", &[]),
            crate::acts::CURRENT_RULES_EPOCH,
        );
        assert!(!bare.second_wind_active, "no name, no carrier");

        let (mut st, mut statics) = buff_line();
        statics[0] = UnitStatic { name: "a".into(), model_count: 2, wounds_max: vec![1, 1], ..built };
        st.activated = vec![false, true, true, true];
        st.fatigued[0] = true;
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(!next.activated[0], "the agent re-opens its own activation");
        assert!(!next.fatigued[0], "the re-opened activation clears fatigue");
        assert!(next.second_wind_used[0]);
        assert_eq!(next.second_wind_uses, 1, "uses_per_game 1: the first grant");
        assert!(
            second_wind_candidate(&statics, &next, next.player[0]).is_none(),
            "once per GAME: the spent carrier is never picked again"
        );
    }

    /// D-PROOF (2026-09-15) — "Martial Prowess" (gf dark_elf_raiders,
    /// primitive Second Wind, params `uses_per_game: 1, army_cap_fraction: 3`
    /// — rules_mechanics_gf.json:3135): the EXACT name read stamps the
    /// carrier through the REAL `build_for`, `uses_per_game` stays 1 (a
    /// spent carrier is never picked again), and the army cap is
    /// `ceil(carriers / army_cap_fraction)` — FOUR carriers give 2 grants per
    /// round, the THIRD is refused. The cap half is the deliberately-broken
    /// read's pin: mistyping `SECOND_WIND_CAP_FRACTION` moves THIS fixture's
    /// cap (ceil(4/4) = 1) while every 2-carrier pin stays at 1 either way.
    #[test]
    fn a_martial_prowess_carrier_gets_one_grant_per_game_and_ceil_carriers_over_3_per_round() {
        let mut reg = crate::rules::Registries::new(&repo_root());
        let built = UnitStatic::build_for(
            &mut reg,
            &boost_carrier("gf", "dark_elf_raiders", &["Martial Prowess"]),
            crate::acts::CURRENT_RULES_EPOCH,
        );
        assert!(built.second_wind_active, "the exact name is registry-backed");
        let bare = UnitStatic::build_for(
            &mut reg,
            &boost_carrier("gf", "dark_elf_raiders", &[]),
            crate::acts::CURRENT_RULES_EPOCH,
        );
        assert!(!bare.second_wind_active, "no name, no carrier");

        // uses_per_game 1: the bearer re-opens its own activation once, the
        // grant is spent, and the SAME carrier is never picked again.
        let (mut st, mut statics) = buff_line();
        statics[0] = UnitStatic { name: "a".into(), model_count: 2, wounds_max: vec![1, 1], ..built };
        st.activated = vec![false, true, true, true];
        st.fatigued[0] = true;
        let (next, _) = run_buff(&st, &statics, &buff_action(None), 11);
        assert!(next.second_wind_used[0], "the grant is spent by its own activation");
        assert!(
            second_wind_candidate(&statics, &next, next.player[0]).is_none(),
            "uses_per_game 1: the spent carrier is never picked again"
        );

        // ceil(carriers / army_cap_fraction): four LIVING carriers on one
        // side -> cap 2 per round. The first two grants go, the third is
        // refused even though carriers are still eligible and unused.
        let (mut st4, mut statics4) = buff_line();
        st4.player = vec![0, 0, 0, 0];
        st4.alive[3] = 1; // "bh" joins the side alive — the fourth carrier
        st4.wounds[3] = vec![1];
        st4.radii[3] = vec![IN2M];
        st4.positions[3] = vec![[9.0 * IN2M, 0.0, 0.0]];
        for s in statics4.iter_mut() {
            s.second_wind_active = true;
        }
        st4.activated = vec![true, true, true, true];
        let picked = second_wind_candidate(&statics4, &st4, 0)
            .expect("four carriers, cap 2: a candidate exists");
        spend_second_wind(&mut st4, picked);
        let picked2 = second_wind_candidate(&statics4, &st4, 0)
            .expect("ceil(4 / 3) = 2: the second grant goes");
        spend_second_wind(&mut st4, picked2);
        assert!(
            second_wind_candidate(&statics4, &st4, 0).is_none(),
            "ceil(4 / 3) = 2 — the third grant is refused this round"
        );
    }
