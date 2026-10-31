//! Rules 3.6 lane morale tests for the dice module; owned by lane morale.
use super::*;

// ---- Row MOR-03 (ruling D-MOST): the Stealth family counts MOST models ----

/// A squad of `models` models carrying `special` (a JSON list) with the joined heroes `heroes` (a
/// JSON list of rule lists), built at `epoch` for (gf, `faction`) through the real registry.
fn mor03_squad(faction: &str, special: &str, heroes: &str, models: i64, epoch: u32) -> UnitStatic {
    let tpl = r#"{"kind":"header","knobs":{},"profiles":{
      "st":{"unit_id":"st","name":"Stealth Squad","quality":4,
        "defense":4,"tough":1,"wounds_max":WOUNDS,"model_count":MODELS,"caster_value":0,
        "base_radius":0.016,"game_system":"gf","faction_folder":"FACTION",
        "special_rules":SPECIAL,"item_grants":[],
        "attached_hero_rules":HEROES,"move_bands":{"advance":6.0,"rush":12.0},
        "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#
        .replace("WOUNDS", &format!("{:?}", vec![1; models as usize]))
        .replace("MODELS", &models.to_string())
        .replace("FACTION", faction)
        .replace("SPECIAL", special)
        .replace("HEROES", heroes);
    let header = read_act_header(&tpl).expect("header");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, header.profiles.get("st").expect("st"), epoch)
}

/// One Quality 4+ rifle shot at `us` from `dist_in` inches.
fn mor03_shot(us: &UnitStatic, dist_in: f64) -> ShootResult {
    let mut tray = Tray::seeded(27);
    resolve_shooting_with_tray(&[rifle(1)], &[0], &[1], &shooter(4), &us.ctx, dist_in, &mut tray)
}

fn mor03_names_most_models(out: &ShootResult) -> bool {
    out.log.iter().any(|l| l.contains("Stealth") && l.contains("most models"))
}

const MOR03_PLAIN_HERO: &str = r#"[["Hero"]]"#;

/// Three Stealth models and a joined hero without it are most models: the shot past 9" takes the
/// -1 and the log says the majority carried it. One Stealth model plus that hero is an exact half
/// (off), and a squad where every model has Stealth logs nothing extra.
#[test]
fn a_stealth_squad_keeps_its_minus_one_with_a_joined_hero_without_it_at_epoch_73() {
    let us = mor03_squad("robot_legions", r#"["Stealth"]"#, MOR03_PLAIN_HERO, 3, crate::acts::EPOCH_73_V36);
    let far = mor03_shot(&us, 12.0);
    assert_eq!(far.rolls[0].target, 5, "3 of 4 models carry Stealth: Quality 4+ reads 5+ past 9\"");
    assert!(mor03_names_most_models(&far), "the log names the most-models read: {:?}", far.log);
    assert_eq!(mor03_shot(&us, 6.0).rolls[0].target, 4, "within 9\" Stealth does nothing");
    let tie = mor03_squad("robot_legions", r#"["Stealth"]"#, MOR03_PLAIN_HERO, 1, crate::acts::EPOCH_73_V36);
    assert_eq!(mor03_shot(&tie, 12.0).rolls[0].target, 4, "1 of 2 models is an exact half: no -1");
    let all = mor03_squad("robot_legions", r#"["Stealth"]"#, "[]", 3, crate::acts::EPOCH_73_V36);
    let all_far = mor03_shot(&all, 12.0);
    assert_eq!(all_far.rolls[0].target, 5, "every model carries Stealth");
    assert!(!mor03_names_most_models(&all_far), "no most-models line when all carry it: {:?}", all_far.log);
}

/// Control: below the 3.6 epoch a joined hero without Stealth still takes it away.
#[test]
fn a_stealth_squad_loses_its_minus_one_with_a_joined_hero_without_it_at_epoch_72() {
    let us = mor03_squad("robot_legions", r#"["Stealth"]"#, MOR03_PLAIN_HERO, 3, crate::acts::EPOCH_72_PLAYTEST_RULES);
    let far = mor03_shot(&us, 12.0);
    assert_eq!(far.rolls[0].target, 4, "at 72 the hero withholds Stealth");
    assert!(!mor03_names_most_models(&far), "{:?}", far.log);
}

/// Changebound is a "most models" alias of the family: its -1 past 9" holds with a plain hero.
#[test]
fn changebound_keeps_its_minus_one_with_a_joined_hero_without_it_at_epoch_73() {
    let us = mor03_squad("change_disciples", r#"["Changebound"]"#, MOR03_PLAIN_HERO, 3, crate::acts::EPOCH_73_V36);
    assert_eq!(mor03_shot(&us, 12.0).rolls[0].target, 5, "3 of 4 models carry Changebound");
}

/// Control: below the 3.6 epoch the same hero withholds Changebound.
#[test]
fn changebound_loses_its_minus_one_with_a_joined_hero_without_it_at_epoch_72() {
    let us = mor03_squad("change_disciples", r#"["Changebound"]"#, MOR03_PLAIN_HERO, 3, crate::acts::EPOCH_72_PLAYTEST_RULES);
    assert_eq!(mor03_shot(&us, 12.0).rolls[0].target, 4);
}
