use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::state::Kit;

// SHO-PAR-F4 — a dead model's ranged weapon dies with it. The table counts a special weapon's dice off the
// LIVING models' own kits; the core assumed its bearers fall last (`min(copies, alive)`), so a unit that lost
// its pistol bearers still fired the pistol. From EPOCH_73_V36, with one kit per living model, the core
// counts the living bearers too; without aligned kits the old number stays.

fn gun(name: &str, attacks: i64, count: i64, range: i64) -> ShootProfile {
    ShootProfile { name: name.into(), attacks, count, range, ..Default::default() }
}

/// Unit 0: five Assault Brothers, four alive. "Pistol" has 3 copies (1 attack each) in a unit of five, "Rifle"
/// is carried by all five. The four living kits: two carry the Pistol, all four the Rifle. Unit 1 is a joined
/// hero (one model, one single-copy weapon). Unit 2 is the target, 12" in front of the host.
fn squad() -> (State, Vec<UnitStatic>) {
    let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
    let lone = |name: &str, models: i64| UnitStatic {
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models, ..Default::default() },
        name: name.into(),
        model_count: models,
        wounds_max: vec![1; models as usize],
        ..Default::default()
    };
    let statics = vec![
        UnitStatic { shoot: vec![gun("Pistol", 3, 3, 18), gun("Rifle", 5, 5, 24)], ..lone("Brothers", 5) },
        UnitStatic { shoot: vec![gun("Hero Pistol", 1, 1, 18)], ..lone("Hero", 1) },
        lone("Target", 1),
    ];
    let mut st = four_unit_line();
    let keys: Vec<String> = ["a", "ah", "b", "bh"].iter().map(|k| k.to_string()).collect();
    let index = keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
    st.roster = Rc::new(Roster { keys, index, profile: vec![0, 1, 2, 2] });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile.clone(), profile], index: HashMap::new() });
    st.alive = vec![4, 0, 1, 0];
    st.positions[0] = (0..4).map(|i| [0.0, 0.0, i as f64 * 0.1 * IN2M]).collect();
    st.wounds[0] = vec![1; 4];
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M; 4];
    st.positions[3].clear();
    let kit = |weapons: Vec<u16>| Kit { weapons, equipment: 0, wounds_max: 1 };
    st.kits = vec![
        Rc::new(vec![kit(vec![0, 1]), kit(vec![0, 1]), kit(vec![1]), kit(vec![1])]),
        Rc::new(Vec::new()),
        Rc::new(Vec::new()),
        Rc::new(Vec::new()),
    ];
    st.kit_names = vec![
        Rc::new(vec!["Pistol".into(), "Rifle".into()]),
        Rc::new(Vec::new()),
        Rc::new(Vec::new()),
        Rc::new(Vec::new()),
    ];
    (st, statics)
}

/// The tray's per-weapon die counts for the host (`sighting` on): the host's four models all see the target.
fn tray(st: &State, statics: &[UnitStatic], epoch: u32) -> Vec<i64> {
    let mut sc = Scratch { rules_epoch: epoch, bearers_last: true, ..Default::default() };
    sighted_profiles_of(&statics[0], st, statics, 0, 2, &[], 6.0, &mut sc);
    sc.attacks
}

/// The expected-value half's per-weapon counts; `hero` joins the host so the folded leg runs.
fn ev(mut st: State, statics: &[UnitStatic], epoch: u32, hero: bool) -> Vec<i64> {
    if hero {
        st.alive[1] = 1;
    }
    let seams = Seams { rules_epoch: epoch, casualties_bearers_last: true, hero_attach: hero, ..Seams::default() };
    let mut sc = Scratch::default();
    member_profiles_of(statics, &st, 0, false, 6.0, seams, &mut sc);
    sc.attacks
}

/// Every attack die the host rolls at the target through the whole tray resolve (both sighting legs).
fn volley_dice(st: &State, statics: &[UnitStatic], epoch: u32, sighting: bool) -> i64 {
    let mut hold = advance_to(0.0);
    hold.kind = HOLD;
    hold.dest = None;
    hold.shoot = Some("b".into());
    let seams = Seams { rules_epoch: epoch, casualties_bearers_last: true, sighting, ..Seams::default() };
    let terrain = crate::terrain::Terrain::default();
    let (_, shot) = resolve_stochastic_tray_on_board(
        statics, st, &hold, &terrain, seams, &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(1),
    )
    .unwrap();
    shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "Brothers").map(|r| r.count).sum()
}

#[test]
fn full_volley_rolls_living_pistol_bearers_at_epoch_73() {
    let (st, statics) = squad();
    for sighting in [false, true] {
        assert_eq!(volley_dice(&st, &statics, EPOCH_73_V36, sighting), 6, "sighting={sighting}: 2 pistol + 4 rifle dice");
    }
}

#[test]
fn full_volley_keeps_the_bearers_last_dice_at_epoch_72() {
    let (st, statics) = squad();
    for sighting in [false, true] {
        assert_eq!(volley_dice(&st, &statics, EPOCH_72_PLAYTEST_RULES, sighting), 7, "sighting={sighting}: 3 pistol + 4 rifle dice");
    }
}

#[test]
fn tray_counts_living_pistol_bearers_at_epoch_73() {
    let (st, statics) = squad();
    assert_eq!(tray(&st, &statics, EPOCH_73_V36), vec![2, 4], "two living pistols; the rifle keeps its ratio");
}

#[test]
fn tray_keeps_the_bearers_last_count_at_epoch_72() {
    let (st, statics) = squad();
    assert_eq!(tray(&st, &statics, EPOCH_72_PLAYTEST_RULES), vec![3, 4], "min(3 copies, 4 alive)");
}

#[test]
fn tray_fires_nothing_when_no_living_model_carries_the_weapon() {
    let (mut st, statics) = squad();
    st.kits[0] = Rc::new((0..4).map(|_| Kit { weapons: vec![1], equipment: 0, wounds_max: 1 }).collect());
    assert_eq!(tray(&st, &statics, EPOCH_73_V36), vec![0, 4], "zero bearers, zero pistol dice");
    assert_eq!(tray(&st, &statics, EPOCH_72_PLAYTEST_RULES), vec![3, 4]);
}

#[test]
fn tray_without_aligned_kits_keeps_the_old_count_at_epoch_73() {
    let (mut st, statics) = squad();
    Rc::make_mut(&mut st.kits[0]).pop();
    assert_eq!(tray(&st, &statics, EPOCH_73_V36), vec![3, 4], "three kits for four living models");
    st.kits.clear();
    assert_eq!(tray(&st, &statics, EPOCH_73_V36), vec![3, 4], "no kits recorded at all");
}

#[test]
fn ev_counts_living_pistol_bearers_at_epoch_73() {
    let (st, statics) = squad();
    assert_eq!(ev(st, &statics, EPOCH_73_V36, false), vec![2, 4]);
}

#[test]
fn ev_keeps_the_bearers_last_count_at_epoch_72() {
    let (st, statics) = squad();
    assert_eq!(ev(st, &statics, EPOCH_72_PLAYTEST_RULES, false), vec![3, 4]);
}

#[test]
fn ev_folded_leg_counts_living_pistol_bearers_at_epoch_73() {
    let (st, statics) = squad();
    assert_eq!(ev(st, &statics, EPOCH_73_V36, true), vec![2, 4, 1], "host pistol, host rifle, hero pistol");
}

#[test]
fn ev_folded_leg_keeps_the_bearers_last_count_at_epoch_72() {
    let (st, statics) = squad();
    assert_eq!(ev(st, &statics, EPOCH_72_PLAYTEST_RULES, true), vec![3, 4, 1]);
}
