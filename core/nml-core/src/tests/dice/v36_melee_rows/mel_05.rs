//! MEL-05 tests (rules 3.6, lane melee): the charge's Impact pools lose their Counter term at
//! `EPOCH_73_V36`; the epoch-72 leg keeps the defender's Counter models cutting the dice.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::Profile;

fn build(unit_id: &str, rules: &[&str], models: i64, epoch: u32) -> UnitStatic {
    let mut p: Profile = serde_json::from_str(&format!(
        r#"{{"unit_id":"{unit_id}","name":"{unit_id}","game_system":"aof","faction_folder":"ratmen"}}"#
    ))
    .unwrap();
    p.special_rules = rules.iter().map(|r| (*r).to_string()).collect();
    p.model_count = models;
    p.wounds_max = vec![1; models as usize];
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &p, epoch)
}

/// The plain Impact pool's dice on a one-model Impact(3) charge.
fn impact_dice(epoch: u32, defender_rules: &[&str]) -> i64 {
    let att = build("charger", &["Impact(3)"], 1, epoch);
    let def = build("defender", defender_rules, 2, epoch);
    let pools = impact_pools(&att.ctx, &def.ctx);
    pools[0].0 + pools[1].0
}

#[test]
fn a_counter_unit_takes_two_impact_dice_away_at_epoch_72() {
    assert_eq!(impact_dice(EPOCH_72_PLAYTEST_RULES, &["Counter"]), 1, "3 dice minus 2 Counter models");
}

#[test]
fn a_counter_unit_takes_no_impact_dice_away_at_epoch_73() {
    assert_eq!(impact_dice(EPOCH_73_V36, &["Counter"]), 3, "rules 3.6 keeps all three Impact dice");
}

#[test]
fn a_defender_without_counter_changes_nothing_at_either_epoch() {
    assert_eq!(impact_dice(EPOCH_72_PLAYTEST_RULES, &[]), 3);
    assert_eq!(impact_dice(EPOCH_73_V36, &[]), 3);
}
