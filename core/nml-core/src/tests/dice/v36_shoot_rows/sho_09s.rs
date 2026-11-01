use super::super::*;

// SHO-09s (rules 3.6, lane shoot): the two conditional-AP conditions that read TARGET STATE.
// `above_half_strength` = more than half its models left (a single model: more than half its
// Tough); `shaken_or_fatigued` = Shaken OR Fatigued, also while it is being shot at. No shipped
// map entry spells either name, so the arms carry no epoch gate (the SHO-09 precedent); the
// `_at_epoch_72` control pins every existing condition unchanged. RED before the fields exist:
// an unknown spelling answers 0, so the target saves at its plain Defense.

use crate::acts::EPOCH_73_V36;
use crate::io::{Action, Seams};
use crate::rng::GodotRng;
use crate::sim::{melee_threat_at_epoch, resolve_stochastic_tray_on_board, HOLD};
use crate::state::{Profiles, Roster, State};
use crate::terrain::Terrain;
use crate::unit::UnitStatic;
use std::collections::HashMap;
use std::rc::Rc;

fn spec(condition: &str) -> CondAp {
    CondAp { ap_bonus: 1, condition: condition.into(), name: "Probe Gun".into(), ..Default::default() }
}

/// A Gunner (unit 0) twelve inches from a Target (unit 2); the Target carries `models` starting
/// models of which `alive` remain. Both carry one conditional-AP entry spelled `condition`.
fn line(
    condition: Option<&str>,
    models: i64,
    alive: i64,
    shaken: bool,
    fatigued: bool,
) -> (State, Vec<UnitStatic>) {
    let mut st = crate::sim::tests::four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
    st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None; 4]);
    st.alive = vec![1, 0, alive, 0];
    st.wounds = vec![vec![1], Vec::new(), vec![1; alive as usize], Vec::new()];
    st.shaken = vec![false, false, shaken, false];
    st.fatigued = vec![false, false, fatigued, false];
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    st.positions[2] =
        (0..alive).map(|k| [(12.0 + 0.02 * k as f64) * crate::IN2M, 0.0, 0.0]).collect();
    Rc::make_mut(&mut st.radii)[0] = vec![crate::IN2M];
    Rc::make_mut(&mut st.radii)[2] = vec![crate::IN2M; alive as usize];
    let cond: Vec<CondAp> = condition.map(|c| vec![spec(c)]).unwrap_or_default();
    let mut gunner = UnitStatic { name: "Gunner".into(), model_count: 1, ..Default::default() };
    gunner.ctx = Ctx { quality: 4, models: 1, tough: 1, ..Default::default() };
    gunner.shoot = vec![ShootProfile {
        name: "Probe Gun".into(),
        attacks: 12,
        count: 1,
        range: 24,
        cond_ap: cond.clone(),
        ..Default::default()
    }];
    gunner.melee = vec![ShootProfile {
        name: "Probe Blade".into(),
        attacks: 12,
        count: 1,
        range: 0,
        cond_ap: cond,
        ..Default::default()
    }];
    let mut target = UnitStatic { name: "Target".into(), model_count: models, ..Default::default() };
    target.ctx = Ctx { defense: 4, quality: 4, tough: 1, ..Default::default() };
    target.wounds_max = vec![1; models as usize];
    (st, vec![gunner, UnitStatic::default(), target, UnitStatic::default()])
}

fn act() -> Action {
    Action {
        kind: HOLD,
        unit: "a".into(),
        dest: None,
        shoot: Some("b".into()),
        charge: None,
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    }
}

/// The Defense target of the volley's save batch: 4 = no conditional AP, 5 = AP(+1).
fn save_target_of(
    condition: Option<&str>,
    models: i64,
    alive: i64,
    shaken: bool,
    fatigued: bool,
) -> i64 {
    let (st, statics) = line(condition, models, alive, shaken, fatigued);
    let mut tray = Tray::seeded(27);
    let mut rng = GodotRng::new(0);
    let (_, shot) = resolve_stochastic_tray_on_board(
        &statics,
        &st,
        &act(),
        &Terrain::default(),
        Seams { rules_epoch: EPOCH_73_V36, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .expect("the probe activation resolves");
    shot.rolls.iter().find(|r| r.kind == "defense").expect("the volley leaves a save batch").target
}

/// The charge EV `melee_threat_at_epoch` prices for the same pair.
fn threat(condition: Option<&str>, models: i64, alive: i64, shaken: bool, fatigued: bool) -> f64 {
    let (st, statics) = line(condition, models, alive, shaken, fatigued);
    melee_threat_at_epoch(&statics, &st, 0, 2, EPOCH_73_V36)
}

#[test]
fn above_half_strength_pays_only_against_a_target_above_half_at_epoch_73() {
    assert_eq!(save_target_of(Some("above_half_strength"), 5, 5, false, false), 5, "5 of 5 left: AP(+1) -> 5+");
    assert_eq!(save_target_of(Some("above_half_strength"), 5, 3, false, false), 5, "3 of 5 is above half");
    assert_eq!(save_target_of(Some("above_half_strength"), 5, 2, false, false), 4, "2 of 5 is half or less");
    assert_eq!(save_target_of(None, 5, 5, false, false), 4, "a plain entry never pays");
}

#[test]
fn above_half_strength_measures_a_single_model_in_tough_wounds_at_epoch_73() {
    let (mut st, mut statics) = line(Some("above_half_strength"), 1, 1, false, false);
    statics[2].wounds_max = vec![3];
    st.wounds[2] = vec![3];
    let mut tray = Tray::seeded(27);
    let mut rng = GodotRng::new(0);
    let (_, shot) = resolve_stochastic_tray_on_board(
        &statics,
        &st,
        &act(),
        &Terrain::default(),
        Seams { rules_epoch: EPOCH_73_V36, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .expect("the probe activation resolves");
    let full = shot.rolls.iter().find(|r| r.kind == "defense").unwrap().target;
    st.wounds[2] = vec![1];
    let mut tray = Tray::seeded(27);
    let mut rng = GodotRng::new(0);
    let (_, shot) = resolve_stochastic_tray_on_board(
        &statics,
        &st,
        &act(),
        &Terrain::default(),
        Seams { rules_epoch: EPOCH_73_V36, ..Seams::default() },
        &mut rng,
        &mut tray,
    )
    .expect("the probe activation resolves");
    let hurt = shot.rolls.iter().find(|r| r.kind == "defense").unwrap().target;
    assert_eq!(full, 5, "3 of 3 Tough left: AP(+1) -> 5+");
    assert_eq!(hurt, 4, "1 of 3 is half or less");
}

#[test]
fn shaken_or_fatigued_pays_for_either_flag_at_epoch_73() {
    assert_eq!(save_target_of(Some("shaken_or_fatigued"), 5, 3, true, false), 5, "Shaken target");
    assert_eq!(save_target_of(Some("shaken_or_fatigued"), 5, 3, false, true), 5, "Fatigued target");
    assert_eq!(save_target_of(Some("shaken_or_fatigued"), 5, 3, false, false), 4, "a fresh target pays nothing");
}

#[test]
fn the_core_ev_prices_the_same_target_state_at_epoch_73() {
    let above = threat(Some("above_half_strength"), 5, 5, false, false);
    assert!(above > threat(None, 5, 5, false, false), "above half: the AP(+1) must raise the charge EV");
    let below = threat(Some("above_half_strength"), 5, 2, false, false);
    assert!((below - threat(None, 5, 2, false, false)).abs() < 1e-9, "half or less: unchanged");
    let shaken = threat(Some("shaken_or_fatigued"), 5, 3, true, false);
    assert!(shaken > threat(None, 5, 3, true, false), "Shaken: the AP(+1) must raise the charge EV");
}

#[test]
fn existing_conditions_answer_unchanged_at_epoch_72() {
    let spec = |cond: &str, threshold: i64| CondAp {
        ap_bonus: 2,
        condition: cond.into(),
        threshold,
        over_in: 9.0,
        within_in: 12.0,
        ..Default::default()
    };
    assert_eq!(conditional_ap_bonus(&spec("vs_tough_ge", 3), 3, 4, false, 0.0, true), 2);
    assert_eq!(conditional_ap_bonus(&spec("vs_tough_ge", 3), 2, 4, false, 0.0, true), 0);
    assert_eq!(conditional_ap_bonus(&spec("vs_armor", 3), 1, 3, false, 0.0, true), 2);
    assert_eq!(conditional_ap_bonus(&spec("ranged_over", 0), 1, 5, false, 12.0, false), 2);
    assert_eq!(conditional_ap_bonus(&spec("ranged_within", 0), 1, 5, false, 12.0, false), 2);
    assert_eq!(conditional_ap_bonus(&spec("on_charge", 0), 1, 5, true, 0.0, true), 2);
    assert_eq!(conditional_ap_bonus(&spec("on_charge", 0), 1, 5, false, 0.0, true), 0);
}
