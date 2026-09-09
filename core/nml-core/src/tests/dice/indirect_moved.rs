use super::*;

    // ------- wave 4 (port-quick-readjustment): Indirect's moved to-hit penalty + the opt-out ---

    /// The wave-4 fixture, end to end through the REAL registry: a plain
    /// "Indirect when Shooting" carrier (gf/robot_legions — the mechanics
    /// entry sits in the gf common block, `moved_hit_penalty: 1`, so the
    /// table's `unit_param(member, "Indirect", "moved_hit_penalty", 1)`
    /// resolves to 1 for any gf faction) and a "Quick Readjustment" bearer
    /// (gf/human_inquisition — the faction's own entry, primitive Indirect,
    /// `no_moved_penalty: true`), each with one 24" rifle the unit-level
    /// name stamps `indirect` on at epoch 6+.
    const IM_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "indirect_shooter":{"unit_id":"indirect_shooter","name":"Indirect Shooter","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Indirect when Shooting"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "quick_readj":{"unit_id":"quick_readj","name":"Quick Readjustment","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"human_inquisition",
        "special_rules":["Quick Readjustment","Indirect when Shooting"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn im_static(id: &str, epoch: u32) -> UnitStatic {
        let header = read_act_header(IM_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(id).expect(id);
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// (a) the moved penalty at epoch 7: a moved Indirect shooter's to-hit
    /// target is the base Quality PLUS the penalty magnitude (Quality 4+ ->
    /// 5+) and names itself in the log; a shooter that did not move this
    /// activation hits at base. The gate shape is main.gd:3220-3224's own:
    /// `moved and (profile.indirect) and not no_moved_penalty`.
    #[test]
    fn a_moved_indirect_shooter_hits_at_minus_one_a_still_one_hits_at_base() {
        let us = im_static("indirect_shooter", 7);
        let moved = Ctx { moved_this_round: true, ..us.ctx };
        let mut t_moved = Tray::seeded(27);
        let out_moved = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &moved, &defender(4, 5), 12.0, &mut t_moved);
        assert_eq!(out_moved.rolls[0].target, 5, "moved Indirect: Quality 4+ -> 5+ (the book's -1)");
        assert!(
            out_moved.log.iter().any(|l| l.contains("Indirect moved")),
            "the applied rule names itself (rules-must-log): {:?}",
            out_moved.log
        );
        let still = Ctx { moved_this_round: false, ..us.ctx };
        let mut t_still = Tray::seeded(27);
        let out_still = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &still, &defender(4, 5), 12.0, &mut t_still);
        assert_eq!(out_still.rolls[0].target, 4, "no move this activation, no penalty");
        assert!(
            !out_still.log.iter().any(|l| l.contains("Indirect moved")),
            "and the non-application stays silent, like the table's own note policy"
        );
    }

    /// (b) the opt-out at epoch 7: a "Quick Readjustment" bearer that moved
    /// hits at base (the `no_moved_penalty` read off the NAME, the table's
    /// `best_primitive_param(member, "Indirect", "no_moved_penalty", false)`
    /// gate, main.gd:3221-3222) and names itself in the log.
    #[test]
    fn a_quick_readjustment_bearer_that_moved_hits_at_base() {
        let us = im_static("quick_readj", 7);
        let moved = Ctx { moved_this_round: true, ..us.ctx };
        let mut t = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &moved, &defender(4, 5), 12.0, &mut t);
        assert_eq!(out.rolls[0].target, 4, "the bearer ignores the Indirect moved penalty");
        assert!(
            out.log.iter().any(|l| l.contains("Quick Readjustment")),
            "the opt-out names itself (rules-must-log): {:?}",
            out.log
        );
    }

    /// (c) the replay gate: below the FROZEN `EPOCH_7_TABLE_RULES` nothing
    /// exists — no penalty, no opt-out, no log line — so every recorded
    /// corpus at epoch 6 and under replays byte-identically.
    #[test]
    fn below_epoch_7_nothing_changes() {
        for (id, epoch) in [("indirect_shooter", 6u32), ("quick_readj", 6)] {
            let us = im_static(id, epoch);
            assert_eq!(us.shoot[0].indirect, true, "the Indirect facet predates this wave (epoch 6)");
            let moved = Ctx { moved_this_round: true, ..us.ctx };
            let mut t = Tray::seeded(27);
            let out = resolve_shooting_with_tray(
                &us.shoot, &[0], &[1], &moved, &defender(4, 5), 12.0, &mut t);
            assert_eq!(out.rolls[0].target, 4, "{id}: epoch {epoch} keeps the pre-port reading");
            assert!(
                !out.log.iter().any(|l| l.contains("Indirect moved") || l.contains("Quick Readjustment")),
                "{id}: and nothing logs below the gate"
            );
        }
    }

    /// (d) the table twin — the recorded position shape "a moved Indirect
    /// shooter at Quality 4, target in range": the core's hit chance equals
    /// the table's own composition `success_chance(modified_hit_target(4,
    /// AiCombatMath.indirect_hit_modifier(true, unit_param("Indirect",
    /// "moved_hit_penalty", 1))))` (ai_combat_math.gd:563-565, main.gd:3223
    /// -3224 — the param resolves to 1 off the common mechanics entry).
    #[test]
    fn the_table_twin_moved_indirect_hit_chance_equals_the_tables() {
        let us = im_static("indirect_shooter", 7);
        let moved = Ctx { moved_this_round: true, ..us.ctx };
        let mut t = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &moved, &defender(4, 5), 12.0, &mut t);
        let table_indirect_mod = -1; // indirect_hit_modifier(true, 1): -max(penalty, 0)
        assert_eq!(
            crate::combat::success_chance(out.rolls[0].target),
            crate::combat::success_chance(modified_hit_target(4, table_indirect_mod)),
            "the core's moved-Indirect hit chance equals the table's composition"
        );
    }
