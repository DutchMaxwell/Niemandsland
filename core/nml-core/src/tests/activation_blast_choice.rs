//! Step 29b (ruling D-29-R1, "defender picks how"): the even Blast split's remainder is the defender's choice
//! `blast_split:<shooter>:<target>` on the step API; without an answer the core's own (target first) stands.
use super::*;
use crate::acts::EPOCH_108_BLAST_EVEN;
use crate::sim::tests::volley_landings::volley_line;
use crate::IN2M;
use crate::unit::ShootProfile;
use Input::{Begin, Faces};
use std::rc::Rc;

const ID: &str = "blast_split:a:b";

/// `volley_line` in Firefight: "a" fires one Blast(3) shot at "b" (two models); "bh" (two models, b's side) stands 1 in
/// from it, inside the spread. One hit: 3 hits over two units with room 2 each - 1 + 1 and one remainder to place.
fn blast_line() -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = volley_line();
    let mut p = st.profiles.list[0].clone();
    p.game_system = "gff".into();
    st.profiles = Rc::new(crate::state::Profiles { list: vec![p; 4], index: Default::default() });
    st.positions[3] = vec![[9.0 * IN2M, 0.0, 0.0], [9.0 * IN2M, 0.0, 2.5 * IN2M]];
    (st.wounds[3], st.alive[3]) = (vec![1, 1], 2);
    Rc::make_mut(&mut st.radii)[3] = vec![IN2M; 2];
    statics[0].shoot = vec![ShootProfile { name: "mortar".into(), attacks: 1, count: 1, range: 24, blast: 3, ..Default::default() }];
    statics[3].model_count = 2;
    (st, statics)
}

/// Every die a 6 (one hit, every save passes); the answer and the save roll counts in order.
fn play(epoch: u32, choice: Option<&str>) -> (ActStep, Vec<i64>) {
    let (st, mut statics) = blast_line();
    statics.iter_mut().for_each(|u| u.ctx.rules_epoch = epoch);   // `ctx_for` stamps the record's epoch in a real game
    let seams = Seams { rules_epoch: epoch, tray_exact: true, ..Seams::default() };
    let mut t = vec![Begin, Input::Intent { kind: HOLD, shoot: Some("b".into()), split: None, charge: None, no_step: false }];
    if let Some(o) = choice {
        t.push(Input::Choice { id: ID.into(), option: o.into() });
    }
    let mut saves = Vec::new();
    loop {
        match step_activation(&statics, &st, "a", &Terrain::default(), seams, &t, true) {
            ActStep::NeedRoll { faces, kind, count, .. } => {
                if kind == "defense" {
                    saves.push(count);
                }
                t.push(Faces(vec![6; faces]));
            }
            other => return (other, saves),
        }
    }
}

#[test]
fn the_defender_is_asked_who_takes_the_remainder() {
    match play(EPOCH_108_BLAST_EVEN, Some("")).0 {
        ActStep::NeedChoice { id, options, owner, .. } => {
            assert_eq!((id.as_str(), owner.as_str()), (ID, "b"));
            assert_eq!(options, vec!["b".to_string(), "bh".to_string()]);
        }
        other => panic!("expected NeedChoice, got {other:?}"),
    }
}

#[test]
fn the_answer_moves_the_remainder_and_no_answer_keeps_the_target_first() {
    let (done, saves) = play(EPOCH_108_BLAST_EVEN, None);
    assert!(matches!(done, ActStep::Done { .. }), "{done:?}");
    assert_eq!(saves.first(), Some(&2), "the core's own: the target takes the remainder: {saves:?}");
    let (done, saves) = play(EPOCH_108_BLAST_EVEN, Some("bh"));
    assert!(matches!(done, ActStep::Done { .. }), "{done:?}");
    assert_eq!(saves.first(), Some(&1), "the defender put it on bh: {saves:?}");
    match play(EPOCH_108_BLAST_EVEN, Some("ah")).0 {
        ActStep::Refused { reason, .. } => assert_eq!(reason, "ah is not an option of blast_split:a:b (options: b | bh)"),
        other => panic!("expected Refused, got {other:?}"),
    }
}

#[test]
fn below_the_epoch_nothing_is_asked() {
    let (done, saves) = play(crate::acts::EPOCH_107_RUIN_LEDGES, Some(""));
    assert!(matches!(done, ActStep::Done { .. }), "below the epoch the split is the old one, no choice: {done:?}");
    assert_eq!(saves.first(), Some(&2));
}
