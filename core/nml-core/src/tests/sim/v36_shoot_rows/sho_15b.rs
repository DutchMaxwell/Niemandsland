//! SHO-15b tests (rules 3.6, lane shoot): a Scourge melee strike counts every unmodified Defense 1
//! as phantom wounds (the map's phantom_wounds_per_save_one, 2) in the melee-winner tally, against
//! the side that rolled it, and nowhere else: nothing is removed. Below EPOCH_73_V36 the tally is
//! the real wounds alone; a non-Scourge blade is unchanged at 73.
use super::super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::dice::{ShootResult, Tray};
use crate::state::{Kit, Profile, Profiles, Roster};

/// A charger (unit 0) with a one-attack blade against a five-wound defender (unit 1) with a
/// two-attack blade, both in base contact. `scourge` stamps the charger's blade only.
fn duel(scourge: bool) -> (State, Vec<UnitStatic>) {
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
    st.wounds[1] = vec![5];
    Rc::make_mut(&mut st.radii)[1] = vec![IN2M];
    st.kits = vec![
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 5 }]),
        Rc::new(vec![Kit { weapons: vec![0], equipment: 0, wounds_max: 5 }]),
    ];
    st.kit_names = vec![
        Rc::new(vec!["Scourge blade".into()]),
        Rc::new(vec!["Plain blade".into()]),
    ];
    let striker = UnitStatic {
        name: "Charger".into(),
        model_count: 1,
        wounds_max: vec![5],
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
        melee: vec![ShootProfile {
            name: "Scourge blade".into(),
            attacks: 1,
            count: 1,
            range: 0,
            rules: if scourge { vec!["Scourge".into()] } else { Vec::new() },
            ..Default::default()
        }],
        ..Default::default()
    };
    let defender = UnitStatic {
        name: "Defender".into(),
        model_count: 1,
        wounds_max: vec![5],
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() },
        melee: vec![ShootProfile {
            name: "Plain blade".into(),
            attacks: 2,
            count: 1,
            range: 0,
            ..Default::default()
        }],
        ..Default::default()
    };
    (st, vec![striker, defender])
}

fn fight(scourge: bool, epoch: u32, seed: i64) -> (State, Option<usize>, ShootResult) {
    let (mut st, statics) = duel(scourge);
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    let mut tray = Tray::seeded(seed);
    let mut shot = ShootResult::default();
    let loser = tray_charge_with_self_wounds(
        &statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None), 0,
    );
    (st, loser, shot)
}

fn defender_ones(shot: &ShootResult) -> i64 {
    shot.rolls.iter()
        .filter(|r| r.kind == "defense" && r.owner == "Defender")
        .flat_map(|r| r.faces.iter())
        .filter(|&&f| f == 1)
        .count() as i64
}

/// Seeds where rules 3.5 already gives the charger the loss on real wounds, yet the defender rolled
/// at least one unmodified 1 on its block dice — the phantom wounds can flip the verdict. Read from
/// each run, so a shifted dice stream fails as "fixture", never as a silent pass.
fn flip_seeds() -> Vec<i64> {
    (0..400)
        .filter(|&seed| {
            let (_, loser, shot) = fight(true, EPOCH_72_PLAYTEST_RULES, seed);
            loser == Some(0) && defender_ones(&shot) > 0
        })
        .collect()
}

fn no_scourge_line(shot: &ShootResult) -> bool {
    shot.log.iter().all(|l| !l.starts_with("Scourge:"))
}

/// NEW leg: at 73 the defender's Scourge 1s are wounds it TOOK, so the charger now wins the melee
/// and the log names the phantom count and its effect.
#[test]
fn scourge_phantom_wounds_flip_the_melee_loser_at_epoch_73() {
    let seeds = flip_seeds();
    assert!(!seeds.is_empty(), "fixture: no seed leaves the charger losing on real wounds with a 1 on the defender's saves");
    for seed in seeds {
        let (_, loser, shot) = fight(true, EPOCH_73_V36, seed);
        assert_eq!(loser, Some(1), "seed {seed}: the Scourge phantom wounds put the defender behind");
        assert!(
            shot.log.iter().any(|l| l.starts_with("Scourge: 2 phantom wounds count for Defender in the melee result")),
            "seed {seed}: the rule must name the phantom count: {:?}", shot.log
        );
        assert!(
            shot.log.iter().any(|l| l.starts_with("Scourge:") && l.ends_with("they decide it")),
            "seed {seed}: the phantom wounds decided this melee: {:?}", shot.log
        );
    }
}

/// OLD leg: at 72 the same phantom wounds count nowhere; the real wounds keep the charger losing.
#[test]
fn scourge_ones_do_not_count_at_epoch_72() {
    let seeds = flip_seeds();
    assert!(!seeds.is_empty(), "fixture: no seed for the 72 leg");
    for seed in seeds {
        let (_, loser, shot) = fight(true, EPOCH_72_PLAYTEST_RULES, seed);
        assert_eq!(loser, Some(0), "seed {seed}: 72 reads the real wounds alone");
        assert!(no_scourge_line(&shot), "seed {seed}: no rule line below the epoch: {:?}", shot.log);
    }
}

/// Control: at 73 a plain blade leaves the same seed's verdict exactly where 72 had it.
#[test]
fn a_plain_blade_is_unchanged_at_epoch_73() {
    let seeds = flip_seeds();
    assert!(!seeds.is_empty(), "fixture: no seed for the control");
    for seed in seeds {
        let (_, loser, shot) = fight(false, EPOCH_73_V36, seed);
        assert_eq!(loser, Some(0), "seed {seed}: only Scourge 1s count");
        assert!(no_scourge_line(&shot), "seed {seed}: no rule line without Scourge: {:?}", shot.log);
    }
}
