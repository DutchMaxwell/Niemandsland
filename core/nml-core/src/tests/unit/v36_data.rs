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

/// AI-08b: Crossing Strike is the 3.6 name of the weapon that attacks only when its bearer moves
/// through an enemy unit. It must behave like its 3.5 name: out of every normal volley, in the
/// move-through trigger's own set, and carrying the strafing flag.
fn flagged_weapon(rule: &str) -> Weapon {
    Weapon { name: "Twin Autocannon".into(), range: 24.0, attacks: 4, count: 1, ap: 0, rules: vec![rule.into()] }
}

fn plain_gun() -> Weapon {
    Weapon { name: "Lash Cannon".into(), range: 24.0, attacks: 2, count: 1, ap: 0, rules: vec![] }
}

#[test]
fn ai_08b_a_crossing_strike_weapon_never_joins_a_normal_volley() {
    let volley = profiles_in_range(&[flagged_weapon("Crossing Strike"), plain_gun()], 6.0);
    let names: Vec<&str> = volley.iter().map(|p| p.name.as_str()).collect();
    assert_eq!(names, vec!["Lash Cannon"], "a Crossing Strike weapon fired in a normal volley");
}

#[test]
fn ai_08b_a_crossing_strike_weapon_is_in_the_move_through_set_with_the_strafing_flag() {
    let set = strafing_profiles(&[flagged_weapon("Crossing Strike"), plain_gun()]);
    assert_eq!(set.len(), 1, "only the Crossing Strike weapon belongs to the move-through set");
    assert_eq!(set[0].name, "Twin Autocannon");
    assert_eq!(set[0].attacks, 4);
    assert!(set[0].strafing, "the move-through weapon must carry the strafing flag");
}

/// Control: the 3.5 name keeps behaving exactly as before.
#[test]
fn ai_08b_control_a_strafing_weapon_is_unchanged() {
    let volley = profiles_in_range(&[flagged_weapon("Strafing"), plain_gun()], 6.0);
    let names: Vec<&str> = volley.iter().map(|p| p.name.as_str()).collect();
    assert_eq!(names, vec!["Lash Cannon"], "a Strafing weapon fired in a normal volley");
    let set = strafing_profiles(&[flagged_weapon("Strafing"), plain_gun()]);
    assert_eq!(set.len(), 1);
    assert!(set[0].strafing);
}
