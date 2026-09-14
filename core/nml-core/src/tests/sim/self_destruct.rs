    use super::*;

    // -------- block C4: Self-Destruct, the SURVIVAL half (EPOCH_41) ----------

    /// The survival-half fixture, unarmed on BOTH sides so the melee deals no
    /// wounds at all: unit 0 "Charger" and unit 1 "Bomb", 3 models each, no
    /// weapons. Bomb carries Self-Destruct(2) through the gf alien_hives
    /// registry row and is built with `UnitStatic::build`, so the rating rides
    /// the registry stamp exactly like the death half's own read
    /// (unit.rs `death_hits_per_kill`).
    fn suicide_duel() -> (State, Vec<UnitStatic>) {
        let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
        let bomb_profile: Profile = serde_json::from_str(
            r#"{"unit_id": "sd", "name": "Bomb", "special_rules": ["Self-Destruct(2)"],
                "game_system": "gf", "faction_folder": "alien_hives"}"#,
        )
        .unwrap();
        let mut reg = crate::rules::Registries::new(&repo_root());
        let mut bomb = UnitStatic::build(&mut reg, &bomb_profile);
        bomb.melee = vec![];
        bomb.model_count = 3;
        bomb.wounds_max = vec![1, 1, 1];
        bomb.ctx.quality = 4;
        bomb.ctx.defense = 4;
        bomb.ctx.tough = 1;
        bomb.ctx.models = 3;
        let striker = UnitStatic {
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 3, ..Default::default() },
            name: "Charger".into(),
            model_count: 3,
            wounds_max: vec![1, 1, 1],
            ..Default::default()
        };
        let statics = vec![striker, bomb];
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "b".into()],
            index: HashMap::new(),
            profile: vec![0, 1],
        });
        st.profiles = Rc::new(Profiles { list: vec![profile, bomb_profile], index: HashMap::new() });
        st.player = vec![0, 1];
        st.alive = vec![3, 3];
        st.attached = Rc::new(vec![vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None]);
        st.positions[0] = vec![[0.0, 0.0, 0.0], [0.8, 0.0, 0.0], [1.2, 0.0, 0.0]];
        st.wounds[0] = vec![1, 1, 1];
        st.radii[0] = vec![IN2M, IN2M, IN2M];
        st.positions[1] = vec![[2.0, 0.0, 0.0], [3.0, 0.0, 0.0], [4.0, 0.0, 0.0]];
        st.wounds[1] = vec![1, 1, 1];
        st.radii[1] = vec![IN2M, IN2M, IN2M];
        (st, statics)
    }

    /// (a) NEW leg, `EPOCH_41_SELF_DESTRUCT_SURVIVORS`: a 3-model
    /// Self-Destruct(2) unit that survives a melee untouched is REMOVED —
    /// "it is immediately killed", every surviving model detonates with no
    /// saves (main.gd:17363) — and the enemy takes 6 hits (3 surviving models
    /// x rating 2, main.gd:17357-17358), saved at the enemy's own melee
    /// Defense 4+ with AP 0. The table runs the half after both sides have
    /// finished attacking and BEFORE the melee result / morale test
    /// (main.gd:8431-8433), so the detonation carries no tally credit either.
    #[test]
    fn a_surviving_self_destruct_unit_detonates_at_epoch_41() {
        let (mut st, statics) = suicide_duel();
        let seams = Seams {
            rules_epoch: crate::acts::EPOCH_41_SELF_DESTRUCT_SURVIVORS,
            ..Default::default()
        };
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0);
        assert_eq!(st.alive[1], 0, "every surviving carrier is removed — the unit detonated");
        let lash = shot.rolls.last().expect("the detonation save batch");
        assert_eq!(
            (lash.kind, lash.count, lash.owner.as_str()),
            ("defense", 6, "Charger"),
            "the enemy saves 6 hits at its own Defense, AP 0"
        );
        assert_eq!(lash.target, 4, "the enemy's own Defense 4+, AP 0");
        assert_eq!(
            shot.log.last().map(String::as_str),
            Some("Self-Destruct: 3 surviving models detonate, 6 hits to Charger"),
            "the rules-must-log line"
        );
    }

    /// (b) OLD leg, the epoch immediately below the bump (40, pinned by its
    /// frozen constant, re-pointed from the pre-rebase 38 pin per the epoch
    /// rules): the tray replays the death-half-only reading — the untouched
    /// survivors stay on the board, nothing detonates, the enemy never rolls.
    /// RED on the new leg is the defect: in a core-driven fight a surviving
    /// Self-Destruct model neither detonates nor dies.
    #[test]
    fn at_epoch_40_a_surviving_self_destruct_unit_stays_on_the_board() {
        let (mut st, statics) = suicide_duel();
        let seams = Seams {
            rules_epoch: crate::acts::EPOCH_40_STEADFAST_ROLL,
            ..Default::default()
        };
        let mut tray = Tray::seeded(2);
        let mut shot = ShootResult::default();
        tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0);
        assert_eq!(st.alive[1], 3, "no survival half below the gate — the survivors stay");
        assert!(shot.log.iter().all(|l| !l.contains("detonate")), "nothing logged");
        assert!(shot.rolls.is_empty(), "the unarmed melee rolls nothing at all");
    }
