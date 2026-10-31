//! MEL-05 tests (rules 3.6, lane melee): from `EPOCH_73_V36` a Counter defender takes no Impact
//! dice off the charge and only strikes first when it is neither Fatigued nor Shaken. Epoch 72
//! keeps both old behaviours. A unit without Counter is the control.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

struct Outcome {
    impact_dice: i64,
    first_attacker: String,
    log: Vec<String>,
}

/// One charge: a one-model Impact(3) charger (unit 0) into a three-model defender (unit 1) whose
/// melee weapon optionally carries Counter. Tough(9) on both sides keeps every model alive.
fn charge(epoch: u32, counter: bool, fatigued: bool, shaken: bool) -> Outcome {
    let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
    let unit = |name: &str, models: i64, impact: i64, counter: bool| UnitStatic {
        ctx: Ctx {
            quality: 4,
            defense: 4,
            tough: 9,
            models,
            impact,
            counter_models: if counter { models } else { 0 },
            ..Default::default()
        },
        name: name.into(),
        melee: vec![ShootProfile { name: "Blade".into(), attacks: 1, count: 1, range: 0, counter, ..Default::default() }],
        model_count: models,
        wounds_max: vec![9; models as usize],
        ..Default::default()
    };
    let statics = vec![unit("Charger", 1, 3, false), unit("Defender", 3, 0, counter)];
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 3];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    (st.wounds[0], Rc::make_mut(&mut st.radii)[0]) = (vec![9], vec![IN2M]);
    (st.positions[1], st.wounds[1], Rc::make_mut(&mut st.radii)[1]) = (vec![[0.0, 0.0, 0.0]; 3], vec![9; 3], vec![IN2M; 3]);
    st.fatigued[1] = fatigued;
    st.shaken[1] = shaken;
    let seams = Seams { rules_epoch: epoch, ..Default::default() };
    let (mut tray, mut shot) = (Tray::seeded(27), ShootResult::default());
    tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
    let impact_dice = shot.rolls.iter().find(|r| r.kind == "attack" && r.owner == "Charger").map(|r| r.count).unwrap_or(-1);
    let first_attacker = shot.rolls.iter().find(|r| r.kind == "attack").map(|r| r.owner.clone()).unwrap_or_default();
    Outcome { impact_dice, first_attacker, log: shot.log }
}

#[test]
fn a_counter_defender_cuts_impact_at_epoch_72() {
    let out = charge(EPOCH_72_PLAYTEST_RULES, true, false, false);
    assert_eq!(out.impact_dice, 1, "3 Impact dice minus 3 Counter models, floored at 1");
    assert_eq!(out.first_attacker, "Defender", "the Counter phase still opens the melee at 72");
}

#[test]
fn a_counter_defender_cuts_no_impact_at_epoch_73() {
    let out = charge(EPOCH_73_V36, true, false, false);
    assert_eq!(out.impact_dice, 3, "rules 3.6: Counter takes no Impact dice away");
    assert_eq!(out.first_attacker, "Charger", "Impact rolls before either side strikes");
}

#[test]
fn a_fresh_counter_defender_strikes_first_at_epoch_73() {
    let out = charge(EPOCH_73_V36, true, false, false);
    assert!(out.log.iter().any(|l| l == "Counter: Defender strikes first"), "{:?}", out.log);
}

#[test]
fn a_fatigued_counter_defender_does_not_strike_first_at_epoch_73() {
    let out = charge(EPOCH_73_V36, true, true, false);
    assert!(out.log.iter().any(|l| l == "Counter: Defender is Fatigued - no strike-first"), "{:?}", out.log);
    assert!(!out.log.iter().any(|l| l == "Counter: Defender strikes first"), "{:?}", out.log);
}

#[test]
fn a_shaken_counter_defender_does_not_strike_first_at_epoch_73() {
    let out = charge(EPOCH_73_V36, true, false, true);
    assert!(out.log.iter().any(|l| l == "Counter: Defender is Fatigued - no strike-first"), "{:?}", out.log);
    assert!(!out.log.iter().any(|l| l == "Counter: Defender strikes first"), "{:?}", out.log);
}

#[test]
fn a_defender_without_counter_is_unchanged_at_epoch_73() {
    let out = charge(EPOCH_73_V36, false, false, false);
    assert_eq!(out.impact_dice, 3, "no Counter, no Impact cut");
    assert!(!out.log.iter().any(|l| l.starts_with("Counter:")), "{:?}", out.log);
}
