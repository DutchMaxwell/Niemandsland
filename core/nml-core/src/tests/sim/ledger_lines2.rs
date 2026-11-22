use super::*;
use super::volley_landings::volley_line;
use crate::unit::ShieldedAlias;

    // ---- Coverage ledger 2, AI shoot door (lane covfix2-lines, 22.11.): lines and labels only - no die, target or end state moves ----

    /// The lines one HOLD volley of `Att`'s `Rifle` (4 attacks, Quality 2+) at `Def` (two Tough(3) models, Defense 4+) says on the supplied
    /// faces at the current epoch; `tune` edits the state and the statics (0 = Att, 2 = Def) first.
    fn lines_of(tune: impl FnOnce(&mut State, &mut [UnitStatic]), faces: Vec<Vec<u8>>) -> Vec<String> {
        let (mut st, mut statics) = volley_line();
        st.player = vec![1, 1, 0, 0];
        st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
        (statics[0].name, statics[2].name, statics[0].shoot[0].name) = ("Att".into(), "Def".into(), "Rifle".into());
        statics[0].ctx.rules_epoch = crate::acts::CURRENT_RULES_EPOCH;
        statics[2].ctx.rules_epoch = crate::acts::CURRENT_RULES_EPOCH;
        tune(&mut st, &mut statics);
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, sighting: true, ..Seams::default() };
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        let mut tray = Tray::supplied(faces);
        resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut tray).unwrap();
        tray.all_lines().into_iter().map(|l| l.text).collect()
    }

    fn pos(lines: &[String], text: &str) -> usize {
        lines.iter().position(|l| l == text).unwrap_or_else(|| panic!("no line {text:?} in {lines:?}"))
    }

    /// Ledger 1b (4 cells: Strafing): a unit with no ready ranged weapon at all (every Limited one spent here) says the table's other no-volley sentence;
    /// the core was silent. (The out-of-reach volley, whose sentence the pending epoch 96 writes, is the dice lane's: it spends state at 95.)
    #[test]
    fn a_unit_with_no_ready_ranged_weapon_says_no_volley() {
        let spent = lines_of(|st, s| { s[0].shoot[0].limited = true; Rc::make_mut(&mut st.limited_used)[0].push("Rifle".into()); }, vec![]);
        assert!(spent.iter().any(|l| l == "Att: no volley — no ready ranged weapon — the unit holds") && !spent.iter().any(|l| l.contains("fires")), "{spent:?}");
        let ready = lines_of(|_, _| {}, vec![vec![6; 4], vec![1; 4]]);
        assert!(ready.iter().any(|l| l == "Att fires at Def") && !ready.iter().any(|l| l.contains("no volley")), "{ready:?}");
    }

    /// COV-D1 lines (6 cells): the once-per-game Protection Feat's ignore roll names its rule like the table's group line (its spend line is the door's, said after the volley: an order gap left open). RED on main: the die was unnamed.
    #[test]
    fn the_protection_feat_names_its_ignore_roll() {
        let def = Ctx { regeneration: true, regen_target: 5, regen_feat: 5, regen_pending_notes: ["", "", "", "Protection Feat"], ..Default::default() };
        let mut tray = Tray::supplied(vec![vec![6, 1]]);
        crate::dice::ignore_batch(2, 0, 0, &def, "Def", &mut tray, &mut Vec::new());
        let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
        assert_eq!(lines, ["Def rolls 2 Protection Feat dice (5+) — 1 wound ignored"]);
    }

    /// Ledger 2 (12 cells: Enhanced Sturdy and its Aura): the table's last Defense-part line says the Boost replaces Sturdy. RED on main: no line.
    #[test]
    fn enhanced_sturdy_says_it_replaces_sturdy() {
        let boost = |st: &mut State, s: &mut [UnitStatic]| {
            let _ = st;
            let c = &mut s[2].ctx;
            (c.shielded, c.shielded_alias, c.sturdy_boost_gates_guarded, c.guarded, c.guarded_name, c.v36_rules) = (true, ShieldedAlias::SturdyBoost, true, true, "Sturdy", true);
        };
        let said = "Enhanced Sturdy: replaces Sturdy — +1 Defense at any range, no extra +1 from over 9\"";
        let lines = lines_of(boost, vec![vec![6; 4], vec![1; 4]]);
        assert_eq!(lines.iter().filter(|l| **l == said).count(), 1, "{lines:?}");
        assert!(pos(&lines, "Def is Enhanced Sturdy: +1 Defense (saves on 3+)") < pos(&lines, said) && pos(&lines, said) < pos(&lines, "Att fires at Def"), "{lines:?}");
        let lone = lines_of(|st, s| { boost(st, s); s[2].ctx.guarded = false; s[2].ctx.guarded_name = ""; }, vec![vec![6; 4], vec![1; 4]]);
        assert!(!lone.iter().any(|l| l == said), "the Boost without a Sturdy to replace says nothing: {lone:?}");
    }

    /// Ledger 6 / COV-L2 (10 cells): a Deadly(X) wound that skips Regeneration counts the X wounds it deals - the table's ignore step runs once per
    /// unsaved wound over the multiplied count; the core said the raw hit count ("1 wound"). The dice are untouched. RED on main: "1 wound".
    #[test]
    fn a_deadly_wound_that_skips_regeneration_counts_its_x_wounds() {
        let bane_deadly = |_: &mut State, s: &mut [UnitStatic]| {
            let p = &mut s[0].shoot[0];
            (p.deadly, p.bane, p.bypass_regen) = (3, true, true);
            let c = &mut s[2].ctx;
            (c.playtest_rules, c.regeneration, c.regen_target, c.regen_named, c.v36_rules) = (true, true, 5, true, true);
        };
        let lines = lines_of(bane_deadly, vec![vec![6, 1, 1, 1], vec![1], vec![1; 3]]);
        assert!(lines.iter().any(|l| l == "Def: 3 wounds ignore Regeneration — no regeneration roll"), "{lines:?}");
        assert!(!lines.iter().any(|l| l.contains("1 wound ignore")), "{lines:?}");
    }

    /// Ledger 7 (Relentless Mark): a Mark's Relentless names its source and the marked unit, like the table. RED on main: no line for a grant.
    #[test]
    fn a_relentless_mark_names_its_source() {
        let mark = |st: &mut State, s: &mut [UnitStatic]| {
            st.positions[2] = vec![[12.0 * IN2M, 0.0, 0.0], [12.0 * IN2M, 0.0, 2.5 * IN2M]];
            st.buffs[2].push(crate::mods::LiveMod {
                hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0, move_mod: 0, range_in: 0,
                grants_rule: Rc::from("Relentless"), scope: Rc::from(""), attackers: true, once: true, name: Rc::from("Relentless Mark"),
            });
            s[0].ctx.rules_epoch = crate::acts::CURRENT_RULES_EPOCH;
        };
        // over 9": 12" away; 6, 6 hit and add two hits, the 1s miss
        let lines = lines_of(mark, vec![vec![6, 6, 1, 1], vec![1; 6]]);
        assert!(lines.iter().any(|l| l == "Relentless: +2 hits (unmodified 6s) — from Relentless Mark on Def"), "{lines:?}");
        // the core places most Marks on the shooter itself: the same source line
        let own = |st: &mut State, s: &mut [UnitStatic]| {
            mark(st, s);
            let r = st.buffs[2].pop().unwrap();
            st.buffs[0].push(crate::mods::LiveMod { attackers: false, ..r });
        };
        let lines = lines_of(own, vec![vec![6, 6, 1, 1], vec![1; 6]]);
        assert!(lines.iter().any(|l| l == "Relentless: +2 hits (unmodified 6s) — from Relentless Mark on Def"), "{lines:?}");
    }

    /// Ledger 7 (Piercing Feat / Piercing Mark): the table says the AP it adds, after the volley's hit line and before the saves. RED on main: silent.
    #[test]
    fn the_piercing_feat_and_mark_say_their_ap() {
        let lines = lines_of(|_, s| s[0].piercing_feat_ap = 1, vec![vec![6; 4], vec![1; 4]]);
        assert!(pos(&lines, "Att fires Rifle at Def — 4 hits") < pos(&lines, "Piercing Feat: AP(+1) against Def"), "{lines:?}");
        let mark = |st: &mut State, _: &mut [UnitStatic]| st.buffs[0].push(crate::mods::LiveMod {
            hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod: 0, defense_mod: 0, move_mod: 0, range_in: 0,
            grants_rule: Rc::from("AP(+1) when shooting"), scope: Rc::from(""), attackers: false, once: true, name: Rc::from("Piercing Mark"),
        });
        let lines = lines_of(mark, vec![vec![6; 4], vec![1; 4]]);
        assert!(lines.iter().any(|l| l == "Piercing Mark: friendly attackers get AP(+1) against Def (once)"), "{lines:?}");
    }

    /// Ledger 4 (6 cells: Hazardous): the table wounds the firer right after the hit roll, ahead of the "fires" line; the core did it after the saves.
    /// RED on main: the Hazardous line stood behind the volley's saves.
    #[test]
    fn hazardous_wounds_the_firer_before_the_fires_line() {
        let hazardous = |st: &mut State, s: &mut [UnitStatic]| {
            s[0].shoot[0].hazardous = true;
            st.wounds[0] = vec![3];
            st.kits = vec![Rc::new(vec![crate::state::Kit { weapons: vec![0], equipment: 0, wounds_max: 3 }]), Rc::new(vec![]), Rc::new(vec![]), Rc::new(vec![])];
            st.kit_names = vec![Rc::new(vec!["Rifle".into()]), Rc::new(vec![]), Rc::new(vec![]), Rc::new(vec![])];
        };
        // the 1 in the hit roll is a Hazardous 1 and the one model carries the rifle
        let lines = lines_of(hazardous, vec![vec![6, 6, 6, 1], vec![1; 3]]);
        let said = lines.iter().position(|l| l.starts_with("Hazardous:")).unwrap_or_else(|| panic!("{lines:?}"));
        assert!(said < pos(&lines, "Att fires Rifle at Def — 3 hits"), "{lines:?}");
        assert!(said > pos(&lines, "Att fires at Def"), "{lines:?}");
    }

    /// Ledger 3 (6 cells): a moved shooter whose Indirect sight waiver needs a Hold says so before the volley, as the table's note does.
    /// RED on main: the core only traced it.
    #[test]
    fn a_moved_indirect_shooter_says_it_did_not_hold() {
        let lines_for = |alias: bool| {
            let (mut st, mut statics) = volley_line();
            st.player = vec![1, 1, 0, 0];
            st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
            (statics[0].name, statics[2].name, statics[0].shoot[0].name) = ("Att".into(), "Def".into(), "Rifle".into());
            (statics[0].shoot[0].indirect, statics[0].shoot[0].indirect_los_needs_hold, statics[0].shoot[0].indirect_alias) = (true, true, alias);
            statics[0].ctx.rules_epoch = crate::acts::CURRENT_RULES_EPOCH;
            let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, sighting: true, ..Seams::default() };
            let action = Action {
                kind: ADVANCE, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
                patient: false, split: None, traced: None, teleport: None,
            };
            let mut tray = Tray::supplied(vec![vec![6; 4], vec![1; 4]]);
            resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams, &mut GodotRng::new(0), &mut tray).unwrap();
            tray.all_lines().into_iter().map(|l| l.text).collect::<Vec<_>>()
        };
        let note = "Indirect: Att did not Hold — its Indirect weapons need line of sight";
        let lines = lines_for(false);
        assert!(pos(&lines, note) < pos(&lines, "Att fires at Def"), "{lines:?}");
        // the unit-level "Indirect when Shooting" stamp is not a weapon's own Indirect: the table's note does not count it
        let alias = lines_for(true);
        assert!(!alias.iter().any(|l| l == note), "{alias:?}");
    }

    /// Ledger 7 (Relentless Mark, 5 cells with a morale test): the table says a Mark's consumption AFTER the volley's morale test; the core said it
    /// right after the landing. RED on main: the consumed line stood ahead of the morale lines.
    #[test]
    fn a_marks_consumption_is_said_after_the_volleys_morale_test() {
        let (st, mut statics) = super::surge_mark::surge_mark_line(crate::acts::CURRENT_RULES_EPOCH);
        (statics[0].name, statics[2].name) = ("Att".into(), "Def".into());
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let mut tray = Tray::supplied(vec![vec![4; 8], vec![1; 8], vec![4; 4], vec![4; 4]]);
        let _ = resolve_stochastic_tray_on_board(&statics, &st, &buff_action(Some("b")), &Terrain::default(), seams, &mut GodotRng::new(0), &mut tray);
        let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
        let spent = pos(&lines, "\"Surge Mark\" on Def is consumed (applies once)");
        let morale = lines.iter().rposition(|l| l.contains("morale")).unwrap_or_else(|| panic!("the fixture has a morale test: {lines:?}"));
        assert!(morale < spent, "{lines:?}");
    }
