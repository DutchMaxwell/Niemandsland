//! Step 29d-1a (ruling D-29-R2): the step API routes the attacker's push choices - `push:<attacker>:<target>` (push | no)
//! and its free-answer spot `push_to:<attacker>:<target>` - instead of a pre-declared `Input::Push`. 29d-1b makes the
//! volley reach them (29d-1b: the tests from `push_line` on).
use super::*;
use crate::sim::tests::volley_landings::volley_line;
use crate::state::{Profiles, Roster};
use crate::unit::{Ctx, ShootProfile};
use crate::IN2M;
use std::rc::Rc;
use Input::{Begin, Choice, Faces};

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

/// "a" (gff, 6 shots at Quality 2) fires at "b": two models 12 in east, Defense 6, Quality 6. One hit, one failed save and a
/// failed morale test leave b Shaken - the push holds.
fn push_line() -> (State, Vec<UnitStatic>) {
    let mut st = crate::sim::tests::four_unit_line();
    let keys = st.roster.keys.clone();
    st.roster = Rc::new(Roster { index: keys.iter().cloned().zip(0..).collect(), keys, profile: vec![0, 1, 2, 3] });
    let mut p = st.profiles.list[0].clone();
    p.game_system = "gff".into();
    st.profiles = Rc::new(Profiles { list: vec![p; 4], index: Default::default() });
    let at = |x: f64, z: f64| [x * IN2M, 0.0, z * IN2M];
    let n = if PLAY3.with(|f| f.get()) { 4 } else { 2 };
    st.positions = vec![vec![at(0.0, 0.0)], vec![at(-30.0, 0.0)], (0..n).map(|k| at(12.0, 1.5 * k as f64)).collect(), vec![at(30.0, 20.0)]];
    st.radii = Rc::new(vec![vec![0.5 * IN2M], vec![0.5 * IN2M], vec![0.5 * IN2M; n], vec![0.5 * IN2M]]);
    st.wounds = vec![vec![1], vec![1], vec![1; n], vec![1]];
    st.alive = vec![1, 1, n as i64, 1];
    let gun = ShootProfile { name: "Rifle".into(), attacks: 6, count: 1, range: 24, ..Default::default() };
    let unit = |name: &str, n: i64, q: i64, shoot: Vec<ShootProfile>| UnitStatic {
        name: name.into(), shoot, model_count: n, wounds_max: vec![1; n as usize],
        ctx: Ctx { quality: q, defense: 6, models: n, rules_epoch: crate::acts::CURRENT_RULES_EPOCH, ..Default::default() }, ..Default::default()
    };
    (st, vec![unit("Gunners", 1, 2, vec![gun]), unit("Spare", 1, 4, vec![]), unit("Target", n as i64, 6, vec![]), unit("Far", 1, 4, vec![])])
}

/// The answers in `choices`; one hit (6 then five 1s), every save and morale die a 1, the push die `push_face`.
fn play(choices: &[(&str, &str)], push_face: u8) -> (ActStep, State) {
    let (st, statics) = push_line();
    let seams = Seams { rules_epoch: crate::acts::CURRENT_RULES_EPOCH, tray_exact: true, ..Seams::default() };
    let mut t = vec![Begin, Input::Intent { kind: HOLD, shoot: Some("b".into()), split: None, charge: None, no_step: false }];
    t.extend(choices.iter().map(|(id, o)| Choice { id: (*id).into(), option: (*o).into() }));
    loop {
        match step_activation(&statics, &st, "a", &Terrain::default(), seams, &t, true) {
            ActStep::NeedRoll { faces, kind, .. } => t.push(Faces(match kind {
                "attack" => {
                    let hits = if PLAY3.with(|f| f.get()) { 2 } else { 1 };
                    [vec![6; hits], vec![1; faces.saturating_sub(hits)]].concat()
                }
                "push" => vec![push_face],
                _ => vec![1; faces],
            })),
            ActStep::Done { ref state, .. } => {
                let s = state.clone();
                return (ActStep::Done { state: s.clone(), lines: Vec::new(), landings: Vec::new(), unported: Vec::new() }, s);
            }
            other => return (other, st),
        }
    }
}

fn spot(slot: usize, x_in: f64) -> String {
    format!("{slot}:{},0,0", x_in * IN2M)
}

#[test]
fn the_attacker_is_asked_after_the_dice() {
    match play(&[("push:a:b", "")], 5).0 {
        ActStep::NeedChoice { id, options, owner, .. } => {
            assert_eq!((id.as_str(), owner.as_str()), ("push:a:b", "a"));
            assert_eq!(options, vec!["push".to_string(), "no".to_string()]);
        }
        other => panic!("expected NeedChoice, got {other:?}"),
    }
}

#[test]
fn a_yes_rolls_the_die_then_asks_the_spot() {
    match play(&[("push:a:b", "push"), ("push_to:a:b", "")], 5).0 {
        ActStep::NeedChoice { id, options, owner, .. } => assert_eq!((id.as_str(), options.len(), owner.as_str()), ("push_to:a:b", 0, "a")),
        other => panic!("expected NeedChoice, got {other:?}"),
    }
}

#[test]
fn the_spot_moves_the_picked_model_on_4_plus() {
    let to = spot(0, 13.0);
    let (done, after) = play(&[("push:a:b", "push"), ("push_to:a:b", &to)], 5);
    assert!(matches!(done, ActStep::Done { .. }), "{done:?}");
    assert!((after.positions[2][0][0] - 13.0 * IN2M).abs() < 1e-9, "model 1 pushed 1 in east: {:?}", after.positions[2]);
    let (_, after) = play(&[("push:a:b", "push"), ("push_to:a:b", &to)], 3);
    assert!((after.positions[2][0][0] - 12.0 * IN2M).abs() < 1e-9, "no push on 1-3");
}

/// Lead condition (1): the attacker picks which model, but only one of the target's.
#[test]
fn a_slot_outside_the_target_or_a_far_spot_is_refused() {
    match play(&[("push:a:b", "push"), ("push_to:a:b", &spot(5, 13.0))], 5).0 {
        ActStep::Refused { reason, .. } => assert_eq!(reason, "Push: model 6 is no model of b"),
        other => panic!("expected Refused, got {other:?}"),
    }
    match play(&[("push:a:b", "push"), ("push_to:a:b", &spot(0, 15.0))], 5).0 {
        ActStep::Refused { reason, .. } => assert_eq!(reason, "Push: 3.4 in is over the 2 in"),
        other => panic!("expected Refused, got {other:?}"),
    }
}

#[test]
fn no_or_no_answer_is_no_push() {
    for choices in [vec![("push:a:b", "no")], vec![]] {
        let (done, after) = play(&choices, 5);
        assert!(matches!(done, ActStep::Done { .. }), "{done:?}");
        assert!((after.positions[2][0][0] - 12.0 * IN2M).abs() < 1e-9, "{choices:?}: nothing moves");
    }
}

/// `push_line` with four models for b, 1.5 in apart, and two hits: two casualties (half strength, Shaken), two survivors.
fn play3(choices: &[(&str, &str)]) -> (ActStep, State) {
    PLAY3.with(|f| f.set(true));
    let r = play(choices, 5);
    PLAY3.with(|f| f.set(false));
    r
}

thread_local! { static PLAY3: std::cell::Cell<bool> = const { std::cell::Cell::new(false) }; }

/// Step 29d-2 (3.6 p.15: "then the opponent must place any other models from the unit within 1" of it"): the defender is
/// asked; its own spot within 1 in stands; one further off is refused; "auto" is the D14 placer.
#[test]
fn the_defender_places_the_rest_within_1_in() {
    let (_, kept) = play3(&[("push:a:b", "no")]);
    let first = kept.positions[2][0];
    let to = format!("0:{},0,{}", first[0] + 1.5 * IN2M, first[2]);   // survivor 1 pushed 1.5 in east, the other left behind
    let base = [("push:a:b", "push"), ("push_to:a:b", to.as_str())];
    match play3(&[base[0], base[1], ("push_replace:b", "")]).0 {
        ActStep::NeedChoice { id, options, owner, .. } => assert_eq!((id.as_str(), options.len(), owner.as_str()), ("push_replace:b", 0, "b")),
        other => panic!("expected NeedChoice, got {other:?}"),
    }
    let (_, auto) = play3(&[base[0], base[1], ("push_replace:b", "auto")]);
    let pushed = auto.positions[2][0];
    assert!((pushed[0] - first[0] - 1.5 * IN2M).abs() < 1e-9, "fixture: model 1 pushed: {:?}", auto.positions[2]);
    let near = format!("1:{},0,{}", pushed[0], pushed[2] + 1.2 * IN2M);
    let (done, own) = play3(&[base[0], base[1], ("push_replace:b", near.as_str())]);
    assert!(matches!(done, ActStep::Done { .. }), "{done:?}");
    assert!((own.positions[2][1][2] - (pushed[2] + 1.2 * IN2M)).abs() < 1e-9, "the owner's spot stands: {:?}", own.positions[2]);
    let far = format!("1:{},0,{}", pushed[0], pushed[2] + 3.0 * IN2M);
    match play3(&[base[0], base[1], ("push_replace:b", far.as_str())]).0 {
        ActStep::Refused { reason, .. } => assert_eq!(reason, "Push: model 2 stands more than 1 in from the pushed model"),
        other => panic!("expected Refused, got {other:?}"),
    }
}
