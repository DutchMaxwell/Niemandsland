use super::*;

    // --- Wave 3 "Boost Aura (tail)" family — tests (rules-wave3-aura4). ---

    /// WIRING: the expansion reaches the static layer — a carrier printed with
    /// ONLY "Hold the Line Boost Aura" captures at +2 morale through
    /// `build_for` at epoch 6 (the core's own additive leg hands "Hold the
    /// Line Boost" to `banner_bonus_of`'s Banner-primitive alias), NOT at
    /// epoch 5 (the gate is off there, the import expansion is the only leg —
    /// RED before the fix). human_defense_force carries BOTH the aura entry
    /// and the base's Banner-primitive entry, so the same-faction lookup
    /// resolves (the Shot-Modifier Boosts' bases live in other factions'
    /// blocks — dao_union — and would not resolve here).
    #[test]
    fn a_hold_the_line_boost_aura_carrier_captures_at_plus_two_only_at_epoch_6() {
        let build = |epoch: u32| {
            let p = boost_aura_profile(
                "human_defense_force",
                "[\"Hold the Line Boost Aura\"]",
                "[]",
                epoch,
            );
            capture_reads(&mut Registries::new(&repo_root()), &p).morale_bonus
        };
        assert_eq!(build(6), 2, "epoch 6: build_for consumes the core-read grant");
        assert_eq!(build(5), 0, "epoch 5: the gate is OFF — RED before the fix");
    }

    /// HERO LEG: a hero carried by the host prints the aura on the HERO's own
    /// list — the loader's member loop grants the base to EVERY member (the
    /// host AND the hero), because `AiEv.rule_on_all_models` (ai_ev.gd:79-83)
    /// reads the hero's list. Epoch 6 core-read; epoch 5 untouched (the import
    /// leg already ran there — unchanged). `attached_hero_rules` is one list
    /// PER HERO, hence the nested array.
    #[test]
    fn a_hero_boost_aura_stamps_the_base_on_host_and_hero_at_epoch_6() {
        let read = |epoch: u32| {
            let (special, heroes) = boost_aura_expanded(
                "[\"Hold the Line Boost\"]",
                "[[\"Hold the Line Boost Aura\"]]",
                epoch,
            );
            (
                special.iter().any(|r| r == "Hold the Line Boost"),
                heroes.iter().any(|h| h.iter().any(|r| r == "Hold the Line Boost")),
            )
        };
        assert_eq!(read(6), (true, true), "epoch 6: host and hero both carry the base");
        assert_eq!(read(5), (true, false), "epoch 5: the gate is OFF — RED before the fix");
    }

    #[test]
    fn the_four_chaos_storms_stamp_their_own_registry_params_at_epoch_six() {
        let cases: [(&str, &str, StormFacet); 4] = [
            ("Storm of Change", "wormhole_daemons_of_change", StormFacet::Shred),
            ("Storm of Lust", "wormhole_daemons_of_lust", StormFacet::Surge),
            ("Storm of Plague", "wormhole_daemons_of_plague", StormFacet::Bane),
            ("Storm of War", "wormhole_daemons_of_war", StormFacet::Ap1),
        ];
        for (rule, faction, facet) in cases {
            let specs = storm_spec(rule, faction, 6);
            assert_eq!(specs.len(), 1, "{rule} stamps exactly its own entry");
            let s = &specs[0];
            assert_eq!((s.name.as_str(), s.dice, s.trigger, s.range_in, s.hits, s.facet),
                (rule, 3, 2, 12.0, 3, facet), "{rule}: the printed burst shape");
            assert!(
                storm_spec(rule, faction, 5).is_empty(),
                "{rule}: epoch 5 predates the wave-3 port"
            );
        }
    }

    #[test]
    fn unstoppable_mark_carrier_is_ev_only_a_real_unstoppable_reaches_both() {
        let header = read_act_header(HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());

        let mark_carrier = header.profiles.get("mark_carrier").expect("mark_carrier");
        let marked = UnitStatic::build(&mut reg, mark_carrier);
        assert!(
            !marked.shoot[0].unstoppable,
            "an Unstoppable MARK carrier is not Unstoppable on the tray — \
             ai_shooting.gd:132 reads only the weapon's own exact rule"
        );
        assert!(
            marked.shoot[0].unstoppable_ev,
            "the EV imagination's unit-level prefix scan (battle_sim.gd:1003-1021) \
             still ORs the Mark's name onto every profile — unchanged from before this fix"
        );

        let real_unstop = header.profiles.get("real_unstop").expect("real_unstop");
        let real = UnitStatic::build(&mut reg, real_unstop);
        assert!(
            real.shoot[0].unstoppable,
            "the weapon's own exact \"Unstoppable\" rule reaches the tray (ai_shooting.gd:132)"
        );
        assert!(
            real.shoot[0].unstoppable_ev,
            "and the EV field follows — `unstoppable_ev = unstoppable || u_unstop`"
        );
    }

    /// "Ambushing Piercing Shot" (gf/jackals): counts-as + the arrival-round
    /// AP(+1) at epoch 5 — and NOTHING at epoch 4 (Gen-2b's stamping-gap
    /// window — see `acts::EPOCH_5_TABLE_RULES`) or without the rule. Epoch
    /// literals 5/4, NOT `CURRENT_RULES_EPOCH`: a wave-3 bump must not
    /// re-date what these assertions mean.
    #[test]
    fn an_ambushing_piercing_shot_counts_as_ambush_with_its_arrival_round_ap_at_epoch_5() {
        assert_eq!(
            ambush_family_of("Ambushing Piercing Shot", "jackals", 5),
            AmbushFamily { counts_as_ambush: true, deploy_round_ap: 1, ..Default::default() },
            "counts-as and the AP(+1) at the family's own epoch"
        );
        assert_eq!(
            ambush_family_of("Ambushing Piercing Shot", "jackals", 4),
            AmbushFamily::default(),
            "the wave is epoch-gated: rules_epoch 4 is Gen-2b's stamping-gap window, RED before the fix"
        );
        assert_eq!(
            ambush_family_of("", "jackals", 5),
            AmbushFamily::default(),
            "no rule, no stamp"
        );
    }

    /// "Piercing Tag" (gf/alien_hives): range 24, LOS, ONE marker off the
    /// bare name's maxi(rule_rating, 1) — and a rated form "Piercing Tag(2)"
    /// places TWO. RED before the fix: the stamp reads empty everywhere.
    #[test]
    fn piercing_tag_stamps_its_pick_and_marker_count_at_epoch_6() {
        assert_eq!(
            piercing_tags_of("Piercing Tag", "alien_hives", 6),
            vec![PiercingTagEntry {
                name: "Piercing Tag".into(),
                markers: 1,
                range_in: 24.0,
                needs_los: true,
            }],
            "the gf/alien_hives entry: 24\"/LOS, the bare name's one marker"
        );
        assert_eq!(
            piercing_tags_of("Piercing Tag(2)", "alien_hives", 6)[0].markers, 2,
            "the RAW rule string's parsed rating is the marker count (main.gd:17022)"
        );
        assert!(
            piercing_tags_of("Piercing Tag", "alien_hives", 5).is_empty(),
            "the wave is epoch-gated: the fleet stamps rules_epoch 5 and wave 3 does not exist in that recorder"
        );
        assert!(piercing_tags_of("", "alien_hives", 6).is_empty(), "no rule, no stamp");
    }

    /// "Piercing Spotter" (gf/high_elf_fleets): its OWN params (range 30);
    /// `place_roll` is dead data on the TABLE's own resolver (main.gd:17002
    /// never rolls) — the AI places the same maxi(rating, 1) marker. RED
    /// before the fix.
    #[test]
    fn piercing_spotter_stamps_its_own_params_at_epoch_6() {
        assert_eq!(
            piercing_tags_of("Piercing Spotter", "high_elf_fleets", 6),
            vec![PiercingTagEntry {
                name: "Piercing Spotter".into(),
                markers: 1,
                range_in: 30.0,
                needs_los: true,
            }],
            "the gf/high_elf_fleets entry: 30\"/LOS, no die roll — the table rolls none either"
        );
        assert!(
            piercing_tags_of("Piercing Spotter", "high_elf_fleets", 5).is_empty(),
            "the wave is epoch-gated: rules_epoch 5 predates wave 3"
        );
        assert!(piercing_tags_of("", "high_elf_fleets", 6).is_empty(), "no rule, no stamp");
    }

    /// "Piercing Target" (gf/custodian_brothers): its OWN params (range 18);
    /// the table implements its "+AP(X) when attacking" with the same pool +
    /// spend-everything volley seam the other two names ride. RED before the
    /// fix.
    #[test]
    fn piercing_target_stamps_its_own_params_at_epoch_6() {
        assert_eq!(
            piercing_tags_of("Piercing Target", "custodian_brothers", 6),
            vec![PiercingTagEntry {
                name: "Piercing Target".into(),
                markers: 1,
                range_in: 18.0,
                needs_los: true,
            }],
            "the gf/custodian_brothers entry: 18\"/LOS, the same pool the volley spends"
        );
        assert!(
            piercing_tags_of("Piercing Target", "custodian_brothers", 5).is_empty(),
            "the wave is epoch-gated: rules_epoch 5 predates wave 3"
        );
        assert!(piercing_tags_of("", "custodian_brothers", 6).is_empty(), "no rule, no stamp");
    }

    /// "Ambush Beacon" (gf/eternal_dynasty): the registry's `beacon_in` is
    /// the waiver radius at epoch 5; epoch 4 (Gen-2b's stamping-gap window)
    /// and the rule-less carrier stay 0.0 (the caller's constant answers for
    /// them).
    #[test]
    fn an_ambush_beacons_radius_is_the_registrys_beacon_in_at_epoch_5() {
        assert_eq!(
            ambush_family_of("Ambush Beacon", "eternal_dynasty", 5).beacon_radius_in,
            6.0,
            "the registry's own beacon_in"
        );
        assert_eq!(
            ambush_family_of("Ambush Beacon", "eternal_dynasty", 4).beacon_radius_in,
            0.0,
            "the wave is epoch-gated: rules_epoch 4 is Gen-2b's stamping-gap window, RED before the fix"
        );
        assert_eq!(
            ambush_family_of("", "eternal_dynasty", 5).beacon_radius_in,
            0.0,
            "no rule, no beacon"
        );
    }

    /// "Honor Code" (gf/titan_lords): `recover_target` 4 at epoch 6 — and
    /// NOTHING at epoch 5 (the flat Battleborn/Steadfast free-clear epoch) or
    /// without the rule. Epoch literals 6/5, NOT `CURRENT_RULES_EPOCH`: a
    /// wave-4 bump must not re-date what these assertions mean.
    #[test]
    fn an_honor_code_stamps_recover_target_4_at_epoch_6() {
        assert_eq!(
            battleborn_target_of("Honor Code", "gf", "titan_lords", 6),
            4,
            "the registry's own recover_target"
        );
        assert_eq!(
            battleborn_target_of("Honor Code", "gf", "titan_lords", 5),
            0,
            "the wave is epoch-gated: rules_epoch 5 replays the free-clear reading, RED before the fix"
        );
        assert_eq!(battleborn_target_of("", "gf", "titan_lords", 6), 0, "no rule, no stamp");
    }

    /// "Vale Oath" (aof/chivalrous_kingdoms): `recover_target` 4 at epoch 6;
    /// epoch 5 and the rule-less carrier stay 0.
    #[test]
    fn a_vale_oath_stamps_recover_target_4_at_epoch_6() {
        assert_eq!(
            battleborn_target_of("Vale Oath", "aof", "chivalrous_kingdoms", 6),
            4,
            "the registry's own recover_target"
        );
        assert_eq!(
            battleborn_target_of("Vale Oath", "aof", "chivalrous_kingdoms", 5),
            0,
            "the wave is epoch-gated: rules_epoch 5 replays the free-clear reading, RED before the fix"
        );
        assert_eq!(battleborn_target_of("", "aof", "chivalrous_kingdoms", 6), 0, "no rule, no stamp");
    }

    /// "Vale Oath Boost" (aof/chivalrous_kingdoms): the Boost's own
    /// `recover_target` 3 at epoch 6 — the 3+-instead-of-4+ text —; epoch 5
    /// and the rule-less carrier stay 0.
    #[test]
    fn a_vale_oath_boost_stamps_recover_target_3_at_epoch_6() {
        assert_eq!(
            battleborn_target_of("Vale Oath Boost", "aof", "chivalrous_kingdoms", 6),
            3,
            "the registry's own recover_target — the 3+ extension"
        );
        assert_eq!(
            battleborn_target_of("Vale Oath Boost", "aof", "chivalrous_kingdoms", 5),
            0,
            "the wave is epoch-gated: rules_epoch 5 replays the free-clear reading, RED before the fix"
        );
        assert_eq!(battleborn_target_of("", "aof", "chivalrous_kingdoms", 6), 0, "no rule, no stamp");
    }

    /// "Unmovable" (aof/giant_tribes): `recover_target` 4 at epoch 6; epoch 5
    /// and the rule-less carrier stay 0.
    #[test]
    fn an_unmovable_stamps_recover_target_4_at_epoch_6() {
        assert_eq!(
            battleborn_target_of("Unmovable", "aof", "giant_tribes", 6),
            4,
            "the registry's own recover_target"
        );
        assert_eq!(
            battleborn_target_of("Unmovable", "aof", "giant_tribes", 5),
            0,
            "the wave is epoch-gated: rules_epoch 5 replays the free-clear reading, RED before the fix"
        );
        assert_eq!(battleborn_target_of("", "aof", "giant_tribes", 6), 0, "no rule, no stamp");
    }

    /// "Rapid Ambush" (gf/dark_brothers): `arrive_from_round` 1 at epoch 5 —
    /// the round the table's `ambush_earliest_round` hardcodes; epoch 4
    /// (Gen-2b's stamping-gap window) and the rule-less carrier stay 0 (the
    /// caller's own ladder answers).
    #[test]
    fn a_rapid_ambusher_arrives_from_the_registrys_round_at_epoch_5() {
        assert_eq!(
            ambush_family_of("Rapid Ambush", "dark_brothers", 5).arrive_from_round,
            1,
            "the registry's own arrive_from_round"
        );
        assert_eq!(
            ambush_family_of("Rapid Ambush", "dark_brothers", 4).arrive_from_round,
            0,
            "the wave is epoch-gated: rules_epoch 4 is Gen-2b's stamping-gap window, RED before the fix"
        );
        assert_eq!(
            ambush_family_of("", "dark_brothers", 5).arrive_from_round,
            0,
            "no rule, no first-round arrival"
        );
    }

    /// "Ambush Re-Deployment" (gf/elven_jesters): `re_reserve` +
    /// `uses_per_game` stamped at epoch 5; epoch 4 (Gen-2b's stamping-gap
    /// window) and the rule-less carrier stay false/0. The withdraw beat
    /// itself is a future port.
    #[test]
    fn an_ambush_re_deployment_stamps_its_once_per_game_params_at_epoch_5() {
        assert_eq!(
            ambush_family_of("Ambush Re-Deployment", "elven_jesters", 5),
            AmbushFamily { re_reserve: true, re_reserve_uses: 1, ..Default::default() },
            "the registry's own re_reserve/uses_per_game"
        );
        assert_eq!(
            ambush_family_of("Ambush Re-Deployment", "elven_jesters", 4),
            AmbushFamily::default(),
            "the wave is epoch-gated: rules_epoch 4 is Gen-2b's stamping-gap window, RED before the fix"
        );
        assert_eq!(
            ambush_family_of("", "elven_jesters", 5),
            AmbushFamily::default(),
            "no rule, no re-reserve"
        );
    }

    /// WIRING: the expansion reaches the static layer — a unit printed with
    /// ONLY "Fearless Aura" is fearless through `build_for` at epoch 6 (the
    /// core's own additive leg), NOT at epoch 5 (the gate is off there, the
    /// import expansion is the only leg — RED before the fix). `HasSpecial
    /// Rule` reads the expanded `special_rules`, the same exact-name read
    /// `AiEv` does.
    #[test]
    fn a_fearless_aura_carrier_builds_fearless_only_at_epoch_6() {
        let build = |epoch: u32| {
            let p = aura_expanded(&format!("[\"{}\"]", "Fearless Aura"), "[]", epoch);
            let mut reg = Registries::new(&repo_root());
            UnitStatic::build_for(&mut reg, &p, epoch).fearless
        };
        assert!(build(6), "epoch 6: build_for consumes the core-read grant");
        assert!(!build(5), "epoch 5: the gate is OFF — RED before the fix");
    }

    /// HERO LEG: a hero carried by the host prints the aura on the HERO's
    /// own list — the loader's member loop grants the base to EVERY member
    /// (the host AND the hero), because `AiEv.rule_on_all_models`
    /// (ai_ev.gd:79-83) reads the hero's list. Epoch 6 core-read; epoch 5
    /// untouched (the import leg already ran there — unchanged).
    #[test]
    fn a_hero_aura_stamps_the_base_on_host_and_hero_at_epoch_6() {
        let read = |epoch: u32| {
            let p = aura_expanded("[\"Melee Evasion\"]", "[[\"Melee Evasion Aura\"]]", epoch);
            (
                p.special_rules.iter().any(|r| r == "Melee Evasion"),
                p.attached_hero_rules
                    .iter()
                    .flatten()
                    .any(|r| r == "Melee Evasion"),
            )
        };
        assert_eq!(read(6), (true, true), "epoch 6: host and hero both carry the base");
        assert_eq!(read(5), (true, false), "epoch 5: the gate is OFF — RED before the fix");
    }

    /// "Indirect when Shooting" (gf common block): the unit-level name stamps
    /// the full Indirect facet onto every RANGED profile at the wave-3 gate —
    /// the profile's own `indirect` flag that the save gate (dice.rs), the EV
    /// imagination (combat.rs `profile_ev`) and the sight waiver (sim.rs
    /// `sighted_count`) all read. Epoch literals 6/5, NOT
    /// `CURRENT_RULES_EPOCH`: a wave-4 bump must not re-date what these
    /// assertions mean. RED (drop `build_for`'s named walk): the epoch-6
    /// assertion trips on the unstamped flag.
    #[test]
    fn indirect_when_shooting_stamps_its_ranged_facet_at_epoch_6() {
        assert!(
            indirect_family_of("Indirect when Shooting", 6).shoot[0].indirect,
            "the unit-level name reaches the ranged profile at the wave-3 gate"
        );
        assert!(
            !indirect_family_of("Indirect when Shooting", 5).shoot[0].indirect,
            "the wave is epoch-gated: rules_epoch 5 is the recorder fleet's stamping epoch, RED before the fix"
        );
        assert!(
            !indirect_family_of("", 6).shoot[0].indirect,
            "no rule, no stamp"
        );
    }

    /// "Ignores Cover when Shooting" (gf common block): the EFFECT is block
    /// 5's ungated cover-ignore arm (ai_ev.gd:273-281's loop, live at every
    /// epoch — the epoch-5 leg is the regression guard), so THIS wave's port
    /// is the name-literal walk (the census's own-token evidence) plus the
    /// rules-must-log line: the volley names the RULE — not the weapon tag —
    /// the one time its cover skip lands on an in-cover target. RED (drop the
    /// named walk or the dice log leg): the epoch-6 log assertion trips on an
    /// empty log.
    #[test]
    fn ignores_cover_when_shooting_reaches_the_ranged_stamp_and_logs_its_cover_skip() {
        let volley_log = |us: &UnitStatic| {
            let def =
                Ctx { defense: 4, models: 5, tough: 1, in_cover: true, ..Default::default() };
            let mut tray = crate::dice::Tray::seeded(27);
            let one = [crate::dice::Shooter {
                profiles: &us.shoot,
                keep: &[0],
                attacks: &[us.shoot[0].attacks],
                att: &us.ctx,
                owner: &us.name,
            }];
            crate::dice::resolve_volley_with_tray(
                &one, &def, "Target", 12.0, 12.0, true, true, true, true, &mut tray,
            )
            .log
        };
        assert!(
            volley_log(&indirect_family_of("Ignores Cover when Shooting", 6))
                .iter()
                .any(|l| l.starts_with("Ignores Cover when Shooting: Carrier")),
            "the rule logs its cover skip — rules must log"
        );
        assert!(
            !volley_log(&indirect_family_of("Ignores Cover when Shooting", 5))
                .iter()
                .any(|l| l.starts_with("Ignores Cover when Shooting:")),
            "the LOG is wave-3 behaviour: block 5's pre-existing effect stays silent at epoch 5"
        );
        assert!(
            !volley_log(&indirect_family_of("", 6))
                .iter()
                .any(|l| l.starts_with("Ignores Cover when Shooting:")),
            "no rule, no log line"
        );
        assert!(
            indirect_family_of("Ignores Cover when Shooting", 6).shoot[0].ignores_cover,
            "the named walk stamps the plain flag the save gate reads"
        );
        assert!(
            indirect_family_of("Ignores Cover when Shooting", 5).shoot[0].ignores_cover,
            "block 5's ungated cover arm predates this wave — the regression guard"
        );
        assert!(
            !indirect_family_of("", 6).shoot[0].ignores_cover,
            "no rule, no stamp"
        );
    }

    /// "Bane in Melee" (main.gd:6543-6545): melee-only at the current epoch;
    /// the flat prefix reading (both profiles) at epoch 0 — and a rule-less
    /// unit never stamps bane.
    #[test]
    fn bane_in_melee_reaches_melee_only_at_the_current_epoch() {
        assert_eq!(
            bane_stamp_of("Bane in Melee", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH),
            (false, true),
            "melee-only: the rifle stays clean"
        );
        assert_eq!(bane_stamp_of("Bane in Melee", "gf", "robot_legions", 0), (true, true), "flat Gen-0 reading");
        assert_eq!(bane_stamp_of("", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH), (false, false));
    }

    /// "Bane in Melee Buff" (main.gd:6543's prefix arm — the Buff shares the
    /// "Bane in Melee" branch): melee-only at the current epoch, flat at 0.
    #[test]
    fn bane_in_melee_buff_reaches_melee_only_at_the_current_epoch() {
        assert_eq!(
            bane_stamp_of("Bane in Melee Buff", "gf", "human_defense_force", crate::acts::CURRENT_RULES_EPOCH),
            (false, true),
            "the Buff's melee scope"
        );
        assert_eq!(bane_stamp_of("Bane in Melee Buff", "gf", "human_defense_force", 0), (true, true), "flat Gen-0 reading");
    }

    /// "Bane when Shooting" (main.gd:6546-6548): shooting-only at the current
    /// epoch; the flat prefix reading at epoch 0.
    #[test]
    fn bane_when_shooting_reaches_shooting_only_at_the_current_epoch() {
        assert_eq!(
            bane_stamp_of("Bane when Shooting", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH),
            (true, false),
            "shooting-only: the blade stays clean"
        );
        assert_eq!(bane_stamp_of("Bane when Shooting", "gf", "robot_legions", 0), (true, true), "flat Gen-0 reading");
    }

    /// "Bane in Melee Aura" (main.gd:6540): a striker's own "… Aura" rule
    /// never fires — nothing stamps at the current epoch (the aura expansion
    /// hands the base rule to the unit), while epoch 0 keeps the flat read.
    #[test]
    fn bane_in_melee_aura_never_fires_for_its_own_striker() {
        assert_eq!(
            bane_stamp_of("Bane in Melee Aura", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH),
            (false, false),
            "the aura name itself is skipped"
        );
        assert_eq!(bane_stamp_of("Bane in Melee Aura", "gf", "robot_legions", 0), (true, true), "flat Gen-0 reading");
    }

    /// "Bane when Shooting Aura" (main.gd:6540): the same aura skip.
    #[test]
    fn bane_when_shooting_aura_never_fires_for_its_own_striker() {
        assert_eq!(
            bane_stamp_of("Bane when Shooting Aura", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH),
            (false, false),
            "the aura name itself is skipped"
        );
        assert_eq!(bane_stamp_of("Bane when Shooting Aura", "gf", "robot_legions", 0), (true, true), "flat Gen-0 reading");
    }

    /// "Bane Mark" (main.gd:6550's plain arm — the table's dice path reads the
    /// Mark as plain always-on Bane; the once-per-activation pick is the
    /// table's own live state): both profiles at the current epoch, and the
    /// same at epoch 0 (the legacy prefix already caught it).
    #[test]
    fn bane_mark_reads_as_plain_bane() {
        assert_eq!(
            bane_stamp_of("Bane Mark", "gf", "robot_legions", crate::acts::CURRENT_RULES_EPOCH),
            (true, true),
            "plain-bane arm, both profiles"
        );
        assert_eq!(bane_stamp_of("Bane Mark", "gf", "robot_legions", 0), (true, true), "the legacy prefix read too");
    }

    /// "Bestial" (aof/beastmen) — the coverage wave (main.gd:6553-6560):
    /// a Bane-primitive alias with `reroll_save_sixes` re-rolls the defender's
    /// sixes at the current epoch; the legacy prefix scan never caught it, so
    /// epoch 0 stays clean.
    #[test]
    fn bestial_joins_through_the_coverage_wave() {
        assert_eq!(
            bane_stamp_of("Bestial", "aof", "beastmen", crate::acts::CURRENT_RULES_EPOCH),
            (true, true),
            "reroll_save_sixes: both profiles, no scope"
        );
        assert_eq!(bane_stamp_of("Bestial", "aof", "beastmen", 0), (false, false), "the wave is epoch-gated");
    }

    /// "Mischievous" (aof/goblins) — the same coverage wave.
    #[test]
    fn mischievous_joins_through_the_coverage_wave() {
        assert_eq!(
            bane_stamp_of("Mischievous", "aof", "goblins", crate::acts::CURRENT_RULES_EPOCH),
            (true, true),
            "reroll_save_sixes: both profiles, no scope"
        );
        assert_eq!(bane_stamp_of("Mischievous", "aof", "goblins", 0), (false, false), "the wave is epoch-gated");
    }

    /// "Scrapper" (gf/jackals) — the same coverage wave.
    #[test]
    fn scrapper_joins_through_the_coverage_wave() {
        assert_eq!(
            bane_stamp_of("Scrapper", "gf", "jackals", crate::acts::CURRENT_RULES_EPOCH),
            (true, true),
            "reroll_save_sixes: both profiles, no scope"
        );
        assert_eq!(bane_stamp_of("Scrapper", "gf", "jackals", 0), (false, false), "the wave is epoch-gated");
    }

    /// "Scrapper Boost" (gf/jackals) — the gf entry carries `reroll_save_sixes`
    /// alongside its un-read 5-6 extension, so the wave joins it too (the
    /// reroll_save_low/over_in params stay read by nobody — the Boost's own
    /// documented gap).
    #[test]
    fn scrapper_boost_joins_through_the_coverage_wave() {
        assert_eq!(
            bane_stamp_of("Scrapper Boost", "gf", "jackals", crate::acts::CURRENT_RULES_EPOCH),
            (true, true),
            "the gf entry's reroll_save_sixes"
        );
        assert_eq!(bane_stamp_of("Scrapper Boost", "gf", "jackals", 0), (false, false), "the wave is epoch-gated");
    }

    /// Lacerate family (rules-wave2-lacerate2) — one test per ported name,
    /// through the same template as the Bane ladder. Epoch literals 5/4/3,
    /// NOT `CURRENT_RULES_EPOCH`: a wave-3 epoch bump must not re-date what
    /// these assertions mean.
    ///
    /// EPOCH GATES BY RECORDING SHA (05.09. correction): Lacerate's OWN merge
    /// commit (`cf8831d1`) landed BEFORE the Gen-2b recording fleet launched,
    /// so it was live in the recorder for every `rules_epoch: 4` record —
    /// `acts::EPOCH_4_TABLE_RULES`, not `EPOCH_5_TABLE_RULES` (that value is
    /// for the four families that merged AFTER the fleet launched). Epoch 4
    /// now GETS Lacerate; only epoch 3 and below replay the pre-wave reading.
    ///
    /// "Ignores Regeneration" (main.gd:6983-6989, common entries): bypass on
    /// BOTH profiles from epoch 4 onward; epoch 3 replays the pre-wave
    /// reading.
    #[test]
    fn ignores_regeneration_bypasses_regen_on_every_profile_from_epoch_4() {
        assert_eq!(
            bane_stamp_of("Ignores Regeneration", "gf", "robot_legions", 5),
            (true, true),
            "ungated bypass: both profiles"
        );
        assert_eq!(
            bane_stamp_of("Ignores Regeneration", "gf", "robot_legions", 4),
            (true, true),
            "rules_epoch 4 is Gen-2b's OWN recording epoch: Lacerate WAS live in the recorder, RED before the fix"
        );
        assert_eq!(
            bane_stamp_of("Ignores Regeneration", "gf", "robot_legions", 3),
            (false, false),
            "the wave is epoch-gated: epoch 3 predates Lacerate entirely"
        );
        assert_eq!(bane_stamp_of("", "gf", "robot_legions", 5), (false, false), "no rule, no bypass");
    }

    /// "Unstoppable in Melee" (main.gd:6986-6989): the melee_only facet keeps
    /// the rifle clean and the blade bypassing from epoch 4 onward.
    #[test]
    fn unstoppable_in_melee_bypasses_regen_in_melee_only_from_epoch_4() {
        assert_eq!(
            bane_stamp_of("Unstoppable in Melee", "gf", "robot_legions", 5),
            (false, true),
            "melee-only facet"
        );
        assert_eq!(
            bane_stamp_of("Unstoppable in Melee", "gf", "robot_legions", 4),
            (false, true),
            "rules_epoch 4 is Gen-2b's OWN recording epoch: Lacerate WAS live in the recorder, RED before the fix"
        );
        assert_eq!(
            bane_stamp_of("Unstoppable in Melee", "gf", "robot_legions", 3),
            (false, false),
            "the wave is epoch-gated: epoch 3 predates Lacerate entirely"
        );
        assert_eq!(bane_stamp_of("", "gf", "robot_legions", 5), (false, false), "no rule, no bypass");
    }

    /// "Ignores Regeneration in Melee" (gf/gff common): the same melee-only
    /// facet, distinct name, same primitive.
    #[test]
    fn ignores_regeneration_in_melee_bypasses_regen_in_melee_only_from_epoch_4() {
        assert_eq!(
            bane_stamp_of("Ignores Regeneration in Melee", "gf", "robot_legions", 5),
            (false, true),
            "melee-only facet"
        );
        assert_eq!(
            bane_stamp_of("Ignores Regeneration in Melee", "gf", "robot_legions", 4),
            (false, true),
            "rules_epoch 4 is Gen-2b's OWN recording epoch: Lacerate WAS live in the recorder, RED before the fix"
        );
        assert_eq!(
            bane_stamp_of("Ignores Regeneration in Melee", "gf", "robot_legions", 3),
            (false, false),
            "the wave is epoch-gated: epoch 3 predates Lacerate entirely"
        );
        assert_eq!(bane_stamp_of("", "gf", "robot_legions", 5), (false, false), "no rule, no bypass");
    }

    #[test]
    fn primal_and_its_boost_reach_both_profiles_predator_fighter_only_melee() {
        let header = read_act_header(SURGE_ATTACK_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());

        let primal = header.profiles.get("primal_beast").expect("primal_beast");
        let ps = UnitStatic::build(&mut reg, primal);
        assert!(ps.shoot[0].surge_attack, "Primal is ungated — it reaches the ranged profile too");
        assert_eq!(ps.shoot[0].surge_attack_low, 5, "Primal Boost's surge_low");
        assert!(ps.melee[0].surge_attack);
        assert_eq!(ps.melee[0].surge_attack_low, 5);
        assert!(
            ps.unimplemented.iter().all(|u| u.rule != "Primal" && u.rule != "Primal Boost"),
            "consumed, not stamped as unimplemented: {:?}", ps.unimplemented
        );

        let predator = header.profiles.get("predator_fighter_unit").expect("predator_fighter_unit");
        let pf = UnitStatic::build(&mut reg, predator);
        assert!(!pf.shoot[0].surge_attack, "melee_only — the ranged profile stays untouched");
        assert_eq!(pf.shoot[0].surge_attack_low, 6, "unboosted default");
        assert!(pf.melee[0].surge_attack, "but the melee profile gets it");
        assert_eq!(pf.melee[0].surge_attack_low, 6, "Predator Fighter carries no Boost upgrade");
    }

    #[test]
    fn deathstrike_and_self_destruct_stamp_their_ratings_registry_gated() {
        let header = read_act_header(DEATH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let built = |k: &str, reg: &mut Registries| {
            UnitStatic::build(reg, header.profiles.get(k).expect(k)).ctx.death_hits_per_kill
        };
        assert_eq!(built("ds_goblin", &mut reg), 2, "Deathstrike(2)");
        assert_eq!(built("sd_hive", &mut reg), 3, "Self-Destruct(3)");
        assert_eq!(built("ds_bare", &mut reg), 1, "a bare name rates maxi(0, 1)");
        assert_eq!(built("ds_nomap", &mut reg), 0, "no map for the faction — silent");
    }

    #[test]
    fn instinctive_stamps_the_registry_hit_bonus_gated() {
        let header = read_act_header(INSTINCTIVE_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let built = |k: &str, reg: &mut Registries| {
            UnitStatic::build(reg, header.profiles.get(k).expect(k)).ctx.instinctive_hit_bonus
        };
        assert_eq!(built("inst_gf", &mut reg), 1, "gf goblin_reclaimers hit_bonus");
        assert_eq!(built("inst_aof", &mut reg), 1, "aof vampiric_undead hit_bonus");
        assert_eq!(built("inst_nomap", &mut reg), 0, "no map for the faction — silent");
    }

    #[test]
    fn whole_unit_resistance_carries_the_6_plus_2_plus_legs() {
        let header = read_act_header(RESISTANCE_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());

        let p = header.profiles.get("resist_whole").expect("resist_whole");
        let us = UnitStatic::build(&mut reg, p);
        assert!(us.ctx.regeneration, "a whole-unit Resistance carrier regenerates");
        assert_eq!(us.ctx.regen_target, 6, "the registry's ignore_target");
        assert_eq!(us.ctx.regen_target_spell, 2, "the registry's ignore_target_spell");
    }

    #[test]
    fn resistance_needs_every_model_so_a_bare_hero_kills_the_leg() {
        let header = read_act_header(RESISTANCE_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());

        let p = header.profiles.get("resist_partial").expect("resist_partial");
        let us = UnitStatic::build(&mut reg, p);
        assert!(
            !us.ctx.regeneration,
            "an attached hero without Resistance breaks the all-models gate"
        );
        assert_eq!(us.ctx.regen_target, 0, "no regeneration family member fields");
        assert_eq!(us.ctx.regen_target_spell, 0);
    }

    #[test]
    fn angelic_blessing_ignores_on_6_and_spells_on_4_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "angelic", CURRENT_RULES_EPOCH),
            (6, 4),
            "the registry's ignore_target 6 / ignore_target_spell 4"
        );
        assert_eq!(regen_pair_at(&header, "angelic", 0), (0, 0), "epoch 0 replays legacy");
        assert_eq!(
            regen_pair_at(&header, "bare_aof", CURRENT_RULES_EPOCH),
            (0, 0),
            "without the rule: none"
        );
    }

    #[test]
    fn angelic_blessing_boost_is_spell_only_on_2_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "angelic_boost", CURRENT_RULES_EPOCH),
            (0, 2),
            "spell_only entry: no normal leg, spells ignored on 2+"
        );
        assert_eq!(regen_pair_at(&header, "angelic_boost", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn cursed_undead_ignores_on_6_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "cursed", CURRENT_RULES_EPOCH),
            (6, 6),
            "no spell twin: the spell pick falls back to ignore_target (main.gd:6648)"
        );
        assert_eq!(regen_pair_at(&header, "cursed", 0), (0, 0), "epoch 0 replays legacy");
        assert_eq!(regen_pair_at(&header, "bare_aof", CURRENT_RULES_EPOCH), (0, 0));
    }

    #[test]
    fn cursed_undead_boost_ignores_on_5_6_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "cursed_boost", CURRENT_RULES_EPOCH),
            (5, 5),
            "ignore_target 5 = rolls of 5-6"
        );
        assert_eq!(regen_pair_at(&header, "cursed_boost", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn plaguebound_ignores_on_6_and_needs_every_model() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(regen_pair_at(&header, "plague", CURRENT_RULES_EPOCH), (6, 6));
        assert_eq!(regen_pair_at(&header, "plague", 0), (0, 0), "epoch 0 replays legacy");
        assert_eq!(
            regen_pair_at(&header, "plague_partial", CURRENT_RULES_EPOCH),
            (0, 0),
            "all_models: an attached hero without the rule kills the leg"
        );
    }

    #[test]
    fn plaguebound_boost_ignores_on_5_6_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(regen_pair_at(&header, "plague_boost", CURRENT_RULES_EPOCH), (5, 5));
        assert_eq!(regen_pair_at(&header, "plague_boost", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn protected_ignores_on_6_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(regen_pair_at(&header, "protected", CURRENT_RULES_EPOCH), (6, 6));
        assert_eq!(regen_pair_at(&header, "protected", 0), (0, 0), "epoch 0 replays legacy");
        assert_eq!(regen_pair_at(&header, "bare_aof", CURRENT_RULES_EPOCH), (0, 0));
    }

    #[test]
    fn protection_feat_ignores_on_5_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "protection_feat", CURRENT_RULES_EPOCH),
            (5, 5),
            "uses_per_game is the table's own unread param, mirrored"
        );
        assert_eq!(regen_pair_at(&header, "protection_feat", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn grounded_protection_ignores_on_5_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "grounded", CURRENT_RULES_EPOCH),
            (5, 5),
            "terrain_within_in is the table's own unread param, mirrored"
        );
        assert_eq!(regen_pair_at(&header, "grounded", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn knightborn_ignores_on_6_and_spells_on_4_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(regen_pair_at(&header, "knightborn", CURRENT_RULES_EPOCH), (6, 4));
        assert_eq!(regen_pair_at(&header, "knightborn", 0), (0, 0), "epoch 0 replays legacy");
        assert_eq!(regen_pair_at(&header, "bare_gf", CURRENT_RULES_EPOCH), (0, 0));
    }

    #[test]
    fn self_repair_boost_ignores_on_5_6_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(regen_pair_at(&header, "self_repair_boost", CURRENT_RULES_EPOCH), (5, 5));
        assert_eq!(regen_pair_at(&header, "self_repair_boost", 0), (0, 0), "epoch 0 replays legacy");
    }

    #[test]
    fn regeneration_buff_reads_5_epoch_gated() {
        let header = read_act_header(REGEN_FAMILY_HEADER).expect("header");
        assert_eq!(
            regen_pair_at(&header, "regen_buff", CURRENT_RULES_EPOCH),
            (5, 5),
            "table-faithful: the alias layer pays the carrier, the buff flow is unmodelled"
        );
        assert_eq!(regen_pair_at(&header, "regen_buff", 0), (0, 0), "epoch 0 replays legacy");
    }

    /// RED — the REGISTRY value wins, and it is measurably not the fallback.
    /// `min_enemy_dist_in: 3.0` is an exact 3.0; the table's own fallback
    /// expression (`INFILTRATE_MIN_ENEMY_DIST_M / INCHES_TO_METERS`,
    /// solo_controller.gd:9620) is `3.0000000000000004`. Stamp the constant
    /// instead of reading the entry and this assertion fails on that ULP.
    #[test]
    fn an_infiltrators_ring_is_the_registrys_value_not_the_constant() {
        let us = ambush_static("inf_registry");
        assert_eq!(us.infiltrate_min_enemy_dist_in, 3.0, "the registry's exact 3.0");
        assert_ne!(
            us.infiltrate_min_enemy_dist_in, INFILTRATE_MIN_ENEMY_DIST_IN,
            "and it is NOT the fallback — they are one ULP apart by design"
        );
    }

    /// The other half: a faction the map fields no `Infiltrate` entry for still
    /// gets a ring, because the table gates this one on the PLAIN rule name
    /// (`has_special_rule`, :9618), not on `unit_rule_active`. Swap the gate to
    /// `unit_rule_active` and this drops to 0.0.
    #[test]
    fn an_unmapped_infiltrator_falls_back_to_the_tables_own_expression() {
        let us = ambush_static("inf_unmapped");
        assert_eq!(us.infiltrate_min_enemy_dist_in, INFILTRATE_MIN_ENEMY_DIST_IN);
        assert_eq!(us.infiltrate_min_enemy_dist_in, 0.0762 / 0.0254);
        assert_ne!(us.infiltrate_min_enemy_dist_in, 3.0, "a bare 3.0 is a different float");
    }

    /// A plain Ambush unit is NOT an infiltrator: 0.0 hands the caller the 9"
    /// `AMBUSH_MIN_ENEMY_DIST_M` path (:9606). "Ambush Beacon" rides along to
    /// pin the prefix lesson (solo_controller.gd:9731-9734) — `has_special_rule`
    /// is exact-or-parametrised, so it must not answer the "Infiltrate" query
    /// and must not answer "Ambush" for the Beacon either.
    #[test]
    fn a_plain_ambusher_is_not_an_infiltrator() {
        let us = ambush_static("plain_ambusher");
        assert_eq!(us.infiltrate_min_enemy_dist_in, 0.0);
        assert_eq!(us.repel_ambushers_dist_in, 0.0);
    }

    /// Repel Ambushers projects the registry's 12"; the gate here IS
    /// `unit_rule_active`, so a faction whose map fields no entry projects
    /// NOTHING even though the unit prints the rule. Copy the Infiltrate gate
    /// onto this field and the second assertion becomes 12.0.
    #[test]
    fn repel_ambushers_is_registry_gated_unlike_infiltrate() {
        assert_eq!(ambush_static("repel_carrier").repel_ambushers_dist_in, 12.0);
        assert_eq!(ambush_static("repel_carrier").repel_ambushers_dist_in, REPEL_AMBUSHERS_DIST_IN);
        assert_eq!(
            ambush_static("repel_unmapped").repel_ambushers_dist_in, 0.0,
            "alien_hives fields no Repel Ambushers entry -> unit_rule_active is false"
        );
    }

    /// `growth_of` REPORTS the registry's Growth Markers entry — a body
    /// emptied into `vec![]` would report nothing at all.
    #[test]
    fn growth_of_reports_a_registry_growth_rule() {
        let header = read_act_header(GROWTH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let mut un = Vec::new();
        let p = header.profiles.get("growth_carrier").expect("carrier");
        let out = growth_of(&mut reg, p, &mut un);
        assert_eq!(out.len(), 1, "one Growth Markers entry: {out:?}");
        assert_eq!(out[0].name, "Piercing Growth");
    }

    /// ...with the registry's own PARAMS, not a default-constructed stub —
    /// `vec![Default::default()]` carries an empty name, max_markers 0 and
    /// no rates at all.
    #[test]
    fn growth_of_carries_the_registry_params() {
        let header = read_act_header(GROWTH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let mut un = Vec::new();
        let p = header.profiles.get("growth_carrier").expect("carrier");
        let out = growth_of(&mut reg, p, &mut un);
        assert_eq!(out[0].max_markers, 4, "the registry's max_markers");
        assert!(out[0].per_round, "Piercing Growth ticks per round");
        assert_eq!(out[0].ap_per_two, 1);
        assert_eq!(out[0].ap_per_marker, 0);
        assert_eq!(out[0].hit_per_marker, 0);
        assert_eq!(out[0].hit_per_two, 0);
    }

    /// The de-dup: the same rule twice in special_rules reports ONE entry —
    /// the `||` at the skip gate (empty-name OR already-seen) must not
    /// collapse into an `&&` that loses the seen-list half.
    #[test]
    fn a_duplicated_growth_rule_is_reported_once() {
        let header = read_act_header(GROWTH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let mut un = Vec::new();
        let p = header.profiles.get("growth_dup").expect("dup");
        let out = growth_of(&mut reg, p, &mut un);
        assert_eq!(out.len(), 1, "the seen-list keeps one copy: {out:?}");
    }

    /// Same de-dup, by NAME: the seen comparison `*s == n` must not become
    /// `!=`, which would re-admit the very rule just recorded.
    #[test]
    fn a_repeated_growth_name_is_deduped_by_name() {
        let header = read_act_header(GROWTH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let mut un = Vec::new();
        let p = header.profiles.get("growth_dup").expect("dup");
        let out = growth_of(&mut reg, p, &mut un);
        assert_eq!(out.len(), 1, "one entry per distinct name: {out:?}");
    }

    /// The facet gate: a rule WITH any consumed facet is consumed silently; a
    /// rule whose facets are ALL unconsumed is REPORTED as unimplemented.
    /// The rules-wave3-growthmark epoch-6 wave consumes the defense facets,
    /// so the old "defense-only is reported" case (Defensive Growth) is now
    /// consumed — the report shape is still exercised by the shared gate
    /// above (the `==` on the nine-facet tuple); flipping it to `!=` reports
    /// the facet-bearing rules instead and goes silent on a facetless one.
    #[test]
    fn a_growth_rule_with_no_attack_facet_is_reported_unimplemented() {
        let header = read_act_header(GROWTH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let mut un = Vec::new();
        let p = header.profiles.get("growth_carrier").expect("carrier");
        let out = growth_of(&mut reg, p, &mut un);
        assert_eq!(out.len(), 1);
        assert!(un.is_empty(), "Piercing Growth has an ap facet: {un:?}");
        let pz = header.profiles.get("growth_zero").expect("zero");
        let outz = growth_of(&mut reg, pz, &mut un);
        assert_eq!(outz.len(), 1);
        assert!(
            outz[0].defense_per_two == 1 && un.iter().all(|u| u.rule != "Defensive Growth"),
            "the epoch-6 wave consumes Defensive Growth's defense facet: {un:?}"
        );
    }

    /// rules-wave3-growthmark — `growth_of` reads the epoch-6 wave's own
    /// params off the REAL registry: Regenerative Strength's
    /// `on_ignore_wound` + `attacks_per_marker` (alien_hives, gf).
    #[test]
    fn growth_of_carries_the_regenerative_strength_params() {
        let header = read_act_header(GROWTH_RS_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let mut un = Vec::new();
        let p = header.profiles.get("rs_carrier").expect("carrier");
        let out = growth_of(&mut reg, p, &mut un);
        assert_eq!(out.len(), 1, "one Growth Markers entry: {out:?}");
        assert_eq!(out[0].name, "Regenerative Strength");
        assert!(out[0].on_ignore_wound);
        assert_eq!(out[0].attacks_per_marker, 1);
    }

    #[test]
    fn the_base_rule_stamps_the_registry_charge_bonus_and_a_non_carrier_stamps_none() {
        let header = read_act_header(VR_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("vr_carrier").expect("vr_carrier");
        let us = UnitStatic::build(&mut reg, carrier);
        assert_eq!(
            us.versatile_reach_charge_in, Some(2.0),
            "the registry's charge_bonus_in, read off the rule-NAME literal"
        );
        let plain = header.profiles.get("vr_plain").expect("vr_plain");
        let us = UnitStatic::build(&mut reg, plain);
        assert_eq!(
            us.versatile_reach_charge_in, None,
            "no VR name, no stamp — the +4\" range half is not a field at all"
        );
    }

    /// The AURA arm: "Versatile Reach Aura" is UNMAPPED-registered
    /// (`primitive: null`, so `unit_rule_active` is false for it by
    /// construction) — the raw-name arm is what credits the aura carrier
    /// without depending on the import's `_expand_auras` having run. RED the
    /// moment that arm is dropped: the stamp falls to `None`.
    #[test]
    fn an_aura_only_carrier_stamps_too() {
        let header = read_act_header(VR_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let aura = header.profiles.get("vr_aura").expect("vr_aura");
        let us = UnitStatic::build(&mut reg, aura);
        assert_eq!(
            us.versatile_reach_charge_in, Some(2.0),
            "the raw-name arm makes the core independent of the expander"
        );
    }

    /// Screened = the Stealth DATA ALIAS (`stealth_alias_of`): -1 to hit past
    /// 9", same shape as the pre-existing `wormhole_daemons_of_plague` entry.
    /// RED (drop the new `change_disciples` registry entry): the alias
    /// fields fall back to the carrier's plain-Fearless sibling's zero.
    #[test]
    fn screened_carries_the_stealth_alias_a_plain_sibling_does_not() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("screened_unit").expect("screened_unit");
        let us = UnitStatic::build(&mut reg, carrier);
        assert_eq!(us.ctx.stealth_alias_penalty, 1, "Screened's own hit_penalty");
        assert_eq!(us.ctx.stealth_alias_over_in, 9.0, "Screened's own over_in");
        let plain = header.profiles.get("plain_change_disciple").expect("plain_change_disciple");
        let us = UnitStatic::build(&mut reg, plain);
        assert_eq!(us.ctx.stealth_alias_penalty, 0, "no Screened, no alias");
    }

    /// Guardian (`incoming_ap_reduction: 1, over_in: 9`) — PRESENT at epoch 6:
    /// the stamp is live, a 12" volley saves one better, the arm reports
    /// itself; ABSENT at epoch 5 (acts::EPOCH_6_TABLE_RULES's own window).
    #[test]
    fn guardian_is_live_at_epoch_6_and_absent_at_epoch_5() {
        let us6 = fortified_unit("guardian_unit", 6);
        assert_eq!(us6.ctx.fortified_alias_ap, 1, "Guardian's incoming_ap_reduction");
        assert_eq!(us6.ctx.fortified_alias_over_in, 9.0, "Guardian's own over_in gate");
        assert_eq!(us6.fortified_alias_name, "Guardian");
        let (target6, fired6) = fortified_volley(&us6, 12.0);
        assert_eq!(target6, 4, "AP(1) volley past 9\": saves on 4+ instead of 5+");
        assert!(fired6, "rules-must-log: the volley must report the alias arm");
        let us5 = fortified_unit("guardian_unit", 5);
        assert_eq!(us5.ctx.fortified_alias_ap, 0, "epoch 5 gets none of wave 3");
        let (target5, fired5) = fortified_volley(&us5, 12.0);
        assert_eq!(target5, 5, "the plain AP(1) save, unchanged");
        assert!(!fired5);
    }

    /// Primeborn (gf/prime_brothers, same gated shape as Guardian) — live at
    /// epoch 6, absent at 5.
    #[test]
    fn primeborn_is_live_at_epoch_6_and_absent_at_epoch_5() {
        let us6 = fortified_unit("primeborn_unit", 6);
        assert_eq!(us6.ctx.fortified_alias_ap, 1, "Primeborn's incoming_ap_reduction");
        assert_eq!(us6.ctx.fortified_alias_over_in, 9.0);
        assert_eq!(us6.fortified_alias_name, "Primeborn");
        let (target6, fired6) = fortified_volley(&us6, 12.0);
        assert_eq!(target6, 4, "saves on 4+ instead of 5+");
        assert!(fired6, "rules-must-log");
        let us5 = fortified_unit("primeborn_unit", 5);
        assert_eq!(us5.ctx.fortified_alias_ap, 0, "epoch 5 gets none of wave 3");
        let (target5, fired5) = fortified_volley(&us5, 12.0);
        assert_eq!(target5, 5, "the plain AP(1) save, unchanged");
        assert!(!fired5);
    }

    /// Warden (aof/eternal_wardens, Guardian's AoF twin) — live at 6, absent
    /// at 5.
    #[test]
    fn warden_is_live_at_epoch_6_and_absent_at_epoch_5() {
        let us6 = fortified_unit("warden_unit", 6);
        assert_eq!(us6.ctx.fortified_alias_ap, 1, "Warden's incoming_ap_reduction");
        assert_eq!(us6.ctx.fortified_alias_over_in, 9.0);
        assert_eq!(us6.fortified_alias_name, "Warden");
        let (target6, fired6) = fortified_volley(&us6, 12.0);
        assert_eq!(target6, 4, "saves on 4+ instead of 5+");
        assert!(fired6, "rules-must-log");
        let us5 = fortified_unit("warden_unit", 5);
        assert_eq!(us5.ctx.fortified_alias_ap, 0, "epoch 5 gets none of wave 3");
        let (target5, fired5) = fortified_volley(&us5, 12.0);
        assert_eq!(target5, 5, "the plain AP(1) save, unchanged");
        assert!(!fired5);
    }

    /// Ossified (aof/ossified_undead, Guardian's undead twin) — live at 6,
    /// absent at 5.
    #[test]
    fn ossified_is_live_at_epoch_6_and_absent_at_epoch_5() {
        let us6 = fortified_unit("ossified_unit", 6);
        assert_eq!(us6.ctx.fortified_alias_ap, 1, "Ossified's incoming_ap_reduction");
        assert_eq!(us6.ctx.fortified_alias_over_in, 9.0);
        assert_eq!(us6.fortified_alias_name, "Ossified");
        let (target6, fired6) = fortified_volley(&us6, 12.0);
        assert_eq!(target6, 4, "saves on 4+ instead of 5+");
        assert!(fired6, "rules-must-log");
        let us5 = fortified_unit("ossified_unit", 5);
        assert_eq!(us5.ctx.fortified_alias_ap, 0, "epoch 5 gets none of wave 3");
        let (target5, fired5) = fortified_volley(&us5, 12.0);
        assert_eq!(target5, 5, "the plain AP(1) save, unchanged");
        assert!(!fired5);
    }

    /// Guardian Boost (`incoming_ap_reduction: 1`, NO `over_in`) — PRESENT at
    /// epoch 6 on the MELEE leg too (main.gd:6119 passes over9=false there);
    /// ABSENT at epoch 5.
    #[test]
    fn guardian_boost_is_live_at_epoch_6_and_absent_at_epoch_5() {
        let us6 = fortified_unit("guardian_boost_unit", 6);
        assert_eq!(us6.ctx.fortified_boost_ap, 1, "the Boost's incoming_ap_reduction");
        assert_eq!(us6.ctx.fortified_alias_ap, 0, "no gated entry carried");
        assert_eq!(us6.fortified_boost_name, "Guardian Boost");
        let (target6, fired6) = fortified_melee(&us6);
        assert_eq!(target6, 4, "melee AP(1) vs the Boost: saves on 4+ instead of 5+");
        assert!(fired6, "rules-must-log: the melee phase must report the boost");
        let us5 = fortified_unit("guardian_boost_unit", 5);
        assert_eq!(us5.ctx.fortified_boost_ap, 0, "epoch 5 gets none of wave 3");
        let (target5, fired5) = fortified_melee(&us5);
        assert_eq!(target5, 5, "the plain AP(1) save, unchanged");
        assert!(!fired5);
    }

    /// Warden Boost (aof/eternal_wardens) — the same no-gate shape, live at 6,
    /// absent at 5.
    #[test]
    fn warden_boost_is_live_at_epoch_6_and_absent_at_epoch_5() {
        let us6 = fortified_unit("warden_boost_unit", 6);
        assert_eq!(us6.ctx.fortified_boost_ap, 1, "the Boost's incoming_ap_reduction");
        assert_eq!(us6.fortified_boost_name, "Warden Boost");
        let (target6, fired6) = fortified_melee(&us6);
        assert_eq!(target6, 4, "melee AP(1) vs the Boost: saves on 4+ instead of 5+");
        assert!(fired6, "rules-must-log: the melee phase must report the boost");
        let us5 = fortified_unit("warden_boost_unit", 5);
        assert_eq!(us5.ctx.fortified_boost_ap, 0, "epoch 5 gets none of wave 3");
        let (target5, fired5) = fortified_melee(&us5);
        assert_eq!(target5, 5, "the plain AP(1) save, unchanged");
        assert!(!fired5);
    }

    /// Ossified Boost (aof/ossified_undead) — the same no-gate shape, live at
    /// 6, absent at 5.
    #[test]
    fn ossified_boost_is_live_at_epoch_6_and_absent_at_epoch_5() {
        let us6 = fortified_unit("ossified_boost_unit", 6);
        assert_eq!(us6.ctx.fortified_boost_ap, 1, "the Boost's incoming_ap_reduction");
        assert_eq!(us6.fortified_boost_name, "Ossified Boost");
        let (target6, fired6) = fortified_melee(&us6);
        assert_eq!(target6, 4, "melee AP(1) vs the Boost: saves on 4+ instead of 5+");
        assert!(fired6, "rules-must-log: the melee phase must report the boost");
        let us5 = fortified_unit("ossified_boost_unit", 5);
        assert_eq!(us5.ctx.fortified_boost_ap, 0, "epoch 5 gets none of wave 3");
        let (target5, fired5) = fortified_melee(&us5);
        assert_eq!(target5, 5, "the plain AP(1) save, unchanged");
        assert!(!fired5);
    }

    /// The plain sibling carries nothing: no stamp, no firing — the control
    /// every per-name test leans on.
    #[test]
    fn a_unit_without_the_family_stamps_and_fires_nothing() {
        let plain = fortified_unit("plain_unit", 6);
        assert_eq!(plain.ctx.fortified_boost_ap, 0, "no rule, no Boost stamp");
        assert_eq!(plain.ctx.fortified_alias_ap, 0, "no rule, no alias stamp");
        assert_eq!(plain.fortified_alias_name, "");
        assert_eq!(plain.fortified_boost_name, "");
        let (target, fired) = fortified_volley(&plain, 12.0);
        assert_eq!(target, 5, "the plain AP(1) save");
        assert!(!fired);
    }

    /// Predator = the Surge `extra_attack` DATA ALIAS, same shape as the
    /// pre-existing `ratmen_clans` entry — reaches both profiles (ungated).
    /// RED (drop the new `saurian_starhost` registry entry): `surge_attack`
    /// stays false on both.
    #[test]
    fn predator_reaches_both_profiles_via_the_surge_extra_attack_alias() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("predator_unit").expect("predator_unit");
        let us = UnitStatic::build(&mut reg, carrier);
        assert!(us.shoot[0].surge_attack, "Predator's extra-attack-die facet, ranged");
        assert!(us.melee[0].surge_attack, "and melee — Predator carries no facet gate");
        let plain = header.profiles.get("plain_saurian_starhost").expect("plain_saurian_starhost");
        let us = UnitStatic::build(&mut reg, plain);
        assert!(!us.shoot[0].surge_attack, "no Predator, no extra-attack die");
    }

    /// RED (drop the `rule_on` gate or the "Counter-Attack" arm): the carrier
    /// reads `counter` at the wrong epoch or never; GREEN (any ungated stamp):
    /// the epoch-0 row flips and the recorded corpora stop replaying.
    #[test]
    fn counter_attack_strikes_first_only_from_the_current_epoch() {
        let header = read_act_header(COUNTER_ALIASES_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("counter_attack_unit").expect("counter_attack_unit");
        let us = UnitStatic::build_for(&mut reg, carrier, CURRENT_RULES_EPOCH);
        assert!(us.melee[0].counter, "the alias strikes first at the current epoch");
        let us = UnitStatic::build_for(&mut reg, carrier, 0);
        assert!(!us.melee[0].counter, "epoch 0 replays the Gen-0 rule set");
        let plain = header.profiles.get("plain_unit").expect("plain_unit");
        let us = UnitStatic::build_for(&mut reg, plain, CURRENT_RULES_EPOCH);
        assert!(!us.melee[0].counter, "no rule, no stamp");
    }

    /// Same three rows for "Counter in Melee" — the AoF-only sibling.
    #[test]
    fn counter_in_melee_strikes_first_only_from_the_current_epoch() {
        let header = read_act_header(COUNTER_ALIASES_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("counter_in_melee_unit").expect("counter_in_melee_unit");
        let us = UnitStatic::build_for(&mut reg, carrier, CURRENT_RULES_EPOCH);
        assert!(us.melee[0].counter, "the melee-scoped alias strikes first at the current epoch");
        let us = UnitStatic::build_for(&mut reg, carrier, 0);
        assert!(!us.melee[0].counter, "epoch 0 replays the Gen-0 rule set");
        let plain = header.profiles.get("plain_unit").expect("plain_unit");
        let us = UnitStatic::build_for(&mut reg, plain, CURRENT_RULES_EPOCH);
        assert!(!us.melee[0].counter, "no rule, no stamp");
    }

    /// Brutal = Devout's twin: the PLAIN auto-hit Surge alias (no
    /// `extra_attack`), so it lands on `surge`, never `surge_attack`. RED
    /// (drop the new `blessed_sisters` registry entry): `surge` stays false.
    #[test]
    fn brutal_fires_the_plain_surge_auto_hit_not_the_extra_attack_die() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("brutal_unit").expect("brutal_unit");
        let us = UnitStatic::build(&mut reg, carrier);
        assert!(us.melee[0].surge, "Brutal's plain auto-hit facet");
        assert!(!us.melee[0].surge_attack, "not the extra-attack-die form");
        let plain = header.profiles.get("plain_blessed_sisters").expect("plain_blessed_sisters");
        let us = UnitStatic::build(&mut reg, plain);
        assert!(!us.melee[0].surge, "no Brutal, no auto-hit");
    }

    /// "Brutal" (gf/blessed_sisters, aof/halflings|orcs): the plain auto-hit
    /// facet on BOTH profiles from 4, the same at 3 (the pre-wave walk),
    /// nothing without the rule.
    #[test]
    fn brutal_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Brutal", "gf", "blessed_sisters", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Brutal", "gf", "blessed_sisters", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "gf", "blessed_sisters", 4), (false, false), "no rule, no surge");
    }

    /// "Great Sergeant" (aof/ogres, aof/plague_disciples): the table's own
    /// stamp loop never reads the entry's printed `surge_low: 5` (it reads
    /// `surge_low` only off `upgrades` carriers), so the port replays the
    /// TABLE — the plain 6s form — not the printed 5-6 text.
    #[test]
    fn great_sergeant_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Great Sergeant", "aof", "ogres", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Great Sergeant", "aof", "ogres", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "aof", "ogres", 4), (false, false), "no rule, no surge");
    }

    /// "Devout" (gf/blessed_sisters): Devout-Boost's own base, the plain
    /// auto-hit facet on BOTH profiles, same three rows.
    #[test]
    fn devout_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Devout", "gf", "blessed_sisters", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Devout", "gf", "blessed_sisters", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "gf", "blessed_sisters", 4), (false, false), "no rule, no surge");
    }

    /// "Surge when Shooting" (gf/gff common; the book carrier is Dwarf
    /// Guilds): the entry carries NO `shooting_only`, so the table's alias
    /// loop stamps both arrays — the port replays the table, scoping gap and
    /// all (the printed "when shooting" is the table's own gap).
    #[test]
    fn surge_when_shooting_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Surge when Shooting", "gf", "dwarf_guilds", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Surge when Shooting", "gf", "dwarf_guilds", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "gf", "dwarf_guilds", 4), (false, false), "no rule, no surge");
    }

    /// "Lucky" (aof/halflings): Lucky-Boost's own base, the plain auto-hit
    /// facet on BOTH profiles, same three rows.
    #[test]
    fn lucky_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Lucky", "aof", "halflings", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Lucky", "aof", "halflings", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "aof", "halflings", 4), (false, false), "no rule, no surge");
    }

    /// "Surge Mark" (aof/chivalrous_kingdoms): the table's dice path reads the
    /// Mark as plain always-on Surge through the alias loop — the
    /// once-per-activation pick is a Utility-Buff `vs_target` overlay this
    /// entry does not carry (the Bane Mark precedent), so the port replays the
    /// table's plain reading.
    #[test]
    fn surge_mark_reads_as_plain_surge_from_epoch_4() {
        assert_eq!(surge_stamp_of("Surge Mark", "aof", "chivalrous_kingdoms", 4), (true, true), "the named arm's facet, both profiles");
        assert_eq!(surge_stamp_of("Surge Mark", "aof", "chivalrous_kingdoms", 3), (true, true), "epoch 3 replays the pre-wave generic walk");
        assert_eq!(surge_stamp_of("", "aof", "chivalrous_kingdoms", 4), (false, false), "no rule, no surge");
    }
    #[test]
    fn the_surge_gates_stamp_through_the_real_registry() {
        let header = read_act_header(SURGE_GATES_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let dev = UnitStatic::build(
            &mut reg, header.profiles.get("devout_boost_unit").expect("devout_boost_unit"),
        );
        assert_eq!(dev.shoot[0].surge_low, 5, "Devout Boost's surge_low");
        assert_eq!(dev.shoot[0].surge_over_in, 9.0, "Devout Boost's over_in");
        assert_eq!(dev.melee[0].surge_low, 5, "the boost rides EVERY profile Devout gave surge");
        assert!(
            dev.unimplemented.iter().all(|u| u.rule != "Devout Boost"),
            "consumed, not stamped as unimplemented: {:?}", dev.unimplemented
        );
        let plain = UnitStatic::build(
            &mut reg, header.profiles.get("plain_blessed").expect("plain_blessed"),
        );
        assert_eq!(plain.shoot[0].surge_low, 6, "no Boost, no 5s (main.gd's default)");
        assert_eq!(plain.shoot[0].surge_over_in, 0.0, "and no over-9\" gate");
        let pb = UnitStatic::build(
            &mut reg, header.profiles.get("point_blank_unit").expect("point_blank_unit"),
        );
        assert_eq!(pb.shoot[0].surge_within_in, 12.0, "Point-Blank's within gate, ranged");
        assert_eq!(pb.melee[0].surge_within_in, 12.0, "and melee — the entry carries no shooting_only");
    }

    /// Brutal Fighter = the `melee_only` Surge alias (gf human_inquisition):
    /// the facet gate keeps it off the ranged profile. Its effect predates the
    /// epoch mechanism (consumed ungated since block B6), so the RED leg here
    /// is the WITHOUT-rule one: the plain sibling stays silent on both.
    #[test]
    fn brutal_fighter_is_melee_only_through_the_real_registry() {
        let header = read_act_header(SURGE_GATES_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let bf = UnitStatic::build(
            &mut reg, header.profiles.get("brutal_fighter_unit").expect("brutal_fighter_unit"),
        );
        assert!(bf.melee[0].surge, "Brutal Fighter's melee-only surge facet");
        assert!(!bf.shoot[0].surge, "the ranged profile stays untouched (melee_only)");
        let plain = UnitStatic::build(
            &mut reg, header.profiles.get("plain_inquisition").expect("plain_inquisition"),
        );
        assert!(!plain.melee[0].surge && !plain.shoot[0].surge, "no Brutal Fighter, no facet");
    }

    /// Precision Hunter = Targeting Visor's word-for-word twin, now on the
    /// `stamp_shot_modifier` allow-list: +1 to hit past 9". RED (drop the
    /// list entry, or the new `dao_union` registry entry): `hit_bonus_over9`
    /// stays 0.
    #[test]
    fn precision_hunter_stamps_the_over_nine_hit_bonus() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("precision_hunter_unit").expect("precision_hunter_unit");
        let us = UnitStatic::build(&mut reg, carrier);
        assert_eq!(us.shoot[0].hit_bonus_over9, 1, "Precision Hunter's own hit_bonus");
        assert_eq!(us.shoot[0].hit_bonus, 0, "flat (non-over-9) leg stays untouched");
        let plain = header.profiles.get("plain_dao_union").expect("plain_dao_union");
        let us = UnitStatic::build(&mut reg, plain);
        assert_eq!(us.shoot[0].hit_bonus_over9, 0, "no Precision Hunter, no bonus");
    }

    /// Nimble = Bounding's word-for-word twin, own D3 (vs Bounding's D3+1) —
    /// `bounding_of`'s named-carrier loop. RED (drop the new
    /// `elven_jesters` registry entry): `bounding` falls back to `None`.
    #[test]
    fn nimble_stamps_its_own_d3_reach_not_boundings_d3_plus_one() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("nimble_unit").expect("nimble_unit");
        let us = UnitStatic::build(&mut reg, carrier);
        assert_eq!(us.bounding, Some(0.0), "Nimble's own place_d3_plus");
        let plain = header.profiles.get("plain_elven_jesters").expect("plain_elven_jesters");
        let us = UnitStatic::build(&mut reg, plain);
        assert_eq!(us.bounding, None, "no Nimble, no stamp");
    }

    /// Courageous = the Banner DATA ALIAS (`banner_bonus_of`'s generic scan
    /// over every carried rule's own registry entry) — the SAME mechanism
    /// Screened rides for Stealth, so no Rust change was needed here either.
    /// RED (drop the new `alien_hives` registry entry): `morale_bonus` stays 0.
    #[test]
    fn courageous_reaches_capture_reads_via_the_banner_alias() {
        let header = read_act_header(RUNG_C_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let carrier = header.profiles.get("courageous_unit").expect("courageous_unit");
        let reads = capture_reads(&mut reg, carrier);
        assert_eq!(reads.morale_bonus, 1, "Courageous's own morale_bonus");
        let plain = header.profiles.get("plain_alien_hives").expect("plain_alien_hives");
        let reads = capture_reads(&mut reg, plain);
        assert_eq!(reads.morale_bonus, 0, "no Courageous, no bonus");
    }

    /// Agile rides Quick's own params (+1" Advance, +2" Rush/Charge) — the
    /// entry's own `advance_mod`/`rush_mod`, not a constant. RED: drop the
    /// `move_rule_mods_of` arm (or the registry entry) and the carrier falls
    /// to `None`.
    #[test]
    fn agile_stamps_its_own_advance_and_rush_mods() {
        assert_eq!(
            quickfast_bands("agile_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 1.0, rush: 2.0 })
        );
        assert_eq!(
            quickfast_bands("plain_dark_elf_raiders", CURRENT_RULES_EPOCH),
            None,
            "no Agile, no stamp"
        );
        assert_eq!(quickfast_bands("agile_unit", 0), None, "epoch 0 reads the pre-port row");
    }

    /// Highborn = the Quick primitive's +2"/+2" alias. RED: drop the loop's
    /// "Highborn" literal (or the entry): `None`.
    #[test]
    fn highborn_stamps_the_quick_primitive_bands() {
        assert_eq!(
            quickfast_bands("highborn_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 2.0, rush: 2.0 })
        );
        assert_eq!(
            quickfast_bands("plain_high_elf_fleets", CURRENT_RULES_EPOCH),
            None,
            "no Highborn, no stamp"
        );
        assert_eq!(quickfast_bands("highborn_unit", 0), None, "epoch 0 is pre-port");
    }

    /// Quick itself — the name pass's own constant rule (+2"/+2"), stamped
    /// from its own entry's params. RED: drop the "Quick" literal: `None`.
    #[test]
    fn quick_stamps_its_own_entry_params() {
        assert_eq!(
            quickfast_bands("quick_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 2.0, rush: 2.0 })
        );
        assert_eq!(
            quickfast_bands("plain_goblin_reclaimers", CURRENT_RULES_EPOCH),
            None,
            "no Quick, no stamp"
        );
        assert_eq!(quickfast_bands("quick_unit", 0), None, "epoch 0 is pre-port");
    }

    /// Scurry = the Quick primitive's ratmen alias (+2"/+2"). RED: drop the
    /// "Scurry" literal (or the entry): `None`.
    #[test]
    fn scurry_stamps_its_own_entry_params() {
        assert_eq!(
            quickfast_bands("scurry_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 2.0, rush: 2.0 })
        );
        assert_eq!(
            quickfast_bands("plain_ratmen_clans", CURRENT_RULES_EPOCH),
            None,
            "no Scurry, no stamp"
        );
        assert_eq!(quickfast_bands("scurry_unit", 0), None, "epoch 0 is pre-port");
    }

    /// Rapid Charge rides Fast's `rush_mod` (+4" Charge; the rush band is the
    /// system's charge_reach), no advance half. RED: drop the "Rapid Charge"
    /// literal (or the entry): `None`.
    #[test]
    fn rapid_charge_stamps_fast_rush_mod_only() {
        assert_eq!(
            quickfast_bands("rapid_charge_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 0.0, rush: 4.0 })
        );
        assert_eq!(
            quickfast_bands("plain_wormhole_daemons_of_war", CURRENT_RULES_EPOCH),
            None,
            "no Rapid Charge, no stamp"
        );
        assert_eq!(quickfast_bands("rapid_charge_unit", 0), None, "epoch 0 is pre-port");
    }

    /// Rapid Charge Aura — its OWN gf entry carries the same
    /// `rush_mod`/`charge_mod` shape, so the aura name is a carrier in its
    /// own right (the raw-name arm keeps the core independent of the import's
    /// aura expander). The import is ADDITIVE (keeps "X Aura", appends "X"),
    /// so a real aura unit carries BOTH names and the stamp sums to +8
    /// exactly like both band passes' per-name `counted` stacks. RED: drop
    /// the "Rapid Charge Aura" literal: the aura row falls to `None`.
    #[test]
    fn rapid_charge_aura_stamps_own_entry_and_stacks_the_expansion() {
        assert_eq!(
            quickfast_bands("rapid_charge_aura_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 0.0, rush: 4.0 }),
            "the aura entry's own rush_mod"
        );
        assert_eq!(
            quickfast_bands("plain_alien_hives_qf", CURRENT_RULES_EPOCH),
            None,
            "no aura, no stamp"
        );
        assert_eq!(quickfast_bands("rapid_charge_aura_unit", 0), None, "epoch 0 is pre-port");
    }

    /// The import is ADDITIVE (keeps "X Aura", appends "X"), so a real aura
    /// unit carries BOTH names and the stamp sums to +8 — exactly like both
    /// band passes' per-name `counted` stacks.
    #[test]
    fn rapid_charge_aura_plus_expanded_base_stacks_like_the_loaders() {
        assert_eq!(
            quickfast_bands("rapid_charge_expanded_unit", CURRENT_RULES_EPOCH),
            Some(Bands { advance: 0.0, rush: 8.0 }),
            "aura + expanded base, the loaders' per-name stack"
        );
        assert_eq!(
            quickfast_bands("rapid_charge_expanded_unit", 0),
            None,
            "epoch 0 is pre-port"
        );
    }

    /// Royal Legion itself (aof mummified_undead): +4" range, +2" on Charge.
    /// RED: the fields stay 0.
    #[test]
    fn royal_legion_stamps_range_and_charge_at_epoch_6() {
        assert_eq!(royal_legion_halves("rl_unit", 6), (4.0, 2.0), "the entry's own range_bonus_in/charge_mod");
        assert_eq!(royal_legion_halves("plain_mummified", 6), (0.0, 0.0), "no Royal Legion, no stamp");
        assert_eq!(royal_legion_halves("rl_unit", 5), (0.0, 0.0), "epoch 5 is the Gen-3 fleet's window: none of wave 3");
    }

    /// Royal Legion Boost (aof mummified_undead) — the aof entry carries the
    /// base magnitudes (4/2) under the Boost's own name. RED: the fields stay 0.
    #[test]
    fn royal_legion_boost_stamps_through_its_own_entry() {
        assert_eq!(royal_legion_halves("rl_boost_unit", 6), (4.0, 2.0));
        assert_eq!(royal_legion_halves("rl_boost_unit", 5), (0.0, 0.0));
    }

    /// Royal Legion Boost Aura — its aof entry is primitive-bearing (4/2)
    /// under its own name, so the alias wave reaches it WITHOUT a raw-name arm.
    #[test]
    fn royal_legion_boost_aura_stamps_through_its_own_entry() {
        assert_eq!(royal_legion_halves("rl_boost_aura_unit", 6), (4.0, 2.0));
        assert_eq!(royal_legion_halves("rl_boost_aura_unit", 5), (0.0, 0.0));
    }

    /// Lustbound (aof lust_disciples) — the class's data alias, same 4/2
    /// magnitudes. RED: the fields stay 0.
    #[test]
    fn lustbound_stamps_range_and_charge_at_epoch_6() {
        assert_eq!(royal_legion_halves("lustbound_unit", 6), (4.0, 2.0));
        assert_eq!(royal_legion_halves("plain_lust_disciples", 6), (0.0, 0.0), "no Lustbound, no stamp");
        assert_eq!(royal_legion_halves("lustbound_unit", 5), (0.0, 0.0));
    }

    /// Lustbound Boost (aof lust_disciples): +8"/+4". The range half is the
    /// `_shooting_range_bonus` alias-MAX (8 wins over the base's 4 — the
    /// rule's own "instead of"), the charge half the band pass's flat per-name
    /// SUM (2+4=6 — neither twin's pass reads `upgrades`, the move_rule_mods
    /// precedent). RED: the fields stay 0.
    #[test]
    fn lustbound_boost_widens_both_halves_over_the_base() {
        assert_eq!(royal_legion_halves("lustbound_boost_unit", 6), (8.0, 4.0));
        assert_eq!(royal_legion_halves("lustbound_combo_unit", 6), (8.0, 6.0), "range takes the max, charge flat-folds per name — the loaders' own shape");
        assert_eq!(royal_legion_halves("lustbound_boost_unit", 5), (0.0, 0.0));
    }

    /// Lustbound Boost Aura — primitive-NULL in every shipped block (BY
    /// DESIGN: has_primitive false), so the alias wave cannot reach it; the
    /// raw-name arm expands it to "Lustbound Boost" the way the import does.
    #[test]
    fn lustbound_boost_aura_expands_to_its_base() {
        assert_eq!(royal_legion_halves("lustbound_boost_aura_unit", 6), (8.0, 4.0), "the base entry's own magnitudes through the expansion");
        assert_eq!(royal_legion_halves("lustbound_boost_aura_unit", 5), (0.0, 0.0));
    }

    /// Increased Shooting Range (gf alien_hives) — range-only alias, +6", no
    /// charge half. RED: the fields stay 0.
    #[test]
    fn increased_shooting_range_stamps_range_only() {
        assert_eq!(royal_legion_halves("isr_unit", 6), (6.0, 0.0));
        assert_eq!(royal_legion_halves("isr_unit", 5), (0.0, 0.0));
    }

    /// Increased Shooting Range Aura (aof havoc_dwarves) — its own entry is
    /// primitive-bearing (6/0), so the alias wave reaches it under its own name.
    #[test]
    fn increased_shooting_range_aura_stamps_through_its_own_entry() {
        assert_eq!(royal_legion_halves("isr_aura_unit", 6), (6.0, 0.0));
        assert_eq!(royal_legion_halves("isr_aura_unit", 5), (0.0, 0.0));
    }

    /// WAVE 3 (rules-wave3-fastband): Highborn Boost rides its OWN
    /// Fast-primitive entry (+4"/+4") on top of Highborn's +2"/+2" — the
    /// per-name stack both band passes fold — and fires only with the base
    /// rule its entry's `upgrades` param names ("If this model has
    /// Highborn"). Epoch literals, never a symbol: PRESENT at 6, ABSENT at 5
    /// (the recording fleet's epoch — the boost arm is off, Highborn's own
    /// 2/2 stands). RED: drop the epoch-6 arm (or the entry) and the epoch-6
    /// row falls back to 2/2.
    #[test]
    fn highborn_boost_stamps_its_own_entry_over_the_epoch6_gate() {
        assert_eq!(
            quickfast_bands("highborn_boost_unit", 6),
            Some(Bands { advance: 6.0, rush: 6.0 }),
            "Highborn 2/2 + Highborn Boost 4/4, the loaders' per-name stack"
        );
        assert_eq!(
            quickfast_bands("highborn_boost_unit", 5),
            Some(Bands { advance: 2.0, rush: 2.0 }),
            "epoch 5 (the recorder): the boost arm is off"
        );
        assert_eq!(
            quickfast_bands("highborn_boost_bare_unit", 6),
            None,
            "the boost fires only with its `upgrades` base rule carried"
        );
    }

    /// WAVE 3 (rules-wave3-fastband): Scurry Boost, same shape — its OWN
    /// Fast-primitive entry (+4"/+4") over Scurry's +2"/+2", gated on the
    /// entry's `upgrades` base rule and the epoch-6 gate (literals: present
    /// at 6, absent at 5). RED: drop the epoch-6 arm and the epoch-6 row
    /// falls back to 2/2.
    #[test]
    fn scurry_boost_stamps_its_own_entry_over_the_epoch6_gate() {
        assert_eq!(
            quickfast_bands("scurry_boost_unit", 6),
            Some(Bands { advance: 6.0, rush: 6.0 }),
            "Scurry 2/2 + Scurry Boost 4/4, the loaders' per-name stack"
        );
        assert_eq!(
            quickfast_bands("scurry_boost_unit", 5),
            Some(Bands { advance: 2.0, rush: 2.0 }),
            "epoch 5 (the recorder): the boost arm is off"
        );
    }

    /// "Violent" (Warbound/Destroyer/Infected's word-for-word twin, Shred
    /// primitive): enemies blocking on unmodified 1s take +1 wound — the
    /// shred-alias stamp on BOTH profiles at epoch 6; epoch 5 (the Gen-3
    /// fleet's stamping window) and the rule-less carrier stay clean.
    /// RED: the by-primitive walk is ungated, so the entry fires at 5 too.
    #[test]
    fn violent_shreds_block_rolls_of_one_at_epoch_6_not_5() {
        let on = wave3_static_of("Violent", "gf", "war_disciples", 6);
        assert!(
            on.shoot[0].shred_alias && on.melee[0].shred_alias,
            "the Shred alias at the wave's own epoch"
        );
        let before = wave3_static_of("Violent", "gf", "war_disciples", 5);
        assert!(
            !before.shoot[0].shred_alias && !before.melee[0].shred_alias,
            "rules_epoch 5 is the Gen-3 fleet's stamping-gap window, RED before the fix"
        );
        assert!(
            !wave3_static_of("", "gf", "war_disciples", 6).shoot[0].shred_alias,
            "no rule, no shred"
        );
    }

    /// "Vicious" (Bestial/Mischievous/Scrapper's word-for-word twin, Bane
    /// primitive, `reroll_save_sixes`): the defender re-rolls unmodified 6s
    /// against both profiles at epoch 6; epoch 5 and the rule-less carrier
    /// stay clean. RED: the coverage wave's own gate is epoch 3, older than
    /// the wave.
    #[test]
    fn vicious_rerolls_defender_sixes_at_epoch_6_not_5() {
        let on = wave3_static_of("Vicious", "gf", "jackals", 6);
        assert!(
            on.shoot[0].bane && on.melee[0].bane,
            "the Bane alias at the wave's own epoch"
        );
        let before = wave3_static_of("Vicious", "gf", "jackals", 5);
        assert!(
            !before.shoot[0].bane && !before.melee[0].bane,
            "rules_epoch 5 is the Gen-3 fleet's stamping-gap window, RED before the fix"
        );
        assert!(
            !wave3_static_of("", "gf", "jackals", 6).shoot[0].bane,
            "no rule, no re-roll"
        );
    }

    /// "Warding" (Angelic Blessing/Knightborn's word-for-word twin,
    /// Regeneration primitive): wounds ignored on a 6+, spell wounds on a 4+,
    /// at epoch 6; epoch 5 and the rule-less carrier stay (0, 0).
    /// RED: the regen alias wave's own gate is epoch 3, older than the wave.
    #[test]
    fn warding_ignores_wounds_on_six_and_spells_on_four_at_epoch_6_not_5() {
        let on = wave3_static_of("Warding", "aof", "kingdom_of_angels", 6);
        assert_eq!(
            (on.ctx.regen_target, on.ctx.regen_target_spell),
            (6, 4),
            "the entry's own ignore_target / ignore_target_spell"
        );
        let before = wave3_static_of("Warding", "aof", "kingdom_of_angels", 5);
        assert_eq!(
            (before.ctx.regen_target, before.ctx.regen_target_spell),
            (0, 0),
            "rules_epoch 5 is the Gen-3 fleet's stamping-gap window, RED before the fix"
        );
        assert_eq!(
            (
                wave3_static_of("", "aof", "kingdom_of_angels", 6).ctx.regen_target,
                wave3_static_of("", "aof", "kingdom_of_angels", 6).ctx.regen_target_spell
            ),
            (0, 0),
            "no rule, no ward"
        );
    }

    /// "Reach Hunt" (Royal Legion/Lustbound's word-for-word twin, Royal
    /// Legion primitive): +2" on Charge actions (the `charge_mod`) at epoch
    /// 6; epoch 5 and the rule-less carrier stay None. The +4" shooting-range
    /// half is the loader-side `shooting_range_bonus`, unmodelled on this
    /// core exactly like the twins' (sim.rs `has_shoot_target`'s note).
    /// RED: the name is not in the move-band list yet.
    #[test]
    fn reach_hunt_charges_two_inches_further_at_epoch_6_not_5() {
        assert_eq!(
            wave3_static_of("Reach Hunt", "aof", "lust_disciples", 6).move_rule_mods,
            Some(Bands { advance: 0.0, rush: 2.0 }),
            "the entry's own charge_mod"
        );
        assert_eq!(
            wave3_static_of("Reach Hunt", "aof", "lust_disciples", 5).move_rule_mods,
            None,
            "rules_epoch 5 is the Gen-3 fleet's stamping-gap window, RED before the fix"
        );
        assert_eq!(
            wave3_static_of("", "aof", "lust_disciples", 6).move_rule_mods,
            None,
            "no rule, no band"
        );
    }

    /// "Reinforced" PIN (NOT a port): its registry entry (Fortified
    /// primitive, the over-9"-gated form) is table-live through main.gd's
    /// own coverage wave, but the core's save batch sees no modifier
    /// distance (`dice.rs`'s documented Fortified-aliases gap), and a flat
    /// fortified stamp would over-credit at close range — the #489 shape.
    /// The name must stay MISSING in the core until the distance-gated fold
    /// exists; this test pins that decision.
    #[test]
    fn reinforced_stays_out_of_the_core_until_the_gated_fortified_fold_exists() {
        for epoch in [5, 6] {
            assert!(
                !wave3_static_of("Reinforced", "gf", "prime_brothers", epoch).ctx.fortified,
                "no flat fortified alias at epoch {epoch} — needs-primitive, not a flat stamp"
            );
        }
    }
