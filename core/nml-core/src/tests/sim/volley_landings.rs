use super::*;

    // ---- One-core P3 step 7: a plain volley records its landing at its checkpoint ----

    /// `four_unit_line` with "a" firing 4 shots at Quality 2+ into "b": two Tough(3) models.
    fn volley_line() -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        let index = r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
        st.roster = Rc::new(Roster { keys: r.keys.clone(), index, profile: vec![0, 1, 2, 3] });
        st.positions[2] = vec![[12.0 * IN2M, 0.0, 0.0], [12.0 * IN2M, 0.0, 2.5 * IN2M]];
        (st.wounds[2], st.alive[2]) = (vec![3, 3], 2);
        Rc::make_mut(&mut st.radii)[2] = vec![IN2M; 2];
        let mut a = UnitStatic { name: "a".into(), model_count: 1, ..Default::default() };
        a.ctx.quality = 2;
        a.shoot = vec![ShootProfile { name: "rifle".into(), attacks: 4, count: 1, range: 24, ..Default::default() }];
        let mut b = UnitStatic { name: "b".into(), model_count: 2, wounds_max: vec![3, 3], ..Default::default() };
        (b.ctx.defense, b.ctx.tough) = (4, 3);
        let hero = |n: &str| UnitStatic { name: n.into(), ..Default::default() };
        (st, vec![a, hero("ah"), b, hero("bh")])
    }

    /// A supplied volley that kills one Tough(3) model and wounds the other records its landing on
    /// "b" BEFORE the morale test it triggers (RED: move `tray.land` behind the morale test and the
    /// morale roll's checkpoint no longer holds it).
    #[test]
    fn a_supplied_volley_records_its_landing_before_the_morale_roll() {
        let (st, statics) = volley_line();
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let mut tray = Tray::supplied(vec![vec![6; 4], vec![1; 4]]); // 4 hits, 4 failed saves; morale starves
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        let (after, shot) = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams,
            &mut GodotRng::new(0), &mut tray).unwrap();
        let (m, _) = tray.feed().and_then(|f| f.starved_at).expect("the morale test draws after the volley");
        assert_eq!((m, shot.rolls[m].owner.as_str(), shot.rolls[m].count), (2, "b", 1), "fixture: roll 2 is b's morale die: {:?}", shot.rolls);
        let all = tray.all_landings();
        let models: Vec<_> = all.iter().flat_map(|l| &l.models).collect();
        // (a) one `dead` entry per model the volley removed.
        assert_eq!(models.iter().filter(|m| m.dead).count() as i64, st.alive[2] - after.alive[2], "{all:?}");
        // (b) the wounded Tough(3) survivor's `wounds_left` is its wounds after the volley.
        let hurt = models.iter().find(|m| !m.dead).expect("a wounded survivor");
        let j = after.positions[2].iter().position(|p| *p == hurt.at).expect("a survivor keeps its position");
        assert!((1..=2).contains(&hurt.wounds_left), "{all:?}");
        assert_eq!(hurt.wounds_left, after.wounds[2][j], "{all:?} vs {:?}", after.wounds[2]);
        // (c) the morale roll's checkpoint already holds the volley's landing.
        assert!(tray.landings_upto(m).iter().any(|l| l.unit == 2), "{:?}", tray.all_landings());
    }
