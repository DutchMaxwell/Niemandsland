use super::*;

    /// Audit 2026-09-13 §2.2, Impact half — `Ctx::counter_models` is hard 0
    /// (`unit.rs` "Impact reduction is inert in this port") while the table
    /// feeds `_solo_counter_models(defender)` into `impact_total_dice`
    /// (main.gd:6376-6382): the defender's alive models whose melee weapons
    /// carry Counter, per `SoloController.counter_models_of`
    /// (solo_controller.gd:7556-7581, the bearer count min the alive count).
    ///
    /// RED through the REAL registry: a 5-model unit whose melee weapon
    /// carries Counter stamps 5 counter models at the current epoch.
    const COUNTER_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":5,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Blade","range":0,"attacks":1,"count":5,
          "rules":["Counter"]}]}}}"#;

    #[test]
    fn counter_models_count_the_counter_weapon_bearers() {
        let header = read_act_header(COUNTER_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        let us = UnitStatic::build_for(&mut reg, p, crate::acts::EPOCH_13_WHO_WINS);
        assert!(us.melee[0].counter, "the weapon rule stamps the melee flag");
        assert_eq!(
            us.ctx.counter_models, 5,
            "5 bearers of a Counter melee weapon: the Impact cut counts them"
        );
    }

    /// The OLD leg, epoch 12 (the stamp's own gate, `EPOCH_13_WHO_WINS`):
    /// the hard 0 the old comment swore by — the Impact cut stays inert.
    #[test]
    fn at_epoch_12_counter_models_stays_the_hard_zero() {
        let header = read_act_header(COUNTER_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        let us = UnitStatic::build_for(&mut reg, p, 12);
        assert_eq!(
            us.ctx.counter_models, 0,
            "epoch 12 replays the inert port: the Impact cut reads 0"
        );
    }

    #[test]
    fn counter_attack_unit_cuts_two_impact_dice_from_epoch_65() {
        let mut p: Profile = serde_json::from_str(r#"{"unit_id":"counter_alias","name":"Counter-Attack"}"#).unwrap();
        p.game_system = "aof".into();
        p.faction_folder = "ratmen".into();
        p.special_rules = vec!["Counter-Attack".into()];
        p.model_count = 2;
        p.wounds_max = vec![1, 1];
        let mut reg = Registries::new(&repo_root());
        let new = UnitStatic::build_for(&mut reg, &p, crate::acts::EPOCH_65_MELEE_TRUTH);
        assert_eq!(new.ctx.counter_models, 2, "both printed Counter-Attack models deny Impact");
        assert_eq!(new.ctx.counter_impact_per_model, Some(1), "the alias entry supplies the reduction");
        assert_eq!(crate::combat::impact_total_dice(3, 2,
            new.ctx.counter_models * new.ctx.counter_impact_per_model.unwrap_or(1)), 4);
        let old = UnitStatic::build_for(&mut reg, &p, crate::acts::EPOCH_64_DEPLOY_LARGE_RESPOT);
        assert_eq!(old.ctx.counter_models, 0, "old records keep the weapon-only read");
    }
