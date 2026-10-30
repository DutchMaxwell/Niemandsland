//! Rules 3.6 lane w1 tests for the unit module; owned by lane w1.
use crate::acts::{rule_on, CURRENT_RULES_EPOCH, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// D-EPOCH: the whole rules 3.6 wave shares one epoch, and it is the live one, so a fresh
/// `play_game()` stamps it and every 3.6 gate written against `EPOCH_73_V36` is on.
#[test]
fn the_rules_3_6_wave_is_the_live_epoch_73() {
    assert_eq!(EPOCH_73_V36, 73, "the rules 3.6 wave's one frozen epoch");
    assert_eq!(CURRENT_RULES_EPOCH, EPOCH_73_V36, "the live epoch is EPOCH_73_V36");
    assert!(rule_on(CURRENT_RULES_EPOCH, EPOCH_73_V36), "a fresh record gets the 3.6 gates");
}

/// The old leg: the play-test fixes keep their own frozen gate, and a record stamped with it
/// gets none of the rules 3.6 behaviour.
#[test]
fn a_record_at_epoch_72_gets_no_rules_3_6_gate() {
    assert_eq!(EPOCH_72_PLAYTEST_RULES, 72, "the play-test fixes' gate stays frozen at 72");
    assert!(rule_on(EPOCH_72_PLAYTEST_RULES, EPOCH_72_PLAYTEST_RULES), "72 keeps its own rules");
    assert!(!rule_on(EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36), "72 is below every 3.6 gate");
    assert!(rule_on(EPOCH_73_V36, EPOCH_72_PLAYTEST_RULES), "73 keeps the play-test fixes");
}
