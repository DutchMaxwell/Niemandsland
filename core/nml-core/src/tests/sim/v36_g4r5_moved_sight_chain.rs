//! Rules 3.6 row G4R5 R2w F-MOVED-SIGHT-CHAIN (replay row gf_1000_net_012 act 10): a unit that ADVANCES with a
//! living but BLIND host and a joined hero that sees the target still fires the hero's weapon.
//!
//! The moved shooter's target gate (`unit_sees`) asked the HOST's key alone, so a host whose models all stand
//! behind a wood silenced the whole volley, hero included, while the table decides sight per member
//! (`_solo_sighted_count`). From `EPOCH_73_V36` the gate is "any alive chain member sees the target" (#2511 already
//! took the first living member when the host has no model at all); below 73 it stays host-only.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::read_act_header;

/// A real host (one model, no ranged weapon) and a real joined hero with a real ranged weapon (Carbine, 2 dice).
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "sisters":{"unit_id":"sisters","name":"Sisters","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"battle_sisters",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Mace","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "novice":{"unit_id":"novice","name":"Novice Leader","quality":3,
    "defense":4,"tough":3,"wounds_max":[3],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"battle_sisters",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Carbine","range":24,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// A 6x4 board (3" cells, school cell 15 = world cell 0) with FOREST in school column 18 (x 9..12") on the school
/// rows 11..=18 (z -12..12"): every sight line that crosses x 9..12" inside that band is blocked.
fn wood_board() -> crate::terrain::Terrain {
    use crate::terrain::{CellParams, PlainTerrain, FOREST};
    crate::terrain::Terrain::build(&PlainTerrain {
        cells: (11..=18).map(|r| [18.0, r as f64, FOREST as f64]).collect(),
        sandbox: vec![],
        pieces: vec![],
        containers: Vec::new(),
        walls: vec![],
        cell_params: CellParams { table_size_feet: [6.0, 4.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: IN2M },
    })
}

/// Unit 0 = the Sisters (host, one model at z = -9"), unit 1 = the Novice Leader (joined hero at `hero_z`), unit 2 =
/// a sturdy foe 18" east at z = +15", all 3" west of the wood's start. The host's line to the foe crosses the wood
/// band; a hero at z = +15" has an open line past it.
fn line(hero_z_in: f64) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
    st.positions = vec![
        vec![[-3.0 * IN2M, 0.0, -9.0 * IN2M]],
        vec![[-3.0 * IN2M, 0.0, hero_z_in * IN2M]],
        vec![[18.0 * IN2M, 0.0, 15.0 * IN2M]],
        vec![],
    ];
    st.radii = Rc::new(vec![vec![IN2M], vec![IN2M], vec![IN2M], vec![]]);
    st.wounds = vec![vec![1], vec![3], vec![10], vec![]];
    st.alive = vec![1, 1, 1, 0];
    st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, Some(0), None, None]);
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    let mut build = |key: &str| UnitStatic::build_for(&mut reg, header.profiles.get(key).expect(key), EPOCH_73_V36);
    let (sisters, novice) = (build("sisters"), build("novice"));
    let foe = UnitStatic { name: "Foe".into(), model_count: 1, wounds_max: vec![10], ..Default::default() };
    (st, vec![sisters, novice, foe, UnitStatic { name: "bh".into(), ..Default::default() }])
}

/// The host's 3" ADVANCE east (the group moves rigidly), firing at "b".
fn advance(hero_z_in: f64, epoch: u32) -> (State, ShootResult) {
    let (st, statics) = line(hero_z_in);
    let mut action = advance_shoot("b");
    action.dest = Some([0.0, 0.0, -9.0 * IN2M]);
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(7));
    let seams = Seams { rules_epoch: epoch, hero_attach: true, moved_shoot: true, ..Seams::default() };
    resolve_stochastic_tray_on_board(&statics, &st, &action, &wood_board(), seams, &mut rng, &mut tray).unwrap()
}

/// The Carbine volley: an `attack` roll signed by the Novice Leader.
fn hero_volley_dice(shot: &ShootResult) -> i64 {
    shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "Novice Leader").map(|r| r.count).sum()
}

/// The premise (passes with and without the change): after the Advance the wood leaves the host's model without a
/// sight line to the foe while the hero's model sees it.
#[test]
fn the_wood_blinds_the_host_and_not_the_hero_after_the_advance() {
    let (next, _) = advance(15.0, EPOCH_73_V36);
    let zones = crate::sight::zones_of(&wood_board());
    assert!((next.positions[0][0][0] / IN2M).abs() < 1e-6, "the host advanced to x = 0");
    assert!(!crate::sight::unit_sees(&next, &zones, 0, 2, EPOCH_73_V36), "the host is blind");
    assert!(crate::sight::unit_sees(&next, &zones, 1, 2, EPOCH_73_V36), "the hero sees");
}

/// The row (RED on main): the host is blind behind the wood, the hero sees, the hero's 2 Carbine dice fire.
#[test]
fn a_seeing_hero_fires_the_moved_volley_of_a_blind_host_from_73() {
    let (next, shot) = advance(15.0, EPOCH_73_V36);
    assert_eq!((next.alive[0], next.alive[1]), (1, 1), "host and hero both stand: {:?}", shot.log);
    assert_eq!(hero_volley_dice(&shot), 2, "the Novice Leader's Carbine fires (RED on main: 0): {:?} {:?}", shot.rolls, shot.log);
    assert!(
        shot.log.iter().any(|l| l.starts_with("Hero:") && l.contains("sees") && l.contains("fires the volley as the unit")),
        "the applied rule names itself: {:?}",
        shot.log
    );
}

/// CONTROL (passes with and without the change): a hero that is blind as well (inside the wood band) leaves the
/// moved volley without a target, so the widening opens no shot nobody sees.
#[test]
fn a_blind_hero_beside_a_blind_host_still_has_no_shot() {
    let (_, shot) = advance(-9.0, EPOCH_73_V36);
    assert_eq!(hero_volley_dice(&shot), 0, "{:?} {:?}", shot.rolls, shot.log);
}

/// Below 73 the gate stays the host's: the same blind host silences the volley, byte for byte.
#[test]
fn below_73_a_blind_host_still_silences_the_moved_volley() {
    let (_, shot) = advance(15.0, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(hero_volley_dice(&shot), 0, "{:?} {:?}", shot.rolls, shot.log);
}
