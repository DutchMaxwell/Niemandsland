//! Rules 3.6 lane melee tests for the sim module; owned by lane melee.

mod mel_par_f5 {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::state::Kit;

    // MEL-PAR-F5 — a dead model's melee weapon dies with it. The table counts a weapon's attacks off the
    // LIVING models' own kits; the core shrank every melee weapon by the unit's alive/max ratio, so a dead
    // specialist kept swinging a share of its weapon. From EPOCH_73_V36, with one kit per living model and
    // every living model striking, the core counts the living bearers too; partial contact stays pro rata.

    fn blade(name: &str, attacks: i64, count: i64) -> ShootProfile {
        ShootProfile { name: name.into(), attacks, count, range: 0, ..Default::default() }
    }

    /// Five sisters: four carry a CCW (1 attack each), one an Energy Fist (1 attack). Two fell, the fist
    /// bearer among them, so the three living kits all name the CCW. `near` of the three stand within reach
    /// of the single target model, the rest 20" away.
    fn sisters(near: usize) -> (State, Vec<UnitStatic>) {
        let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
        let statics = vec![
            UnitStatic {
                ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 5, ..Default::default() },
                name: "Sisters".into(),
                melee: vec![blade("CCW", 4, 4), blade("Energy Fist", 1, 1)],
                model_count: 5,
                wounds_max: vec![1; 5],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
                name: "Target".into(),
                model_count: 1,
                wounds_max: vec![1],
                ..Default::default()
            },
        ];
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
        st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
        st.player = vec![0, 1];
        st.alive = vec![3, 1];
        st.attached = Rc::new(vec![vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None]);
        st.positions[0] = (0..3).map(|i| [(if i < near { 1.0 } else { 20.0 }) * IN2M, 0.0, i as f64 * IN2M]).collect();
        st.wounds[0] = vec![1; 3];
        Rc::make_mut(&mut st.radii)[0] = vec![IN2M; 3];
        st.positions[1] = vec![[0.0, 0.0, 0.0]];
        st.wounds[1] = vec![1];
        Rc::make_mut(&mut st.radii)[1] = vec![IN2M];
        let ccw = Kit { weapons: vec![0], equipment: 0, wounds_max: 1 };
        st.kits = vec![Rc::new(vec![ccw; 3]), Rc::new(Vec::new())];
        st.kit_names = vec![Rc::new(vec!["CCW".into(), "Energy Fist".into()]), Rc::new(Vec::new())];
        (st, statics)
    }

    fn strike(st: &State, statics: &[UnitStatic], epoch: u32, reach: bool) -> Vec<i64> {
        let seams = Seams { rules_epoch: epoch, melee_reach: reach, ..Seams::default() };
        melee_parts(statics, st, 0, 1, seams)[0].1.attacks.clone()
    }

    fn ev_attacks(st: &State, statics: &[UnitStatic], epoch: u32) -> Vec<i64> {
        let mut sc = Scratch::default();
        member_profiles_of(statics, st, 0, true, 0.0, Seams { rules_epoch: epoch, ..Seams::default() }, &mut sc);
        sc.attacks
    }

    #[test]
    fn living_bearers_counts_the_living_kits_naming_a_weapon() {
        let (st, _) = sisters(3);
        assert_eq!(living_bearers(&st, 0, "CCW"), Some(3));
        assert_eq!(living_bearers(&st, 0, "Energy Fist"), Some(0), "the fist's bearer is dead");
        assert_eq!(living_bearers(&st, 0, "Lance"), Some(0), "a weapon no living kit carries");
    }

    #[test]
    fn living_bearers_is_none_without_aligned_kits() {
        let (mut st, _) = sisters(3);
        assert_eq!(living_bearers(&st, 1, "CCW"), None, "no kits recorded");
        Rc::make_mut(&mut st.kits[0]).pop();
        assert_eq!(living_bearers(&st, 0, "CCW"), None, "two kits for three living models");
        st.kits.clear();
        assert_eq!(living_bearers(&st, 0, "CCW"), None, "a state that carries no kits at all");
    }

    #[test]
    fn melee_strike_counts_living_bearers_at_epoch_73() {
        let (st, statics) = sisters(3);
        assert_eq!(strike(&st, &statics, EPOCH_73_V36, false), vec![3, 0], "one CCW pool of 3, no fist");
        assert_eq!(strike(&st, &statics, EPOCH_73_V36, true), vec![3, 0], "all three in reach strike");
    }

    #[test]
    fn melee_strike_keeps_pro_rata_at_epoch_72() {
        let (st, statics) = sisters(3);
        assert_eq!(strike(&st, &statics, EPOCH_72_PLAYTEST_RULES, false), vec![2, 1], "4x3/5 and 1x3/5 rounded");
    }

    #[test]
    fn partial_contact_keeps_pro_rata_at_epoch_73() {
        let (st, statics) = sisters(2);
        assert_eq!(strike(&st, &statics, EPOCH_73_V36, true), vec![2, 0], "2 of 3 strike: 4x2/5 and 1x2/5 rounded");
    }

    #[test]
    fn melee_ev_counts_living_bearers_at_epoch_73() {
        let (st, statics) = sisters(3);
        assert_eq!(ev_attacks(&st, &statics, EPOCH_73_V36), vec![3, 0]);
    }

    #[test]
    fn melee_ev_keeps_pro_rata_at_epoch_72() {
        let (st, statics) = sisters(3);
        assert_eq!(ev_attacks(&st, &statics, EPOCH_72_PLAYTEST_RULES), vec![2, 1]);
    }
}
