//! W31-F5b test (release 0.3.15): Ravage in aof duchies_of_vinci. The core reads the rule's rating BY NAME off the
//! unit's own rules, so its melee seam already rolls it; the table's strike phase asks the registry per book
//! (`unit_rule_active`) and drops it where the book has no row. The two engines disagreed, so an arena (core) game and
//! a real table game played different fights for the same Scouts. The fix is the missing row (23 other books have it).
//! The carrier is built the way the game builds it (a header profile with the book's slug and system, then
//! `UnitStatic::build_for` at the live epoch). Table twin: `test/v36/f5b_ravage_vinci_test.gd`.
use super::super::*;

fn f5b_ravage_built(system: &str, book: &str, rules: &str) -> UnitStatic {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "carrier":{{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"{system}","faction_folder":"{book}",
        "special_rules":{rules},"item_grants":[],
        "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
    );
    let p = read_act_header(&tpl).expect("header").profiles.get("carrier").expect("carrier").clone();
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &p, CURRENT_RULES_EPOCH)
}

/// The core applies the rating by name in every book, with or without a row: this pins that the core was the correct
/// side (green on main), so the disagreement is the table's.
#[test]
fn f5b_the_core_rolls_ravage_by_name_in_duchies_of_vinci() {
    assert_eq!(f5b_ravage_built("aof", "beastmen", r#"["Ravage(2)"]"#).ctx.ravage, 2, "control book with a row");
    assert_eq!(f5b_ravage_built("aof", "duchies_of_vinci", "[]").ctx.ravage, 0, "no rule, no Ravage");
    assert_eq!(f5b_ravage_built("aof", "duchies_of_vinci", r#"["Ravage(1)"]"#).ctx.ravage, 1, "the core reads the rating by name");
}

/// The registry the table's strike phase asks must carry the same Ravage entry the other 23 books carry.
#[test]
fn f5b_the_registry_row_the_table_asks_for_exists_in_duchies_of_vinci() {
    let mut reg = Registries::new(&repo_root());
    let shape = |reg: &mut Registries, book: &str| {
        reg.rules_for("aof").lookup(book, "Ravage").map(|e| (e.primitive.clone(), e.param_f("wound_target", 0.0), e.param_b("no_save")))
    };
    let control = shape(&mut reg, "beastmen");
    assert_eq!(control, Some((Some("Ravage".to_string()), 6.0, true)), "the control book keeps its row");
    assert_eq!(shape(&mut reg, "duchies_of_vinci"), control, "aof/duchies_of_vinci: Ravage has no registry row (the table drops it)");
}
