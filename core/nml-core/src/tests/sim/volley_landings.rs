use super::*;

    // ---- One-core P3 step 7: a plain volley records its landing at its checkpoint ----

    /// `four_unit_line` with "a" firing 4 shots at Quality 2+ into "b": two Tough(3) models.
    pub(crate) fn volley_line() -> (State, Vec<UnitStatic>) {
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
        // (d) step 27: the core said each landing's loss line, so the table's removal funnel must not.
        assert!(all.iter().all(|l| l.loss_line), "{all:?}");
        // (e) P4.0-1: each model names its capture slot - the index of its start position in "b"'s captured list.
        assert!(models.iter().all(|m| st.positions[2][m.slot] == m.at), "{all:?} vs {:?}", st.positions[2]);
    }

    /// P4.0-1: a model's slot is its index at the CAPTURE, not in the list a later landing sees. "b" has four models; one
    /// landing removes model 1 and wounds model 3, then a second on the same tray removes the model now standing second
    /// in the shrunken list, which is capture slot 2. RED: number a landing's models by their snapshot index (drop `gone`)
    /// and the second landing names slot 1, the model the first landing already killed; count a wounded model among the
    /// dead slots and it names slot 3's neighbour wrongly.
    #[test]
    fn a_later_landing_names_capture_slots_not_the_shrunken_list() {
        let (mut st, _) = volley_line();
        st.positions[2] = (0..4).map(|i| [12.0 * IN2M, 0.0, 2.5 * i as f64 * IN2M]).collect();
        st.wounds[2] = vec![1, 1, 1, 2];
        let mut tray = Tray::supplied(vec![]);
        let snap = |st: &State| (st.positions[2].clone(), st.wounds[2].clone());
        let (at, wounds) = snap(&st);
        st.positions[2].remove(1);
        st.wounds[2].remove(1);
        st.wounds[2][2] = 1; // capture slot 3 is wounded: 2 -> 1
        let first = landing_of(&st, 2, &at, &wounds, &tray.dead_slots(2)).expect("a landing");
        assert_eq!(first.models.iter().map(|m| (m.slot, m.dead)).collect::<Vec<_>>(), vec![(1, true), (3, false)]);
        tray.land(|| first);
        assert_eq!(tray.dead_slots(2), vec![1], "a wounded survivor is not a dead slot");
        assert!(tray.dead_slots(3).is_empty(), "another unit's landings are not this unit's");
        let (at, wounds) = snap(&st);
        st.positions[2].remove(1); // list is now [slot 0, slot 2, slot 3]: slot 2 sits second
        st.wounds[2].remove(1);
        let second = landing_of(&st, 2, &at, &wounds, &tray.dead_slots(2)).expect("a landing");
        assert_eq!(second.models.iter().map(|m| (m.slot, m.at == at[1])).collect::<Vec<_>>(), vec![(2, true)]);
        tray.land(|| second);
        assert_eq!(tray.dead_slots(2), vec![1, 2]);
    }
