//! SHO-21b tests (rules 3.6, lane shoot): Hazardous — every unmodified 1 on a
//! Hazardous weapon wounds the BEARER model for X (the larger Blast/Deadly, else
//! 1), never the unit's pool. Below EPOCH_73_V36 nothing changes (no self-wound).
//! The melee twin feeds the 3.6 "took more wounds" loser comparison.
use super::super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::dice::{ShootResult, Tray};
use crate::state::{Kit, Profile, Profiles, Roster};

/// A Hazardous gunner (unit 0, one Tough(10) model carrying a three-attack
/// Hazardous rifle) 12" from the target (unit 2). Seed 283 draws three
/// unmodified 1s on the attack roll, so every die is a self-wound.
fn shooter_line(blast: i64, deadly: i64, hazardous: bool) -> (State, Vec<UnitStatic>) {
    let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: vec!["a".into(), "ah".into(), "b".into(), "bh".into()],
        index: ["a", "ah", "b", "bh"].iter().enumerate().map(|(i, k)| (k.to_string(), i)).collect(),
        profile: vec![0, 1, 2, 2],
    });
    st.profiles = Rc::new(Profiles {
        list: vec![profile.clone(), profile.clone(), profile],
        index: HashMap::new(),
    });
    st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None, None]);
    st.alive = vec![1, 0, 1, 0];
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    st.wounds[0] = vec![10];
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M];
    st.positions[1] = vec![];
    st.wounds[1] = vec![];
    Rc::make_mut(&mut st.radii)[1] = vec![];
    st.positions[2] = vec![[12.0 * IN2M, 0.0, 0.0]];
    st.wounds[2] = vec![1];
    Rc::make_mut(&mut st.radii)[2] = vec![IN2M];
    st.positions[3] = vec![];
    st.wounds[3] = vec![];
    Rc::make_mut(&mut st.radii)[3] = vec![];
    st.kits = vec![
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 10 }]),
        Rc::new(vec![]),
        Rc::new(vec![]),
        Rc::new(vec![]),
    ];
    st.kit_names = vec![
        Rc::new(vec!["Hazardous gun".into()]),
        Rc::new(vec![]),
        Rc::new(vec![]),
        Rc::new(vec![]),
    ];
    let shooter = UnitStatic {
        name: "Shooter".into(),
        model_count: 1,
        wounds_max: vec![10],
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
        shoot: vec![ShootProfile {
            name: "Hazardous gun".into(),
            attacks: 3,
            count: 1,
            range: 24,
            blast,
            deadly,
            hazardous,
            ..Default::default()
        }],
        ..Default::default()
    };
    let target = UnitStatic {
        name: "Target".into(),
        model_count: 1,
        wounds_max: vec![1],
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
        ..Default::default()
    };
    (
        st,
        vec![shooter, UnitStatic { name: "ah".into(), ..Default::default() }, target, UnitStatic { name: "bh".into(), ..Default::default() }],
    )
}

fn hold_shoot(st: &State, statics: &[UnitStatic], epoch: u32) -> (State, ShootResult) {
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
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    resolve_stochastic_tray_on_board(
        statics, st, &action, &crate::terrain::Terrain::default(), seams,
        &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(283),
    )
    .unwrap()
}

/// Control: rules 3.5 has no bearer self-wound, so the shooter is untouched even
/// though the same three 1s are rolled. Passes before and after the fix.
#[test]
fn a_hazardous_volley_leaves_the_shooter_unhurt_at_epoch_72() {
    let (st, statics) = shooter_line(0, 0, true);
    let (next, shot) = hold_shoot(&st, &statics, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(next.wounds[0], vec![10], "rules 3.5: no self-wound");
    assert!(shot.log.iter().all(|l| !l.contains("Hazardous:")), "{:?}", shot.log);
}

/// Control: a non-Hazardous weapon never wounds its bearer at 73 either.
#[test]
fn a_plain_volley_never_wounds_the_shooter_at_epoch_73() {
    let (st, statics) = shooter_line(0, 0, false);
    let (next, shot) = hold_shoot(&st, &statics, EPOCH_73_V36);
    assert_eq!(next.wounds[0], vec![10], "no Hazardous tag, no self-wound");
    assert!(shot.log.iter().all(|l| !l.contains("Hazardous:")), "{:?}", shot.log);
}

/// Rules 3.6: with no Blast/Deadly each unmodified 1 costs the bearer 1 wound.
#[test]
fn a_hazardous_volley_wounds_the_bearer_one_per_one_at_epoch_73() {
    let (st, statics) = shooter_line(0, 0, true);
    let (next, shot) = hold_shoot(&st, &statics, EPOCH_73_V36);
    assert_eq!(next.wounds[0], vec![7], "three 1s, one wound each");
    assert!(
        shot.log.iter().any(|l| l.contains("Hazardous:") && l.contains("model 1") && l.contains("takes 1 wound")),
        "the self-wound names the bearer model: {:?}", shot.log
    );
}

/// Rules 3.6: Blast(X)/Deadly(X) scale each unmodified 1 (the larger if both).
#[test]
fn blast_scales_each_hazardous_self_wound_at_epoch_73() {
    let (st, statics) = shooter_line(3, 0, true);
    let (next, shot) = hold_shoot(&st, &statics, EPOCH_73_V36);
    assert_eq!(next.wounds[0], vec![1], "three 1s x Blast(3) = 9");
    assert!(
        shot.log.iter().any(|l| l.contains("Hazardous:") && l.contains("takes 3 wounds")),
        "the line names the X: {:?}", shot.log
    );
}

/// A charger with a two-attack Hazardous blade in base contact with an unarmed
/// defender; no other die decides the melee, so the verdict is the self-wound.
fn melee_duel() -> (State, Vec<UnitStatic>) {
    let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: vec!["a".into(), "b".into()],
        index: ["a", "b"].iter().enumerate().map(|(i, k)| (k.to_string(), i)).collect(),
        profile: vec![0, 1],
    });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 1];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions[0] = vec![[2.0 * IN2M, 0.0, 0.0]];
    st.wounds[0] = vec![5];
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M];
    st.positions[1] = vec![[0.0, 0.0, 0.0]];
    st.wounds[1] = vec![1];
    Rc::make_mut(&mut st.radii)[1] = vec![IN2M];
    st.kits = vec![
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 5 }]),
        Rc::new(vec![]),
    ];
    st.kit_names = vec![Rc::new(vec!["Hazardous blade".into()]), Rc::new(vec![])];
    let striker = UnitStatic {
        name: "Charger".into(),
        model_count: 1,
        wounds_max: vec![5],
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
        melee: vec![ShootProfile {
            name: "Hazardous blade".into(),
            attacks: 2,
            count: 1,
            range: 0,
            hazardous: true,
            ..Default::default()
        }],
        ..Default::default()
    };
    let defender = UnitStatic {
        name: "Defender".into(),
        model_count: 1,
        wounds_max: vec![1],
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
        ..Default::default()
    };
    (st, vec![striker, defender])
}

fn fight(epoch: u32) -> (State, Option<usize>, ShootResult) {
    let (mut st, statics) = melee_duel();
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    let mut tray = Tray::seeded(283);
    let mut shot = ShootResult::default();
    let loser = tray_charge_with_self_wounds(
        &statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None), 0,
    );
    (st, loser, shot)
}

/// Control: at 72 the two rolled 1s are no wounds at all, both sides dealt 0 and
/// nobody tests. Passes before and after the fix.
#[test]
fn a_hazardous_strike_is_no_self_wound_and_no_loser_at_epoch_72() {
    let (next, loser, _shot) = fight(EPOCH_72_PLAYTEST_RULES);
    assert_eq!(next.wounds[0], vec![5], "rules 3.5: the striker is untouched");
    assert_eq!(loser, None, "0 dealt against 0 dealt: a tie");
}

/// Rules 3.6: the striker's own Hazardous 1s are wounds it TOOK, so the charger
/// loses the comparison it tied at 72.
#[test]
fn the_strikers_hazardous_self_wounds_flip_the_melee_loser_at_epoch_73() {
    let (next, loser, shot) = fight(EPOCH_73_V36);
    assert_eq!(next.wounds[0], vec![3], "two 1s, one wound each");
    assert_eq!(loser, Some(0), "the charger took 2 against 0: it loses");
    assert!(
        shot.log.iter().any(|l| l.contains("Hazardous:") && l.contains("model 1")),
        "the self-wound names the bearer model: {:?}", shot.log
    );
}
