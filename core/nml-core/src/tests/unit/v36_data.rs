//! Rules 3.6 lane data tests for the unit module; owned by lane data.
use super::*;
use serde_json::json;

/// DAT-01: Shred and Surge are core rules in both 3.6 systems, so the gf and aof maps carry them
/// as common entries. A book without its own entry resolves them through the common fallback,
/// with the params every faction entry already carries; a book with its own entry resolves the same.
fn assert_resolves(reg: &mut Registries, system: &str, book: &str, rule: &str, params: serde_json::Value) {
    let map = reg.rules_for(system);
    assert!(map.has_primitive(book, rule), "{system} / {book}: {rule} must resolve to a primitive");
    let entry = map.lookup(book, rule).expect("a resolving rule has an entry");
    assert_eq!(entry.primitive.as_deref(), Some(rule), "{system} / {book}: {rule} primitive");
    assert_eq!(entry.params, params, "{system} / {book}: {rule} params");
}

#[test]
fn dat_01_a_book_without_its_own_entry_resolves_shred_and_surge() {
    let mut reg = Registries::new(&repo_root());
    for (system, book) in [("gf", "human_defense_force"), ("aof", "orcs")] {
        assert_resolves(&mut reg, system, book, "Shred", json!({"extra_wound_per_save_one": 1}));
        assert_resolves(&mut reg, system, book, "Surge", json!({"bonus_hits_per_six": 1}));
    }
}

/// Control: the books that already had their own entries resolve unchanged.
#[test]
fn dat_01_a_book_with_its_own_entry_resolves_shred_and_surge_unchanged() {
    let mut reg = Registries::new(&repo_root());
    for (system, book) in [("gf", "alien_hives"), ("aof", "beastmen")] {
        assert_resolves(&mut reg, system, book, "Shred", json!({"extra_wound_per_save_one": 1}));
        assert_resolves(&mut reg, system, book, "Surge", json!({"bonus_hits_per_six": 1}));
    }
}
