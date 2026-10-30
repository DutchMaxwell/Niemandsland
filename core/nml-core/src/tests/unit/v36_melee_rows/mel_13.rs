//! MEL-13 tests (rules 3.6, lane melee); empty until the row lands - start with `use super::super::*;`.
use super::super::*;
use crate::acts::EPOCH_73_V36;

/// MEL-13 (F 26b): the Dodge stamp `ctx_for` writes for one unit: `rules` on every host model,
/// `heroes` the rule lists of the joined heroes (each counts as one model).
fn dodge_stamp(rules: &[&str], model_count: i64, heroes: &[&[&str]]) -> (bool, bool) {
    let mut p: crate::state::Profile =
        serde_json::from_str(r#"{"unit_id":"d","name":"Dodger","game_system":"gf","faction_folder":"dark_elf_raiders"}"#).unwrap();
    p.model_count = model_count;
    p.special_rules = rules.iter().map(|r| r.to_string()).collect();
    p.attached_hero_rules = heroes.iter().map(|h| h.iter().map(|r| r.to_string()).collect()).collect();
    let mut reg = Registries::new(&repo_root());
    let us = UnitStatic::build_for(&mut reg, &p, EPOCH_73_V36);
    (us.ctx.dodge, us.ctx.melee_evasion)
}

#[test]
fn dodge_is_stamped_when_most_models_carry_it_and_never_by_plain_melee_evasion() {
    assert_eq!(dodge_stamp(&["Dodge"], 5, &[]), (true, false), "every model carries Dodge");
    assert_eq!(dodge_stamp(&["Dodge"], 5, &[&["Hero"]]), (true, false), "5 of 6 is most");
    assert_eq!(dodge_stamp(&["Dodge"], 1, &[&["Hero"]]), (false, false), "an exact half is not most");
    assert_eq!(dodge_stamp(&["Hero"], 5, &[]), (false, false), "no rule, no stamp");
    assert_eq!(dodge_stamp(&["Melee Evasion"], 5, &[]), (false, true), "plain Melee Evasion keeps its own stamp");
}
