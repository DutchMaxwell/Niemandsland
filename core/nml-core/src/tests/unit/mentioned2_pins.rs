use super::*;

    // --- TEST WAVE (2026-09-15, D-PROOF part 2 chunk 2) — the 15 unit-layer
    // NUMBER pins for the ledger's `mentioned` rows that live on the profile
    // stamp (the 16th row, Rapid Blink, is a sim-layer read and pins in
    // tests/sim/place_d3.rs). Each test reads the rule BY ITS EXACT NAME off
    // the REAL registry (the faction block its book prints) through
    // `UnitStatic::build_for` at `CURRENT_RULES_EPOCH`, with the rule-less /
    // pre-gate arm beside it. The aura rows ride the core's own Aura-Channel
    // expansion: the carried "* Aura" entry grants its base, the base's own
    // fold stamps the number — the whole chain is what the pin holds.

    /// The family's carrier template: one ranged Rifle (24") and one melee
    /// Blade, so the shoot/melee scoping is observable on both arrays.
    const PIN2_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// The REAL `build_for` product: `system`/`faction` swapped in, `rules`
    /// printed as the unit's special_rules.
    fn pin_unit(system: &str, faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
        let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = PIN2_HEADER
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("PIN2_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// "Lucky Boost Aura" (aof/halflings — the aura grants "Lucky Boost",
    /// Surge primitive, surge_low 5 / over_in 9 behind its own
    /// `upgrades: "Lucky"` coupling): the carrier carrying the aura AND the
    /// base "Lucky" stamps the widened 5+ window over 9"; the base alone
    /// stays the plain 6 (6 = no boost) and the pre-gate epoch 5 never
    /// expands the aura at all.
    #[test]
    fn a_lucky_boost_aura_widens_the_surge_window_to_five_over_nine_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "halflings", &["Lucky Boost Aura", "Lucky"], epoch);
        assert_eq!(us.shoot[0].surge_low, 5, "the granted Lucky Boost widens the window to 5+");
        assert_eq!(us.shoot[0].surge_over_in, 9.0, "the 5s count only past 9\"");
        let base_only = pin_unit("aof", "halflings", &["Lucky"], epoch);
        assert_eq!(base_only.shoot[0].surge_low, 6, "without the boost the plain 6 window stands");
        let pre = pin_unit("aof", "halflings", &["Lucky Boost Aura", "Lucky"], 5);
        assert_eq!(pre.shoot[0].surge_low, 6, "epoch 5: the aura gate is OFF, no expansion");
    }

    /// "Lustbound Boost Aura" (aof/lust_disciples — primitive-NULL aura, the
    /// Royal Legion fold's raw-name arm expands it to "Lustbound Boost"):
    /// +8" shooting range, +4" charge — the base entry's own magnitudes
    /// through the expansion; epoch 5 predates wave 3.
    #[test]
    fn a_lustbound_boost_aura_stamps_eight_range_and_four_charge_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        assert_eq!(
            royal_legion_halves("lustbound_boost_aura_unit", epoch),
            (8.0, 4.0),
            "the expansion's base magnitudes: +8\" range, +4\" charge"
        );
        assert_eq!(
            royal_legion_halves("lustbound_boost_aura_unit", 5),
            (0.0, 0.0),
            "epoch 5: the wave-3 gate is OFF"
        );
    }

    /// "Melee Evasion Aura" (aof/lust_disciples — grants "Melee Evasion",
    /// hit_penalty 1, melee only): the granted base fires the ctx stamp and
    /// the melee to-hit fold hands the attacker the -1; a rule-less carrier
    /// keeps the plain 0.
    #[test]
    fn a_melee_evasion_aura_carrier_costs_the_attacker_one_to_hit_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "lust_disciples", &["Melee Evasion Aura"], epoch);
        assert!(us.ctx.melee_evasion, "the granted base fires the ctx stamp");
        assert_eq!(
            crate::combat::melee_hit_modifier(false, us.ctx.melee_evasion, 0, 0.0, false, 0.0),
            -crate::combat::EVASIVE_HIT_PENALTY,
            "the number the rule produces: -1 to hit in melee"
        );
        let plain = pin_unit("aof", "lust_disciples", &[], epoch);
        assert!(!plain.ctx.melee_evasion, "no aura, no stamp");
        assert_eq!(crate::combat::melee_hit_modifier(false, plain.ctx.melee_evasion, 0, 0.0, false, 0.0), 0);
    }

    /// "Melee Slayer Aura" (aof/lust_disciples — grants "Melee Slayer",
    /// ap_bonus 2, charge_only, vs_tough_ge 3): the granted base stamps the
    /// conditional-AP spec the dice fold fires — AP(+2) while charging vs
    /// Tough(3)+, named for the strike log.
    #[test]
    fn a_melee_slayer_aura_stamps_ap_two_vs_tough_three_on_the_charge_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "lust_disciples", &["Melee Slayer Aura"], epoch);
        let c = us.melee[0].cond_ap.first().expect("the granted base stamps the spec");
        assert_eq!(c.ap_bonus, 2, "AP(+2) on the charge");
        assert!(c.charge_only, "only while charging");
        assert_eq!(c.condition, "vs_tough_ge", "gated on the target's Tough");
        assert_eq!(c.threshold, 3, "Tough(3)+");
        assert_eq!(c.name, "Melee Slayer", "the named form, for the strike log");
        let plain = pin_unit("aof", "lust_disciples", &[], epoch);
        assert!(plain.melee[0].cond_ap.is_empty(), "no aura, no spec");
    }

    /// "Ossified Boost Aura" (aof/ossified_undead — grants "Ossified Boost",
    /// Fortified primitive, incoming_ap_reduction 1, no over_in): the
    /// granted base rides the boost arm — EVERY save batch eats 1 AP; a
    /// rule-less carrier keeps 0.
    #[test]
    fn an_ossified_boost_aura_reduces_every_incoming_ap_by_one_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "ossified_undead", &["Ossified Boost Aura"], epoch);
        assert_eq!(us.ctx.fortified_boost_ap, 1, "the granted Boost's incoming_ap_reduction");
        let plain = pin_unit("aof", "ossified_undead", &[], epoch);
        assert_eq!(plain.ctx.fortified_boost_ap, 0, "no aura, no reduction");
    }

    /// "Piercing Hunter Aura" (aof/orcs — grants "Piercing Hunter",
    /// ap_bonus 1, ranged_over 9"): the granted base stamps the generic-pass
    /// spec on BOTH arrays — AP(+1) on shots past 9"; a rule-less carrier
    /// stamps nothing.
    #[test]
    fn a_piercing_hunter_aura_stamps_ap_one_past_nine_inches_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "orcs", &["Piercing Hunter Aura"], epoch);
        for sp in [us.shoot.first().unwrap(), us.melee.first().unwrap()] {
            let c = sp.cond_ap.first().expect("the granted base stamps the spec");
            assert_eq!(c.ap_bonus, 1, "AP(+1)");
            assert_eq!(c.condition, "ranged_over", "the ranged-over gate");
            assert_eq!(c.over_in, 9.0, "past 9\"");
        }
        let plain = pin_unit("aof", "orcs", &[], epoch);
        assert!(plain.shoot[0].cond_ap.is_empty(), "no aura, no spec");
    }

    /// "Piercing Shooter" (aof/ossified_undead, Piercing Hunter primitive,
    /// ap_bonus 1, condition ranged): the wave-3 named arm stamps the spec
    /// the volley reads — AP(+1) at ANY measured distance (the degenerate
    /// over_in -1: the unknown-distance sentinel stays shut); a rule-less
    /// carrier stamps nothing by that name.
    #[test]
    fn a_piercing_shooter_stamps_ap_one_on_every_measured_shot_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "ossified_undead", &["Piercing Shooter"], epoch);
        let c = us
            .shoot[0]
            .cond_ap
            .iter()
            .find(|c| c.name == "Piercing Shooter")
            .expect("the named form stamps its spec");
        assert_eq!(c.ap_bonus, 1, "AP(+1)");
        assert_eq!(c.condition, "ranged_over", "the named arm's spelling");
        assert_eq!(c.over_in, -1.0, "any MEASURED distance fires");
        let plain = pin_unit("aof", "ossified_undead", &[], epoch);
        assert!(
            plain.shoot[0].cond_ap.iter().all(|c| c.name != "Piercing Shooter"),
            "no rule, no named spec"
        );
    }

    /// "Piercing Shooter Aura" (aof/ossified_undead — the Aura-Channel entry
    /// grants "Piercing Shooter"): the aura carrier's named spec carries the
    /// same numbers the bare base stamps, and the rule-less carrier stays
    /// without it.
    #[test]
    fn a_piercing_shooter_aura_grants_the_base_ap_one_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let aura = pin_unit("aof", "ossified_undead", &["Piercing Shooter Aura"], epoch);
        let c = aura
            .shoot[0]
            .cond_ap
            .iter()
            .find(|c| c.name == "Piercing Shooter")
            .expect("the aura's grant stamps the named spec");
        assert_eq!(c.ap_bonus, 1, "the granted base's AP(+1)");
        assert_eq!(c.over_in, -1.0, "any measured distance");
        let plain = pin_unit("aof", "ossified_undead", &[], epoch);
        assert!(
            plain.shoot[0].cond_ap.iter().all(|c| c.name != "Piercing Shooter"),
            "no aura, no grant"
        );
    }

    /// "Plaguebound Boost" (gf/plague_disciples, Regeneration primitive,
    /// all_models, ignore_target 5): the alias fold's MIN picks 5 for BOTH
    /// wound kinds (no `ignore_target_spell` key — the spell twin repeats
    /// the normal target); a rule-less carrier stays 0.
    #[test]
    fn a_plaguebound_boost_carrier_ignores_wounds_on_a_five_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("gf", "plague_disciples", &["Plaguebound Boost"], epoch);
        assert_eq!(us.ctx.regen_target, 5, "the entry's own ignore_target");
        assert_eq!(us.ctx.regen_target_spell, 5, "no spell key: the spell twin repeats 5");
        let plain = pin_unit("gf", "plague_disciples", &[], epoch);
        assert_eq!(plain.ctx.regen_target, 0, "no rule, no regen");
        assert_eq!(plain.ctx.regen_target_spell, 0);
    }

    /// "Protected Aura" (aof/duchies_of_vinci — grants "Protected",
    /// ignore_target 6): the aura carrier folds the 6+ ignore into the regen
    /// MIN; the rule-less carrier and the pre-gate epoch 5 stay 0.
    #[test]
    fn a_protected_aura_carrier_ignores_wounds_on_a_six_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "duchies_of_vinci", &["Protected Aura"], epoch);
        assert_eq!(us.ctx.regen_target, 6, "the granted base's ignore_target");
        let plain = pin_unit("aof", "duchies_of_vinci", &[], epoch);
        assert_eq!(plain.ctx.regen_target, 0, "no aura, no grant");
        let pre = pin_unit("aof", "duchies_of_vinci", &["Protected Aura"], 5);
        assert_eq!(pre.ctx.regen_target, 0, "epoch 5: the aura gate is OFF");
    }

    /// "Quick Shot Aura" (gf/lust_disciples — grants "Quick Shot",
    /// shoot_after_rush): the granted base stamps the ctx flag the volley
    /// seam reads (a RUSH may still shoot — the 1/0 the rule produces); the
    /// rule-less carrier stays false.
    #[test]
    fn a_quick_shot_aura_carrier_may_shoot_after_a_rush_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("gf", "lust_disciples", &["Quick Shot Aura"], epoch);
        assert!(us.quick_shot_active, "the granted base stamps the flag (1)");
        let plain = pin_unit("gf", "lust_disciples", &[], epoch);
        assert!(!plain.quick_shot_active, "no aura, no flag (0)");
    }

    /// "Ranged Slayer Aura" (aof/duchies_of_vinci — grants "Ranged Slayer",
    /// ap_bonus 2, gate ranged_over 9", vs_tough_ge 3): the granted base
    /// stamps the shooting-only spec — AP(+2) on far shots vs Tough(3)+;
    /// the melee array stays empty (the charge leg is deleted).
    #[test]
    fn a_ranged_slayer_aura_stamps_ap_two_on_far_shots_only_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "duchies_of_vinci", &["Ranged Slayer Aura"], epoch);
        let c = us.shoot[0].cond_ap.first().expect("the granted base stamps the spec");
        assert_eq!(c.ap_bonus, 2, "AP(+2)");
        assert_eq!(c.gate, "ranged_over", "shooting-only gate");
        assert_eq!(c.over_in, 9.0, "past 9\"");
        assert_eq!(c.threshold, 3, "vs Tough(3)+");
        assert_eq!(c.name, "Ranged Slayer", "the named form, for the volley log");
        assert!(us.melee[0].cond_ap.is_empty(), "the charge leg is deleted: melee stays empty");
        let plain = pin_unit("aof", "duchies_of_vinci", &[], epoch);
        assert!(plain.shoot[0].cond_ap.is_empty(), "no aura, no spec");
    }

    /// "Rapid Advance Aura" (gf/robot_legions — grants "Rapid Advance",
    /// advance_mod 4): the granted base rides the epoch-7 move-band fold —
    /// +4" advance, no rush half; the pre-gate epochs keep the band None.
    #[test]
    fn a_rapid_advance_aura_extends_the_advance_band_by_four_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("gf", "robot_legions", &["Rapid Advance Aura"], epoch);
        assert_eq!(
            us.move_rule_mods,
            Some(Bands { advance: 4.0, rush: 0.0, ..Default::default() }),
            "the granted base's advance_mod"
        );
        let pre = pin_unit("gf", "robot_legions", &["Rapid Advance Aura"], 5);
        assert_eq!(pre.move_rule_mods, None, "epoch 5: the aura gate is OFF, the fold never fires");
    }

    /// "Rapid Advance Buff" (gf/human_defense_force, Utility Buff primitive):
    /// the record the resolver stamps — grants_rule "Rapid Advance", 12"
    /// range, one target, once, friendly. The rule-less carrier carries no
    /// record.
    #[test]
    fn a_rapid_advance_buff_stamps_a_twelve_inch_single_target_grant_record_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("gf", "human_defense_force", &["Rapid Advance Buff"], epoch);
        let rec = us
            .utility_buffs
            .iter()
            .find(|b| b.name == "Rapid Advance Buff")
            .expect("the buff's own record");
        assert_eq!(rec.grants_rule, "Rapid Advance", "what the grant hands the target");
        assert_eq!(rec.range_in, 12.0, "within 12\"");
        assert_eq!(rec.max_targets, 1, "one target");
        assert!(rec.once, "once per game");
        assert_eq!(rec.target, "friendly", "the friendly side");
        assert!(
            pin_unit("gf", "human_defense_force", &[], epoch)
                .utility_buffs
                .iter()
                .all(|b| b.name != "Rapid Advance Buff"),
            "no rule, no record"
        );
    }

    /// "Rapid Charge Aura" (gf/alien_hives, Fast primitive, charge_only,
    /// rush_mod 4): the row's own entry rides the per-name carrier list —
    /// +4" rush/charge only, no advance half; epoch 0 (below the fold's own
    /// `EPOCH_3_TABLE_RULES` gate) keeps the band None.
    #[test]
    fn a_rapid_charge_aura_extends_the_charge_band_by_four_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        assert_eq!(
            quickfast_bands("rapid_charge_aura_unit", epoch),
            Some(Bands { advance: 0.0, rush: 4.0, ..Default::default() }),
            "the aura entry's own rush_mod, charge-only"
        );
        assert_eq!(quickfast_bands("rapid_charge_aura_unit", 0), None, "epoch 0 is pre-port (the fold's own gate, EPOCH_3_TABLE_RULES)");
    }

    /// "Rapid Charge Mark" (aof/dark_elves, Utility Buff primitive,
    /// vs_target mark): the record the resolver stamps — the enemy-side mark
    /// within 18" needing LOS, one target, once, handing the attacker
    /// "Rapid Charge", riding the attackers side. The rule-less carrier
    /// carries no record.
    #[test]
    fn a_rapid_charge_mark_stamps_an_eighteen_inch_los_mark_record_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "dark_elves", &["Rapid Charge Mark"], epoch);
        let rec = us
            .utility_buffs
            .iter()
            .find(|b| b.name == "Rapid Charge Mark")
            .expect("the mark's own record");
        assert_eq!(rec.grants_rule, "Rapid Charge", "what the mark hands the attacker");
        assert_eq!(rec.range_in, 18.0, "within 18\"");
        assert!(rec.vs_target, "an enemy-side mark");
        assert!(rec.needs_los, "in line of sight");
        assert_eq!(rec.max_targets, 1, "one target");
        assert_eq!(rec.beneficiary, "attackers", "the record belongs to the attacker's side");
        assert!(
            pin_unit("aof", "dark_elves", &[], epoch)
                .utility_buffs
                .iter()
                .all(|b| b.name != "Rapid Charge Mark"),
            "no rule, no record"
        );
    }

    /// "Rapid Rush Aura" (gf/battle_brothers — the loader's expansion shape:
    /// the aura entry carries only `grants`, the import grants the base
    /// "Rapid Rush", rush_mod 6): the post-import profile rides the epoch-7
    /// fold — +6" rush, the aura entry itself kept; epoch 6 (below the gate)
    /// keeps the band None, byte-exact.
    #[test]
    fn a_rapid_rush_aura_profile_extends_the_rush_band_by_six_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("gf", "battle_brothers", &["Rapid Rush Aura", "Rapid Rush"], epoch);
        assert_eq!(
            us.move_rule_mods,
            Some(Bands { advance: 0.0, rush: 6.0, ..Default::default() }),
            "the granted base's rush_mod"
        );
        let pre = pin_unit("gf", "battle_brothers", &["Rapid Rush Aura", "Rapid Rush"], 6);
        assert_eq!(pre.move_rule_mods, None, "epoch 6: granted, not read (byte-exact)");
    }