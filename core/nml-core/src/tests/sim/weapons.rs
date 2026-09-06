use super::*;

    // ------------------------------------------------- NML-1132: the WEAPONS ---

    /// The imagined VOLLEY is the table's member list: the host's weapons and its
    /// joined hero's. At 30" the host's own 24" rifle is out of reach, so the fold
    /// is the only thing that can put a die on the table at all — and it puts the
    /// HERO's 36" gun there, with the hero's own survivor scaling.
    #[test]
    fn the_imagined_volley_carries_a_joined_heros_ranged_weapon() {
        let (st, statics) = hero_line();
        let on = Seams { hero_attach: true, ..Seams::default() };
        let mut sc = Scratch::default();
        member_profiles_of(&statics, &st, 0, false, 30.0, on, &mut sc);
        assert_eq!(kept(&statics, false, &sc), vec!["Heavy Gun".to_string()]);
        assert_eq!(sc.attacks, vec![3]);
        // Closer in, BOTH members fire, host first — the table's build order.
        member_profiles_of(&statics, &st, 0, false, 20.0, on, &mut sc);
        assert_eq!(kept(&statics, false, &sc), vec!["Rifle".to_string(), "Heavy Gun".into()]);
        assert_eq!(sc.attacks, vec![1, 3]);
    }

    /// The MELEE half, and the RED for both: with the seam off `member_profiles_of`
    /// is the plain `profiles_of`/`melee_profiles_of` — the host alone, which is the
    /// imagination this ticket found and the identity every recorded corpus replays on.
    #[test]
    fn the_seam_off_leaves_the_host_alone_in_both_halves() {
        let (st, statics) = hero_line();
        let on = Seams { hero_attach: true, ..Seams::default() };
        let off = Seams::default();
        let mut sc = Scratch::default();
        member_profiles_of(&statics, &st, 0, true, 0.0, on, &mut sc);
        assert_eq!(kept(&statics, true, &sc), vec!["CCW".to_string(), "Fist".into()]);
        assert_eq!(sc.attacks, vec![2, 4]);
        member_profiles_of(&statics, &st, 0, true, 0.0, off, &mut sc);
        assert_eq!(kept(&statics, true, &sc), vec!["CCW".to_string()]);
        assert_eq!(sc.attacks, vec![2]);
        // The RED knob (vintage corpus, `engage_fold=false`): the weapons fold is
        // one of the LATE halves, so it must read the pin exactly like the
        // engage half does — host alone even with `hero_attach` on.
        let red = Seams { hero_attach: true, no_engage_fold: true, ..Seams::default() };
        member_profiles_of(&statics, &st, 0, true, 0.0, red, &mut sc);
        assert_eq!(kept(&statics, true, &sc), vec!["CCW".to_string()]);
        assert_eq!(sc.attacks, vec![2]);
        member_profiles_of(&statics, &st, 0, false, 30.0, off, &mut sc);
        assert!(kept(&statics, false, &sc).is_empty());   // the 24" rifle cannot reach
    }

    /// A hero with no living model brings no shot — `main._run_ai_shooting` :2915
    /// skips exactly that member, and so does the fold.
    #[test]
    fn a_dead_joined_hero_brings_no_weapon() {
        let (mut st, statics) = hero_line();
        st.alive[1] = 0;
        let on = Seams { hero_attach: true, ..Seams::default() };
        let mut sc = Scratch::default();
        member_profiles_of(&statics, &st, 0, true, 0.0, on, &mut sc);
        assert_eq!(kept(&statics, true, &sc), vec!["CCW".to_string()]);
    }

    /// The RANGE half: the reach is measured over the table's two model sets, so the
    /// two joined heroes (2" and 9") decide it at 7" — not the hosts' 12". Folding
    /// one side alone would read 9" or 10", which is why the number is exact.
    #[test]
    fn the_imagined_reach_is_measured_from_the_joined_heros_model() {
        let st = four_unit_line();
        let on = Seams { hero_attach: true, ..Seams::default() };
        assert!((fold_dist_in(&st, 0, 2, on) - 7.0).abs() < 1e-4);
        assert!((fold_dist_in(&st, 0, 2, Seams::default()) - 12.0).abs() < 1e-4);
    }
