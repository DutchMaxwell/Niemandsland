use super::*;

    // ---- wave 4 (port-entrenched): the stationary Stealth-alias gate -------

    /// The wave-4 fixture, end to end through the REAL registry: an
    /// "Entrenched" carrier (rules 3.6 row MOR-04 moved the mechanics entry
    /// into the gf human_defense_force block: `primitive: Stealth,
    /// hit_penalty: 1, over_in: 12, requires_stationary: true` — the map data
    /// is not epoch-gated, so every epoch reads these numbers; only the
    /// most-models quantifier is code-gated at 73). main.gd:5694-5702 skips a
    /// `requires_stationary` name while the target's `moved_round ==
    /// current_round`; each profile carries one 24" rifle.
    const ENT_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "entrenched":{"unit_id":"entrenched","name":"Entrenched","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"human_defense_force",
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
    /// -1 past its `over_in: 12` gate — Quality 4+ reads 5+ — and stays
    /// silent: the battle-log line is rules-3.6 only (`EPOCH_73_V36`), so
    /// every epoch below 73 prints nothing (the maths is unchanged; the
    /// 73+ wording is covered in `v36_mor_04.rs`).
    #[test]
    fn an_unmoved_entrenched_target_takes_minus_one_past_twelve_inches() {
        let us = ent_static(7);
        let entrenched = Ctx {
            moved_round: -1,
            round: 3,
            ..us.ctx
        };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &entrenched, 13.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 5, "unmoved Entrenched: Quality 4+ -> 5+ (the -1)");
        assert!(
            !out.log.iter().any(|l| l.contains("[Entrenched]")),
            "below epoch 73 the penalty stays silent: {:?}",
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

    /// (c) at EXACTLY 12" the alias's own `over_in` gate is closed even for an
    /// unmoved target — `dist_in > gate`, not `>=` (main.gd:5705).
    #[test]
    fn entrenched_does_nothing_at_exactly_twelve_inches() {
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
        assert_eq!(out.rolls[0].target, 4, "at exactly 12\" the gate is closed");
    }

    /// (d) the replay gate: below the FROZEN `EPOCH_7_TABLE_RULES` the split
    /// does not exist — the OLD unconditional fold (both kinds merged, moved
    /// or not) stays byte-identical. The epoch-6 build keeps Entrenched in
    /// `stealth_alias_*` and zeros the stationary pair, so a MOVED epoch-6
    /// target still takes the map's -1 over 12", exactly as every pre-port
    /// corpus recorded (the map numbers are not epoch-gated).
    #[test]
    fn below_epoch_7_the_old_unconditional_fold_fires_moved_or_not() {
        let us = ent_static(6);
        assert_eq!(us.ctx.stationary_alias_penalty, 0, "the stationary pair is zero below the gate");
        assert_eq!(us.ctx.stealth_alias_penalty, 1, "the old merged fold keeps the -1");
        let moved = Ctx { moved_round: 3, round: 3, ..us.ctx };
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &[rifle(1)], &[0], &[1], &shooter(4), &moved, 13.0, &mut tray,
        );
        assert_eq!(out.rolls[0].target, 5, "epoch 6: the fold is unconditional, moved or not");
    }

    /// (e) the split itself, on the REAL build: at epoch 7 Entrenched leaves
    /// the unconditional pair and lands in the stationary sibling pair with
    /// its own `over_in` — the caller (dice.rs) resolves which one fires.
    #[test]
    fn at_epoch_7_the_walk_splits_entrenched_into_the_stationary_pair() {
        let us = ent_static(7);
        assert_eq!(us.ctx.stealth_alias_penalty, 0, "no unconditional alias left");
        assert_eq!(us.ctx.stationary_alias_penalty, 1, "the stationary pair carries the -1");
        assert_eq!(us.ctx.stationary_alias_over_in, 12.0);
        assert_eq!(us.ctx.stationary_alias_name, "Entrenched");
    }
