//! The Versatile mode of a human shooter's volley is the player's pick, asked through the
//! core as a `NeedChoice` (`versatile_mode:<unit>`, options `ap` / `hit`), where the volley decides it (the first eligible shot).

use super::*;
use crate::activation::{step_activation, ActStep, Input};

/// "a" (buff_line, its Rifle Versatile) holds and shoots "b" over 9" away; every roll answered with sixes, `choice` appended.
fn run(st: &State, statics: &[UnitStatic], choice: Option<&str>) -> ActStep {
    let seams = Seams { rules_epoch: 95, ..Seams::default() };
    let board = crate::terrain::Terrain::default();
    let mut t = vec![Input::Begin, Input::Intent { kind: HOLD, shoot: Some("b".into()), split: None, charge: None, no_step: false }];
    t.extend(choice.map(|o| Input::Choice { id: "versatile_mode:a".into(), option: o.into() }));
    for _ in 0..40 {
        match step_activation(statics, st, "a", &board, seams, &t, false) {
            ActStep::NeedRoll { faces, .. } => t.push(Input::Faces(vec![6; faces])),
            other => return other,
        }
    }
    panic!("no end in 40 steps")
}

fn picked(a: ActStep) -> i64 {
    let ActStep::Done { state, .. } = a else { panic!("{a:?}") };
    state.versatile_pick_mode[0]
}

/// RED before: the kind did not exist (the probe was refused as an unknown choice kind). The probe asks, owned by the shooter;
/// each answer is the mode the volley rolls with and the latch the delta carries; no choice = the core's best mode.
#[test]
fn the_versatile_mode_is_the_players_pick() {
    let (st, mut statics) = buff_line();
    statics[0].shoot[0].versatile_attack = true;
    let ActStep::NeedChoice { id, options, owner, .. } = run(&st, &statics, Some("")) else { panic!("the probe asks") };
    assert_eq!((id.as_str(), options, owner.as_str()), ("versatile_mode:a", vec!["ap".to_string(), "hit".to_string()], "a"));
    assert_eq!(picked(run(&st, &statics, Some("ap"))), 2, "AP(+1) latched");
    assert_eq!(picked(run(&st, &statics, Some("hit"))), 1, "+1 to hit latched");
    assert!(picked(run(&st, &statics, None)) > 0, "no choice: the core's own best mode");
    assert!(matches!(run(&st, &statics, Some("both")), ActStep::Refused { .. }), "not an option");
}
