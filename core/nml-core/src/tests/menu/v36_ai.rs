//! Rules 3.6 (SHO-16) AI side: a Cumbersome unit may only Hold or Advance and
//! fires no volley after moving. The menu drops RUSH, CHARGE and the moving
//! shots; the reply model drops the charge and the advance-and-shoot legs but
//! keeps the standing volley. Below `EPOCH_73_V36` every menu is unchanged.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::sim::{reply_threat_core, ReplyOpts};
use crate::state::{Objective, Profile, Profiles, Roster};
use std::collections::HashMap;
use std::rc::Rc;

fn gun() -> ShootProfile {
    ShootProfile { name: "Gun".into(), attacks: 8, count: 1, range: 24, ..Default::default() }
}

/// Two single-model units on one line: "m" (player 0) at the origin and "f"
/// (player 1) `gap_in` inches up +x, both with a 24" gun. `cumbersome` marks
/// each static, and both statics carry `epoch`.
fn two_unit_line(epoch: u32, gap_in: f64, cumbersome: [bool; 2]) -> (State, Vec<UnitStatic>) {
    let mut st = crate::sim::tests::four_unit_line();
    let mine: Profile = serde_json::from_str(r#"{"unit_id": "m", "name": "Mine"}"#).unwrap();
    let foe: Profile = serde_json::from_str(r#"{"unit_id": "f", "name": "Foe"}"#).unwrap();
    st.roster = Rc::new(Roster {
        keys: vec!["m".into(), "f".into()],
        index: [("m", 0usize), ("f", 1usize)].iter().map(|(k, i)| (k.to_string(), *i)).collect(),
        profile: vec![0, 1],
    });
    st.profiles = Rc::new(Profiles { list: vec![mine, foe], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 1];
    st.activated = vec![false, false];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[gap_in * IN2M, 0.0, 0.0]]];
    st.wounds = vec![vec![1], vec![1]];
    st.radii = Rc::new(vec![vec![IN2M], vec![IN2M]]);
    let statics = vec![
        UnitStatic {
            name: "Mine".into(),
            model_count: 1,
            wounds_max: vec![1],
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
            shoot: vec![gun()],
            cumbersome: cumbersome[0],
            rules_epoch: epoch,
            ..Default::default()
        },
        UnitStatic {
            name: "Foe".into(),
            model_count: 1,
            wounds_max: vec![1],
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
            shoot: vec![gun()],
            cumbersome: cumbersome[1],
            rules_epoch: epoch,
            ..Default::default()
        },
    ];
    (st, statics)
}

fn objective_at(inches: f64) -> Objective {
    Objective { pos: [inches * IN2M, 0.0, 0.0], owner: 0 }
}

fn build_menu(st: &State, statics: &[UnitStatic]) -> Vec<Candidate> {
    let mut sc = Scratch::default();
    candidates_tuned(st, &Terrain::default(), statics, 0, &mut sc, Tuning::default())
}

fn fingerprint(menu: &[Candidate]) -> Vec<String> {
    menu.iter().map(|c| format!("{c:?}")).collect()
}

/// Control: rules 3.5 has no Cumbersome, so the menu still offers a RUSH.
#[test]
fn a_cumbersome_unit_is_offered_a_rush_at_epoch_72() {
    let (mut st, statics) = two_unit_line(EPOCH_72_PLAYTEST_RULES, 20.0, [true, false]);
    st.objectives = vec![objective_at(10.0)];
    let menu = build_menu(&st, &statics);
    assert!(menu.iter().any(|c| c.kind == RUSH), "rules 3.5: RUSH stays on the menu: {menu:?}");
}

/// Rules 3.6: the Cumbersome menu is HOLD, HOLD+shoot and one plain ADVANCE per
/// objective — no RUSH, no CHARGE, no ADVANCE that carries a shot.
#[test]
fn a_cumbersome_unit_only_holds_or_advances_straight_at_epoch_73() {
    let (mut st, statics) = two_unit_line(EPOCH_73_V36, 20.0, [true, false]);
    st.objectives = vec![objective_at(10.0)];
    let menu = build_menu(&st, &statics);
    assert!(menu.iter().any(|c| c.kind == HOLD && c.shoot.is_none()), "{menu:?}");
    assert!(menu.iter().any(|c| c.kind == HOLD && c.shoot.as_deref() == Some("f")), "{menu:?}");
    let advances: Vec<&Candidate> = menu.iter().filter(|c| c.kind == ADVANCE).collect();
    assert_eq!(advances.len(), st.objectives.len(), "one ADVANCE per objective: {menu:?}");
    assert!(advances.iter().all(|c| c.shoot.is_none()), "no moving shot: {menu:?}");
    assert!(advances.iter().any(|c| c.dest == Some(st.objectives[0].pos)), "{menu:?}");
    assert!(menu.iter().all(|c| c.kind != RUSH), "no RUSH: {menu:?}");
    assert!(menu.iter().all(|c| c.kind != CHARGE), "no CHARGE: {menu:?}");
    assert!(
        menu.iter().all(|c| !(c.kind == ADVANCE && c.shoot.is_some())),
        "no ADVANCE+shoot: {menu:?}"
    );
}

/// Control: a unit without the rule keeps the same menu at 73 as at 72.
#[test]
fn an_ordinary_units_menu_is_the_same_at_epoch_73() {
    let (mut st72, statics72) = two_unit_line(EPOCH_72_PLAYTEST_RULES, 20.0, [false, false]);
    let (mut st73, statics73) = two_unit_line(EPOCH_73_V36, 20.0, [false, false]);
    st72.objectives = vec![objective_at(10.0)];
    st73.objectives = vec![objective_at(10.0)];
    assert_eq!(fingerprint(&build_menu(&st72, &statics72)), fingerprint(&build_menu(&st73, &statics73)));
}

fn incoming_at(gap_in: f64, epoch: u32) -> f64 {
    let (st, statics) = two_unit_line(epoch, gap_in, [false, true]);
    reply_threat_core(&statics, &st, 0, epoch, ReplyOpts { v2: true, ..ReplyOpts::default() })[0]
}

/// Rules 3.5: the Cumbersome enemy advances its 6" and shoots the 24" gun.
#[test]
fn a_cumbersome_enemy_advances_and_shoots_at_epoch_72() {
    assert!(incoming_at(29.0, EPOCH_72_PLAYTEST_RULES) > 0.0, "rules 3.5: the advance+shot counts");
}

/// Rules 3.6: it may not advance-and-shoot, so a target beyond its gun is safe.
#[test]
fn a_cumbersome_enemy_advances_no_more_at_epoch_73() {
    assert_eq!(incoming_at(29.0, EPOCH_73_V36), 0.0, "no advance+shot, and 29\" is out of range");
}

/// Rules 3.6 keeps the standing volley: inside the gun's range it still counts.
#[test]
fn a_cumbersome_enemy_still_fires_standing_at_epoch_73() {
    assert!(incoming_at(18.0, EPOCH_73_V36) > 0.0, "standing volley stays");
}
