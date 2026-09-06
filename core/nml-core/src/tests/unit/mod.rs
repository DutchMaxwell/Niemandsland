    use super::*;
    // Tests exercise "the current epoch" generically (bumped forward each
    // wave); production reads the FROZEN `EPOCH_3_TABLE_RULES` instead — see
    // acts.rs.
    use crate::acts::CURRENT_RULES_EPOCH;
    use crate::acts::read_act_header;
    use crate::rules::Registries;

    /// The checkout this crate lives in — mirrors `rows.rs`'s own helper.
    fn repo_root() -> String {
        format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
    }

    // The carrier template: the unit's `special_rules` and
    // `attached_hero_rules` are swapped in by the helpers below (empty lists =
    // the no-aura arm). The default faction stays robot_legions for the pure
    // name read — no registry entry resolves for it (the aura entry is
    // primitive-null BY DESIGN; that is the STAMPED cap this wave lifts).
    // The wiring test swaps to human_defense_force, whose registry entry
    // resolves the granted base ("Targeting Visor Boost", Shot Modifier,
    // hit_bonus 1).
    const BOOST_AURA_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,
          "rules":[]}]}}}"#;

    /// The wave-3 expansion read at `epoch` over the carrier template: the
    /// EXPANDED profile (`expand_boost_aura`'s own output, so `build_for` can
    /// consume exactly what the read produced).
    fn boost_aura_profile(faction: &str, special: &str, heroes: &str, epoch: u32) -> Profile {
        let tpl = BOOST_AURA_HEADER
            .replace("robot_legions", faction)
            .replace(
                "\"special_rules\":[]",
                &format!("\"special_rules\":{special}"),
            )
            .replace(
                "\"attached_hero_rules\":[]",
                &format!("\"attached_hero_rules\":{heroes}"),
            );
        let header = read_act_header(&tpl).expect("header");
        let p = header.profiles.get("carrier").expect("carrier");
        expand_boost_aura(p, epoch).into_owned()
    }

    /// The wave-3 expansion read at `epoch`: the (special_rules,
    /// attached_hero_rules) pair after the read.
    fn boost_aura_expanded(
        special: &str,
        heroes: &str,
        epoch: u32,
    ) -> (Vec<String>, Vec<Vec<String>>) {
        let p = boost_aura_profile("robot_legions", special, heroes, epoch);
        (
            p.special_rules.clone(),
            p.attached_hero_rules.iter().map(|h| h.to_vec()).collect(),
        )
    }

    /// One aura name's truth table through the template: the base granted at
    /// epoch 6 (the entry core-read, the aura entry itself kept — additive,
    /// the loader's own shape), NOTHING at epoch 5 (`EPOCH_6_TABLE_RULES` is
    /// the frozen wave-3 gate — RED before the fix) and nothing without the
    /// aura. Epoch literals 6/5, NOT `CURRENT_RULES_EPOCH`: a wave-4 bump
    /// must not re-date what these assertions mean.
    macro_rules! boost_aura_test {
        ($test:ident, $aura:literal) => {
            #[test]
            fn $test() {
                let base = $aura.strip_suffix(" Aura").expect("aura name ends ' Aura'");
                let granted = |epoch: u32| {
                    let (special, _) =
                        boost_aura_expanded(&format!("[\"{}\"]", $aura), "[]", epoch);
                    special
                };
                assert!(
                    granted(6).iter().any(|r| r == base),
                    "epoch 6: the aura entry is core-read, grants '{}'",
                    base
                );
                assert!(
                    granted(6).iter().any(|r| r == $aura),
                    "the aura entry itself stays on the unit — additive, never removed"
                );
                assert!(
                    !granted(5).iter().any(|r| r == base),
                    "epoch 5: the gate is OFF (EPOCH_6_TABLE_RULES) — RED before the fix"
                );
                let (empty, _) = boost_aura_expanded("[]", "[]", 6);
                assert!(
                    empty.is_empty(),
                    "no aura entry, no grant — epoch 6 stays inert"
                );
            }
        };
    }

    boost_aura_test!(a_hold_the_line_boost_aura_grants_its_base_at_epoch_6, "Hold the Line Boost Aura");
    boost_aura_test!(a_targeting_visor_boost_aura_grants_its_base_at_epoch_6, "Targeting Visor Boost Aura");
    boost_aura_test!(a_warden_boost_aura_grants_its_base_at_epoch_6, "Warden Boost Aura");
    boost_aura_test!(a_lucky_boost_aura_grants_its_base_at_epoch_6, "Lucky Boost Aura");
    boost_aura_test!(a_buccaneer_boost_aura_grants_its_base_at_epoch_6, "Buccaneer Boost Aura");
    boost_aura_test!(a_vale_oath_boost_aura_grants_its_base_at_epoch_6, "Vale Oath Boost Aura");
    boost_aura_test!(a_wave_step_boost_aura_grants_its_base_at_epoch_6, "Wave-Step Boost Aura");
    boost_aura_test!(a_royal_warrior_boost_aura_grants_its_base_at_epoch_6, "Royal Warrior Boost Aura");
    boost_aura_test!(a_bestial_boost_aura_grants_its_base_at_epoch_6, "Bestial Boost Aura");
    boost_aura_test!(a_vinci_tech_boost_aura_grants_its_base_at_epoch_6, "Vinci Tech Boost Aura");
    boost_aura_test!(an_ossified_boost_aura_grants_its_base_at_epoch_6, "Ossified Boost Aura");
    boost_aura_test!(a_shadowborn_boost_aura_grants_its_base_at_epoch_6, "Shadowborn Boost Aura");
    boost_aura_test!(a_destroyer_boost_aura_grants_its_base_at_epoch_6, "Destroyer Boost Aura");
    boost_aura_test!(an_empyrean_spirit_boost_aura_grants_its_base_at_epoch_6, "Empyrean Spirit Boost Aura");
    boost_aura_test!(a_wild_veil_boost_aura_grants_its_base_at_epoch_6, "Wild Veil Boost Aura");

    /// Two units: `mark_carrier` prints "Unstoppable Mark" as a UNIT-level
    /// special rule and its Rifle carries no weapon rule at all; `real_unstop`
    /// prints nothing unit-level but its Cannon carries the real "Unstoppable"
    /// weapon rule. Neither unit fires a spell/mark GRANT (`sim::tray_vs_marks`
    /// / `Ctx::unstoppable_grant`) — this fixture is about the static profile
    /// flags `UnitStatic::build` stamps, not the live ledger #489 already
    /// covers in `sim.rs`.
    const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "mark_carrier":{"unit_id":"mark_carrier","name":"Mark Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Unstoppable Mark"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "real_unstop":{"unit_id":"real_unstop","name":"Real Unstoppable","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Cannon","range":24,"attacks":1,"count":1,"ap":0,"rules":["Unstoppable"]}]}}}"#;

    /// PROOF (1): a unit carrying only "Unstoppable Mark" has NO unstoppable
    /// on the tray path but keeps it on the EV path; a unit with a weapon's
    /// real "Unstoppable" rule has it on both. RED (revert `stamp_unit_
    /// strikers`'s `sp.unstoppable_ev = sp.unstoppable || u_unstop;` back to
    /// the pre-fix `sp.unstoppable |= u_unstop;`): this test fails, the tray
    /// assertion tripping on the now-true `unstoppable`.
    /// PROOF (1): a unit carrying only "Unstoppable Mark" has NO unstoppable
    /// on the tray path but keeps it on the EV path; a unit with a weapon's
    /// real "Unstoppable" rule has it on both. RED (revert `stamp_unit_
    /// strikers`'s `sp.unstoppable_ev = sp.unstoppable || u_unstop;` back to
    /// the pre-fix `sp.unstoppable |= u_unstop;`): this test fails, the tray
    /// assertion tripping on the now-true `unstoppable`.
    /// The family's registry stamp: each chaos Storm reads its OWN entry's
    /// params off the real gf registry, at epoch literals 6/5 — never
    /// `CURRENT_RULES_EPOCH` — so the assertions stay true after a bump.
    fn storm_spec(rule: &str, faction: &str, epoch: u32) -> Vec<StormSpec> {
        let p = Profile {
            unit_id: "carrier".into(),
            name: "carrier".into(),
            special_rules: vec![rule.into()],
            game_system: "gf".into(),
            faction_folder: faction.into(),
            ..storm_profile_template()
        };
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch).storm
    }

    use crate::state::MoveBands;

    /// A minimal `Profile` (no `Default`) with everything the stamp reads.
    fn storm_profile_template() -> Profile {
        Profile {
            unit_id: String::new(),
            name: String::new(),
            quality: 0,
            defense: 0,
            tough: 0,
            wounds_max: vec![],
            model_count: 1,
            weapons: vec![],
            special_rules: vec![],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: String::new(),
            faction_folder: String::new(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        }
    }

    /// Bane family (rules-wave-bane) — end to end through the REAL registry,
    /// one test per ported name. Each carrier holds a ranged Rifle (24") and a
    /// melee Blade, so a scope suffix is observable per profile; each test
    /// reads the stamp at `rules_epoch: CURRENT_RULES_EPOCH` (the new reading)
    /// and `0` (the flat prefix reading every earlier corpus replayed). The
    /// DATA-ALIAS carriers need the REAL (system, faction) entry their books
    /// print: aof/beastmen (Bestial), aof/goblins (Mischievous), gf/jackals
    /// (Scrapper, Scrapper Boost).
    const BANE_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Bane in Melee"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// Ambush family (rules-wave2-ambush) — the rule-less carrier template:
    /// `ambush_family_of` swaps a rule into `special_rules` (empty = the
    /// no-rule arm) and the faction over so the REAL gf registry entry
    /// resolves — the same factions the mechanics map fields.
    const AMBUSH_FAMILY_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// One name's family stamp at `epoch`: the `rule` swapped into the
    /// carrier's special_rules, the faction over so the real entry resolves.
    fn ambush_family_of(rule: &str, faction: &str, epoch: u32) -> AmbushFamily {
        let tpl = AMBUSH_FAMILY_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch).ambush_family
    }

    /// Piercing Tag family (wave 3) — one test per ported name, through the
    /// REAL gf registry (alien_hives / high_elf_fleets / custodian_brothers),
    /// the ambush template: the rule swapped into the carrier's
    /// special_rules, the faction over so the entry resolves. Epoch literals
    /// 6/5, NOT `CURRENT_RULES_EPOCH`: a wave-4 bump must not re-date what
    /// these assertions mean.
    fn piercing_tags_of(rule: &str, faction: &str, epoch: u32) -> Vec<PiercingTagEntry> {
        let tpl = AMBUSH_FAMILY_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch).piercing_tags
    }

    /// Battleborn family (rules-wave3-battleborn) — the rule-less carrier
    /// template: `battleborn_target_of` swaps the rule and the faction over
    /// so the REAL registry entry resolves — gf/titan_lords (Honor Code),
    /// aof/chivalrous_kingdoms (Vale Oath, Vale Oath Boost), aof/giant_tribes
    /// (Unmovable) — the same factions the mechanics maps field.
    const BATTLEBORN_FAMILY_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"titan_lords",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// One name's family stamp at `epoch`: the LOWEST `recover_target` the
    /// carrier's Battleborn-primitive aliases carry.
    fn battleborn_target_of(rule: &str, system: &str, faction: &str, epoch: u32) -> u32 {
        let tpl = BATTLEBORN_FAMILY_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"))
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"titan_lords\"", &format!("\"faction_folder\":\"{faction}\""));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch).battleborn_recover_target
    }

    /// Aura Channel wave (rules-wave3-aura2) — the carrier template: the
    /// unit's `special_rules` and `attached_hero_rules` swapped by the test
    /// helpers below (empty lists = the no-aura arm). System/faction stay
    /// robot_legions: the expansion read is a pure name read off the carried
    /// entries, no registry entry resolves for it (the aura entry is
    /// primitive-null BY DESIGN — that is the STAMPED cap this wave lifts).
    const AURA_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,
          "rules":[]}]}}}"#;

    /// The wave-3 expansion read at `epoch` for one carrier shape: `special`
    /// and `heroes` are the JSON arrays swapped into the template.
    fn aura_expanded(special: &str, heroes: &str, epoch: u32) -> Profile {
        let tpl = AURA_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":{special}"))
            .replace("\"attached_hero_rules\":[]", &format!("\"attached_hero_rules\":{heroes}"));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        expand_aura_channel(p, epoch).into_owned()
    }

    /// One aura name's truth table through the template: the base granted at
    /// epoch 6 (the entry core-read, the aura entry itself kept — additive,
    /// the loader's own shape), NOTHING at epoch 5 (`EPOCH_6_TABLE_RULES` is
    /// the frozen wave-3 gate — RED before the fix) and nothing without the
    /// aura. Epoch literals 6/5, NOT `CURRENT_RULES_EPOCH`: a wave-4 bump
    /// must not re-date what these assertions mean.
    macro_rules! aura_channel_test {
        ($test:ident, $aura:literal) => {
            #[test]
            fn $test() {
                let base = $aura.strip_suffix(" Aura").expect("aura name ends ' Aura'");
                let granted = |epoch: u32| {
                    aura_expanded(&format!("[\"{}\"]", $aura), "[]", epoch).special_rules
                };
                assert!(
                    granted(6).iter().any(|r| r == base),
                    "epoch 6: the aura entry is core-read, grants '{}'",
                    base
                );
                assert!(
                    granted(6).iter().any(|r| r == $aura),
                    "the aura entry itself stays on the unit — additive, never removed"
                );
                assert!(
                    !granted(5).iter().any(|r| r == base),
                    "epoch 5: the gate is OFF (EPOCH_6_TABLE_RULES) — RED before the fix"
                );
                assert!(
                    aura_expanded("[]", "[]", 6).special_rules.is_empty(),
                    "no aura entry, no grant — epoch 6 stays inert"
                );
            }
        };
    }

    aura_channel_test!(a_melee_evasion_aura_grants_its_base_at_epoch_6, "Melee Evasion Aura");
    aura_channel_test!(a_fearless_aura_grants_its_base_at_epoch_6, "Fearless Aura");
    aura_channel_test!(a_bounding_aura_grants_its_base_at_epoch_6, "Bounding Aura");
    aura_channel_test!(a_strider_aura_grants_its_base_at_epoch_6, "Strider Aura");
    aura_channel_test!(a_rending_in_melee_aura_grants_its_base_at_epoch_6, "Rending in Melee Aura");
    aura_channel_test!(a_quick_shot_aura_grants_its_base_at_epoch_6, "Quick Shot Aura");
    aura_channel_test!(a_piercing_hunter_aura_grants_its_base_at_epoch_6, "Piercing Hunter Aura");
    aura_channel_test!(a_teleport_aura_grants_its_base_at_epoch_6, "Teleport Aura");
    aura_channel_test!(a_hit_and_run_fighter_aura_grants_its_base_at_epoch_6, "Hit & Run Fighter Aura");
    aura_channel_test!(an_indirect_when_shooting_aura_grants_its_base_at_epoch_6, "Indirect when Shooting Aura");
    aura_channel_test!(a_piercing_fighter_aura_grants_its_base_at_epoch_6, "Piercing Fighter Aura");
    aura_channel_test!(a_rapid_advance_aura_grants_its_base_at_epoch_6, "Rapid Advance Aura");
    aura_channel_test!(a_ranged_slayer_aura_grants_its_base_at_epoch_6, "Ranged Slayer Aura");
    aura_channel_test!(a_melee_slayer_aura_grants_its_base_at_epoch_6, "Melee Slayer Aura");
    aura_channel_test!(a_speed_feat_aura_grants_its_base_at_epoch_6, "Speed Feat Aura");
    aura_channel_test!(a_reanimation_aura_grants_its_base_at_epoch_6, "Reanimation Aura");
    aura_channel_test!(a_piercing_shooter_aura_grants_its_base_at_epoch_6, "Piercing Shooter Aura");
    aura_channel_test!(a_grounded_reinforcement_aura_grants_its_base_at_epoch_6, "Grounded Reinforcement Aura");
    aura_channel_test!(a_grounded_protection_aura_grants_its_base_at_epoch_6, "Grounded Protection Aura");
    aura_channel_test!(a_protected_aura_grants_its_base_at_epoch_6, "Protected Aura");

    /// Indirect family (rules-wave3-indirect) — the rule-less carrier
    /// template: the `rule` swapped into `special_rules` so the REAL gf
    /// common-block entry resolves (both ported names live there), one ranged
    /// Rifle (24") so the shooting-only facet is observable.
    const INDIRECT_FAMILY_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":2,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// One name's family stamp: the `rule` swapped into the carrier's
    /// special_rules, built at `epoch` off the REAL registry.
    fn indirect_family_of(rule: &str, epoch: u32) -> UnitStatic {
        let tpl = INDIRECT_FAMILY_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// One rule's truth table through the template: the (shoot, melee) bane
    /// stamp at `epoch`, with `rule` swapped into the carrier's special_rules
    /// and (system, faction) set so the REAL registry entry resolves (the
    /// alias wave needs aof/beastmen, aof/goblins, gf/jackals).
    fn bane_stamp_of(rule: &str, system: &str, faction: &str, epoch: u32) -> (bool, bool) {
        let tpl = BANE_HEADER
            .replace("\"Bane in Melee\"", &format!("\"{rule}\""))
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        let us = UnitStatic::build_for(&mut reg, p, epoch);
        (us.shoot[0].bane, us.melee[0].bane)
    }

    /// Block B6, end to end through the REAL registry: `saurian_starhost/gf`'s
    /// "Primal" (`Surge`, `extra_attack: true`, no melee_only/shooting_only)
    /// reaches BOTH ranged and melee profiles, and "Primal Boost" moves
    /// `surge_attack_low` to 5 on both; `alien_hives/gf`'s "Predator Fighter"
    /// (same primitive, `melee_only: true`) reaches ONLY the melee profile.
    const SURGE_ATTACK_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "primal_beast":{"unit_id":"primal_beast","name":"Primal Beast","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"saurian_starhost",
        "special_rules":["Primal","Primal Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},
          {"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "predator_fighter_unit":{"unit_id":"predator_fighter_unit","name":"Predator","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Predator Fighter"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Spitter","range":18,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Talons","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// Block C4 — the death-half field, end to end through the REAL registry:
    /// the rating is the rule's own (`maxi(rating, 1)`), each literal is
    /// registry-gated (`unit_rule_active`). gf goblin_reclaimers fields
    /// Deathstrike, gf alien_hives fields Self-Destruct, robot_legions fields
    /// neither (a carrier there stays silent). RED (drop a literal from
    /// `death_hits_per_kill`): its carrier's count falls to 0.
    const DEATH_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "ds_goblin":{"unit_id":"ds_goblin","name":"DS Goblin","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"goblin_reclaimers",
        "special_rules":["Deathstrike(2)"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Slasha","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "sd_hive":{"unit_id":"sd_hive","name":"SD Hive","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Self-Destruct(3)"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "ds_bare":{"unit_id":"ds_bare","name":"DS Bare","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"goblin_reclaimers",
        "special_rules":["Deathstrike"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Slasha","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "ds_nomap":{"unit_id":"ds_nomap","name":"DS Nomap","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Deathstrike(2)"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// Block C5 — Instinctive stamped end to end through the REAL registry:
    /// gf goblin_reclaimers and aof vampiric_undead field
    /// `Instinctive {force_closest_target: true, hit_bonus: 1}`; a carrier
    /// whose faction map fields nothing stays 0. RED (drop the literal from
    /// `instinctive_hit_bonus`): every carrier falls to 0.
    const INSTINCTIVE_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "inst_gf":{"unit_id":"inst_gf","name":"Inst GF","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"goblin_reclaimers",
        "special_rules":["Instinctive"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Slasha","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "inst_aof":{"unit_id":"inst_aof","name":"Inst AoF","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"vampiric_undead",
        "special_rules":["Instinctive"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "inst_nomap":{"unit_id":"inst_nomap","name":"Inst Nomap","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Instinctive"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// Block B10 — Resistance end to end through the REAL registry
    /// (`alien_hives/gf` fields it with `ignore_target:6,
    /// ignore_target_spell:2, all_models:true`). `resist_whole` carries it
    /// alone (whole unit = the models); `resist_partial` carries it but its
    /// attached hero does NOT — `_solo_rule_on_all_models` (main.gd:4599)
    /// gates the whole family, so the partial unit gets NO regeneration from
    /// Resistance. RED (disable the Resistance leg in `regen_targets`):
    /// `resist_whole`'s assertions trip on regen_target 0 vs 6.
    const RESISTANCE_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "resist_whole":{"unit_id":"resist_whole","name":"Resist Whole","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Resistance"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "resist_partial":{"unit_id":"resist_partial","name":"Resist Partial","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Resistance"],"item_grants":[],
        "attached_hero_rules":[["Fearless"]],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    // ====================================== Regeneration family alias wave ====

    /// The Regeneration family's DATA-ALIAS wave, end to end through the REAL
    /// registry — one unit per ported name, in the faction whose mechanics
    /// map fields the entry (`_forge/names.md`'s twelve, all primitive
    /// "Regeneration"). RED (drop the `rule_on` gate in `regen_targets`): the
    /// epoch-0 asserts trip — the alias layer is new behaviour, so the
    /// pre-epoch corpora must keep reading 0/0. RED (drop the `all_models`
    /// gate): `plague_partial`'s asserts trip.
    const REGEN_FAMILY_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "angelic":{"unit_id":"angelic","name":"Angelic","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"kingdom_of_angels",
        "special_rules":["Angelic Blessing"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "angelic_boost":{"unit_id":"angelic_boost","name":"Angelic Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"kingdom_of_angels",
        "special_rules":["Angelic Blessing Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "cursed":{"unit_id":"cursed","name":"Cursed","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"vampiric_undead",
        "special_rules":["Cursed Undead"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "cursed_boost":{"unit_id":"cursed_boost","name":"Cursed Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"vampiric_undead",
        "special_rules":["Cursed Undead Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "plague":{"unit_id":"plague","name":"Plague","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"plague_disciples",
        "special_rules":["Plaguebound"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "plague_boost":{"unit_id":"plague_boost","name":"Plague Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"plague_disciples",
        "special_rules":["Plaguebound Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "plague_partial":{"unit_id":"plague_partial","name":"Plague Partial","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"plague_disciples",
        "special_rules":["Plaguebound"],"item_grants":[],
        "attached_hero_rules":[["Fearless"]],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "protected":{"unit_id":"protected","name":"Protected","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"duchies_of_vinci",
        "special_rules":["Protected"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "protection_feat":{"unit_id":"protection_feat","name":"Protection Feat","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"saurians",
        "special_rules":["Protection Feat"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "grounded":{"unit_id":"grounded","name":"Grounded","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"volcanic_dwarves",
        "special_rules":["Grounded Protection"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "knightborn":{"unit_id":"knightborn","name":"Knightborn","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"knight_brothers",
        "special_rules":["Knightborn"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "self_repair_boost":{"unit_id":"self_repair_boost","name":"Self-Repair Boost","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":["Self-Repair Boost"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "regen_buff":{"unit_id":"regen_buff","name":"Regeneration Buff","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"ossified_undead",
        "special_rules":["Regeneration Buff"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "bare_aof":{"unit_id":"bare_aof","name":"Bare Aof","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"kingdom_of_angels",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "bare_gf":{"unit_id":"bare_gf","name":"Bare Gf","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"knight_brothers",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// (regen_target, regen_target_spell) for one fixture unit at one epoch.
    fn regen_pair_at(header: &crate::acts::ActHeader, key: &str, epoch: u32) -> (i64, i64) {
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(key).expect(key);
        let us = UnitStatic::build_for(&mut reg, p, epoch);
        (us.ctx.regen_target, us.ctx.regen_target_spell)
    }

    // ================================================ mutant-killing tests ====

    /// Three profiles for `growth_of`: one plain "Piercing Growth" carrier
    /// (alien_hives: per_round, max_markers 4, ap_per_two 1), one carrying
    /// the same rule TWICE in special_rules (the de-dup case), and one
    /// "Defensive Growth" carrier (human_inquisition) whose params carry NO
    /// ap/hit facet at all.
    const GROWTH_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "growth_carrier":{"unit_id":"growth_carrier","name":"Growth Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Piercing Growth"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "growth_dup":{"unit_id":"growth_dup","name":"Growth Dup","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Piercing Growth","Piercing Growth"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "growth_zero":{"unit_id":"growth_zero","name":"Growth Zero","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"human_inquisition",
        "special_rules":["Defensive Growth"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// One "Regenerative Strength" carrier (alien_hives: on_ignore_wound,
    /// attacks_per_marker 1, scope one_melee_weapon) — the epoch-6 wave's
    /// registry read.
    const GROWTH_RS_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "rs_carrier":{"unit_id":"rs_carrier","name":"RS Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Regenerative Strength"],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// Five gf units chosen so the REGISTRY tells them apart, not a stub.
    /// `alien_hives` fields an `Infiltrate` entry (`min_enemy_dist_in: 3.0`) and
    /// NO `Repel Ambushers`; `eternal_dynasty` is the mirror image (a
    /// `Repel Ambushers` entry at `min_dist_in: 12.0`, no `Infiltrate`).
    const AMBUSH_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "inf_registry":{"unit_id":"inf_registry","name":"Infiltrator","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Infiltrate"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "inf_unmapped":{"unit_id":"inf_unmapped","name":"Unmapped Infiltrator","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"eternal_dynasty",
        "special_rules":["Infiltrate"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "plain_ambusher":{"unit_id":"plain_ambusher","name":"Plain Ambusher","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Ambush","Ambush Beacon"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "repel_carrier":{"unit_id":"repel_carrier","name":"Repeller","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"eternal_dynasty",
        "special_rules":["Repel Ambushers"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},
      "repel_unmapped":{"unit_id":"repel_unmapped","name":"Unmapped Repeller","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives",
        "special_rules":["Repel Ambushers"],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;

    fn ambush_static(key: &str) -> UnitStatic {
        let header = read_act_header(AMBUSH_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build(&mut reg, header.profiles.get(key).expect(key))
    }

    /// Block C (Versatile Reach) end to end through the REAL registry: the
    /// base rule's `charge_bonus_in` param (`battle_brothers/gf`, identical
    /// 2.0 on every occurrence) stamps `Some(2.0)`; a profile without either
    /// name stamps `None`. RED the moment the rule-NAME literal is misspelled
    /// (the field then falls to `None` on every arm).
    const VR_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "vr_carrier":{"unit_id":"vr_carrier","name":"VR Carrier","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers","special_rules":["Versatile Reach"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "vr_plain":{"unit_id":"vr_plain","name":"VR Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers","special_rules":["Fearless"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "vr_aura":{"unit_id":"vr_aura","name":"VR Aura","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers","special_rules":["Versatile Reach Aura"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// Rung C data port (AUDIT_armybook_flanks_2026-09-02.md §"NO REGISTRY
    /// ENTRY"): six names with no registry entry in any system, now aliased
    /// onto an existing primitive through the SAME faction folders the new
    /// `assets/solo/rules_mechanics_gf.json` entries live in. Each carrier
    /// sits next to a plain non-carrier in the identical faction, so the
    /// registry lookup (system, faction, name) is exercised for real, not
    /// synthesised.
    const RUNG_C_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "screened_unit":{"unit_id":"screened_unit","name":"Screened Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"change_disciples","special_rules":["Screened"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_change_disciple":{"unit_id":"plain_change_disciple","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"change_disciples","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "predator_unit":{"unit_id":"predator_unit","name":"Predator Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"saurian_starhost","special_rules":["Predator"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_saurian_starhost":{"unit_id":"plain_saurian_starhost","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"saurian_starhost","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "brutal_unit":{"unit_id":"brutal_unit","name":"Brutal Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":["Brutal"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_blessed_sisters":{"unit_id":"plain_blessed_sisters","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "precision_hunter_unit":{"unit_id":"precision_hunter_unit","name":"Precision Hunter Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"dao_union","special_rules":["Precision Hunter"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_dao_union":{"unit_id":"plain_dao_union","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"dao_union","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "nimble_unit":{"unit_id":"nimble_unit","name":"Nimble Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"elven_jesters","special_rules":["Nimble"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_elven_jesters":{"unit_id":"plain_elven_jesters","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"elven_jesters","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "courageous_unit":{"unit_id":"courageous_unit","name":"Courageous Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives","special_rules":["Courageous"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_alien_hives":{"unit_id":"plain_alien_hives","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// The Fortified family's seven carriers — one per name — plus a plain gf
    /// sibling. The registry entries they resolve against are the SHIPPED ones
    /// (rules_mechanics_gf.json custodian_brothers / prime_brothers,
    /// rules_mechanics_aof.json eternal_wardens / ossified_undead); the header
    /// only stamps the carriers. Every weapon is AP(1) so the save target
    /// moves exactly one step when the family fires.
    const FORTIFIED_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "guardian_unit":{"unit_id":"guardian_unit","name":"Guardian Bearer","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"custodian_brothers","special_rules":["Guardian"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]},{"name":"CCW","range":0,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]}]},
      "guardian_boost_unit":{"unit_id":"guardian_boost_unit","name":"Guardian Boost Bearer","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"custodian_brothers","special_rules":["Guardian Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]},{"name":"CCW","range":0,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]}]},
      "primeborn_unit":{"unit_id":"primeborn_unit","name":"Primeborn Bearer","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"prime_brothers","special_rules":["Primeborn"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]},{"name":"CCW","range":0,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]}]},
      "warden_unit":{"unit_id":"warden_unit","name":"Warden Bearer","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"eternal_wardens","special_rules":["Warden"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]},{"name":"CCW","range":0,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]}]},
      "warden_boost_unit":{"unit_id":"warden_boost_unit","name":"Warden Boost Bearer","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"eternal_wardens","special_rules":["Warden Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]},{"name":"CCW","range":0,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]}]},
      "ossified_unit":{"unit_id":"ossified_unit","name":"Ossified Bearer","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"ossified_undead","special_rules":["Ossified"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]},{"name":"CCW","range":0,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]}]},
      "ossified_boost_unit":{"unit_id":"ossified_boost_unit","name":"Ossified Boost Bearer","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"ossified_undead","special_rules":["Ossified Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]},{"name":"CCW","range":0,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]}]},
      "plain_unit":{"unit_id":"plain_unit","name":"Plain Bearer","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"custodian_brothers","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]},{"name":"CCW","range":0,"attacks":2,"count":1,"ap":1,"rules":["AP(1)"]}]}}}"#;

    /// Builds the named carrier at `epoch` — the per-name tests' own build.
    fn fortified_unit(key: &str, epoch: u32) -> UnitStatic {
        let header = read_act_header(FORTIFIED_HEADER).expect("FORTIFIED_HEADER parses");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get(key).unwrap_or_else(|| panic!("{key}"));
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// One AP(1) rifle volley (64 attacks) at the carrier, centre distance
    /// `dist_in` — returns (save target, alias/boost arm fired).
    fn fortified_volley(us: &UnitStatic, dist_in: f64) -> (i64, bool) {
        let mut tray = crate::dice::Tray::seeded(27);
        let out = crate::dice::resolve_shooting_with_tray(
            &us.shoot, &[0], &[64], &Ctx { quality: 4, ..us.ctx }, &us.ctx, dist_in, &mut tray,
        );
        (out.rolls[1].target, out.fortified_fired)
    }

    /// One AP(1) CCW strike phase (64 attacks) against the carrier — the
    /// Boost names' own leg: no distance exists here, the no-gate shape
    /// applies. Returns (save target, alias/boost arm fired).
    fn fortified_melee(us: &UnitStatic) -> (i64, bool) {
        let strikers = [crate::dice::Shooter {
            profiles: &us.melee, keep: &[0], attacks: &[64], att: &us.ctx, owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        let out = crate::dice::resolve_melee_with_tray(
            &strikers, &us.ctx, "def", false, true, false, &mut tray,
        );
        (out.rolls[1].target, out.fortified_fired)
    }

    /// Lacerate+Counter wave — one melee-weapon carrier per Counter DATA
    /// alias next to a plain sibling. The stamp is the EPOCH-gated one
    /// (`UnitStatic::build`'s `rule_on` gate), so every test reads the rule at
    /// the current epoch, at epoch 0 (every recorded corpus) and without the
    /// rule — the three rows the port must never confuse.
    const COUNTER_ALIASES_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "counter_attack_unit":{"unit_id":"counter_attack_unit","name":"Counter-Attack Bearer","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions","special_rules":["Counter-Attack"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "counter_in_melee_unit":{"unit_id":"counter_in_melee_unit","name":"Counter in Melee Bearer","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions","special_rules":["Counter in Melee"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_unit":{"unit_id":"plain_unit","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// Surge family wave 2 (rules-wave2-surge2) — one test per ported name,
    /// end to end through the REAL registry (each name's own (system, faction)
    /// entry, the folder its book prints). The six names ride the plain
    /// auto-hit form: the generic alias walk (stamp's block 3, ungated) has
    /// stamped them since the coverage wave, and build_for's named arm (gated
    /// `EPOCH_5_TABLE_RULES`, frozen at 5 — the stamping-gap fix, NOT the
    /// naive 4) states the same facet BY NAME on top. Since the generic walk
    /// already covers these six names, the named arm is a redundant safety
    /// net for THEM specifically: the assertions below stay true at 4
    /// (Gen-2b's stamping-gap window) exactly as they did at 3, unlike
    /// Lacerate/Ambush/Utility Buff, whose gates are the ONLY path to their
    /// effect and so DO flip at the new boundary (see their own tests).
    /// Present at 5 (the named arm) and at 3/4 (the pre-wave generic walk,
    /// byte-exact — the wave must never re-date it), absent WITHOUT the rule
    /// (the RED leg; the effect predates the epoch mechanism, the Brutal
    /// Fighter precedent).
    const SURGE_WAVE2_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":["Brutal"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// One rule's truth table through the template: the (shoot, melee) surge
    /// stamp at `epoch`, with `rule` swapped into the carrier's special_rules
    /// and (system, faction) set so the REAL registry entry resolves.
    fn surge_stamp_of(rule: &str, system: &str, faction: &str, epoch: u32) -> (bool, bool) {
        let tpl = SURGE_WAVE2_HEADER
            .replace("\"Brutal\"", &format!("\"{rule}\""))
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"blessed_sisters\"", &format!("\"faction_folder\":\"{faction}\""));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        let us = UnitStatic::build_for(&mut reg, p, epoch);
        (us.shoot[0].surge, us.melee[0].surge)
    }

    /// The Surge family's plain-form gates through the REAL registry: Devout
    /// Boost stamps `surge_low`/`surge_over_in` onto every profile Devout gave
    /// `surge` (ai_ev.gd:250-260) and stops being reported unimplemented;
    /// Point-Blank stamps its `within_in` on BOTH facets (no `shooting_only`
    /// in the entry). RED: drop the stamp arms or the entries — the asserts
    /// fall back to the defaults.
    const SURGE_GATES_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "devout_boost_unit":{"unit_id":"devout_boost_unit","name":"Devout Boost Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":["Devout","Devout Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "plain_blessed":{"unit_id":"plain_blessed","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "point_blank_unit":{"unit_id":"point_blank_unit","name":"Point Blank Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"blessed_sisters","special_rules":["Point-Blank Surge"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "brutal_fighter_unit":{"unit_id":"brutal_fighter_unit","name":"Brutal Fighter Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"human_inquisition","special_rules":["Brutal Fighter"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
      "plain_inquisition":{"unit_id":"plain_inquisition","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"human_inquisition","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// The Quick/Fast move-band family's six carriers, one per real gf faction
    /// block (`assets/solo/rules_mechanics_gf.json`), each next to a plain
    /// sibling in the SAME faction so the (system, faction, name) lookup is
    /// real. Three rows per name: stamped with the rule at
    /// CURRENT_RULES_EPOCH, absent without the rule, absent at epoch 0 —
    /// the same reading the recorded (epoch 0/2) corpora replay with.
    const QUICKFAST_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "agile_unit":{"unit_id":"agile_unit","name":"Agile Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"dark_elf_raiders","special_rules":["Agile"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_dark_elf_raiders":{"unit_id":"plain_dark_elf_raiders","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"dark_elf_raiders","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "highborn_unit":{"unit_id":"highborn_unit","name":"Highborn Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"high_elf_fleets","special_rules":["Highborn"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_high_elf_fleets":{"unit_id":"plain_high_elf_fleets","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"high_elf_fleets","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "quick_unit":{"unit_id":"quick_unit","name":"Quick Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"goblin_reclaimers","special_rules":["Quick"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_goblin_reclaimers":{"unit_id":"plain_goblin_reclaimers","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"goblin_reclaimers","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "scurry_unit":{"unit_id":"scurry_unit","name":"Scurry Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":["Scurry"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_ratmen_clans":{"unit_id":"plain_ratmen_clans","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "rapid_charge_unit":{"unit_id":"rapid_charge_unit","name":"Rapid Charge Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"wormhole_daemons_of_war","special_rules":["Rapid Charge"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_wormhole_daemons_of_war":{"unit_id":"plain_wormhole_daemons_of_war","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"wormhole_daemons_of_war","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "rapid_charge_aura_unit":{"unit_id":"rapid_charge_aura_unit","name":"Rapid Charge Aura Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives","special_rules":["Rapid Charge Aura"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "rapid_charge_expanded_unit":{"unit_id":"rapid_charge_expanded_unit","name":"Rapid Charge Expanded","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives","special_rules":["Rapid Charge Aura","Rapid Charge"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_alien_hives_qf":{"unit_id":"plain_alien_hives_qf","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "highborn_boost_unit":{"unit_id":"highborn_boost_unit","name":"Highborn Boost Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"high_elf_fleets","special_rules":["Highborn","Highborn Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "highborn_boost_bare_unit":{"unit_id":"highborn_boost_bare_unit","name":"Highborn Boost Bare","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"high_elf_fleets","special_rules":["Highborn Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "scurry_boost_unit":{"unit_id":"scurry_boost_unit","name":"Scurry Boost Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"ratmen_clans","special_rules":["Scurry","Scurry Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn quickfast_bands(name: &str, rules_epoch: u32) -> Option<Bands> {
        let header = read_act_header(QUICKFAST_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, header.profiles.get(name).expect(name), rules_epoch).move_rule_mods
    }

    /// The Royal Legion family (wave 3, epoch 6) — one carrier per name, each
    /// next to a plain sibling in the SAME real faction block so the
    /// (system, faction, name) lookup is real. Reads the rule at the literal
    /// epoch 6 (present) and 5 (absent — the Gen-3 fleet's own stamping window
    /// must never gain wave 3), so the test keeps meaning what it says after
    /// the next epoch bump.
    const ROYAL_LEGION_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "rl_unit":{"unit_id":"rl_unit","name":"Royal Legion Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"mummified_undead","special_rules":["Royal Legion"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_mummified":{"unit_id":"plain_mummified","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"mummified_undead","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "rl_boost_unit":{"unit_id":"rl_boost_unit","name":"Royal Legion Boost Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"mummified_undead","special_rules":["Royal Legion Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "rl_boost_aura_unit":{"unit_id":"rl_boost_aura_unit","name":"Royal Legion Boost Aura Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"mummified_undead","special_rules":["Royal Legion Boost Aura"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "lustbound_unit":{"unit_id":"lustbound_unit","name":"Lustbound Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"lust_disciples","special_rules":["Lustbound"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "lustbound_boost_unit":{"unit_id":"lustbound_boost_unit","name":"Lustbound Boost Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"lust_disciples","special_rules":["Lustbound Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "lustbound_combo_unit":{"unit_id":"lustbound_combo_unit","name":"Lustbound Combo Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"lust_disciples","special_rules":["Lustbound","Lustbound Boost"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "lustbound_boost_aura_unit":{"unit_id":"lustbound_boost_aura_unit","name":"Lustbound Boost Aura Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"lust_disciples","special_rules":["Lustbound Boost Aura"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "plain_lust_disciples":{"unit_id":"plain_lust_disciples","name":"Plain","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"lust_disciples","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "isr_aura_unit":{"unit_id":"isr_aura_unit","name":"Increased Shooting Range Aura Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"aof","faction_folder":"havoc_dwarves","special_rules":["Increased Shooting Range Aura"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]},
      "isr_unit":{"unit_id":"isr_unit","name":"Increased Shooting Range Unit","quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"alien_hives","special_rules":["Increased Shooting Range"],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

    fn royal_legion_halves(name: &str, rules_epoch: u32) -> (f64, f64) {
        let header = read_act_header(ROYAL_LEGION_HEADER).expect("header");
        let mut reg = Registries::new(&repo_root());
        let us = UnitStatic::build_for(
            &mut reg,
            header.profiles.get(name).expect(name),
            rules_epoch,
        );
        (us.royal_legion_range_in, us.royal_legion_charge_in)
    }

    // ------------------------------------------------------------------
    // The "Unregistered Rules" wave (epoch 6) — one test per ported name,
    // through the REAL registry. Each carrier holds a ranged Rifle (24") and
    // a melee Blade, so the shooting/melee scoping is observable per profile.
    // Epoch literals 6/5, NOT `CURRENT_RULES_EPOCH`: a wave-4 bump must not
    // re-date what these assertions mean (the Ambush family's rule).
    const WAVE3_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// One name's wave-3 static at `epoch`: `rule` swapped into the carrier's
    /// special_rules, (system, faction) over so the REAL registry entry
    /// resolves — the same factions the mechanics maps field.
    fn wave3_static_of(rule: &str, system: &str, faction: &str, epoch: u32) -> UnitStatic {
        let tpl = WAVE3_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"))
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""));
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    // One name per test: the effect PRESENT at epoch 6, ABSENT at epoch 5 or
    // without the rule. Epoch LITERALS (never CURRENT_RULES_EPOCH) so the
    // assertions keep their meaning after the next epoch bump — the fold is
    // gated `rule_on(rules_epoch, EPOCH_6_TABLE_RULES)`.

    /// One aura carrier's `UnitStatic` at `epoch`: the rule swapped into a
    /// gf unit of `faction`, the REAL registry resolving the entry's
    /// `grants` base and the base's own effect. Empty rule = the rule-less
    /// carrier leg.
    fn aura_static(rule: &str, faction: &str, epoch: u32) -> UnitStatic {
        let tpl = if rule.is_empty() {
            AMBUSH_FAMILY_HEADER.to_string()
        } else {
            AMBUSH_FAMILY_HEADER
                .replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"))
                .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
                .replace(RIFLE_ONLY, RIFLE_AND_BLADE)
        };
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// The melee-array legs need a NON-EMPTY melee table — `all()` over an
    /// empty vec would assert nothing.
    const RIFLE_ONLY: &str = "\"weapons\":[{\"name\":\"Rifle\",\"range\":24,\"attacks\":1,\"count\":1,\"ap\":0,\"rules\":[]}]";
    const RIFLE_AND_BLADE: &str = "\"weapons\":[{\"name\":\"Rifle\",\"range\":24,\"attacks\":1,\"count\":1,\"ap\":0,\"rules\":[]},{\"name\":\"Blade\",\"range\":0,\"attacks\":1,\"count\":1,\"ap\":0,\"rules\":[]}]";

    /// The capture twin's `CaptureReads` at `epoch` — the shroud read lives
    /// there, not on `Ctx`.
    fn aura_capture(rule: &str, faction: &str, epoch: u32) -> CaptureReads {
        let tpl = AMBUSH_FAMILY_HEADER
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
            .replace(RIFLE_ONLY, RIFLE_AND_BLADE);
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        capture_reads_for_epoch(&mut reg, p, epoch)
    }

// Per-family test modules (wave-4 layout): one file per family, so two
// family PRs in the same wave never append to the same region. A new
// family adds ONE line to this ALPHABETICAL list plus its own file; the
// fixtures every family shares stay here, in the module root.
mod aura_channel;
mod boost_aura_tail;
