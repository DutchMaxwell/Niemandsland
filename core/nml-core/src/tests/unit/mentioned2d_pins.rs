use super::*;

    // --- TEST WAVE (2026-09-15, D-PROOF part 2 chunk 4 of 4) — NUMBER pins
    // for the ledger's LAST 15 `mentioned` rows (the 18th, `Unique`, is
    // list-building only and stays NA). Thirteen live on the profile stamp
    // and pin here; "Wave-Step" is a sim-layer placement read and pins in
    // tests/sim/place_d3.rs beside its Bounding family. Every row is read BY
    // ITS EXACT NAME off the REAL registry (the faction block its book
    // prints) through the REAL `build_for` at `CURRENT_RULES_EPOCH` (no
    // epoch bump, nothing changes behaviour), each beside its rule-less /
    // pre-gate control. The read's own trace lines fire only under
    // NML_TRACE_RULES=1, which no core test asserts today (#985's standing
    // note).

    /// The family's carrier template: one Rifle (24", 2 attacks — the volley
    /// pins' seed needs the second die to reach the save batch) and one
    /// Blade, with (system, faction) and the unit's special_rules swapped in.
    const PIN_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// The REAL `build_for` product: `system`/`faction` swapped in, `rules`
    /// printed as the unit's special_rules (aura expansion included).
    fn pin_unit(system: &str, faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
        let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = PIN_HEADER
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("PIN_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// One carrier's `CaptureReads` at `epoch` — the shroud pair lives on the
    /// capture twin, not on `Ctx`.
    fn pin_capture(system: &str, faction: &str, rules: &[&str], epoch: u32) -> CaptureReads {
        let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = PIN_HEADER
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"));
        let header = read_act_header(&tpl).expect("PIN_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        crate::unit::capture_reads_for_epoch(&mut reg, p, epoch)
    }

    /// One rifle volley at 12" (past the 9" versatile gate), quality 4 into
    /// defense 4, ap 0. Seed 27's first two faces are [1, 5] — one hit at
    /// 4+, so the save batch always exists.
    fn volley(us: &UnitStatic, owner: &str) -> crate::dice::ShootResult {
        let att = Ctx { quality: 4, models: 1, ..Default::default() };
        let def = Ctx { defense: 4, models: 1, tough: 1, ..Default::default() };
        crate::dice::resolve_volley_with_tray(
            &[crate::dice::Shooter {
                profiles: &us.shoot,
                keep: &[0],
                attacks: &[2],
                att: &att,
                owner,
            }],
            &def,
            "target",
            12.0,
            12.0,
            true,
            true,
            true,
            true,
            &mut crate::dice::Tray::seeded(27),
        )
    }

    /// "Swift Buff" (gf/robot_legions, Utility Buff primitive): the record
    /// the resolver stamps — grants_rule "Swift", 12" range, one target,
    /// once, friendly. The rule-less carrier carries no record.
    #[test]
    fn a_swift_buff_stamps_a_twelve_inch_single_target_swift_grant_record_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("gf", "robot_legions", &["Swift Buff"], epoch);
        let rec = us
            .utility_buffs
            .iter()
            .find(|b| b.name == "Swift Buff")
            .expect("the buff's own record");
        assert_eq!(rec.grants_rule, "Swift", "what the grant hands the target");
        assert_eq!(rec.range_in, 12.0, "within 12\"");
        assert_eq!(rec.max_targets, 1, "one target");
        assert!(rec.once, "once per game");
        assert_eq!(rec.target, "friendly", "the friendly side");
        assert!(
            pin_unit("gf", "robot_legions", &[], epoch)
                .utility_buffs
                .iter()
                .all(|b| b.name != "Swift Buff"),
            "no rule, no record"
        );
    }

    /// "Targeting Visor Boost" (gf/dao_union, Shot Modifier primitive,
    /// hit_bonus 1, NO over_in): a FLAT +1 on every rifle's to-hit roll —
    /// `hit_bonus_over9` stays 0. A rule-less carrier shoots at the plain 4+.
    #[test]
    fn a_targeting_visor_boost_carrier_shoots_one_better_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("gf", "dao_union", &["Targeting Visor Boost"], epoch);
        assert_eq!(us.shoot[0].hit_bonus, 1, "the entry's own flat hit_bonus");
        assert_eq!(us.shoot[0].hit_bonus_over9, 0, "no over_in: the over-9\" arm stays 0");
        assert_eq!(pin_unit("gf", "dao_union", &[], epoch).shoot[0].hit_bonus, 0, "no rule, no +1");
    }

    /// "Targeting Visor Boost Aura" (gf/dao_union, Aura Channel — the carried
    /// aura entry grants "Targeting Visor Boost"): the same flat +1 through
    /// the grant; epoch 5 keeps the gate OFF (`EPOCH_6_TABLE_RULES`).
    #[test]
    fn a_targeting_visor_boost_aura_carrier_shoots_one_better_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("gf", "dao_union", &["Targeting Visor Boost Aura"], epoch);
        assert_eq!(us.shoot[0].hit_bonus, 1, "the granted Boost's flat hit_bonus");
        assert_eq!(pin_unit("gf", "dao_union", &[], epoch).shoot[0].hit_bonus, 0, "no aura, no +1");
        assert_eq!(
            pin_unit("gf", "dao_union", &["Targeting Visor Boost Aura"], 5).shoot[0].hit_bonus,
            0,
            "epoch 5: the aura gate is OFF, no expansion"
        );
    }

    /// "Teleport Aura" (aof/halflings — the aura grants "Teleport"): the
    /// Teleport-primitive read stamps at `EPOCH_8_PLANNER_MENU` and the cap
    /// by NAME is the entry's own 3"/6" (advance/rush); no aura, or epoch 7,
    /// leaves the read `None`.
    #[test]
    fn a_teleport_aura_carrier_stamps_the_teleport_read_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let spec = pin_unit("aof", "halflings", &["Teleport Aura"], epoch)
            .teleport
            .expect("the aura grants Teleport and the stamp reads it");
        assert_eq!(spec.name, "Teleport", "the cap key and log subject, exactly");
        assert_eq!(teleport_cap_in("Teleport", false), 3.0, "the advance cap");
        assert_eq!(teleport_cap_in("Teleport", true), 6.0, "the rush cap");
        assert!(
            pin_unit("aof", "halflings", &[], epoch).teleport.is_none(),
            "no aura, no stamp"
        );
        assert!(
            pin_unit("aof", "halflings", &["Teleport Aura"], 7).teleport.is_none(),
            "epoch 7 predates the EPOCH_8_PLANNER_MENU read"
        );
    }

    /// "Vale Oath Boost Aura" (aof/chivalrous_kingdoms — the aura grants
    /// "Vale Oath Boost", the Battleborn die-roll recover alias whose entry
    /// carries recover_target 3): the lowest-wins merge stamps 3; the
    /// rule-less carrier rolls no recovery die (0), nor does epoch 5.
    #[test]
    fn a_vale_oath_boost_aura_carrier_recovers_on_a_three_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        assert_eq!(
            pin_unit("aof", "chivalrous_kingdoms", &["Vale Oath Boost Aura"], epoch)
                .battleborn_recover_target,
            3,
            "the granted base's own recover_target through the grant"
        );
        assert_eq!(
            pin_unit("aof", "chivalrous_kingdoms", &[], epoch).battleborn_recover_target,
            0,
            "no aura, no recovery die"
        );
        assert_eq!(
            pin_unit("aof", "chivalrous_kingdoms", &["Vale Oath Boost Aura"], 5)
                .battleborn_recover_target,
            0,
            "epoch 5: the aura gate is OFF, no expansion"
        );
    }

    /// "Versatile Reach Aura" (gf/battle_brothers — UNMAPPED-registered, so
    /// the raw-name arm is the leg that credits the carrier): the CHARGE half
    /// of the pick stamps the base entry's charge_bonus_in 2; the rule-less
    /// carrier stamps None (the +4" range half is not a field at all).
    #[test]
    fn a_versatile_reach_aura_carrier_charges_two_inches_farther_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        assert_eq!(
            pin_unit("gf", "battle_brothers", &["Versatile Reach Aura"], epoch)
                .versatile_reach_charge_in,
            Some(2.0),
            "the raw-name arm reads the base entry's charge_bonus_in"
        );
        assert_eq!(
            pin_unit("gf", "battle_brothers", &[], epoch).versatile_reach_charge_in,
            None,
            "no rule, no charge bonus"
        );
    }

    /// "Vinci Tech" (aof/duchies_of_vinci, Versatile Attack primitive,
    /// ap_bonus 1 / hit_bonus 1 / over_in 9 / pick_one): past 9" the pick
    /// takes the AP arm (ev_ap >= ev_hit at ap 0) — the save steps 4+ -> 5+,
    /// the hit roll stays 4+ — and the volley names the rule
    /// (rules-must-log). A rule-less carrier keeps the plain 4+ and is
    /// silent.
    #[test]
    fn vinci_tech_picks_the_ap_arm_over_nine_inches_at_the_current_epoch() {
        let v6 = volley(&pin_unit("aof", "duchies_of_vinci", &["Vinci Tech"],
            crate::acts::CURRENT_RULES_EPOCH), "vinci");
        assert_eq!(v6.rolls[0].target, 4, "the pick keeps the hit arm shut");
        assert_eq!(v6.rolls[1].target, 5, "AP(+1) over 9\": the save steps to 5+");
        assert!(
            v6.log.iter().any(|l| l.starts_with("Vinci Tech:")),
            "rules-must-log: the volley names the rule: {:?}",
            v6.log
        );
        let none = volley(&pin_unit("aof", "duchies_of_vinci", &[],
            crate::acts::CURRENT_RULES_EPOCH), "vinci");
        assert_eq!(none.rolls[1].target, 4, "no rule, no AP");
        assert!(none.log.iter().all(|l| !l.starts_with("Vinci Tech:")), "no rule, no log");
    }

    /// "Vinci Tech Boost" (aof/duchies_of_vinci, pick_one FALSE — the
    /// BOTH-arms form): beside its base the bearer gets the hit arm TOO —
    /// attack 3+ AND save 5+ — and names itself on the log. The Boost alone
    /// never engages (the rule's own printed condition): the generic pick's
    /// AP arm stays, no hit arm, no log.
    #[test]
    fn vinci_tech_boost_gets_both_arms_beside_its_base_at_the_current_epoch() {
        let on = volley(
            &pin_unit("aof", "duchies_of_vinci",
                &["Vinci Tech", "Vinci Tech Boost"], crate::acts::CURRENT_RULES_EPOCH),
            "vinci",
        );
        assert_eq!(on.rolls[0].target, 3, "the hit arm fires TOO (both, not pick)");
        assert_eq!(on.rolls[1].target, 5, "the AP arm fires as well");
        assert!(
            on.log.iter().any(|l| l.starts_with("Vinci Tech Boost:")),
            "rules-must-log: the volley names the boost: {:?}",
            on.log
        );
        let lone = volley(
            &pin_unit("aof", "duchies_of_vinci", &["Vinci Tech Boost"],
                crate::acts::CURRENT_RULES_EPOCH),
            "vinci",
        );
        assert_eq!(lone.rolls[0].target, 4, "the `pick_one` coupling: no hit arm alone");
        assert_eq!(lone.rolls[1].target, 5, "the generic pick's AP arm (pre-existing)");
        assert!(
            lone.log.iter().all(|l| !l.starts_with("Vinci Tech Boost:")),
            "the Boost alone does not fire, no log: {:?}",
            lone.log
        );
    }

    /// "Vinci Tech Boost Aura" (aof/duchies_of_vinci — the Aura-Channel
    /// entry grants "Vinci Tech Boost"): beside the base the grant reaches
    /// the BOTH-arms form (attack 3+ AND save 5+); at epoch 5 the aura gate
    /// is OFF and the pick stays byte-exact.
    #[test]
    fn a_vinci_tech_boost_aura_reaches_both_arms_through_the_grant_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let via_aura = volley(
            &pin_unit("aof", "duchies_of_vinci",
                &["Vinci Tech", "Vinci Tech Boost Aura"], epoch),
            "vinci",
        );
        assert_eq!(via_aura.rolls[0].target, 3, "the granted Boost arms the hit half");
        assert_eq!(via_aura.rolls[1].target, 5, "the AP half rides the same grant");
        let pre = volley(
            &pin_unit("aof", "duchies_of_vinci",
                &["Vinci Tech", "Vinci Tech Boost Aura"], 5),
            "vinci",
        );
        assert_eq!(pre.rolls[0].target, 4, "epoch 5: no expansion, no both-arms form");
    }

    /// "Warden Boost Aura" (aof/eternal_wardens — the aura grants "Warden
    /// Boost", Fortified primitive, incoming_ap_reduction 1): the carrier's
    /// incoming AP folds one step lighter through the grant; no aura, or
    /// epoch 5, keeps the plain reading.
    #[test]
    fn a_warden_boost_aura_carrier_reduces_incoming_ap_by_one_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "eternal_wardens", &["Warden Boost Aura"], epoch);
        assert_eq!(us.ctx.fortified_boost_ap, 1, "the granted Boost's incoming_ap_reduction");
        assert_eq!(us.fortified_boost_name, "Warden Boost", "the boost names its rule");
        assert_eq!(
            pin_unit("aof", "eternal_wardens", &[], epoch).ctx.fortified_boost_ap,
            0,
            "no aura, no fold"
        );
        assert_eq!(
            pin_unit("aof", "eternal_wardens", &["Warden Boost Aura"], 5).ctx.fortified_boost_ap,
            0,
            "epoch 5: the aura gate is OFF, no expansion"
        );
    }

    /// "Wave-Step Boost Aura" (aof/deep_sea_elves — the aura grants "Wave-
    /// Step Boost", whose `place_die: "2d3"` doubles the placement dice
    /// behind the `upgrades: "Wave-Step"` coupling): the carrier carrying
    /// the aura AND the base stamps dice 2; the aura alone (no base) and
    /// every pre-gate epoch keep the base single die (0 = no Boost).
    #[test]
    fn a_wave_step_boost_aura_rolls_two_placement_dice_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        assert_eq!(
            pin_unit("aof", "deep_sea_elves", &["Wave-Step", "Wave-Step Boost Aura"], epoch)
                .bounding_dice,
            2,
            "the granted Boost's own place_die \"2d3\" through the grant"
        );
        assert_eq!(
            pin_unit("aof", "deep_sea_elves", &["Wave-Step"], epoch).bounding_dice,
            0,
            "no Boost, no second die"
        );
        assert_eq!(
            pin_unit("aof", "deep_sea_elves", &["Wave-Step", "Wave-Step Boost Aura"], 6)
                .bounding_dice,
            0,
            "epoch 6: pre-port records read the base single die"
        );
    }

    /// "Wild Veil" (aof/wood_elves, Ranged Shrouding primitive, range 4" to
    /// a 6" floor, melee-move half 2"): the ctx stamps the range pair, the
    /// capture twin the melee pair; the rule-less carrier reads plain.
    #[test]
    fn a_wild_veil_carrier_shrouds_four_inches_of_range_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "wood_elves", &["Wild Veil"], epoch);
        assert!(us.ctx.ranged_shrouding, "the alias arms the shroud");
        assert_eq!(
            (us.ctx.ranged_shroud_penalty_in, us.ctx.ranged_shroud_floor_in),
            (4.0, 6.0),
            "the entry's own range_penalty_in/floor_in"
        );
        assert_eq!(
            pin_capture("aof", "wood_elves", &["Wild Veil"], epoch).shroud,
            Some([2.0, 6.0]),
            "the entry's melee_move_penalty_in/melee_floor_in"
        );
        let plain = pin_unit("aof", "wood_elves", &[], epoch);
        assert!(!plain.ctx.ranged_shrouding, "no rule, no shroud flag");
        assert_eq!(pin_capture("aof", "wood_elves", &[], epoch).shroud, None, "no rule, no pair");
    }

    /// "Wild Veil Boost" (aof/wood_elves — the upgrade entry: range 8" to
    /// the same 6" floor, melee-move half 4"): its own numbers on both
    /// halves.
    #[test]
    fn a_wild_veil_boost_carrier_shrouds_eight_inches_of_range_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "wood_elves", &["Wild Veil Boost"], epoch);
        assert_eq!(us.ctx.ranged_shroud_penalty_in, 8.0, "the Boost's own -8\"");
        assert_eq!(us.ctx.ranged_shroud_floor_in, 6.0, "the shared 6\" floor");
        assert_eq!(
            pin_capture("aof", "wood_elves", &["Wild Veil Boost"], epoch).shroud,
            Some([4.0, 6.0]),
            "the Boost's widened melee-move penalty"
        );
    }

    /// "Wild Veil Boost Aura" (aof/wood_elves — the aura grants "Wild Veil
    /// Boost"): the Boost's own 8"/4" through the grant; epoch 5 keeps the
    /// plain reading.
    #[test]
    fn a_wild_veil_boost_aura_carrier_shrouds_eight_inches_through_the_grant_at_the_current_epoch() {
        let epoch = crate::acts::CURRENT_RULES_EPOCH;
        let via_aura = pin_unit("aof", "wood_elves", &["Wild Veil Boost Aura"], epoch);
        assert_eq!(via_aura.ctx.ranged_shroud_penalty_in, 8.0, "the grant rides the same read");
        assert_eq!(
            pin_capture("aof", "wood_elves", &["Wild Veil Boost Aura"], epoch).shroud,
            Some([4.0, 6.0]),
            "the melee half through the grant"
        );
        assert!(
            !pin_unit("aof", "wood_elves", &["Wild Veil Boost Aura"], 5).ctx.ranged_shrouding,
            "epoch 5: the aura gate is OFF, no expansion"
        );
    }
