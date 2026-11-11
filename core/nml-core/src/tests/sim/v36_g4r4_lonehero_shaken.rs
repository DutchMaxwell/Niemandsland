//! G4R4 row C-LONEHERO-SHAKEN: a lone joined hero IS its dead host's unit, so the Shaken the host carried is the
//! unit's own. The table reads the flag on the unit object (log: "is already Shaken - automatically fails
//! morale", no die); the core kept one flag per member and rolled a morale die for the hero, one roll more.
//! From `EPOCH_73_V36` the shooting-morale test reads the chain's flag (the host's or the hero's). Replay rows:
//! aof_1000_net_012 act 22, gf_1000_net_033 act 24, gf_1000_net_029 act 25. Below 73 nothing moves.
use super::*;
use crate::acts::EPOCH_73_V36;
use crate::read_act_header;

/// A real Quality 2+ shooter with one five-attack rifle, built the way the game builds a unit.
const GUNNER_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "gunner":{"unit_id":"gunner","name":"Gunner","quality":2,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":5,"count":1,"ap":0,"rules":[]}]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Attacker "a" against the unit "b" (host, two models) with the joined hero "bh" (three models, 5" away). The host
/// is dead and carries `host_shaken`.
fn line(epoch: u32, host_shaken: bool) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    let at = |x: f64| [x * IN2M, 0.0, 0.0];
    st.positions = vec![vec![at(0.0)], vec![], vec![], vec![at(5.0), at(5.5), at(6.0)]];
    st.radii = Rc::new(vec![vec![IN2M], vec![], vec![], vec![IN2M; 3]]);
    st.wounds = vec![vec![1], vec![], vec![], vec![1; 3]];
    st.alive = vec![1, 0, 0, 3];
    st.shaken[2] = host_shaken;
    st.attached = Rc::new(vec![vec![], vec![], vec![3], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None, Some(2)]);
    let header = read_act_header(GUNNER_HEADER).expect("GUNNER_HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    let gunner = UnitStatic::build_for(&mut reg, header.profiles.get("gunner").expect("gunner"), epoch);
    let body = |name: &str, models: i64| {
        let mut u = UnitStatic { name: name.into(), model_count: models, wounds_max: vec![1; models as usize], quality: 4, ..Default::default() };
        u.ctx.defense = 4;
        u.ctx.tough = 1;
        u
    };
    (st, vec![gunner, UnitStatic { name: "ah".into(), ..Default::default() }, body("b", 2), body("bh", 3)])
}

/// One HOLD+shoot activation at the lone hero (the aim the gate maps a dead host to), on the tray path.
fn shoot(st: &State, statics: &[UnitStatic], seed: i64, epoch: u32) -> (State, ShootResult) {
    let action = Action {
        kind: HOLD,
        unit: "a".into(),
        dest: None,
        shoot: Some("bh".into()),
        charge: None,
        patient: false,
        split: None,
        traced: None,
        teleport: None,
    };
    let terrain = Terrain::default();
    let mut tray = Tray::seeded(seed);
    let mut rng = GodotRng::new(0);
    let seams = Seams { rules_epoch: epoch, hero_attach: true, hero_counts_in_size: true, ..Seams::default() };
    resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray).unwrap()
}

/// The first seed whose volley leaves the hero unit one or two models of three: a lost model at or below half of
/// the chain's five, so the shooting-morale test is due.
fn due_seed(st: &State, statics: &[UnitStatic], epoch: u32) -> i64 {
    (0..400)
        .find(|&s| (1..=2).contains(&shoot(st, statics, s, epoch).0.alive[3]))
        .expect("a seed that wounds the hero unit into a morale test")
}

fn morale_dice(shot: &ShootResult) -> usize {
    shot.rolls.iter().filter(|r| r.owner == "bh" && r.kind == "attack" && r.count == 1).count()
}

/// The row: the host died Shaken, the lone hero's test is the unit's — no die, Shaken again, and the applied
/// rule names itself. RED on main: the hero's own flag is false, so a morale die is rolled.
#[test]
fn a_lone_hero_inherits_its_dead_hosts_shaken_at_73() {
    let (st, statics) = line(EPOCH_73_V36, true);
    let seed = due_seed(&st, &statics, EPOCH_73_V36);
    let (after, shot) = shoot(&st, &statics, seed, EPOCH_73_V36);
    assert_eq!(morale_dice(&shot), 0, "a Shaken unit fails the test without a die: {:?}", shot.rolls);
    assert!(after.shaken[3], "the hero unit is Shaken after the failed test");
    assert!(
        shot.log.iter().any(|l| l.starts_with("Shaken:") && l.contains("bh") && l.contains("b")),
        "the applied rule names itself: {:?}",
        shot.log
    );
}

/// CONTROL: the host died but was not Shaken, so the hero's test rolls its die.
#[test]
fn a_lone_hero_of_an_unshaken_host_rolls_its_die() {
    let (st, statics) = line(EPOCH_73_V36, false);
    let seed = due_seed(&st, &statics, EPOCH_73_V36);
    let (_, shot) = shoot(&st, &statics, seed, EPOCH_73_V36);
    assert_eq!(morale_dice(&shot), 1, "{:?}", shot.rolls);
}

/// CONTROL: below 73 the host's flag changes nothing — the same dice, the same Shaken flags, byte for byte.
#[test]
fn below_73_the_hosts_flag_changes_nothing() {
    let epoch = EPOCH_73_V36 - 1;
    let (st, statics) = line(epoch, true);
    let (plain, _) = line(epoch, false);
    let seed = due_seed(&st, &statics, epoch);
    let (after, shot) = shoot(&st, &statics, seed, epoch);
    let (after_plain, shot_plain) = shoot(&plain, &statics, seed, epoch);
    assert_eq!(shot.rolls, shot_plain.rolls);
    assert_eq!(after.shaken[3], after_plain.shaken[3]);
}
