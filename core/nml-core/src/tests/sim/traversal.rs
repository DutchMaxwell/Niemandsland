use super::*;

    // ---- STANDALONE_SWEEP_C_2026-09-14, row `Traversal` (ledger
    //      proven_vs_read.tsv line 71, proof_kind "none"): the phase-through
    //      move band — the plain-move seam reads the rule BY NAME
    //      (`rules.iter().any(|r| r == "Traversal")`, mv/step.rs) and the
    //      plan then treats the other units' bases as pass-through: the discs
    //      bind only the resting place (`zones_rest_only`). -------

    /// A single-model mover "a" on a straight lane toward x=12", an enemy "b"
    /// parked ON the lane at x=5" (1"-radius bases): with Traversal the move
    /// may pass THROUGH b's base and land the full band on the lane; without
    /// it the same plan must detour or fall short.
    fn traversal_line(with_rule: bool) -> (State, Vec<UnitStatic>) {
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
        let mut carrier_profile: Profile = serde_json::from_str(
            r#"{"unit_id": "a", "name": "Phaser", "model_count": 1,
                "quality": 4, "defense": 4, "tough": 1, "weapons": []}"#,
        )
        .expect("the mover's state profile parses");
        if with_rule {
            carrier_profile.special_rules = vec!["Traversal".into()];
        }
        let target_profile: Profile =
            serde_json::from_str(r#"{"unit_id": "b", "name": "Blocker"}"#).expect("profile");
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
        let mover = UnitStatic {
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
            name: "Phaser".into(),
            model_count: 1,
            wounds_max: vec![1],
            ..Default::default()
        };
        let blocker = UnitStatic {
            ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
            name: "Blocker".into(),
            model_count: 1,
            wounds_max: vec![1],
            ..Default::default()
        };
        (st, vec![mover, blocker])
    }

    /// ON the lane: the full 12" band walked straight through the blocker.
    /// The epsilon is ~0.2" in METRES — tight enough that the detoured
    /// answer (x ~10.2", z ~-1") can never read as on-lane.
    fn on_lane(p: &[f64]) -> bool {
        (p[0] - 12.0 * IN2M).abs() < 0.005 && p[2].abs() < 0.005
    }

    /// THE READ: with the rule's exact name on the unit, the ADVANCE lands
    /// the full band ON the lane — straight through the live enemy base (the
    /// route-blocking spacing zones are emptied, rest-clear stays). The board
    /// is the real 6x4 `small_board`: a plain ADVANCE only routes through
    /// `plain_move` when the board is valid.
    #[test]
    fn traversal_phases_the_advance_straight_through_the_enemy_base() {
        let (st, statics) = traversal_line(true);
        let mut tray = Tray::seeded(3);
        let mut rng = crate::rng::GodotRng::new(0);
        let (next, _shot) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(12.0), &small_board(),
            Seams { movement: true, ..Seams::default() }, &mut rng, &mut tray,
        )
        .expect("the traversal advance resolves");
        assert!(
            on_lane(&next.positions[0][0]),
            "the phased advance lands the full band on the lane: {:?}",
            next.positions[0][0]
        );
    }

    /// The control: WITHOUT the rule the same move may not answer the full
    /// straight 12" lane through a live base — the plan detours or falls
    /// short (and an outright refusal is a legal non-phase shape too).
    #[test]
    fn without_traversal_the_same_advance_cannot_rest_on_the_lane_through_the_base() {
        let (st, statics) = traversal_line(false);
        let mut tray = Tray::seeded(3);
        let mut rng = crate::rng::GodotRng::new(0);
        if let Ok((next, _)) = resolve_stochastic_tray_on_board(
            &statics, &st, &advance_to(12.0), &small_board(),
            Seams { movement: true, ..Seams::default() }, &mut rng, &mut tray,
        ) {
            assert!(
                !on_lane(&next.positions[0][0]),
                "without Traversal the straight 12\" lane through a live base \
                 must not be the answer: {:?}",
                next.positions[0][0]
            );
        }
    }
