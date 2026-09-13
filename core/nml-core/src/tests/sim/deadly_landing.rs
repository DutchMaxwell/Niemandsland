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

    /// One HOLD+shoot activation on the tray path (the `run_shoot` shape).
    fn run_shoot(st: &State, statics: &[UnitStatic], seed: i64) -> (State, ShootResult) {
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
        let seams = Seams { rules_epoch: 7, ..Seams::default() };
        resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray)
            .unwrap()
    }

    /// The audit board on the tray. Seed 2 draws [5, 4] on the attack roll
    /// (Quality 2+ -> 2 hits) and [1, 3] on the save batch (target 6 -> both
    /// fail): exactly 2 unsaved wounds into the Deadly(3) weapon.
    #[test]
    fn deadly_wounds_do_not_carry_onto_the_next_model() {
        let (st, statics) = deadly_line();
        let (next, shot) = run_shoot(&st, &statics, 2);
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