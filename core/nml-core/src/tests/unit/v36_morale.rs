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
