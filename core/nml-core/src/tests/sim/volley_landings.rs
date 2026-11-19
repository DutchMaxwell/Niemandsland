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

    /// EPOCH_83_LONE_HERO_TARGET (S1 shadow soak: Corsairs -> Elf Thralls, Little Ones -> Scarab Swarms, ...): "a" shoots
    /// "b", whose own models are all gone while its joined hero "bh" (Defense 3+, one model 12" away) lives. The table shoots
    /// and saves as the hero; from 83 the core rolls the saves on the hero's Defense and wounds the hero. At 82 the record
    /// replays the old reading (RED: drop the epoch-83 redirect -> the 83 run has no save at 3+).
    #[test]
    fn a_volley_at_a_host_with_no_models_is_shot_and_saved_as_its_lone_hero() {
        let (mut st, mut statics) = volley_line();
        (st.positions[2], st.wounds[2], st.alive[2]) = (vec![], vec![], 0);
        Rc::make_mut(&mut st.radii)[2] = vec![];
        (st.positions[3], st.wounds[3], st.alive[3]) = (vec![[12.0 * IN2M, 0.0, 0.0]], vec![1], 1);
        Rc::make_mut(&mut st.radii)[3] = vec![IN2M];
        (statics[2].ctx.defense, statics[3].ctx.defense, statics[3].model_count, statics[3].wounds_max) = (6, 3, 1, vec![1]);
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        let run = |epoch: u32| {
            let seams = Seams { rules_epoch: epoch, tray_exact: true, hero_attach: true, ..Seams::default() };
            resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut Tray::seeded(3)).unwrap()
        };
        let (after, shot) = run(crate::acts::EPOCH_83_LONE_HERO_TARGET);
        let saves: Vec<i64> = shot.rolls.iter().filter(|r| r.kind == "defense").map(|r| r.target).collect();
        assert_eq!(saves, vec![3], "the hero's Defense 3+: {:?}", shot.rolls);
        assert!(shot.log.iter().any(|l| l.contains("is the unit now")), "the redirect logs: {:?}", shot.log);
        assert!(after.wounds[3] != st.wounds[3] || after.alive[3] < st.alive[3] || saves == vec![3], "the hero takes the volley");
        let (_, old) = run(crate::acts::EPOCH_82_IGNORE_BY_NAME);
        assert!(!old.rolls.iter().any(|r| r.kind == "defense" && r.target == 3), "82 replays the old reading: {:?}", old.rolls);
    }

    /// EPOCH_88_SPLIT_LONE_HERO (wide-gate prep soak: Organ Tank -> Blood Battle Brothers, a split volley): a split group aimed at
    /// "b", whose own models are gone while its joined hero "bh" (Defense 3+) lives, saves on the hero's Defense from 88; at 87
    /// the record replays the host's (RED: drop the split redirect -> the 88 run saves at the host's 6+).
    #[test]
    fn a_split_group_at_a_host_with_no_models_is_saved_as_its_lone_hero() {
        let (mut st, mut statics) = volley_line();
        (st.positions[2], st.wounds[2], st.alive[2]) = (vec![], vec![], 0);
        Rc::make_mut(&mut st.radii)[2] = vec![];
        (st.positions[3], st.wounds[3], st.alive[3]) = (vec![[12.0 * IN2M, 0.0, 0.0]], vec![1], 1);
        Rc::make_mut(&mut st.radii)[3] = vec![IN2M];
        (statics[2].ctx.defense, statics[3].ctx.defense, statics[3].model_count, statics[3].wounds_max) = (6, 3, 1, vec![1]);
        // The recorded key names the hero, the aim names the empty host: `split_plan` builds a group for "b".
        let aim = vec![crate::io::SplitShot { member: "a".into(), weapon: "rifle".into(), target: "b".into() }];
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("bh".into()), charge: None,
            patient: false, split: Some(aim), traced: None, teleport: None,
        };
        let saves = |epoch: u32| {
            let seams = Seams { rules_epoch: epoch, tray_exact: true, hero_attach: true, ..Seams::default() };
            let (_, shot) = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut Tray::seeded(3)).unwrap();
            shot.rolls.iter().filter(|r| r.kind == "defense").map(|r| r.target).collect::<Vec<_>>()
        };
        assert_eq!(saves(crate::acts::EPOCH_88_SPLIT_LONE_HERO), vec![3], "the hero's Defense 3+");
        assert!(!saves(crate::acts::EPOCH_87_WALKED_DANGEROUS).contains(&3), "87 replays the host group");
    }

    /// The Hero rule on the STEP path (C-19: `lone_hero_target`): "b" has no models left, its joined hero "bh" lives. The table
    /// says "Hero: <hero> is the unit now - shots from <shooter> at <host> are ..." before the volley and then "<shooter> fires at
    /// <host>"; the step path only shows what the tray says, and `shot.log` (where the line used to go) is not read there. A
    /// log line, no die: the dice are the ones the tests above pin. RED: drop the `tray.say` -> no Hero line, and "a fires at bh".
    #[test]
    fn the_step_path_says_the_hero_line_and_aims_at_the_host() {
        let (mut st, mut statics) = volley_line();
        (st.positions[2], st.wounds[2], st.alive[2]) = (vec![], vec![], 0);
        Rc::make_mut(&mut st.radii)[2] = vec![];
        (st.positions[3], st.wounds[3], st.alive[3]) = (vec![[12.0 * IN2M, 0.0, 0.0]], vec![1], 1);
        Rc::make_mut(&mut st.radii)[3] = vec![IN2M];
        (statics[2].ctx.defense, statics[3].ctx.defense, statics[3].model_count, statics[3].wounds_max) = (6, 3, 1, vec![1]);
        let hero = "Hero: bh is the unit now — shots from a at b are measured and saved as the hero";
        let aim = vec![crate::io::SplitShot { member: "a".into(), weapon: "rifle".into(), target: "b".into() }];
        let said = |epoch: u32, key: &str, split: Option<Vec<crate::io::SplitShot>>| {
            let action = Action {
                kind: HOLD, unit: "a".into(), dest: None, shoot: Some(key.into()), charge: None,
                patient: false, split, traced: None, teleport: None,
            };
            let seams = Seams { rules_epoch: epoch, tray_exact: true, hero_attach: true, ..Seams::default() };
            let mut tray = Tray::supplied(vec![vec![6; 4], vec![1; 4]]); // 4 hits, 4 failed saves; morale starves
            resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut tray).unwrap();
            tray.all_lines().into_iter().map(|l| l.text).collect::<Vec<_>>()
        };
        let one = said(crate::acts::EPOCH_83_LONE_HERO_TARGET, "b", None);
        assert_eq!(one[..2], [hero, "a fires at b"], "one target, from 83: {one:?}");
        assert_eq!(one.iter().filter(|l| l.starts_with("Hero: ")).count(), 1, "said once: {one:?}");
        let old = said(crate::acts::EPOCH_82_IGNORE_BY_NAME, "b", None);
        assert!(!old.iter().any(|l| l.starts_with("Hero: ")), "82 replays the old reading, no Hero rule: {old:?}");
        let split = said(crate::acts::EPOCH_88_SPLIT_LONE_HERO, "bh", Some(aim));
        assert_eq!(split[..2], [hero, "a fires at b"], "a split group, from 88: {split:?}");
    }
