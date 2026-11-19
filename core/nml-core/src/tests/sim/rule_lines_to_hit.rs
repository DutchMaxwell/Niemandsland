use super::*;
use super::volley_landings::volley_line;
use crate::unit::ShotModNote;

    // ---- Door rule lines (lane dlines train 4, DS-GHITN): to-hit note and Takedown ----

    fn rule_lines(tune: impl FnOnce(&mut State, &mut [UnitStatic]), faces: Vec<Vec<u8>>) -> Vec<String> {
        let (mut st, mut statics) = volley_line();
        st.player = vec![1, 1, 0, 0];
        st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
        (statics[0].name, statics[2].name, statics[0].shoot[0].name) = ("Att".into(), "Def".into(), "Rifle".into());
        statics[0].ctx.quality = 4;
        statics[0].ctx.rules_epoch = crate::acts::CURRENT_RULES_EPOCH;
        statics[2].ctx.rules_epoch = crate::acts::CURRENT_RULES_EPOCH;
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

    #[test]
    fn the_to_hit_note_follows_table_order_and_logs_zero_net() {
        let lines = rule_lines(|st, s| {
            st.positions[2] = vec![[18.0 * IN2M, 0.0, 0.0]; 2];
            let a = &mut s[0].ctx;
            (a.artillery, a.artillery_shooter_over_in, a.artillery_shooter_needs_hold) = (true, 12.0, true);
            a.shot_mod_notes[0] = ShotModNote { name: "Good Shot", bonus: 1, over_in: 0.0, kind: 0 };
            s[0].shoot[0].hit_bonus = 1;
            let d = &mut s[2].ctx;
            (d.stealth, d.evasive) = (true, true);
        }, vec![vec![6, 1, 1, 1], vec![1]]);
        assert!(lines.iter().any(|l| l == "To-hit vs Def: Artillery +1 (Held, target over 12\"), Stealth -1, Evasive -1, Good Shot +1 → hits on 4+"), "{lines:?}");
        // Plain volley with no modifiers writes no To-hit line.
        let plain = rule_lines(|_, _| {}, vec![vec![6, 1, 1, 1], vec![1]]);
        assert!(plain.iter().all(|l| !l.starts_with("To-hit vs")), "{plain:?}");
    }

    #[test]
    fn stealth_alias_evasive_stand_down_aircraft_and_instinctive_are_named() {
        let lines = rule_lines(|st, s| {
            st.positions[2] = vec![[18.0 * IN2M, 0.0, 0.0]; 2];
            s[0].ctx.instinctive_hit_bonus = 1;
            s[0].ctx.instinctive_name = "Instinctive";
            let d = &mut s[2].ctx;
            (d.stealth_alias_penalty, d.stealth_alias_over_in, d.stealth_alias_name) = (1, 9.0, "Screened");
            (d.aircraft_hit_penalty, d.aircraft_hit_name) = (1, "Aircraft");
            (d.evasive, d.evasive_stand_down_name) = (true, "Enhanced Empyrean Spirit");
        }, vec![vec![6, 1, 1, 1], vec![1]]);
        assert!(lines.iter().any(|l| l == "To-hit vs Def: Screened -1 over 9\", Aircraft -1, Enhanced Empyrean Spirit: -1 to hit (base Evasive stood down), Instinctive +1 (closest target) → hits on 6+"), "{lines:?}");
    }

    #[test]
    fn takedown_writes_its_three_lines_embeds_the_note_and_omits_takes_wounds() {
        let lines = rule_lines(|st, s| {
            st.positions[2] = vec![[14.0 * IN2M, 0.0, 0.0]; 2];
            st.wounds[2] = vec![3, 3];
            s[2].wounds_max = vec![3, 3];
            s[0].shoot[0].takedown = true;
            s[0].shoot[0].hit_bonus = 1;
            s[0].ctx.shot_mod_notes[0] = ShotModNote { name: "Good Shot", bonus: 1, over_in: 0.0, kind: 0 };
            s[2].ctx.stealth = true;
        }, vec![vec![6, 6, 1, 1], vec![1, 1]]);
        assert!(lines.iter().any(|l| l == "Takedown (Rifle): targets the Tough(3) model in Def — resolved as a unit of [1]"), "{lines:?}");
        assert!(lines.iter().any(|l| l == "To-hit vs Def: Stealth -1, Good Shot +1 → hits on 4+"), "{lines:?}");
        assert!(lines.iter().any(|l| l == "Takedown (Rifle) vs the Tough(3) model of Def — unit of [1]: hits on 4+, Stealth -1, Good Shot +1, no cover of its own, saves on 4+"), "{lines:?}");
        assert!(lines.iter().any(|l| l == "Takedown (Rifle): the Tough(3) model of Def is wounded"), "{lines:?}");
        assert!(lines.iter().all(|l| !l.starts_with("Def takes")), "Takedown wounds must not emit a takes-wounds line: {lines:?}");
    }
