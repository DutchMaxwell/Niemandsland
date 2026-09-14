use super::*;

    // ------- the four GATE-ONLY rows (PROVEN_VS_READ 2026-09-14 ledger) ------
    // Bloodborn, Destructive, Predator Shooter and Reliable were judged
    // CORRECT by READING both layers; a replay gate proves a RECORDED game
    // replays and pins none of their numbers. These four tests pin each
    // rule's number in a FRESH sim, reached by the rule's EXACT NAME through
    // the real gf registry (the #489 lesson), at the build's current rules
    // epoch. None of the four reads carries a trace line (the Surge walk's
    // only `trace_rule` is Great Sergeant's printed low window), so the
    // numbers themselves are the witness and no log line is asserted.

    /// End to end through the REAL registry: the two name rows as unit-level
    /// `special_rules` (Bloodborn on gf/blood_prime_brothers, Predator Shooter
    /// on gf/ratmen_clans), the two weapon rows on the WEAPON's own `rules`
    /// list (`base_profile`'s `weapon_has` read — Destructive on
    /// gf/robot_legions, Reliable from gf's common block), plus the plain
    /// control every leg below leans on. Every unit carries a 24" rifle AND a
    /// blade, so the shooting facet and the melee facet are both observable.
    const GATE_ONLY_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "bloodborn":{"unit_id":"bloodborn","name":"Bloodborn","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blood_prime_brothers",
        "special_rules":["Bloodborn"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]},
      "predator_shooter":{"unit_id":"predator_shooter","name":"Predator Shooter","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"ratmen_clans",
        "special_rules":["Predator Shooter"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]},
      "destructive_w":{"unit_id":"destructive_w","name":"Destructive","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":["Destructive"]},
          {"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":["Destructive"]}]},
      "reliable_w":{"unit_id":"reliable_w","name":"Reliable","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":["Reliable"]},
          {"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":["Reliable"]}]},
      "plain":{"unit_id":"plain","name":"Plain","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn gate_static(id: &str) -> UnitStatic {
        let header = read_act_header(GATE_ONLY_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(id).expect(id);
        UnitStatic::build(&mut reg, p)
    }

    /// Bloodborn — "For each unmodified roll of 6 to hit when attacking, this
    /// model may roll +1 attack with that weapon": the registry's `Surge`
    /// `extra_attack` entry (gf/blood_prime_brothers) reaches BOTH facets
    /// (no facet gate), and the fresh melee sim draws ONE extra die per
    /// unmodified 6 (seed 9: two of them), at the primary's to-hit target,
    /// with the extras' hits folded into the save batch.
    #[test]
    fn bloodborn_draws_one_extra_attack_die_per_unmodified_six_on_both_facets() {
        let us = gate_static("bloodborn");
        assert!(us.shoot[0].surge_attack, "Bloodborn's extra-attack facet, ranged");
        assert!(us.melee[0].surge_attack, "and melee — Bloodborn carries no facet gate");
        let want_primary = Tray::seeded(9).roll(8);
        assert_eq!(want_primary.iter().filter(|&&f| f == 6).count(), 2, "fixture: seed 9 must roll two 6s");
        let want_extra = {
            let mut t = Tray::seeded(9);
            t.roll(8);
            t.roll(2)
        };
        let p = [us.melee[0].clone()];
        let mut tray = Tray::seeded(9);
        let out = resolve_melee_with_tray(
            &[striker(&p, &[0], &[8], &us.ctx)], &defender(4, 5), "Target", false, true, true, &mut tray);
        assert_eq!(out.rolls.len(), 3, "hit roll, ONE extra attack roll, one save batch: {:?}", out.rolls);
        assert_eq!(out.rolls[1].kind, "attack");
        assert_eq!(out.rolls[1].count, 2, "one extra die per unmodified 6");
        assert_eq!(out.rolls[1].target, 4, "the same to-hit target as the primary roll");
        assert_eq!(out.rolls[1].faces, want_extra, "the extras draw exactly two fresh faces");
        let want_hits = faces_to_hits(&want_primary, 4) as i64 + faces_to_hits(&want_extra, 4) as i64;
        assert_eq!(out.rolls[2].kind, "defense");
        assert_eq!(out.rolls[2].count, want_hits, "the extras' hits are in the save batch's die count");
        let plain = gate_static("plain");
        let p2 = [plain.melee[0].clone()];
        let mut t2 = Tray::seeded(9);
        let out2 = resolve_melee_with_tray(
            &[striker(&p2, &[0], &[8], &us.ctx)], &defender(4, 5), "Target", false, true, true, &mut t2);
        assert_eq!(out2.rolls.len(), 2, "no Bloodborn, no extra roll: {:?}", out2.rolls);
    }

    /// Predator Shooter — the same Surge `extra_attack` entry, but
    /// `shooting_only: true` (gf/ratmen_clans): the volley draws ONE extra die
    /// per unmodified 6 (seed 9: two), while the MELEE facet stays shut — the
    /// exact half ai_ev.gd:288-290 records as fixed.
    #[test]
    fn predator_shooter_draws_the_extra_dice_in_the_volley_and_never_in_melee() {
        let us = gate_static("predator_shooter");
        assert!(us.shoot[0].surge_attack, "Predator Shooter's shooting facet");
        assert!(!us.melee[0].surge_attack, "the melee facet stays shut (shooting_only)");
        let p = [us.shoot[0].clone()];
        let mut tray = Tray::seeded(9);
        let out = resolve_shooting_with_tray(&p, &[0], &[8], &us.ctx, &defender(4, 5), 12.0, &mut tray);
        assert_eq!(out.rolls.len(), 3, "hit roll, ONE extra attack roll, one save batch: {:?}", out.rolls);
        assert_eq!(out.rolls[1].kind, "attack");
        assert_eq!(out.rolls[1].count, 2, "one extra die per unmodified 6");
        assert_eq!(out.rolls[1].target, 4, "the same to-hit target as the primary roll");
        let b = [us.melee[0].clone()];
        let mut tray2 = Tray::seeded(9);
        let m = resolve_melee_with_tray(
            &[striker(&b, &[0], &[8], &us.ctx)], &defender(4, 5), "Target", false, true, true, &mut tray2);
        assert_eq!(m.rolls.len(), 2, "no melee facet, no extra roll: {:?}", m.rolls);
        let plain = gate_static("plain");
        let p2 = [plain.shoot[0].clone()];
        let mut t3 = Tray::seeded(9);
        let out2 = resolve_shooting_with_tray(&p2, &[0], &[8], &us.ctx, &defender(4, 5), 12.0, &mut t3);
        assert_eq!(out2.rolls.len(), 2, "no Predator Shooter, no extra roll: {:?}", out2.rolls);
    }

    /// Destructive — "On unmodified results of 6 to hit, those hits get
    /// AP(+4)" (the weapon's own rules list, gf/robot_legions): the two 6s of
    /// seed 9 ride their own save sub-batch at Defense 4 + AP(4) = 8+, every
    /// other hit keeps the plain 4+, and every hit gets exactly one save die.
    #[test]
    fn destructive_raises_the_unmodified_sixes_save_ap_to_4() {
        let us = gate_static("destructive_w");
        assert!(us.shoot[0].destructive, "the weapon's own rules list carries Destructive");
        let want_primary = Tray::seeded(9).roll(8);
        let want_hits = faces_to_hits(&want_primary, 4) as i64;
        let p = [us.shoot[0].clone()];
        let mut tray = Tray::seeded(9);
        let out = resolve_shooting_with_tray(&p, &[0], &[8], &us.ctx, &defender(4, 5), 12.0, &mut tray);
        let saves: Vec<&Roll> = out.rolls.iter().filter(|r| r.kind == "defense").collect();
        assert_eq!(saves.iter().map(|r| r.count).sum::<i64>(), want_hits, "every hit gets its save die");
        assert_eq!(saves[0].count, 2, "the two unmodified 6s ride their own sub-batch");
        assert_eq!(saves[0].target, 8, "Defense 4 + AP(4) on the unmodified 6s");
        if let Some(rest) = saves.get(1) {
            assert_eq!(rest.target, 4, "every hit that is not an unmodified 6 keeps the plain save");
        }
        let plain = gate_static("plain");
        let p2 = [plain.shoot[0].clone()];
        let mut t2 = Tray::seeded(9);
        let out2 = resolve_shooting_with_tray(&p2, &[0], &[8], &us.ctx, &defender(4, 5), 12.0, &mut t2);
        let s2: Vec<&Roll> = out2.rolls.iter().filter(|r| r.kind == "defense").collect();
        assert_eq!(s2.len(), 1, "no Destructive, one save batch: {:?}", s2);
        assert_eq!(s2[0].target, 4, "no Destructive, no on-6 AP");
    }

    /// Reliable — "Attacks at Quality 2+" (the weapon's own rules list, gf's
    /// common block): the to-hit target is the fixed 2+ on BOTH legs at
    /// Quality 4+ (`reliable_quality`'s min), while the plain twin keeps its
    /// printed 4+. The melee-leg number itself was already pinned per flag in
    /// `melee_impact_order` — this pin reaches it by the rule's NAME.
    #[test]
    fn reliable_fixes_the_to_hit_target_at_2_on_both_legs() {
        let us = gate_static("reliable_w");
        assert!(us.shoot[0].reliable, "the weapon's own rules list carries Reliable");
        assert!(us.melee[0].reliable, "the melee weapon carries it too");
        let p = [us.shoot[0].clone()];
        let mut tray = Tray::seeded(4);
        let out = resolve_shooting_with_tray(&p, &[0], &[8], &us.ctx, &defender(4, 5), 12.0, &mut tray);
        assert_eq!(out.rolls[0].target, 2, "the volley hits on the fixed 2+");
        let b = [us.melee[0].clone()];
        let mut tray2 = Tray::seeded(4);
        let m = resolve_melee_with_tray(
            &[striker(&b, &[0], &[8], &us.ctx)], &defender(4, 5), "Target", false, true, true, &mut tray2);
        assert_eq!(m.rolls[0].target, 2, "the strike hits on the same fixed 2+");
        let plain = gate_static("plain");
        let p2 = [plain.shoot[0].clone()];
        let mut t3 = Tray::seeded(4);
        let out2 = resolve_shooting_with_tray(&p2, &[0], &[8], &us.ctx, &defender(4, 5), 12.0, &mut t3);
        assert_eq!(out2.rolls[0].target, 4, "no Reliable, the printed Quality 4+");
    }
