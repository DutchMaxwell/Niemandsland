use super::*;

use crate::rules::Registries;

    // ---- STANDALONE_SWEEP_A_2026-09-14, row `Strafing`, TABLE-ONLY: the
    //      once-per-activation move-through attack exists at the table, not in
    //      the core ----------------------------------------------------------

    /// The checkout this crate lives in — mirrors the dice tests' helper.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// The strafe carrier's REAL profile, through the import's own stamp: one
    /// normal 2-attack gun and ONE 4-attack Strafing autocannon (range 24").
    /// `AiShooting.strafing_profiles` (ai_shooting.gd:30-39) is that weapon's
    /// ONLY firing path — `profiles_in_range` excludes it from every normal
    /// volley ("This weapon may only be used in this way").
    fn strafe_carrier() -> UnitStatic {
        let p: Profile = serde_json::from_str(
            r#"{"unit_id": "a", "name": "Strafer", "model_count": 1,
                "quality": 4, "defense": 4, "tough": 1,
                "weapons": [
                    {"name": "Lash Cannon", "range": 24.0, "attacks": 2, "count": 1, "rules": []},
                    {"name": "Twin Autocannon", "range": 24.0, "attacks": 4, "count": 1,
                     "rules": ["Strafing"]}
                ]}"#,
        )
        .expect("the strafe carrier's profile parses");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, 32)
    }

    /// A strafing aircraft "a" (single model, Quality 4+) facing a single-model
    /// enemy "b" parked ON the advance lane: a straight 12" advance from x=0
    /// to x=12" flies straight over b's 1"-radius base at x=5" — the table's
    /// move-through trigger fires on exactly such an executed trail
    /// (`_solo_apply_strafing` main.gd:2964-3007, trails vs
    /// `SoloController.trails_cross_unit_bases`).
    fn strafe_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "b".into()],
            index: ["a".to_string(), "b".to_string()]
                .iter()
                .enumerate()
                .map(|(i, k)| (k.clone(), i))
                .collect(),
            profile: vec![0, 1],
        });
        let carrier_profile: Profile = serde_json::from_str(
            r#"{"unit_id": "a", "name": "Strafer", "model_count": 1,
                "quality": 4, "defense": 4, "tough": 1,
                "weapons": [
                    {"name": "Lash Cannon", "range": 24.0, "attacks": 2, "count": 1, "rules": []},
                    {"name": "Twin Autocannon", "range": 24.0, "attacks": 4, "count": 1,
                     "rules": ["Strafing"]}
                ]}"#,
        )
        .expect("the carrier's state profile parses");
        let target_profile: Profile =
            serde_json::from_str(r#"{"unit_id": "b", "name": "Target"}"#).expect("profile");
        st.profiles = Rc::new(Profiles {
            list: vec![carrier_profile, target_profile],
            index: HashMap::new(),
        });
        st.player = vec![0, 1];
        st.alive = vec![1, 1];
        st.attached = Rc::new(vec![vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None]);
        st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[5.0 * IN2M, 0.0, 0.0]]];
        st.wounds = vec![vec![1], vec![1]];
        st.radii = vec![vec![IN2M], vec![IN2M]];
        st.bands[0].advance = 12.0;
        let carrier = strafe_carrier();
        let target = UnitStatic {
            ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
            name: "Target".into(),
            model_count: 1,
            wounds_max: vec![1],
            ..Default::default()
        };
        (st, vec![carrier, target])
    }

    /// RED — the NEW leg: a Strafing carrier whose advance path crosses an
    /// enemy unit must resolve ONE shooting exchange with that weapon at epoch
    /// 32 (main.gd:1092-1097 -> `_solo_apply_strafing` main.gd:2964-3007,
    /// resolved "as if shooting" through the shared volley resolver, once per
    /// activation). In the core the aircraft used to fly past in silence: the
    /// flag was stamped (unit.rs:1130), the fold marked (dice.rs:945), and
    /// nothing ever fired.
    #[test]
    fn a_strafing_carriers_advance_over_an_enemy_resolves_one_exchange_at_32() {
        let (st, statics) = strafe_line();
        let mut tray = Tray::seeded(1);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(12.0), &crate::terrain::Terrain::default(),
            Seams { rules_epoch: 32, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        let strafe_rolls: Vec<&crate::dice::Roll> =
            shot.rolls.iter().filter(|r| r.owner == "Strafer").collect();
        assert!(
            !strafe_rolls.is_empty(),
            "the Strafing carrier's advance over the enemy produced no shooting exchange at all: {:?}",
            shot.rolls
        );
        assert!(
            shot.log.iter().any(|l| l.contains("Strafing")),
            "rules-must-log: the strafe names itself, one line per exchange: {:?}",
            shot.log
        );
    }

    /// The OLD leg, pinned at the epoch immediately below the bump (30 today,
    /// the frozen constant): a record stamped before the port replays
    /// unchanged — the Strafing weapon stays silent on the move-through, byte
    /// for byte what every recorded game played like.
    #[test]
    fn below_epoch_32_the_strafing_weapon_stays_silent_on_the_move_through() {
        let (st, statics) = strafe_line();
        let mut tray = Tray::seeded(1);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(12.0), &crate::terrain::Terrain::default(),
            Seams { rules_epoch: crate::acts::EPOCH_30_SCRAPPER_BOOST, ..Seams::default() },
            &mut rng, &mut tray,
        )
        .unwrap();
        assert!(
            shot.rolls.iter().all(|r| r.owner != "Strafer"),
            "no exchange below the gate: {:?}",
            shot.rolls
        );
        assert!(
            shot.log.iter().all(|l| !l.contains("Strafing")),
            "no strafe line below the gate: {:?}",
            shot.log
        );
    }

    /// `weapon_only` — "This weapon may only be used in this way": a normal
    /// (recorded-key) volley fires the carrier's plain gun and NEVER the
    /// Strafing weapon. The import's own filter is
    /// `AiShooting.profiles_in_range` (ai_shooting.gd:20-21) mirrored at
    /// unit.rs:4395-4397, so this guards the stamp against ever growing the
    /// normal set back.
    #[test]
    fn the_strafing_weapon_never_fires_in_a_normal_volley() {
        let (st, statics) = strafe_line();
        let mut hold = advance_to(12.0);
        hold.kind = HOLD;
        hold.dest = None;
        hold.shoot = Some("b".into());
        let mut tray = Tray::seeded(1);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &hold, &crate::terrain::Terrain::default(),
            Seams { rules_epoch: 32, ..Seams::default() }, &mut rng, &mut tray,
        )
        .unwrap();
        let volleys = shot.rolls.iter().filter(|r| r.owner == "Strafer").count();
        assert_eq!(
            volleys, 1,
            "the normal volley fires exactly the one legal gun, never the Strafing weapon: {:?}",
            shot.rolls
        );
    }
