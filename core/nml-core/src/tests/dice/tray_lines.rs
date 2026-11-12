use super::*;
use crate::logline::{Category, LogLine};

    fn line(text: &str) -> LogLine {
        LogLine { rule: "test", category: Category::Combat, side: 0, text: text.into(), detail: None }
    }

    /// A seeded tray (training, self-play) keeps no line and never formats one.
    #[test]
    fn a_seeded_tray_keeps_no_line() {
        let mut t = Tray::seeded(7);
        let mut formatted = false;
        t.say(|| { formatted = true; line("A") });
        t.roll(1);
        assert!(!formatted, "a seeded tray must not format a line");
        assert!(t.all_lines().is_empty());
    }

    /// `lines_upto(2)`: what a step starved at roll 2 may show (C read 1s).
    #[test]
    fn a_supplied_tray_stamps_lines_by_draw() {
        let mut t = Tray::supplied(vec![vec![1], vec![2]]);
        t.say(|| line("A"));
        t.roll(1);
        t.say(|| line("B"));
        t.roll(1);
        t.roll(1);
        assert_eq!(t.feed().and_then(|f| f.starved_at), Some((2, 1)), "starves at roll 2");
        t.say(|| line("C"));
        assert_eq!(t.lines_upto(2), vec![line("A"), line("B")]);
        assert_eq!(t.lines_upto(1), vec![line("A"), line("B")], "B said at draw 1 counts");
        assert_eq!(t.all_lines(), vec![line("A"), line("B"), line("C")]);
    }
