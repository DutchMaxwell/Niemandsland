//! MEL-PAR-B14 tests (rules 3.6, lane melee): from `EPOCH_73_V36` a defender with no melee weapon at
//! all neither strikes back nor is made Fatigued by the fight; below the gate today's behaviour stays.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

fn blade(name: &str) -> ShootProfile {
    ShootProfile { name: name.into(), attacks: 2, count: 1, range: 0, ..Default::default() }
}

fn gun(name: &str) -> ShootProfile {
    ShootProfile { name: name.into(), attacks: 3, count: 1, range: 24, ..Default::default() }
}

/// One charge melee: a 3-model Blade charger into a 3-model defender whose melee list is
/// `def_melee` and whose ranged list is `def_shoot`. Returns the attack-roll owners in tray order,
/// the defender's fatigue flag after the fight and the battle log.
fn charge(epoch: u32, def_melee: Vec<ShootProfile>, def_shoot: Vec<ShootProfile>) -> (Vec<String>, bool, Vec<String>) {
    let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
    let statics = vec![
        UnitStatic {
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 3, ..Default::default() },
            name: "Charger".into(),
            melee: vec![blade("Blade")],
            model_count: 3,
            wounds_max: vec![1; 3],
            ..Default::default()
        },
        UnitStatic {
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 3, ..Default::default() },
            name: "Defender".into(),
            shoot: def_shoot,
            melee: def_melee,
            model_count: 3,
            wounds_max: vec![1; 3],
            ..Default::default()
        },
    ];
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![3, 3];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions[0] = vec![[0.0, 0.0, 0.0], [0.8, 0.0, 0.0], [1.2, 0.0, 0.0]];
    st.wounds[0] = vec![1; 3];
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M; 3];
    st.positions[1] = vec![[2.0, 0.0, 0.0], [3.0, 0.0, 0.0], [4.0, 0.0, 0.0]];
    st.wounds[1] = vec![1; 3];
    Rc::make_mut(&mut st.radii)[1] = vec![IN2M; 3];

    let seams = Seams { rules_epoch: epoch, ..Default::default() };
    let mut tray = Tray::seeded(27);
    let mut shot = ShootResult::default();
    tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
    let owners = shot.rolls.iter().filter(|r| r.kind == "attack").map(|r| r.owner.clone()).collect();
    (owners, st.fatigued[1], shot.log)
}

#[test]
fn a_ranged_only_defender_neither_strikes_back_nor_tires_at_epoch_73() {
    let (owners, fatigued, log) = charge(EPOCH_73_V36, vec![], vec![gun("Rifle")]);
    assert!(owners.iter().all(|o| o != "Defender"), "no strike-back rolls: {owners:?}");
    assert!(!fatigued, "a defender with no melee weapon is not made Fatigued by the fight");
    assert!(
        log.iter().any(|l| l == "Defender has no melee weapons - cannot strike back"),
        "the rule names itself in the battle log: {log:?}"
    );
}

#[test]
fn below_epoch_73_a_ranged_only_defender_is_still_fatigued() {
    let (owners, fatigued, _) = charge(EPOCH_72_PLAYTEST_RULES, vec![], vec![gun("Rifle")]);
    assert!(owners.iter().all(|o| o != "Defender"), "{owners:?}");
    assert!(fatigued, "today's behaviour below the gate: the empty strike-back slot still tires the defender");
}

#[test]
fn an_assault_weapons_melee_copy_still_strikes_back_at_epoch_73() {
    let copy = ShootProfile { name: "Assault Rifle".into(), attacks: 2, count: 1, printed_range: 24, ..Default::default() };
    let (owners, fatigued, _) = charge(EPOCH_73_V36, vec![copy], vec![gun("Rifle")]);
    assert!(owners.iter().any(|o| o == "Defender"), "an Assault weapon's melee copy counts: {owners:?}");
    assert!(fatigued, "a defender that struck back is Fatigued");
}

#[test]
fn a_defender_with_a_real_melee_weapon_is_unchanged_at_both_epochs() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        let (owners, fatigued, log) = charge(epoch, vec![blade("Club")], vec![gun("Rifle")]);
        assert!(owners.iter().any(|o| o == "Defender"), "epoch {epoch}: {owners:?}");
        assert!(fatigued, "epoch {epoch}");
        assert!(log.iter().all(|l| !l.contains("cannot strike back")), "epoch {epoch}: {log:?}");
    }
}
