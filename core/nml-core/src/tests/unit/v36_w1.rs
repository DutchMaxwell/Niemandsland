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

/// D-MOST: one row of the "most models" case table. test/v36/w1_4_test.gd carries the same
/// rows under the same names, so both engines answer every row alike.
struct MostCase {
    name: &'static str,
    host_rules: &'static [&'static str],
    host_models: i64,
    host_dead: i64,
    /// Each joined hero: its own rules, and whether it still lives.
    heroes: &'static [(&'static [&'static str], bool)],
    solo: bool,
    want: bool,
}

const PLAIN_HERO: (&[&str], bool) = (&["Hero"], true);
const FEARLESS_HERO: (&[&str], bool) = (&["Hero", "Fearless"], true);

#[rustfmt::skip]
const MOST_CASES: &[MostCase] = &[
    MostCase { name: "three host models with it, two joined heroes without: 3 of 5, on", host_rules: &["Fearless"], host_models: 3, host_dead: 0, heroes: &[PLAIN_HERO, PLAIN_HERO], solo: false, want: true },
    MostCase { name: "one host model with it, one joined hero without: an exact half, off", host_rules: &["Fearless"], host_models: 1, host_dead: 0, heroes: &[PLAIN_HERO], solo: false, want: false },
    MostCase { name: "one host model without it, a joined hero with it: 1 of 2, off", host_rules: &[], host_models: 1, host_dead: 0, heroes: &[FEARLESS_HERO], solo: false, want: false },
    MostCase { name: "two host models without it, a joined hero with it: 1 of 3, off", host_rules: &[], host_models: 2, host_dead: 0, heroes: &[FEARLESS_HERO], solo: false, want: false },
    MostCase { name: "a Tough(6) joined hero without it is one model, not six wounds: 2 of 3, on", host_rules: &["Fearless"], host_models: 2, host_dead: 0, heroes: &[(&["Hero", "Tough(6)"], true)], solo: false, want: true },
    MostCase { name: "a Tough(6) joined hero with it is one model, not six wounds: 1 of 3, off", host_rules: &[], host_models: 2, host_dead: 0, heroes: &[(&["Hero", "Fearless", "Tough(6)"], true)], solo: false, want: false },
    MostCase { name: "a Tough(3) host model with it is one model, not three wounds: 1 of 3, off", host_rules: &["Fearless", "Tough(3)"], host_models: 1, host_dead: 0, heroes: &[PLAIN_HERO, PLAIN_HERO], solo: false, want: false },
    MostCase { name: "a lone hero keeps its own rule", host_rules: &["Hero", "Fearless"], host_models: 1, host_dead: 0, heroes: &[], solo: false, want: true },
    MostCase { name: "a lone hero without the rule stays off", host_rules: &["Hero"], host_models: 1, host_dead: 0, heroes: &[], solo: false, want: false },
    MostCase { name: "dead host models without it do not count: 2 of 3 living, on", host_rules: &[], host_models: 3, host_dead: 2, heroes: &[FEARLESS_HERO, FEARLESS_HERO], solo: false, want: true },
    MostCase { name: "dead host models with it do not count: 1 of 3 living, off", host_rules: &["Fearless"], host_models: 3, host_dead: 2, heroes: &[PLAIN_HERO, PLAIN_HERO], solo: false, want: false },
    MostCase { name: "a fallen joined hero without it does not count: 1 of 1, on", host_rules: &["Fearless"], host_models: 1, host_dead: 0, heroes: &[(&["Hero"], false)], solo: false, want: true },
    MostCase { name: "a wiped-out unit has no majority", host_rules: &["Fearless"], host_models: 2, host_dead: 2, heroes: &[], solo: false, want: false },
    MostCase { name: "solo: the picked host model answers from its own unit, on", host_rules: &["Fearless"], host_models: 1, host_dead: 0, heroes: &[PLAIN_HERO, PLAIN_HERO], solo: true, want: true },
    MostCase { name: "solo: the collapse never borrows the heroes' rule, off", host_rules: &[], host_models: 1, host_dead: 0, heroes: &[FEARLESS_HERO, FEARLESS_HERO], solo: true, want: false },
    MostCase { name: "solo: a host with no living model is off", host_rules: &["Fearless"], host_models: 1, host_dead: 1, heroes: &[], solo: true, want: false },
];

/// The core reads a unit's living model count off the live state, and its per-activation
/// profile lists only the living joined heroes (a fallen hero drops out of
/// `attached_hero_rules`), so the fixture hands the reader exactly that.
fn most_of(c: &MostCase) -> bool {
    let mut p: crate::state::Profile =
        serde_json::from_str(r#"{"unit_id":"host","name":"Host"}"#).unwrap();
    p.special_rules = c.host_rules.iter().map(|r| r.to_string()).collect();
    p.attached_hero_rules = c
        .heroes
        .iter()
        .filter(|(_, alive)| *alive)
        .map(|(rules, _)| rules.iter().map(|r| r.to_string()).collect())
        .collect();
    crate::unit::rule_on_most_models(&p, c.host_models - c.host_dead, "Fearless", c.solo)
}

#[test]
fn rule_on_most_models_answers_the_shared_case_table() {
    for c in MOST_CASES {
        assert_eq!(most_of(c), c.want, "{}", c.name);
    }
}

/// The one majority test the morale rows count live state with: strictly more than half.
#[test]
fn most_models_of_needs_a_strict_majority() {
    assert!(!crate::unit::most_models_of(1, 2), "an exact half is not most");
    assert!(crate::unit::most_models_of(2, 3), "2 of 3 is most");
    assert!(!crate::unit::most_models_of(0, 0), "an empty unit has no majority");
    assert!(crate::unit::most_models_of(1, 1), "1 of 1 is most");
    assert!(!crate::unit::most_models_of(2, 5), "2 of 5 is not most");
}
