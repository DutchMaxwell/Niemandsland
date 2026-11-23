//! The human spot-marker offer (OD-2: a player's own pick is asked of the player through the core): Precision Spotter markers on the
//! target MAY be removed by an attacker before rolling to hit (+1 to hit each). The table asks the human how many
//! (`_solo_offer_spot_markers`, 0..N) and the AI takes them all. The step path asks `spot_markers:<shooter>:<target>`, options 0..N.

use super::*;
use crate::activation::{step_activation, ActStep, Input};

/// "a" (buff_line) holds and shoots "b", which carries two spot markers; every roll answered with sixes, `answer` appended.
fn run(answer: Option<&str>) -> ActStep {
    let (mut st, statics) = buff_line();
    st.spot_markers[2] = 2;
    let seams = Seams { rules_epoch: 95, ..Seams::default() };
    let board = crate::terrain::Terrain::default();
    let mut t = vec![Input::Begin, Input::Intent { kind: HOLD, shoot: Some("b".into()), split: None, charge: None, no_step: false }];
    t.extend(answer.map(|o| Input::Choice { id: "spot_markers:a:b".into(), option: o.into() }));
    for _ in 0..40 {
        match step_activation(&statics, &st, "a", &board, seams, &t, false) {
            ActStep::NeedRoll { faces, .. } => t.push(Input::Faces(vec![6; faces])),
            other => return other,
        }
    }
    panic!("no end in 40 steps")
}

/// RED before: the kind did not exist (the probe was refused as an unknown choice kind) and every marker was spent. The probe asks the
/// shooter's side; an answer removes that many (the rest stay, the line says so); no choice takes all, the AI's rule; 3 is no option.
#[test]
fn the_attacker_picks_how_many_spot_markers_to_remove() {
    let ActStep::NeedChoice { id, options, owner, .. } = run(Some("")) else { panic!("the probe asks") };
    assert_eq!((id.as_str(), options, owner.as_str()), ("spot_markers:a:b", vec!["0".to_string(), "1".into(), "2".into()], "a"));
    let ActStep::Done { state, lines, .. } = run(Some("1")) else { panic!("one marker") };
    assert_eq!(state.spot_markers[2], 1, "one marker stays");
    assert!(lines.iter().any(|l| l.text == "Precision Spotter: 1 marker removed — +1 to hit this volley (1 remains)"), "{lines:?}");
    let ActStep::Done { state, .. } = run(Some("0")) else { panic!("none") };
    assert_eq!(state.spot_markers[2], 2, "0: nothing removed");
    let ActStep::Done { state, .. } = run(None) else { panic!("no choice") };
    assert_eq!(state.spot_markers[2], 0, "no choice: all of them, as before");
    assert!(matches!(run(Some("3")), ActStep::Refused { .. }), "3 is not an option");
}
