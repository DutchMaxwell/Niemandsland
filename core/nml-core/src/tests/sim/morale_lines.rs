use super::*;
use super::save_lines::att_def;
use crate::logline::Category;

    // ---- One-core P3 step 26: the core says the table's morale outcome lines, byte for byte ----

    /// Step 23's plain volley with Def at Quality 4+: 7 failed saves leave it at 3/10, so it tests morale. After
    /// the morale die (stamp 3) the table's outcome line (`_solo_morale_test`'s match, main.gd:13170-13184), as
    /// step 23 pinned it for seed 57 (face 6) and seed 0 (face 3). RED: drop the em dash and the Shaken case fails.
    #[test]
    fn a_supplied_volley_says_the_tables_morale_line() {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let action = Action {
            kind: HOLD, unit: "a".into(), dest: None, shoot: Some("b".into()), charge: None,
            patient: false, split: None, traced: None, teleport: None,
        };
        for (face, said) in [(6, "Def passes morale"), (3, "Def fails morale — Shaken")] {
            let (st, mut statics) = att_def(10, 1);
            statics[2].ctx.quality = 4;
            let hit_faces: Vec<u8> = (0..10).map(|i| if i < 7 { 6 } else { 1 }).collect();
            let mut tray = Tray::supplied(vec![hit_faces, vec![1; 7], vec![face]]);
            let (after, _) = resolve_stochastic_tray_on_board(&statics, &st, &action, &Terrain::default(), seams,
                &mut GodotRng::new(0), &mut tray).unwrap();
            let feed = tray.feed().unwrap();
            assert_eq!((feed.draws(), feed.starved_at, after.shaken[2]), (3, None, face == 3), "fixture: one morale die");
            let all = tray.all_lines();
            assert_eq!(tray.lines_upto(2).len() + 1, all.len(), "{said}: said after the morale die, last: {all:?}");
            let l = all.last().unwrap();
            assert_eq!((l.rule, l.category, l.side, l.text.as_str(), l.detail.is_none()),
                ("morale", Category::Combat, 1, said, true));
        }
    }

    /// The melee-only Rout arm (main.gd:13181-13183): a failed melee test at half strength says ROUTS.
    #[test]
    fn a_failed_melee_test_at_half_strength_says_routs() {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let (mut st, mut statics) = att_def(5, 1);
        (statics[2].model_count, statics[2].ctx.quality) = (10, 4); // 5 of 10 left: at half
        let mut tray = Tray::supplied(vec![vec![3]]);
        tray_morale_for(&mut st, &statics, 2, true, true, None, seams, &mut tray, &mut ShootResult::default(), None, None);
        assert_eq!(st.alive[2], 0, "fixture: the unit routs");
        let texts: Vec<_> = tray.all_lines().into_iter().map(|l| (l.side, l.text)).collect();
        assert_eq!(texts, [(1, "Def fails morale at half strength — ROUTS".to_string())]);
    }

    // ---- The table's "gets +N to morale test rolls" line before the test die (`_solo_morale_test`) ----

    /// The words of the lines said before the morale die: `att_def`'s Def at 4+ with 10 models, 5 standing (the
    /// half-strength fixture of the Rout test above), a stamped bonus of `bonus` of which `rating` is the Morale(X)
    /// rating, the Banner family named `family`; one die of `face` decides the test.
    fn lines_before_the_die(bonus: i64, rating: i64, family: &str, shaken: bool, face: u8) -> Vec<String> {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let (mut st, mut statics) = att_def(5, 1);
        (statics[2].model_count, statics[2].ctx.quality, statics[2].ctx.morale_rating) = (10, 4, rating);
        statics[2].morale_family = family.into();
        (st.morale_bonus[2], st.shaken[2]) = (bonus, shaken);
        let mut tray = Tray::supplied(if shaken { vec![] } else { vec![vec![face]] });
        tray_morale_for(&mut st, &statics, 2, true, true, None, seams, &mut tray, &mut ShootResult::default(), None, None);
        // A Shaken unit draws no die, so its outcome line shares the stamp: keep only the bonus line.
        tray.lines_upto(0).into_iter().map(|l| l.text).filter(|t| t.contains("to morale test rolls")).collect()
    }

    /// RED on main: nothing is said before the die. A plain Banner names itself, the target is the die's own (4+, +1 = 3+).
    #[test]
    fn a_banner_unit_says_the_tables_morale_line_before_the_die() {
        assert_eq!(lines_before_the_die(1, 0, "", false, 6), ["Banner: Def gets +1 to morale test rolls (passes on 3+)"]);
    }

    /// Morale(X) names the rating; a family bonus on top names both, joined by " + ", the family as the registry spells it.
    #[test]
    fn morale_x_and_a_banner_family_name_themselves_in_the_line() {
        assert_eq!(lines_before_the_die(2, 2, "", false, 6), ["Morale(2): Def gets +2 to morale test rolls (passes on 2+)"]);
        assert_eq!(lines_before_the_die(3, 2, "Hold the Line", false, 6),
            ["Morale(2) + Hold the Line: Def gets +3 to morale test rolls (passes on 2+)"]);
        assert_eq!(lines_before_the_die(1, 0, "Hold the Line", false, 6), ["Hold the Line: Def gets +1 to morale test rolls (passes on 3+)"]);
    }

    /// No bonus, no line; a Shaken unit rolls no die and the table writes no such line either.
    #[test]
    fn no_bonus_or_a_shaken_unit_says_no_bonus_line() {
        assert!(lines_before_the_die(0, 0, "", false, 6).is_empty());
        assert!(lines_before_the_die(2, 2, "", true, 6).is_empty());
    }

    /// A rule-forced test takes the Banner share back out (rules 3.6): the bonus the line names is what is left, so a
    /// plain Banner on a Dangerous-terrain test says no line (the table's `morale_bonus > 0` guard), the rating stays.
    #[test]
    fn a_rule_forced_test_names_only_what_is_left_of_the_bonus() {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let say = |bonus: i64, rating: i64| {
            let (mut st, mut statics) = att_def(5, 1);
            (statics[2].model_count, statics[2].ctx.quality, statics[2].ctx.morale_rating) = (10, 4, rating);
            st.morale_bonus[2] = bonus;
            let mut tray = Tray::supplied(vec![vec![6]]);
            tray_morale_for(&mut st, &statics, 2, false, true, Some("Dangerous terrain"), seams, &mut tray, &mut ShootResult::default(), None, None);
            tray.lines_upto(0).into_iter().map(|l| l.text).collect::<Vec<_>>()
        };
        assert!(say(1, 0).is_empty(), "the Banner's +1 does not help a rule-forced test, so there is nothing to name");
        assert_eq!(say(3, 2), ["Morale(2): Def gets +2 to morale test rolls (passes on 2+)"], "the rating stays, the Banner share goes");
    }

    /// No Retreat's self-wounds land before the table writes its outcome: "has No Retreat", the wounds and models it cost
    /// (`_solo_apply_wounds`), then "passes morale". The landing report that follows the test says them ahead of the outcome
    /// line; the landing itself is one record, unchanged. RED on main: the outcome came first and the wounds after it.
    #[test]
    fn no_retreat_self_wounds_are_said_ahead_of_the_outcome_line() {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let (mut st, mut statics) = att_def(5, 1);
        (statics[2].model_count, statics[2].ctx.quality, statics[2].ctx.no_retreat) = (10, 4, true);
        let mut tray = Tray::supplied(vec![vec![1], vec![1, 1, 6, 6, 6]]);
        let before = chain_snapshot(&st, 2, &tray);
        tray_morale_for(&mut st, &statics, 2, true, true, None, seams, &mut tray, &mut ShootResult::default(), None, None);
        land_chain_report(&statics, &st, &mut tray, 2, before);
        assert_eq!(st.alive[2], 3, "fixture: two self-wounds, two models down");
        let said: Vec<_> = tray.all_lines().into_iter().map(|l| l.text).collect();
        assert_eq!(said, [
            "Def has No Retreat — the test counts as passed; 2 self-wounds (1-3 on 5 dice, can't be ignored)",
            "Def takes 2 wounds (3/10)",
            "Def loses 2 models (3/10)",
            "Def passes morale",
        ]);
        assert_eq!(tray.all_landings().len(), 1);
    }

    /// A rout's removal follows the outcome line (the table: "ROUTS", then the wounds), and a landing report with no held
    /// outcome says its lines at the end as before.
    #[test]
    fn a_rout_is_still_said_before_its_removal_lines() {
        let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
        let (mut st, mut statics) = att_def(5, 1);
        (statics[2].model_count, statics[2].ctx.quality) = (10, 4); // 5 of 10 left: at half
        let mut tray = Tray::supplied(vec![vec![1]]);
        let before = chain_snapshot(&st, 2, &tray);
        tray_morale_for(&mut st, &statics, 2, true, true, None, seams, &mut tray, &mut ShootResult::default(), None, None);
        land_chain_report(&statics, &st, &mut tray, 2, before);
        let said: Vec<_> = tray.all_lines().into_iter().map(|l| l.text).collect();
        assert_eq!(said.first().map(String::as_str), Some("Def fails morale at half strength — ROUTS"), "{said:?}");
        assert!(said[1..].iter().all(|t| t.starts_with("Def ")), "{said:?}");
    }
