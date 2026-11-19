use super::*;
use super::volley_landings::volley_line;

    // ---- Door rule lines (lane dlines, PR 3): the save step's and the morale trigger's lines in the table's words ----

    /// The lines one volley of `Att`'s `Rifle` (4 attacks, Quality 2+) at `Def` (two Tough(3) models, Defense 4+) says on the
    /// supplied faces; `tune` edits the fixture first. Epoch = the current one, so a wording change on an epoch turns it red.
    fn rule_lines(tune: impl FnOnce(&mut State, &mut [UnitStatic]), faces: Vec<Vec<u8>>) -> Vec<String> {
        let (mut st, mut statics) = volley_line();
        st.player = vec![1, 1, 0, 0];
        st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() }); // one profile per roster slot
        (statics[0].name, statics[2].name, statics[0].shoot[0].name) = ("Att".into(), "Def".into(), "Rifle".into());
        tune(&mut st, &mut statics);
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        let mut tray = Tray::supplied(faces);
        resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut tray).unwrap();
        tray.all_lines().into_iter().map(|l| l.text).collect()
    }

    /// A single Tough model that wounds leave at half says so before its morale test (the table's `_solo_shooting_morale`): a 4-wound model, 3 unsaved, 1 left. One still above half (3/4) says nothing.
    #[test]
    fn a_tough_single_model_at_half_says_so_before_its_morale_test() {
        let tough = |st: &mut State, s: &mut [UnitStatic]| {
            st.positions[2].truncate(1);
            (st.wounds[2], st.alive[2]) = (vec![4], 1);
            Rc::make_mut(&mut st.radii)[2] = vec![IN2M];
            s[2].model_count = 1;
            s[2].wounds_max = vec![4];
            let mut list = st.profiles.list.clone();
            (list[2].model_count, list[2].wounds_max) = (1, vec![4]);
            st.profiles = Rc::new(Profiles { list, index: HashMap::new() });
        };
        let hit3 = vec![vec![6, 6, 6, 1], vec![1; 3], vec![1]];
        let lines = rule_lines(tough, hit3);
        let at = lines.iter().position(|l| l == "Def is at half its tough value (1/4) — morale test ({cite})").unwrap_or_else(|| panic!("{lines:?}"));
        assert!(lines[at - 1].starts_with("Def takes 3 wounds"), "{lines:?}");
        let hit1 = rule_lines(tough, vec![vec![6, 1, 1, 1], vec![1], vec![1]]);
        assert!(hit1.iter().all(|l| !l.contains("half its tough value")), "{hit1:?}");
    }

    /// A target of the Guarded family names its over-9" Defense once per volley, with the Defense it then saves on; a shot from within
    /// 9" says nothing (the table's `_solo_resolve_ai_volley`).
    #[test]
    fn a_sturdy_target_names_its_over_nine_defense_once() {
        let sturdy = |_: &mut State, s: &mut [UnitStatic]| { s[2].ctx.guarded = true; s[2].ctx.guarded_name = "Sturdy"; };
        let lines = rule_lines(sturdy, vec![vec![6, 6, 6, 1], vec![1; 3]]);
        assert_eq!(lines.iter().filter(|l| l.contains("(Sturdy)")).count(), 1, "{lines:?}");
        assert!(lines.iter().any(|l| l == "Def (Sturdy): shot from over 9\" — +1 Defense (saves on 3+)"), "{lines:?}");
    }

    /// A Bane weapon alias names its re-rolls before the re-roll dice, with the singular and the condition's words.
    #[test]
    fn a_bane_alias_names_its_rerolls_before_the_dice() {
        let lines = rule_lines(|_, s| { let p = &mut s[0].shoot[0]; p.bane = true; p.bane_alias = "Smash".into(); },
            vec![vec![6, 6, 6, 1], vec![6, 1, 1], vec![1]]);
        assert!(lines.iter().any(|l| l == "Smash: Def re-rolls 1 unmodified Defense 6"), "{lines:?}");
    }
