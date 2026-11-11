//! MEL-08 tests (rules 3.6, lane melee); empty until the row lands - start with `use super::super::*;`.

// MEL-08 — strike reach. Rules 3.6 records (`EPOCH_73_V36`) let a model strike from 3" across and 3" up;
// the 3.5 records (epoch 72 and below) keep 2" across and 4" up. Centre space folds the 1" base contact
// onto the reach, exactly as `combat::striking_models` measures it.
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::combat::striking_models;
use crate::IN2M;

const ENEMY: [[f64; 3]; 1] = [[0.0, 0.0, 0.0]];

/// 2.5" past base contact = 3.5" centre to centre: inside the 3.6 reach only.
fn two_and_a_half_out() -> [[f64; 3]; 1] {
    [[3.5 * IN2M, 0.0, 0.0]]
}

/// 3.5" above the enemy, 1" across: inside the old 4" vertical reach only.
fn three_and_a_half_up() -> [[f64; 3]; 1] {
    [[IN2M, 3.5 * IN2M, 0.0]]
}

#[test]
fn a_model_2_5in_beyond_contact_strikes_at_epoch_73() {
    assert_eq!(striking_models(&two_and_a_half_out(), &ENEMY, EPOCH_73_V36), 1);
}

#[test]
fn a_model_2_5in_beyond_contact_stays_out_at_epoch_72() {
    assert_eq!(striking_models(&two_and_a_half_out(), &ENEMY, EPOCH_72_PLAYTEST_RULES), 0);
}

#[test]
fn a_model_3_5in_above_stays_out_at_epoch_73() {
    assert_eq!(striking_models(&three_and_a_half_up(), &ENEMY, EPOCH_73_V36), 0);
}

#[test]
fn a_model_3_5in_above_strikes_at_epoch_72() {
    assert_eq!(striking_models(&three_and_a_half_up(), &ENEMY, EPOCH_72_PLAYTEST_RULES), 1);
}

/// The ten-model line of combat.rs' epoch-72 pin: one more model reaches under 3.6.
#[test]
fn a_ten_model_line_strikes_with_four_at_epoch_73() {
    let line: Vec<[f64; 3]> = (1..=10).map(|i| [i as f64 * IN2M, 0.0, 0.0]).collect();
    assert_eq!(striking_models(&line, &ENEMY, EPOCH_73_V36), 4);
}
