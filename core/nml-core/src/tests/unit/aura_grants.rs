use super::*;

    // --- The 41 AURA rows (PROVEN_VS_READ_PART2 2026-09-14, family "auras") ---
    //
    // One table-driven pin for the whole family. Two shapes live under the
    // "… Aura" names, and the table says which:
    //
    // GRANT rows (33): the registry entry resolves to the "Aura Channel"
    // primitive and carries `grants: "<base>"` — the grant-channel read
    // (`apply_aura_channel`/`aura_channel_hits`, unit.rs) hands the base to
    // the unit and every attached hero, additive and deduped, the loader's
    // own `_expand_auras` shape. Pinned per row through the REAL registry at
    // the build's CURRENT rules epoch:
    //   1. the entry's own shape: exact name, primitive "Aura Channel",
    //      `grants` == the table's base (a renamed aura fails loudly here);
    //   2. `build_for([aura]) == build_for([aura, base])` — the core-read
    //      grant lands byte-identical to the import-expanded shape (the
    //      fold's own documented invariant), so every number the base
    //      stamps (hit mod, AP, band, regen target, …) is asserted equal on
    //      the aura carrier;
    //   3. for OBSERVABLE bases: `build_for([aura]) != build_for([])` — the
    //      granted read is actually there ("present inside"), and at the
    //      frozen pre-gate epoch 5 it is gone again ("absent outside" —
    //      `EPOCH_6_TABLE_RULES` gates the fold, RED before the break).
    //      Rows whose base has no statics-time read in this core (Ambush,
    //      Dash, Grounded Precision's runtime gate, Rapid Blink Boost,
    //      Scout — each documented at its row) pin the grant channel only
    //      through legs 1–2 and say so.
    //   4. Hive Bond Boost's base is a Banner-primitive morale record: its
    //      number lives on the capture reads, not the statics — asserted
    //      through `capture_reads_for_epoch` by exact name.
    //
    // DIRECT rows (8): the ledger groups them with the auras, but their
    // registry entries carry the EFFECT directly (primitive Regeneration /
    // Evasive / Stealth / Shielded / Fast / Shot Modifier / Utility Buff, no
    // `grants` param) — nothing to grant, the entry IS the read. Pinned by
    // the entry's own number, at the exact name, with the rule-less control
    // leg. Shielded Aura and Fast Aura are the census's "recognised, read by
    // nobody" shape in this core — pinned INERT (byte-equal to the rule-less
    // carrier), which fails the moment anyone over-credits them.
    //
    // The names come from the ledger's auras family (41 rows, proof_kind
    // none); the two length asserts below fail loudly if a wave adds or
    // renames a row without updating this pin. No prefix matching anywhere:
    // every lookup is the row's exact name.

    /// (aura, system, faction, granted base, observable on the statics)
    /// — one row per GRANT-channel name, in the ledger's order.
    const GRANT_ROWS: &[(&str, &str, &str, &str, bool)] = &[
        ("Ambush Aura", "aof", "beastmen", "Ambush", false),
        ("Changebound Boost Aura", "aof", "change_disciples", "Changebound Boost", true),
        ("Clan Warrior Boost Aura", "gf", "eternal_dynasty", "Clan Warrior Boost", true),
        ("Dash Aura", "gf", "custodian_brothers", "Dash", false),
        ("Defensive Growth Aura", "gf", "human_inquisition", "Defensive Growth", true),
        ("Devout Boost Aura", "gf", "blessed_sisters", "Devout Boost", true),
        ("Ferocious Boost Aura", "aof", "orcs", "Ferocious Boost", true),
        ("Grounded Precision Aura", "aofs", "merchant_unions", "Grounded Precision", false),
        ("Guardian Boost Aura", "gf", "custodian_brothers", "Guardian Boost", true),
        ("Guerrilla Boost Aura", "gf", "rebel_guerrillas", "Guerrilla Boost", true),
        ("Harassing Boost Aura", "aof", "dark_elves", "Harassing Boost", true),
        ("Havocbound Boost Aura", "aof", "havoc_dwarves", "Havocbound Boost", true),
        ("Highborn Boost Aura", "aof", "high_elves", "Highborn Boost", true),
        ("Hive Bond Boost Aura", "gf", "alien_hives", "Hive Bond Boost", false),
        ("Ignores Cover Aura", "gf", "eternal_dynasty", "Ignores Cover", true),
        ("Ignores Cover when Shooting Aura", "gf", "dwarf_guilds", "Ignores Cover when Shooting", true),
        ("Infected Boost Aura", "gf", "infected_colonies", "Infected Boost", true),
        ("Infiltrate Aura", "gf", "dwarf_guilds", "Infiltrate", true),
        ("Machine-Fog Boost Aura", "gf", "machine_cults", "Machine-Fog Boost", true),
        ("Mischievous Boost Aura", "aof", "goblins", "Mischievous Boost", true),
        ("Piercing Assault Aura", "aof", "beastmen", "Piercing Assault", true),
        ("Plaguebound Boost Aura", "aof", "plague_disciples", "Plaguebound Boost", true),
        ("Point-Blank Piercing Aura", "gf", "blessed_sisters", "Point-Blank Piercing", true),
        ("Protection Feat Aura", "aofs", "crazed_zealots", "Protection Feat", true),
        ("Rapid Blink Boost Aura", "gf", "elven_jesters", "Rapid Blink Boost", false),
        ("Ravage Aura", "aof", "orcs", "Ravage", true),
        ("Relentless Aura", "aof", "dwarves", "Relentless", false),
        ("Scout Aura", "aof", "change_disciples", "Scout", false),
        ("Scrapper Boost Aura", "gf", "jackals", "Scrapper Boost", true),
        ("Screened Aura", "gf", "wormhole_daemons_of_plague", "Screened", true),
        ("Scurry Boost Aura", "aof", "ratmen", "Scurry Boost", true),
        ("Sturdy Boost Aura", "aof", "dwarves", "Sturdy Boost", true),
        ("Warbound Boost Aura", "aof", "rift_daemons_of_war", "Warbound Boost", true),
    ];

    /// One Rifle+Blade carrier in `system/faction` printing `rules`, built
    /// through the REAL registry at `epoch` — the aura row's unit under test.
    fn aura_carrier(system: &str, faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
        let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
        let tpl = AMBUSH_FAMILY_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"))
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
            .replace(RIFLE_ONLY, RIFLE_AND_BLADE);
        let header = read_act_header(&tpl).expect("aura carrier header parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    fn dbg_of(us: &UnitStatic) -> String {
        format!("{us:?}")
    }

    /// The whole GRANT family in one loop — one row per name, the row's own
    /// exact name everywhere.
    #[test]
    fn the_grant_channel_auras_deliver_their_base_at_the_current_epoch() {
        assert_eq!(GRANT_ROWS.len(), 33, "the ledger's 33 grant-channel aura rows");
        let all: Vec<&str> = GRANT_ROWS.iter().map(|r| r.0).collect();
        assert_eq!(all.len(), all.iter().collect::<std::collections::HashSet<_>>().len(),
            "no name twice — the table is the registry's aura list, one row per name");

        for (aura, system, faction, base, observable) in GRANT_ROWS.iter().copied() {
            // (1) The entry's own shape, by the EXACT name — a renamed aura
            // fails loudly right here.
            let mut reg = Registries::new(&repo_root());
            let e = reg
                .rules_for(system)
                .lookup(faction, aura)
                .unwrap_or_else(|| panic!("{aura}: no registry entry at {system}/{faction}"));
            assert_eq!(e.primitive.as_deref(), Some("Aura Channel"), "{aura}: the grant channel's primitive");
            assert_eq!(e.param_s("grants"), base, "{aura}: the entry's own `grants` base");

            // (2) The core-read grant == the import-expanded shape: every
            // number the base stamps is asserted equal on the aura carrier.
            let granted = aura_carrier(system, faction, &[aura], crate::acts::CURRENT_RULES_EPOCH);
            let imported = aura_carrier(system, faction, &[aura, base], crate::acts::CURRENT_RULES_EPOCH);
            assert_eq!(
                dbg_of(&granted),
                dbg_of(&imported),
                "{aura}: the core-read grant must land byte-identical to the import-expanded shape"
            );

            if !observable {
                continue; // the base has no statics-time read — legs 1–2 are the pin
            }

            // (3a) Present inside: the granted base moves the statics —
            // the RED-proof leg (a dead grant channel leaves the carrier
            // byte-identical to the rule-less unit).
            let plain = aura_carrier(system, faction, &[], crate::acts::CURRENT_RULES_EPOCH);
            assert_ne!(
                dbg_of(&granted),
                dbg_of(&plain),
                "{aura}: the granted base must be observable on the carrier"
            );
            // (3b) Absent outside: at the frozen pre-gate epoch the fold is
            // OFF and the carrier replays the rule-less reading byte-exact.
            let granted5 = aura_carrier(system, faction, &[aura], 5);
            let plain5 = aura_carrier(system, faction, &[], 5);
            assert_eq!(
                dbg_of(&granted5),
                dbg_of(&plain5),
                "{aura}: below EPOCH_6_TABLE_RULES the fold is OFF — RED before the break"
            );

            // Per-name numbers the base carries, asserted on the granted
            // carrier itself.
            match aura {
                "Guardian Boost Aura" => {
                    assert_eq!(granted.ctx.fortified_boost_ap, 1, "Guardian Boost's incoming_ap_reduction");
                }
                "Plaguebound Boost Aura" => {
                    assert_eq!(granted.ctx.regen_target, 5, "Plaguebound Boost's ignore_target");
                }
                "Protection Feat Aura" => {
                    assert_eq!(granted.ctx.regen_target, 5, "Protection Feat's ignore_target");
                }
                _ => {}
            }

            // (4) The Banner-primitive morale number lives on the capture
            // reads, not the statics — Hive Bond Boost's own number, by name.
            if aura == "Hive Bond Boost Aura" {
                let mut reg = Registries::new(&repo_root());
                let header = read_act_header(
                    &AMBUSH_FAMILY_HEADER
                        .replace("\"special_rules\":[]", "\"special_rules\":[\"Hive Bond Boost Aura\"]")
                        .replace("\"faction_folder\":\"robot_legions\"", "\"faction_folder\":\"alien_hives\"")
                        .replace(RIFLE_ONLY, RIFLE_AND_BLADE),
                )
                .expect("header");
                let p = header.profiles.get("carrier").expect("carrier");
                let reads = crate::unit::capture_reads_for_epoch(&mut reg, p, crate::acts::CURRENT_RULES_EPOCH);
                assert_eq!(reads.morale_bonus, 2, "Hive Bond Boost's morale_bonus");
                let bare = read_act_header(
                    &AMBUSH_FAMILY_HEADER
                        .replace("\"faction_folder\":\"robot_legions\"", "\"faction_folder\":\"alien_hives\"")
                        .replace(RIFLE_ONLY, RIFLE_AND_BLADE),
                )
                .expect("header");
                let p_bare = bare.profiles.get("carrier").expect("carrier");
                let no_grant =
                    crate::unit::capture_reads_for_epoch(&mut reg, p_bare, crate::acts::CURRENT_RULES_EPOCH);
                assert_eq!(no_grant.morale_bonus, 0, "no aura entry, no morale bonus");
            }
        }
    }

    /// The eight DIRECT rows: the entry IS the read (no `grants` channel) —
    /// each pinned by its own number at the exact name, with the rule-less
    /// control leg.
    #[test]
    fn the_direct_effect_aura_entries_stamp_their_own_numbers() {
        // Regeneration Aura (gf/alien_hives): ignore_target 5 — the regen
        // family's DATA-ALIAS wave reads the entry's own param.
        let us = aura_carrier("gf", "alien_hives", &["Regeneration Aura"], crate::acts::CURRENT_RULES_EPOCH);
        assert_eq!(us.ctx.regen_target, 5, "Regeneration Aura's own ignore_target");
        assert_eq!(
            aura_carrier("gf", "alien_hives", &[], crate::acts::CURRENT_RULES_EPOCH).ctx.regen_target,
            0,
            "no entry, no regen target"
        );

        // Evasive Aura (aof/ossified_undead): the Evasive-primitive alias —
        // hit_penalty 1 — without the literal "Evasive" name.
        let us = aura_carrier("aof", "ossified_undead", &["Evasive Aura"], crate::acts::CURRENT_RULES_EPOCH);
        assert!(us.ctx.evasive_alias, "Evasive Aura is the Evasive alias");
        assert_eq!(us.ctx.evasive_alias_name, "Evasive Aura", "the alias's own name");
        assert!(
            !aura_carrier("aof", "ossified_undead", &[], crate::acts::CURRENT_RULES_EPOCH).ctx.evasive_alias,
            "no entry, no alias"
        );

        // Stealth Aura (aof/eternal_wardens): the Stealth-primitive alias —
        // hit_penalty 1 within over_in 9.
        let us = aura_carrier("aof", "eternal_wardens", &["Stealth Aura"], crate::acts::CURRENT_RULES_EPOCH);
        assert_eq!(us.ctx.stealth_alias_penalty, 1, "Stealth Aura's hit_penalty");
        assert_eq!(us.ctx.stealth_alias_over_in, 9.0, "Stealth Aura's over_in");
        let bare = aura_carrier("aof", "eternal_wardens", &[], crate::acts::CURRENT_RULES_EPOCH);
        assert_eq!(bare.ctx.stealth_alias_penalty, 0, "no entry, no alias penalty");

        // Precision Shooter Aura (aof/beastmen): the Shot Modifier family's
        // flat shooting +1 — the named carrier list in stamp_shot_modifier.
        let us = aura_carrier("aof", "beastmen", &["Precision Shooter Aura"], crate::acts::CURRENT_RULES_EPOCH);
        assert_eq!(us.shoot[0].hit_bonus, 1, "Precision Shooter Aura's flat hit_bonus");
        assert_eq!(
            aura_carrier("aof", "beastmen", &[], crate::acts::CURRENT_RULES_EPOCH).shoot[0].hit_bonus,
            0,
            "no entry, no shooting bonus"
        );

        // Precision Fighter Aura (aof/halflings): the Shot Modifier family's
        // melee leg — hit_bonus 1 onto the ctx (melee_only).
        let us = aura_carrier("aof", "halflings", &["Precision Fighter Aura"], crate::acts::CURRENT_RULES_EPOCH);
        assert_eq!(us.ctx.melee_hit_bonus, 1, "Precision Fighter Aura's melee hit_bonus");
        assert_eq!(
            aura_carrier("aof", "halflings", &[], crate::acts::CURRENT_RULES_EPOCH).ctx.melee_hit_bonus,
            0,
            "no entry, no melee bonus"
        );

        // Thrust in Melee Aura (aof/goblins): the Utility-Buff record whose
        // grants_rule "Thrust" (melee scope) feeds the thrust leg.
        let us = aura_carrier("aof", "goblins", &["Thrust in Melee Aura"], crate::acts::CURRENT_RULES_EPOCH);
        assert!(us.ctx.thrust_grant, "Thrust in Melee Aura's grants_rule Thrust");
        assert!(
            !aura_carrier("aof", "goblins", &[], crate::acts::CURRENT_RULES_EPOCH).ctx.thrust_grant,
            "no entry, no thrust"
        );

        // Shielded Aura (aof/dragon_empire) and Fast Aura
        // (aof/vampiric_undead) are the census's "recognised, read by
        // nobody" shape in this core: no walk reads them, so the honest pin
        // is INERTNESS — byte-identical to the rule-less carrier, which
        // fails the moment anyone over-credits the names.
        for (aura, system, faction) in [
            ("Shielded Aura", "aof", "dragon_empire"),
            ("Fast Aura", "aof", "vampiric_undead"),
        ] {
            let us = aura_carrier(system, faction, &[aura], crate::acts::CURRENT_RULES_EPOCH);
            let bare = aura_carrier(system, faction, &[], crate::acts::CURRENT_RULES_EPOCH);
            assert_eq!(dbg_of(&us), dbg_of(&bare), "{aura}: read by nobody — the carrier must stay inert");
        }
        assert_eq!(GRANT_ROWS.len() + 8, 41, "the ledger's full auras family: 33 grant + 8 direct");
    }
