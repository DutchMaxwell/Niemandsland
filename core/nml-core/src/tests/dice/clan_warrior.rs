use super::*;

    // ------- the unit-stat base row `Clan Warrior` (ledger
    //      proven_vs_read_part2.tsv, family "unit-stat bases", proof_kind
    //      "none", sweep RF): the gf/eternal_dynasty entry rides the `Surge`
    //      primitive with `extra_attack: true` — the extra-ATTACK-DIE form
    //      (block B6): every unmodified 6 to hit draws one MORE attack die at
    //      the same to-hit target, as its own tray slot, the extras' hits
    //      folding into the save batch (dice.rs's `surge_attack_hits`). The
    //      exact name reaches the stamp through the REAL registry
    //      (`rules_of_primitive` over `lookup("eternal_dynasty",
    //      "Clan Warrior")`), so the number is asserted by the rule's exact
    //      name (the #489 lesson) at the build's current rules epoch. The
    //      Surge walk carries no trace line, so the numbers are the witness.

    /// End to end through the REAL registry (`gate_only_rows`' harness): the
    /// `Clan Warrior` carrier on gf/eternal_dynasty plus the plain control
    /// every leg below leans on. Every unit carries a 24" rifle AND a blade,
    /// so the shooting facet and the melee facet are both observable.
    const CLAN_WARRIOR_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "clan_warrior":{"unit_id":"clan_warrior","name":"Clan Warrior","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"eternal_dynasty",
        "special_rules":["Clan Warrior"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]},
      "plain":{"unit_id":"plain","name":"Plain","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":8,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":8,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn clan_static(id: &str) -> UnitStatic {
        let header = read_act_header(CLAN_WARRIOR_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(id).expect(id);
        UnitStatic::build(&mut reg, p)
    }

    /// THE NUMBER: seed 9's eight strike dice carry exactly two unmodified 6s —
    /// each draws ONE extra attack die at the SAME 4+ target as its own tray
    /// slot, the two extras' hits join the save batch's die count, and the
    /// plain twin (no rule) draws nothing.
    #[test]
    fn clan_warrior_draws_one_extra_attack_die_per_unmodified_six_on_both_facets() {
        let us = clan_static("clan_warrior");
        assert!(us.shoot[0].surge_attack, "the shooting facet, stamped by the exact name");
        assert!(us.melee[0].surge_attack, "and melee — the entry carries no facet gate");
        assert!(!us.melee[0].surge, "the extra-ATTACK form, never the auto-hit form");
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
        let plain = clan_static("plain");
        let p2 = [plain.melee[0].clone()];
        let mut t2 = Tray::seeded(9);
        let out2 = resolve_melee_with_tray(
            &[striker(&p2, &[0], &[8], &us.ctx)], &defender(4, 5), "Target", false, true, true, &mut t2);
        assert_eq!(out2.rolls.len(), 2, "no rule, no extra roll: {:?}", out2.rolls);
    }

    /// The registry entry itself, by the rule's EXACT NAME: gf/eternal_dynasty
    /// `Clan Warrior` is a `Surge` carrier with `extra_attack: true` — the
    /// printed stat base the stamp above spends.
    #[test]
    fn the_clan_warrior_entry_is_a_surge_extra_attack_carrier() {
        let mut reg = Registries::new(&repo_root());
        let e = reg
            .rules_for("gf")
            .lookup("eternal_dynasty", "Clan Warrior")
            .expect("the entry, by the rule's exact name");
        assert_eq!(e.primitive.as_deref(), Some("Surge"), "the Surge primitive");
        assert!(e.param_b("extra_attack"), "extra_attack: true — the stat base the rule grants");
    }
