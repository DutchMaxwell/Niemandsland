//! G4R4 row C-BANNER-DEAD-HOST: the Banner's +1 belongs to the models that carry it. The table reads the unit's
//! Banner by LIVING member (`morale_bonus_named_of` skips a member with no models), so once the host that carried
//! it died in the volley, the joined hero that lives tests morale without it. The core kept the bonus recorded at
//! the act's start. From `EPOCH_73_V36` the test recomputes the Banner share from the chain's living members
//! (rules-must-log: "Banner"). Replay rows: aof_1000_net_028 act 20 (table 3+, core 2+), aof_1000_net_038 act 23.
use super::*;
use crate::acts::EPOCH_73_V36;
use crate::read_act_header;

/// One real header: the Quality 2+ shooter, and the host/hero profiles with the Banner on one of them (a host
/// whose joined hero carries it stamps it through `attached_hero_rules`, as the game's capture does).
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "gunner":{"unit_id":"gunner","name":"Gunner","quality":2,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":5,"count":1,"ap":0,"rules":[]}]},
  "host_banner":{"unit_id":"host_banner","name":"host_banner","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers",
    "special_rules":["Banner"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[]},
  "host_plain":{"unit_id":"host_plain","name":"host_plain","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[["Banner"]],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[]},
  "hero_banner":{"unit_id":"hero_banner","name":"hero_banner","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers",
    "special_rules":["Banner"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[]},
  "hero_plain":{"unit_id":"hero_plain","name":"hero_plain","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"battle_brothers",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Attacker "a" against the host "b" (one model) with the joined hero "bh" (one model). The Banner sits on the host,
/// or on the hero when `hero_carries`. Both units' recorded `morale_bonus` is what the game's own capture stamps.
fn line(epoch: u32, hero_carries: bool) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    let at = |x: f64| [x * IN2M, 0.0, 0.0];
    st.positions = vec![vec![at(0.0)], vec![], vec![at(5.0)], vec![at(5.5)]];
    st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M], vec![IN2M]]);
    st.wounds = vec![vec![1], vec![], vec![1], vec![1]];
    st.alive = vec![1, 0, 1, 1];
    st.attached = Rc::new(vec![vec![], vec![], vec![3], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None, Some(2)]);
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    let gunner = UnitStatic::build_for(&mut reg, header.profiles.get("gunner").expect("gunner"), epoch);
    let (host_id, hero_id) = if hero_carries { ("host_plain", "hero_banner") } else { ("host_banner", "hero_plain") };
    for (i, id) in [(2, host_id), (3, hero_id)] {
        st.morale_bonus[i] = crate::capture_reads_for_epoch(&mut reg, header.profiles.get(id).expect(id), epoch).morale_bonus;
    }
    let body = |name: &str| {
        let mut u = UnitStatic { name: name.into(), model_count: 1, wounds_max: vec![1], quality: 4, ..Default::default() };
        u.ctx.defense = 4;
        u.ctx.tough = 1;
        u
    };
    (st, vec![gunner, UnitStatic { name: "ah".into(), ..Default::default() }, body("b"), body("bh")])
}

/// One HOLD+shoot activation at the host on the tray path.
fn shoot(st: &State, statics: &[UnitStatic], seed: i64, epoch: u32) -> (State, ShootResult) {
    let action = Action {
        kind: HOLD,
        unit: "a".into(),
        dest: None,
        shoot: Some("b".into()),
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

/// The first seed whose volley kills the host and leaves the hero: half of the chain is gone, so the shooting
/// morale test is due.
fn seed_where_host_dies(st: &State, statics: &[UnitStatic], epoch: u32) -> i64 {
    (0..600)
        .find(|&s| {
            let after = shoot(st, statics, s, epoch).0;
            after.alive[2] == 0 && after.alive[3] == 1
        })
        .expect("a seed that kills the host and spares the hero")
}

/// The target of the chain's morale die (the roll is signed by the target unit), if one was rolled.
fn morale_target_rolled(shot: &ShootResult) -> Option<i64> {
    shot.rolls.iter().find(|r| r.owner == "b" && r.kind == "attack" && r.count == 1).map(|r| r.target)
}

fn banner_lines(shot: &ShootResult) -> Vec<&String> {
    shot.log.iter().filter(|l| l.starts_with("Banner:")).collect()
}

/// The row: the host (the Banner carrier) died in the volley, so the hero's test is Quality 4+ without the +1,
/// and the log names the Banner. RED on main: the recorded +1 stays and the die is rolled at 3+.
#[test]
fn the_banner_of_a_host_that_died_in_the_volley_no_longer_counts_at_73() {
    let (st, statics) = line(EPOCH_73_V36, false);
    assert_eq!(st.morale_bonus[2], 1, "fixture: the game's capture stamps the carrier's Banner");
    let seed = seed_where_host_dies(&st, &statics, EPOCH_73_V36);
    let (_, shot) = shoot(&st, &statics, seed, EPOCH_73_V36);
    assert_eq!(morale_target_rolled(&shot), Some(4), "no Banner: Quality 4+ alone: {:?}", shot.rolls);
    assert_eq!(banner_lines(&shot).len(), 1, "the applied rule names itself: {:?}", shot.log);
}

/// CONTROL: the hero carries the Banner and lives, so the unit keeps it (3+) and nothing is logged.
#[test]
fn a_living_hero_keeps_the_banner_it_carries_at_73() {
    let (st, statics) = line(EPOCH_73_V36, true);
    assert_eq!((st.morale_bonus[2], st.morale_bonus[3]), (1, 1), "fixture: host stamps the hero's Banner too");
    let seed = seed_where_host_dies(&st, &statics, EPOCH_73_V36);
    let (_, shot) = shoot(&st, &statics, seed, EPOCH_73_V36);
    assert_eq!(morale_target_rolled(&shot), Some(3), "the hero's Banner counts: {:?}", shot.rolls);
    assert!(banner_lines(&shot).is_empty(), "{:?}", shot.log);
}

/// CONTROL: below 73 the recorded bonus stands, byte for byte (3+ and no Banner line).
#[test]
fn below_73_the_recorded_bonus_stands() {
    let epoch = EPOCH_73_V36 - 1;
    let (st, statics) = line(epoch, false);
    let seed = seed_where_host_dies(&st, &statics, epoch);
    let (_, shot) = shoot(&st, &statics, seed, epoch);
    assert!(banner_lines(&shot).is_empty(), "{:?}", shot.log);
    assert!(morale_target_rolled(&shot).is_none_or(|t| t == 3), "{:?}", shot.rolls);
}
