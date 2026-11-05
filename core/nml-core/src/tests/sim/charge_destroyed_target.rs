use super::*;

    /// AI-G4 round 2, row G4-H7 (rules epoch 73). The table's cast leg can destroy the charge target before the
    /// charge lands; the table then logs "the charge falls short" and moves and rolls nothing. The core was handed
    /// the same state (the target with no model, no joined hero) and still carried out the charge move to the
    /// recorded `dest`: on the recorded aof_1000_net_026 act 30 that move crossed dangerous terrain and drew the
    /// charger's own six-dice test. From `EPOCH_73_V36` a charge on a unit with no living model, host and joined
    /// heroes, resolves nothing (no move, so no test and no fight); below it the old leg stays byte-identical.
    ///
    /// One charger "a" (3 models, one melee weapon) and its hero, against the target host "b" at 2.5" with its
    /// hero "bh" - the charge fixtures' distance (buff_consumption_bridge.rs).
    fn charge_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let p = st.profiles.list[0].clone();
        st.profiles = Rc::new(Profiles { list: vec![p; 4], index: HashMap::new() });
        let r = &*st.roster;
        st.roster = Rc::new(Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.positions = vec![
            vec![[0.0, 0.0, 0.0], [0.02 * IN2M, 0.0, 0.0], [0.04 * IN2M, 0.0, 0.0]],
            vec![],
            vec![[2.5 * IN2M, 0.0, 0.0]],
            vec![[2.52 * IN2M, 0.0, 0.0]],
        ];
        st.radii = Rc::new(vec![vec![IN2M; 3], vec![], vec![IN2M], vec![IN2M]]);
        st.wounds = vec![vec![1; 3], vec![], vec![1], vec![1]];
        st.alive = vec![3, 0, 1, 1];
        st.attached = Rc::new(vec![vec![], vec![], vec![3], vec![]]);
        st.attached_to = Rc::new(vec![None, None, None, Some(2)]);
        let mut a = UnitStatic { name: "a".into(), model_count: 3, wounds_max: vec![1; 3], ..Default::default() };
        a.ctx = Ctx { quality: 4, defense: 4, tough: 1, models: 3, ..Default::default() };
        a.melee = vec![ShootProfile { name: "Blade".into(), attacks: 2, count: 1, range: 0, ..Default::default() }];
        let mut b = UnitStatic { name: "b".into(), model_count: 1, wounds_max: vec![1], ..Default::default() };
        b.ctx = Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() };
        let statics = vec![
            a,
            UnitStatic { name: "ah".into(), ..Default::default() },
            b,
            UnitStatic { name: "bh".into(), model_count: 1, wounds_max: vec![1], ..Default::default() },
        ];
        (st, statics)
    }

    /// One CHARGE on the tray path at `rules_epoch` with a recorded landing 2" along the line: where the charger
    /// stands afterwards and how many dice the activation drew.
    fn charge(st: &State, statics: &[UnitStatic], rules_epoch: u32) -> (Vec<[f64; 3]>, usize) {
        let action = Action {
            kind: CHARGE, unit: "a".into(), dest: Some([2.0 * IN2M, 0.0, 0.0]), shoot: None, charge: Some("b".into()),
            patient: false, split: None, traced: None, teleport: None,
        };
        let seams = Seams { rules_epoch, hero_attach: true, ..Seams::default() };
        let (next, shot) = resolve_stochastic_tray_on_board(
            statics, st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut Tray::seeded(2),
        )
        .unwrap();
        (next.positions[0].clone(), shot.rolls.len())
    }

    fn destroy(st: &mut State, u: usize) {
        st.alive[u] = 0;
        st.positions[u] = vec![];
        st.wounds[u] = vec![];
        Rc::make_mut(&mut st.radii)[u] = vec![];
    }

    /// RED: the host and its hero are gone, so there is nothing to charge - the charger stays where it stood and
    /// draws nothing. The guard-off mutant is the epoch below 73: the old leg walks the charger to the landing.
    #[test]
    fn a_charge_on_a_unit_with_no_living_model_resolves_nothing() {
        let (mut st, statics) = charge_line();
        destroy(&mut st, 2);
        destroy(&mut st, 3);
        let v36 = crate::acts::EPOCH_73_V36;
        let (stays, dice) = charge(&st, &statics, v36);
        assert_eq!((stays, dice), (st.positions[0].clone(), 0), "the charge moved or rolled against a destroyed unit");
        let (walks, _) = charge(&st, &statics, v36 - 1);
        assert_ne!(walks, st.positions[0], "below epoch 73 the old leg must stay byte-identical (it moves)");
    }

    /// The guard reads HOST AND HEROES: a dead host with a living joined hero is still a target, so the charge goes on.
    #[test]
    fn a_dead_host_with_a_living_joined_hero_is_still_charged() {
        let (mut st, statics) = charge_line();
        destroy(&mut st, 2);
        let (walks, _) = charge(&st, &statics, crate::acts::EPOCH_73_V36);
        assert_ne!(walks, st.positions[0], "a unit with a living hero was skipped");
    }

    /// And the ordinary case stays what it was: a living target is charged at 73.
    #[test]
    fn a_living_target_is_charged_at_epoch_73() {
        let (st, statics) = charge_line();
        let (walks, _) = charge(&st, &statics, crate::acts::EPOCH_73_V36);
        assert_ne!(walks, st.positions[0]);
    }
