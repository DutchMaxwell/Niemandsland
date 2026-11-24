//! `Input::Intent { no_step }` - a human Hit & Run bearer's post-attack step is the player's own
//! drag, so the core's step path takes none; without the flag the core steps as before.

use super::*;
use crate::activation::{step_activation, ActStep, Input};

/// "a" (buff_line, Hit & Run) holds and shoots "b"; every roll answered with sixes. The state at the end.
fn after(st: &State, statics: &[UnitStatic], no_step: bool) -> State {
    let seams = Seams { rules_epoch: 95, ..Seams::default() };
    let board = crate::terrain::Terrain::default();
    let mut t = vec![Input::Begin, Input::Intent { kind: HOLD, shoot: Some("b".into()), split: None, charge: None, no_step }];
    for _ in 0..40 {
        match step_activation(statics, st, "a", &board, seams, &t, false) {
            ActStep::NeedRoll { faces, .. } => t.push(Input::Faces(vec![6; faces])),
            ActStep::Done { state, .. } => return state,
            other => panic!("{other:?}"),
        }
    }
    panic!("no end in 40 steps")
}

/// RED before: the flag did not exist (the core always stepped). Without it the bearer steps and stamps the round; with it
/// the models stay where they shot from and the once-per-round stamp stays open for the player's own step.
#[test]
fn no_step_keeps_the_hit_and_run_bearer_in_place() {
    let (st, mut statics) = buff_line();
    statics[0].hit_and_run_active = true;
    statics[1].hit_and_run_active = true; // its joined hero "ah" carries it too (rules 3.6: every model)
    let stepped = after(&st, &statics, false);
    assert_ne!(stepped.positions[0], st.positions[0], "control: without no_step the core takes the step");
    assert_eq!(stepped.hit_and_run_round[0], stepped.round);
    let held = after(&st, &statics, true);
    assert_eq!(held.positions[0], st.positions[0], "no_step: the player drags it");
    assert_ne!(held.hit_and_run_round[0], held.round, "the round's step is still open");
}
