use super::*;

    // ---------------------------------------- block B8: second wind ---

    /// The candidate scan's SKIPS: an attached hero of the acting side is
    /// never a candidate even when activated and unused — the `||` chain at
    /// the gate must not collapse into an `&&` that lets the hero through.
    #[test]
    fn an_attached_hero_is_never_the_second_wind_candidate() {
        let (mut st, mut statics) = buff_line();
        st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, Some(0), None, None]);
        statics[1].second_wind_active = true;
        st.activated[1] = true;
        assert_eq!(second_wind_candidate(&statics, &st, 0), None);
    }

    /// Nor is an ENEMY unit, however eligible it looks: the player mismatch
    /// alone skips it. An `&&` there lets a fresh enemy carrier be picked.
    #[test]
    fn an_enemy_unit_is_never_the_second_wind_candidate() {
        let (mut st, mut statics) = buff_line();
        statics[2].second_wind_active = true;
        st.activated[2] = true;
        assert_eq!(second_wind_candidate(&statics, &st, 0), None);
    }

    /// The pick is strictly-greater: two carriers at 2 alive each, the FIRST
    /// wins. A `>=` lets the later equal twin overwrite the pick.
    #[test]
    fn two_equal_carriers_pick_the_first_not_the_last() {
        let (mut st, mut statics) = buff_line();
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        statics[0].second_wind_active = true;
        statics[1].second_wind_active = true;
        st.alive[1] = st.alive[0];
        st.activated[0] = true;
        st.activated[1] = true;
        assert_eq!(second_wind_candidate(&statics, &st, 0), Some(0));
    }

    /// The round cap: ceil(3 carriers / 3) = 1 grant, so one spent use
    /// exhausts the round. Turning the `- 1` into a `/ 1` inflates the cap
    /// to 2 and hands out a second activation.
    #[test]
    fn one_spent_grant_exhausts_a_three_carrier_round() {
        let (mut st, mut statics) = buff_line();
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.player[2] = 0; // a third carrier joins the acting side
        statics[0].second_wind_active = true;
        statics[1].second_wind_active = true;
        statics[2].second_wind_active = true;
        st.activated[0] = true;
        st.activated[1] = true;
        st.second_wind_used[1] = true; // spent, but still a carrier for the cap
        st.second_wind_round = st.round;
        st.second_wind_uses = 1;
        assert_eq!(second_wind_candidate(&statics, &st, 0), None);
    }
