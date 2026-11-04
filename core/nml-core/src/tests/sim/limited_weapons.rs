use super::*;

    // ------------------------------------------- GF v3.5.1: Limited weapons ---

    /// GF v3.5.1 weapon rule Limited — "may only be used once per game": the
    /// Limited Cannon fires alongside the plain Rifle in round 1, then draws
    /// no dice at all in round 2, while the Rifle keeps firing.
    #[test]
    fn a_limited_weapon_fires_once_then_draws_no_dice_the_next_round() {
        let (st, mut statics) = buff_line();
        statics[0].shoot = vec![ShootProfile { limited: true, ..gun("Cannon", 1, 24) }, gun("Rifle", 1, 24)];
        let (round1, shot1) = run_buff(&st, &statics, &buff_action(Some("b")), 11);
        assert_eq!(
            shot1.rolls.iter().filter(|r| r.kind == "attack").count(), 2,
            "round 1: Cannon and Rifle both fire"
        );
        assert!(round1.limited_used[0].iter().any(|n| n == "Cannon"));

        let (_, shot2) = run_buff(&round1, &statics, &buff_action(Some("b")), 12);
        assert_eq!(
            shot2.rolls.iter().filter(|r| r.kind == "attack").count(), 1,
            "round 2: the spent Cannon draws no dice, the Rifle still fires"
        );
    }

    // ----------------------------- G4-H-LIM: the table's ledger rides the act state ---

    /// One unit's recorded `ledger` block folded the way the reader folds it for every act.
    fn fold_spent(st: &mut State, unit: usize, rules_epoch: u32, json: &str) {
        let ledger: crate::io::PlainLedger = serde_json::from_str(json).expect("ledger");
        crate::io::fold_ledger(st, unit, &ledger, rules_epoch, st.alive[unit], false, -1);
    }

    fn cannon_and_rifle() -> Vec<ShootProfile> {
        vec![ShootProfile { limited: true, ..gun("Cannon", 1, 24) }, gun("Rifle", 1, 24)]
    }

    const SPENT_CANNON: &str = r#"{"limited_used":["Cannon"]}"#;

    /// The reader: `ledger.limited_used` lands in the core's ledger from `EPOCH_73_V36`; below it the
    /// ledger stays empty, byte for byte what every older recording replays.
    #[test]
    fn the_act_states_limited_ledger_is_read_from_epoch_73() {
        let (mut st, _) = buff_line();
        fold_spent(&mut st, 0, crate::acts::EPOCH_73_V36, SPENT_CANNON);
        assert_eq!(st.limited_used[0], vec!["Cannon".to_string()]);
        let (mut old, _) = buff_line();
        fold_spent(&mut old, 0, crate::acts::EPOCH_72_PLAYTEST_RULES, SPENT_CANNON);
        assert!(old.limited_used[0].is_empty(), "below 73 the key is not read");
    }

    /// `resolve`: a Limited weapon the act state's ledger names draws no dice, the Rifle still
    /// fires, and the log names the book rule.
    #[test]
    fn a_limited_weapon_in_the_ledger_is_skipped_by_resolve() {
        let (mut st, mut statics) = buff_line();
        statics[0].shoot = cannon_and_rifle();
        fold_spent(&mut st, 0, crate::acts::EPOCH_73_V36, SPENT_CANNON);
        let seams = Seams { rules_epoch: crate::acts::EPOCH_73_V36, ..Seams::default() };
        let mut tray = Tray::seeded(11);
        let mut rng = crate::rng::GodotRng::new(0);
        let terrain = crate::terrain::Terrain::default();
        let (_, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &buff_action(Some("b")), &terrain, seams, &mut rng, &mut tray,
        )
        .unwrap();
        assert_eq!(shot.rolls.iter().filter(|r| r.kind == "attack").count(), 1, "the Rifle only");
        assert!(
            shot.log.iter().any(|l| l.starts_with("Limited:") && l.contains("Cannon")),
            "the spent weapon is logged by its book rule: {:?}", shot.log
        );
    }

    /// The EV volley (`member_profiles_of`, the imagined shot the search prices): host alone and with a
    /// joined hero (the folded build) both price the Rifle and not the spent Cannon from epoch 73.
    #[test]
    fn a_limited_weapon_in_the_ledger_is_skipped_by_the_ev_volley() {
        let (mut st, mut statics) = hero_line();
        statics[0].shoot = cannon_and_rifle();
        fold_spent(&mut st, 0, crate::acts::EPOCH_73_V36, SPENT_CANNON);
        let price = |hero_attach: bool, rules_epoch: u32| {
            let seams = Seams { hero_attach, rules_epoch, ..Seams::default() };
            let mut sc = Scratch::default();
            member_profiles_of(&statics, &st, 0, false, 20.0, seams, &mut sc);
            kept(&statics, false, &sc)
        };
        let e73 = crate::acts::EPOCH_73_V36;
        assert_eq!(price(false, e73), vec!["Rifle".to_string()]);
        assert_eq!(price(true, e73), vec!["Rifle".to_string(), "Heavy Gun".into()]);
        let e72 = crate::acts::EPOCH_72_PLAYTEST_RULES;
        assert_eq!(price(false, e72), vec!["Cannon".to_string(), "Rifle".into()], "below 73 the spent Cannon is priced as fresh");
    }
