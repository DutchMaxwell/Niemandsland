//! Rules 3.6 row G4R4 R3-C1 (replay rows aof_1000_net_021 act 35, aof_026 act 31, aof_027 act 19, aof_037 act 32):
//! a joined hero is part of the unit, so a charge that wipes the HOST's models while the hero stands does not
//! end the strike-back - the hero strikes back for the unit before the melee result.
//!
//! The core gated the defender's strike-back on the HOST's alive count alone and went straight to the morale
//! die. From `EPOCH_73_V36` the gate reads the host plus its living joined heroes (`combined_alive`). Below 73
//! the host-only gate stays, byte for byte.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::read_act_header;

/// A real charger and a real hero, both built the way the game builds a unit from a profile.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "charger":{"unit_id":"charger","name":"Charger","quality":2,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Cleaver","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]},
  "champion":{"unit_id":"champion","name":"Champion","quality":3,
    "defense":4,"tough":6,"wounds_max":[6],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Greatsword","range":0,"attacks":3,"count":1,"ap":0,"rules":[]}]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Charger "a" against a host "b" of `models` models with `wounds` wounds each and a joined six-wound hero
/// "bh" (Champion).
fn line(epoch: u32, models: usize, wounds: i64) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    let host_at = |k: usize| [(2.5 + 0.02 * k as f64) * IN2M, 0.0, 0.0];
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![], (0..models).map(host_at).collect(), vec![[2.54 * IN2M, 0.0, 0.0]]];
    st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M; models], vec![IN2M]]);
    st.wounds = vec![vec![1], vec![], vec![wounds; models], vec![6]];
    st.alive = vec![1, 0, models as i64, 1];
    st.attached = Rc::new(vec![vec![], vec![], vec![3], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None, Some(2)]);
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    let mut build = |key: &str| UnitStatic::build_for(&mut reg, header.profiles.get(key).expect(key), epoch);
    let (charger, champion) = (build("charger"), build("champion"));
    let host = UnitStatic { name: "Host".into(), model_count: models as i64, wounds_max: vec![wounds; models], ..Default::default() };
    (st, vec![charger, UnitStatic { name: "ah".into(), ..Default::default() }, host, champion])
}

fn charge(st: &State, statics: &[UnitStatic], seed: i64, epoch: u32) -> (State, ShootResult) {
    let action = Action {
        kind: CHARGE,
        unit: "a".into(),
        dest: None,
        shoot: None,
        charge: Some("b".into()),
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    };
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(seed));
    let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Seams::default() };
    resolve_stochastic_tray_on_board(statics, st, &action, &Terrain::default(), seams, &mut rng, &mut tray).unwrap()
}

/// The first seed whose charge wipes the host and leaves the hero standing (two attacks, one host wound).
fn host_wiped(epoch: u32) -> (State, ShootResult) {
    let (st, statics) = line(epoch, 1, 1);
    (0..400)
        .map(|s| charge(&st, &statics, s, epoch))
        .find(|(next, _)| next.alive[2] == 0 && next.alive[3] == 1)
        .expect("a seed where the charger wipes the host and the hero lives")
}

fn hero_rolls(shot: &ShootResult) -> usize {
    shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "Champion").count()
}

/// The row: the host is gone, the hero stands - the hero strikes back and the log names the rule.
#[test]
fn a_joined_hero_strikes_back_for_a_wiped_host_from_73() {
    let (next, shot) = host_wiped(EPOCH_73_V36);
    assert!(hero_rolls(&shot) >= 1, "the Champion rolls its strike-back dice: {:?}", shot.rolls);
    assert!(next.fatigued[3] || next.fatigued[2], "the strike-back tires the unit: {:?}", next.fatigued);
    assert!(
        shot.log.iter().any(|l| l.starts_with("Hero:") && l.contains("strike")),
        "the applied rule names itself: {:?}",
        shot.log
    );
}

/// Below 73 the recorded corpora keep the host-only gate: no strike-back dice.
#[test]
fn below_73_the_host_only_gate_stays() {
    let (_, shot) = host_wiped(EPOCH_72_PLAYTEST_RULES);
    assert_eq!(hero_rolls(&shot), 0, "no hero strike-back below the gate: {:?}", shot.rolls);
    assert!(shot.log.iter().all(|l| !l.starts_with("Hero:")), "{:?}", shot.log);
}

/// CONTROL: with the host alive the hero strikes back at both epochs, as before.
#[test]
fn a_living_host_leaves_the_hero_strike_back_unchanged() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        let (st, statics) = line(epoch, 2, 60);
        let (_, shot) = charge(&st, &statics, 7, epoch);
        assert!(hero_rolls(&shot) >= 1, "epoch {epoch}: {:?}", shot.rolls);
        assert!(shot.log.iter().all(|l| !l.starts_with("Hero:") || !l.contains("strike")), "epoch {epoch}: {:?}", shot.log);
    }
}
