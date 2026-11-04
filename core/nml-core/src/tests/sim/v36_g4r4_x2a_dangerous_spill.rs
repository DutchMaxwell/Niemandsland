//! Rules 3.6 row G4R4 R3-X2a (lead ruling 2; replay row gf_1000_net_002 act 11): a charging unit whose host
//! dies in its own Dangerous test while a joined hero lives is NOT destroyed. The test's surplus wounds go on
//! to the hero (heroes last, `land_pool_wounds`), and the charge goes on with the hero as the unit.
//!
//! The core landed the Dangerous test's wounds on the host's slots only and dropped the surplus, then stopped
//! the charge's own strikes because the host had no model left. From `EPOCH_73_V36` the surplus spills onto
//! the hero and the hero strikes. Below 73 the surplus is dropped and the host-only gates stay, byte for byte.
use super::*;
use crate::acts::EPOCH_73_V36;
use crate::read_act_header;

/// A real host (one model) and a real joined hero, both built from profiles the way the game builds a unit.
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
    "weapons":[{"name":"Greatsword","range":0,"attacks":3,"count":1,"ap":0,"rules":[]}]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Unit 0 = the Sisters (one model, one wound left) joined by unit 1 = the Novice Leader (three wounds), both
/// standing on the bar where `dangerous_bar_board` marks Dangerous cells (x = 4"); unit 2 = a sturdy foe 2.5" on.
fn line(epoch: u32) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
    st.positions = vec![vec![[4.0 * IN2M, 0.0, 0.0]], vec![[4.02 * IN2M, 0.0, 0.0]], vec![[6.5 * IN2M, 0.0, 0.0]], vec![]];
    st.radii = Rc::new(vec![vec![IN2M], vec![IN2M], vec![IN2M], vec![]]);
    st.wounds = vec![vec![1], vec![3], vec![10], vec![]];
    st.alive = vec![1, 1, 1, 0];
    st.attached = Rc::new(vec![vec![1], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, Some(0), None, None]);
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    let mut build = |key: &str| UnitStatic::build_for(&mut reg, header.profiles.get(key).expect(key), epoch);
    let (sisters, novice) = (build("sisters"), build("novice"));
    let foe = UnitStatic { name: "Foe".into(), model_count: 1, wounds_max: vec![10], ..Default::default() };
    (st, vec![sisters, novice, foe, UnitStatic { name: "bh".into(), ..Default::default() }])
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
    resolve_stochastic_tray_on_board(statics, st, &action, &dangerous_bar_board(), seams, &mut rng, &mut tray).unwrap()
}

/// The Dangerous test's own roll: an `attack` roll on the tray's success target 6, signed by the host.
fn test_wounds(shot: &ShootResult) -> i64 {
    shot.rolls.iter().find(|r| r.kind == "attack" && r.target == DANGEROUS_TARGET).map_or(0, |r| dangerous_wounds(&r.faces))
}

/// The first seed whose 4-dice test costs exactly 2 wounds: the host's one wound and one more.
fn two_wound_test(epoch: u32) -> (State, ShootResult) {
    let (st, statics) = line(epoch);
    (0..400)
        .map(|s| charge(&st, &statics, s, epoch))
        .find(|(_, shot)| test_wounds(shot) == 2)
        .expect("a seed where the Dangerous test costs exactly two wounds")
}

/// The row: the host dies, the surplus wound lands on the Novice Leader, and the Novice Leader strikes.
#[test]
fn the_dangerous_surplus_reaches_the_hero_and_the_hero_charges_on_from_73() {
    let (next, shot) = two_wound_test(EPOCH_73_V36);
    assert_eq!((next.alive[0], next.wounds[1].clone()), (0, vec![2]), "host dead, hero down one wound: {:?}", shot.log);
    assert!(
        shot.log.iter().any(|l| l.starts_with("Hero:") && l.contains("beyond the unit's models")),
        "the applied rule names itself: {:?}",
        shot.log
    );
    let strikes = shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "Novice Leader").count();
    assert!(strikes >= 1, "the Novice Leader strikes for the unit: {:?}", shot.rolls);
}

/// CONTROL: a one-wound test costs the host its last wound and nothing spills - the host dies, the hero keeps
/// all three wounds at 73 too.
#[test]
fn a_one_wound_test_spills_nothing() {
    let (st, statics) = line(EPOCH_73_V36);
    let (next, _) = (0..400)
        .map(|s| charge(&st, &statics, s, EPOCH_73_V36))
        .find(|(_, shot)| test_wounds(shot) == 1)
        .expect("a seed where the Dangerous test costs exactly one wound");
    assert_eq!((next.alive[0], next.wounds[1].clone()), (0, vec![3]));
}
