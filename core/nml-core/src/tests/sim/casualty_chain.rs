use super::*;

    /// Tray-exact S5 — the core half of the chain-order parity pin (the table half:
    /// test/casualty_order_parity_test.gd, the same fixture). Each fixture chain becomes unit 0
    /// of `four_unit_line`, its joined hero emptied so the group is the unit alone.
    #[test]
    fn the_cores_chain_casualty_order_matches_the_tables_on_the_shared_fixture() {
        let fx: serde_json::Value =
            serde_json::from_str(include_str!("../../../tests/fixtures/casualty_order.json")).unwrap();
        for c in fx["chains"].as_array().unwrap() {
            let mut st = four_unit_line();
            let ms = c["models"].as_array().unwrap();
            let f = |v: &serde_json::Value| v.as_f64().unwrap();
            st.positions[0] = ms.iter().map(|m| [f(&m["pos"][0]), f(&m["pos"][1]), f(&m["pos"][2])]).collect();
            st.wounds[0] = ms.iter().map(|m| m["wounds"].as_i64().unwrap()).collect();
            Rc::make_mut(&mut st.radii)[0] = vec![f(&c["base_mm"]) / 2000.0; ms.len()];
            st.alive[0] = ms.len() as i64;
            let mut names: Vec<String> = Vec::new();
            let mut kits = Vec::new();
            for m in ms {
                let mut weapons = Vec::new();
                for w in m["weapons"].as_array().unwrap() {
                    let w = w.as_str().unwrap().to_string();
                    let i = names.iter().position(|n| *n == w).unwrap_or(names.len());
                    if i == names.len() {
                        names.push(w);
                    }
                    weapons.push(i as u16);
                }
                let (e, x) = (m["equipment"].as_u64().unwrap() as u16, m["wounds_max"].as_i64().unwrap());
                kits.push(crate::state::Kit { weapons, equipment: e, wounds_max: x });
            }
            st.kits = vec![Rc::new(kits)];
            (st.positions[1], Rc::make_mut(&mut st.radii)[1], st.wounds[1], st.alive[1]) = (vec![], vec![], vec![], 0);
            let want: Vec<usize> =
                c["expected"].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect();
            assert_eq!(crate::casualty::chain_casualty_order(&st, 0, None, 0), Some(want), "{}", c["name"]);
        }
    }

    /// Tray-exact S6 (LIVE behind `Seams::tray_exact`): casualties come off in the table's
    /// `chain_casualty_order` — `apply_wounds_to_models` for plain wounds, `deadly_pick` for Deadly —
    /// so the Missile Launcher bearer in slot 0 is NOT the first to die. Without the switch, and on a
    /// unit without kits, slot 0 still goes first (every game today).
    #[test]
    fn with_tray_exact_the_launcher_in_slot_0_outlives_the_cheap_end_model() {
        let line = || {
            let mut st = four_unit_line();
            let s = 0.0574; // 32 mm bases, 1-inch edge gaps
            st.positions[0] = vec![[0.0, 0.0, 0.0], [s, 0.0, 0.0], [2.0 * s, 0.0, 0.0]];
            (st.wounds[0], Rc::make_mut(&mut st.radii)[0], st.alive[0]) = (vec![1, 1, 1], vec![0.016; 3], 3);
            let k = |w: Vec<u16>| crate::state::Kit { weapons: w, equipment: 0, wounds_max: 1 };
            st.kits = vec![Rc::new(vec![k(vec![1]), k(vec![0]), k(vec![0])])]; // 1 = the launcher
            (st.positions[1], Rc::make_mut(&mut st.radii)[1], st.wounds[1], st.alive[1]) = (vec![], vec![], vec![], 0);
            st
        };
        let kit_ids = |st: &State| st.kits[0].iter().map(|k| k.weapons[0]).collect::<Vec<_>>();
        let mut st = line();
        crate::sim::land_wounds_with(&mut st, 0, 1, true, 0);
        assert_eq!((st.alive[0], kit_ids(&st)), (2, vec![1, 0]), "the end Rifle died, the launcher stands");
        let mut old = line();
        crate::sim::land_wounds_with(&mut old, 0, 1, false, 0);
        assert_eq!(kit_ids(&old), vec![0, 0], "without the switch slot 0 (the launcher) dies");
        let exact = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let mut st = line();
        st.profiles = Rc::new(Profiles { list: vec![Profile { wounds_max: vec![1, 1, 1], model_count: 3, ..st.profiles.list[0].clone() }; 4], index: HashMap::new() });
        land_deadly_wounds(&mut st, 0, 1, 3, exact);
        assert_eq!(kit_ids(&st), vec![1, 0], "the Deadly pick follows the same order");
    }

    /// Tray-exact S8: the Takedown re-pick's own square (`takedown_pick_cover_after`). Three models in
    /// a line at x = 4" (forest) / 7" / 8" (open); the launcher (Tough 2) at 4" is picked first. Once a
    /// group KILLS it, the next pick stands in the open; a group that only WOUNDS it moves the pick on
    /// as well (a wounded body ranks first for removal, never last for the sniper). No board: the flag.
    #[test]
    fn the_takedown_re_pick_reads_the_next_picks_own_square() {
        let board = forest_bar_board();
        let mut st = four_unit_line();
        st.positions[0] = vec![[4.0 * IN2M, 0.0, 0.0], [7.0 * IN2M, 0.0, 0.0], [8.0 * IN2M, 0.0, 0.0]];
        (st.wounds[0], Rc::make_mut(&mut st.radii)[0], st.alive[0]) = (vec![2, 1, 1], vec![0.016; 3], 3);
        let k = |w: u16, x: i64| crate::state::Kit { weapons: vec![w], equipment: 0, wounds_max: x };
        st.kits = vec![Rc::new(vec![k(1, 2), k(0, 1), k(0, 1)])];
        let at = |groups: &[i64]| takedown_pick_cover_after(&st, 0, Cover::Board(&board), false, groups, None);
        assert!(at(&[]), "the first pick, the launcher, stands in the forest");
        assert!(!at(&[2]), "killed: the next pick stands in the open");
        assert!(!at(&[1]), "wounded: the pick moves on as well");
        assert!(at(&[0]), "a group that landed nothing changes nothing");
        assert!(takedown_pick_cover_after(&st, 0, Cover::Recorded(None), true, &[2], None), "no board: the unit flag");
    }

    /// EPOCH_70_TRAY_EXACT, the tray-exact series' one bump: `seams_of` (the planner, in-game too)
    /// turns `Seams::tray_exact` on from 70 only. A record at EPOCH_69_HERO_FOLD replays the core's old
    /// slot order (the launcher in slot 0 dies first); a fresh game at 70 plays the table's.
    #[test]
    fn epoch_70_turns_tray_exact_on_and_epoch_69_replays_the_old_order() {
        let exact_at = |e: u32| crate::plan::seams_of(&crate::acts::Knobs { rules_epoch: e, ..Default::default() }).tray_exact;
        let survivors = |e: u32| {
            let mut st = four_unit_line();
            let s = 0.0574; // 32 mm bases, 1-inch edge gaps
            st.positions[0] = vec![[0.0, 0.0, 0.0], [s, 0.0, 0.0], [2.0 * s, 0.0, 0.0]];
            (st.wounds[0], Rc::make_mut(&mut st.radii)[0], st.alive[0]) = (vec![1, 1, 1], vec![0.016; 3], 3);
            let k = |w: Vec<u16>| crate::state::Kit { weapons: w, equipment: 0, wounds_max: 1 };
            st.kits = vec![Rc::new(vec![k(vec![1]), k(vec![0]), k(vec![0])])]; // 1 = the launcher
            (st.positions[1], Rc::make_mut(&mut st.radii)[1], st.wounds[1], st.alive[1]) = (vec![], vec![], vec![], 0);
            crate::sim::land_wounds_with(&mut st, 0, 1, exact_at(e), e);
            st.kits[0].iter().map(|k| k.weapons[0]).collect::<Vec<_>>()
        };
        assert_eq!(survivors(crate::acts::EPOCH_69_HERO_FOLD), vec![0, 0], "69: slot 0, the launcher, dies");
        assert_eq!(survivors(crate::acts::EPOCH_70_TRAY_EXACT), vec![1, 0], "70: the end Rifle dies");
        assert_eq!(survivors(crate::acts::CURRENT_RULES_EPOCH), vec![1, 0], "the live epoch plays the tray-exact order");
    }


/// Step 9c: the casualty pick reads the unit's chain at the epoch. Six models in a line, 1 in edge gaps (32 mm bases), both
/// end models carry the launcher (kept last in the value order): the line spans 10 in, so no pick keeps every pair within
/// 6 in, but dropping an end keeps them within 9 in. A gff unit at the Firefight 9 in drops an end (slot 0) from the
/// casualty-chain epoch; one epoch below it still plays the recorded 6 in (no coherent pick: the value order's lead,
/// slot 1, which breaks the line). aofs keeps its 6 in; gf keeps its 9 in at every epoch.
#[test]
fn the_casualty_pick_reads_the_firefight_9_in_chain_from_its_epoch() {
    let pick = |sys: &str, e: u32| {
        let mut st = four_unit_line();
        let s = 0.0574;
        st.positions[0] = (0..6).map(|i| [i as f64 * s, 0.0, 0.0]).collect();
        (st.wounds[0], Rc::make_mut(&mut st.radii)[0], st.alive[0]) = (vec![1; 6], vec![0.016; 6], 6);
        let k = |w: Vec<u16>| crate::state::Kit { weapons: w, equipment: 0, wounds_max: 1 };
        st.kits = vec![Rc::new((0..6).map(|i| k(vec![u16::from(i == 0 || i == 5)])).collect())];
        (st.positions[1], Rc::make_mut(&mut st.radii)[1], st.wounds[1], st.alive[1]) = (vec![], vec![], vec![], 0);
        let mut p = st.profiles.list[0].clone();
        p.game_system = sys.into();
        st.profiles = Rc::new(crate::state::Profiles { list: vec![p; st.profiles.list.len()], index: Default::default() });
        crate::casualty::chain_casualty_order(&st, 0, Some(1), e).and_then(|o| o.first().copied())
    };
    let e = crate::acts::PENDING_EPOCH_CASUALTY_CHAIN;
    assert!(e > crate::acts::CURRENT_RULES_EPOCH, "a placeholder no record has played");
    assert_eq!(pick("gff", e), Some(0), "the Firefight 9 in: an end model goes, the line stays whole");
    assert_eq!(pick("gff", e - 1), Some(1), "one epoch below: the recorded 6 in, no coherent pick, the value order's lead");
    assert_eq!(pick("aofs", e), Some(1), "AoF: Skirmish keeps 6 in");
    assert_eq!((pick("gf", e), pick("gf", e - 1)), (Some(0), Some(0)), "gf is 9 in at every epoch");
}

/// Ruling D16: the command-group bearer's slot follows the models out - it moves up past a removed slot before it, goes
/// to `None` when its own slot is removed, and a unit with no model left has none; a wound landed in slot order on a
/// three-model unit whose bearer is the last slot leaves the bearer at slot 1.
#[test]
fn the_cmd_bearer_slot_follows_the_models_out() {
    let mut st = four_unit_line();
    st.cmd_bearer = vec![Some(2), None, None, None];
    st.kit_remove(0, 0);
    assert_eq!(st.cmd_bearer[0], Some(1), "a slot before it left");
    st.kit_remove(0, 3);
    assert_eq!(st.cmd_bearer[0], Some(1), "a slot after it left");
    st.kit_remove(0, 1);
    assert_eq!(st.cmd_bearer[0], None, "its own slot left");
    let mut st = four_unit_line();
    st.positions[0] = vec![[0.0; 3], [0.05, 0.0, 0.0], [0.1, 0.0, 0.0]];
    (st.wounds[0], Rc::make_mut(&mut st.radii)[0], st.alive[0]) = (vec![1, 1, 1], vec![0.016; 3], 3);
    st.cmd_bearer = vec![Some(2), None, None, None];
    crate::sim::land_wounds_with(&mut st, 0, 1, false, 0);
    assert_eq!((st.alive[0], st.cmd_bearer[0]), (2, Some(1)), "slot 0 fell: the bearer is now slot 1");
    st.positions[0].clear();
    st.kits_drop(0);
    assert_eq!(st.cmd_bearer[0], None, "no model left, no bearer");
}
