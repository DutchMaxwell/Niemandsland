use super::*;
use crate::landing::{LandedModel, Landing};

    fn landing(unit: usize) -> Landing {
        Landing { unit, models: vec![LandedModel { at: [unit as f64, 0.0, 0.0], wounds_left: 1, dead: false }], loss_line: false }
    }

    /// A seeded tray (training, self-play) keeps no landing and never builds one.
    #[test]
    fn a_seeded_tray_keeps_no_landing() {
        let mut t = Tray::seeded(7);
        let mut built = false;
        t.land(|| { built = true; landing(0) });
        t.roll(1);
        assert!(!built, "a seeded tray must not build a landing");
        assert!(t.all_landings().is_empty());
    }

    /// `landings_upto(2)`: what a step starved at roll 2 may show (C read 1s).
    #[test]
    fn a_supplied_tray_stamps_landings_by_draw() {
        let mut t = Tray::supplied(vec![vec![1], vec![2]]);
        t.land(|| landing(0));
        t.roll(1);
        t.land(|| landing(1));
        t.roll(1);
        t.roll(1);
        assert_eq!(t.feed().and_then(|f| f.starved_at), Some((2, 1)), "starves at roll 2");
        t.land(|| landing(2));
        assert_eq!(t.landings_upto(2), vec![landing(0), landing(1)]);
        assert_eq!(t.landings_upto(1), vec![landing(0), landing(1)], "B landed at draw 1 counts");
        assert_eq!(t.all_landings(), vec![landing(0), landing(1), landing(2)]);
    }
