use super::*;
use super::save_lines::att_def;
use crate::logline::Category;

    // ---- One-core P3 step 26: the core says the table's morale outcome lines, byte for byte ----

    /// Step 23's plain volley with Def at Quality 4+: 7 failed saves leave it at 3/10, so it tests morale. After
    /// the morale die (stamp 3) the table's outcome line (`_solo_morale_test`'s match, main.gd:13170-13184), as
    /// step 23 pinned it for seed 57 (face 6) and seed 0 (face 3). RED: drop the em dash and the Shaken case fails.
    #[test]
    fn a_supplied_volley_says_the_tables_morale_line() {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        for (face, said) in [(6, "Def passes morale"), (3, "Def fails morale — Shaken")] {
            let (st, mut statics) = att_def(10, 1);
            statics[2].ctx.quality = 4;
            let hit_faces: Vec<u8> = (0..10).map(|i| if i < 7 { 6 } else { 1 }).collect();
            let mut tray = Tray::supplied(vec![hit_faces, vec![1; 7], vec![face]]);
            let (after, _) = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams,
                &mut GodotRng::new(0), &mut tray).unwrap();
            let feed = tray.feed().unwrap();
            assert_eq!((feed.draws(), feed.starved_at, after.shaken[2]), (3, None, face == 3), "fixture: one morale die");
            let all = tray.all_lines();
            assert_eq!(tray.lines_upto(2).len() + 1, all.len(), "{said}: said after the morale die, last: {all:?}");
            let l = all.last().unwrap();
            assert_eq!((l.rule, l.category, l.side, l.text.as_str(), l.detail.is_none()),
                ("morale", Category::Combat, 1, said, true));
        }
    }

    /// The melee-only Rout arm (main.gd:13181-13183): a failed melee test at half strength says ROUTS.
    #[test]
    fn a_failed_melee_test_at_half_strength_says_routs() {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let (mut st, mut statics) = att_def(5, 1);
        (statics[2].model_count, statics[2].ctx.quality) = (10, 4); // 5 of 10 left: at half
        let mut tray = Tray::supplied(vec![vec![3]]);
        tray_morale_for(&mut st, &statics, 2, true, true, None, seams, &mut tray, &mut ShootResult::default(), None, None);
        assert_eq!(st.alive[2], 0, "fixture: the unit routs");
        let texts: Vec<_> = tray.all_lines().into_iter().map(|l| (l.side, l.text)).collect();
        assert_eq!(texts, [(1, "Def fails morale at half strength — ROUTS".to_string())]);
    }
