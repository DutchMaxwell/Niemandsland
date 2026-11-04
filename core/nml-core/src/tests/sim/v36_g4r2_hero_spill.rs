//! Rules 3.6 row G4R2 F-SPILL (ruling D1): a joined hero is part of the unit, so the wounds the host's
//! models cannot soak go on to the living joined heroes, heroes LAST.
//!
//! The core landed a volley's or a strike's unsaved wounds on the host's slots only and dropped the rest, so
//! a hero beside a wiped host stayed alive and the core then rolled a morale test the table never reaches.
//! From `EPOCH_73_V36` the pool's surplus goes on to the heroes in `State::attached` order. Below 73 the
//! surplus is still dropped, byte for byte. Replay rows: aof_1000_net_003 act 9, gf_1000_net_010 act 6
//! (shooting) and aof_1000_net_022 act 20 (melee).
use super::*;
use crate::acts::EPOCH_73_V36;
use crate::read_act_header;

/// A real gunner with a ranged and a melee weapon, `ATT` attacks each, built the way the game builds a unit.
const SPILL_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "gunner":{"unit_id":"gunner","name":"Gunner","quality":2,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Volley Gun","range":24,"attacks":ATT,"count":1,"ap":0,"rules":[]},
      {"name":"Cleaver","range":0,"attacks":ATT,"count":1,"ap":0,"rules":[]}]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Attacker "a" (`attacks` per weapon) vs host "b" (two 1-wound models) with a joined hero "bh" (one Tough(3)
/// model, 3 wounds): capacity 5. `gap_in` is the host's distance (the charge fixtures use 2.5").
fn spill_line(epoch: u32, attacks: i64, gap_in: f64) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    st.positions = vec![
        vec![[0.0, 0.0, 0.0]],
        vec![],
        vec![[gap_in * IN2M, 0.0, 0.0], [(gap_in + 0.02) * IN2M, 0.0, 0.0]],
        vec![[(gap_in + 0.04) * IN2M, 0.0, 0.0]],
    ];
    st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M; 2], vec![IN2M]]);
    st.wounds = vec![vec![1], vec![], vec![1, 1], vec![3]];
    st.alive = vec![1, 0, 2, 1];
    st.attached = Rc::new(vec![vec![], vec![], vec![3], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None, Some(2)]);
    let header = read_act_header(&SPILL_HEADER.replace("ATT", &attacks.to_string())).expect("SPILL_HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    let gunner = UnitStatic::build_for(&mut reg, header.profiles.get("gunner").expect("gunner"), epoch);
    let body = |name: &str, models: i64, wounds: Vec<i64>, tough: i64| {
        let mut u = UnitStatic { name: name.into(), model_count: models, wounds_max: wounds, ..Default::default() };
        u.ctx.defense = 4;
        u.ctx.tough = tough;
        u
    };
    (st, vec![gunner, UnitStatic { name: "ah".into(), ..Default::default() }, body("b", 2, vec![1, 1], 1), body("bh", 1, vec![3], 3)])
}

fn activation(st: &State, statics: &[UnitStatic], melee: bool, seed: i64, epoch: u32) -> (State, ShootResult) {
    let action = Action {
        kind: if melee { CHARGE } else { HOLD },
        unit: "a".into(),
        dest: None,
        shoot: if melee { None } else { Some("b".into()) },
        charge: if melee { Some("b".into()) } else { None },
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    };
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(seed));
    let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Seams::default() };
    resolve_stochastic_tray_on_board(statics, st, &action, &Terrain::default(), seams, &mut rng, &mut tray).unwrap()
}

/// 30 attacks at Quality 2+ against Defense 4+ leave far more unsaved wounds than the unit's capacity of 5.
fn flood(melee: bool, epoch: u32) -> (State, ShootResult) {
    let (st, statics) = spill_line(epoch, 30, if melee { 2.5 } else { 5.0 });
    let out = activation(&st, &statics, melee, 3, epoch);
    assert!(out.1.caused >= 5, "fixture: at least the unit's 5 wounds of capacity are unsaved: {:?}", out.1.rolls);
    out
}

/// The row, shooting: the host's two models die and the surplus kills the hero; no morale roll follows.
#[test]
fn a_volleys_surplus_wounds_reach_the_joined_hero_from_73() {
    let (next, shot) = flood(false, EPOCH_73_V36);
    assert_eq!((next.alive[2], next.alive[3]), (0, 0), "host and hero both die: {:?}", next.wounds);
    assert!(next.wounds[3].is_empty(), "the hero has no wounds left: {:?}", next.wounds);
    assert_eq!(shot.rolls.last().map(|r| r.kind), Some("defense"), "no trailing morale roll: {:?}", shot.rolls);
    assert!(shot.log.iter().any(|l| l.starts_with("Hero:") && l.contains("bh")), "the applied rule names itself: {:?}", shot.log);
}

/// The row, melee (aof_1000_net_022 act 20): the charging blade's surplus kills the hero too.
#[test]
fn a_strikes_surplus_wounds_reach_the_joined_hero_from_73() {
    let (next, shot) = flood(true, EPOCH_73_V36);
    assert_eq!((next.alive[2], next.alive[3]), (0, 0), "host and hero both die: {:?}", next.wounds);
    assert!(next.wounds[3].is_empty(), "the hero has no wounds left: {:?}", next.wounds);
    assert!(shot.log.iter().any(|l| l.starts_with("Hero:") && l.contains("bh")), "the applied rule names itself: {:?}", shot.log);
}

/// Below 73 the recorded corpora keep dropping the surplus: the hero survives with all 3 wounds.
#[test]
fn below_73_the_surplus_is_still_dropped() {
    for melee in [false, true] {
        let (next, _) = flood(melee, EPOCH_73_V36 - 1);
        assert_eq!(next.alive[2], 0, "melee {melee}: the host dies");
        assert_eq!((next.alive[3], next.wounds[3].clone()), (1, vec![3]), "melee {melee}: the hero is untouched");
    }
}

/// CONTROL, heroes LAST: one unsaved wound stays on the host; the hero keeps all 3 wounds at 73 too.
#[test]
fn a_single_wound_stays_on_the_host_and_spares_the_hero() {
    let (st, statics) = spill_line(EPOCH_73_V36, 1, 5.0);
    let (next, shot) = (0..400)
        .map(|s| activation(&st, &statics, false, s, EPOCH_73_V36))
        .find(|(_, shot)| shot.caused == 1)
        .expect("a seed with exactly one unsaved wound");
    assert_eq!(next.alive[2], 1, "the host loses one model: {:?}", next.wounds);
    assert_eq!((next.alive[3], next.wounds[3].clone()), (1, vec![3]), "the hero is assigned wounds last: {:?}", shot.log);
}
