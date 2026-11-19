use super::*;
use super::save_lines::att_def;
use crate::mods::LiveMod;

    // ---- Door rule lines (lane dlines, PR 4): the lines of the table's `_solo_morale_test` that only the core's ledger had ----

    fn token(name: &str, morale_mod: i64) -> LiveMod {
        LiveMod {
            hit_mod: 0, casting_mod: 0, morale_mod, ap_mod: 0, def_mod: 0, defense_mod: 0, move_mod: 0, grants_rule: Rc::from(""),
            scope: Rc::from(""), attackers: false, once: true, name: Rc::from(name),
        }
    }

    /// The lines said before the morale die for `att_def`'s Def (Quality 4, ten models, five standing: the half-strength fixture) with
    /// `bonus` stamped as its Banner share (`valiant` of it Valiant), `tokens` live, tested for `cause` / at `over_in`; one die decides.
    fn before_the_die(bonus: i64, valiant: i64, tokens: Vec<LiveMod>, cause: Option<&str>, over_in: Option<f64>, hero: bool) -> Vec<String> {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, hero_attach: hero, ..Seams::default() };
        let (mut st, mut statics) = att_def(5, 1);
        (statics[2].model_count, statics[2].ctx.quality, statics[2].quality, statics[2].ctx.valiant_bonus) = (10, 4, 4, valiant);
        st.morale_bonus[2] = bonus;
        st.buffs[2].extend(tokens);
        if hero {
            (st.attached, st.attached_to) = (Rc::new(vec![vec![], vec![], vec![3], vec![]]), Rc::new(vec![None, None, None, Some(2)]));
            (st.alive[3], statics[3].quality) = (1, 3);
        }
        let mut tray = Tray::supplied(vec![vec![6]]);
        tray_morale_for(&mut st, &statics, 2, false, true, cause, seams, &mut tray, &mut ShootResult::default(), over_in, None);
        tray.lines_upto(0).into_iter().map(|l| l.text).collect()
    }

    /// A rule-forced test names the Banner share it takes back out, and a Great Banner token it leaves out (the table's two lines).
    #[test]
    fn a_rule_forced_test_names_the_banner_and_great_banner_it_drops() {
        let lines = before_the_die(1, 0, vec![token("Great Banner", 1)], Some("Dangerous terrain"), None, false);
        assert_eq!(lines, [
            "Banner: Def gets no +1 against Dangerous terrain (only shooting or melee)",
            "Great Banner: Def gets no +1 against Dangerous terrain (only shooting or melee)",
        ]);
    }

    /// Inside the Valiant band the Valiant share comes out and says so; the charge the unit made itself says why.
    #[test]
    fn a_valiant_share_taken_back_names_the_band_or_the_own_charge() {
        let band = before_the_die(1, 1, vec![], None, Some(5.0), false);
        assert_eq!(band, ["Banner: Def gets no +1 from a shot at 9\" or under (Valiant counts only beyond the gate)"]);
        let outside = before_the_die(1, 1, vec![], None, Some(12.0), false);
        assert_eq!(outside, ["Banner: Def gets +1 to morale test rolls (passes on 3+)"], "beyond the gate the Valiant share stays");
    }

    /// A live spell token names itself and the target (the table's "<spell> +1: +1 to morale test rolls - <U> passes on N+" line).
    #[test]
    fn a_spell_token_names_its_morale_bonus() {
        assert_eq!(before_the_die(0, 0, vec![token("Bless", 1), token("Doom", -1), token("Boon", 2)], None, None, false),
            ["Bless +1, Doom -1, Boon +2: +2 to morale test rolls — Def passes on 2+"]);
        assert!(before_the_die(0, 0, vec![token("Bless", 1), token("Doom", -1)], None, None, false).is_empty(), "a zero net says nothing");
    }

    /// A joined Hero with the better Quality tests on the unit's behalf, and says so once; a unit with no better Hero says nothing.
    #[test]
    fn a_joined_hero_names_the_quality_it_lends() {
        assert_eq!(before_the_die(0, 0, vec![], None, None, true), ["Hero bh tests on behalf of Def (Q3+)"]);
        assert!(before_the_die(0, 0, vec![], None, None, false).is_empty());
    }

    /// The Mind Control family's morale test (`control_morale_passed`) says the same bonus line, cause line and Hero line.
    #[test]
    fn the_mind_control_test_says_its_bonus_and_cause_lines() {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let (mut st, mut statics) = att_def(5, 1);
        (statics[2].model_count, statics[2].ctx.quality, statics[2].quality, statics[2].ctx.morale_rating) = (10, 4, 4, 1);
        (st.morale_bonus[2], statics[2].morale_family) = (2, "Banner".into());
        let mut tray = Tray::supplied(vec![vec![6]]);
        control_morale_passed(&statics, &mut st, 2, ControlMoraleSource { owner: "Def", rule: "Mind Control" }, seams, &mut tray, &mut ShootResult::default());
        let lines: Vec<String> = tray.lines_upto(0).into_iter().map(|l| l.text).collect();
        assert_eq!(lines, [
            "Banner: Def gets no +1 against Mind Control (only shooting or melee)",
            "Morale(1): Def gets +1 to morale test rolls (passes on 3+)",
        ]);
    }

    /// The Hero aura (rules 3.6): a free friendly Tough(9)+ Hero within 6" with the better Quality lends it, and the line says so.
    #[test]
    fn the_hero_aura_names_the_lender() {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let (mut st, mut statics) = att_def(5, 1);
        (statics[2].model_count, statics[2].ctx.quality, statics[2].quality) = (10, 4, 4);
        st.positions[3] = vec![[12.0 * IN2M, 0.0, -3.0 * IN2M]];
        (st.alive[3], st.wounds[3], st.player[3]) = (1, vec![9], 1);
        Rc::make_mut(&mut st.radii)[3] = vec![IN2M];
        (statics[3].is_hero, statics[3].ctx.tough, statics[3].quality, statics[3].name) = (true, 9, 2, "Champion".into());
        let mut tray = Tray::supplied(vec![vec![6]]);
        tray_morale_for(&mut st, &statics, 2, false, true, None, seams, &mut tray, &mut ShootResult::default(), None, None);
        let lines: Vec<String> = tray.lines_upto(0).into_iter().map(|l| l.text).collect();
        assert_eq!(lines, ["Champion (Tough 9+) lends its Quality to Def's morale test (Q2+)"]);
    }

    /// A lone hero's test (its host has no model left, the hero lives) is its host's in the table's log: every morale line names the host,
    /// the Hero who lends the Quality tests "on behalf of" it, and the outcome says the host fails.
    #[test]
    fn a_lone_heros_morale_test_names_its_host() {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, hero_attach: true, ..Seams::default() };
        let (mut st, mut statics) = att_def(5, 1);
        (statics[2].name, statics[3].name) = ("Cultists".into(), "Champion".into());
        (statics[2].model_count, statics[2].quality, statics[2].ctx.quality, statics[3].quality) = (10, 4, 4, 3);
        (st.positions[2], st.wounds[2], st.alive[2]) = (vec![], vec![], 0);
        (st.attached, st.attached_to) = (Rc::new(vec![vec![], vec![], vec![3], vec![]]), Rc::new(vec![None, None, None, Some(2)]));
        (st.alive[3], st.morale_bonus[3]) = (1, 1);
        let mut tray = Tray::supplied(vec![vec![1]]);
        tray_morale_for(&mut st, &statics, 3, false, true, None, seams, &mut tray, &mut ShootResult::default(), None, None);
        let lines: Vec<String> = tray.all_lines().into_iter().map(|l| l.text).collect();
        assert_eq!(lines, [
            "Hero Champion tests on behalf of Cultists (Q3+)",
            "Banner: Cultists gets +1 to morale test rolls (passes on 2+)",
            "Cultists fails morale — Shaken",
        ], "{lines:?}");
    }
