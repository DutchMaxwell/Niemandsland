use super::*;

    // ------ The morale dice say the table's kinds and lines (`main._solo_morale_test`) ------
    //
    // After a failed test the table rolls the Fearless recovery die as kind "fearless" and writes
    // "<unit> is Fearless — recovery die (4+) holds|fails"; the No Retreat self-wound dice are kind "no_retreat"
    // and the table writes "<unit> has No Retreat — the test counts as passed; N self-wound(s) (1-3 on D dice,
    // can't be ignored)". The roll RECORDS keep the replay's "attack" kind: only the step's kind label and the
    // lines are the table's words. Every draw and every outcome below is the one the unnamed core already made.

    fn texts(tray: &Tray) -> Vec<String> {
        tray.all_lines().into_iter().map(|l| l.text).collect()
    }

    fn kinds(tray: &Tray, draws: usize) -> Vec<Option<&'static str>> {
        (0..draws).map(|i| tray.feed().unwrap().kind_of(i)).collect()
    }

    /// RED on main: the recovery die carries no kind name (the step asks for "attack") and says nothing.
    #[test]
    fn a_fearless_recovery_die_that_holds_says_the_tables_line_and_kind() {
        let unit = Ctx { quality: 4, fearless: true, side: 2, ..Default::default() };
        let mut tray = Tray::supplied(vec![vec![1], vec![5]]);
        let (res, out) = resolve_morale_with_tray(&unit, "Unit", None, true, false, false, 4, &mut tray);
        assert_eq!(res, Morale::Passed, "the 4+ die rescues the failed test");
        assert_eq!(texts(&tray), ["Unit is Fearless — recovery die (4+) holds"]);
        let l = &tray.all_lines()[0];
        assert_eq!((l.rule, l.category, l.side, l.detail.is_none()), ("morale", Category::Combat, 2, true));
        assert_eq!(kinds(&tray, 2), [Some("morale"), Some("fearless")]);
        assert_eq!(out.rolls.iter().map(|r| (r.kind, r.target)).collect::<Vec<_>>(), [("attack", 4), ("attack", 4)], "the records keep the replay's kind");
    }

    #[test]
    fn a_fearless_recovery_die_that_fails_says_the_tables_line() {
        let unit = Ctx { quality: 4, fearless: true, side: 1, ..Default::default() };
        let mut tray = Tray::supplied(vec![vec![1], vec![2]]);
        let (res, _) = resolve_morale_with_tray(&unit, "Unit", None, true, false, false, 4, &mut tray);
        assert_eq!(res, Morale::Shaken, "the recovery die fails too");
        assert_eq!(texts(&tray), ["Unit is Fearless — recovery die (4+) fails"]);
        assert_eq!(tray.all_lines()[0].side, 1);
    }

    /// A test that passes draws no recovery die and says nothing about Fearless.
    #[test]
    fn a_passed_test_says_nothing_about_fearless() {
        let unit = Ctx { quality: 4, fearless: true, ..Default::default() };
        let mut tray = Tray::supplied(vec![vec![6]]);
        let (res, _) = resolve_morale_with_tray(&unit, "Unit", None, true, false, false, 4, &mut tray);
        assert_eq!(res, Morale::Passed);
        assert!(texts(&tray).is_empty());
    }

    /// RED on main: no kind name and no line. Zero and one self-wound read as the table's plural rule.
    #[test]
    fn no_retreat_says_the_tables_line_and_kind() {
        let unit = Ctx { quality: 4, no_retreat: true, side: 2, ..Default::default() };
        for (faces, said) in [
            (vec![2u8], "Unit has No Retreat — the test counts as passed; 1 self-wound (1-3 on 1 dice, can't be ignored)"),
            (vec![6u8], "Unit has No Retreat — the test counts as passed; 0 self-wounds (1-3 on 1 dice, can't be ignored)"),
        ] {
            let mut tray = Tray::supplied(vec![faces]);
            let (res, _) = resolve_morale_with_tray(&unit, "Unit", None, true, false, true, 1, &mut tray);
            assert_eq!(res, Morale::Passed);
            assert_eq!(texts(&tray), [said]);
            assert_eq!(kinds(&tray, 1), [Some("no_retreat")], "a Shaken unit draws no test die: the self-wound dice come first");
        }
    }

    /// Both rules on one unit: the table's order is the test die, the recovery die, ITS line, the self-wound dice, THEIR
    /// line. The Fearless line is said before the third draw, the No Retreat line after it.
    #[test]
    fn fearless_then_no_retreat_keep_the_tables_order() {
        let unit = Ctx { quality: 4, fearless: true, no_retreat: true, side: 1, ..Default::default() };
        let mut tray = Tray::supplied(vec![vec![1], vec![2], vec![1, 5, 2]]);
        let (res, out) = resolve_morale_with_tray(&unit, "Unit", None, true, false, false, 3, &mut tray);
        assert_eq!((res, out.wounds), (Morale::Passed, 2));
        assert_eq!(texts(&tray), [
            "Unit is Fearless — recovery die (4+) fails",
            "Unit has No Retreat — the test counts as passed; 2 self-wounds (1-3 on 3 dice, can't be ignored)",
        ]);
        assert_eq!(tray.lines_upto(2).len(), 1, "the Fearless line stands before the self-wound dice");
        assert_eq!(kinds(&tray, 3), [Some("morale"), Some("fearless"), Some("no_retreat")]);
    }
