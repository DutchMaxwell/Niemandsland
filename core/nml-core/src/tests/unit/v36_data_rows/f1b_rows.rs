//! W31-F1 follow-up tests (release 0.3.15): rules the registry-gated readers dropped in books that field them
//! without a mechanics row. Every carrier is built the way the game builds it (a header profile with the book's
//! slug and system, then `UnitStatic::build_for` at the live epoch) and read through the reader the rule uses.
//! Each rule has a control book that already had its row, and a unit without the rule that must stay unlifted.
//! Table twin: `test/v36/f1b_registry_rows_test.gd`.
use super::super::*;
use serde_json::json;

/// One unit of `book` carrying `rules` (a JSON array) with a rifle and an Indirect mortar.
fn f1b_carrier(system: &str, book: &str, rules: &str) -> Profile {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "carrier":{{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"{system}","faction_folder":"{book}",
        "special_rules":{rules},"item_grants":[],
        "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}},
          {{"name":"Mortar","range":24,"attacks":1,"count":1,"ap":0,"rules":["Indirect"]}}]}}}}}}"#
    );
    read_act_header(&tpl).expect("header").profiles.get("carrier").expect("carrier").clone()
}

fn f1b_built(system: &str, book: &str, rules: &str) -> UnitStatic {
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &f1b_carrier(system, book, rules), CURRENT_RULES_EPOCH)
}

/// The four books that field Vanguard without a row of their own (the first batch is a separate change).
const F1B_VANGUARD_BOOKS: [(&str, &str); 4] = [
    ("gf", "prime_brothers"), ("gf", "watch_prime_brothers"), ("gf", "wolf_brothers"), ("gf", "wolf_prime_brothers"),
];

#[test]
fn f1b_vanguard_books_apply_it_with_the_nine_inch_reach() {
    let mut reg = Registries::new(&repo_root());
    let control = f1b_carrier("gf", "dark_elf_raiders", r#"["Vanguard"]"#);
    assert!(unit_rule_active(&mut reg, &control, "Vanguard"), "the control book keeps its row");
    let mut dropped: Vec<String> = Vec::new();
    for (system, book) in F1B_VANGUARD_BOOKS {
        let p = f1b_carrier(system, book, r#"["Vanguard"]"#);
        let params = reg.rules_for(system).lookup(book, "Vanguard").map(|e| e.params.clone());
        if !unit_rule_active(&mut reg, &p, "Vanguard") || params != Some(json!({"place_in": 9.0})) {
            dropped.push(format!("{system}/{book}"));
        }
    }
    assert!(dropped.is_empty(), "Vanguard silently dropped in: {dropped:?}");
}

#[test]
fn f1b_hit_and_run_shooter_is_active_where_the_book_fields_it() {
    assert!(f1b_built("gf", "custodian_brothers", r#"["Hit & Run Shooter"]"#).hit_and_run_shooter_active,
        "the control book keeps its row");
    assert!(!f1b_built("gf", "infected_colonies", "[]").hit_and_run_shooter_active, "no rule, no step");
    assert!(f1b_built("gf", "infected_colonies", r#"["Hit & Run Shooter"]"#).hit_and_run_shooter_active,
        "gf/infected_colonies: Hit & Run Shooter silently dropped");
}

#[test]
fn f1b_bounding_places_the_unit_where_the_book_fields_it() {
    let named = |us: &UnitStatic| us.bounding_place.as_ref().map(|b| (b.name.clone(), b.dice, b.plus));
    assert_eq!(named(&f1b_built("aof", "giant_tribes", r#"["Bounding"]"#)), Some(("Bounding".into(), 1, 1.0)),
        "the control book keeps its row");
    assert_eq!(named(&f1b_built("aof", "eternal_wardens", "[]")), None, "no rule, no placement");
    assert_eq!(named(&f1b_built("aof", "eternal_wardens", r#"["Bounding"]"#)), Some(("Bounding".into(), 1, 1.0)),
        "aof/eternal_wardens: Bounding silently dropped");
}

/// The sight waiver of an Indirect weapon needs Hold unless the unit carries Quick Throw.
#[test]
fn f1b_quick_throw_lifts_the_hold_need_where_the_book_fields_it() {
    let needs_hold = |us: &UnitStatic| {
        let sp = us.shoot.iter().find(|sp| sp.indirect).expect("the mortar is Indirect");
        sp.indirect_los_needs_hold
    };
    assert!(!needs_hold(&f1b_built("aof", "dragon_empire", r#"["Quick Throw"]"#)), "the control book keeps its row");
    assert!(needs_hold(&f1b_built("aof", "dwarves", "[]")), "without the rule the waiver needs Hold");
    for book in ["duchies_of_vinci", "dwarves"] {
        assert!(!needs_hold(&f1b_built("aof", book, r#"["Quick Throw"]"#)), "aof/{book}: Quick Throw silently dropped");
    }
}
