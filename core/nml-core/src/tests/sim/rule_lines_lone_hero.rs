use super::*;
use super::volley_landings::volley_line;

    // ---- Door rule lines (lane dlines, PR 5): a volley at a lone hero reads like the table's, host and all ----

    /// `volley_line` with "b" out of models and its joined hero "bh" (one model, 6 wounds, Defense 6+) the only one standing; "a"
    /// fires its rifle at "b" and three of its four hits are not saved. `faces` = hit dice, saves, then the morale die.
    fn lone_hero_lines(faces: Vec<Vec<u8>>) -> Vec<String> {
        lone_hero_lines_with(faces, |_| {})
    }

    /// `lone_hero_lines` with `tune` run on the state first (the hero's flags).
    fn lone_hero_lines_with(faces: Vec<Vec<u8>>, tune: impl FnOnce(&mut State)) -> Vec<String> {
        let (mut st, mut statics) = volley_line();
        tune(&mut st);
        (st.positions[2], st.wounds[2], st.alive[2]) = (vec![], vec![], 0);
        Rc::make_mut(&mut st.radii)[2] = vec![];
        (st.positions[3], st.wounds[3], st.alive[3]) = (vec![[12.0 * IN2M, 0.0, 0.0]], vec![6], 1);
        Rc::make_mut(&mut st.radii)[3] = vec![IN2M];
        st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
        (statics[0].name, statics[2].name, statics[3].name, statics[0].shoot[0].name) = ("Gunners".into(), "Cultists".into(), "Champion".into(), "Rifle".into());
        (statics[2].ctx.defense, statics[3].ctx.defense, statics[3].model_count, statics[3].wounds_max) = (6, 6, 1, vec![6]);
        let (q, _) = (4, 0);
        (statics[2].quality, statics[3].quality, statics[2].ctx.quality) = (q, q, q);
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, hero_attach: true, hero_counts_in_size: true, ..Seams::default() };
        let mut tray = Tray::supplied(faces);
        resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut tray).unwrap();
        tray.all_lines().into_iter().map(|l| l.text).collect()
    }

    /// The table calls the target by its host's name throughout, the hero's own save line apart: the hit line, the wound line (the
    /// chain counted as ONE unit: models, not the hero's wounds), the half-strength trigger, the Hero who tests on its behalf and the
    /// outcome. RED: aim the hit line at the hero, report the chain on the hero, name the hero in the morale lines.
    #[test]
    fn a_volley_at_a_lone_hero_names_the_host_where_the_table_does() {
        let lines = lone_hero_lines(vec![vec![6; 4], vec![1, 1, 1, 6], vec![1]]);
        assert_eq!(lines, [
            "Hero: Champion is the unit now — shots from Gunners at Cultists are measured and saved as the hero",
            "Gunners fires at Cultists",
            "Gunners fires Rifle at Cultists — 4 hits",
            "Champion saves on 6+",
            "Cultists takes 3 wounds (1/3)",
            "Cultists takes wounds at half strength or less (1/3 models) — morale test ({cite})",
            "Hero Champion tests on behalf of Cultists (Q4+)",
            "Cultists fails morale — Shaken",
        ]);
    }

    /// The host is wiped and the hero carries the unit's flag: the table says so after the wound lines (`_solo_hero_carries_on`), and the
    /// morale test that follows is the Shaken unit's own (no die). RED on main: neither line was said.
    #[test]
    fn a_hero_that_fights_on_alone_says_the_flag_it_carries() {
        let flagged = |shaken: bool, fatigued: bool| lone_hero_lines_with(vec![vec![6; 4], vec![1, 1, 1, 6]], |st| (st.shaken[3], st.fatigued[3]) = (shaken, fatigued));
        assert_eq!(flagged(true, false), [
            "Hero: Champion is the unit now — shots from Gunners at Cultists are measured and saved as the hero",
            "Gunners fires at Cultists",
            "Gunners fires Rifle at Cultists — 4 hits",
            "Champion saves on 6+",
            "Cultists takes 3 wounds (1/3)",
            "Champion fights on alone — carries the unit's Shaken ({cite})",
            "Cultists takes wounds at half strength or less (1/3 models) — morale test ({cite})",
            "Cultists is already Shaken — automatically fails morale ({cite})",
            "Cultists fails morale — Shaken",
        ]);
        let said = |lines: &[String]| lines.iter().filter(|l| l.contains("fights on alone")).cloned().collect::<Vec<_>>();
        assert_eq!(said(&flagged(true, true)), ["Champion fights on alone — carries the unit's Shaken + Fatigue ({cite})"]);
        assert_eq!(said(&flagged(false, true)), ["Champion fights on alone — carries the unit's Fatigue ({cite})"]);
        assert!(said(&flagged(false, false)).is_empty(), "no flag, no line");
    }

