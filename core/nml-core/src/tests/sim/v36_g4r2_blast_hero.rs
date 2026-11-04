//! Rules 3.6 row G4R2 F-BLAST: Blast(X) caps its multiplier by the host PLUS its living joined heroes.
//!
//! The table caps by `_solo_combined_alive(target)` (a joined hero is a model of the unit) and logs
//! "capped by N models in target". The core capped by the host's own alive count (`Ctx::models`).
//! From `EPOCH_73_V36` the shot's defender context carries the combined count for Blast alone;
//! `models` itself stays the host's count for every other reader. Below 73 nothing moves.
//! Replay rows: aof_1000_net_018 act 21 (Blast(6), host 5 + hero 1) and gf_1000_net_017 act 28.
use super::*;
use crate::acts::EPOCH_73_V36;
use crate::read_act_header;

/// A real "Blast(3)" weapon on a Quality 2+ gunner, built the way the game builds a unit.
const BLAST_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "gunner":{"unit_id":"gunner","name":"Gunner","quality":2,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Giant Sling","range":24,"attacks":1,"count":1,"ap":0,"rules":["Blast(3)"]}]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Attacker "a" (the Blast(3) gunner) vs host "b" (one model) with a joined hero "bh" (one model when
/// `hero_alive`), five inches apart on the plain line.
fn blast_line(epoch: u32, hero_alive: bool) -> (State, Vec<UnitStatic>) {
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
        vec![[5.0 * IN2M, 0.0, 0.0]],
        if hero_alive { vec![[5.02 * IN2M, 0.0, 0.0]] } else { vec![] },
    ];
    st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M], if hero_alive { vec![IN2M] } else { vec![] }]);
    st.wounds = vec![vec![1], vec![], vec![1], if hero_alive { vec![1] } else { vec![] }];
    st.alive = vec![1, 0, 1, hero_alive as i64];
    st.attached = Rc::new(vec![vec![], vec![], vec![3], vec![]]);
    st.attached_to = Rc::new(vec![None, None, None, Some(2)]);
    let header = read_act_header(BLAST_HEADER).expect("BLAST_HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    let gunner = UnitStatic::build_for(&mut reg, header.profiles.get("gunner").expect("gunner"), epoch);
    let body = |name: &str| {
        let mut u = UnitStatic { name: name.into(), model_count: 1, wounds_max: vec![1], ..Default::default() };
        u.ctx.defense = 4;
        u.ctx.tough = 1;
        u
    };
    (st, vec![gunner, UnitStatic { name: "ah".into(), ..Default::default() }, body("b"), body("bh")])
}

/// One HOLD+shoot activation at the host on the tray path, hero joined as the game joins it.
fn shoot(st: &State, statics: &[UnitStatic], seed: i64, epoch: u32) -> ShootResult {
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
    let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Seams::default() };
    resolve_stochastic_tray_on_board(statics, st, &action, &terrain, seams, &mut rng, &mut tray).unwrap().1
}

/// A seed whose first attack die hits at Quality 2+ (any face but a 1), so exactly one hit lands.
fn hitting_seed() -> i64 {
    (0..64).find(|&s| Tray::seeded(s).roll(1)[0] >= 2).expect("a seed with a hit")
}

fn save_dice(shot: &ShootResult) -> i64 {
    let saves: Vec<_> = shot.rolls.iter().filter(|r| r.kind == "defense").collect();
    assert_eq!(saves.len(), 1, "fixture: one save batch: {:?}", shot.rolls);
    saves[0].count
}

/// The row: one hit with Blast(3) at host 1 + hero 1 -> 2 hits, so two save dice, and the shot names Blast.
#[test]
fn a_blast_hit_counts_the_joined_hero_from_73() {
    let (st, statics) = blast_line(EPOCH_73_V36, true);
    let shot = shoot(&st, &statics, hitting_seed(), EPOCH_73_V36);
    assert_eq!(save_dice(&shot), 2, "1 hit x min(3, host 1 + hero 1): {:?}", shot.rolls);
    assert!(
        shot.log.iter().any(|l| l.contains("Blast(3): 1 hit ×2") && l.contains("capped by 2 models")),
        "the applied rule names itself: {:?}",
        shot.log
    );
}

/// Below 73 the recorded corpora keep the host-only cap, byte for byte.
#[test]
fn below_73_a_blast_hit_keeps_the_host_only_cap() {
    let (st, statics) = blast_line(EPOCH_73_V36 - 1, true);
    let shot = shoot(&st, &statics, hitting_seed(), EPOCH_73_V36 - 1);
    assert_eq!(save_dice(&shot), 1, "below 73: 1 hit x host 1: {:?}", shot.rolls);
}

/// CONTROL: a dead hero is no model of the unit, so the cap is the host alone at 73 too.
#[test]
fn a_dead_hero_does_not_raise_the_blast_cap() {
    let (st, statics) = blast_line(EPOCH_73_V36, false);
    let shot = shoot(&st, &statics, hitting_seed(), EPOCH_73_V36);
    assert_eq!(save_dice(&shot), 1, "dead hero: 1 hit x host 1: {:?}", shot.rolls);
}
