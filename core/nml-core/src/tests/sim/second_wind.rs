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
