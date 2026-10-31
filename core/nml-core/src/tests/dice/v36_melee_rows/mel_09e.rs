//! MEL-09e: the AI's melee EV twin of MEL-09. From `EPOCH_73_V36` a fatigued striker's sixes still
//! hit but fire no rule, so `profile_ev` prices its whole on-6 AP sub-batch at zero (Rending's +4
//! included); epoch 72 keeps the bonus. The table twin is test/v36/mel_09e_test.gd.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

fn rending() -> ShootProfile {
    ShootProfile { rending: true, ..blade(12) }
}

/// The EV of a Quality 4 striker's 12-attack melee profile into a Defense 4 unit of 10.
fn ev(p: &ShootProfile, fatigued: bool, epoch: u32) -> f64 {
    let att = Ctx { quality: 4, fatigued, rules_epoch: epoch, ..Default::default() };
    crate::combat::profile_ev(p, 12, &att, &defender(4, 10), 0.0, false)
}

#[test]
fn fatigued_rending_ev_still_rends_at_epoch_72() {
    assert!(
        ev(&rending(), true, EPOCH_72_PLAYTEST_RULES) > ev(&blade(12), true, EPOCH_72_PLAYTEST_RULES),
        "72: a fatigued striker's sixes still save at AP(+4)"
    );
}

#[test]
fn fatigued_rending_ev_drops_the_on6_bonus_at_epoch_73() {
    let rending_ev = ev(&rending(), true, EPOCH_73_V36);
    let plain_ev = ev(&blade(12), true, EPOCH_73_V36);
    assert!(
        (rending_ev - plain_ev).abs() < 1e-12,
        "73: the muted sixes save at the plain Defense ({rending_ev} vs {plain_ev})"
    );
}

#[test]
fn a_fresh_rending_striker_still_rends_in_the_ev_at_epoch_73() {
    assert!(
        ev(&rending(), false, EPOCH_73_V36) > ev(&blade(12), false, EPOCH_73_V36),
        "a rested rending strike keeps the AP(+4) on its sixes"
    );
}
