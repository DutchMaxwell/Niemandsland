use super::*;

    // ---- sweep C 2026-09-14, row `Unstoppable in Melee` — the clamp half ----
    //
    // The book: "This model gets Unstoppable in melee." Unstoppable is TWO
    // halves — ignore all negative to-hit modifiers AND ignore the target's
    // Regeneration. The registry models the name as `Lacerate {bypass_regen,
    // melee_only}`, so only the Regeneration half ever fired: the unit-level
    // Unstoppable stamp skips every name containing " in " and the Evasive
    // -1 (and every moved penalty) landed on the strike anyway.
    //
    // Fix: from `EPOCH_35_UNSTOPPABLE_MELEE` the stamp accepts the
    // "Unstoppable in Melee" name for the MELEE profiles, so the clamp at the
    // melee hit fold reads it. Below the gate every recorded game replays
    // with the penalty landing.

    /// The fixture, end to end through the REAL registry: an Unstoppable-in-
    /// Melee carrier with a rifle and a blade (so the melee stamp and the
    /// shooting non-stamp are both observable), plus a rule-less control.
    const UNSTOP_MELEE_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "unstop_melee":{"unit_id":"unstop_melee","name":"Unstop Melee","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":["Unstoppable in Melee"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain":{"unit_id":"plain","name":"Plain","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn unstop_static(id: &str, epoch: u32) -> UnitStatic {
        let header = read_act_header(UNSTOP_MELEE_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(id).expect(id);
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    fn evasive_defender() -> Ctx {
        Ctx { evasive: true, ..defender(4, 5) }
    }

    /// One seeded melee strike of the blade at an Evasive defender.
    fn melee_strike(us: &UnitStatic, tray: &mut Tray) -> ShootResult {
        let p = [us.melee[0].clone()];
        let strikers = [striker(&p, &[0], &[2], &us.ctx)];
        resolve_melee_with_tray(&strikers, &evasive_defender(), "Target", false, true, true, tray)
    }

    /// NEW leg: at the frozen `EPOCH_35_UNSTOPPABLE_MELEE` the Evasive -1 is
    /// clamped — the Unstoppable-in-Melee carrier strikes at its unmodified
    /// Quality 4+, not at the penalised 5+.
    #[test]
    fn an_unstoppable_in_melee_striker_hits_unmodified_against_evasive_at_epoch_35() {
        let us = unstop_static("unstop_melee", 35);
        let mut tray = Tray::seeded(27);
        let out = melee_strike(&us, &mut tray);
        assert_eq!(out.rolls[0].target, 4,
            "the Evasive -1 is clamped: the strike reads the plain Quality 4+");
    }

    /// OLD leg: at the epoch immediately below the bump (at rebase time 34,
    /// the frozen `EPOCH_34_UNSTOPPABLE_MARK` — the unstopmark leg landed
    /// first) every recorded game replays with the penalty landing — the name
    /// carried only its Regeneration half, so the Evasive -1 raises Quality
    /// 4+ to 5+.
    #[test]
    fn below_epoch_35_the_evasive_penalty_still_lands_on_the_strike() {
        let us = unstop_static("unstop_melee", crate::acts::EPOCH_34_UNSTOPPABLE_MARK);
        let mut tray = Tray::seeded(27);
        let out = melee_strike(&us, &mut tray);
        assert_eq!(out.rolls[0].target, 5,
            "the old leg: no clamp read, Evasive -1 raises Quality 4+ to 5+");
    }

    /// The scope half: MELEE attacks only. The same carrier's rifle keeps the
    /// Evasive -1 at the new epoch — the stamp never hands the clamp to a
    /// ranged profile, so the volley fold cannot see it.
    #[test]
    fn the_carriers_rifle_keeps_the_evasive_penalty_at_epoch_35() {
        let us = unstop_static("unstop_melee", 35);
        let mut tray = Tray::seeded(27);
        let out = resolve_shooting_with_tray(
            &us.shoot, &[0], &[1], &us.ctx, &evasive_defender(), 12.0, &mut tray);
        assert_eq!(out.rolls[0].target, 5,
            "melee-only scoping: the volley still rolls at the penalised 5+");
    }
