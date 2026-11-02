//! AUDIT-doubt-ravage: the orcs' rated Ravage grant is read from epoch 73 and
//! rates one die; below the epoch the rating read keeps today's answer.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// One orcs carrier printing `rules`, built through the REAL aof registry at
/// `epoch`. Returns the built rating and the rule list the build's own folds
/// left on the profile — the oracle `unit_rating` reads, not a guess.
fn ravage_of(rules: &[&str], epoch: u32) -> (i64, Vec<String>) {
    let printed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let tpl = AMBUSH_FAMILY_HEADER
        .replace("\"special_rules\":[]", &format!("\"special_rules\":[{printed}]"))
        .replace("\"game_system\":\"gf\"", "\"game_system\":\"aof\"")
        .replace("\"faction_folder\":\"robot_legions\"", "\"faction_folder\":\"orcs\"")
        .replace(RIFLE_ONLY, RIFLE_AND_BLADE);
    let header = read_act_header(&tpl).expect("orc carrier header parses");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("carrier").expect("carrier");
    let us = UnitStatic::build_for(&mut reg, p, epoch);
    // The same folds `build_for` runs, replayed so the oracle sees the exact
    // rule list the build read.
    let aura_leg = expand_aura_channel(p, epoch);
    let boost_leg = expand_boost_aura(&aura_leg, epoch);
    let mut effective = boost_leg.into_owned();
    apply_aura_channel(&mut reg, &mut effective, epoch);
    apply_fortified_aura_picks(&mut reg, &mut effective, epoch);
    (us.ctx.ravage, effective.special_rules)
}

/// (a) The orcs' Ravage Aura hands out "Ravage(+1)", and the core rates it one
/// die at epoch 73.
#[test]
fn the_ravage_aura_rates_one_at_epoch_73() {
    let (rating, rules) = ravage_of(&["Ravage Aura"], EPOCH_73_V36);
    assert_eq!(
        rating, 1,
        "epoch 73: Ravage Aura grants Ravage(+1) and the core rates one die; rules: {rules:?}"
    );
    assert_eq!(
        rating,
        crate::rules::unit_rating(&rules, "Ravage"),
        "the stamp is the rating read's own answer; rules: {rules:?}"
    );
    let (literal, literal_rules) = ravage_of(&["Ravage(+1)"], EPOCH_73_V36);
    assert_eq!(literal, 1, "a record printing Ravage(+1) rates one die; rules: {literal_rules:?}");
}

/// (b) The same fixture at epoch 72 keeps TODAY'S answer: the stamp equals
/// what `unit_rating` answers for the rule list the build actually read, and
/// a literal rated record answers exactly as it does at 73.
#[test]
fn the_ravage_aura_keeps_todays_answer_at_epoch_72() {
    let (rating, rules) = ravage_of(&["Ravage Aura"], EPOCH_72_PLAYTEST_RULES);
    assert_eq!(
        rating,
        crate::rules::unit_rating(&rules, "Ravage"),
        "epoch 72 answers exactly what unit_rating answers today; rules: {rules:?}"
    );
    let (literal, literal_rules) = ravage_of(&["Ravage(+1)"], EPOCH_72_PLAYTEST_RULES);
    assert_eq!(
        literal,
        crate::rules::unit_rating(&literal_rules, "Ravage"),
        "a literal rated record keeps unit_rating's answer; rules: {literal_rules:?}"
    );
    let (literal73, _) = ravage_of(&["Ravage(+1)"], EPOCH_73_V36);
    assert_eq!(literal, literal73, "the rating read answers the same below the epoch");
}

/// (c) A plain "Ravage" carries no rating and is byte-identical at both
/// epochs.
#[test]
fn a_plain_ravage_is_unchanged_at_both_epochs() {
    let (new, new_rules) = ravage_of(&["Ravage"], EPOCH_73_V36);
    let (old, old_rules) = ravage_of(&["Ravage"], EPOCH_72_PLAYTEST_RULES);
    assert_eq!(new, crate::rules::unit_rating(&new_rules, "Ravage"), "epoch 73 plain Ravage");
    assert_eq!(old, crate::rules::unit_rating(&old_rules, "Ravage"), "epoch 72 plain Ravage");
    assert_eq!(new, old, "the plain Ravage stamp is epoch-invariant");
}
