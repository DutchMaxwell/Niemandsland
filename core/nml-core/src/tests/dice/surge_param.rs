use super::*;

    // ------------- Dead-parameter recount 2026-09-15, family 2: the
    // `bonus_hits_per_six` / `extra_attack_per_enemy_save_one` READS ---
    //
    // The Surge family's auto-hit fold pays its bonus by a hard-coded
    // constant 1 and Bloodthirsty Fighter's blocked-1s leg rolls ONE extra
    // attack per blocked 1, while both params ride the registry entries
    // unread. These tests build a FIXTURE registry whose entries say 2 and
    // hold the folds to the entry's own number; on main the constant wins,
    // so both RED. The shipped books all print 1 — exactly the constant the
    // folds hard-code — so a real-book run cannot tell the read apart, and
    // no recorded game changes (no epoch gate involved).

    /// A fixture registry with ONE entry: `name` aliasing `primitive` under
    /// `faction`, carrying `params` verbatim (the shred3 wave's temp-map
    /// shape — a whole temp repo root, not a cache override).
    fn param_registry(
        tag: &str, system: &str, faction: &str, name: &str, primitive: &str, params: &str,
    ) -> String {
        let dir = std::env::temp_dir().join(format!("nml_sixbonus_{}_{}", tag, std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        let map_dir = dir.join("assets/solo");
        std::fs::create_dir_all(&map_dir).expect("temp map dir");
        let body = format!(
            r#"{{"common":{{}},"factions":{{"{faction}":{{"{name}":{{"primitive":"{primitive}","rated":false,"book_version":"3.5.3","params":{params}}}}}}}}}}"#
        );
        std::fs::write(map_dir.join(format!("rules_mechanics_{system}.json")), body)
            .expect("write temp mechanics map");
        dir.to_string_lossy().into_owned()
    }

    /// One Rifle (24", 8 attacks) + one Blade — the volley leg reads the
    /// shoot array, the melee surge fold the melee array.
    const PARAM_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"testfac",
        "special_rules":["War Cry"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// The Bloodthirsty carrier: one Blade, 64 attacks (the
    /// bloodthirsty_fighter fixture's shape) under the fixture faction, so
    /// the temp map's own entry answers the name lookup.
    const BT_PARAM_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"testfac",
        "special_rules":["Bloodthirsty Fighter"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Blade","range":0,"attacks":64,"count":1,"ap":0,
          "rules":[]}]}}}"#;

    fn param_static(root: &str, header: &str, epoch: u32) -> UnitStatic {
        let parsed = read_act_header(header).expect("header parses");
        let mut reg = Registries::new(root);
        let p = parsed.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// Seed 9 rolls two unmodified 6s in 8 dice (the surge_gates fixture).
    /// The entry's `bonus_hits_per_six: 2` must pay TWO bonus hits per six —
    /// in the volley fold and in the melee fold alike — while the param-less
    /// control on the same seed replays the recorded +1. On main the folds
    /// hard-code 1, so the two-per-six assertions fail (RED).
    #[test]
    fn a_surge_entrys_bonus_hits_per_six_pays_the_entry_number_not_the_constant() {
        use crate::acts::CURRENT_RULES_EPOCH;
        let want = Tray::seeded(9).roll(8);
        assert_eq!(want.iter().filter(|&&f| f == 6).count(), 2, "fixture: seed 9 must roll two 6s");
        let base = faces_to_hits(&want, 4) as i64;
        let two = param_static(
            &param_registry("surge2", "gf", "testfac", "War Cry", "Surge",
                r#"{"bonus_hits_per_six":2}"#),
            PARAM_HEADER, CURRENT_RULES_EPOCH);
        let one = param_static(
            &param_registry("surge1", "gf", "testfac", "War Cry", "Surge", "{}"),
            PARAM_HEADER, CURRENT_RULES_EPOCH);
        let volley = |us: &UnitStatic| {
            let p = [us.shoot[0].clone()];
            let mut tray = Tray::seeded(9);
            resolve_volley_with_tray(
                &[Shooter { profiles: &p, keep: &[0], attacks: &[8], att: &shooter(4), owner: "" }],
                &defender(4, 5), "Target", 12.0, 12.0, true, true, true, true, &mut tray,
            )
        };
        let v2 = volley(&two);
        let v1 = volley(&one);
        assert_eq!(v2.rolls[1].count, base + 2 * 2,
            "the volley fold pays the entry's bonus_hits_per_six (2) per six");
        assert_eq!(v1.rolls[1].count, base + 2,
            "the param-less entry replays the recorded +1-per-six constant");
        let melee = |us: &UnitStatic| {
            let p = [us.melee[0].clone()];
            let att = Ctx { quality: 4, ..Default::default() };
            let mut tray = Tray::seeded(9);
            resolve_melee_with_tray(
                &[striker(&p, &[0], &[8], &att)], &defender(4, 5), "Target",
                false, false, false, &mut tray,
            )
        };
        let m2 = melee(&two);
        let m1 = melee(&one);
        let hits_of = |out: &ShootResult| {
            out.rolls.iter().filter(|r| r.kind == "defense")
                .map(|r| r.count).max().unwrap_or(0)
        };
        assert_eq!(hits_of(&m2), base + 2 * 2,
            "the melee surge fold pays the entry's bonus_hits_per_six (2) per six too");
        assert_eq!(hits_of(&m1), base + 2, "melee replay: the constant 1");
    }

    /// Bloodthirsty Fighter (aof, primitive self): each blocked unmodified 1
    /// pays the entry's `extra_attack_per_enemy_save_one` extra attacks —
    /// the fixture entry says 2, so twice the control's extra-attack dice.
    /// On main the leg hard-codes 1 and the counts come out equal (RED).
    /// Seed 27 lands blocked 1s (the bloodthirsty_fighter fixture's own
    /// seed); the epoch is the LITERAL 7, never the moving symbol.
    #[test]
    fn a_bloodthirsty_entrys_extra_attack_per_enemy_save_one_pays_the_entry_number() {
        let strike = |us: &UnitStatic| {
            let profiles = [us.melee[0].clone()];
            let att = Ctx { quality: 4, ..Default::default() };
            let strikers = [Shooter {
                profiles: &profiles, keep: &[0], attacks: &[64], att: &att, owner: "att",
            }];
            let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
            let mut tray = Tray::seeded(27);
            resolve_melee_with_tray(&strikers, &def, "def", false, false, false, &mut tray)
        };
        let one = param_static(
            &param_registry("bt1", "aof", "testfac", "Bloodthirsty Fighter",
                "Bloodthirsty Fighter", r#"{"melee_only":true,"no_recursion":true}"#),
            BT_PARAM_HEADER, 7);
        let c1 = strike(&one);
        let ones = c1.rolls.iter().rev().find(|r| r.kind == "attack")
            .map(|r| r.count).unwrap_or(0);
        assert!(ones > 0, "fixture: seed 27 must land blocked 1s or the test is blind");
        let two = param_static(
            &param_registry("bt2", "aof", "testfac", "Bloodthirsty Fighter",
                "Bloodthirsty Fighter",
                r#"{"melee_only":true,"no_recursion":true,"extra_attack_per_enemy_save_one":2}"#),
            BT_PARAM_HEADER, 7);
        let c2 = strike(&two);
        let extra = c2.rolls.iter().rev().find(|r| r.kind == "attack")
            .map(|r| r.count).unwrap_or(0);
        assert_eq!(extra, 2 * ones,
            "each blocked 1 pays the entry's extra_attack_per_enemy_save_one (2), \
             not the hard-coded 1");
    }
