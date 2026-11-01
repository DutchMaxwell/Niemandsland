//! Rules 3.6 row AI-06 (sim module), shooting half: the AI's expected shooting-morale number counts
//! Scourge's phantom wounds. The resolver already counts an unmodified block 1 as two phantom
//! wounds (SHO-15a); the ESTIMATE must count them toward the post-volley read too, from
//! EPOCH_73_V36. Below 73 and for a non-Scourge volley the number stays put.

use super::super::*;
use super::four_unit_line;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::state::{Profile, Profiles, Roster};
use std::collections::HashMap;
use std::rc::Rc;

/// Two single-model units on a line, 12" apart: the shooter carries 36 attacks at Q4+ against the
/// defender's Defense 4+, which land 9 expected wounds and leave a 20-Tough target at 11 (above
/// half) on real wounds alone; the 18 expected hits add 6 phantom wounds, which put it at 5.
fn shot_line(scourge: bool) -> (State, Vec<UnitStatic>) {
    let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: vec!["a".into(), "b".into()],
        index: HashMap::from([("a".to_string(), 0), ("b".to_string(), 1)]),
        profile: vec![0, 1],
    });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 1];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[12.0 * IN2M, 0.0, 0.0]]];
    st.wounds = vec![vec![100], vec![20]];
    st.radii = Rc::new(vec![vec![IN2M], vec![IN2M]]);
    st.wound_frac = vec![0.0, 0.0];
    let statics = vec![
        UnitStatic {
            name: "Shooter".into(),
            model_count: 1,
            wounds_max: vec![100],
            quality: 4,
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
            shoot: vec![ShootProfile {
                name: "Gun".into(),
                attacks: 36,
                count: 1,
                range: 24,
                rules: if scourge { vec!["Scourge".into()] } else { vec![] },
                ..Default::default()
            }],
            ..Default::default()
        },
        UnitStatic {
            name: "Target".into(),
            model_count: 1,
            wounds_max: vec![20],
            quality: 4,
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
            ..Default::default()
        },
    ];
    (st, statics)
}

fn shot_ev(scourge: bool, epoch: u32) -> State {
    let (st, statics) = shot_line(scourge);
    let action = Action {
        kind: HOLD,
        unit: "a".into(),
        dest: None,
        shoot: Some("b".into()),
        charge: None,
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    };
    resolve_on_board(
        &statics, &st, &action, &crate::terrain::Terrain::default(),
        Seams { rules_epoch: epoch, ..Default::default() },
    )
    .unwrap()
}

/// NEW leg: the shooting-morale read counts the phantom wounds at 73.
#[test]
fn scourge_phantom_wounds_tip_the_shooting_morale_read_at_epoch_73() {
    let next = shot_ev(true, EPOCH_73_V36);
    assert!(next.shaken[1], "the Scourge 1s put the target at half or less: {:?}", next.shaken);
}

/// OLD leg: at 72 the same volley leaves the target above half on real wounds.
#[test]
fn the_same_scourge_volley_leaves_no_test_at_epoch_72() {
    let next = shot_ev(true, EPOCH_72_PLAYTEST_RULES);
    assert!(!next.shaken[1], "below 73 the phantom wounds count nowhere: {:?}", next.shaken);
}

/// Control: a plain volley leaves no test at 73.
#[test]
fn a_plain_volley_leaves_no_test_at_epoch_73() {
    let next = shot_ev(false, EPOCH_73_V36);
    assert!(!next.shaken[1], "a non-Scourge volley is unchanged: {:?}", next.shaken);
}
