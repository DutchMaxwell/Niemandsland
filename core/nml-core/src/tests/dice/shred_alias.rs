use super::*;

    // ------------- Wave: the Shred data-alias FAMILY (unit.rs::stamp's arm

    #[test]
    fn a_destroyer_carrier_shreds_melee_only_at_the_current_epoch() {
        use crate::acts::{rule_on, CURRENT_RULES_EPOCH};
        let us = shred_static("destroyer");
        let p = [us.melee[0].clone()];
        let def = defender(4, 5);
        let mut t_on = Tray::seeded(2);
        let on = resolve_melee_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            false, true, rule_on(CURRENT_RULES_EPOCH, CURRENT_RULES_EPOCH), &mut t_on);
        let mut t_off = Tray::seeded(2);
        let off = resolve_melee_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            false, true, rule_on(0, CURRENT_RULES_EPOCH), &mut t_off);
        assert_eq!(on.rolls, off.rolls, "the gate moves no die");
        assert!(on.wounds > off.wounds,
            "epoch CURRENT: every unmodified Defense 1 deals +1 wound ({} -> {})", off.wounds, on.wounds);
        assert_eq!(on.wounds - off.wounds, on.rolls[1].faces.iter().filter(|&&f| f as i64 == 1).count() as i64,
            "the delta is exactly the Defense 1s");
        // and the plain ogre (no rule, gate on) never shreds
        let plain = shred_static("plain_ogre");
        let pp = [plain.melee[0].clone()];
        let mut t_c = Tray::seeded(2);
        let control = resolve_melee_with_tray(&[striker(&pp, &[0], &[6], &plain.ctx)], &def, "Target",
            false, true, true, &mut t_c);
        assert_eq!(control.wounds, off.wounds, "without the rule the same dice shred nothing");
    }

    #[test]
    fn an_infected_carrier_shreds_shooting_only_at_the_current_epoch() {
        use crate::acts::{rule_on, CURRENT_RULES_EPOCH};
        let us = shred_static("infected");
        let p = [us.shoot[0].clone()];
        let def = defender(4, 5);
        let mut t_on = Tray::seeded(3);
        let on = resolve_volley_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            12.0, 12.0, true, true, rule_on(CURRENT_RULES_EPOCH, CURRENT_RULES_EPOCH), true, &mut t_on);
        let mut t_off = Tray::seeded(3);
        let off = resolve_volley_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            12.0, 12.0, true, true, rule_on(0, CURRENT_RULES_EPOCH), true, &mut t_off);
        assert_eq!(on.rolls, off.rolls, "the gate moves no die");
        assert!(on.wounds > off.wounds,
            "epoch CURRENT: the shooting save 1s shred ({} -> {})", off.wounds, on.wounds);
        assert_eq!(on.wounds - off.wounds, on.rolls[1].faces.iter().filter(|&&f| f as i64 == 1).count() as i64,
            "the delta is exactly the Defense 1s");
    }

    #[test]
    fn a_warbound_carrier_shreds_melee_only_at_the_current_epoch() {
        use crate::acts::{rule_on, CURRENT_RULES_EPOCH};
        let us = shred_static("warbound");
        let p = [us.melee[0].clone()];
        let def = defender(4, 5);
        let mut t_on = Tray::seeded(2);
        let on = resolve_melee_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            false, true, rule_on(CURRENT_RULES_EPOCH, CURRENT_RULES_EPOCH), &mut t_on);
        let mut t_off = Tray::seeded(2);
        let off = resolve_melee_with_tray(&[striker(&p, &[0], &[6], &us.ctx)], &def, "Target",
            false, true, rule_on(0, CURRENT_RULES_EPOCH), &mut t_off);
        assert_eq!(on.rolls, off.rolls, "the gate moves no die");
        assert!(on.wounds > off.wounds,
            "epoch CURRENT: Warbound's save 1s shred ({} -> {})", off.wounds, on.wounds);
        assert_eq!(on.wounds - off.wounds, on.rolls[1].faces.iter().filter(|&&f| f as i64 == 1).count() as i64);
    }

    #[test]
    fn shred_in_melee_shreds_the_melee_half_and_not_the_shooting_half() {
        let us = shred_static("shred_melee");
        let plain = shred_static("plain_gf");
        let def = defender(4, 5);
        // melee half: the alias shreds — the wound delta over a non-carrier on
        // the same seed is exactly the save batch's Defense 1s.
        let pm = [us.melee[0].clone()];
        let cm = [plain.melee[0].clone()];
        let mut t_a = Tray::seeded(2);
        let with = resolve_melee_with_tray(&[striker(&pm, &[0], &[6], &us.ctx)], &def, "Target",
            false, true, true, &mut t_a);
        let mut t_b = Tray::seeded(2);
        let without = resolve_melee_with_tray(&[striker(&cm, &[0], &[6], &plain.ctx)], &def, "Target",
            false, true, true, &mut t_b);
        assert_eq!(with.rolls, without.rolls, "the gate moves no die");
        assert!(with.wounds > without.wounds,
            "melee half shreds ({} -> {})", without.wounds, with.wounds);
        assert_eq!(with.wounds - without.wounds,
            with.rolls[1].faces.iter().filter(|&&f| f as i64 == 1).count() as i64);
        // shooting half: the melee_only facet keeps the rifle silent — the
        // carrier's volley lands exactly a non-carrier's on the same seed.
        let ps = [us.shoot[0].clone()];
        let cs2 = [plain.shoot[0].clone()];
        let mut t_c = Tray::seeded(3);
        let shoot_with = resolve_volley_with_tray(&[striker(&ps, &[0], &[6], &us.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, true, &mut t_c);
        let mut t_d = Tray::seeded(3);
        let shoot_without = resolve_volley_with_tray(&[striker(&cs2, &[0], &[6], &plain.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, true, &mut t_d);
        assert_eq!(shoot_with.rolls, shoot_without.rolls);
        assert_eq!(shoot_with.wounds, shoot_without.wounds,
            "shooting_only: the melee-only alias never shreds a ranged save");
    }

    #[test]
    fn shred_when_shooting_shreds_the_shooting_half_and_not_the_melee_half() {
        let us = shred_static("shred_shooting");
        let plain = shred_static("plain_gf");
        let def = defender(4, 5);
        // shooting half: the alias shreds the save batch.
        let ps = [us.shoot[0].clone()];
        let cs = [plain.shoot[0].clone()];
        let mut t_a = Tray::seeded(3);
        let shoot_with = resolve_volley_with_tray(&[striker(&ps, &[0], &[6], &us.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, true, &mut t_a);
        let mut t_b = Tray::seeded(3);
        let shoot_without = resolve_volley_with_tray(&[striker(&cs, &[0], &[6], &plain.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, true, &mut t_b);
        assert_eq!(shoot_with.rolls, shoot_without.rolls, "the gate moves no die");
        assert!(shoot_with.wounds > shoot_without.wounds,
            "shooting half shreds ({} -> {})", shoot_without.wounds, shoot_with.wounds);
        assert_eq!(shoot_with.wounds - shoot_without.wounds,
            shoot_with.rolls[1].faces.iter().filter(|&&f| f as i64 == 1).count() as i64);
        // melee half: the shooting_only facet keeps the blade silent.
        let pm = [us.melee[0].clone()];
        let cm2 = [plain.melee[0].clone()];
        let mut t_c = Tray::seeded(2);
        let with = resolve_melee_with_tray(&[striker(&pm, &[0], &[6], &us.ctx)], &def, "Target",
            false, true, true, &mut t_c);
        let mut t_d = Tray::seeded(2);
        let without = resolve_melee_with_tray(&[striker(&cm2, &[0], &[6], &plain.ctx)], &def, "Target",
            false, true, true, &mut t_d);
        assert_eq!(with.rolls, without.rolls);
        assert_eq!(with.wounds, without.wounds,
            "melee half: the shooting-only alias never shreds in melee");
    }
