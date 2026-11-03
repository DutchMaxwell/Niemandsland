//! FAB-B4 tests (rules 3.6, lane melee): from `EPOCH_73_V36` a defender whose every melee weapon is a
//! SPENT Limited weapon counts as "no melee" — it neither strikes back nor is made Fatigued, the table's
//! `_solo_strike_back_block` "spent" read. Below the gate the old behaviour stands.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

fn blade(name: &str, limited: bool) -> ShootProfile {
    ShootProfile { name: name.into(), attacks: 2, count: 1, range: 0, limited, ..Default::default() }
}

/// One charge melee: a 3-model Blade charger into a 3-model defender whose melee list is
/// `def_melee` and whose already-spent Limited names are `spent`. Returns the attack-roll owners in
/// tray order, the defender's fatigue flag after the fight and the battle log.
fn charge(epoch: u32, def_melee: Vec<ShootProfile>, spent: &[&str]) -> (Vec<String>, bool, Vec<String>) {
    let profile: Profile = serde_json::from_str(r#"{"unit_id":"u","name":"u"}"#).unwrap();
    let statics = vec![
        UnitStatic {
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 3, ..Default::default() },
            name: "Charger".into(),
            melee: vec![blade("Blade", false)],
            model_count: 3,
            wounds_max: vec![1; 3],
            ..Default::default()
        },
        UnitStatic {
            ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 3, ..Default::default() },
            name: "Defender".into(),
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
    for name in spent {
        Rc::make_mut(&mut st.limited_used)[1].push((*name).into());
    }

    let seams = Seams { rules_epoch: epoch, ..Default::default() };
    let mut tray = Tray::seeded(27);
    let mut shot = ShootResult::default();
    tray_charge(&statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None));
    let owners = shot.rolls.iter().filter(|r| r.kind == "attack").map(|r| r.owner.clone()).collect();
    (owners, st.fatigued[1], shot.log)
}

#[test]
fn an_all_spent_limited_defender_neither_strikes_back_nor_tires_at_epoch_73() {
    let (owners, fatigued, log) = charge(EPOCH_73_V36, vec![blade("Blade", true)], &["Blade"]);
    assert!(owners.iter().all(|o| o != "Defender"), "no strike-back rolls: {owners:?}");
    assert!(!fatigued, "an all-spent-Limited defender is not made Fatigued by the fight");
    assert!(
        log.iter().any(|l| l == "Defender has no melee weapons - cannot strike back"),
        "the rule names itself in the battle log: {log:?}"
    );
}

#[test]
fn below_epoch_73_an_all_spent_limited_defender_is_still_fatigued() {
    let (_, fatigued, _) = charge(EPOCH_72_PLAYTEST_RULES, vec![blade("Blade", true)], &["Blade"]);
    assert!(fatigued, "today's behaviour below the gate: the empty strike-back slot still tires the defender");
}

#[test]
fn a_still_unspent_limited_defender_strikes_back_and_tires_at_epoch_73() {
    let (owners, fatigued, log) = charge(EPOCH_73_V36, vec![blade("Blade", true)], &[]);
    assert!(owners.iter().any(|o| o == "Defender"), "an unspent Limited weapon still strikes: {owners:?}");
    assert!(fatigued, "a defender that struck back is Fatigued");
    assert!(log.iter().all(|l| !l.contains("cannot strike back")), "{log:?}");
}
