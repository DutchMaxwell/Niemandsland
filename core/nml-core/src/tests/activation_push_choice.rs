//! Step 29d-1a (ruling D-29-R2): the step API routes the attacker's push choices - `push:<attacker>:<target>` (push | no)
//! and its free-answer spot `push_to:<attacker>:<target>` - instead of a pre-declared `Input::Push`. 29d-1b makes the
//! volley reach them; here the routing and the tray's free-answer choice on their own.
use super::*;
use crate::sim::tests::volley_landings::volley_line;
use Input::{Begin, Choice};

fn step(t: &[Input]) -> ActStep {
    let (st, statics) = volley_line();
    step_activation(&statics, &st, "a", &Terrain::default(), Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() }, t, true)
}

fn intent() -> Input {
    Input::Intent { kind: HOLD, shoot: Some("b".into()), split: None, charge: None, no_step: false }
}

#[test]
fn the_push_choices_are_known_kinds_and_a_bad_answer_names_the_options() {
    for (id, o) in [("push:a:b", "push"), ("push:a:b", "no"), ("push_to:a:b", "0:0.3,0,0")] {
        if let ActStep::Refused { reason, .. } = step(&[Begin, intent(), Choice { id: id.into(), option: o.into() }]) {
            assert!(!reason.starts_with("unknown choice kind"), "{id} {o}: {reason}");
        }
    }
    match step(&[Begin, intent(), Choice { id: "push:a:b".into(), option: "maybe".into() }]) {
        ActStep::Refused { reason, .. } => assert_eq!(reason, "maybe is not an option of push:a:b (options: push, no)"),
        other => panic!("expected Refused, got {other:?}"),
    }
}

#[test]
fn a_free_choice_is_reached_once_answered_and_refused_with_its_reason() {
    let mut tray = crate::dice::Tray::supplied(vec![]);
    tray.offer_free("push_to:a:b".into(), Some("0:1,0,0".into()));
    assert_eq!(tray.reach_free("push_to:a:b", "a").as_deref(), Some("0:1,0,0"));
    assert_eq!(tray.reach_free("push_to:a:b", "a").as_deref(), Some("0:1,0,0"), "a second reach reads the same answer");
    tray.refuse_free("push_to:a:b", "Push: too far".into());
    let c = &tray.feed().unwrap().free_choices[0];
    assert_eq!((c.reached.as_ref().map(|r| r.1.as_str()), c.bad.as_deref()), (Some("a"), Some("Push: too far")));
    assert_eq!(tray.reach_free("push_to:x:y", "a"), None, "an id nobody offered");
    let mut seeded = crate::dice::Tray::seeded(1);
    seeded.offer_free("push_to:a:b".into(), Some("0:1,0,0".into()));
    assert_eq!(seeded.reach_free("push_to:a:b", "a"), None, "a seeded tray keeps no choices");
}
