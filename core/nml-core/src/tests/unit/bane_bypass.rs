use super::*;

    /// Audit 2026-09-13 §2.3 — Bane-primitive aliases (Bestial, Mischievous,
    /// Scrapper, Vicious) carry `reroll_save_sixes` but NOT `bypass_regen`;
    /// the book gives the regen bypass only to the printed Bane. The resolver
    /// regen split (dice.rs `_solo_ignores_regen`'s twin) reads the alias
    /// stamp's `bane` flag today, so a Bestial carrier's wounds skip the
    /// defender's Regeneration dice entirely.
    ///
    /// RED through the REAL registry: a Bestial carrier's volley against a
    /// Regeneration(5+) defender must roll the regen batch (wounds land BELOW
    /// the pre-Regeneration count). The plain-Bane carrier is the GREEN guard:
    /// the printed rule keeps its bypass.
    #[test]
    fn bestial_does_not_bypass_regeneration_only_the_printed_bane_does() {
        let att = Ctx { quality: 2, models: 1, ..Default::default() };
        let def = Ctx {
            defense: 4, tough: 1, models: 1,
            regeneration: true, regen_target: 5,
            ..Default::default()
        };
        // Bestial (aof/beastmen): bane stamped (the sixes re-roll) ...
        let us = bane_unit_of("Bestial", "aof", "beastmen", crate::acts::EPOCH_13_WHO_WINS);
        assert!(us.shoot[0].bane, "the alias re-rolls the defender's sixes");
        let mut prof = us.shoot[0].clone();
        prof.attacks = 24;
        let mut tray = crate::dice::Tray::seeded(27);
        let out = crate::dice::resolve_shooting_with_tray(
            &[prof], &[0], &[24], &att, &def, 12.0, &mut tray,
        );
        assert!(out.caused > 0, "fixture seed no longer wounds — pick another");
        assert!(
            out.wounds < out.caused,
            "Bestial's sixes re-roll must not also bypass Regeneration: \
             the defender rolls its regen dice (caused {}, landed {})",
            out.caused, out.wounds
        );
        // Plain "Bane" (gf/robot_legions): the printed rule — bypass stays.
        let us = bane_unit_of("Bane", "gf", "robot_legions", crate::acts::EPOCH_13_WHO_WINS);
        assert!(us.shoot[0].bane);
        let mut prof = us.shoot[0].clone();
        prof.attacks = 24;
        let mut tray = crate::dice::Tray::seeded(27);
        let out = crate::dice::resolve_shooting_with_tray(
            &[prof], &[0], &[24], &att, &def, 12.0, &mut tray,
        );
        assert_eq!(
            out.wounds, out.caused,
            "the printed Bane ignores Regeneration — every unsaved wound lands"
        );
    }

    /// The OLD leg, epoch 12 (the fold's own gate, `EPOCH_13_WHO_WINS`): the
    /// alias's `bane` was the regen-bypass test too — Bestial still skips the
    /// defender's regen dice, byte-exact with the pre-port corpora.
    #[test]
    fn at_epoch_12_bestial_still_bypasses_regeneration() {
        let att = Ctx { quality: 2, models: 1, ..Default::default() };
        let def = Ctx {
            defense: 4, tough: 1, models: 1,
            regeneration: true, regen_target: 5,
            ..Default::default()
        };
        let us = bane_unit_of("Bestial", "aof", "beastmen", 12);
        assert!(us.shoot[0].bane);
        let mut prof = us.shoot[0].clone();
        prof.attacks = 24;
        let mut tray = crate::dice::Tray::seeded(27);
        let out = crate::dice::resolve_shooting_with_tray(
            &[prof], &[0], &[24], &att, &def, 12.0, &mut tray,
        );
        assert_eq!(
            out.wounds, out.caused,
            "epoch 12 replays the old flat read: the alias bypasses Regeneration"
        );
    }