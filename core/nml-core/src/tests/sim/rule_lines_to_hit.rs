use super::*;
use super::volley_landings::volley_line;
use crate::unit::ShotModNote;

    // ---- Door rule lines (lane dlines train 4, DS-GHITN): to-hit note and Takedown ----

    fn rule_lines(tune: impl FnOnce(&mut State, &mut [UnitStatic]), faces: Vec<Vec<u8>>) -> Vec<String> {
        rule_lines_as(HOLD, None, tune, faces)
    }

    /// `rule_lines` for an activation of `kind` (an ADVANCE with a `dest` moves the shooter: its weapons shoot "after moving").
    fn rule_lines_as(kind: i64, dest: Option<[f64; 3]>, tune: impl FnOnce(&mut State, &mut [UnitStatic]), faces: Vec<Vec<u8>>) -> Vec<String> {
        let (mut st, mut statics) = volley_line();
        st.player = vec![1, 1, 0, 0];
        st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
        (statics[0].name, statics[2].name, statics[0].shoot[0].name) = ("Att".into(), "Def".into(), "Rifle".into());
        statics[0].ctx.quality = 4;
        statics[0].ctx.rules_epoch = crate::acts::CURRENT_RULES_EPOCH;
        statics[2].ctx.rules_epoch = crate::acts::CURRENT_RULES_EPOCH;
        tune(&mut st, &mut statics);
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, movement: dest.is_some(), moved_shoot: dest.is_some(), ..Seams::default() };
        let action = Action {
            kind, unit: "a".into(), dest, shoot: Some("b".into()), charge: None,
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

    /// The table's `_solo_unstoppable_fold` says its fold once per weapon with the same three shapes: a minus from another source swallowed, the
    /// shooter's own minus kept, both at once. A weapon's own Unstoppable used to stay silent in the core (the mark and aura say their own lines).
    #[test]
    fn a_weapons_own_unstoppable_names_its_fold_in_the_tables_three_shapes() {
        let said = |lines: &[String]| lines.iter().filter(|l| l.starts_with("Unstoppable:")).cloned().collect::<Vec<_>>();
        let faces = || vec![vec![6, 1, 1, 1], vec![1]];
        let swallowed = rule_lines(|st, s| {
            st.positions[2] = vec![[18.0 * IN2M, 0.0, 0.0]; 2];
            s[0].shoot[0].unstoppable = true;
            s[2].ctx.stealth = true;
        }, faces());
        assert_eq!(said(&swallowed), ["Unstoppable: negative to-hit modifiers ignored"], "{swallowed:?}");
        let plain = rule_lines(|st, s| {
            st.positions[2] = vec![[18.0 * IN2M, 0.0, 0.0]; 2];
            s[0].shoot[0].unstoppable = true;
        }, faces());
        assert!(said(&plain).is_empty(), "nothing to swallow, nothing said: {plain:?}");
        let near = rule_lines(|st, s| {
            st.positions[2] = vec![[6.0 * IN2M, 0.0, 0.0]; 2];
            s[0].shoot[0].unstoppable = true;
            s[2].ctx.stealth = true;
        }, faces());
        assert!(said(&near).is_empty(), "Stealth does not reach within 9\": {near:?}");
        let own_only = rule_lines(|st, s| {
            st.positions[2] = vec![[18.0 * IN2M, 0.0, 0.0]; 2];
            (s[0].ctx.v36_rules, s[0].shoot[0].unstoppable, s[0].shoot[0].hit_bonus) = (true, true, -1);
        }, faces());
        assert_eq!(said(&own_only), ["Unstoppable: own rules' -1 to hit kept"], "{own_only:?}");
        let both = rule_lines(|st, s| {
            st.positions[2] = vec![[18.0 * IN2M, 0.0, 0.0]; 2];
            (s[0].ctx.v36_rules, s[0].shoot[0].unstoppable, s[0].shoot[0].hit_bonus) = (true, true, -1);
            s[2].ctx.stealth = true;
        }, faces());
        assert_eq!(said(&both), ["Unstoppable: -1 to hit from other sources ignored, own rules' -1 kept"], "{both:?}");
        let none = rule_lines(|st, s| {
            st.positions[2] = vec![[18.0 * IN2M, 0.0, 0.0]; 2];
            s[2].ctx.stealth = true;
        }, faces());
        assert!(said(&none).is_empty(), "no Unstoppable, no fold line: {none:?}");
    }

    /// A shooter that moved says "Indirect: no moved penalty" in its to-hit note whenever the shot IS Indirect, and the table makes it
    /// one when the TARGET carries an Indirect mark (`_solo_bridge_granted_flags`: the marked shot is an Indirect profile, soak game 16:
    /// "Triangulation Bots"). RED: the core said it only for a weapon with its own Indirect, so the marked shot's note was left out.
    #[test]
    fn a_marks_indirect_names_the_moved_penalty_it_waives() {
        let mark = |st: &mut State| st.buffs[2].push(crate::mods::LiveMod {
            hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0, move_mod: 0, range_in: 0,
            grants_rule: Rc::from("Indirect"), scope: Rc::from(""), attackers: true, once: true, name: Rc::from("Triangulation Bots"),
        });
        let (faces, dest, note) = (|| vec![vec![6, 1, 1, 1], vec![1]], Some([6.0 * IN2M, 0.0, 0.0]), "To-hit vs Def: Indirect: no moved penalty → hits on 4+");
        let moved = rule_lines_as(ADVANCE, dest, |st, _| mark(st), faces());
        assert!(moved.iter().any(|l| l == note), "{moved:?}");
        let held = rule_lines(|st, _| mark(st), faces());
        assert!(held.iter().all(|l| !l.starts_with("To-hit vs")), "a shooter that did not move has no penalty to waive: {held:?}");
        let unmarked = rule_lines_as(ADVANCE, dest, |_, _| {}, faces());
        assert!(unmarked.iter().all(|l| !l.starts_with("To-hit vs")), "no Indirect, no note: {unmarked:?}");
    }
