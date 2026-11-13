use super::*;
use super::volley_landings::volley_line;
use crate::logline::Category;

    // ---- One-core P3 step 25: the core says the table's save and casualty lines, byte for byte ----

    /// The step-23 plain volley: `Att` fires a 10-attack `Rifle` at Quality 2+ into `Def`, ten 1-wound models
    /// at Defense 4+, no joined hero; Def sits on seat 1, so its lines' side is read, not defaulted. `models` = 1 with
    /// `wounds` 3 makes Def one Tough(3) model instead.
    pub(super) fn att_def(models: usize, wounds: i64) -> (State, Vec<UnitStatic>) {
        let (mut st, mut statics) = volley_line();
        st.player = vec![0, 0, 1, 1];
        (st.attached, st.attached_to) = (Rc::new(vec![vec![]; 4]), Rc::new(vec![None; 4])); // a plain unit: no joined hero
        st.positions[2] = (0..models).map(|i| [12.0 * IN2M, 0.0, 2.5 * i as f64 * IN2M]).collect();
        (st.wounds[2], st.alive[2]) = (vec![wounds; models], models as i64);
        Rc::make_mut(&mut st.radii)[2] = vec![IN2M; models];
        (statics[0].name, statics[2].name, statics[0].shoot[0].name) = ("Att".into(), "Def".into(), "Rifle".into());
        statics[0].shoot[0].attacks = 10;
        (statics[2].model_count, statics[2].wounds_max, statics[2].ctx.tough) = (models as i64, vec![wounds; models], wounds);
        (st, statics)
    }

    /// Per supplied volley: the threshold line before the save dice (stamp 1, main.gd:9823), then at the
    /// landing's stamp (2, before the morale die) the wounds that landed and the models lost, in
    /// `_solo_apply_wounds`'s order (main.gd:16582-16600). RED: drop a plural `s` and a case fails.
    #[test]
    fn a_supplied_volley_says_the_tables_save_and_casualty_lines() {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        let cases: [(usize, i64, usize, u8, &[&str]); 5] = [
            (10, 1, 7, 1, &["Def takes 7 wounds (3/10)", "Def loses 7 models (3/10)"]),
            (10, 1, 1, 1, &["Def takes 1 wound (9/10)", "Def loses a model (9/10)"]),
            (10, 1, 3, 6, &[]), // every save holds: no wound, no line (main.gd:16533)
            (10, 1, 10, 1, &["Def takes 10 wounds (0/10)", "Def destroyed"]),
            (1, 3, 2, 1, &["Def takes 2 wounds (1/3 wounds)"]), // NML-1091: one Tough model counts wounds
        ];
        for (models, wounds, hits, save_face, said) in cases {
            let (st, statics) = att_def(models, wounds);
            let hit_faces: Vec<u8> = (0..10).map(|i| if i < hits { 6 } else { 1 }).collect();
            let mut tray = Tray::supplied(vec![hit_faces, vec![save_face; hits]]);
            resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams,
                &mut GodotRng::new(0), &mut tray).unwrap();
            let texts = |ls: Vec<LogLine>| ls.into_iter().map(|l| l.text).collect::<Vec<_>>();
            let mut want = vec!["Att fires at Def".to_string(), format!("Att fires Rifle at Def — {hits} hit{}", if hits == 1 { "" } else { "s" }), "Def saves on 4+".into()];
            want.extend(said.iter().map(|s| s.to_string()));
            assert_eq!(texts(tray.all_lines())[..want.len()], want, "{models} models, {hits} hits"); // morale: morale_lines.rs
            assert_eq!(texts(tray.lines_upto(1)), want[..3], "{hits} hits: the threshold comes before the save dice");
            assert_eq!(tray.landings_upto(1).len(), 0, "{hits} hits: nothing lands before the save dice");
            assert_eq!(texts(tray.lines_upto(2)), want, "{hits} hits: the casualty lines share the landing's stamp");
            assert!(tray.all_lines()[2..].iter().all(|l| (l.category, l.side, l.detail.is_none()) == (Category::Combat, 1, true)),
                "{:?}", tray.all_lines());
        }
    }

    /// The AP forms of `save_threshold_text` (main.gd:11634), which the plain volley never reaches.
    #[test]
    fn the_threshold_text_says_the_ap_forms() {
        let (st, mut statics) = att_def(10, 1);
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        for (ap, said) in [(1, "Def saves on 5+ (Def 4+, AP 1)"), (3, "Def saves on 6 only (Def 4+, AP 3 — a natural 6 always saves)")] {
            statics[0].shoot[0].ap = ap;
            let mut tray = Tray::supplied(vec![vec![6; 10], vec![6; 10]]);
            resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams,
                &mut GodotRng::new(0), &mut tray).unwrap();
            assert_eq!(tray.all_lines()[2].text, said);
        }
    }
