//! G4R3 F-MORALE-CHAIN (rules 3.6, `EPOCH_73_V36`): a lone hero (its host dead) that a volley wounds
//! but does not kill makes the unit test morale, like the table: the table's unit is the host plus its
//! joined heroes, so it counts the CHAIN's models (`combined_alive` over `combined_total`) and the
//! CHAIN's wounds. The core read the hero as a unit of its own (Tough measured against its own max)
//! and stayed silent while the chain stood at half or less (aof_1000_net_001 act 18: 1 of 11 models).
use super::super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::dice::{ShootResult, Tray};

/// Unit 0 = the shooter (8 shots, Quality 4+), unit 2 = the target host, DEAD, a squad of five, unit 3
/// = its joined hero (Tough 3, saves on 5+), the only living model. Unit 1 stays out of the game.
fn line() -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = hero_line();
    statics[0].ctx = Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() };
    statics[0].shoot = vec![ShootProfile { name: "Rifle".into(), attacks: 8, count: 1, range: 24, ..Default::default() }];
    statics[2] = UnitStatic { name: "Acolytes".into(), model_count: 5, wounds_max: vec![1; 5], ..Default::default() };
    statics[3] = UnitStatic {
        ctx: Ctx { quality: 4, defense: 5, tough: 3, models: 1, ..Default::default() },
        name: "Birdman Champion".into(),
        model_count: 1,
        wounds_max: vec![3],
        ..Default::default()
    };
    let keys = st.roster.keys.clone();
    let index = keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
    st.roster = Rc::new(Roster { keys, index, profile: vec![0, 1, 2, 3] });
    let base = st.profiles.list[0].clone();
    st.profiles = Rc::new(Profiles { list: vec![base; 4], index: HashMap::new() });
    st.alive = vec![1, 0, 0, 1];
    st.wounds[2] = vec![0; 5];
    st.wounds[3] = vec![3];
    st.attached = Rc::new(vec![vec![], vec![], vec![3], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None, Some(2)]);
    st.positions[1].clear();
    st.positions[2].clear();
    for u in 0..4 {
        Rc::make_mut(&mut st.radii)[u] = vec![IN2M];
    }
    (st, statics)
}

/// One HOLD volley of unit 0 at the lone hero (`bh`); returns the state after and the shot.
fn volley(seed: i64, epoch: u32) -> (State, ShootResult) {
    let (st, statics) = line();
    let mut hold = advance_to(0.0);
    hold.kind = HOLD;
    hold.dest = None;
    hold.shoot = Some("bh".into());
    let seams = Seams {
        rules_epoch: epoch, hero_attach: true, hero_last: true, hero_counts_in_size: true, ..Seams::default()
    };
    let terrain = crate::terrain::Terrain::default();
    resolve_stochastic_tray_on_board(
        &statics, &st, &hold, &terrain, seams, &mut crate::rng::GodotRng::new(0), &mut Tray::seeded(seed),
    )
    .unwrap()
}

/// The morale die: the only roll signed by the target (the volley's dice are signed by the shooter).
fn morale_dice(shot: &ShootResult) -> i64 {
    shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "Birdman Champion").map(|r| r.count).sum()
}

/// Seeds where the hero ends alive with 1 or 2 of its 3 wounds left: wounded, not killed.
fn wounded_not_killed(epoch: u32) -> Vec<(i64, i64, i64)> {
    (1..=80)
        .filter_map(|seed| {
            let (after, shot) = volley(seed, epoch);
            let left: i64 = after.wounds[3].iter().sum();
            (after.alive[3] == 1 && left < 3).then_some((seed, left, morale_dice(&shot)))
        })
        .collect()
}

#[test]
fn the_fixture_wounds_the_hero_without_killing_it() {
    let cases = wounded_not_killed(EPOCH_73_V36);
    assert!(cases.iter().any(|c| c.1 == 2), "a seed leaves the hero at 2 of 3 wounds: {cases:?}");
    assert!(cases.iter().any(|c| c.1 == 1), "a seed leaves the hero at 1 of 3 wounds: {cases:?}");
}

/// RED on main: 1 of 6 chain models alive is at half or less, so ANY wound tests — the core only tested
/// once the hero's own Tough was at half (1 of 3 left).
#[test]
fn a_wounded_lone_hero_tests_morale_at_epoch_73() {
    for (seed, left, dice) in wounded_not_killed(EPOCH_73_V36) {
        assert_eq!(dice, 1, "seed {seed}: hero at {left} of 3 wounds left must roll one morale die");
    }
}

/// Below 73 the hero is its own unit: only the half-Tough case (1 of 3 left) tests.
#[test]
fn below_epoch_73_only_the_half_tough_hero_tests() {
    for (seed, left, dice) in wounded_not_killed(EPOCH_72_PLAYTEST_RULES) {
        assert_eq!(dice, i64::from(left == 1), "seed {seed}: epoch 72, {left} of 3 wounds left");
    }
}

/// No wound lands, no test: a volley that wounds nothing never rolls morale at 73.
#[test]
fn an_unwounded_lone_hero_does_not_test() {
    let unwounded: Vec<_> = (1..=80)
        .map(|seed| volley(seed, EPOCH_73_V36))
        .filter(|(after, _)| after.wounds[3].iter().sum::<i64>() == 3)
        .collect();
    assert!(!unwounded.is_empty(), "fixture guard: some seed wounds nothing");
    for (_, shot) in unwounded {
        assert_eq!(morale_dice(&shot), 0);
    }
}
