    use super::*;

    // -------- inventory C12: a joined hero counts in the unit size ----------
    // GF/AoF v3.5.1 p.14: "when a Hero joins a unit ... the unit's size is increased by 1". The table
    // (`main._solo_below_half_strength`, `_solo_shooting_morale`) already measures COMBINED alive over
    // COMBINED total; the imagination measured the host alone.

    /// Unit 0 = a four-model squad with a joined hero (unit 1, one model); `squad_alive` squad models live.
    fn hero_squad(squad_alive: i64, with_hero: bool) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = hero_line();
        statics[0].model_count = 4;
        statics[1].model_count = 1;
        st.alive[0] = squad_alive;
        st.alive[1] = 1;
        st.attached = Rc::new(vec![if with_hero { vec![1] } else { vec![] }, vec![], vec![], vec![]]);
        (st, statics)
    }

    fn seams(on: bool) -> Seams {
        Seams { hero_attach: true, hero_counts_in_size: on, ..Seams::default() }
    }

    fn half(st: &State, statics: &[UnitStatic], on: bool) -> bool {
        below_half(st, statics, &statics[0], 0, seams(on))
    }

    /// The post-volley morale trigger with the snapshot taken as the resolve takes it (4 squad models + the
    /// hero alive before; `squad_alive` after).
    fn shooting_test_due(squad_alive: i64, on: bool) -> bool {
        let (before, statics) = hero_squad(4, true);
        let s = seams(on);
        let alive_before = morale_alive(&before, 0, s);
        let (after, _) = hero_squad(squad_alive, true);
        shooting_morale_trigger(&after, &statics, s, &statics[0], 0, alive_before, 0)
    }

    /// RED on unmodified behaviour: a hero + 4-model squad with 2 squad models dead is 3 of 5 = NOT half.
    #[test]
    fn hero_and_squad_two_dead_is_not_half_strength_with_the_knob() {
        let (st, statics) = hero_squad(2, true);
        assert!(!half(&st, &statics, true), "knob on: 3 of 5 alive is over half (no rout on a lost melee)");
        assert!(half(&st, &statics, false), "knob off: today's host-only reading, 2 of 4 = half strength");
        assert!(!shooting_test_due(2, true), "knob on: no shooting morale test at 3 of 5");
        assert!(shooting_test_due(2, false), "knob off: today's test at 2 of 4");
    }

    /// 3 squad models dead = 2 of 5 alive = half strength either way.
    #[test]
    fn three_squad_models_dead_is_half_strength_in_both() {
        let (st, statics) = hero_squad(1, true);
        assert!(half(&st, &statics, true));
        assert!(half(&st, &statics, false));
        assert!(shooting_test_due(1, true));
        assert!(shooting_test_due(1, false));
    }

    /// A unit without a hero: on == off, whatever the casualties.
    #[test]
    fn a_unit_without_a_hero_reads_the_same_with_the_knob() {
        for alive in 0..=4 {
            let (st, statics) = hero_squad(alive, false);
            assert_eq!(half(&st, &statics, true), half(&st, &statics, false), "alive {alive}");
        }
    }

    /// The knob parses from a header and reaches the seams; absent = off.
    #[test]
    fn the_knob_parses_and_reaches_the_seams() {
        let on: crate::acts::Knobs = serde_json::from_str(r#"{"hero_counts_in_size": true}"#).unwrap();
        assert!(on.hero_counts_in_size);
        assert!(crate::plan::seams_of(&on).hero_counts_in_size);
        let off: crate::acts::Knobs = serde_json::from_str("{}").unwrap();
        assert!(!off.hero_counts_in_size);
        assert!(!crate::plan::seams_of(&off).hero_counts_in_size);
    }
