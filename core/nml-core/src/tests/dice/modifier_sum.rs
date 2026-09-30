use super::*;

    // ------------- D21 (EPOCH_68_MODIFIER_SUM): one summed save target ---------

    /// The save die's target of a 12" AP(1) volley into `def`.
    fn save_target_of(def: &Ctx) -> i64 {
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(&[ap_rifle(10)], &[0], &[10], &shooter(2), def, 12.0, &mut tray);
        out.rolls.iter().find(|r| r.kind == "defense").expect("hits reach the save").target
    }

    /// GF p.5 MODIFIERS: Def 2+ in cover is 1, AP(1) brings it back to 2+. The
    /// old ladder floored the cover at 2+ first and saved on 3+.
    #[test]
    fn def_2_in_cover_vs_ap_1_saves_on_2_from_epoch_68() {
        let old = Ctx { in_cover: true, ..defender(2, 5) };
        let new = Ctx { modifier_sum: true, ..old };
        assert_eq!(save_target_of(&old), 3, "below the gate: the cover floors at 2+ before AP");
        assert_eq!(save_target_of(&new), 2, "from the gate: 2 - 1 + 1 = 2+");
    }

    /// The single clamp also holds the top: Def 6+ vs AP(2) is 8 -> a natural 6.
    #[test]
    fn the_sum_is_clamped_at_six_from_epoch_68() {
        let ap2 = ShootProfile { ap: 2, ..rifle(10) };
        let mut tray = Tray::seeded(27);
        let def = Ctx { modifier_sum: true, ..defender(6, 5) };
        let out = resolve_shooting_with_tray(&[ap2], &[0], &[10], &shooter(2), &def, 12.0, &mut tray);
        assert_eq!(out.rolls.iter().find(|r| r.kind == "defense").expect("save").target, 6);
    }

    /// Amendment B1: the stamp reads the RECORD's epoch — a record at 67 replays the old ladder even
    /// though the live build is 68.
    #[test]
    fn the_stamp_follows_the_records_epoch_not_the_live_one() {
        use crate::acts::EPOCH_68_MODIFIER_SUM;
        use crate::sim::with_modifier_sum;
        assert!(!with_modifier_sum(Ctx::default(), EPOCH_68_MODIFIER_SUM - 1).modifier_sum);
        assert!(with_modifier_sum(Ctx::default(), EPOCH_68_MODIFIER_SUM).modifier_sum);
    }
