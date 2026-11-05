//! W31-F1 tests (release 0.3.15): a book that fields Vanguard without a mechanics row was dropped by the
//! registry-gated reader (`unit_rule_active`), while the table's "is it automated?" list said it was handled.
//! Each carrier is built the way the game builds it (a header profile with the book's slug and system) and read
//! through the reader the placement uses. Table twin: `test/v36/w31_f1_vanguard_books_test.gd`.
use super::super::*;
use serde_json::json;

/// One unit of `book` carrying `rules` (a JSON array) at unit level, read off the real registry.
fn w31_f1_carrier(system: &str, book: &str, rules: &str) -> Profile {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "carrier":{{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"{system}","faction_folder":"{book}",
        "special_rules":{rules},"item_grants":[],
        "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
    );
    read_act_header(&tpl).expect("header").profiles.get("carrier").expect("carrier").clone()
}

/// The books that field Vanguard and, before this change, had no Vanguard row of their own.
const W31_F1_VANGUARD_BOOKS: [(&str, &str); 10] = [
    ("gf", "battle_brothers"), ("gf", "blood_brothers"), ("gf", "blood_prime_brothers"),
    ("gf", "dark_prime_brothers"), ("gf", "infected_colonies"), ("gf", "knight_prime_brothers"),
    ("gf", "rebel_guerrillas"), ("gf", "saurian_starhosts"),
    ("aof", "dwarves"), ("aof", "saurians"),
];

/// Control: a book that always had its row resolves Vanguard, so the reader itself is sound.
#[test]
fn w31_f1_control_a_book_with_its_row_applies_vanguard() {
    let mut reg = Registries::new(&repo_root());
    let p = w31_f1_carrier("gf", "dark_elf_raiders", r#"["Vanguard"]"#);
    assert!(unit_rule_active(&mut reg, &p, "Vanguard"), "dark_elf_raiders keeps its Vanguard row");
}

#[test]
fn w31_f1_books_that_field_vanguard_apply_it_with_the_nine_inch_reach() {
    let mut reg = Registries::new(&repo_root());
    let mut dropped: Vec<String> = Vec::new();
    for (system, book) in W31_F1_VANGUARD_BOOKS {
        let p = w31_f1_carrier(system, book, r#"["Vanguard"]"#);
        let entry = reg.rules_for(system).lookup(book, "Vanguard").cloned();
        let params = entry.as_ref().map(|e| e.params.clone());
        if !unit_rule_active(&mut reg, &p, "Vanguard") || params != Some(json!({"place_in": 9.0})) {
            dropped.push(format!("{system}/{book}"));
        }
    }
    assert!(dropped.is_empty(), "Vanguard silently dropped in: {dropped:?}");
}
