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

    // ------------- D21 to-hit half: Thrust / Versatile / Precise fold into the SAME sum ---------

    /// Q2 Thrust charge vs Evasive: 2 - 1 (Thrust) + 1 (Evasive) = 2+. The old ladder floored Thrust at 2+
    /// before the Evasive penalty and hit on 3+.
    #[test]
    fn q2_thrust_charge_vs_evasive_hits_on_2_from_epoch_68() {
        let att = Ctx { quality: 2, ..Default::default() };
        let p = ShootProfile { thrust: true, ..blade(1) };
        let old = Ctx { evasive: true, ..defender(4, 5) };
        let new = Ctx { modifier_sum: true, ..old };
        assert_eq!(melee_hit_target(&p, &att, &old, true, 0, 0.0, false).0, 3, "below the gate: the Thrust floors at 2+");
        assert_eq!(melee_hit_target(&p, &att, &new, true, 0, 0.0, false).0, 2, "from the gate: one sum");
    }

    /// Q5 vs Artillery + Stealth over 9" with a latched Versatile +1: 5 + 2 - 1 = 6+. The old ladder clamped the
    /// -2 to 6+ first and the +1 then walked it back to 5+.
    #[test]
    fn versatile_plus_one_folds_into_the_sum_from_epoch_68() {
        let p = ShootProfile { versatile_attack: true, ..rifle(10) };
        let att = Ctx { quality: 5, versatile_latched: true, versatile_pick_hit: 1, ..Default::default() };
        let old = Ctx { stealth: true, artillery: true, ..defender(4, 5) };
        let new = Ctx { modifier_sum: true, ..old };
        let attack_target = |def: &Ctx| {
            let mut tray = Tray::seeded(27);
            let out = resolve_shooting_with_tray(&[p.clone()], &[0], &[10], &att, def, 12.0, &mut tray);
            out.rolls.iter().find(|r| r.kind == "attack").expect("attack roll").target
        };
        assert_eq!(attack_target(&old), 5, "below the gate: clamp to 6+, then Versatile walks it back to 5+");
        assert_eq!(attack_target(&new), 6, "from the gate: 5 + 2 - 1 = 6+");
    }
