use super::*;

    /// Audit 2026-09-13 §2.2, strike-order half — the table runs a WHOLE
    /// `SoloStrike.COUNTER_ONLY` phase before Impact (main.gd:8268-8274):
    /// the defender's Counter weapons strike first, only non-Counter weapons
    /// remain for the normal strike-back slot (:8315), and an Impact pool
    /// never rolls once the counter phase wiped the charger (:8276's alive
    /// gate). The core only marks `counter_strikes_first` and orders by
    /// Unwieldy — the 5-model Impact(1) charger vs 3 Counter models board
    /// flips the melee-winner tally and with it the morale test.
    ///
    /// RED on the tray: the first roll of the charge melee must be the
    /// DEFENDER's counter-strike hit roll, not the charger's Impact pool.
    #[test]
    fn counter_strikes_run_a_whole_phase_before_impact() {
        let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
        let statics = vec![
            UnitStatic {
                ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 5, impact: 1, ..Default::default() },
                name: "Charger".into(),
                melee: vec![ShootProfile { name: "Blade".into(), attacks: 1, count: 1, range: 0, ..Default::default() }],
                model_count: 5,
                wounds_max: vec![1; 5],
                ..Default::default()
            },
            UnitStatic {
                ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 3, counter_models: 3, ..Default::default() },
                name: "Defender".into(),
                melee: vec![ShootProfile { name: "Reaver".into(), attacks: 1, count: 1, range: 0, counter: true, ..Default::default() }],
                model_count: 3,
                wounds_max: vec![1; 3],
                ..Default::default()
            },
        ];
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
        st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
        st.player = vec![0, 1];
        st.alive = vec![5, 3];
        st.attached = Rc::new(vec![vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None]);
        st.positions[0] = (1..=5).map(|i| [i as f64 * IN2M, 0.0, 0.0]).collect();
        st.wounds[0] = vec![1; 5];
        st.radii[0] = vec![IN2M; 5];
        st.positions[1] = vec![[0.0, 0.0, 0.0]; 3];
        st.wounds[1] = vec![1; 3];
        st.radii[1] = vec![IN2M; 3];

        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Default::default() };
        let mut tray = Tray::seeded(27);
        let mut shot = ShootResult::default();
        tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot);
        assert!(
            !shot.rolls.is_empty(),
            "the charge melee must roll at all"
        );
        assert_eq!(
            (shot.rolls[0].kind.as_str(), shot.rolls[0].owner.as_str()),
            ("attack", "Defender"),
            "the counter pre-phase strikes before Impact — its hit roll opens the stream"
        );
    }