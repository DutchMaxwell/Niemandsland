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
    /// instead. That share needs the live alive count (Sergeant's own gap), so the static stamp
    /// reports it by name rather than surging.
    #[test]
    fn a_great_sergeant_leaves_the_surge_window_and_reports_its_gap_at_epoch_73() {
        let us = great_sergeant("\"Great Sergeant\"", EPOCH_73_V36);
        assert!(!us.shoot[0].surge, "no extra hits when shooting from 73");
        assert!(!us.melee[0].surge, "no extra hits in melee from 73");
        assert_eq!(us.shoot[0].surge_low, 6, "no 5-6 window from 73");
        assert_eq!(reports(&us, "Great Sergeant"), 1, "exactly one report, by the exact name");
    }

    /// The rules 3.5 leg: every game recorded at 72 replays the 5-6 window, no report.
    #[test]
    fn a_great_sergeant_keeps_its_surge_window_at_epoch_72() {
        let us = great_sergeant("\"Great Sergeant\"", EPOCH_72_PLAYTEST_RULES);
        assert!(us.shoot[0].surge, "the facet replays at 72");
        assert_eq!(us.shoot[0].surge_low, 5, "the printed 5-6 replays at 72");
        assert_eq!(reports(&us, "Great Sergeant"), 0, "no report at 72");
    }

    /// Sergeant keeps its live-count report at BOTH epochs: the core never guesses the share.
    #[test]
    fn a_sergeant_reports_its_live_count_gap_at_epoch_72_and_epoch_73() {
        for e in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
            let us = great_sergeant("\"Sergeant\"", e);
            assert_eq!(reports(&us, "Sergeant"), 1, "epoch {e}: one report, by the exact name");
            assert_eq!(us.melee[0].sergeant_attacks, 0, "epoch {e}: the share is never guessed");
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
