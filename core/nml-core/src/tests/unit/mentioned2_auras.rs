use super::*;

    // --- TEST WAVE (part 2, chunk 3 of 4; D-PROOF 14.09.) — NUMBER pins for
    // the ledger's `mentioned` rows that ride the unit stamp, the two
    // aura-channel folds and the capture twin. Every row is read BY ITS
    // EXACT NAME off the REAL registry at `CURRENT_RULES_EPOCH` (no epoch
    // bump, nothing changes behaviour), each beside its rule-less control;
    // the aura rows also carry the below-gate epoch-5 leg (the frozen
    // `EPOCH_6_TABLE_RULES` window). The reads' own trace lines fire only
    // under NML_TRACE_RULES=1, which no core test asserts today (#985's
    // standing note).

    /// The family's carrier template: one rifle (AP 0, 24") and one blade, so
    /// both facets are observable, with (system, faction) and the unit's
    /// special_rules swapped in — the REAL `build_for` product, aura
    /// expansion included.
    const PIN_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn pin_header(system: &str, faction: &str, rules: &[&str]) -> crate::acts::ActHeader {
        let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = PIN_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"))
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""));
        read_act_header(&tpl).expect("PIN_HEADER parses")
    }

    /// One carrier's `UnitStatic` at `epoch`, built through the REAL registry.
    fn pin_unit(system: &str, faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
        let header = pin_header(system, faction, rules);
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// One carrier's `CaptureReads` at `epoch` — the Strider/Shroud reads live
    /// there, not on `Ctx`.
    fn pin_capture(system: &str, faction: &str, rules: &[&str], epoch: u32) -> CaptureReads {
        let header = pin_header(system, faction, rules);
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        crate::unit::capture_reads_for_epoch(&mut reg, p, epoch)
    }

    /// "Strider Aura" (gf/rebel_guerrillas, aof rift_daemons_of_lust et al.,
    /// Aura Channel -> "Strider"): the granted base is the p.13 exemption —
    /// `charge_no_difficult` on the capture twin. No aura, or the aura below
    /// `EPOCH_6_TABLE_RULES`, keeps the plain reading.
    #[test]
    fn a_strider_aura_carrier_skips_difficult_terrain_at_the_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        assert!(
            pin_capture("gf", "rebel_guerrillas", &["Strider Aura"], e).charge_no_difficult,
            "the granted Strider stamps the p.13 difficult-terrain exemption"
        );
        assert!(
            !pin_capture("gf", "rebel_guerrillas", &[], e).charge_no_difficult,
            "no aura, no exemption"
        );
        assert!(
            !pin_capture("gf", "rebel_guerrillas", &["Strider Aura"], 5).charge_no_difficult,
            "epoch 5: the aura gate is OFF — RED before the break"
        );
    }

    /// "Rending in Melee Aura" (gf/rebel_guerrillas, aof saurians et al.):
    /// the granted "Rending in Melee" is melee-only — the melee profiles
    /// rend, the rifle stays clean; the rule-less carrier rends nowhere.
    #[test]
    fn a_rending_in_melee_aura_rends_only_the_melee_profiles_at_the_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("gf", "rebel_guerrillas", &["Rending in Melee Aura"], e);
        assert!(us.melee[0].rending, "the granted base arms the melee facet");
        assert!(!us.shoot[0].rending, "the entry prints melee_only — the rifle stays clean");
        let plain = pin_unit("gf", "rebel_guerrillas", &[], e);
        assert!(!plain.melee[0].rending && !plain.shoot[0].rending, "no aura, no rending");
    }

    /// "Speed Feat Aura" (aof/orcs, gf/orc_marauders): the granted "Speed
    /// Feat" is the once-per-game move feat — the stamp carries the entry's
    /// own advance_mod/rush_mod (+2/+4) for the move seam's latch reader; a
    /// rule-less carrier stamps None.
    #[test]
    fn a_speed_feat_aura_stamps_the_once_per_game_move_feat_at_the_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let feat = pin_unit("aof", "orcs", &["Speed Feat Aura"], e)
            .speed_feat
            .expect("the aura grants the feat and the stamp reads it");
        assert_eq!(feat.name, "Speed Feat", "the base name, exactly");
        assert_eq!((feat.advance_mod, feat.rush_mod), (2.0, 4.0), "the entry's own mods");
        assert!(
            pin_unit("aof", "orcs", &[], e).speed_feat.is_none(),
            "no aura, no feat stamp"
        );
    }

    /// "Reanimation Aura" (aof/vampiric_undead; gf/robot_legions' twin is
    /// #983's pin): the Aura-Channel grant reaches the same
    /// `restore_target` 5 the base stamps — at the current epoch, `None`
    /// without the aura and below `EPOCH_7_TABLE_RULES`.
    #[test]
    fn a_reanimation_aura_restores_on_a_five_at_the_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "vampiric_undead", &["Reanimation Aura"], e);
        assert_eq!(
            us.reanimation.expect("the aura grants the base").target,
            5,
            "the vampiric_undead block's own restore_target through the grant"
        );
        assert!(
            pin_unit("aof", "vampiric_undead", &[], e).reanimation.is_none(),
            "no aura, no stamp"
        );
        assert!(
            pin_unit("aof", "vampiric_undead", &["Reanimation Aura"], 6).reanimation.is_none(),
            "epoch 6 replays the pre-gate reading"
        );
    }

    /// The Royal Warrior surge family (aof/dragon_empire): the base "Royal
    /// Warrior" is the extra-ATTACK-DIE Surge form (`surge_attack`, natural
    /// 6s); the Boost's own `surge_low` 5 widens the window ONLY where the
    /// base rule is also carried (the upgrades arm), and the Boost Aura
    /// reaches the same 5 through the grant.
    #[test]
    fn the_royal_warrior_surge_family_upgrades_to_fives_at_the_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let base = pin_unit("aof", "dragon_empire", &["Royal Warrior"], e);
        assert!(base.melee[0].surge_attack, "the base's extra-attack-die facet");
        assert_eq!(base.melee[0].surge_attack_low, 6, "unboosted, the natural 6s pay");
        let boosted = pin_unit("aof", "dragon_empire", &["Royal Warrior", "Royal Warrior Boost"], e);
        assert_eq!(
            boosted.melee[0].surge_attack_low, 5,
            "the Boost entry's own surge_low, read only beside the base"
        );
        let via_aura =
            pin_unit("aof", "dragon_empire", &["Royal Warrior Boost Aura", "Royal Warrior"], e);
        assert_eq!(
            via_aura.melee[0].surge_attack_low, 5,
            "the Aura-Channel grant rides the same upgrade arm"
        );
        let aura_alone = pin_unit("aof", "dragon_empire", &["Royal Warrior Boost Aura"], e);
        assert!(
            !aura_alone.melee[0].surge_attack,
            "no base rule to upgrade: the Boost alone stamps nothing"
        );
    }

    /// "Predator Shooter Aura" (gf/ratmen_clans): the Aura-Channel grant
    /// reaches the Surge stamp #982 pinned for the printed base — the
    /// shooting facet arms, the melee facet stays shut (`shooting_only`);
    /// no aura, or the aura below the frozen `EPOCH_6_TABLE_RULES`, keeps
    /// both inert.
    #[test]
    fn a_predator_shooter_aura_arms_the_surge_shooting_only_at_the_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("gf", "ratmen_clans", &["Predator Shooter Aura"], e);
        assert!(us.shoot[0].surge_attack, "the granted base arms the shooting surge facet");
        assert!(!us.melee[0].surge_attack, "shooting_only: the blade's melee facet stays shut");
        assert!(
            !pin_unit("gf", "ratmen_clans", &[], e).shoot[0].surge_attack,
            "no aura, no surge"
        );
        assert!(
            !pin_unit("gf", "ratmen_clans", &["Predator Shooter Aura"], 5).shoot[0].surge_attack,
            "epoch 5: the aura gate is OFF (EPOCH_6_TABLE_RULES) — RED before the break"
        );
    }

    /// The Shadowborn shroud family (aof/shadow_stalkers): the base and its
    /// Boost stamp the Ranged-Shrouding alias numbers (-4"/-8" range to a 6"
    /// floor) on the ctx and the melee-move shroud pair on the capture twin;
    /// the Boost Aura reaches the Boost's own 8/4 through the grant. No rule,
    /// no shroud.
    #[test]
    fn the_shadowborn_shroud_family_stamps_its_penalties_at_the_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let base = pin_unit("aof", "shadow_stalkers", &["Shadowborn"], e);
        assert!(base.ctx.ranged_shrouding, "the alias arms the shroud");
        assert_eq!(
            (base.ctx.ranged_shroud_penalty_in, base.ctx.ranged_shroud_floor_in),
            (4.0, 6.0),
            "the base entry's own range_penalty_in/floor_in"
        );
        assert_eq!(
            pin_capture("aof", "shadow_stalkers", &["Shadowborn"], e).shroud,
            Some([2.0, 6.0]),
            "the entry's melee_move_penalty_in/melee_floor_in"
        );
        let boost = pin_unit("aof", "shadow_stalkers", &["Shadowborn Boost"], e);
        assert_eq!(boost.ctx.ranged_shroud_penalty_in, 8.0, "the Boost's own -8\"");
        assert_eq!(
            pin_capture("aof", "shadow_stalkers", &["Shadowborn Boost"], e).shroud,
            Some([4.0, 6.0]),
            "the Boost's widened melee-move penalty"
        );
        let via_aura = pin_unit("aof", "shadow_stalkers", &["Shadowborn Boost Aura"], e);
        assert_eq!(via_aura.ctx.ranged_shroud_penalty_in, 8.0, "the grant rides the same read");
        let plain = pin_unit("aof", "shadow_stalkers", &[], e);
        assert!(!plain.ctx.ranged_shrouding, "no rule, no shroud flag");
        assert_eq!(pin_capture("aof", "shadow_stalkers", &[], e).shroud, None, "no rule, no pair");
    }

    /// "Sergeant" (gf+aof+the rest `common`, primitive Sergeant,
    /// bonus_hits_per_six 1): its share needs the LIVE alive count, so the
    /// static stamp REPORTS the gap by the exact name instead of guessing a
    /// number — the report is the rule's honest core output, and the melee
    /// share stays 0.
    #[test]
    fn a_sergeant_reports_its_live_count_gap_at_the_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("gf", "knight_brothers", &["Sergeant"], e);
        assert_eq!(
            us.unimplemented.iter().filter(|u| u.rule == "Sergeant").count(),
            1,
            "exactly one report, by the exact name"
        );
        assert_eq!(us.melee[0].sergeant_attacks, 0, "the share is never guessed on the static");
        assert!(
            pin_unit("gf", "knight_brothers", &[], e)
                .unimplemented
                .iter()
                .all(|u| u.rule != "Sergeant"),
            "no rule, no report"
        );
    }

    /// "Regeneration Buff" (aof/ossified_undead; gf/dark_elf_raiders and
    /// gf/wormhole_daemons_of_plague field their own blocks): the
    /// Regeneration-primitive alias folds its `ignore_target` 5 into BOTH
    /// halves — (5, 5) at the current epoch, zeros without the rule.
    #[test]
    fn a_regeneration_buff_folds_a_five_into_both_regen_targets_at_the_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        assert_eq!(
            regen_pair_at(&pin_header("aof", "ossified_undead", &["Regeneration Buff"]), "carrier", e),
            (5, 5),
            "the aof block's own ignore_target on both halves"
        );
        assert_eq!(
            regen_pair_at(&pin_header("gf", "dark_elf_raiders", &["Regeneration Buff"]), "carrier", e),
            (5, 5),
            "the gf dark_elf_raiders block folds the same 5"
        );
        assert_eq!(
            regen_pair_at(
                &pin_header("gf", "wormhole_daemons_of_plague", &["Regeneration Buff"]),
                "carrier",
                e
            ),
            (5, 5),
            "the gf wormhole_daemons_of_plague block folds the same 5"
        );
        assert_eq!(
            regen_pair_at(&pin_header("aof", "ossified_undead", &[]), "carrier", e),
            (0, 0),
            "no rule, no fold"
        );
    }

    /// "Royal Legion Boost Aura" (aof/mummified_undead): the entry carries
    /// the Royal Legion primitive DIRECTLY (no grants channel) — its own
    /// range_bonus_in 4 / charge_mod 2 are the aura's numbers; the rule-less
    /// carrier stamps 0/0.
    #[test]
    fn a_royal_legion_boost_aura_stamps_reach_and_charge_at_the_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = pin_unit("aof", "mummified_undead", &["Royal Legion Boost Aura"], e);
        assert_eq!(
            (us.royal_legion_range_in, us.royal_legion_charge_in),
            (4.0, 2.0),
            "the entry's own range_bonus_in/charge_mod"
        );
        let plain = pin_unit("aof", "mummified_undead", &[], e);
        assert_eq!((plain.royal_legion_range_in, plain.royal_legion_charge_in), (0.0, 0.0));
    }

    /// "Swift Aura" (gf/dwarf_guilds, aof dwarves et al.): the Aura-Channel
    /// fold grants "Swift" BEFORE the band stamp, and the granted name
    /// cancels the printed Slow fold — the carrier folds nothing while a
    /// Slow-only unit keeps the flat -2"/-4".
    #[test]
    fn a_swift_aura_cancels_the_slow_band_stamp_at_the_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        assert_eq!(
            pin_unit("gf", "dwarf_guilds", &["Slow", "Swift Aura"], e).move_rule_mods,
            None,
            "the granted Swift cancels the Slow fold — nothing stamps"
        );
        assert_eq!(
            pin_unit("gf", "dwarf_guilds", &["Slow"], e).move_rule_mods,
            Some(Bands { advance: -2.0, rush: -4.0, ..Default::default() }),
            "a Slow-only unit keeps the flat -2/-4 fold"
        );
    }
