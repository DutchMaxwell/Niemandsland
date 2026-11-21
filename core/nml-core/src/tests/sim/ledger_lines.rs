use super::*;
use super::volley_landings::volley_line;

    // ---- Coverage ledger, AI shoot door (lane covfix-lines, 21.11.): the ORDER of two lines the table says before / after the rest ----

    /// The lines one volley of `Att`'s `Rifle` (4 attacks, Quality 2+, the weapon edited by `weapon`) at `Def` (two Tough(3) models, Defense
    /// 4+, edited by `tune`) says on the supplied faces, at the current epoch.
    fn volley_lines(tune: impl FnOnce(&mut Ctx), weapon: impl FnOnce(&mut ShootProfile), faces: Vec<Vec<u8>>) -> Vec<String> {
        let (mut st, mut statics) = volley_line();
        st.player = vec![1, 1, 0, 0];
        st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
        (statics[0].name, statics[2].name, statics[0].shoot[0].name) = ("Att".into(), "Def".into(), "Rifle".into());
        tune(&mut statics[2].ctx);
        weapon(&mut statics[0].shoot[0]);
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        let mut tray = Tray::supplied(faces);
        resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut tray).unwrap();
        tray.all_lines().into_iter().map(|l| l.text).collect()
    }

    fn at(lines: &[String], text: &str) -> usize {
        lines.iter().position(|l| l == text).unwrap_or_else(|| panic!("no line {text:?} in {lines:?}"))
    }

    /// Ledger 4 (16 cells: Guarded, Sturdy, Versatile Defense): the table says the over-9" Defense line right after the Defense parts and
    /// BEFORE the announce (`_solo_resolve_ai_volley`); the fold said it after. RED on main: the line stood behind "Att fires at Def".
    #[test]
    fn the_over_nine_defense_line_stands_before_the_announce() {
        for name in ["Guarded", "Sturdy", "Versatile Defense"] {
            let lines = volley_lines(|c| { c.guarded = true; c.guarded_name = name_static(name); }, |_| {}, vec![vec![6, 6, 6, 1], vec![1; 3]]);
            let line = format!("Def ({name}): shot from over 9\" — +1 Defense (saves on 3+)");
            assert_eq!(lines.iter().filter(|l| **l == line).count(), 1, "once: {lines:?}");
            assert!(at(&lines, &line) < at(&lines, "Att fires at Def"), "{name}: {lines:?}");
        }
    }

    fn name_static(n: &str) -> &'static str {
        match n { "Guarded" => "Guarded", "Sturdy" => "Sturdy", _ => "Versatile Defense" }
    }
