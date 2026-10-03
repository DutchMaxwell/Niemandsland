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

        let seams = Seams { rules_epoch: crate::acts::EPOCH_13_WHO_WINS, ..Default::default() };
        let mut tray = Tray::seeded(27);
        let mut shot = ShootResult::default();
        tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
        assert!(
            !shot.rolls.is_empty(),
            "the charge melee must roll at all"
        );
        assert_eq!(
            (shot.rolls[0].kind, shot.rolls[0].owner.as_str()),
            ("attack", "Defender"),
            "the counter pre-phase strikes before Impact — its hit roll opens the stream"
        );
    }

    /// The OLD leg, epoch 12 (the gate's own constant, `EPOCH_13_WHO_WINS`):
    /// the tray replays the pre-fix order — Impact opens the stream, the
    /// charger strikes before the defender, no COUNTER_ONLY phase exists.
    #[test]
    fn at_epoch_12_impact_still_opens_the_stream_and_the_counter_phase_never_runs() {
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

        let seams = Seams { rules_epoch: 12, ..Default::default() };
        let mut tray = Tray::seeded(27);
        let mut shot = ShootResult::default();
        tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
        assert!(
            !shot.rolls.is_empty(),
            "the charge melee must roll at all"
        );
        assert_eq!(
            (shot.rolls[0].kind, shot.rolls[0].owner.as_str()),
            ("attack", "Charger"),
            "epoch 12 replays the old order: the charger's Impact pool opens the stream"
        );
    }

    /// Tray-exact tail — the table's Counter walk covers the host AND its living attached heroes
    /// (`_solo_has_counter` main.gd:7050, `counter_models_of` solo_controller.gd:8465): a joined
    /// hero's Counter weapon strikes first and cuts the charger's Impact dice although the host
    /// carries none. With `Seams::tray_exact` the core does both, unflagged; without it the old
    /// host-only read stands and `counter_strikes_first` names the gap. A CHARGER's own Counter
    /// weapon strikes in its normal slot and is never flagged.
    #[test]
    fn a_joined_heros_counter_strikes_first_and_cuts_impact_with_tray_exact() {
        let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
        let unit = |name: &str, models: i64, impact: i64, counter: bool| UnitStatic {
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models, impact, counter_models: counter as i64, ..Default::default() },
            name: name.into(),
            melee: vec![ShootProfile { name: "Blade".into(), attacks: 1, count: 1, range: 0, counter, ..Default::default() }],
            model_count: models,
            wounds_max: vec![1; models as usize],
            ..Default::default()
        };
        let charge = |charger_counter: bool, tray_exact: bool| {
            let statics = vec![unit("Charger", 5, 2, charger_counter), unit("Host", 3, 0, false), unit("Hero", 1, 0, !charger_counter)];
            let mut st = four_unit_line();
            st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into(), "bh".into()], index: HashMap::new(), profile: vec![0, 1, 2] });
            st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile.clone(), profile.clone()], index: HashMap::new() });
            st.player = vec![0, 1, 1];
            st.alive = vec![5, 3, 1];
            st.attached = Rc::new(vec![vec![], vec![2], vec![]]);
            st.attached_to = Rc::new(vec![None, None, Some(1)]);
            st.positions[0] = (1..=5).map(|i| [i as f64 * IN2M, 0.0, 0.0]).collect();
            (st.wounds[0], st.radii[0]) = (vec![1; 5], vec![IN2M; 5]);
            (st.positions[1], st.wounds[1], st.radii[1]) = (vec![[0.0, 0.0, 0.0]; 3], vec![1; 3], vec![IN2M; 3]);
            (st.positions[2], st.wounds[2], st.radii[2]) = (vec![[0.0, 0.0, 0.0]], vec![1], vec![IN2M]);
            let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact, ..Default::default() };
            let (mut tray, mut shot) = (Tray::seeded(27), ShootResult::default());
            tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
            shot
        };
        let impact_dice = |s: &ShootResult| s.rolls.iter().find(|r| r.owner == "Charger").map(|r| r.count).unwrap_or(-1);
        let (exact, old) = (charge(false, true), charge(false, false));
        assert_eq!((exact.rolls[0].owner.as_str(), exact.unported.is_empty()), ("Hero", true), "{:?}", exact.unported);
        assert_eq!((old.rolls[0].owner.as_str(), old.unported.contains(&"counter_strikes_first")), ("Charger", true));
        assert_eq!(impact_dice(&old) - impact_dice(&exact), 1, "the hero's one Counter model cuts one Impact die");
        assert!(!charge(true, false).unported.contains(&"counter_strikes_first"), "a charger's own Counter is no gap");
    }

