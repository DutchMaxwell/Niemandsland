use super::*;

    // -------------------------------------------- W2 S0: melee_reach="table" ---

    /// A 10-model line, one inch apart, striking a single enemy model planted
    /// at the head of the line: only the first three sit within the p.9 2"
    /// reach (+1" base contact = 3" centre-space, `combat::MELEE_REACH_IN`/
    /// `BASE_CONTACT_IN`). `melee_reach` OFF (the default) is unaffected —
    /// today's behaviour scales by the whole unit's `alive` count.
    #[test]
    fn melee_reach_table_scales_by_the_models_within_2in_of_the_enemy() {
        let blade = ShootProfile { name: "Blade".into(), attacks: 10, count: 1, range: 0, ..Default::default() };
        let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
        let statics = vec![
            UnitStatic {
                ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 10, ..Default::default() },
                name: "Line".into(),
                melee: vec![blade],
                model_count: 10,
                wounds_max: vec![1; 10],
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
        st.alive = vec![10, 1];
        st.attached = Rc::new(vec![vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None]);
        st.positions[0] = (1..=10).map(|i| [i as f64 * IN2M, 0.0, 0.0]).collect();
        st.wounds[0] = vec![1; 10];
        st.radii[0] = vec![IN2M; 10];
        st.positions[1] = vec![[0.0, 0.0, 0.0]];
        st.wounds[1] = vec![1];
        st.radii[1] = vec![IN2M];

        let all = melee_parts(&statics, &st, 0, 1, Seams::default());
        assert_eq!(all[0].1.attacks[0], 10, "melee_reach=all (default): every model strikes");

        let table = Seams { melee_reach: true, ..Seams::default() };
        let reached = melee_parts(&statics, &st, 0, 1, table);
        assert_eq!(reached[0].1.attacks[0], 3, "melee_reach=table: only the 3 models within 2\" strike");
    }

    /// Retaliate(2) against 3 wounds LANDED = the striker faces a 6-die save
    /// batch at its own Defense, AP 0; the wounds land on the striker, the
    /// credit is the UNSAVED count, and the caller hands it to the defender's
    /// tally (main.gd:6146-6171).
    #[test]
    fn retaliate_throws_two_hits_per_wound_landed_at_the_striker() {
        let (mut st, statics) = duel(2);
        let def_pool = wounds_left(&st, 1);
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        let (caused, credit) = strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        let landed = def_pool - wounds_left(&st, 1);
        assert_eq!(landed, 3, "fixture: seed 9 lands exactly 3 wounds (got {landed})");
        assert!(caused >= landed, "the tally is the PRE-Regeneration count");
        let lash = shot.rolls.last().expect("the lash-back save batch");
        assert_eq!((lash.kind, lash.count, lash.owner.as_str()), ("defense", 6, "Striker"));
        assert_eq!(lash.target, 4, "the striker's own Defense 4+, AP 0");
        assert_eq!(credit, lash.faces.iter().filter(|&&f| f < 4).count() as i64,
            "the credit is the unsaved count the caller gives the defender's tally");
        assert!(wounds_left(&st, 0) < 3, "the retaliation wounds LAND on the striker");
        assert_eq!(shot.log.last().map(String::as_str),
            Some("Retaliate: Target lashes back — 6 hits"), "the rules-must-log line");
    }

    /// The same strike WITHOUT the rule: no lash-back batch, no log line —
    /// the tray stands exactly where the phase's own draws left it.
    #[test]
    fn without_the_rule_no_extra_rolls_and_no_log() {
        let (mut st, statics) = duel(0);
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        let (_, credit) = strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        assert_eq!(credit, 0, "nothing to credit");
        assert!(shot.log.iter().all(|l| !l.contains("Retaliate")), "nothing logged");
        assert!(shot.rolls.iter().all(|r| !(r.kind == "defense" && r.owner == "Striker")),
            "the striker never rolls a save when the defender carries no Retaliate");
    }

    /// NON-CHAINING (main.gd:6155): the lash lands through `land_wounds`
    /// alone, never through another strike phase — a striker that ITSELF
    /// carries Retaliate(2) does not answer the defender's lash-back.
    #[test]
    fn retaliation_wounds_never_trigger_the_strikers_own_retaliate() {
        let (mut st, mut statics) = duel(2);
        statics[0].ctx.retaliate_hits_per_wound = 2;
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        strike_phase(&statics, &mut st, 0, 1, false, Seams::default(), &mut tray, &mut shot);
        let striker_saves = shot.rolls.iter().filter(|r| r.kind == "defense" && r.owner == "Striker").count();
        let defender_saves = shot.rolls.iter().filter(|r| r.kind == "defense" && r.owner == "Target").count();
        assert_eq!(striker_saves, 1, "exactly the defender's lash-back batch");
        assert_eq!(defender_saves, 1, "the strike's own save batch — no chained counter-lash");
    }
