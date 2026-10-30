//! Rules 3.6 lane ux tests for the sim module; owned by lane ux.
use super::*;

    // ---- UX-20 (rules 3.6, CORE 24a): Dangerous terrain - one affected model is enough, and then the
    //      WHOLE joined unit (host + attached heroes) takes ONE test. The dice per model stay its Tough
    //      value here; the count of wounds left is the next row (UX-21) ------------------------------

    /// `dangerous_line`'s unit "a" grown to ten one-wound models in a column at x = 4": model k stands at
    /// z = 3.5" + 2" * k, so only model 0's 1" base edge reaches into `dangerous_bar_board`'s bar
    /// (z below 3") and the other nine stand clear of it. Nobody moves (`next` = `state`), so this is the
    /// activated-in-it half of the trigger, read model by model exactly like a crossing.
    fn ten_models_one_clipping() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = dangerous_line();
        st.positions[0] = (0..10).map(|k| [4.0 * IN2M, 0.0, (3.5 + 2.0 * k as f64) * IN2M]).collect();
        Rc::make_mut(&mut st.radii)[0] = vec![IN2M; 10];
        st.wounds[0] = vec![1; 10];
        st.alive[0] = 10;
        statics[0].wounds_max = vec![1; 10];
        statics[0].model_count = 10;
        (st, statics)
    }

    /// The same ten models all stepped 2" clear of the bar, and `four_unit_line`'s joined hero (unit 1,
    /// attached to unit 0) as ONE Tough(3) model whose base edge clips it: only the hero is affected.
    fn hero_alone_clipping() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = ten_models_one_clipping();
        st.positions[0] = (0..10).map(|k| [4.0 * IN2M, 0.0, (5.5 + 2.0 * k as f64) * IN2M]).collect();
        st.positions[1] = vec![[7.0 * IN2M, 0.0, 3.5 * IN2M]];
        st.wounds[1] = vec![3];
        statics[1].name = "ah".into();
        statics[1].wounds_max = vec![3];
        (st, statics)
    }

    /// The dangerous dice of unit 0 standing where it is, on the bar board, at `epoch`.
    fn standing_dice(st: &State, statics: &[UnitStatic], epoch: u32) -> (i64, crate::dice::ShootResult) {
        let t = dangerous_bar_board();
        let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Seams::default() };
        let mut shot = crate::dice::ShootResult::default();
        let n = dangerous_dice(statics, st, st, 0, seams, None, Cover::Board(&t), &mut shot);
        (n, shot)
    }

    /// The control leg: below the 3.6 epoch only the affected model tests, one die for its one wound, and
    /// no whole-unit line is written.
    #[test]
    fn one_clipping_model_of_ten_rolls_its_own_die_at_epoch_72() {
        let (st, statics) = ten_models_one_clipping();
        let (n, shot) = standing_dice(&st, &statics, crate::acts::EPOCH_72_PLAYTEST_RULES);
        assert_eq!(n, 1, "epoch 72 keeps one test per affected model");
        assert!(shot.log.iter().all(|l| !l.contains("whole unit")), "{:?}", shot.log);
    }

    /// The new leg: the same single clipping model makes the whole ten-model unit test once (ten dice),
    /// the core names the test in its log, and a unit nobody of which is affected still rolls nothing.
    #[test]
    fn one_clipping_model_of_ten_makes_the_whole_unit_test_at_epoch_73() {
        let (mut st, statics) = ten_models_one_clipping();
        let (n, shot) = standing_dice(&st, &statics, crate::acts::EPOCH_73_V36);
        assert_eq!(n, 10, "one affected model: the whole unit tests, every model's Tough counted");
        assert!(
            shot.log.iter().any(|l| l.contains("Dangerous terrain") && l.contains("whole unit")),
            "the applied rule must name itself: {:?}",
            shot.log
        );
        st.positions[0][0][2] += 2.0 * IN2M;
        assert_eq!(standing_dice(&st, &statics, crate::acts::EPOCH_73_V36).0, 0, "nobody affected: no test");
    }

    /// The control leg for a joined hero: only the hero is affected, so only the hero's Tough(3) rolls.
    #[test]
    fn a_joined_hero_alone_in_it_tests_on_its_own_at_epoch_72() {
        let (st, statics) = hero_alone_clipping();
        assert_eq!(standing_dice(&st, &statics, crate::acts::EPOCH_72_PLAYTEST_RULES).0, 3);
    }

    /// The new leg: the hero is part of the joined unit, so its host's ten models test with it in one
    /// test - ten dice for the host plus the hero's three.
    #[test]
    fn a_joined_hero_alone_in_it_makes_the_joined_unit_test_at_epoch_73() {
        let (st, statics) = hero_alone_clipping();
        assert_eq!(standing_dice(&st, &statics, crate::acts::EPOCH_73_V36).0, 13);
    }
