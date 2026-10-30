//! MEL-11 — Ravage rolls once per round, before the unit attacks, and never
//! while the unit is Fatigued (a Shaken strike-back counts). Epoch 72 keeps
//! the old every-strike roll.

use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// A weaponless 12-model charger against a 3-model Ravage(2) defender, so
/// every Ravage pool of the defender is exactly 6 dice.
fn fixture(fatigued: bool, counter: bool) -> (Vec<UnitStatic>, State) {
    let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
    let blade = |n: &str, counter: bool| ShootProfile { name: n.into(), attacks: 1, count: 1, range: 0, counter, ..Default::default() };
    let mut claws = vec![blade("Claws", false)];
    if counter {
        claws.push(blade("Spear", true));
    }
    let statics = vec![
        UnitStatic { ctx: Ctx { quality: 4, defense: 6, tough: 1, models: 12, ..Default::default() },
            name: "Charger".into(), model_count: 12, wounds_max: vec![1; 12], ..Default::default() },
        UnitStatic { ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 3, ravage: 2, ..Default::default() },
            name: "Ravager".into(), melee: claws, model_count: 3, wounds_max: vec![1; 3], ..Default::default() },
    ];
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![12, 3];
    st.shaken = vec![false, false];
    st.fatigued = vec![false, fatigued];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions[0] = vec![[IN2M, 0.0, 0.0]; 12];
    st.wounds[0] = vec![1; 12];
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M; 12];
    st.positions[1] = vec![[0.0, 0.0, 0.0]; 3];
    st.wounds[1] = vec![1; 3];
    Rc::make_mut(&mut st.radii)[1] = vec![IN2M; 3];
    (statics, st)
}

/// One charge on the tray; returns the result and how many Ravage pools the defender rolled.
fn melee(rules_epoch: u32, fatigued: bool, counter: bool) -> (ShootResult, usize) {
    let (statics, mut st) = fixture(fatigued, counter);
    let seams = Seams { rules_epoch, ..Default::default() };
    let mut shot = ShootResult::default();
    tray_charge(&statics, &mut st, 0, 1, seams, &mut Tray::seeded(27), &mut shot, 0.0, Cover::Recorded(None));
    let pools = shot.rolls.iter().filter(|r| r.owner == "Ravager" && r.target == RAVAGE_WOUND_TARGET && r.count == 6).count();
    (shot, pools)
}

#[test]
fn a_fatigued_ravager_still_rolls_ravage_at_epoch_72() {
    assert_eq!(melee(EPOCH_72_PLAYTEST_RULES, true, false).1, 1, "the old leg rolls Ravage while Fatigued");
}

#[test]
fn a_fatigued_ravager_rolls_no_ravage_at_epoch_73() {
    let (shot, pools) = melee(EPOCH_73_V36, true, false);
    assert_eq!(pools, 0, "a Fatigued unit rolls no Ravage");
    assert!(shot.log.iter().any(|l| l.starts_with("Ravage: Ravager is Fatigued")), "rules-must-log: {:?}", shot.log);
}

#[test]
fn a_counter_ravager_rolls_ravage_twice_in_one_melee_at_epoch_72() {
    assert_eq!(melee(EPOCH_72_PLAYTEST_RULES, false, true).1, 2, "the old leg rolls in the Counter phase and the strike-back");
}

#[test]
fn a_counter_ravager_rolls_ravage_once_in_one_melee_at_epoch_73() {
    assert_eq!(melee(EPOCH_73_V36, false, true).1, 1, "once per round: the Counter phase and the strike-back share one roll");
}

/// The EV twin: the Ravager's 6 Ravage dice are worth exactly one wound (6 x 1/6).
fn threat_drop(rules_epoch: u32) -> f64 {
    let (statics, st) = fixture(true, false);
    let (fresh_statics, fresh) = fixture(false, false);
    melee_threat_at_epoch(&fresh_statics, &fresh, 1, 0, rules_epoch) - melee_threat_at_epoch(&statics, &st, 1, 0, rules_epoch)
}

#[test]
fn a_fatigued_ravager_still_prices_ravage_at_epoch_72() {
    let fresh_hits = threat_drop(EPOCH_72_PLAYTEST_RULES);
    assert!(fresh_hits > 0.0 && fresh_hits < 1.0, "only the hit roll changes with fatigue: {fresh_hits}");
}

#[test]
fn a_fatigued_ravager_prices_no_ravage_at_epoch_73() {
    let drop = threat_drop(EPOCH_73_V36) - threat_drop(EPOCH_72_PLAYTEST_RULES);
    assert!((drop - 1.0).abs() < 1e-9, "fatigue also drops the one Ravage wound: {drop}");
}
