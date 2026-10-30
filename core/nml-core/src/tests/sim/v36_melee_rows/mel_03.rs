//! MEL-03 tests (rules 3.6, lane melee); empty until the row lands - start with `use super::super::*;`.
//! From rules 3.6 (`EPOCH_73_V36`) the charger's Impact dice roll before EITHER side strikes, so the
//! defender's Counter phase moves behind Impact; epoch 72 keeps Counter first. The Counter cut of the
//! Impact dice stays in this row (Brace takes it over in a later row).
use super::super::*;

/// One charge melee: a 5-model Impact(`impact`) charger (unit 0) into a `def_models`-model
/// defender at Defense `def` (unit 1). The Counter weapon sits on the defender itself, or with
/// `hero` on a 1-model hero joined to it (unit 2, tray-exact read). Returns the owners of the
/// attack rolls in tray order, the Impact dice rolled and the defender's survivors.
fn charge(epoch: u32, impact: i64, def_models: i64, def: i64, hero: bool) -> (Vec<String>, i64, i64) {
    let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
    let unit = |name: &str, models: i64, impact: i64, def: i64, counter: bool| UnitStatic {
        ctx: Ctx { quality: 4, defense: def, tough: 1, models, impact, counter_models: if counter { models } else { 0 }, ..Default::default() },
        name: name.into(),
        melee: vec![ShootProfile { name: "Blade".into(), attacks: 1, count: 1, range: 0, counter, ..Default::default() }],
        model_count: models,
        wounds_max: vec![1; models as usize],
        ..Default::default()
    };
    let statics = vec![unit("Charger", 5, impact, 4, false), unit("Defender", def_models, 0, def, !hero), unit("Hero", 1, 0, 4, hero)];
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into(), "bh".into()], index: HashMap::new(), profile: vec![0, 1, 2] });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile.clone(), profile], index: HashMap::new() });
    st.player = vec![0, 1, 1];
    st.alive = vec![5, def_models, hero as i64];
    st.attached = Rc::new(vec![vec![], if hero { vec![2] } else { vec![] }, vec![]]);
    st.attached_to = Rc::new(vec![None, None, if hero { Some(1) } else { None }]);
    let n = def_models as usize;
    st.positions[0] = (1..=5).map(|i| [i as f64 * IN2M, 0.0, 0.0]).collect();
    (st.wounds[0], Rc::make_mut(&mut st.radii)[0]) = (vec![1; 5], vec![IN2M; 5]);
    (st.positions[1], st.wounds[1], Rc::make_mut(&mut st.radii)[1]) = (vec![[0.0, 0.0, 0.0]; n], vec![1; n], vec![IN2M; n]);
    (st.positions[2], st.wounds[2], Rc::make_mut(&mut st.radii)[2]) = (vec![[0.0, 0.0, 0.0]], vec![1], vec![IN2M]);
    let seams = Seams { rules_epoch: epoch, tray_exact: hero, ..Default::default() };
    let (mut tray, mut shot) = (Tray::seeded(27), ShootResult::default());
    tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
    let attacks = shot.rolls.iter().filter(|r| r.kind == "attack").map(|r| r.owner.clone()).collect();
    let impact_dice = shot.rolls.iter().find(|r| r.owner == "Charger").map(|r| r.count).unwrap_or(-1);
    (attacks, impact_dice, st.alive[1])
}

#[test]
fn impact_rolls_before_the_counter_phase_at_epoch_73() {
    let (attacks, impact_dice, _) = charge(crate::acts::EPOCH_73_V36, 1, 3, 4, false);
    assert_eq!(attacks, ["Charger", "Defender", "Charger"], "Impact, then Counter, then the charger's strikes");
    assert_eq!(impact_dice, 2, "the three Counter models still cut three of five Impact dice");
}

#[test]
fn counter_strikes_before_impact_at_epoch_72() {
    let (attacks, impact_dice, _) = charge(crate::acts::EPOCH_72_PLAYTEST_RULES, 1, 3, 4, false);
    assert_eq!(attacks, ["Defender", "Charger", "Charger"], "the old order replays: Counter, Impact, strikes");
    assert_eq!(impact_dice, 2);
}

/// The Counter phase keeps the alive gate it had before Impact: a defender the Impact pool
/// wiped has nobody left to strike first.
#[test]
fn an_impact_wipe_leaves_no_counter_phase_at_epoch_73() {
    let (attacks, _, survivors) = charge(crate::acts::EPOCH_73_V36, 6, 1, 6, false);
    assert_eq!((attacks, survivors), (vec!["Charger".to_string()], 0), "Impact wiped the defender, no Counter strike");
}

/// The joined hero's Counter (tray-exact read) moves behind Impact too and still cuts one die.
#[test]
fn a_joined_heros_counter_strikes_after_impact_at_epoch_73() {
    let (attacks, impact_dice, _) = charge(crate::acts::EPOCH_73_V36, 2, 3, 4, true);
    assert_eq!(attacks[..2], ["Charger", "Hero"], "{attacks:?}");
    assert_eq!(impact_dice, 9, "the hero's one Counter model cuts one of ten Impact dice");
}
