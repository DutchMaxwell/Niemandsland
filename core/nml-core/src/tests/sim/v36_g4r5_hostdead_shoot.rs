//! Rules 3.6 row G4R5 R2 F-HOSTDEAD-SHOOT (replay row gf_1000_net_029 act 24): a unit whose host dies in its own
//! Dangerous test on an ADVANCE while a joined hero lives goes on - and the hero fires the moved volley.
//!
//! The moved shooter's target gate (`unit_sees`) and the pooled range probe both started from the HOST's key and
//! found no models, so the volley was refused although the same hero fires the same shot on a Hold. From
//! `EPOCH_73_V36` the probes start from the first living chain member; below 73 they stay host-only.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::read_act_header;

/// A real host (one model, one wound) and a real joined hero with a real ranged weapon (Carbine, 2 dice).
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

/// Unit 0 = the Sisters (one model, one wound) joined by unit 1 = the Novice Leader (Carbine, three wounds);
/// both start 2.5" west of the Dangerous bar and advance onto it; unit 2 = a sturdy foe 12" east.
fn line(epoch: u32) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    st.profiles = Rc::new(Profiles { list: vec![st.profiles.list[0].clone(); 4], index: HashMap::new() });
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![[0.02 * IN2M, 0.0, 0.0]], vec![[12.0 * IN2M, 0.0, 0.0]], vec![]];
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

/// The host's ADVANCE onto the Dangerous bar, firing at "b".
fn advance(st: &State, statics: &[UnitStatic], seed: i64, epoch: u32) -> (State, ShootResult) {
    let mut action = advance_shoot("b");
    action.dest = Some([4.0 * IN2M, 0.0, 0.0]);
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(seed));
    let seams = Seams { rules_epoch: epoch, hero_attach: true, moved_shoot: true, ..Seams::default() };
    resolve_stochastic_tray_on_board(statics, st, &action, &dangerous_bar_board(), seams, &mut rng, &mut tray).unwrap()
}

/// The Dangerous test's own roll: an `attack` roll on the tray's success target 6, signed by the host.
fn test_wounds(shot: &ShootResult) -> i64 {
    shot.rolls.iter().find(|r| r.kind == "attack" && r.target == DANGEROUS_TARGET).map_or(0, |r| dangerous_wounds(&r.faces))
}

/// The first seed whose test costs the host its one wound and leaves the hero standing (1 or 2 wounds in all).
fn host_dies(epoch: u32) -> (State, ShootResult) {
    let (st, statics) = line(epoch);
    (0..400)
        .map(|s| advance(&st, &statics, s, epoch))
        .find(|(_, shot)| (1..=2).contains(&test_wounds(shot)))
        .expect("a seed where the host dies in its own Dangerous test and the hero lives")
}

/// The Carbine volley: an `attack` roll signed by the Novice Leader that is not the Dangerous test.
fn hero_volley_dice(shot: &ShootResult) -> i64 {
    shot.rolls.iter().filter(|r| r.kind == "attack" && r.owner == "Novice Leader" && r.target != DANGEROUS_TARGET).map(|r| r.count).sum()
}

/// The row (RED on main): the host dies in its own test, the hero fires its 2 Carbine dice after the Advance.
#[test]
fn the_hero_fires_the_moved_volley_when_the_host_died_in_its_dangerous_test_from_73() {
    let (next, shot) = host_dies(EPOCH_73_V36);
    assert_eq!(next.alive[0], 0, "the host's one model is dead: {:?}", shot.log);
    assert_eq!(hero_volley_dice(&shot), 2, "the Novice Leader's Carbine fires: {:?} {:?}", shot.rolls, shot.log);
}

/// CONTROL (passes with and without the change): the same hero fires the same Carbine on a Hold.
#[test]
fn the_same_hero_fires_on_a_hold_with_a_dead_host() {
    let (mut st, statics) = line(EPOCH_73_V36);
    (st.alive[0], st.wounds[0], st.positions[0]) = (0, vec![], vec![]);
    let mut action = advance_shoot("b");
    action.kind = HOLD;
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(7));
    let seams = Seams { rules_epoch: EPOCH_73_V36, hero_attach: true, moved_shoot: true, ..Seams::default() };
    let (_, shot) = resolve_stochastic_tray_on_board(&statics, &st, &action, &dangerous_bar_board(), seams, &mut rng, &mut tray).unwrap();
    assert_eq!(hero_volley_dice(&shot), 2, "{:?}", shot.rolls);
}

/// Below 73 the probes stay host-only: the same dead host leaves the moved volley unfired, byte for byte.
#[test]
fn below_73_the_dead_hosts_moved_volley_stays_unfired() {
    let (_, shot) = host_dies(EPOCH_72_PLAYTEST_RULES);
    assert_eq!(hero_volley_dice(&shot), 0, "{:?}", shot.rolls);
}
