use super::*;

    // ---- DEAD_PARAMS recount 2026-09-15, row `Immobile` (gf, param
    //      `hold_only: true`, proof_kind "none"): the read keys the exact
    //      name (`menu.rs::forces_hold`, trimmed prefix) and binds at the
    //      ACTION MENU — the carrier's menu ends after its holds, so no
    //      playout can ever imagine the unit moving (menu.rs:737). -------

    /// The carrier "a" (single model, one blade, no gun) 8" from an enemy
    /// "b", with an objective marker 8" up +x: the menu a ground unit fills
    /// with RUSH and CHARGE candidates. The rule under test rides the
    /// PROFILE slot the menu read consults.
    fn hold_line(immobile: bool) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        st.roster = Rc::new(Roster {
            keys: vec!["a".into(), "ah".into(), "b".into(), "bh".into()],
            index: ["a", "ah", "b", "bh"]
                .iter()
                .enumerate()
                .map(|(i, k)| (k.to_string(), i))
                .collect(),
            profile: vec![0, 1, 2, 3],
        });
        let mut carrier = st.profiles.list[0].clone();
        if immobile {
            carrier.special_rules = vec!["Immobile".into()];
        }
        let base = st.profiles.list[0].clone();
        st.profiles = Rc::new(Profiles {
            list: vec![carrier, base.clone(), base.clone(), base],
            index: HashMap::new(),
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0]],
            vec![],
            vec![[8.0 * IN2M, 0.0, 0.0]],
            vec![],
        ];
        st.wounds = vec![vec![1], vec![], vec![1], vec![]];
        st.radii = vec![vec![IN2M], vec![], vec![IN2M], vec![]];
        st.alive = vec![1, 0, 1, 0];
        st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, None]);
        st.objectives =
            vec![crate::state::Objective { pos: [8.0 * IN2M, 0.0, 0.0], owner: 1 }];
        let carrier_static = UnitStatic {
            name: "a".into(),
            model_count: 1,
            wounds_max: vec![1],
            melee: vec![ShootProfile {
                name: "Blade".into(),
                attacks: 2,
                count: 1,
                range: 0,
                ..Default::default()
            }],
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
            ..Default::default()
        };
        let foe = UnitStatic {
            name: "b".into(),
            model_count: 1,
            wounds_max: vec![1],
            ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
            ..Default::default()
        };
        (
            st,
            vec![
                carrier_static,
                UnitStatic { name: "ah".into(), ..Default::default() },
                foe,
                UnitStatic { name: "bh".into(), ..Default::default() },
            ],
        )
    }

    /// hold_only: the carrier's menu ends after the holds — the objective
    /// and the chargeable enemy change nothing; the ground twin gets the
    /// move option on the very same board, so the pin is not vacuous.
    #[test]
    fn an_immobile_carriers_menu_never_offers_a_move() {
        let (st, statics) = hold_line(true);
        let menu = crate::menu::candidates(&st, &small_board(), &statics, 0);
        assert!(!menu.is_empty(), "setup: the menu is never empty");
        assert!(
            menu.iter().all(|c| c.kind == HOLD),
            "Immobile may only Hold — the menu offered: {:?}",
            menu.iter().map(|c| c.kind).collect::<Vec<_>>()
        );
        let (st2, statics2) = hold_line(false);
        let ground = crate::menu::candidates(&st2, &small_board(), &statics2, 0);
        assert!(
            ground.iter().any(|c| c.kind == RUSH),
            "the control: the ground twin gets the move option: {:?}",
            ground.iter().map(|c| c.kind).collect::<Vec<_>>()
        );
    }
