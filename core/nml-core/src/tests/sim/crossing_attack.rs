use super::*;

use crate::rules::Registries;

    // ---- STANDALONE_SWEEP_A_2026-09-14, row `Crossing Attack` (ledger
    //      proven_vs_read.tsv line 10, proof_kind "none"): the move-triggered
    //      damage roll — `crossing_attack_of` reads the EXACT name off the
    //      unit's rule list (unit.rs) and `tray_crossing_attack` rolls X dice
    //      at the wound target on the executed move's trail (sim.rs). -------

    /// The checkout this crate lives in — mirrors the dice tests' helper.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    /// The carrier's REAL profile through the import's own stamp: one model
    /// carrying "Crossing Attack(2)" (gf/high_elf_fleets fields the name with
    /// `{rating: "X", wound_target: 6}`) and no weapons, so the crossing roll
    /// is the only dice this activation can produce.
    fn crossing_carrier() -> UnitStatic {
        let p: Profile = serde_json::from_str(
            r#"{"unit_id": "a", "name": "Crosser", "model_count": 1,
                "quality": 4, "defense": 4, "tough": 1,
                "game_system": "gf", "faction_folder": "high_elf_fleets",
                "special_rules": ["Crossing Attack(2)"], "weapons": []}"#,
        )
        .expect("the crossing carrier's profile parses");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, crate::acts::CURRENT_RULES_EPOCH)
    }

    /// A single-model carrier "a" (1"-radius base) facing a single-model enemy
    /// "b" parked ON the advance lane at x=5": a straight 12" advance from
    /// x=0 to x=12" crosses b's base — the trigger geometry of the table's
    /// post-move crossing roll (`_solo_apply_crossing_attack` main.gd:17086).
    fn crossing_line() -> (State, Vec<UnitStatic>) {
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
            r#"{"unit_id": "a", "name": "Crosser", "model_count": 1,
                "quality": 4, "defense": 4, "tough": 1,
                "game_system": "gf", "faction_folder": "high_elf_fleets",
                "special_rules": ["Crossing Attack(2)"], "weapons": []}"#,
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
        let carrier = crossing_carrier();
        let target = UnitStatic {
            ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
            name: "Target".into(),
            model_count: 1,
            wounds_max: vec![1],
            ..Default::default()
        };
        (st, vec![carrier, target])
    }

    /// THE STAMP: the exact name "Crossing Attack" is what produces the spec —
    /// X = the rule's OWN rating ("Crossing Attack(2)" -> 2), each 6+ one
    /// wound (`wound_target` 6, the registry's own param).
    #[test]
    fn crossing_attack_stamps_its_rating_as_the_dice_count_at_the_current_epoch() {
        let carrier = crossing_carrier();
        let spec = carrier
            .crossing_attack
            .as_ref()
            .expect("the exact name \"Crossing Attack\" stamps the spec");
        assert_eq!(
            (spec.dice, spec.wound_target),
            (2, 6),
            "Crossing Attack(2): X = the rule's own rating 2, wounds on a 6+"
        );
    }

    /// THE ROLL: the executed advance's trail crosses the enemy base, so the
    /// tray draws exactly the rating's dice at the wound target, and the
    /// report names the rule (rules-must-log, sim.rs's own push).
    #[test]
    fn crossing_attack_rolls_its_rating_at_the_wound_target_and_logs_itself() {
        let (st, statics) = crossing_line();
        let mut tray = Tray::seeded(1);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(12.0), &crate::terrain::Terrain::default(),
            Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Seams::default() },
            &mut rng, &mut tray,
        )
        .unwrap();
        let crossing: Vec<&crate::dice::Roll> =
            shot.rolls.iter().filter(|r| r.owner == "Crosser").collect();
        assert_eq!(
            crossing.len(),
            1,
            "one crossing roll for one crossed enemy: {:?}",
            shot.rolls
        );
        assert_eq!(
            (crossing[0].count, crossing[0].target),
            (2, 6),
            "X dice (the rating) at the 6+ wound target: {:?}",
            crossing[0]
        );
        assert!(
            shot.log.iter().any(|l| l.contains("Crossing Attack") && l.contains("Crosser")),
            "rules-must-log: the line names the rule and its bearer: {:?}",
            shot.log
        );
    }

    /// The epoch gate (the FROZEN `EPOCH_7_TABLE_RULES`): a record below 7
    /// keeps the pre-port silence — the corpus replay reading.
    #[test]
    fn below_epoch_7_the_crossing_attack_stays_silent() {
        let (st, statics) = crossing_line();
        let mut tray = Tray::seeded(1);
        let mut rng = crate::rng::GodotRng::new(0);
        let (_next, shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(12.0), &crate::terrain::Terrain::default(),
            Seams { rules_epoch: crate::acts::EPOCH_7_TABLE_RULES - 1, ..Seams::default() },
            &mut rng, &mut tray,
        )
        .unwrap();
        assert!(
            shot.rolls.is_empty(),
            "no crossing roll below the gate: {:?}",
            shot.rolls
        );
        assert!(shot.log.iter().all(|l| !l.contains("Crossing Attack")));
    }
