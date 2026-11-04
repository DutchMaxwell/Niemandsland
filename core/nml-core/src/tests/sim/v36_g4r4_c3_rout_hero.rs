//! Rules 3.6 row G4R4 R3-C3 (parity diagnosis G4R3 OBS-1; after-states of gf_1000_net_006 act 11,
//! gf_015 act 24, gf_021 act 12, aof_039 act 14): a unit that fails its morale test at half strength is
//! Routed WITH its joined heroes - the chain is destroyed, not only the host.
//!
//! The core cleared the host's models alone, so a hero stayed standing after a rout and the AI search
//! priced a rout that left it on the table. From `EPOCH_73_V36` the living attached heroes go too, and the
//! battle log names the rule. Below 73 the host-only clear stays, byte for byte.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::read_act_header;

/// A real squad (three models, Quality 6+ so the test is lost most rolls) and a real hero, both built from
/// profiles the way the game builds a unit.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "squad":{"unit_id":"squad","name":"Squad","quality":6,
    "defense":4,"tough":1,"wounds_max":[1,1,1],"model_count":3,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Spear","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "champion":{"unit_id":"champion","name":"Champion","quality":6,
    "defense":4,"tough":3,"wounds_max":[3],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Greatsword","range":0,"attacks":3,"count":1,"ap":0,"rules":[]}]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Unit 2 = the squad with one of three models left (below half), unit 3 = its joined Champion.
fn line(epoch: u32) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![], vec![[2.5 * IN2M, 0.0, 0.0]], vec![[2.54 * IN2M, 0.0, 0.0]]];
    st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M], vec![IN2M]]);
    st.wounds = vec![vec![1], vec![], vec![1], vec![3]];
    st.alive = vec![1, 0, 1, 1];
    st.attached = Rc::new(vec![vec![], vec![], vec![3], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None, Some(2)]);
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    let mut build = |key: &str| UnitStatic::build_for(&mut reg, header.profiles.get(key).expect(key), epoch);
    let (squad, champion) = (build("squad"), build("champion"));
    let foe = UnitStatic { name: "Foe".into(), model_count: 1, wounds_max: vec![1], ..Default::default() };
    (st, vec![foe.clone(), foe, squad, champion])
}

/// The first seed whose melee morale test routs the squad.
fn routed(epoch: u32) -> (State, ShootResult) {
    let (st, statics) = line(epoch);
    let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Seams::default() };
    (0..400)
        .map(|seed| {
            let (mut next, mut shot) = (st.clone(), ShootResult::default());
            tray_morale(&mut next, &statics, 2, true, seams, &mut Tray::seeded(seed), &mut shot, None, None);
            (next, shot)
        })
        .find(|(next, _)| next.alive[2] == 0)
        .expect("a seed where the squad fails its morale test and routs")
}

/// The row: the Champion goes with the squad - no models, no wounds, no position - and the log names the rule.
#[test]
fn a_rout_takes_the_joined_hero_with_it_from_73() {
    let (next, shot) = routed(EPOCH_73_V36);
    assert_eq!(next.alive[3], 0, "the Champion is destroyed with the unit: {:?}", next.wounds);
    assert!(next.wounds[3].is_empty() && next.positions[3].is_empty(), "no slot left: {:?} {:?}", next.wounds, next.positions);
    assert!(
        shot.log.iter().any(|l| l.starts_with("Routed:") && l.contains("Champion")),
        "the applied rule names itself: {:?}",
        shot.log
    );
}

/// Below 73 the recorded corpora keep the host-only clear: the Champion stands.
#[test]
fn below_73_the_hero_stays_standing() {
    let (next, shot) = routed(EPOCH_72_PLAYTEST_RULES);
    assert_eq!((next.alive[3], next.wounds[3].clone()), (1, vec![3]), "the hero is untouched below the gate");
    assert!(shot.log.iter().all(|l| !l.contains("Routed")), "{:?}", shot.log);
}

/// CONTROL: a unit that only gets Shaken (not below half) keeps its hero at both epochs.
#[test]
fn a_shaken_unit_keeps_its_hero() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        let (mut st, statics) = line(epoch);
        st.alive[2] = 3;
        st.wounds[2] = vec![1, 1, 1];
        st.positions[2] = vec![[2.5 * IN2M, 0.0, 0.0], [2.52 * IN2M, 0.0, 0.0], [2.54 * IN2M, 0.0, 0.0]];
        Rc::make_mut(&mut st.radii)[2] = vec![IN2M; 3];
        let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Seams::default() };
        for seed in 0..60 {
            let (mut next, mut shot) = (st.clone(), ShootResult::default());
            tray_morale(&mut next, &statics, 2, true, seams, &mut Tray::seeded(seed), &mut shot, None, None);
            assert_eq!((next.alive[2], next.alive[3]), (3, 1), "epoch {epoch} seed {seed}: a full-strength unit is never Routed");
        }
    }
}
