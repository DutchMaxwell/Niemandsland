//! Rules 3.6 row AI-06 (sim module), melee half: the AI's expected melee-morale number counts
//! Scourge's phantom wounds. The resolver already counts an unmodified block 1 as two phantom
//! wounds (SHO-15a/b); the ESTIMATE must count them in the defender's taken tally too, from
//! EPOCH_73_V36. Below 73 and for a non-Scourge striker the number stays put.

use super::super::*;
use super::four_unit_line;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::state::{Profile, Profiles, Roster};
use std::collections::HashMap;
use std::rc::Rc;

/// Two single-model units on a line; the charger carries `a_melee` attacks (Scourge when asked)
/// against the defender's `b_melee` attacks, 100 Tough wounds each so neither routs on the wounds.
fn two_line(a_melee: i64, b_melee: i64, scourge: bool) -> (State, Vec<UnitStatic>) {
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
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[1.3 * IN2M, 0.0, 0.0]]];
    st.wounds = vec![vec![100], vec![100]];
    st.radii = Rc::new(vec![vec![IN2M], vec![IN2M]]);
    st.wound_frac = vec![0.0, 0.0];
    let blade = |attacks: i64, scourge: bool| ShootProfile {
        name: "Blade".into(),
        attacks,
        count: 1,
        range: 0,
        rules: if scourge { vec!["Scourge".into()] } else { vec![] },
        ..Default::default()
    };
    let statics = vec![
        UnitStatic {
            name: "Charger".into(),
            model_count: 1,
            wounds_max: vec![100],
            quality: 4,
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
            melee: vec![blade(a_melee, scourge)],
            ..Default::default()
        },
        UnitStatic {
            name: "Target".into(),
            model_count: 1,
            wounds_max: vec![100],
            quality: 4,
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
            melee: vec![blade(b_melee, false)],
            ..Default::default()
        },
    ];
    (st, statics)
}

fn charge_ev(scourge: bool, epoch: u32) -> State {
    let (st, statics) = two_line(30, 33, scourge);
    let action = Action {
        kind: CHARGE,
        unit: "a".into(),
        dest: None,
        shoot: None,
        charge: Some("b".into()),
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

/// NEW leg: the charger dealt 7 to the defender and took 8, so it loses on real wounds; the 5
/// expected phantom wounds the Scourge 1s add to the defender's taken tally flip the loser.
#[test]
fn a_scourge_chargers_phantom_wounds_flip_the_melee_loser_at_epoch_73() {
    let next = charge_ev(true, EPOCH_73_V36);
    assert!(
        next.shaken[1] && !next.shaken[0],
        "the defender took the Scourge phantom wounds and must test: {:?}", next.shaken
    );
}

/// OLD leg: at 72 the same charge keeps the charger as the loser — the phantom wounds count nowhere.
#[test]
fn the_same_scourge_charge_keeps_the_old_loser_at_epoch_72() {
    let next = charge_ev(true, EPOCH_72_PLAYTEST_RULES);
    assert!(
        next.shaken[0] && !next.shaken[1],
        "below 73 the Scourge phantom wounds count nowhere: {:?}", next.shaken
    );
}

/// Control: a plain charger (no Scourge) keeps the old loser at 73.
#[test]
fn a_plain_charger_keeps_the_old_loser_at_epoch_73() {
    let next = charge_ev(false, EPOCH_73_V36);
    assert!(
        next.shaken[0] && !next.shaken[1],
        "a non-Scourge striker is unchanged: {:?}", next.shaken
    );
}
