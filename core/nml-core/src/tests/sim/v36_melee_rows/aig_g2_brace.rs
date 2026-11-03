//! AI gate AI-G2 (rules 3.6): a UNIT rule the faction map resolves to the Brace primitive ("Brace in
//! Melee") blunts a charge like a Brace weapon, from `EPOCH_73_V36` on, and the log names the book rule.
//! Every case is the real `build_for` product through the real registry and the real charge. Twin:
//! test/v36/aig_g2_brace_test.gd.
use super::mel_04::charge_with;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// Control: the Brace weapon keeps its cut and its own name.
#[test]
fn a_brace_weapon_still_takes_one_die_under_its_own_name() {
    let (dice, lines) = charge_with(EPOCH_73_V36, 3, 2, &[], true, false, false);
    assert_eq!(dice, 2, "Impact(3) into two Brace(1) models");
    assert!(lines.iter().any(|l| l == "Brace: Defender takes 1 Impact dice off Charger"), "{lines:?}");
}

/// Control: below the 3.6 epoch the unit rule replays as before (nothing taken off, nothing logged).
#[test]
fn below_epoch_73_brace_in_melee_stays_inert() {
    let (dice, lines) = charge_with(EPOCH_72_PLAYTEST_RULES, 3, 2, &["Brace in Melee"], false, false, false);
    assert_eq!(dice, 3, "epoch 72 replays today's dice");
    assert!(!lines.iter().any(|l| l.contains("Brace")), "{lines:?}");
}

#[test]
fn brace_in_melee_takes_one_impact_die_and_logs_its_own_name() {
    let (dice, lines) = charge_with(EPOCH_73_V36, 3, 2, &["Brace in Melee"], false, false, false);
    assert_eq!(dice, 2, "the map's rating 1 comes off the three Impact dice");
    assert!(lines.iter().any(|l| l == "Brace in Melee: Defender takes 1 Impact dice off Charger"), "{lines:?}");
}

#[test]
fn a_fatigued_unit_with_brace_in_melee_takes_nothing_and_logs_its_name() {
    let (dice, lines) = charge_with(EPOCH_73_V36, 3, 2, &["Brace in Melee"], false, false, true);
    assert_eq!(dice, 3, "a Fatigued braced unit removes nothing");
    assert!(lines.iter().any(|l| l == "Brace in Melee: no effect, Defender is Fatigued"), "{lines:?}");
}

/// The map is the reader, not the name: a rated unit-level Brace(2) cuts its printed X once.
#[test]
fn a_rated_unit_rule_brace_cuts_its_printed_rating() {
    let (dice, lines) = charge_with(EPOCH_73_V36, 3, 2, &["Brace(2)"], false, false, false);
    assert_eq!(dice, 1, "Impact(3) minus Brace(2)");
    assert!(lines.iter().any(|l| l == "Brace: Defender takes 2 Impact dice off Charger"), "{lines:?}");
}
