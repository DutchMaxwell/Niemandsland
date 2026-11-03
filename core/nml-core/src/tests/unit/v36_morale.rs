//! Rules 3.6 lane morale tests for the unit module; owned by lane morale.

// --- Row MOR-12: Sergeant / Great Sergeant strike with AP instead of extra hits.
mod mor_12 {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

    /// One Great Sergeant bearer (aof/ogres, the folder the book prints) with a rifle and a
    /// blade, so both facets are observable, built through the REAL registry at `epoch`.
    fn great_sergeant(rules: &str, epoch: u32) -> UnitStatic {
        let header = format!(
            r#"{{"kind":"header","knobs":{{}},"profiles":{{"gs":{{"unit_id":"gs","name":"Bearer",
            "quality":4,"defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
            "base_radius":0.016,"game_system":"aof","faction_folder":"ogres","special_rules":[{rules}],
            "item_grants":[],"attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
            "weapons":[{{"name":"Rifle","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}},
            {{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
        );
        let hdr = read_act_header(&header).expect("header parses");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, hdr.profiles.get("gs").expect("gs"), epoch)
    }

    fn reports(us: &UnitStatic, rule: &str) -> usize {
        us.unimplemented.iter().filter(|u| u.rule == rule).count()
    }

    /// Rules 3.6: Great Sergeant's 5-6 extra-hit window is gone; the bearer strikes at AP(+2)
    /// instead, so the static stamp names the rule and its bonus instead of reporting it.
    #[test]
    fn a_great_sergeant_leaves_the_surge_window_and_strikes_at_ap_plus_2_at_epoch_73() {
        let us = great_sergeant("\"Great Sergeant\"", EPOCH_73_V36);
        assert!(!us.shoot[0].surge, "no extra hits when shooting from 73");
        assert!(!us.melee[0].surge, "no extra hits in melee from 73");
        assert_eq!(us.shoot[0].surge_low, 6, "no 5-6 window from 73");
        assert_eq!(reports(&us, "Great Sergeant"), 0, "the core plays the rule from 73");
        assert_eq!(us.shoot[0].sergeant_ap, 2, "Great Sergeant strikes at AP(+2)");
        assert_eq!(us.melee[0].sergeant_rule, "Great Sergeant");
    }

    /// The rules 3.5 leg: every game recorded at 72 replays the 5-6 window, no report.
    #[test]
    fn a_great_sergeant_keeps_its_surge_window_at_epoch_72() {
        let us = great_sergeant("\"Great Sergeant\"", EPOCH_72_PLAYTEST_RULES);
        assert!(us.shoot[0].surge, "the facet replays at 72");
        assert_eq!(us.shoot[0].surge_low, 5, "the printed 5-6 replays at 72");
        assert_eq!(reports(&us, "Great Sergeant"), 0, "no report at 72");
    }

    /// Sergeant keeps its report below the gate; from 73 the static names its AP(+1) instead.
    #[test]
    fn a_sergeant_reports_its_gap_at_epoch_72_and_strikes_at_ap_plus_1_at_epoch_73() {
        let old = great_sergeant("\"Sergeant\"", EPOCH_72_PLAYTEST_RULES);
        assert_eq!(reports(&old, "Sergeant"), 1, "epoch 72: one report, by the exact name");
        assert_eq!(old.melee[0].sergeant_attacks, 0, "the share is never guessed");
        assert_eq!(old.melee[0].sergeant_ap, 0, "no AP share below the gate");
        let live = great_sergeant("\"Sergeant\"", EPOCH_73_V36);
        assert_eq!(reports(&live, "Sergeant"), 0, "the core plays the rule from 73");
        assert_eq!(live.shoot[0].sergeant_ap, 1, "Sergeant strikes at AP(+1)");
        assert_eq!(live.melee[0].sergeant_ap, 1, "the melee set carries the same bonus");
        for e in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
            assert_eq!(reports(&great_sergeant("", e), "Sergeant"), 0, "epoch {e}: no rule, no report");
        }
    }
}

use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// Row MOR-02 (ruling D-MOST): a squad of `models` models carrying `special` (a JSON list) with
/// the joined heroes `heroes` (a JSON list of rule lists), built at `epoch` for (gf, `faction`).
/// Answers the stamped Regeneration-family read: (rolls at all, the ignore target).
fn regen_of(faction: &str, special: &str, heroes: &str, models: i64, epoch: u32) -> (bool, i64) {
    let tpl = r#"{"kind":"header","knobs":{},"profiles":{
      "rg":{"unit_id":"rg","name":"Regen Squad","quality":4,
        "defense":4,"tough":1,"wounds_max":WOUNDS,"model_count":MODELS,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"FACTION",
        "special_rules":SPECIAL,"item_grants":[],
        "attached_hero_rules":HEROES,"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#
        .replace("WOUNDS", &format!("{:?}", vec![1; models as usize]))
        .replace("MODELS", &models.to_string())
        .replace("FACTION", faction)
        .replace("SPECIAL", special)
        .replace("HEROES", heroes);
    let header = read_act_header(&tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    let us = UnitStatic::build_for(&mut reg, header.profiles.get("rg").expect("rg"), epoch);
    (us.ctx.regeneration, us.ctx.regen_target)
}

const PLAIN_HERO: &str = r#"[["Hero"]]"#;

/// Self-Repair and the "most models" family names (Plaguebound here) hold for a three-model
/// squad whose joined hero lacks them; a Boost off that list still needs every model, so the
/// Plaguebound squad keeps 6+ instead of the Boost's 5+.
#[test]
fn self_repair_and_plaguebound_roll_with_a_joined_hero_without_them_at_epoch_73() {
    let sr = regen_of("robot_legions", r#"["Self-Repair"]"#, PLAIN_HERO, 3, EPOCH_73_V36);
    assert_eq!(sr, (true, 6), "Self-Repair: 3 of 4 models carry it");
    let pb = regen_of("plague_disciples", r#"["Plaguebound","Plaguebound Boost"]"#, PLAIN_HERO, 3, EPOCH_73_V36);
    assert_eq!(pb, (true, 6), "Plaguebound holds on most models; its Boost still needs all of them");
}

/// Control: below the 3.6 epoch a joined hero without the rule still switches it off.
#[test]
fn self_repair_and_plaguebound_need_every_model_at_epoch_72() {
    let sr = regen_of("robot_legions", r#"["Self-Repair"]"#, PLAIN_HERO, 3, EPOCH_72_PLAYTEST_RULES);
    assert!(!sr.0, "Self-Repair at 72: the hero withholds it");
    let pb = regen_of("plague_disciples", r#"["Plaguebound","Plaguebound Boost"]"#, PLAIN_HERO, 3, EPOCH_72_PLAYTEST_RULES);
    assert!(!pb.0, "Plaguebound at 72: the hero withholds it");
}

/// One Regeneration model plus a joined hero without it is an exact half: no roll.
#[test]
fn a_regeneration_tie_with_a_joined_hero_is_off_at_epoch_73() {
    assert!(!regen_of("robot_legions", r#"["Regeneration"]"#, PLAIN_HERO, 1, EPOCH_73_V36).0);
}

/// Control: below the 3.6 epoch the core reads the host's own Regeneration alone.
#[test]
fn a_regeneration_tie_with_a_joined_hero_rolls_at_epoch_72() {
    assert_eq!(regen_of("robot_legions", r#"["Regeneration"]"#, PLAIN_HERO, 1, EPOCH_72_PLAYTEST_RULES), (true, 5));
}

/// Regeneration on most models keeps its roll; a Regeneration hero in a plain squad of three is
/// one model of four, so it gives the squad none (the core never read the hero; the table did).
#[test]
fn regeneration_counts_most_models_at_epoch_73() {
    assert_eq!(regen_of("robot_legions", r#"["Regeneration"]"#, PLAIN_HERO, 3, EPOCH_73_V36), (true, 5));
    let hero_only = regen_of("robot_legions", "[]", r#"[["Hero","Regeneration"]]"#, 3, EPOCH_73_V36);
    assert!(!hero_only.0, "1 of 4 models carry Regeneration");
}

// --- Row MOR-17a: Warding, Knightborn and Angelic Blessing carry the 3.6 distance gate.
mod mor_17a {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

    /// A gf knight_brothers squad built through the REAL registry at `epoch`.
    fn knight_ctx(special: &str, grants: &str, epoch: u32) -> Ctx {
        let tpl = r#"{"kind":"header","knobs":{},"profiles":{
          "kb":{"unit_id":"kb","name":"Knightborn Squad","quality":4,
            "defense":4,"tough":1,"wounds_max":[1,1,1,1],"model_count":4,"caster_value":0,
            "base_radius":0.016,"game_system":"gf","faction_folder":"knight_brothers",
            "special_rules":SPECIAL,"item_grants":GRANTS,
            "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
            "weapons":[{"name":"Claws","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#
            .replace("SPECIAL", special)
            .replace("GRANTS", grants);
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, header.profiles.get("kb").expect("kb"), epoch).ctx
    }

    #[test]
    fn knightborn_stamps_the_36_gate_and_spell_leg_at_epoch_73() {
        let ctx = knight_ctx(r#"["Knightborn"]"#, "[]", EPOCH_73_V36);
        assert!(ctx.regeneration);
        assert_eq!(ctx.regen_target, 6, "the entry's ignore_target");
        assert_eq!(ctx.regen_target_spell, 2, "the 3.6 spell leg");
        assert_eq!(ctx.regen_gate_over_in, 9.0, "shot from over 9in");
        assert_eq!(ctx.regen_gate_charge_in, 6.0, "charged from over 6in");
    }

    #[test]
    fn knightborn_keeps_the_35_entry_at_epoch_72() {
        let ctx = knight_ctx(r#"["Knightborn"]"#, "[]", EPOCH_72_PLAYTEST_RULES);
        assert_eq!((ctx.regen_target, ctx.regen_target_spell), (6, 4), "old keys keep the 3.5 meaning");
        assert_eq!((ctx.regen_gate_over_in, ctx.regen_gate_charge_in), (0.0, 0.0), "no gate below 73");
    }

    #[test]
    fn enhanced_knightborn_stamps_no_gate_at_epoch_73() {
        let ctx = knight_ctx(r#"["Enhanced Knightborn"]"#, "[]", EPOCH_73_V36);
        assert!(ctx.regeneration);
        assert_eq!((ctx.regen_target, ctx.regen_target_spell), (6, 2));
        assert_eq!((ctx.regen_gate_over_in, ctx.regen_gate_charge_in), (0.0, 0.0), "the grant has no gate");
    }

    #[test]
    fn enhanced_knightborn_does_nothing_new_at_epoch_72() {
        let ctx = knight_ctx(r#"["Enhanced Knightborn"]"#, "[]", EPOCH_72_PLAYTEST_RULES);
        assert_eq!((ctx.regen_target, ctx.regen_target_spell), (6, 4), "old keys keep the 3.5 meaning");
        assert_eq!((ctx.regen_gate_over_in, ctx.regen_gate_charge_in), (0.0, 0.0));
    }
}

// --- Row MOR-SPELLFACET-a: spell facets read the 3.6 weapon-rule names at epoch 73.
mod mor_spellfacet_a {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::rules::{Registries, Spell};
    use crate::spell::{spell_damage_ev_of, spell_facets};
    use crate::unit::Ctx;

    /// One spell entry the LIVE registry really carries, built through
    /// `spells_for` — the token list under test is the committed map's own.
    fn live_spell(system: &str, faction: &str, name: &str) -> Spell {
        let mut reg = Registries::new(&repo_root());
        reg.spells_for(system, faction)
            .iter()
            .find(|s| s.name == name)
            .cloned()
            .unwrap_or_else(|| panic!("{system}/{faction} carries no {name}"))
    }

    fn plain_tough(tough: i64) -> Ctx {
        Ctx { defense: 4, tough, models: 1, ..Default::default() }
    }

    /// The table at EPOCH_73_V36: Fracture is the old Crack, Puncture the old
    /// Disintegrate, Disintegrate now the Tough(3)+ AP fold and Shatter the
    /// sixes' AP(+3).
    #[test]
    fn the_four_tokens_read_the_36_facets_at_epoch_73() {
        let fracture = spell_facets(&live_spell("aof", "high_elves", "Magic Arrows").weapon_rules, EPOCH_73_V36);
        assert_eq!(
            (fracture.on6_ap, fracture.ignores_regen, fracture.ap_vs_def3, fracture.ap_vs_tough3),
            (2, false, 0, 0),
            "Fracture = the old Crack"
        );

        let puncture = spell_facets(
            &live_spell("aof", "duchies_of_vinci", "Explosive Concoction").weapon_rules,
            EPOCH_73_V36,
        );
        assert_eq!(
            (puncture.on6_ap, puncture.ignores_regen, puncture.ap_vs_def3, puncture.ap_vs_tough3),
            (0, true, 2, 0),
            "Puncture = the old Disintegrate"
        );

        let disintegrate = spell_facets(&live_spell("aof", "beastmen", "Ancestral Wrath").weapon_rules, EPOCH_73_V36);
        assert_eq!(
            (disintegrate.on6_ap, disintegrate.ignores_regen, disintegrate.ap_vs_def3, disintegrate.ap_vs_tough3),
            (0, true, 0, 2),
            "Disintegrate: regen bypass + AP(+2) vs Tough(3)+, never ap_vs_def3"
        );

        let shatter = spell_facets(
            &live_spell("aof", "kingdom_of_angels", "Lightning Bolt").weapon_rules,
            EPOCH_73_V36,
        );
        assert_eq!(
            (shatter.on6_ap, shatter.ap_vs_tough3),
            (3, 0),
            "Shatter: sixes get AP(+3), never ap_vs_tough3"
        );
    }

    /// Pattern 12 — below 73 all four keep the 3.5 readings byte-identical.
    #[test]
    fn the_four_tokens_keep_their_35_readings_at_epoch_72() {
        let fracture = spell_facets(&live_spell("aof", "high_elves", "Magic Arrows").weapon_rules, EPOCH_72_PLAYTEST_RULES);
        assert_eq!((fracture.on6_ap, fracture.ignores_regen), (0, false), "Fracture was unknown");

        let puncture = spell_facets(
            &live_spell("aof", "duchies_of_vinci", "Explosive Concoction").weapon_rules,
            EPOCH_72_PLAYTEST_RULES,
        );
        assert_eq!(
            (puncture.on6_ap, puncture.ignores_regen, puncture.ap_vs_def3, puncture.ap_vs_tough3),
            (0, false, 0, 0),
            "Puncture was unknown"
        );

        let disintegrate = spell_facets(&live_spell("aof", "beastmen", "Ancestral Wrath").weapon_rules, EPOCH_72_PLAYTEST_RULES);
        assert_eq!(
            (disintegrate.on6_ap, disintegrate.ignores_regen, disintegrate.ap_vs_def3, disintegrate.ap_vs_tough3),
            (0, true, 2, 0),
            "the 3.5 Disintegrate ticket"
        );

        let shatter = spell_facets(
            &live_spell("aof", "kingdom_of_angels", "Lightning Bolt").weapon_rules,
            EPOCH_72_PLAYTEST_RULES,
        );
        assert_eq!(
            (shatter.on6_ap, shatter.ap_vs_tough3),
            (0, 2),
            "the 3.5 Shatter ticket"
        );
    }

    /// Shatter at 73 upgrades the trigger-roll sixes, so a 6-hit spell prices
    /// above its own 3.5 EV.
    #[test]
    fn shatter_raises_the_six_hit_ev_at_epoch_73() {
        let spell = live_spell("aof", "kingdom_of_angels", "Lightning Bolt");
        let def = plain_tough(1);
        let now = spell_damage_ev_of(&spell, &def, EPOCH_73_V36);
        let before = spell_damage_ev_of(&spell, &def, EPOCH_72_PLAYTEST_RULES);
        assert!(now > before + 1e-9, "AP(+3) on the sixes must raise the EV: {now} vs {before}");
    }

    /// Disintegrate at 73 pays AP(+2) against Tough(3)+ only, and still
    /// bypasses Regeneration.
    #[test]
    fn disintegrate_adds_ap_two_only_against_tough_three_at_epoch_73() {
        let spell = live_spell("aof", "beastmen", "Ancestral Wrath");
        let tough3 = plain_tough(3);
        let tough2 = plain_tough(2);
        assert!(
            spell_damage_ev_of(&spell, &tough3, EPOCH_73_V36) > spell_damage_ev_of(&spell, &tough3, EPOCH_72_PLAYTEST_RULES) + 1e-9,
            "Tough(3)+ pays the new AP(+2)"
        );
        assert!(
            (spell_damage_ev_of(&spell, &tough2, EPOCH_73_V36)
                - spell_damage_ev_of(&spell, &tough2, EPOCH_72_PLAYTEST_RULES))
            .abs()
                < 1e-9,
            "Tough(2) pays nothing new"
        );

        let regen = Ctx {
            defense: 4,
            tough: 3,
            models: 1,
            regeneration: true,
            regen_target: 5,
            regen_target_spell: 5,
            ..Default::default()
        };
        assert!(
            (spell_damage_ev_of(&spell, &regen, EPOCH_73_V36) - spell_damage_ev_of(&spell, &tough3, EPOCH_73_V36)).abs() < 1e-9,
            "Disintegrate still bypasses Regeneration at 73"
        );
    }
}

// --- Row MOR-15: a WEAPON-borne "Spell Amplifier" adds +1 to the bearer's own casting rolls.
mod mor_15 {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::rules::{Spell, SpellModifier};
    use crate::sim::cast_phase;
    use crate::sim::tests::four_unit_line;
    use crate::{Seams, State, IN2M};

    /// One 12" damage bolt, threshold 1 — the fixture's castable spell.
    fn bolt() -> Spell {
        Spell {
            name: "bolt".into(),
            status: "modeled".into(),
            threshold: 1,
            range_in: 12.0,
            target_count: 1,
            effect_kind: "damage".into(),
            effect_hits: 3,
            weapon_rules: vec![],
            beneficiary: String::new(),
            modifier: SpellModifier::default(),
            grants_rule: String::new(),
            needs_los: false,
        }
    }

    /// The REAL registry product (`build_for`): a quality-2 caster whose
    /// weapon list carries `weapon_rules` (or not). `special` is the
    /// `special_rules` list — the "wrong spelling" control.
    fn caster(
        weapon_rules: &str,
        special: &str,
        system: &str,
        faction: &str,
        epoch: u32,
    ) -> UnitStatic {
        let tpl = r#"{"kind":"header","knobs":{},"profiles":{
          "c":{"unit_id":"c","name":"Caster","quality":2,"defense":4,"tough":1,
            "wounds_max":[1],"model_count":1,"caster_value":1,
            "base_radius":0.016,"game_system":"SYSTEM","faction_folder":"FACTION",
            "special_rules":SPECIAL,"item_grants":[],
            "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
            "weapons":[{"name":"Rod","range":12,"attacks":1,"count":1,"ap":0,
              "rules":WEAPONS}]}}}"#
            .replace("SYSTEM", system)
            .replace("FACTION", faction)
            .replace("SPECIAL", special)
            .replace("WEAPONS", weapon_rules);
        let header = read_act_header(&tpl).expect("header");
        let mut reg = Registries::new(&repo_root());
        UnitStatic::build_for(&mut reg, header.profiles.get("c").expect("c"), epoch)
    }

    /// One cast sub-phase: unit 0 casts the bolt at the enemy (unit 2) 10"
    /// away. The caster's static comes from `build_for`; only the spell list
    /// and the `is_caster` flag are supplied by the fixture.
    fn run(caster: UnitStatic, epoch: u32) -> State {
        run_tokens(caster, epoch, 1)
    }

    /// The same attempt with `own` casting tokens in the purse (`run`'s
    /// threshold-1 bolt leaves no boost room at one token).
    fn run_tokens(mut caster: UnitStatic, epoch: u32, own: i64) -> State {
        caster.is_caster = true;
        caster.spells = vec![bolt()];
        let mut st = four_unit_line();
        st.casts = vec![own, 0, 0, 0];
        st.positions[2] = vec![[10.0 * IN2M, 0.0, 0.0]];
        let statics = vec![caster];
        let mut next = st.clone();
        let los = vec![true; st.units()];
        cast_phase(
            &statics,
            &mut next,
            0,
            &los,
            Seams { rules_epoch: epoch, ..Seams::default() },
            None,
        );
        next
    }

    /// The planned cast chance (the attempt event's `p_success`).
    fn p_success(s: &State) -> f64 {
        s.cast_events
            .iter()
            .find(|e| e.get("spell").is_some())
            .expect("one cast attempt")["p_success"]
            .as_f64()
            .expect("p_success")
    }

    /// The planned boost token count (the attempt event's `boost`).
    fn planned_boost(s: &State) -> i64 {
        s.cast_events
            .iter()
            .find(|e| e.get("spell").is_some())
            .expect("one cast attempt")["boost"]
            .as_i64()
            .expect("boost")
    }

    #[test]
    fn a_weapon_borne_amplifier_lowers_the_bearers_cast_target_at_epoch_73() {
        let caster = caster(
            r#"["Spell Amplifier"]"#,
            r#"["Caster(1)"]"#,
            "gf",
            "blessed_sisters",
            EPOCH_73_V36,
        );
        assert_eq!(
            caster.spell_amplifier_casting_mod, 1,
            "the weapon-borne stamp reads casting_mod"
        );
        let next = run(caster, EPOCH_73_V36);
        assert!(
            (p_success(&next) - 2.0 / 3.0).abs() < 1e-9,
            "4+ becomes 3+, got {}",
            p_success(&next)
        );
    }

    #[test]
    fn a_caster_without_the_rule_stays_at_four_plus_at_epoch_73() {
        let caster = caster("[]", r#"["Caster(1)"]"#, "gf", "blessed_sisters", EPOCH_73_V36);
        assert_eq!(caster.spell_amplifier_casting_mod, 0);
        let next = run(caster, EPOCH_73_V36);
        assert!((p_success(&next) - 0.5).abs() < 1e-9, "plain caster stays at 4+");
    }

    #[test]
    fn the_amplifier_does_nothing_at_epoch_72() {
        let caster = caster(
            r#"["Spell Amplifier"]"#,
            r#"["Caster(1)"]"#,
            "gf",
            "blessed_sisters",
            EPOCH_72_PLAYTEST_RULES,
        );
        assert_eq!(caster.spell_amplifier_casting_mod, 0, "the gate is EPOCH_73_V36");
        let next = run(caster, EPOCH_72_PLAYTEST_RULES);
        assert!((p_success(&next) - 0.5).abs() < 1e-9, "the old 4+ replays byte-exact");
    }

    #[test]
    fn a_special_rule_spelling_does_nothing_at_epoch_73() {
        let caster = caster(
            "[]",
            r#"["Caster(1)","Spell Amplifier"]"#,
            "gf",
            "blessed_sisters",
            EPOCH_73_V36,
        );
        assert_eq!(
            caster.spell_amplifier_casting_mod, 0,
            "the row is weapon-borne only"
        );
        let next = run(caster, EPOCH_73_V36);
        assert!((p_success(&next) - 0.5).abs() < 1e-9, "special_rules never grant it");
    }

    #[test]
    fn both_system_maps_carry_the_amplifier_entry() {
        let mut reg = Registries::new(&repo_root());
        let gf = reg
            .rules_for("gf")
            .lookup("blessed_sisters", "Spell Amplifier")
            .expect("gf entry");
        assert_eq!(gf.param_i("casting_mod", 0), 1);
        let aof = reg
            .rules_for("aof")
            .lookup("ogres", "Spell Amplifier")
            .expect("aof entry");
        assert_eq!(aof.param_i("casting_mod", 0), 1);
    }

    #[test]
    fn an_aof_caster_stamps_the_same_amplifier() {
        let caster = caster(
            r#"["Spell Amplifier"]"#,
            r#"["Caster(1)"]"#,
            "aof",
            "ogres",
            EPOCH_73_V36,
        );
        assert_eq!(
            caster.spell_amplifier_casting_mod, 1,
            "the aof map resolves the same entry"
        );
        let next = run(caster, EPOCH_73_V36);
        assert!(
            (p_success(&next) - 2.0 / 3.0).abs() < 1e-9,
            "the aof map resolves the same entry"
        );
    }

    /// Pre-review FLAG — the CORE planner must price the same fold the ROLL
    /// uses. At 73 an amplifier carrier (target 3+) already has fewer steps
    /// left, so it buys strictly FEWER boost tokens than the same caster
    /// without the rule (target 4+, the coin-flip clause buys two).
    #[test]
    fn an_amplifier_caster_buys_fewer_boost_tokens_at_epoch_73() {
        let plain = caster(
            "[]",
            r#"["Caster(1)"]"#,
            "gf",
            "blessed_sisters",
            EPOCH_73_V36,
        );
        let amplified = caster(
            r#"["Spell Amplifier"]"#,
            r#"["Caster(1)"]"#,
            "gf",
            "blessed_sisters",
            EPOCH_73_V36,
        );
        let plain = run_tokens(plain, EPOCH_73_V36, 6);
        let amplified = run_tokens(amplified, EPOCH_73_V36, 6);
        assert_eq!(planned_boost(&plain), 2, "the blind 4+ read buys two tokens");
        assert!(
            planned_boost(&amplified) < planned_boost(&plain),
            "priced at the roll's 3+ it must buy fewer, got {}",
            planned_boost(&amplified)
        );
        assert_eq!(
            planned_boost(&amplified),
            1,
            "3+ leaves one step, and the 2+ clamp ends the spend"
        );
    }

    /// Pre-review FLAG — below 73 the plan stays BLIND (net 0), so the old
    /// boost count is byte-exact even for a carrier whose stamp is gated off.
    #[test]
    fn the_epoch_72_boost_plan_stays_blind() {
        let plain = caster(
            "[]",
            r#"["Caster(1)"]"#,
            "gf",
            "blessed_sisters",
            EPOCH_72_PLAYTEST_RULES,
        );
        let amplified = caster(
            r#"["Spell Amplifier"]"#,
            r#"["Caster(1)"]"#,
            "gf",
            "blessed_sisters",
            EPOCH_72_PLAYTEST_RULES,
        );
        let plain = run_tokens(plain, EPOCH_72_PLAYTEST_RULES, 6);
        let amplified = run_tokens(amplified, EPOCH_72_PLAYTEST_RULES, 6);
        assert_eq!(planned_boost(&plain), 2, "the old blind count");
        assert_eq!(
            planned_boost(&amplified),
            planned_boost(&plain),
            "below 73 the pricing argument stays 0"
        );
    }
}
// --- Row MOR-SPELLFACET-b: Destructive prices AP(+1) against an above-half defender at 73.
mod mor_spellfacet_b {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::rules::{Registries, Spell};
    use crate::spell::{spell_damage_ev_of, spell_facets};
    use crate::unit::Ctx;

    /// One spell entry the LIVE registry really carries, built through
    /// `spells_for` — the token list under test is the committed map's own.
    fn live_spell(system: &str, faction: &str, name: &str) -> Spell {
        let mut reg = Registries::new(&repo_root());
        reg.spells_for(system, faction)
            .iter()
            .find(|s| s.name == name)
            .cloned()
            .unwrap_or_else(|| panic!("{system}/{faction} carries no {name}"))
    }

    fn defender(above_half_strength: bool) -> Ctx {
        Ctx { defense: 4, tough: 1, models: 5, above_half_strength, ..Default::default() }
    }

    /// The 3.6 meaning: the token no longer upgrades the sixes; it adds AP(+1)
    /// only against a defender still above half. Six hits into Defense 4 are
    /// 6 × 2/3 = 4 above half and 6 × 1/2 = 3 at or below it.
    #[test]
    fn destructive_prices_ap_one_only_against_an_above_half_defender_at_epoch_73() {
        let spell = live_spell("gf", "elven_jesters", "Light Fragments");
        let f = spell_facets(&spell.weapon_rules, EPOCH_73_V36);
        assert_eq!(f.on6_ap, 0, "the 3.5 AP(+4) on the sixes is gone from 73");
        assert_eq!(f.ap_vs_above_half, 1, "the token prices AP(+1) against the state");

        let above = spell_damage_ev_of(&spell, &defender(true), EPOCH_73_V36);
        let below = spell_damage_ev_of(&spell, &defender(false), EPOCH_73_V36);
        assert!((above - 4.0).abs() < 1e-9, "above half pays AP(+1): {above}");
        assert!((below - 3.0).abs() < 1e-9, "below half pays nothing: {below}");
    }

    /// A plain damage spell reads the same in both defender states at 73 and
    /// exactly its 3.5 number at 72.
    #[test]
    fn a_plain_spell_is_unchanged_in_both_states() {
        let spell = live_spell("gf", "elven_jesters", "Fatal Sorrow");
        for above in [true, false] {
            let now = spell_damage_ev_of(&spell, &defender(above), EPOCH_73_V36);
            let before = spell_damage_ev_of(&spell, &defender(above), EPOCH_72_PLAYTEST_RULES);
            assert!((now - 3.0).abs() < 1e-9, "six plain hits into Defense 4: {now}");
            assert!((now - before).abs() < 1e-9, "no epoch change for a plain spell");
        }
    }

    /// Pattern 12 — below 73 the old AP(+4)-on-six ticket and its EV come back,
    /// byte-identical in both defender states.
    #[test]
    fn destructive_keeps_the_35_on6_ap_at_epoch_72() {
        let spell = live_spell("gf", "elven_jesters", "Light Fragments");
        let f = spell_facets(&spell.weapon_rules, EPOCH_72_PLAYTEST_RULES);
        assert_eq!((f.on6_ap, f.ap_vs_above_half), (4, 0), "the 3.5 on-6 ticket");

        let old = 5.0 * 0.5 + 1.0 * (5.0 / 6.0);
        for above in [true, false] {
            let ev = spell_damage_ev_of(&spell, &defender(above), EPOCH_72_PLAYTEST_RULES);
            assert!((ev - old).abs() < 1e-9, "the 3.5 EV replays: {ev} vs {old}");
        }
    }
}

/// Row MOR-09: "Valiant" resolves as the Banner primitive; at Epoch 73 the
/// Banner share counts only over the 9" shot / 6" charge gate. Built through
/// the REAL registry so the stamp and the gate are the live ones.
mod mor_09 {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::dice::{ShootResult, Tray};
    use crate::io::Seams;
    use crate::sim::tray_morale_for;
    use crate::state::Profile;
    use crate::unit::{capture_reads_for_epoch, UnitStatic};

    fn banner_profile(rule: &str, faction: &str) -> Profile {
        Profile {
            cost: 0,
            unit_id: "b".into(),
            name: "b".into(),
            quality: 4,
            defense: 4,
            tough: 1,
            wounds_max: vec![1],
            model_count: 1,
            weapons: vec![],
            special_rules: vec![rule.into()],
            caster_value: 0,
            base_radius: 0.0,
            base_shape: String::new(),
            base_w_mm: 0.0,
            base_d_mm: 0.0,
            game_system: "gf".into(),
            faction_folder: faction.into(),
            item_grants: vec![],
            attached_hero_rules: vec![],
            move_bands: crate::state::MoveBands::default(),
        }
    }

    fn seed_rolling_a_three() -> i64 {
        (0..500).find(|&s| Tray::seeded(s).roll(1)[0] == 3).expect("some seed rolls a 3")
    }

    fn run_profile(p: &Profile, melee: bool, over_in: Option<f64>, charge_from_in: Option<f64>, epoch: u32) -> (i64, bool) {
        let mut reg = Registries::new(&repo_root());
        let us = UnitStatic::build_for(&mut reg, p, epoch);
        let reads = capture_reads_for_epoch(&mut reg, p, epoch);
        let mut st = crate::sim::tests::four_unit_line();
        st.morale_bonus[2] = reads.morale_bonus;
        let statics = vec![us; 4];
        let mut tray = Tray::seeded(seed_rolling_a_three());
        let mut shot = ShootResult::default();
        let seams = Seams { rules_epoch: epoch, ..Seams::default() };
        tray_morale_for(&mut st, &statics, 2, melee, None, seams, &mut tray, &mut shot, over_in, charge_from_in);
        let die = shot.rolls.iter().find(|r| r.count == 1).expect("the morale die is drawn");
        (die.target, st.shaken[2])
    }

    fn run_banner(rule: &str, faction: &str, melee: bool, over_in: Option<f64>, charge_from_in: Option<f64>, epoch: u32) -> (i64, bool) {
        run_profile(&banner_profile(rule, faction), melee, over_in, charge_from_in, epoch)
    }

    #[test]
    fn valiant_resolves_through_the_registry_like_hold_the_line() {
        let p = banner_profile("Valiant", "human_defense_force");
        let mut reg = Registries::new(&repo_root());
        assert_eq!(capture_reads_for_epoch(&mut reg, &p, EPOCH_73_V36).morale_bonus, 1);
    }

    #[test]
    fn old_banner_names_drop_inside_the_shot_gate_at_epoch_73() {
        for (rule, faction) in [("Hold the Line", "human_defense_force"), ("Hive Bond", "alien_hives")] {
            let (target, _) = run_banner(rule, faction, false, Some(4.0), None, EPOCH_73_V36);
            assert_eq!(target, 4, "{rule} inside 9\": no Banner +1");
        }
    }

    #[test]
    fn valiant_gate_covers_shots_and_charges_at_epoch_73() {
        for (melee, over, charge, expected) in [
            (false, Some(4.0), None, 4),
            (false, Some(10.0), None, 3),
            (true, None, Some(4.0), 4),
            (true, None, Some(8.0), 3),
        ] {
            let (target, _) = run_banner("Valiant", "human_defense_force", melee, over, charge, EPOCH_73_V36);
            assert_eq!(target, expected, "melee={melee} over={over:?} charge={charge:?}");
        }
    }

    #[test]
    fn old_banner_names_keep_the_bonus_at_epoch_72() {
        let (target, _) = run_banner("Hold the Line", "human_defense_force", false, Some(4.0), None, EPOCH_72_PLAYTEST_RULES);
        assert_eq!(target, 3, "epoch 72: the unconditional reading stays");
    }

    #[test]
    fn valiant_without_distance_keeps_the_bonus_at_epoch_73() {
        let (target, _) = run_banner("Valiant", "human_defense_force", false, None, None, EPOCH_73_V36);
        assert_eq!(target, 3, "no distance supplied: keep the 3.5 reading");
    }

    #[test]
    fn banner_at_five_keeps_the_bonus_at_epoch_73() {
        let (target, _) = run_banner("Banner", "human_defense_force", false, Some(5.0), None, EPOCH_73_V36);
        assert_eq!(target, 3, "plain Banner keeps its +1 inside the band");
    }

    #[test]
    fn valiant_at_five_loses_and_at_ten_keeps_the_bonus_at_epoch_73() {
        let (inside, _) = run_banner("Valiant", "human_defense_force", false, Some(5.0), None, EPOCH_73_V36);
        assert_eq!(inside, 4, "Valiant inside 9\": no +1");
        let (outside, _) = run_banner("Valiant", "human_defense_force", false, Some(10.0), None, EPOCH_73_V36);
        assert_eq!(outside, 3, "Valiant over 9\": the +1 counts");
    }

    #[test]
    fn valiant_minority_gives_nothing_at_epoch_73() {
        let mut p = banner_profile("Valiant", "human_defense_force");
        p.attached_hero_rules = vec![Vec::new()];
        let mut reg = Registries::new(&repo_root());
        assert_eq!(capture_reads_for_epoch(&mut reg, &p, EPOCH_73_V36).morale_bonus, 0,
            "a minority carrier gets no Banner stamp");
        let (target, _) = run_profile(&p, false, Some(5.0), None, EPOCH_73_V36);
        assert_eq!(target, 4, "a minority carrier reads plain Quality");
    }
}
