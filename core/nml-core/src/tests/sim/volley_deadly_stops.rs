use super::*;

    // ---- Volley Deadly (gate 12, Eternal Artillery -> Ancient Wraith): the wounds left once the chain is dead roll no ignore dice ----

    /// A Deadly(3) gun with two unsaved wounds at ONE Tough(3) model with a 6+ Regeneration: the first wound's three ignore dice
    /// and its landing kill the model, so the table (`_solo_land_deadly_wounds`: empty pick, break) rolls no dice for the second.
    /// The volley twin of `melee_deadly_stops`. Returns the 3-dice ignore rolls (6+) the volley drew at `epoch`.
    fn ignore_rolls(epoch: u32) -> usize {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(crate::state::Roster {
            keys: r.keys.clone(),
            index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
            profile: vec![0, 1, 2, 3],
        });
        st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
        st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![], vec![[5.0 * IN2M, 0.0, 0.0]], vec![]];
        st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M], vec![]]);
        st.wounds = vec![vec![1], vec![], vec![3], vec![]];
        st.alive = vec![1, 0, 1, 0];
        let mut a = UnitStatic { name: "a".into(), model_count: 1, wounds_max: vec![1], ..Default::default() };
        (a.ctx.quality, a.ctx.defense, a.ctx.rules_epoch) = (2, 4, epoch);
        a.shoot = vec![ShootProfile { name: "Cannon".into(), attacks: 2, count: 1, range: 24, deadly: 3, ..Default::default() }];
        let mut b = UnitStatic { name: "b".into(), model_count: 1, wounds_max: vec![3], ..Default::default() };
        let c = &mut b.ctx;
        (c.defense, c.tough, c.rules_epoch, c.regeneration, c.regen_target, c.playtest_rules) = (6, 3, epoch, true, 6, true);
        let statics = vec![a, UnitStatic { name: "ah".into(), ..Default::default() }, b, UnitStatic { name: "bh".into(), ..Default::default() }];
        let action = Action { kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None, patient: false, split: None,
            traced: None, teleport: None };
        let mut faces = vec![vec![6, 6], vec![1, 1], vec![1, 1, 1]];
        faces.extend((0..24).map(|_| vec![1u8; 24]));
        let mut tray = Tray::supplied(faces);
        let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
        let (next, shot) = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut tray)
            .unwrap();
        assert_eq!(next.alive[2], 0, "the Deadly wound killed the model: {:?}", shot.rolls);
        shot.rolls.iter().filter(|r| r.target == 6 && r.count == 3).count()
    }

    /// RED at the epoch: the core threw the second wound's three dice as well (2 rolls against the table's 1). Below it nothing moves.
    #[test]
    fn a_dead_target_gets_no_more_ignore_dice_from_a_volleys_deadly_wounds() {
        assert_eq!(ignore_rolls(crate::acts::EPOCH_95_PARITY_BATCH), 1, "95: the second wound is dropped, no dice");
        assert_eq!(ignore_rolls(crate::acts::EPOCH_95_PARITY_BATCH - 1), 2, "below the epoch the old fold rolls both wounds' dice");
    }
