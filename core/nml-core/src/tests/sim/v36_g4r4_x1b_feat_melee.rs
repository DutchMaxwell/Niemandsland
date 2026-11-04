//! Rules 3.6 row G4R4 R3-X1b (lead ruling 1; replay row aof_1000_net_012 act 38): Precision Feat is ONE latch per
//! game shared by shooting AND melee. The bearer's first attack of any kind - a strike-back included - gets +1 to
//! hit on every strike of that phase, then the latch is spent and recorded in `feats_used`.
//!
//! The core read the Feat on the volley seam only, so a Feat bearer's strike-back hit on its plain Quality and
//! the latch never closed in melee. From `EPOCH_73_V36` the melee strike phase applies and spends it like the
//! volley does. Below 73 the melee never sees the Feat, byte for byte.
use super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::read_act_header;

/// A real Feat bearer (ghostly_undead, `special_rules: ["Precision Feat"]`) and a real plain charger, both
/// built from profiles the way the game builds a unit. The Horde hits on 5+ without the Feat, 4+ with it.
const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "charger":{"unit_id":"charger","name":"Charger","quality":4,
    "defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"halflings",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Cleaver","range":0,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "horde":{"unit_id":"horde","name":"Ghost Horde","quality":5,
    "defense":4,"tough":10,"wounds_max":[10],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"aof","faction_folder":"ghostly_undead",
    "special_rules":["Precision Feat"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Claws","range":0,"attacks":2,"count":1,"ap":0,"rules":[]}]}}}"#;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// Unit 0 = the plain Charger, unit 2 = the Feat-bearing Ghost Horde two inches away.
fn line(epoch: u32) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    let r = &*st.roster;
    st.roster = Rc::new(crate::state::Roster {
        keys: r.keys.clone(),
        index: r.keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect(),
        profile: vec![0, 1, 2, 3],
    });
    st.positions = vec![vec![[0.0, 0.0, 0.0]], vec![], vec![[2.5 * IN2M, 0.0, 0.0]], vec![]];
    st.radii = Rc::new(vec![vec![IN2M], vec![], vec![IN2M], vec![]]);
    st.wounds = vec![vec![1], vec![], vec![10], vec![]];
    st.alive = vec![1, 0, 1, 0];
    st.attached = Rc::new(vec![vec![]; 4]);
    st.attached_to = Rc::new(vec![None; 4]);
    let header = read_act_header(HEADER).expect("HEADER parses");
    let mut reg = crate::rules::Registries::new(&repo_root());
    let mut build = |key: &str| UnitStatic::build_for(&mut reg, header.profiles.get(key).expect(key), epoch);
    let (charger, horde) = (build("charger"), build("horde"));
    (st, vec![charger, UnitStatic { name: "ah".into(), ..Default::default() }, horde, UnitStatic { name: "bh".into(), ..Default::default() }])
}

fn charge(st: &State, statics: &[UnitStatic], epoch: u32) -> (State, ShootResult) {
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
    let (mut rng, mut tray) = (GodotRng::new(0), Tray::seeded(5));
    let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Seams::default() };
    resolve_stochastic_tray_on_board(statics, st, &action, &Terrain::default(), seams, &mut rng, &mut tray).unwrap()
}

/// The Horde's strike-back roll: the `attack` roll signed by it that carries its two Claws dice.
fn horde_target(shot: &ShootResult) -> Option<i64> {
    shot.rolls.iter().find(|r| r.kind == "attack" && r.owner == "Ghost Horde" && r.count == 2).map(|r| r.target)
}

/// The row: the strike-back hits on 4+ (Quality 5 and the Feat), the Feat is spent and recorded, the log names it.
#[test]
fn a_strike_back_spends_the_precision_feat_from_73() {
    let (st, statics) = line(EPOCH_73_V36);
    let (next, shot) = charge(&st, &statics, EPOCH_73_V36);
    assert_eq!(horde_target(&shot), Some(4), "Quality 5 plus the Feat's +1: {:?}", shot.rolls);
    assert!(next.feats_used[2].iter().any(|n| n == "Precision Feat"), "the latch is spent: {:?}", next.feats_used);
    assert!(shot.log.iter().any(|l| l.contains("Precision Feat")), "the applied rule names itself: {:?}", shot.log);
}

/// ONE latch: a second melee of the same bearer hits on plain Quality again.
#[test]
fn the_latch_is_spent_after_the_first_attack() {
    let (st, statics) = line(EPOCH_73_V36);
    let (after, _) = charge(&st, &statics, EPOCH_73_V36);
    let mut again = after.clone();
    (again.fatigued[0], again.fatigued[2]) = (false, false);
    again.wounds[2] = vec![10];
    again.alive[2] = 1;
    again.positions[0] = vec![[0.0, 0.0, 0.0]];
    again.positions[2] = vec![[2.5 * IN2M, 0.0, 0.0]];
    again.wounds[0] = vec![1];
    again.alive[0] = 1;
    let (_, shot) = charge(&again, &statics, EPOCH_73_V36);
    assert_eq!(horde_target(&shot), Some(5), "the spent Feat gives nothing the second time: {:?}", shot.rolls);
}

/// Below 73 the melee never saw the Feat: plain Quality, no spend.
#[test]
fn below_73_the_melee_ignores_the_precision_feat() {
    let (st, statics) = line(EPOCH_72_PLAYTEST_RULES);
    let (next, shot) = charge(&st, &statics, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(horde_target(&shot), Some(5), "{:?}", shot.rolls);
    assert!(next.feats_used[2].is_empty(), "{:?}", next.feats_used);
}
