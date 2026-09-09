use super::*;

    // ---- wave 4 (port-entrenched): the stationary Stealth-alias gate -------

    /// The wave-4 fixture, end to end through the REAL registry: an
    /// "Entrenched" carrier (the mechanics entry sits in the gf COMMON block,
    /// `primitive: Stealth, hit_penalty: 2, over_in: 9, requires_stationary:
    /// true` — main.gd:5694-5702 skips a `requires_stationary` name while the
    /// target's `moved_round == current_round`), each profile with one 24"
    /// rifle.
    const ENT_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "entrenched":{"unit_id":"entrenched","name":"Entrenched","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Entrenched"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn ent_static(epoch: u32) -> UnitStatic {
        let header = read_act_header(ENT_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("entrenched").expect("entrenched");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// (a) an Entrenched target that has NOT moved this round takes its own
    /// -2 past its `over_in: 9` gate — Quality 4+ reads 6+ — and the penalty
    /// names itself (rules-must-log).
    #[test]
    fn an_unmoved_entrenched_target_takes_minus_two_past_nine_inches() {
        let us = ent_static(7);
        let entrenched = Ctx {
            moved_round: -1,
            round: 3,
            ..us.ctx
        };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &entrenched, 12.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 6, "unmoved Entrenched: Quality 4+ -> 6+ (the book's -2)");
        assert!(
            out.log.iter().any(|l| l.contains("[Entrenched]")),
            "the applied rule names itself (rules-must-log): {:?}",
            out.log
        );
    }

    /// (b) the SAME target that ADVANCED this round (`moved_round == round`)
    /// loses the alias — main.gd:5700-5702's `continue` — so Quality 4+
    /// stands and nothing logs.
    #[test]
    fn an_entrenched_target_that_moved_this_round_is_not_penalized() {
        let us = ent_static(7);
        let moved = Ctx {
            moved_round: 3,
            round: 3,
            ..us.ctx
        };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &moved, 12.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 4, "moved this round: the stationary alias stands down");
        assert!(
            !out.log.iter().any(|l| l.contains("[Entrenched]")),
            "and the non-application stays silent: {:?}",
            out.log
        );
    }

    /// (c) at EXACTLY 9" the alias's own `over_in` gate is closed even for an
    /// unmoved target — `dist_in > gate`, not `>=` (main.gd:5705).
    #[test]
    fn entrenched_does_nothing_at_exactly_nine_inches() {
        let us = ent_static(7);
        let entrenched = Ctx {
            moved_round: -1,
            round: 3,
            ..us.ctx
        };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &entrenched, 9.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 4, "at exactly 9\" the gate is closed");
    }

    /// (d) the replay gate: below the FROZEN `EPOCH_7_TABLE_RULES` the split
    /// does not exist — the OLD unconditional fold (both kinds merged, moved
    /// or not) stays byte-identical. The epoch-6 build keeps Entrenched in
    /// `stealth_alias_*` and zeros the stationary pair, so a MOVED epoch-6
    /// target still takes the -2, exactly as every pre-port corpus recorded.
    #[test]
    fn below_epoch_7_the_old_unconditional_fold_fires_moved_or_not() {
        let us = ent_static(6);
        assert_eq!(us.ctx.stationary_alias_penalty, 0, "the stationary pair is zero below the gate");
        assert_eq!(us.ctx.stealth_alias_penalty, 2, "the old merged fold keeps the -2");
        let moved = Ctx { moved_round: 3, round: 3, ..us.ctx };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &moved, 12.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 6, "epoch 6: the fold is unconditional, moved or not");
    }

    /// (e) the split itself, on the REAL build: at epoch 7 Entrenched leaves
    /// the unconditional pair and lands in the stationary sibling pair with
    /// its own `over_in` — the caller (dice.rs) resolves which one fires.
    #[test]
    fn at_epoch_7_the_walk_splits_entrenched_into_the_stationary_pair() {
        let us = ent_static(7);
        assert_eq!(us.ctx.stealth_alias_penalty, 0, "no unconditional alias left");
        assert_eq!(us.ctx.stationary_alias_penalty, 2, "the stationary pair carries the -2");
        assert_eq!(us.ctx.stationary_alias_over_in, 9.0);
        assert_eq!(us.ctx.stationary_alias_name, "Entrenched");
    }
