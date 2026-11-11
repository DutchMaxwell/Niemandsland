use super::*;

    // A2 (`EPOCH_72_PLAYTEST_RULES`, the table's #1912 in `_solo_shooting_morale`): at the end of an
    // activation in which a unit takes WOUNDS that leave it at half or less of its starting size it
    // tests morale (GF v3.5.1 p.10) — not only when a model fell. Below 72 the old trigger replays.

    /// Unit 0: a four-model Tough(3) squad, `alive` of them left, `wounds` = their wounds now.
    fn squad(alive: i64, wounds: Vec<i64>) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = hero_line();
        statics[0].model_count = 4;
        st.alive[0] = alive;
        st.wounds[0] = wounds;
        (st, statics)
    }

    /// Two models left before and after (no loss); 6 wounds before, `after` now.
    fn test_due(alive: i64, after: Vec<i64>, epoch: u32) -> bool {
        let (st, statics) = squad(alive, after);
        let s = Seams { rules_epoch: epoch, ..Seams::default() };
        shooting_morale_trigger(&st, &statics, s, &statics[0], 0, alive, 3 * alive)
    }

    /// OLD leg: at 71 wounds without a lost model never test, even at half strength.
    #[test]
    fn wounds_without_a_loss_do_not_test_at_epoch_71() {
        assert!(!test_due(2, vec![3, 1], 71), "71 replays the casualty-only trigger");
    }

    /// NEW leg: from 72 the wounds test at 2 of 4; above half (3 of 4) or without wounds they do not.
    #[test]
    fn wounds_at_half_strength_test_from_epoch_72() {
        let e = crate::acts::EPOCH_72_PLAYTEST_RULES;
        assert!(test_due(2, vec![3, 1], e), "A2: 2 of 4 alive and wounded — the test is due");
        assert!(!test_due(3, vec![3, 3, 1], e), "3 of 4 is above half");
        assert!(!test_due(2, vec![3, 3], e), "no wound taken, no test");
    }
