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
            assert_eq!(texts(tray.all_lines())[..2], want, "{hit_faces:?}"); // the save lines after them: save_lines.rs
            assert_eq!(texts(tray.lines_upto(0)), want[..1], "{hit_faces:?}: the announce comes before the hit die");
            assert_eq!(texts(tray.lines_upto(1))[..2], want, "{hit_faces:?}: the hit line comes before the save dice");
            assert!(tray.all_lines()[..2].iter().all(|l| (l.rule, l.category, l.side, l.detail.is_none())
                == ("shoot", Category::Combat, 1, true)), "{:?}", tray.all_lines());
        }
    }

    /// The lines one HOLD volley of "a" at "b" says on supplied faces.
    fn said(st: &State, statics: &[UnitStatic], sighting: bool, faces: Vec<Vec<u8>>) -> Vec<LogLine> {
        // Per-model sight reads each unit's own base (`State::profile`): one profile per roster slot.
        let mut st = st.clone();
        st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, sighting, ..Seams::default() };
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        let mut tray = Tray::supplied(faces);
        resolve_stochastic_tray_on_board(statics, &st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut tray)
            .unwrap();
        tray.all_lines()
    }

    /// Step 27, Q17 (answered 13.11.: the announce line for every side): the core says "<A> fires at <B>" whichever
    /// seat shoots; the table's AI path says it today, its human path does not. RED: say it for seat 1 only.
    #[test]
    fn the_announce_is_said_for_every_seat() {
        for seat in [0i64, 1] {
            let (mut st, statics) = att_def();
            st.player = vec![seat, seat, 1 - seat, 1 - seat];
            let lines = said(&st, &statics, true, vec![vec![6, 6, 6, 1], vec![1; 3]]);
            assert_eq!((lines[0].text.as_str(), lines[0].side), ("Att fires at Def", seat), "seat {seat}: {lines:?}");
        }
    }

    /// Step 27: with per-model sight (the step path's `sighting`, step 22b) a member whose models do not all have range
    /// and sight says the table's "(n/m models sighted)" part (main.gd:5129); all four in range, or the whole-unit
    /// reading, say none. RED: drop the part.
    #[test]
    fn a_partly_sighted_volley_says_how_many_models_see() {
        for (back_in, sighting, dice, want) in [
            (30.0, true, 2, "Att fires Rifle at Def (2/4 models sighted) — 2 hits"),
            (0.0, true, 4, "Att fires Rifle at Def — 4 hits"),
            (30.0, false, 4, "Att fires Rifle at Def — 4 hits"),
        ] {
            let (mut st, mut statics) = att_def();
            // Four shooters; the last two `back_in` behind the line (30" puts them out of the Rifle's 24").
            st.positions[0] = vec![[0.0, 0.0, 0.0], [0.0, 0.0, IN2M], [-back_in * IN2M, 0.0, 2.0 * IN2M],
                [-back_in * IN2M, 0.0, 3.0 * IN2M]];
            (st.alive[0], st.wounds[0]) = (4, vec![1; 4]);
            Rc::make_mut(&mut st.radii)[0] = vec![IN2M; 4];
            (statics[0].model_count, statics[0].shoot[0].count) = (4, 4); // one Rifle per model, four attacks in all
            let lines = said(&st, &statics, sighting, vec![vec![6; dice], vec![1; dice]]);
            assert_eq!(lines[1].text, want, "{back_in}\" back, sighting {sighting}: {lines:?}");
        }
    }
