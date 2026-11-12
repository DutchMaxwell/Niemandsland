use super::*;
use super::volley_landings::volley_line;
use crate::logline::Category;

    // ---- One-core P3 step 24: the core says the table's hit lines, byte for byte ----

    /// `volley_line` renamed to the table's plain-volley names (`Att` fires a `Rifle` 4 times at Quality 2+
    /// into `Def`), with the shooter on seat 1 so the lines' side is read, not defaulted.
    fn att_def() -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = volley_line();
        st.player = vec![1, 1, 0, 0];
        (statics[0].name, statics[2].name, statics[0].shoot[0].name) = ("Att".into(), "Def".into(), "Rifle".into());
        (st, statics)
    }

    /// Per supplied hit roll: the announce before the first die (stamp 0) and the hit line after it
    /// (stamp 1), in the table's words (main.gd:11752, :5056-5057), one, many and no hits alike.
    /// RED: drop the plural `s` and the "3 hits" case fails.
    #[test]
    fn a_supplied_volley_says_the_tables_hit_lines() {
        let (st, statics) = att_def();
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        for (hit_faces, hits, said) in [([6, 6, 6, 1], 3, "3 hits"), ([6, 1, 1, 1], 1, "1 hit"), ([1, 1, 1, 1], 0, "0 hits")] {
            let mut tray = Tray::supplied(vec![hit_faces.to_vec(), vec![1; hits]]); // every save fails
            resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams,
                &mut GodotRng::new(0), &mut tray).unwrap();
            let texts = |ls: Vec<LogLine>| ls.into_iter().map(|l| l.text).collect::<Vec<_>>();
            let want = vec!["Att fires at Def".to_string(), format!("Att fires Rifle at Def — {said}")];
            assert_eq!(texts(tray.all_lines()), want, "{hit_faces:?}");
            assert_eq!(texts(tray.lines_upto(0)), want[..1], "{hit_faces:?}: the announce comes before the hit die");
            assert_eq!(texts(tray.lines_upto(1)), want, "{hit_faces:?}: the hit line comes before the save dice");
            assert!(tray.all_lines().iter().all(|l| (l.rule, l.category, l.side, l.detail.is_none())
                == ("shoot", Category::Combat, 1, true)), "{:?}", tray.all_lines());
        }
    }
