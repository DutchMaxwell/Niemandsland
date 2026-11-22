//! D-PAR3 14b: `Input::Paid { dangerous, beats }` - what the table resolved before it captured the core's board (its Dangerous
//! test, its casts and pre-attack beats) does not run again on the step path; the first die asked is the next section's.

use super::*;
use crate::activation::{step_activation, ActStep, Input};

fn paid(dangerous: bool, beats: bool) -> Input {
    Input::Paid { start: false, dangerous, beats }
}

/// (count, target, owner) of the first die the step path asks for.
fn first_roll(a: ActStep) -> Option<(i64, i64, String)> {
    match a {
        ActStep::NeedRoll { count, target, owner, .. } => Some((count, target, owner)),
        _ => None,
    }
}

/// `buff_line`'s "a" holds on `dangerous_bar_board`'s Dangerous cells and shoots "b". Unpaid, the first die is the standing test
/// (2 dice at 6+, F-DANG-HOLD) and the volley's comes after it; with `paid { dangerous }` the volley's die is asked first.
#[test]
fn paid_dangerous_skips_the_test() {
    let (mut st, statics) = buff_line();
    st.positions[0] = vec![[4.0 * IN2M, 0.0, 0.0], [4.02 * IN2M, 0.0, 0.0]];
    let board = dangerous_bar_board();
    let seams = Seams { rules_epoch: 95, ..Seams::default() };
    let hold = Input::Intent { kind: HOLD, shoot: Some("b".into()), split: None, charge: None };
    let ask = |t: &[Input]| first_roll(step_activation(&statics, &st, "a", &board, seams, t, true));
    assert_eq!(ask(&[Input::Begin, hold.clone()]), Some((2, DANGEROUS_TARGET, "a".to_string())), "unpaid: the test first");
    let volley = ask(&[Input::Begin, hold.clone(), Input::Faces(vec![6, 6])]).expect("the volley's die after the test");
    assert_eq!(ask(&[Input::Begin, paid(true, false), hold]), Some(volley), "paid: the volley's die first");
}

/// A Storm bearer holds: unpaid, the burst asks for its dice; with `paid { beats }` nothing is asked (no beat, no volley).
#[test]
fn paid_beats_skip_the_storm() {
    let (st, statics) = storm_line("Storm of Change", "wormhole_daemons_of_change", 95);
    let board = crate::terrain::Terrain::default();
    let seams = Seams { rules_epoch: 95, ..Seams::default() };
    let hold = Input::Intent { kind: HOLD, shoot: None, split: None, charge: None };
    let step = |t: &[Input]| step_activation(&statics, &st, "a", &board, seams, t, true);
    assert!(first_roll(step(&[Input::Begin, hold.clone()])).is_some(), "unpaid: the burst rolls");
    assert!(matches!(step(&[Input::Begin, paid(false, true), hold]), ActStep::Done { .. }), "paid: no die");
}
