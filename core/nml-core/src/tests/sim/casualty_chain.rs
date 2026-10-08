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
            st.radii[0] = vec![f(&c["base_mm"]) / 2000.0; ms.len()];
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
            (st.positions[1], st.radii[1], st.wounds[1], st.alive[1]) = (vec![], vec![], vec![], 0);
            let want: Vec<usize> =
                c["expected"].as_array().unwrap().iter().map(|x| x.as_u64().unwrap() as usize).collect();
            assert_eq!(crate::casualty::chain_casualty_order(&st, 0, None), Some(want), "{}", c["name"]);
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
            (st.wounds[0], st.radii[0], st.alive[0]) = (vec![1, 1, 1], vec![0.016; 3], 3);
            let k = |w: Vec<u16>| crate::state::Kit { weapons: w, equipment: 0, wounds_max: 1 };
            st.kits = vec![Rc::new(vec![k(vec![1]), k(vec![0]), k(vec![0])])]; // 1 = the launcher
            (st.positions[1], st.radii[1], st.wounds[1], st.alive[1]) = (vec![], vec![], vec![], 0);
            st
        };
        let kit_ids = |st: &State| st.kits[0].iter().map(|k| k.weapons[0]).collect::<Vec<_>>();
        let mut st = line();
        crate::sim::land_wounds_with(&mut st, 0, 1, true);
        assert_eq!((st.alive[0], kit_ids(&st)), (2, vec![1, 0]), "the end Rifle died, the launcher stands");
        let mut old = line();
        crate::sim::land_wounds_with(&mut old, 0, 1, false);
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
        (st.wounds[0], st.radii[0], st.alive[0]) = (vec![2, 1, 1], vec![0.016; 3], 3);
        let k = |w: u16, x: i64| crate::state::Kit { weapons: vec![w], equipment: 0, wounds_max: x };
        st.kits = vec![Rc::new(vec![k(1, 2), k(0, 1), k(0, 1)])];
        let at = |groups: &[i64]| takedown_pick_cover_after(&st, 0, Cover::Board(&board), false, groups);
        assert!(at(&[]), "the first pick, the launcher, stands in the forest");
        assert!(!at(&[2]), "killed: the next pick stands in the open");
        assert!(!at(&[1]), "wounded: the pick moves on as well");
        assert!(at(&[0]), "a group that landed nothing changes nothing");
        assert!(takedown_pick_cover_after(&st, 0, Cover::Recorded(None), true, &[2]), "no board: the unit flag");
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
            (st.wounds[0], st.radii[0], st.alive[0]) = (vec![1, 1, 1], vec![0.016; 3], 3);
            let k = |w: Vec<u16>| crate::state::Kit { weapons: w, equipment: 0, wounds_max: 1 };
            st.kits = vec![Rc::new(vec![k(vec![1]), k(vec![0]), k(vec![0])])]; // 1 = the launcher
            (st.positions[1], st.radii[1], st.wounds[1], st.alive[1]) = (vec![], vec![], vec![], 0);
            crate::sim::land_wounds_with(&mut st, 0, 1, exact_at(e));
            st.kits[0].iter().map(|k| k.weapons[0]).collect::<Vec<_>>()
        };
        assert_eq!(survivors(crate::acts::EPOCH_69_HERO_FOLD), vec![0, 0], "69: slot 0, the launcher, dies");
        assert_eq!(survivors(crate::acts::EPOCH_70_TRAY_EXACT), vec![1, 0], "70: the end Rifle dies");
        assert!(crate::acts::CURRENT_RULES_EPOCH >= crate::acts::EPOCH_70_TRAY_EXACT);
    }

