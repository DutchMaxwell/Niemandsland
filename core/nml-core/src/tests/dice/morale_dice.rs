use super::*;

    // ------------------------------------------------ D1-B5b: the morale dice ---

    /// One test die at the Banner-modified Quality target, and Fearless's single
    /// recovery die as a SECOND batch after it (main.gd:8336 then :8347).
    #[test]
    fn a_morale_test_is_one_die_and_fearless_rolls_a_recovery_die() {
        let unit = Ctx { quality: 6, fearless: true, ..Default::default() };
        let mut tray = Tray::seeded(11);
        let (_, out) = resolve_morale_with_tray(&unit, "Unit", true, false, false, 4, &mut tray);
        assert_eq!(out.rolls[0].count, 1);
        assert_eq!(out.rolls[0].target, 6, "Quality 6+, no Banner");
        let failed = faces_to_hits(&out.rolls[0].faces, 6) == 0;
        assert_eq!(out.rolls.len(), if failed { 2 } else { 1 });
        if failed {
            assert_eq!(out.rolls[1].target, FEARLESS_RECOVER_TARGET, "the 4+ rescue die");
        }
    }

    /// An ALREADY Shaken unit fails automatically and draws NO die (:8310-8317).
    /// Burn one and every later activation of the game is on other faces.
    #[test]
    fn an_already_shaken_unit_fails_morale_without_drawing_a_die() {
        let unit = Ctx { quality: 4, ..Default::default() };
        let mut tray = Tray::seeded(5);
        let (res, out) = resolve_morale_with_tray(&unit, "Unit", true, true, true, 3, &mut tray);
        assert!(out.rolls.is_empty(), "no Quality roll for a Shaken unit");
        assert_eq!(res, Morale::Routed, "Shaken + at half + melee = Rout");
        assert_eq!(tray.state_i64(), Tray::seeded(5).state_i64(), "and not one draw spent");
    }

    /// ROUT is melee-only (p.10). The same failed test at half strength is a
    /// Rout in melee and only Shaken after shooting.
    #[test]
    fn only_a_melee_test_can_rout() {
        let unit = Ctx { quality: 4, ..Default::default() };
        let melee = resolve_morale_with_tray(&unit, "U", true, true, true, 2, &mut Tray::seeded(1));
        let shot = resolve_morale_with_tray(&unit, "U", false, true, true, 2, &mut Tray::seeded(1));
        assert_eq!(melee.0, Morale::Routed);
        assert_eq!(shot.0, Morale::Shaken);
    }

    /// No Retreat turns the still-failed test into a PASS and pays for it in
    /// self-wounds: one die per wound needed to destroy the unit, 1-3 wounding
    /// (:8365). The target the tray records is `MAX + 1`, the safe face.
    #[test]
    fn no_retreat_pays_a_failed_test_in_self_wounds() {
        let unit = Ctx { quality: 6, no_retreat: true, ..Default::default() };
        let mut tray = Tray::seeded(2);
        let (res, out) = resolve_morale_with_tray(&unit, "Unit", true, true, true, 5, &mut tray);
        assert_eq!(res, Morale::Passed, "No Retreat counts as passed");
        assert_eq!(out.rolls.len(), 1, "Shaken drew no test die; only the self-wound roll");
        assert_eq!(out.rolls[0].count, 5, "one die per wound needed to destroy it");
        assert_eq!(out.rolls[0].target, NO_RETREAT_SELF_WOUND_MAX + 1);
        let want = out.rolls[0].faces.iter().filter(|&&f| f <= 3).count() as i64;
        assert_eq!(out.wounds, want, "each 1-3 is one self-wound");
    }

    #[test]
    fn faces_to_hits_follows_the_natural_6_and_natural_1_rules() {
        let faces = [1u8, 2, 3, 4, 5, 6];
        assert_eq!(faces_to_hits(&faces, 4), 3, "4, 5, 6");
        assert_eq!(faces_to_hits(&faces, 2), 5, "everything but the 1");
        assert_eq!(faces_to_hits(&faces, 6), 1, "only the 6");
        assert_eq!(faces_to_hits(&faces, 7), 1, "the natural 6 still succeeds");
        assert_eq!(faces_to_hits(&faces, 1), 5, "the natural 1 still fails");
        assert_eq!(faces_to_hits(&faces, 0), 0, "TARGET_NONE tests nothing");
        assert_eq!(faces_to_hits(&[], 4), 0);
    }
