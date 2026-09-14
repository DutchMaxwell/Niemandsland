use super::*;

    // --- TEST WAVE (2026-09-14, D-PROOF) — the six stamp-layer NUMBER pins
    // for the ledger's `mentioned` rows that live on the profile stamp:
    // Buccaneer Boost, +1 to Defense, Armor, Hazardous, Reanimation and
    // Surprise Attack. Each test reads the rule BY ITS EXACT NAME off the
    // REAL registry (each name's own (system, faction) block, the folder its
    // book prints) through `UnitStatic::build_for` at
    // `CURRENT_RULES_EPOCH`, with the no-rule / unmapped arm beside it.

    /// The family's carrier template: one rifle (AP 0) and one blade whose
    /// AP(5) prints as the weapon's own "AP(5)" rule (the field the AP stamp
    /// reads), so a stamped AP floor is observable on both arrays and the
    /// "floor, not a set" leg has a host.
    const MENTIONED_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":["AP(5)"]}]}}}"#;

    /// The REAL `build_for` product: `system`/`faction` swapped in, `special`
    /// printed as the unit's special_rules, and `weapon` ("" = none) printed
    /// on BOTH weapons (the books' own shape for weapon rules).
    fn mentioned_unit(system: &str, faction: &str, special: &[&str], weapon: &str, epoch: u32) -> UnitStatic {
        let printed =
            special.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let mut tpl = MENTIONED_HEADER
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        if !weapon.is_empty() {
            tpl = tpl.replace("\"rules\":[]", &format!("\"rules\":[\"{weapon}\"]"));
            tpl = tpl.replace(
                "\"rules\":[\"AP(5)\"]",
                &format!("\"rules\":[\"AP(5)\",\"{weapon}\"]"),
            );
        }
        let header = read_act_header(&tpl).expect("MENTIONED_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// "Buccaneer Boost" (aof/sky_city_dwarves, primitive Shot Modifier,
    /// hit_bonus 1, NO over_in): the Boost Aura's granted base stamps the
    /// FLAT +1 to hit; the base "Buccaneer" rides the strictly-over-9" ring
    /// instead; epoch 5 (below the aura gate) and the rule-less carrier
    /// stamp nothing.
    #[test]
    fn a_buccaneer_boost_aura_stamps_one_flat_to_hit_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let boost = mentioned_unit("aof", "sky_city_dwarves", &["Buccaneer Boost Aura"], "", epoch);
        assert!(boost.shoot[0].hit_bonus == 1, "the granted base stamps the flat +1");
        assert!(
            boost.shoot[0].hit_bonus_over9 == 0,
            "the Boost entry carries no over_in: flat, never the over-9 ring"
        );
        let base = mentioned_unit("aof", "sky_city_dwarves", &["Buccaneer"], "", epoch);
        assert!(
            base.shoot[0].hit_bonus == 0 && base.shoot[0].hit_bonus_over9 == 1,
            "the base Buccaneer rides the strictly-over-9 ring instead"
        );
        let pre = mentioned_unit("aof", "sky_city_dwarves", &["Buccaneer Boost Aura"], "", 5);
        assert!(
            pre.shoot[0].hit_bonus == 0 && pre.shoot[0].hit_bonus_over9 == 0,
            "epoch 5: the aura gate is OFF"
        );
        let plain = mentioned_unit("aof", "sky_city_dwarves", &[], "", epoch);
        assert!(plain.shoot[0].hit_bonus == 0 && plain.shoot[0].hit_bonus_over9 == 0);
    }

    /// "+1 to Defense" (gf/wormhole_daemons_of_war, primitive Shielded,
    /// defense_bonus 1): the alias fires the shielded half — the +1 rung
    /// lowers Defense 4 to a 3+ to be hit; unmapped factions and rule-less
    /// carriers keep the plain rung.
    #[test]
    fn a_plus_one_to_defense_carrier_shields_by_one_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = mentioned_unit("gf", "wormhole_daemons_of_war", &["+1 to Defense"], "", epoch);
        assert!(us.ctx.shielded, "the alias fires the shielded half");
        assert_eq!(us.ctx.shielded_alias, ShieldedAlias::PlusOneToDefense);
        assert_eq!(us.ctx.shielded_bonus(), 1, "the +1 the rule produces");
        assert_eq!(
            crate::combat::shielded_defense(us.ctx.defense, us.ctx.shielded_bonus()),
            3,
            "Defense 4 -> hit on 3+"
        );
        let plain = mentioned_unit("gf", "wormhole_daemons_of_war", &[], "", epoch);
        assert!(!plain.ctx.shielded && plain.ctx.shielded_bonus() == 0);
        assert_eq!(crate::combat::shielded_defense(plain.ctx.defense, 0), 4, "no rule, plain rung");
        let unmapped = mentioned_unit("gf", "robot_legions", &["+1 to Defense"], "", epoch);
        assert!(!unmapped.ctx.shielded, "no (faction) entry, no fold");
    }

    /// "Armor(X)" (gf/aof common, rated): the rating is the defense rung's
    /// best-of floor — Armor(2) takes Defense 4 to a 2+ to be hit, Armor(1)
    /// sits below the 2+ floor and leaves the rung untouched, and no rule
    /// leaves it untouched too.
    #[test]
    fn an_armor_rating_takes_the_defense_rung_to_its_rating_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let two = mentioned_unit("gf", "robot_legions", &["Armor(2)"], "", epoch);
        assert_eq!(two.ctx.defense, 2, "Armor(2): Defense 4 -> saves at 2 (best-of)");
        let one = mentioned_unit("gf", "robot_legions", &["Armor(1)"], "", epoch);
        assert_eq!(one.ctx.defense, 4, "Armor(1): below the 2+ floor, the rung is untouched");
        let none = mentioned_unit("gf", "robot_legions", &[], "", epoch);
        assert_eq!(none.ctx.defense, 4, "no rule, plain Defense");
    }

    /// "Hazardous" (gf/ratmen_clans, ap 4): the weapon tag floors BOTH
    /// arrays' AP at 4 — AP 0 rises to 4, AP 5 stays 5 (a floor, not a set) —
    /// and the no-rule carrier keeps its own AP.
    #[test]
    fn a_hazardous_weapon_floors_its_ap_at_four_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = mentioned_unit("gf", "ratmen_clans", &[], "Hazardous", epoch);
        assert!(us.shoot[0].hazardous && us.melee[0].hazardous, "the tag stamps both arrays");
        assert_eq!(us.shoot[0].ap, 4, "AP 0 rises to the AP(4) floor");
        assert_eq!(us.melee[0].ap, 5, "AP 5 stays 5: a floor, not a set");
        let plain = mentioned_unit("gf", "ratmen_clans", &[], "", epoch);
        assert!(!plain.shoot[0].hazardous && plain.shoot[0].ap == 0, "no tag, no floor");
    }

    /// "Reanimation" (gf/robot_legions, restore_target 5): the exact-name
    /// stamp carries target 5 — and the "Reanimation Aura" carrier reaches
    /// the same 5 through the Aura-Channel grant of the base; a rule-less
    /// carrier and a below-`EPOCH_7_TABLE_RULES` record stay `None`.
    #[test]
    fn a_reanimation_carrier_restores_on_a_five_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = mentioned_unit("gf", "robot_legions", &["Reanimation"], "", epoch);
        assert_eq!(us.reanimation.expect("stamped").target, 5, "robot_legions' restore_target");
        let aura = mentioned_unit("gf", "robot_legions", &["Reanimation Aura"], "", epoch);
        assert_eq!(
            aura.reanimation.expect("the aura grants the base").target,
            5,
            "the Aura-Channel grant rides the same read"
        );
        let plain = mentioned_unit("gf", "robot_legions", &[], "", epoch);
        assert!(plain.reanimation.is_none(), "no name, no stamp");
        let pre = mentioned_unit("gf", "robot_legions", &["Reanimation"], "", 6);
        assert!(pre.reanimation.is_none(), "below EPOCH_7_TABLE_RULES the gate keeps None");
    }

    /// "Surprise Attack(X)" (gf/alien_hives, primitive Infiltrate): the
    /// rating is the burst's X, each 2+ is one AP(1) hit within 6", and the
    /// alias arm counts as Infiltrate for alien_hives' own 3" ring; a bare
    /// name is X = 1 and a rule-less carrier stamps nothing.
    #[test]
    fn a_surprise_attack_rating_is_its_burst_dice_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let rated = mentioned_unit("gf", "alien_hives", &["Surprise Attack(2)"], "", epoch);
        let s = rated.surprise_attack.expect("stamped");
        assert_eq!(s.dice, 2, "the rating is the X");
        assert_eq!(s.trigger, 2, "each 2+ is one hit");
        assert_eq!(s.ap, 1, "AP(1)");
        assert!((s.range_in - 6.0).abs() < 1e-9, "within 6\"");
        assert_eq!(
            rated.infiltrate_min_enemy_dist_in, 3.0,
            "counts as Infiltrate: alien_hives' own 3\" ring"
        );
        let bare = mentioned_unit("gf", "alien_hives", &["Surprise Attack"], "", epoch);
        assert_eq!(bare.surprise_attack.expect("stamped").dice, 1, "a bare name is X = 1");
        let plain = mentioned_unit("gf", "alien_hives", &[], "", epoch);
        assert!(plain.surprise_attack.is_none(), "no name, no burst");
    }
