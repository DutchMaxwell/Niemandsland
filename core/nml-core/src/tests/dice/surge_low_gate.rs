use super::*;

    // ------------------------------------- block B6 mutant killer: the LOW gate ---

    /// Primal Boost's LOW surge (`surge_attack_low < 6`, main.gd:4417-4443):
    /// the successful unmodified 5s are extra attack dice ON TOP of the 6s —
    /// `xn` ADDS the 5-count, so one 6 and two 5s draw three extras, not the
    /// `6s - 5s` of an inverted sign, which would draw nothing at all.
    #[test]
    fn a_low_surge_adds_the_fives_to_the_sixes_never_subtracts() {
        let p = [ShootProfile { surge_attack: true, surge_attack_low: 5, ..rifle(8) }];
        let mut tray = Tray::seeded(5);
        let mut rolls = Vec::new();
        let extra = surge_attack_hits(&p[0], &[6, 5, 5], 4, "shooter", &mut tray, &mut rolls);
        assert_eq!(rolls.len(), 1, "one extra-attack-die roll: {:?}", rolls);
        assert_eq!(rolls[0].count, 3, "one 6 plus two 5s = three extra dice");
        assert_eq!(rolls[0].target, 4, "the extras roll at the weapon's own target");
        let want = Tray::seeded(5).roll(3);
        assert_eq!(extra, faces_to_hits(&want, 4) as i64, "the extras are the tray's next three");
    }

    // --------------------- the plain auto-hit form's own LOW window (EPOCH_50) ---

    /// RED (STANDALONE_SWEEP_F 2026-09-14, row `Great Sergeant`): the printed
    /// "5 or 6" Surge never paid on either layer - both stamp loops read
    /// `surge_low` only off `upgrades` carriers, so the plain auto-hit form's
    /// printed `surge_low: 5` was dead data and the folds paid the natural 6s
    /// alone. End to end through the REAL registry (aof/ogres, the folder the
    /// book prints): at the low epoch the volley pays the 6 plus both
    /// successful 5s, below the gate (48/49) every recorded corpus replays the
    /// 6s read. Seed 6: one 6 plus two 5s in 8 dice.
    #[test]
    fn great_sergeant_volley_pays_a_rolled_5_at_50_and_replays_the_sixes_below() {
        let want = Tray::seeded(6).roll(8);
        assert_eq!(want.iter().filter(|&&f| f == 6).count(), 1, "fixture: seed 6 must roll one 6");
        assert_eq!(want.iter().filter(|&&f| f == 5).count(), 2, "fixture: seed 6 must roll two 5s");
        let base = faces_to_hits(&want, 4) as i64;
        let mut reg = Registries::new(&repo_root());
        let p = read_act_header(GS_HEADER).expect("header").profiles.get("gs").expect("gs").clone();
        let us50 = UnitStatic::build_for(&mut reg, &p, 50);
        assert_eq!(us50.shoot[0].surge_low, 5, "the printed low window stamps from 50");
        assert_eq!(us50.shoot[0].surge_over_in, -1.0, "the entry prints no distance gate");
        let mut t = Tray::seeded(6);
        assert_eq!(surge_volley(&[us50.shoot[0].clone()], 4, 10.0, true, &mut t).rolls[1].count,
            base + 3, "at 50 the printed 5-6 pays: the 6 plus both successful 5s");
        let melee_att = Ctx { quality: 4, models: 1, ..Default::default() };
        let mut t = Tray::seeded(6);
        assert_eq!(resolve_melee_with_tray(
                &[striker(&[us50.melee[0].clone()], &[0], &[8], &melee_att)],
                &defender(4, 5), "Target", false, true, true, &mut t).rolls[1].count,
            base + 3, "at 50 the melee fold pays the printed 5-6 too");
        for epoch in [48u32, 49] {
            let us = UnitStatic::build_for(&mut reg, &p, epoch);
            assert_eq!(us.shoot[0].surge_low, 6, "below the gate the stamp replays the 6s read");
            assert_eq!(us.shoot[0].surge_over_in, 0.0, "and stamps no window");
            let mut t = Tray::seeded(6);
            assert_eq!(surge_volley(&[us.shoot[0].clone()], 4, 10.0, true, &mut t).rolls[1].count,
                base + 1, "epoch {epoch}: the recorded read, the 6 alone");
        }
    }

    /// The melee fold's LOW window (the volley fold's twin): the ungated
    /// sentinel pays in melee - melee resolves at 0.0", so the Boost's strict
    /// `dist > over_in` gate (9.0) stays shut there, exactly like the table
    /// (main.gd:4539) - while the SAME fold pays the ungated window.
    #[test]
    fn the_melee_low_window_opens_only_for_the_ungated_sentinel() {
        let want = Tray::seeded(6).roll(8);
        assert_eq!(want.iter().filter(|&&f| f == 5).count(), 2, "fixture: seed 6 must roll two 5s");
        let gs = [ShootProfile { surge: true, surge_low: 5, surge_over_in: -1.0, ..rifle(8) }];
        let boost = [ShootProfile { surge: true, surge_low: 5, surge_over_in: 9.0, ..rifle(8) }];
        let att = Ctx { quality: 4, models: 1, ..Default::default() };
        let mut t = Tray::seeded(6);
        assert_eq!(resolve_melee_with_tray(
                &[striker(&gs, &[0], &[8], &att)],
                &defender(4, 5), "Target", false, true, true, &mut t).rolls[1].count,
            faces_to_hits(&want, 4) as i64 + 3,
            "the sentinel opens the melee window: the 6 plus both successful 5s");
        let mut t = Tray::seeded(6);
        assert_eq!(resolve_melee_with_tray(
                &[striker(&boost, &[0], &[8], &att)],
                &defender(4, 5), "Target", false, true, true, &mut t).rolls[1].count,
            faces_to_hits(&want, 4) as i64 + 1,
            "the Boost's 5s stay shut in melee - the recorded read");
    }

    /// The default-6 read (the brief's "surge_low (default 6)"): an alias
    /// whose entry prints no `surge_low` (Brutal, aof/halflings) keeps the
    /// 6s read at the live epoch - the walk must not leak the Boost reader's
    /// 5 default onto the plain aliases. And a Boost carrier keeps its own
    /// printed over-9" gate at the live epoch.
    #[test]
    fn aliases_without_a_printed_low_keep_the_sixes_at_the_live_epoch() {
        let mut reg = Registries::new(&repo_root());
        let hdr = read_act_header(GS_HEADER).expect("header");
        let brutal = UnitStatic::build_for(&mut reg, hdr.profiles.get("brutal").expect("brutal"), 50);
        assert!(brutal.shoot[0].surge, "the plain alias keeps its facet");
        assert_eq!(brutal.shoot[0].surge_low, 6, "no printed low, no 5s (main.gd's default)");
        let boost = UnitStatic::build_for(&mut reg, hdr.profiles.get("boost").expect("boost"), 50);
        assert_eq!(boost.shoot[0].surge_low, 5, "the Boost's own printed low rides its base");
        assert_eq!(boost.shoot[0].surge_over_in, 9.0, "the Boost keeps its over-9\" gate");
    }

    /// One header, three carriers through the REAL registry: the Great
    /// Sergeant bearer (aof/ogres), a Brutal bearer in the SAME system
    /// (aof/halflings - the no-printed-low sibling) and a Devout Boost
    /// carrier (gf/blessed_sisters - the upgrade low-window twin), each with
    /// a rifle and a blade so both facets are observable.
    const GS_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "gs":{"unit_id":"gs","name":"Great Sergeant","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"ogres","special_rules":["Great Sergeant"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},{"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]},
      "brutal":{"unit_id":"brutal","name":"Brutal Bearer","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"halflings","special_rules":["Brutal"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},{"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]},
      "boost":{"unit_id":"boost","name":"Devout Boost Carrier","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":["Devout","Devout Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},{"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;
