use super::*;

    // ------------- block C6: Shot Modifier, the runtime-gated siblings (wave 3) ---

    /// (a) Mobile Artillery (wave 3, `EPOCH_6_TABLE_RULES`): at epoch 6 the +1
    /// is stamped off the entry's own params and the volley fold applies it
    /// strictly past 9" ONLY while the shooter has not moved this round (Ctx
    /// ::moved_this_round, the table's `moved_round` stamp gate,
    /// main.gd:5773-5775); at epoch 5 (the recorder's stamp) nothing is
    /// stamped and every volley reads plain Quality.
    #[test]
    fn mobile_artillery_adds_one_past_nine_inches_only_while_stationary_at_epoch_6() {
        let us = c6_static("mobile_artillery", 6);
        assert_eq!(us.ctx.mobile_artillery_hit, 1, "stamped off the entry's own params at epoch 6");
        assert_eq!(us.ctx.mobile_artillery_over_in, 9.0);
        let stationary = Ctx { moved_this_round: false, ..us.ctx };
        let mut t_over = Tray::seeded(27);
        let over = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &stationary, &defender(4, 5), 12.0, &mut t_over);
        assert_eq!(over.rolls[0].target, 3, "past 9\" while stationary: Quality 4+ -> 3+");
        assert!(
            over.log.iter().any(|l| l.contains("Mobile Artillery")),
            "the applied rule names itself (rules-must-log): {:?}",
            over.log
        );
        let moved = Ctx { moved_this_round: true, ..us.ctx };
        let mut t_moved = Tray::seeded(27);
        let out_moved = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &moved, &defender(4, 5), 12.0, &mut t_moved);
        assert_eq!(out_moved.rolls[0].target, 4, "the moved_round stamp gate: no +1 after a move");
        assert!(
            !out_moved.log.iter().any(|l| l.contains("Mobile Artillery")),
            "and the non-application stays silent, like the table's own note policy"
        );
        let mut t_at = Tray::seeded(27);
        let at = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &stationary, &defender(4, 5), 9.0, &mut t_at);
        assert_eq!(at.rolls[0].target, 4, "exactly 9\" is not \"over\" (main.gd's own wording)");

        let us5 = c6_static("mobile_artillery", 5);
        assert_eq!(us5.ctx.mobile_artillery_hit, 0, "epoch 5 (the recorder's stamp) keeps the pre-port reading");
        let stationary5 = Ctx { moved_this_round: false, ..us5.ctx };
        let mut t5 = Tray::seeded(27);
        let out5 = resolve_shooting_with_tray(
            &us5.shoot, &[0], &[1], &stationary5, &defender(4, 5), 12.0, &mut t5);
        assert_eq!(out5.rolls[0].target, 4, "and no fold fires below the gate");
    }

    /// (b) Grounded Precision (wave 3, `EPOCH_6_TABLE_RULES`): the
    /// `all_attacks` +1 reaches BOTH seams while the attacker stands in
    /// terrain (Ctx::in_cover, the core's own cover read standing in for the
    /// table's majority-in-cover gate, main.gd:5771) and neither at epoch 5,
    /// nor in the open.
    #[test]
    fn grounded_precision_adds_one_on_every_attack_while_in_terrain_at_epoch_6() {
        let us = c6_static("grounded_precision", 6);
        assert_eq!(us.ctx.grounded_precision_hit, 1, "stamped off the entry's own params at epoch 6");
        let in_terrain = Ctx { in_cover: true, ..us.ctx };
        let mut t_shoot = Tray::seeded(27);
        let shoot = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &in_terrain, &defender(4, 5), 12.0, &mut t_shoot);
        assert_eq!(shoot.rolls[0].target, 3, "the shoot seam: Quality 4+ -> 3+");
        assert!(
            shoot.log.iter().any(|l| l.contains("Grounded Precision")),
            "rules-must-log: {:?}",
            shoot.log
        );
        assert_eq!(
            melee_hit_target(&us.melee[0], &in_terrain, &defender(4, 5), false, 0), 3,
            "all_attacks reaches the melee seam too (main.gd:5698-5713)");
        let p = [us.melee[0].clone()];
        let mut t_melee = Tray::seeded(27);
        let strikers = [striker(&p, &[0], &[2], &in_terrain)];
        let melee = resolve_melee_with_tray(
            &strikers, &defender(4, 5), "Target", false, true, true, &mut t_melee);
        assert_eq!(melee.rolls[0].target, 3, "the melee fold moves the strike target");
        assert!(
            melee.log.iter().any(|l| l.contains("Grounded Precision")),
            "rules-must-log: {:?}",
            melee.log
        );

        let in_open = Ctx { in_cover: false, ..us.ctx };
        assert_eq!(
            melee_hit_target(&us.melee[0], &in_open, &defender(4, 5), false, 0), 4,
            "the terrain gate: no +1 in the open");
        let mut t_open = Tray::seeded(27);
        let out_open = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &in_open, &defender(4, 5), 12.0, &mut t_open);
        assert_eq!(out_open.rolls[0].target, 4, "and the shoot seam stays shut too");

        let us5 = c6_static("grounded_precision", 5);
        assert_eq!(us5.ctx.grounded_precision_hit, 0, "epoch 5 keeps the pre-port reading");
        let in_terrain5 = Ctx { in_cover: true, ..us5.ctx };
        assert_eq!(
            melee_hit_target(&us5.melee[0], &in_terrain5, &defender(4, 5), false, 0), 4,
            "and no fold fires below the gate");
    }
