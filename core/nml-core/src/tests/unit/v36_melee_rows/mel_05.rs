//! MEL-05 tests (rules 3.6, lane melee): Counter no longer cuts the charger's Impact dice from
//! `EPOCH_73_V36`; the epoch-72 leg keeps the cut. Brace is the only Impact cut from 73 on.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// A two-model unit carrying the plain unit-wide Counter rule.
fn counter_unit_at(epoch: u32) -> UnitStatic {
    let mut p: Profile = serde_json::from_str(
        r#"{"unit_id":"counter","name":"Counter Unit","game_system":"aof","faction_folder":"ratmen"}"#,
    )
    .unwrap();
    p.special_rules = vec!["Counter".into()];
    p.model_count = 2;
    p.wounds_max = vec![1, 1];
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &p, epoch)
}

/// A two-model unit without any Counter rule.
fn plain_unit_at(epoch: u32) -> UnitStatic {
    let mut p: Profile = serde_json::from_str(
        r#"{"unit_id":"plain","name":"Plain Unit","game_system":"aof","faction_folder":"ratmen"}"#,
    )
    .unwrap();
    p.model_count = 2;
    p.wounds_max = vec![1, 1];
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, &p, epoch)
}

#[test]
fn a_counter_unit_cuts_impact_at_epoch_72() {
    let us = counter_unit_at(EPOCH_72_PLAYTEST_RULES);
    assert_eq!(us.ctx.counter_models, 2, "both Counter models deny Impact");
    assert_eq!(us.ctx.counter_impact_per_model, Some(1), "the Counter entry's own magnitude");
}

#[test]
fn a_counter_unit_cuts_no_impact_at_epoch_73() {
    let us = counter_unit_at(EPOCH_73_V36);
    assert_eq!(us.ctx.counter_models, 0, "rules 3.6: Counter takes no Impact dice away");
    assert_eq!(us.ctx.counter_impact_per_model, None, "no Counter cut is stamped at 73");
}

#[test]
fn a_unit_without_counter_has_no_reduction_at_either_epoch() {
    let old = plain_unit_at(EPOCH_72_PLAYTEST_RULES);
    let new = plain_unit_at(EPOCH_73_V36);
    assert_eq!(old.ctx.counter_models, 0);
    assert_eq!(new.ctx.counter_models, 0);
    assert_eq!(crate::combat::impact_total_dice(3, 2, 0), 6, "no Counter models, no Impact cut");
}
