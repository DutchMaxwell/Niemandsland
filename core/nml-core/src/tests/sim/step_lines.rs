//! The step path's battle log is the tray's lines (`Tray::say`); a rules-must-log line the resolve only pushes into `shot.log`
//! never reaches the door (LOG-MISSING under D-PAR1 item 5). These pin the lines that now ride the tray as well.

use super::*;
use crate::activation::{step_activation, ActStep, Input};

/// Drives one activation of "a" to its end, answering every roll with sixes; the surfaced lines.
fn surfaced(statics: &[UnitStatic], st: &State, mut t: Vec<Input>) -> Vec<String> {
    let seams = Seams { rules_epoch: 95, ..Seams::default() };
    let board = crate::terrain::Terrain::default();
    for _ in 0..40 {
        match step_activation(statics, st, "a", &board, seams, &t, false) {
            ActStep::NeedRoll { faces, .. } => t.push(Input::Faces(vec![6; faces])),
            ActStep::Done { lines, .. } => return lines.into_iter().map(|l| l.text).collect(),
            other => panic!("{other:?}"),
        }
    }
    panic!("no end in 40 steps")
}

fn shoot(kind: i64) -> Input {
    Input::Intent { kind, shoot: Some("b".into()), split: None, charge: None, no_step: false }
}

/// Rules 3.6 Cumbersome (SHO-16): the moved unit fires nothing and the log says why. RED before: the line sat in `shot.log` only.
#[test]
fn a_moved_cumbersome_unit_names_the_rule_on_the_step_path() {
    let (st, mut statics) = buff_line();
    statics[0].cumbersome = true;
    let at: Vec<[f64; 3]> = st.positions[0].iter().map(|p| [p[0], p[1], p[2] + 2.0 * IN2M]).collect();
    let lines = surfaced(&statics, &st, vec![Input::Begin, Input::Placed { at, trails: Vec::new() }, shoot(ADVANCE)]);
    assert!(lines.iter().any(|l| l == "Cumbersome: a moved, so it cannot shoot this activation"), "{lines:?}");
    assert!(lines.iter().all(|l| !l.contains("fires")), "no volley: {lines:?}");
}

/// A spell token on Defense (a +1 ward, a -1 hex) is named at the save with the table's per-part line (`_solo_log_defense_parts`).
/// RED before: no line named the token, though the save target moved.
#[test]
fn a_defense_token_is_named_on_the_step_path() {
    let named = |n: &str, def_mod: i64, defense_mod: i64| mods::LiveMod {
        move_mod: 0, range_in: 0, hit_mod: 0, casting_mod: 0, morale_mod: 0, ap_mod: 0, def_mod, defense_mod,
        grants_rule: Rc::from(""), scope: Rc::from(""), attackers: false, once: true, name: Rc::from(n),
    };
    let (mut st, mut statics) = buff_line();
    statics[0].shoot[0].attacks = 8;
    st.buffs[2].push(named("Warding Chant", 1, 0));
    let lines = surfaced(&statics, &st, vec![Input::Begin, shoot(HOLD)]);
    assert_eq!(lines.iter().filter(|l| *l == "b is Warding Chant: +1 Defense (saves on 3+)").count(), 1, "{lines:?}");
    let (mut hex, _) = buff_line();
    hex.buffs[2].push(named("Withering Hex", 0, -1));
    let lines = surfaced(&statics, &hex, vec![Input::Begin, shoot(HOLD)]);
    assert!(lines.iter().any(|l| l == "b is Withering Hex: -1 Defense (saves on 5+)"), "{lines:?}");
    let lines = surfaced(&statics, &buff_line().0, vec![Input::Begin, shoot(HOLD)]);
    assert!(lines.iter().all(|l| !l.contains(" Defense (saves on")), "no token, no line: {lines:?}");
}

/// Reanimation (fd-door, the G1' start_twice counter): the pool roll and each restore are said on the step path. RED before: the
/// core rolled the pool (no `paid`) and the door saw no line.
#[test]
fn the_reanimation_roll_is_named_on_the_step_path() {
    let (mut st, mut statics) = buff_line();
    statics[0].reanimation = Some(crate::unit::ReanimationSpec { target: 1 });
    statics[0].wounds_max = vec![1, 1, 1];
    let mut list = st.profiles.list.clone();
    list[0].wounds_max = vec![1, 1, 1];
    st.profiles = Rc::new(Profiles { list, index: HashMap::new() });
    st.wounds[0] = vec![1, 1]; // three models, one fell
    let lines = surfaced(&statics, &st, vec![Input::Begin, Input::Intent { kind: HOLD, shoot: None, split: None, charge: None, no_step: false }]);
    assert!(lines.iter().any(|l| l == "Reanimation: a rolls 1 dice (1) — 1 success(es)"), "{lines:?}");
}
