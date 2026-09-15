    use super::*;

    // ------------------- MENTIONED wave 2, chunk 1: the static-stamp rows ------
    //
    // D-PROOF (14.09.): the 18 MENTIONED rows of proven_vs_read_part2.tsv
    // (chunk 1 of 4) had no core test pinning their numbers — the rows' own
    // tests asserted names or other rules' numbers (a read is not a proof).
    // The rows that resolve on the STATIC layer live here; the board-fold
    // rows (Entrenched Buff, Hold the Line Boost Buff) and the Hit & Run
    // Fighter Aura's 3-inch step live in tests/sim/mentioned2a_buffs.rs.
    // Every row is pinned by its EXACT NAME at `CURRENT_RULES_EPOCH` (= 56;
    // no epoch bump, no behaviour change): fixture + the number the rule
    // produces, plus the epoch-0/no-rule controls the red break must not move.

    /// One rule-less carrier template with a rifle AND a Blade, swappable to
    /// any (system, faction) — the fixture behind `aura_us`/`morale_of`.
    const AURA_US_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
      "carrier":{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
        "special_rules":[],"item_grants":[],
        "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]},
          {"name":"Blade","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

    /// A single-model carrier whose ONLY printed rules are `rules`, with one
    /// 24" rifle and a Blade (so the shooting/melee scoping is observable),
    /// built through the REAL `build_for` at `epoch`.
    fn carrier(system: &str, faction: &str, rules: &[&str], epoch: u32) -> UnitStatic {
        let p = Profile {
            unit_id: "carrier".into(),
            name: "Carrier".into(),
            quality: 4,
            defense: 3,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![
                crate::state::Weapon {
                    name: "Rifle".into(),
                    range: 24.0,
                    attacks: 2,
                    count: 1,
                    ap: 0,
                    rules: vec![],
                },
                crate::state::Weapon {
                    name: "Blade".into(),
                    range: 0.0,
                    attacks: 1,
                    count: 1,
                    ap: 0,
                    rules: vec![],
                },
            ],
            special_rules: rules.iter().map(|r| r.to_string()).collect(),
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: system.into(),
            faction_folder: faction.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: MoveBands::default(),
        };
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch)
    }

    /// The aura carrier for ANY (system, faction) pair — the mod.rs
    /// `aura_static` twin keeps the gf system fixed, and half of this
    /// chunk's rows resolve their entries in aof blocks. One rifle + one
    /// Blade so the shooting/melee scoping stays observable.
    fn aura_us(system: &str, faction: &str, rule: &str, epoch: u32) -> UnitStatic {
        let tpl = AURA_US_HEADER
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"));
        let header = read_act_header(&tpl).expect("aura_us header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        UnitStatic::build_for(&mut reg, p, epoch)
    }

    /// The capture-time morale read for the same carrier shape (the Banner
    /// alias fold answers through `capture_reads_for_epoch`).
    fn morale_of(system: &str, faction: &str, rule: &str, epoch: u32) -> i64 {
        let tpl = AURA_US_HEADER
            .replace("\"game_system\":\"gf\"", &format!("\"game_system\":\"{system}\""))
            .replace("\"faction_folder\":\"robot_legions\"", &format!("\"faction_folder\":\"{faction}\""))
            .replace("\"special_rules\":[]", &format!("\"special_rules\":[\"{rule}\"]"));
        let header = read_act_header(&tpl).expect("morale_of header");
        let mut reg = Registries::new(&repo_root());
        let p = header.profiles.get("carrier").expect("carrier");
        capture_reads_for_epoch(&mut reg, p, epoch).morale_bonus
    }

    /// One 64-attack volley at the DEFENDER-side carrier (the to-hit seam the
    /// Empyrean Spirit Boost's unconditional -1 rides).
    fn incoming_volley(us: &UnitStatic, dist_in: f64) -> crate::dice::ShootResult {        let profiles = [us.shoot[0].clone()];
        let att = Ctx { quality: 4, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles, keep: &[0], attacks: &[64], att: &att, owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_volley_with_tray(
            &strikers, &us.ctx, "Target", dist_in, dist_in, false, false, false, false, &mut tray,
        )
    }

    /// One 6-attack volley at the defender (the Bane save seam).
    fn bane_volley(us: &UnitStatic, dist_in: f64) -> crate::dice::ShootResult {
        let profiles = [us.shoot[0].clone()];
        let def = Ctx { quality: 4, defense: 4, tough: 1, ..Default::default() };
        let att = Ctx { quality: 4, ..Default::default() };
        let strikers = [crate::dice::Shooter {
            profiles: &profiles, keep: &[0], attacks: &[64], att: &att, owner: "att",
        }];
        let mut tray = crate::dice::Tray::seeded(27);
        crate::dice::resolve_volley_with_tray(
            &strikers, &def, "Target", dist_in, dist_in, false, false, false, false, &mut tray,
        )
    }

    // ------------------------------------------------ Angelic Blessing --------
    // The registry's 6+/spells-4+ legs at the CURRENT epoch (the merged
    // Angelic Blessing test pins them at the same read; this sibling adds
    // the no-rule control beside it).
    #[test]
    fn an_angelic_blessing_carrier_ignores_on_6_and_spells_on_4_at_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = carrier("aof", "kingdom_of_angels", &["Angelic Blessing"], e);
        assert_eq!(us.ctx.regen_target, 6, "the entry's ignore_target");
        assert_eq!(us.ctx.regen_target_spell, 4, "the entry's ignore_target_spell");
        assert!(us.ctx.regeneration);
        let none = carrier("aof", "kingdom_of_angels", &["Fearless"], e);
        assert_eq!(none.ctx.regen_target, 0, "no Regeneration-family member, no legs");
    }

    // ------------------------------------------------ Cursed Undead -----------
    #[test]
    fn a_cursed_undead_carrier_ignores_on_6_at_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = carrier("aof", "vampiric_undead", &["Cursed Undead"], e);
        assert_eq!(us.ctx.regen_target, 6, "the entry's ignore_target");
        assert_eq!(
            us.ctx.regen_target_spell, 6,
            "no spell twin: the spell pick falls back to ignore_target"
        );
    }

    // ------------------------------------------------ Bestial Boost Aura ------
    // The aura hands "Bestial Boost" to the carrier; the Boost's own widened
    // window (reroll_save_low 5, over 9") rides the Bane save seam past 9".
    #[test]
    fn a_bestial_boost_aura_widens_the_bane_window_to_5_over_nine_inches() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = carrier("aof", "beastmen", &["Bestial Boost Aura", "Bestial"], e);
        assert_eq!(us.shoot[0].bane_low, 5, "the granted Boost's reroll_save_low");
        assert_eq!(us.shoot[0].bane_over_in, 9.0, "the Boost's own over-in gate");
        assert_eq!(us.shoot[0].bane_rule, "Bestial Boost", "rules-must-log name");
        let bare = carrier("aof", "beastmen", &["Bestial"], e);
        assert_eq!(bare.shoot[0].bane_low, 0, "the base Bestial keeps the 6s-only window");
        let on = bane_volley(&us, 12.0);
        let saves = &on.rolls[1];
        assert_eq!(saves.kind, "defense", "rolls[1] is the save batch");
        let fives = saves.faces.iter().filter(|&&f| f == 5).count();
        let sixes = saves.faces.iter().filter(|&&f| f == 6).count();
        assert!(fives > 0 && sixes > 0, "this seed must land both faces or the test is blind");
        assert_eq!(on.rolls[2].count as usize, fives + sixes, "every successful 5-6 re-rolls");
    }

    // ------------------------------------------------ Bounding Aura ----------
    // The aura hands "Bounding" to the unit; the unit's own D3+1 placement
    // read is the number (place_d3_plus 1, one die).
    #[test]
    fn a_bounding_aura_places_d3_plus_one() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = aura_us("gf", "wormhole_daemons_of_change", "Bounding Aura", e);
        assert_eq!(us.bounding, Some(1.0), "the granted entry's place_d3_plus");
        let place = us.bounding_place.expect("the aura carrier places with Bounding");
        assert_eq!(place.name, "Bounding", "the granted base's own name");
        assert_eq!((place.dice, place.plus), (1, 1.0), "one die, D3+1");
        assert_eq!(aura_us("gf", "wormhole_daemons_of_change", "Fearless", e).bounding, None);
    }

    // ------------------------------------------------ Buccaneer Boost Aura ---
    // The aura hands "Buccaneer Boost" (Shot Modifier hit_bonus 1, no
    // over_in) to the carrier: flat +1 to hit at EVERY range, shooting only.
    #[test]
    fn a_buccaneer_boost_aura_adds_a_flat_plus_one_to_shooting_only() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = aura_us("aof", "sky_city_dwarves", "Buccaneer Boost Aura", e);
        assert_eq!(us.shoot[0].hit_bonus, 1, "the granted Boost's flat hit_bonus");
        assert_eq!(us.shoot[0].hit_bonus_over9, 0, "no over_in on the Boost");
        assert_eq!(us.melee[0].hit_bonus, 0, "the Shot Modifier never reaches melee");
    }

    // ------------------------------------------------ Courage Aura -----------
    // A Banner-primitive alias: the capture-time morale read.
    #[test]
    fn a_courage_aura_captures_at_plus_one_morale() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        assert_eq!(morale_of("aof", "ogres", "Courage Aura", e), 1);
        assert_eq!(morale_of("aof", "ogres", "Fearless", e), 0, "no rule, no bonus");
    }

    // ------------------------------------------------ Hive Bond --------------
    #[test]
    fn a_hive_bond_carrier_captures_at_plus_one_morale() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        assert_eq!(morale_of("gf", "alien_hives", "Hive Bond", e), 1);
        assert_eq!(morale_of("gf", "alien_hives", "Fearless", e), 0);
    }

    // ------------------------------------------------ Hold the Line ----------
    #[test]
    fn a_hold_the_line_carrier_captures_at_plus_one_morale() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        assert_eq!(morale_of("gf", "human_defense_force", "Hold the Line", e), 1);
        assert_eq!(
            morale_of("aof", "human_empire", "Hold the Line", e), 1,
            "the aof twin's own +1"
        );
        assert_eq!(morale_of("gf", "human_defense_force", "Fearless", e), 0);
    }

    // ------------------------------------------------ Destroyer Boost Aura ---
    // The aura hands "Destroyer Boost" (Shred: save_fail_max 2, over 9",
    // extra_wound_per_save_one 1): the bare Boost shreds every unmodified
    // save 1 for one extra wound; with the base Destroyer the window widens
    // to failed 2s.
    #[test]
    fn a_destroyer_boost_aura_shreds_one_extra_wound_per_save_one_and_widens_with_the_base() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let bare = carrier("aof", "ogres", &["Destroyer Boost Aura"], e);
        assert!(bare.shoot[0].shred_alias, "the granted Boost is a Shred carrier");
        assert_eq!(bare.shoot[0].shred_ones_wound_bonus, 1, "the entry's extra_wound_per_save_one");
        assert_eq!(bare.shoot[0].shred_ones_rule, "Destroyer Boost", "the rule names itself");
        assert_eq!(bare.shoot[0].shred_low, 1, "the bare Boost keeps its own 1s window");
        let full = carrier("aof", "ogres", &["Destroyer Boost Aura", "Destroyer"], e);
        assert_eq!(full.shoot[0].shred_low, 2, "the granted Boost's save_fail_max window");
        assert_eq!(full.shoot[0].shred_ones_wound_bonus, 1);
    }

    // ------------------------------------------ Empyrean Spirit Boost Aura ---
    // The aura hands "Empyrean Spirit Boost" to a carrier that also prints
    // the base: the Boost's printed unconditional -1 to hit (Evasive), with
    // the base entry's conditional alias standing down so the two never stack.
    #[test]
    fn an_empyrean_spirit_boost_aura_makes_the_minus_one_unconditional() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = carrier(
            "aof", "ghostly_undead",
            &["Empyrean Spirit Boost Aura", "Empyrean Spirit"], e,
        );
        assert!(us.ctx.evasive, "the Boost folds into evasive");
        assert_eq!(us.ctx.evasive_alias_name, "Empyrean Spirit Boost", "the fold names the rule");
        assert_eq!(us.ctx.stealth_alias_penalty, 0, "the base's conditional alias stands down");
        let shot = incoming_volley(&us, 6.0);
        assert_eq!(shot.rolls[0].target, 5, "always -1: Quality 4+ -> 5+");
        assert!(
            shot.log.iter().any(|l| l.contains("Empyrean Spirit Boost")),
            "rules-must-log"
        );
    }

    // ---------------------------------------- Grounded Reinforcement Aura ----
    // The aura hands "Grounded Reinforcement" (Shielded defense_bonus 1,
    // terrain_within_in 1): the alias kind is stamped and the +1 stays
    // terrain-pending, resolved per save moment on in_cover.
    #[test]
    fn a_grounded_reinforcement_aura_shields_its_unit_terrain_pending() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = aura_us("aof", "volcanic_dwarves", "Grounded Reinforcement Aura", e);
        assert_eq!(us.ctx.shielded_alias, ShieldedAlias::GroundedReinforcement);
        assert!(!us.ctx.shielded, "the within-1in condition is the point: held aside");
        assert_eq!(
            aura_us("aof", "volcanic_dwarves", "Fearless", e).ctx.shielded_alias,
            ShieldedAlias::None
        );
    }

    // ------------------------------------------ Grounded Protection Aura -----
    // The aura hands "Grounded Protection" (Regeneration ignore_target 5,
    // terrain_within_in 1): the target is HELD ASIDE (the EPOCH 56 pending
    // tail) — the spell twin repeats the normal target, the save-moment
    // verdict resolves both.
    #[test]
    fn a_grounded_protection_aura_holds_its_5_plus_aside_for_the_terrain_verdict() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = aura_us("aof", "volcanic_dwarves", "Grounded Protection Aura", e);
        assert_eq!(us.ctx.regen_pending, 5, "the entry's ignore_target, held aside");
        assert_eq!(us.ctx.regen_pending_spell, 5, "no spell twin: the normal target repeats");
        assert_eq!(us.ctx.regen_target, 0, "never folded flat past the within-1in condition");
        assert_eq!(aura_us("aof", "volcanic_dwarves", "Fearless", e).ctx.regen_pending, 0);
    }

    // ------------------------------------------ Hit & Run Fighter Aura -------
    // The aura hands "Hit & Run Fighter" to the carrier: the FIGHTER half's
    // own flag fires on the melee leg (the 3-inch band itself is pinned on
    // the board fold in tests/sim/mentioned2a_buffs.rs).
    #[test]
    fn a_hit_and_run_fighter_aura_grants_the_fighter_half_at_current_epoch() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = aura_us("gf", "wormhole_daemons_of_lust", "Hit & Run Fighter Aura", e);
        assert!(us.hit_and_run_fighter_active, "the granted Fighter's own flag");
        assert!(
            !aura_us("gf", "wormhole_daemons_of_lust", "Hit & Run Fighter Aura", 5)
                .hit_and_run_fighter_active,
            "epoch 5: the gate is off"
        );
        assert!(!aura_us("gf", "wormhole_daemons_of_lust", "Fearless", e).hit_and_run_fighter_active);
    }

    // ------------------------------------------ Increased Shooting Range Aura
    // The aof spelling is a Royal Legion-primitive alias of its own: +6in
    // shooting range, charge untouched (charge_mod 0).
    #[test]
    fn an_increased_shooting_range_aura_adds_six_inches_of_range_and_no_charge() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        assert_eq!(royal_legion_halves("isr_aura_unit", e), (6.0, 0.0));
        assert_eq!(royal_legion_halves("isr_aura_unit", 0), (0.0, 0.0), "epoch 0 replays legacy");
        assert_eq!(
            royal_legion_halves("isr_unit", e),
            (6.0, 0.0),
            "the gf spelling's base carries the same +6in"
        );
    }

    // ------------------------------------------ Indirect when Shooting Aura --
    // The aura hands "Indirect when Shooting" to the carrier: the volley
    // folds -1 after a move (the granted base's moved_hit_penalty), with the
    // wave-3 alias marker naming the rule in the volley log.
    #[test]
    fn an_indirect_when_shooting_aura_stamps_the_moved_penalty_at_minus_one() {
        let e = crate::acts::CURRENT_RULES_EPOCH;
        let us = aura_us("gf", "wormhole_daemons_of_change", "Indirect when Shooting Aura", e);
        assert!(us.shoot[0].indirect, "the granted base stamps the indirect flag");
        assert!(us.shoot[0].indirect_alias, "the wave-3 alias marker rides the flag");
        assert_eq!(us.shoot[0].indirect_moved_hit_penalty, 1, "the entry's moved_hit_penalty");
        let none = aura_us("gf", "wormhole_daemons_of_change", "Fearless", e);
        assert!(!none.shoot[0].indirect);
        assert_eq!(none.shoot[0].indirect_moved_hit_penalty, 0);
    }
