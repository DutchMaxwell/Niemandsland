use super::*;

    // ------------- Wave 3: the Shred per-save-one param read (unit.rs

    #[test]
    fn a_warbound_carriers_save_ones_cost_the_entry_param_at_epoch_6() {
        let root = shred_param_registry("warbound", "gf", "war_disciples", "Warbound");
        let us6 = shred_param_built(&root, "warbound", 6);
        let us5 = shred_param_built(&root, "warbound", 5);
        let plain = shred_param_built(&root, "plain_ogre", 6);
        let def = defender(4, 5);
        let p6 = [us6.melee[0].clone()];
        let p5 = [us5.melee[0].clone()];
        let pc = [plain.melee[0].clone()];
        let mut t6 = Tray::seeded(2);
        let on6 = resolve_melee_with_tray(&[striker(&p6, &[0], &[6], &us6.ctx)], &def, "Target",
            false, true, true, &mut t6);
        let mut t5 = Tray::seeded(2);
        let on5 = resolve_melee_with_tray(&[striker(&p5, &[0], &[6], &us5.ctx)], &def, "Target",
            false, true, true, &mut t5);
        let mut tc = Tray::seeded(2);
        let control = resolve_melee_with_tray(&[striker(&pc, &[0], &[6], &plain.ctx)], &def, "Target",
            false, true, true, &mut tc);
        assert_eq!(on6.rolls, control.rolls, "the gate moves no die");
        let ones = on6.rolls[1].faces.iter().filter(|&&f| f == 1).count() as i64;
        assert!(ones > 0, "the seed must land unmodified save 1s or the test is blind");
        assert_eq!(on6.wounds - control.wounds, 2 * ones,
            "epoch 6: each unmodified save 1 costs the entry's extra_wound_per_save_one (2)");
        assert_eq!(on5.wounds - control.wounds, ones,
            "epoch 5: the read is gated off — the wave-1 base +1 replays");
        assert!(on6.log.iter().any(|l| l.contains("Shred (Warbound)")),
            "rules must log: the firing names the rule");
        assert!(on5.log.iter().all(|l| !l.contains("Shred")),
            "epoch 5 replays silent — no wave-3 log line");
    }

    #[test]
    fn an_infected_carriers_save_ones_cost_the_entry_param_at_epoch_6() {
        let root = shred_param_registry("infected", "gf", "infected_colonies", "Infected");
        let us6 = shred_param_built(&root, "infected", 6);
        let us5 = shred_param_built(&root, "infected", 5);
        let plain = shred_param_built(&root, "plain_gf", 6);
        let def = defender(4, 5);
        let p6 = [us6.shoot[0].clone()];
        let p5 = [us5.shoot[0].clone()];
        let pc = [plain.shoot[0].clone()];
        let mut t6 = Tray::seeded(3);
        let on6 = resolve_volley_with_tray(&[striker(&p6, &[0], &[6], &us6.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, true, &mut t6);
        let mut t5 = Tray::seeded(3);
        let on5 = resolve_volley_with_tray(&[striker(&p5, &[0], &[6], &us5.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, true, &mut t5);
        let mut tc = Tray::seeded(3);
        let control = resolve_volley_with_tray(&[striker(&pc, &[0], &[6], &plain.ctx)], &def, "Target",
            12.0, 12.0, true, true, true, true, &mut tc);
        assert_eq!(on6.rolls, control.rolls, "the gate moves no die");
        let ones = on6.rolls[1].faces.iter().filter(|&&f| f == 1).count() as i64;
        assert!(ones > 0, "the seed must land unmodified save 1s or the test is blind");
        assert_eq!(on6.wounds - control.wounds, 2 * ones,
            "epoch 6: each unmodified save 1 costs the entry's extra_wound_per_save_one (2)");
        assert_eq!(on5.wounds - control.wounds, ones,
            "epoch 5: the read is gated off — the wave-1 base +1 replays");
        assert!(on6.log.iter().any(|l| l.contains("Shred (Infected)")),
            "rules must log: the firing names the rule");
        assert!(on5.log.iter().all(|l| !l.contains("Shred")),
            "epoch 5 replays silent — no wave-3 log line");
    }

    #[test]
    fn a_destroyer_carriers_save_ones_cost_the_entry_param_at_epoch_6() {
        let root = shred_param_registry("destroyer", "aof", "ogres", "Destroyer");
        let us6 = shred_param_built(&root, "destroyer", 6);
        let us5 = shred_param_built(&root, "destroyer", 5);
        let plain = shred_param_built(&root, "plain_ogre", 6);
        let def = defender(4, 5);
        let p6 = [us6.melee[0].clone()];
        let p5 = [us5.melee[0].clone()];
        let pc = [plain.melee[0].clone()];
        let mut t6 = Tray::seeded(2);
        let on6 = resolve_melee_with_tray(&[striker(&p6, &[0], &[6], &us6.ctx)], &def, "Target",
            false, true, true, &mut t6);
        let mut t5 = Tray::seeded(2);
        let on5 = resolve_melee_with_tray(&[striker(&p5, &[0], &[6], &us5.ctx)], &def, "Target",
            false, true, true, &mut t5);
        let mut tc = Tray::seeded(2);
        let control = resolve_melee_with_tray(&[striker(&pc, &[0], &[6], &plain.ctx)], &def, "Target",
            false, true, true, &mut tc);
        assert_eq!(on6.rolls, control.rolls, "the gate moves no die");
        let ones = on6.rolls[1].faces.iter().filter(|&&f| f == 1).count() as i64;
        assert!(ones > 0, "the seed must land unmodified save 1s or the test is blind");
        assert_eq!(on6.wounds - control.wounds, 2 * ones,
            "epoch 6: each unmodified save 1 costs the entry's extra_wound_per_save_one (2)");
        assert_eq!(on5.wounds - control.wounds, ones,
            "epoch 5: the read is gated off — the wave-1 base +1 replays");
        assert!(on6.log.iter().any(|l| l.contains("Shred (Destroyer)")),
            "rules must log: the firing names the rule");
        assert!(on5.log.iter().all(|l| !l.contains("Shred")),
            "epoch 5 replays silent — no wave-3 log line");
    }

    /// Condition kind 2 — `vs_tough_ge` behind `charge_only` (Melee Slayer):
    /// AP(+2) only when BOTH charging and the target is Tough(3)+.
    #[test]
    fn melee_slayer_raises_the_melee_save_ap_only_charging_a_tough_three_target() {
        let us = cond_ap_static("melee_slayer");
        let p = [us.melee[0].clone()];
        let tough = Ctx { defense: 4, tough: 3, models: 5, ..Default::default() };
        let soft = Ctx { defense: 4, tough: 2, models: 5, ..Default::default() };
        let mut t1 = Tray::seeded(27);
        let charging_tough = resolve_melee_with_tray(
            &[striker(&p, &[0], &[6], &us.ctx)], &tough, "Target", true, true, true, &mut t1);
        assert_eq!(charging_tough.rolls[1].target, 6, "AP(+2) charging vs Tough(3)+: 4+ -> 6+");
        let mut t2 = Tray::seeded(27);
        let steady_tough = resolve_melee_with_tray(
            &[striker(&p, &[0], &[6], &us.ctx)], &tough, "Target", false, true, true, &mut t2);
        assert_eq!(steady_tough.rolls[1].target, 4, "not charging: the charge_only gate stays shut");
        let mut t3 = Tray::seeded(27);
        let charging_soft = resolve_melee_with_tray(
            &[striker(&p, &[0], &[6], &us.ctx)], &soft, "Target", true, true, true, &mut t3);
        assert_eq!(charging_soft.rolls[1].target, 4, "charging a Tough(2) target: vs_tough_ge(3) stays shut");
    }

    /// Condition kind 3 — `ranged_over` (Piercing Hunter): AP(+1) only past
    /// 9", off `mod_dist_in` like every other shooting modifier (NML-1152).
    #[test]
    fn piercing_hunter_raises_the_shooting_save_ap_only_past_nine_inches() {
        let us = cond_ap_static("piercing_hunter");
        let def = defender(4, 5);
        let mut t1 = Tray::seeded(27);
        let over = resolve_shooting_with_tray(
            &us.shoot, &[0], &[6], &us.ctx, &def, 12.0, &mut t1);
        assert_eq!(over.rolls[1].target, 5, "AP(+1) past 9\": Defense 4+ -> 5+");
        let mut t2 = Tray::seeded(27);
        let under = resolve_shooting_with_tray(
            &us.shoot, &[0], &[6], &us.ctx, &def, 6.0, &mut t2);
        assert_eq!(under.rolls[1].target, 4, "at or under 9\": no bonus");
    }

    /// Condition kind 4 — the shared `ranged_over_or_charge` gate (Slayer):
    /// ONE unit-level stamp reaches both dice paths, each leg firing on its
    /// own half of the gate — proof the fold is generic, not per-rule.
    #[test]
    fn slayer_raises_ap_from_either_leg_of_its_shared_gate_vs_a_tough_target() {
        let us = cond_ap_static("slayer");
        let tough = Ctx { defense: 4, tough: 3, models: 5, ..Default::default() };
        let mut t1 = Tray::seeded(27);
        let over = resolve_shooting_with_tray(
            &us.shoot, &[0], &[6], &us.ctx, &tough, 12.0, &mut t1);
        assert_eq!(over.rolls[1].target, 6, "ranged leg: past 9\" vs Tough(3)+ is AP(+2) on its own");
        let mut t2 = Tray::seeded(27);
        let under = resolve_shooting_with_tray(
            &us.shoot, &[0], &[6], &us.ctx, &tough, 6.0, &mut t2);
        assert_eq!(under.rolls[1].target, 4, "at 6\" and not charging: neither leg of the gate is open");
        let melee = [us.melee[0].clone()];
        let mut t3 = Tray::seeded(27);
        let charging = resolve_melee_with_tray(
            &[striker(&melee, &[0], &[6], &us.ctx)], &tough, "Target", true, true, true, &mut t3);
        assert_eq!(charging.rolls[1].target, 6, "charge leg: charging vs Tough(3)+ is AP(+2) on its own too");
    }
