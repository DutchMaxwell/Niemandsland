//! Rules 3.6 row MOR-14 tests (sim module); owned by lane morale.

use super::super::*;
use super::{four_unit_line, repo_root};
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::rules::{Registries, Spell};

/// One REAL spell entry off the committed spell book — the same registry read
/// the live resolver uses.
fn real_spell(system: &str, faction: &str, name: &str) -> Spell {
    let mut reg = Registries::new(&repo_root());
    reg.spells_for(system, faction)
        .iter()
        .find(|s| s.name == name)
        .cloned()
        .unwrap_or_else(|| panic!("'{name}' is in {system}/{faction}'s spell book"))
}

/// The four-unit line with only the enemy "b" (unit 2) alive, so the pick has
/// exactly one candidate 12" from the caster.
fn hidden_enemy_line() -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    st.alive = vec![1, 0, 1, 0];
    let statics = (0..4).map(|_| UnitStatic::default()).collect();
    (st, statics)
}

/// The hidden enemy is not sighted: every los answer is false.
fn no_sight() -> Vec<bool> {
    vec![false; 4]
}

#[test]
fn needs_los_parses_from_the_real_spell_list() {
    assert!(
        !real_spell("gf", "dao_union", "Deadly Surge").needs_los,
        "a spell without the key needs no sight"
    );
    assert!(
        real_spell("gf", "alien_hives", "Hive Shriek").needs_los,
        "the entry's own top-level needs_los is read"
    );
}

#[test]
fn a_spell_without_the_clause_reaches_a_hidden_unit_at_epoch_73() {
    let (st, statics) = hidden_enemy_line();
    let entry = real_spell("gf", "dao_union", "Deadly Surge");
    assert_eq!(
        best_spell_target(&statics, &st, 0, &entry, &no_sight(), &[(0, 0)], EPOCH_73_V36),
        Some((2, 0)),
        "Deadly Surge has no needs_los clause, so the wall-hidden unit in range is a legal target"
    );
}

#[test]
fn a_spell_with_the_clause_still_refuses_a_hidden_unit_at_epoch_73() {
    let (st, statics) = hidden_enemy_line();
    let entry = real_spell("gf", "alien_hives", "Hive Shriek");
    assert_eq!(
        best_spell_target(&statics, &st, 0, &entry, &no_sight(), &[(0, 0)], EPOCH_73_V36),
        None,
        "Hive Shriek carries needs_los: true, so the hidden unit stays untargetable"
    );
}

#[test]
fn every_spell_needs_sight_at_epoch_72() {
    let (st, statics) = hidden_enemy_line();
    let entry = real_spell("gf", "dao_union", "Deadly Surge");
    assert_eq!(
        best_spell_target(
            &statics,
            &st,
            0,
            &entry,
            &no_sight(),
            &[(0, 0)],
            EPOCH_72_PLAYTEST_RULES
        ),
        None,
        "epoch 72 keeps today's rule: sight is required for every spell"
    );
}
