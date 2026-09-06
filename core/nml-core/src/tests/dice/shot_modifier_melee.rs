use super::*;

    // ------------------ block C2: Shot Modifier, the melee / charge leg ---

    /// (a) `_solo_hit_mod_info`'s melee branch (main.gd:5658-5668) keeps a
    /// `melee_only` Shot Modifier on EVERY melee strike, charge or not: a Good
    /// Fighter carrier hits one better than its plain Quality both ways. The
    /// SHOOTING branch (:5721-5722) skips `melee_only` entries — the dead-aura
    /// wave — so the same unit's rifle stays at Quality 4+.
    #[test]
    fn a_good_fighter_carrier_hits_one_better_in_melee_charging_or_not() {
        let us = c2_static("good_fighter");
        let def = defender(4, 5);
        assert_eq!(
            melee_hit_target(&us.melee[0], &us.ctx, &def, false, 0), 3,
            "Good Fighter +1 on a plain melee strike: Quality 4+ -> 3+");
        assert_eq!(
            melee_hit_target(&us.melee[0], &us.ctx, &def, true, 0), 3,
            "melee_only carries no charge gate: the charge strikes at 3+ too");
        let mut tray = Tray::seeded(27);
        let volley = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &us.ctx, &defender(4, 5), 12.0, &mut tray);
        assert_eq!(volley.rolls[0].target, 4,
            "the melee-scoped bonus never reaches the rifle (dead-aura wave)");
    }

    /// (b) `when: "charge"` is a GATE (main.gd:5661-5663 keeps the entry only
    /// when `charge_only3 and charging`): a Precision Charge Aura carrier hits
    /// one better ONLY while charging, and at its plain Quality when it does
    /// not. RED if the `if charging` guard is dropped — the uncharged strike
    /// would flip to 3+.
    #[test]
    fn a_precision_charge_aura_carrier_hits_one_better_only_while_charging() {
        let us = c2_static("charge_aura");
        let def = defender(4, 5);
        assert_eq!(
            melee_hit_target(&us.melee[0], &us.ctx, &def, false, 0), 4,
            "when: \"charge\" without a charge is no bonus at all");
        assert_eq!(
            melee_hit_target(&us.melee[0], &us.ctx, &def, true, 0), 3,
            "and on the charge it is exactly +1");
    }

    /// (c) A unit that carries none of the three names is BYTE-IDENTICAL: its
    /// melee target stays the plain Quality both ways, and a seeded melee
    /// resolve draws exactly the raw tray's faces — the stamping pass adds no
    /// die and no draw for a non-carrier.
    #[test]
    fn a_plain_unit_stays_byte_identical_on_target_and_faces() {
        let us = c2_static("plain");
        let def = defender(4, 5);
        assert_eq!(melee_hit_target(&us.melee[0], &us.ctx, &def, false, 0), 4);
        assert_eq!(melee_hit_target(&us.melee[0], &us.ctx, &def, true, 0), 4);
        let p = [us.melee[0].clone()];
        let mut tray = Tray::seeded(27);
        let strikers = [striker(&p, &[0], &[2], &us.ctx)];
        let out = resolve_melee_with_tray(&strikers, &defender(4, 5), "Target", false, true, true, &mut tray);
        assert_eq!(out.rolls[0].kind, "attack");
        assert_eq!(out.rolls[0].target, 4);
        assert_eq!(out.rolls[0].faces, Tray::seeded(27).roll(2),
            "the hit dice are the tray's first two draws, byte for byte");
    }
