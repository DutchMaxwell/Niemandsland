use super::*;

    // ------------------- audit 2026-09-13 §2.1: Deadly lands PER MODEL ------

    // The audit board (analysis/RULE_FIDELITY_AUDIT_2026-09-13.md §2.1): a
    // 3-model Tough(3) unit with wounds remaining [3, 1, 1] takes 2 unsaved
    // wounds from a Deadly(3) weapon. The book (GF v3.5.1 p.14, `gf/_common.json`)
    // assigns each wound to one model, multiplies THERE, and the surplus does
    // not carry over; the table plays it that way
    // (`SoloController.apply_deadly_wounds`, solo_controller.gd:8333-8352):
    // 3 absorbed on the first model, 1 on the next — TWO models die, ONE
    // survives, still holding its objective. The core multiplied at the POOL
    // level (dice.rs save_batch `unsaved * mult` against the unit's printed
    // Tough) and let `land_wounds` spill the 6 onto every model — the unit was
    // wiped. This test pins the core's outcome to the table's.

    /// The audit board: attacker "a" (1 model, one Deadly(3) rifle, 2 attacks,
    /// Quality 2+, AP(2)) vs defender "b" (3 models, printed Tough(3), Defense
    /// 4) 5" apart on the plain line. State wounds [3, 1, 1]: the first model
    /// fresh, the other two each down to 1.
    fn deadly_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![],
            vec![[5.0 * IN2M, 0.0, 0.0], [5.02 * IN2M, 0.0, 0.0], [5.04 * IN2M, 0.0, 0.0]],
            vec![],
        ];
        st.radii = vec![vec![IN2M], vec![], vec![IN2M; 3], vec![]];
        st.wounds = vec![vec![1], vec![], vec![3, 1, 1], vec![]];
        st.alive = vec![1, 0, 3, 0];
        let mut a = UnitStatic { name: "a".into(), ..Default::default() };
        a.model_count = 1;
        a.wounds_max = vec![1];
        a.ctx.quality = 2;
        a.ctx.defense = 4;
        a.shoot = vec![ShootProfile {
            name: "Deadly rifle".into(),
            attacks: 2,
            count: 1,
            range: 24,
            ap: 2,
            deadly: 3,
            ..Default::default()
        }];
        let mut b = UnitStatic { name: "b".into(), ..Default::default() };
        b.model_count = 3;
        b.wounds_max = vec![3, 3, 3];
        b.ctx.defense = 4;
        b.ctx.tough = 3;
        (
            st,
            vec![
                a,
                UnitStatic { name: "ah".into(), ..Default::default() },
                b,
                UnitStatic { name: "bh".into(), ..Default::default() },
            ],
        )
    }

    /// One HOLD+shoot activation on the tray path (the `run_shoot` shape); the
    /// epoch picks the Deadly gate's leg (14 = per model, 13 = pooled legacy).
    fn run_shoot(st: &State, statics: &[UnitStatic], seed: i64, rules_epoch: u32) -> (State, ShootResult) {
        let action = Action {
            kind: HOLD,
            unit: "a".into(),
            dest: None,
            shoot: Some("b".into()),
            charge: None,
            patient: false,
            split: None,
            traced: None,
            teleport: None,
        };
        let terrain = Terrain::default();
        let mut tray = Tray::seeded(seed);
        let mut rng = GodotRng::new(0);
        let seams = Seams { rules_epoch, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
    }

    /// The audit board on the tray, at `EPOCH_14_DEADLY_LANDING`. Seed 2 draws
    /// [5, 4] on the attack roll (Quality 2+ -> 2 hits) and [1, 3] on the save
    /// batch (target 6 -> both fail): exactly 2 unsaved wounds into the
    /// Deadly(3) weapon.
    #[test]
    fn deadly_wounds_do_not_carry_onto_the_next_model() {
        let (st, statics) = deadly_line();
        let (next, shot) = run_shoot(&st, &statics, 2, 14);
        // The stream: one attack roll of 2 at Quality 2+, one save batch of 2
        // at Defense 4 + AP(2) = 6 — exactly the two draws, nothing pooled.
        let atk: Vec<_> = shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "a").collect();
        assert_eq!(
            (atk.len(), atk[0].count, atk[0].target),
            (1, 2, 2),
            "fixture: the volley draws 2 attack dice at 2+: {:?}",
            shot.rolls
        );
        let save: Vec<_> = shot.rolls.iter().filter(|r| r.kind == "defense").collect();
        assert_eq!(
            (save.len(), save[0].count, save[0].target),
            (1, 2, 6),
            "fixture: one save batch of 2 at 6+: {:?}",
            shot.rolls
        );
        // The tally is the RAW unsaved count (the table's shooting tally,
        // `total_caused += w`, main.gd:3318).
        assert_eq!(shot.caused, 2, "2 unsaved, the raw count: {:?}", shot.rolls);
        // THE DEFECT: the book and the table absorb 3 on the first model and 1
        // on the next — two models die, ONE survives. The pool multiply wiped
        // all three.
        assert_eq!(
            next.alive[2], 1,
            "the table leaves ONE model standing: alive {:?}, wounds {:?}",
            next.alive, next.wounds
        );
        assert_eq!(
            next.wounds[2], vec![1],
            "the survivor is the third model at its 1 remaining wound: {:?}",
            next.wounds
        );
        // Rules-must-log: the applied rule names itself, the table's own line
        // (main.gd:6778).
        assert!(
            shot.log.iter().any(|l| l.contains("Deadly(3): 2 unsaved ×3") && l.contains("no carry-over")),
            "the Deadly landing names itself: {:?}",
            shot.log
        );
    }

    /// THE OLD LEG, pinned (the gate discipline): the same board at epoch 13 —
    /// one below the gate — keeps the POOL multiply verbatim. The 2 unsaved
    /// become 6 pooled wounds and `land_wounds` spills them: the unit is wiped
    /// and the tally is the multiplied 6. Same seed, same stream — only the
    /// leg differs.
    #[test]
    fn at_epoch_13_the_pool_multiply_still_wipes_the_unit() {
        let (st, statics) = deadly_line();
        let (next, shot) = run_shoot(&st, &statics, 2, 13);
        assert_eq!(shot.caused, 6, "2 unsaved × Deadly(3), the pooled tally");
        assert_eq!(
            (shot.rolls[0].count, shot.rolls[1].count),
            (2, 2),
            "the stream is identical on both legs: {:?}",
            shot.rolls
        );
        assert_eq!(next.alive[2], 0, "the legacy leg wipes the unit: wounds {:?}", next.wounds);
        assert!(
            !shot.log.iter().any(|l| l.contains("no carry-over")),
            "the legacy leg has no Deadly landing line: {:?}",
            shot.log
        );
    }

    // --------------------- D17, EPOCH_67_MARKERS_BURSTS: host/hero + Tough --

    /// `land_deadly_wounds` called directly (it is `pub`, this module's own
    /// `use super::*`) — no attacker fixture needed, the algorithm is the unit
    /// under test. "a" (host): model 0 a FRESH Tough(1) body, model 1 a FRESH
    /// Tough(3) team member; "ah" (joined hero, `four_unit_line`'s own
    /// attachment): one Tough(1) model.
    fn deadly_chain() -> State {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions[0] = vec![[0.0, 0.0, 0.0], [0.02 * IN2M, 0.0, 0.0]];
        st.wounds[0] = vec![1, 3];
        st.radii[0] = vec![IN2M; 2];
        st.alive[0] = 2;
        st.positions[1] = vec![[2.0 * IN2M, 0.0, 0.0]];
        st.wounds[1] = vec![1];
        st.radii[1] = vec![IN2M];
        st.alive[1] = 1;
        st.profiles = Rc::new(Profiles {
            list: vec![
                Profile { wounds_max: vec![1, 3], model_count: 2, ..host_profile("a") },
                Profile { wounds_max: vec![1], model_count: 1, ..host_profile("ah") },
                Profile { wounds_max: vec![], model_count: 0, ..host_profile("b") },
                Profile { wounds_max: vec![], model_count: 0, ..host_profile("bh") },
            ],
            index: HashMap::new(),
        });
        st
    }

    fn host_profile(id: &str) -> Profile {
        Profile {
            unit_id: id.into(), name: id.into(), quality: 4, defense: 4, tough: 1,
            wounds_max: vec![], model_count: 1, weapons: vec![], special_rules: vec![],
            caster_value: 0, base_radius: 0.0, base_shape: String::new(), base_w_mm: 0.0,
            base_d_mm: 0.0, game_system: String::new(), faction_folder: String::new(),
            item_grants: vec![], attached_hero_rules: vec![], move_bands: MoveBands::default(),
        }
    }

    /// D17 (a) leg 1 — with NEITHER host model already wounded, a Deadly(3)
    /// wound falls to `land_wounds`'s own slot order (index 0 = the Tough(1)
    /// body), not the model with the most remaining wounds: the body dies
    /// instead of the fresh Tough(3) team member taking a 3-wound bite. Below
    /// the gate the OLD reading still picks the team (most remaining wounds).
    #[test]
    fn a_deadly_wound_lands_on_the_body_not_a_fresh_tough_team_member_from_epoch_67() {
        let mut st67 = deadly_chain();
        let s67 = Seams { rules_epoch: crate::acts::EPOCH_67_MARKERS_BURSTS, hero_attach: true, ..Seams::default() };
        let dealt = land_deadly_wounds(&mut st67, 0, 1, 3, s67);
        assert_eq!(dealt, 1, "capped at the body's own 1 remaining wound: {:?}", st67.wounds);
        assert_eq!(st67.wounds[0], vec![3], "the body died, the team member stands untouched: {:?}", st67.wounds);
        assert_eq!(st67.alive[0], 1);

        let mut st66 = deadly_chain();
        let s66 = Seams { rules_epoch: crate::acts::EPOCH_66_DISTANCE_TRUTH, hero_attach: true, ..Seams::default() };
        let dealt66 = land_deadly_wounds(&mut st66, 0, 1, 3, s66);
        assert_eq!(dealt66, 3, "below the gate: the OLD 'most remaining wounds' pick hits the team for all 3: {:?}", st66.wounds);
        assert_eq!(st66.wounds[0], vec![1], "the team died (3-3=0, removed), the body stands: {:?}", st66.wounds);
    }

    /// D17 (a) leg 2 — an ALREADY-WOUNDED Tough slot (here the team member, one
    /// wound already taken, current < max) is finished off before a FRESH slot
    /// even when the fresh one sits earlier in the array (the tie the old
    /// array-order pick would have resolved the other way); once the whole
    /// host chain is dead the leftover wound reaches the joined hero instead
    /// of being wasted (p.15 "heroes must be assigned wounds last").
    #[test]
    fn an_already_wounded_tough_slot_is_finished_first_then_the_leftover_reaches_the_hero() {
        let mut st = deadly_chain();
        st.wounds[0] = vec![1, 1]; // body still at its 1, the team already down to 1 of 3
        let s = Seams { rules_epoch: crate::acts::EPOCH_67_MARKERS_BURSTS, hero_attach: true, ..Seams::default() };

        // Wound 1: the DAMAGED team member (index 1), not the fresh-tied body at index 0.
        assert_eq!(land_deadly_wounds(&mut st, 0, 1, 1, s), 1);
        assert_eq!(st.wounds[0], vec![1], "the team died, only the body remains: {:?}", st.wounds);
        assert_eq!(st.alive[0], 1);

        // Wound 2: the body, the only host model left — the host chain is now wiped.
        assert_eq!(land_deadly_wounds(&mut st, 0, 1, 1, s), 1);
        assert_eq!(st.wounds[0], Vec::<i64>::new());
        assert_eq!(st.alive[0], 0, "the host is fully wiped: {:?}", st.wounds);
        assert_eq!(st.alive[1], 1, "the hero is untouched so far: {:?}", st.wounds);

        // Wound 3: nothing left in the host — the joined hero takes it (never wasted).
        assert_eq!(land_deadly_wounds(&mut st, 0, 1, 1, s), 1);
        assert_eq!(st.alive[1], 0, "the leftover wound reached the hero instead of being wasted");

        // Wound 4: the whole chain is dead now — wasted, not an error.
        assert_eq!(land_deadly_wounds(&mut st, 0, 1, 1, s), 0);
    }