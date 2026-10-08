    use super::*;

    // -------- inventory C03: special-weapon bearers fall LAST in the imagined volley ----------
    // The table's dice assumption (`bearer_scaled_attacks`, sim.rs) prices a weapon carried by FEWER models than
    // the unit as `per-copy x min(copies, alive)`; the imagination shrank every weapon pro rata.
    // Order with `fire_in_range_only` (#1693): the casualty rule runs first (bearers alive), the reach filter
    // is applied afterwards on those bearers; both rescale `sc.attacks[k]`, so they compose in that order.

    fn weapon(name: &str, attacks: i64, count: i64, range: i64) -> ShootProfile {
        ShootProfile { name: name.into(), attacks, count, range, ..Default::default() }
    }

    /// A 10-model squad: rifles (10 attacks, carried by the whole squad) and ONE heavy weapon (3 attacks).
    fn squad() -> UnitStatic {
        UnitStatic {
            name: "squad".into(),
            model_count: 10,
            shoot: vec![weapon("Rifle", 10, 10, 24), weapon("Heavy", 3, 1, 24)],
            ..Default::default()
        }
    }

    fn attacks_for(alive: i64, on: bool) -> Vec<i64> {
        let us = squad();
        let mut sc = Scratch { bearers_last: on, ..Scratch::default() };
        profiles_of(&us, alive, 12.0, &mut sc);
        sc.attacks.clone()
    }

    /// RED on unmodified behaviour: 7 of 10 dead, the heavy weapon's one bearer lives -> it fires at full strength.
    #[test]
    fn seven_dead_the_heavy_weapon_keeps_its_full_attacks_with_the_knob() {
        let seams = Seams { casualties_bearers_last: true, ..Seams::default() };
        let (st, mut statics) = hero_line();
        statics[0] = squad();
        let mut st = st;
        st.alive[0] = 3;
        let mut sc = Scratch::default();
        member_profiles_of(&statics, &st, 0, false, 12.0, seams, &mut sc);
        assert_eq!(sc.attacks[1], 3, "knob on: the heavy weapon's one living bearer fires its full 3 attacks");
        assert_eq!(sc.attacks[0], 3, "the common rifle keeps the pro-rata ratio (3 of 10)");
        let off = attacks_for(3, false);
        assert_eq!(off, vec![3, 1], "knob off: today's pro-rata numbers, the heavy weapon at 3/10 = 1 attack");
    }

    /// No casualties: on == off.
    #[test]
    fn no_casualties_reads_the_same_with_the_knob() {
        assert_eq!(attacks_for(10, true), attacks_for(10, false));
        assert_eq!(attacks_for(10, true), vec![10, 3]);
    }

    /// One model left: the table lets the special weapon keep firing (min(copies, alive) = 1).
    #[test]
    fn last_model_alive_still_fires_the_heavy_weapon() {
        assert_eq!(attacks_for(1, true), vec![1, 3]);
        assert_eq!(attacks_for(1, false), vec![1, 0]);
    }

    /// A weapon carried by two models: two bearers while at least two live, then what is left.
    #[test]
    fn a_two_bearer_weapon_keeps_min_of_bearers_and_alive() {
        let mut us = squad();
        us.shoot = vec![weapon("Pair", 6, 2, 24)];
        for (alive, want) in [(10, 6), (5, 6), (2, 6), (1, 3)] {
            let mut sc = Scratch { bearers_last: true, ..Scratch::default() };
            profiles_of(&us, alive, 12.0, &mut sc);
            assert_eq!(sc.attacks[0], want, "alive {alive}");
        }
    }

    /// The hero-fold path (host first, then the joined hero) honours the knob too.
    #[test]
    fn the_folded_member_list_honours_the_knob() {
        let (mut st, mut statics) = hero_line();
        statics[0].model_count = 4;
        statics[0].shoot = vec![weapon("Rifle", 4, 4, 24), weapon("Gun", 3, 1, 24)];
        st.alive[0] = 1;
        st.alive[1] = 1;
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        let run = |on: bool| {
            let seams = Seams { hero_attach: true, casualties_bearers_last: on, ..Seams::default() };
            let mut sc = Scratch::default();
            member_profiles_of(&statics, &st, 0, false, 12.0, seams, &mut sc);
            sc.attacks.clone()
        };
        assert_eq!(run(true)[..2], [1, 3]);
        assert_eq!(run(false)[..2], [1, 1]);
    }

    /// The knob parses from a header and reaches the seams; absent = off.
    #[test]
    fn the_knob_parses_and_reaches_the_seams() {
        let on: crate::acts::Knobs = serde_json::from_str(r#"{"casualties_bearers_last": true}"#).unwrap();
        assert!(on.casualties_bearers_last);
        assert!(crate::plan::seams_of(&on).casualties_bearers_last);
        let off: crate::acts::Knobs = serde_json::from_str("{}").unwrap();
        assert!(!off.casualties_bearers_last);
        assert!(!crate::plan::seams_of(&off).casualties_bearers_last);
    }
