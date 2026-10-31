use super::super::*;

// Rules 3.6 row MOR-04: Entrenched is a Human Defense Force rule, -1 to be hit from over 12" while
// the unit is unmoved and MOST of its models carry it (from EPOCH_73_V36; below it every model must).

use crate::acts::{read_act_header, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::rules::Registries;
use crate::unit::UnitStatic;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// A Human Defense Force squad of `models` models carrying Entrenched, with the joined heroes'
/// rule lists `heroes` (a JSON list of lists), built through the REAL registry at `epoch`.
fn ent_squad(heroes: &str, models: i64, epoch: u32) -> UnitStatic {
    let tpl = r#"{"kind":"header","knobs":{},"profiles":{
      "ent":{"unit_id":"ent","name":"Entrenched Squad","quality":4,
        "defense":4,"tough":1,"wounds_max":WOUNDS,"model_count":MODELS,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"human_defense_force",
        "special_rules":["Entrenched"],"item_grants":[],
        "attached_hero_rules":HEROES,"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#
        .replace("WOUNDS", &format!("{:?}", vec![1; models as usize]))
        .replace("MODELS", &models.to_string())
        .replace("HEROES", heroes);
    let header = read_act_header(&tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("ent").expect("ent"), epoch)
}

fn rifle(attacks: i64) -> ShootProfile {
    ShootProfile { name: "Rifle".into(), attacks, count: 1, range: 24, ..Default::default() }
}

fn shooter(quality: i64) -> Ctx {
    Ctx { quality, ..Default::default() }
}

/// One Quality 4+ rifle shot at `ctx` from `dist_in` inches.
fn ent_shot(ctx: &Ctx, dist_in: f64) -> ShootResult {
    let mut tray = Tray::seeded(27);
    resolve_shooting_with_tray(&[rifle(1)], &[0], &[1], &shooter(4), ctx, dist_in, &mut tray)
}

fn names_entrenched(out: &ShootResult) -> bool {
    out.log.iter().any(|l| l.contains("[Entrenched]") && l.contains("12"))
}

const PLAIN_HERO: &str = r#"[["Hero"]]"#;

/// The 3.6 reading at 73: an unmoved HDF squad is -1 (Quality 4+ reads 5+) past 12", silent at
/// exactly 12" and within it, and the battle log names Entrenched with the 12" gate.
#[test]
fn an_hdf_entrenched_squad_is_minus_one_past_twelve_inches_at_epoch_73() {
    let us = ent_squad("[]", 1, EPOCH_73_V36);
    let unmoved = Ctx { moved_round: -1, round: 3, ..us.ctx };
    let far = ent_shot(&unmoved, 13.0);
    assert_eq!(far.rolls[0].target, 5, "unmoved Entrenched: Quality 4+ -> 5+ (the -1)");
    assert!(names_entrenched(&far), "the line names Entrenched with the 12\" gate: {:?}", far.log);
    assert_eq!(ent_shot(&unmoved, 12.0).rolls[0].target, 4, "at exactly 12\" the gate is closed");
    assert_eq!(ent_shot(&unmoved, 11.0).rolls[0].target, 4, "within 12\" Entrenched does nothing");
}

/// MOST models is the 3.6 carrier test at 73: three Entrenched models with a joined hero without
/// it still take the -1, while one plus that hero is an exact half and gets nothing.
#[test]
fn most_models_carrying_entrenched_keep_the_minus_one_at_epoch_73() {
    let us = ent_squad(PLAIN_HERO, 3, EPOCH_73_V36);
    let unmoved = Ctx { moved_round: -1, round: 3, ..us.ctx };
    assert_eq!(ent_shot(&unmoved, 13.0).rolls[0].target, 5, "3 of 4 models carry Entrenched");
    let tie = ent_squad(PLAIN_HERO, 1, EPOCH_73_V36);
    let tie_unmoved = Ctx { moved_round: -1, round: 3, ..tie.ctx };
    let tie_far = ent_shot(&tie_unmoved, 13.0);
    assert_eq!(tie_far.rolls[0].target, 4, "1 of 2 models is an exact half: no -1");
    assert!(!names_entrenched(&tie_far), "{:?}", tie_far.log);
}

/// Control: below 73 the carrier test is still every model, so a joined hero without Entrenched
/// withholds it (unchanged before and after the row).
#[test]
fn a_joined_hero_without_entrenched_withholds_it_at_epoch_72() {
    let us = ent_squad(PLAIN_HERO, 3, EPOCH_72_PLAYTEST_RULES);
    let unmoved = Ctx { moved_round: -1, round: 3, ..us.ctx };
    let far = ent_shot(&unmoved, 13.0);
    assert_eq!(far.rolls[0].target, 4, "at 72 the hero without Entrenched withholds it");
    assert!(!names_entrenched(&far), "{:?}", far.log);
}

/// Control: a squad that moved this round gets no penalty at either epoch.
#[test]
fn an_entrenched_squad_that_moved_gets_no_penalty_at_epoch_72_and_73() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        let us = ent_squad("[]", 1, epoch);
        let moved = Ctx { moved_round: 3, round: 3, ..us.ctx };
        let far = ent_shot(&moved, 13.0);
        assert_eq!(far.rolls[0].target, 4, "{epoch}: moved this round, the gate stands down");
        assert!(!names_entrenched(&far), "{epoch}: {:?}", far.log);
    }
}
