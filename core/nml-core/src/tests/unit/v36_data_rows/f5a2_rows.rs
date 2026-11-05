//! W31-F5a2 tests (release 0.3.15): rules the registry-gated readers dropped in books that field them without a
//! mechanics row (Piercing Spotter, Precision Spotter, Slayer). The "is it automated?" test reads the static
//! `modeled` list for every book, so the rules neither applied nor told the player to do them by hand. Every
//! carrier is built the way the game builds it (a header profile with the book's slug and system, then
//! `UnitStatic::build_for` at the live epoch) and read through the stamp the rule uses. Each rule has a control
//! book that already had its row. Table twin: `test/v36/f5a2_silent_rows_test.gd`.
use super::super::*;

/// One unit of `book` carrying `rules` (a JSON array: the unit's own rules, as the army import writes them), with a
/// rifle and a melee blade.
fn f5b_carrier(system: &str, book: &str, rules: &str) -> Profile {
    let tpl = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{
      "carrier":{{"unit_id":"carrier","name":"Carrier","quality":4,
        "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"{system}","faction_folder":"{book}",
        "special_rules":{rules},"item_grants":[],
        "attached_hero_rules":[],"move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}},
          {{"name":"Blade","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}}]}}}}}}"#
    );
    read_act_header(&tpl).expect("header").profiles.get("carrier").expect("carrier").clone()
}

fn f5b_built(system: &str, book: &str, rules: &str) -> UnitStatic {
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &f5b_carrier(system, book, rules), CURRENT_RULES_EPOCH)
}

/// Piercing Spotter: the 30 inch pick with the printed 4+ die (the control is the one book that had its row).
#[test]
fn f5a2_piercing_spotter_rolls_its_die_where_the_book_fields_it() {
    let marks = |us: &UnitStatic| {
        us.piercing_tags.iter().map(|t| (t.name.clone(), t.range_in, t.place_roll)).collect::<Vec<_>>()
    };
    let want = vec![("Piercing Spotter".to_string(), 30.0, 4)];
    assert_eq!(marks(&f5b_built("aof", "mummified_undead", r#"["Piercing Spotter"]"#)), want, "control book");
    assert!(marks(&f5b_built("aof", "duchies_of_vinci", "[]")).is_empty(), "no rule, no pick");
    let mut dropped: Vec<&str> = Vec::new();
    for book in ["duchies_of_vinci", "sky_city_dwarves"] {
        if marks(&f5b_built("aof", book, r#"["Piercing Spotter"]"#)) != want {
            dropped.push(book);
        }
    }
    assert!(dropped.is_empty(), "aof: Piercing Spotter silently dropped in {dropped:?}");
}

/// Precision Spotter: the core reads it only through its registry row ("Utility Buff"); the table already reads the
/// rule by name, so before the row the two engines disagreed in this book.
#[test]
fn f5a2_precision_spotter_marks_an_enemy_where_the_book_fields_it() {
    let spotter = |us: &UnitStatic| {
        us.utility_buffs.iter().filter(|b| b.name == "Precision Spotter").map(|b| (b.range_in, b.target.clone())).collect::<Vec<_>>()
    };
    let want = vec![(30.0, "enemy".to_string())];
    assert_eq!(spotter(&f5b_built("aof", "duchies_of_vinci", r#"["Precision Spotter"]"#)), want, "control book");
    assert!(spotter(&f5b_built("aof", "saurians", "[]")).is_empty(), "no rule, no mark");
    assert_eq!(spotter(&f5b_built("aof", "saurians", r#"["Precision Spotter"]"#)), want,
        "aof/saurians: Precision Spotter silently dropped");
}

/// Slayer (the unit's own rule): AP(+2) on a charge or a Hold-and-shoot against a Tough(3)+ target.
#[test]
fn f5a2_slayer_adds_its_ap_where_the_book_fields_it() {
    let specs = |us: &UnitStatic| {
        us.shoot.iter().flat_map(|sp| sp.cond_ap.iter())
            .filter(|c| c.ap_bonus == 2 && c.threshold == 3 && c.condition == "vs_tough_ge" && c.gate == "hold_or_charge")
            .count()
    };
    assert_eq!(specs(&f5b_built("aof", "duchies_of_vinci", r#"["Slayer"]"#)), 1, "control book");
    assert_eq!(specs(&f5b_built("aof", "high_elves", "[]")), 0, "no rule, no AP spec");
    assert_eq!(specs(&f5b_built("aof", "high_elves", r#"["Slayer"]"#)), 1, "aof/high_elves: Slayer silently dropped");
}
