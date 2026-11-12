//! MEL-07f tests (`EPOCH_75_TABLE_FIXES`, port of table #2642): a Parry WEAPON brings X dice per
//! model that CARRIES it (the weapon's `count`, capped at the living models), not per living model
//! of the unit. The unit-rule form (every model has Parry) is unchanged; 74 and below replay the old
//! per-living-model draw.
use super::super::*;
use crate::acts::{EPOCH_74_CLIMB_COST, EPOCH_75_TABLE_FIXES};
use crate::rules::Registries;

/// A gf unit through the REAL stamp: `models` models carrying `rules` and the given weapon JSON.
fn unit(name: &str, models: i64, rules: &[&str], weapons: &str, epoch: u32) -> (UnitStatic, Profile) {
    let listed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let json = format!(
        r#"{{"unit_id":"u","name":"{name}","model_count":{models},"quality":4,"defense":4,"tough":1,"game_system":"gf","faction_folder":"","special_rules":[{listed}],"weapons":[{weapons}]}}"#
    );
    let p: Profile = serde_json::from_str(&json).expect("the profile parses");
    let mut reg = Registries::new(&repo_root());
    (UnitStatic::build_for(&mut reg, &p, epoch), p)
}

/// Unit 0 strikes the three-model defender (unit 1) with a 30-attack blade; returns the Parry roll's
/// dice count and the strike's hits.
fn parry_dice(epoch: u32, rules: &[&str], weapons: &str) -> (i64, i64) {
    let (attacker, att_p) = unit("Attacker", 1, &[], r#"{"name":"Blade","range":0,"attacks":30,"count":1,"ap":0,"rules":[]}"#, epoch);
    let (defender, def_p) = unit("Defender", 3, rules, weapons, epoch);
    let statics = vec![attacker, defender];
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into(), "c".into(), "d".into()], index: HashMap::new(), profile: vec![0, 1, 0, 0] });
    st.profiles = Rc::new(Profiles { list: vec![att_p, def_p], index: HashMap::new() });
    st.player = vec![0, 1, 0, 0];
    st.alive = vec![1, 3, 0, 0];
    st.attached = Rc::new(vec![vec![]; 4]);
    st.attached_to = Rc::new(vec![None; 4]);
    st.positions[1] = vec![[0.0, 0.0, 0.0]; 3];
    st.wounds[1] = vec![1; 3];
    Rc::make_mut(&mut st.radii)[1] = vec![IN2M; 3];
    let seams = Seams { rules_epoch: epoch, ..Default::default() };
    let mut shot = ShootResult::default();
    strike_phase(&statics, &mut st, 0, 1, false, 0.0, seams, &mut Tray::seeded(7), &mut shot, StrikeSet::All, Cover::Recorded(None));
    let hits: i64 = shot.rolls.iter().filter(|r| r.kind == "attack").map(|r| r.count).sum();
    assert!(hits >= 6, "the seeded strike lands enough hits that no cap hides the dice: {:?}", shot.rolls);
    (shot.rolls.iter().find(|r| r.kind == "parry").map_or(0, |r| r.count), hits)
}

const ONE_CARRIER: &str = r#"{"name":"Sword","range":0,"attacks":1,"count":1,"ap":0,"rules":["Parry(1)"]},{"name":"Hand","range":0,"attacks":1,"count":2,"ap":0,"rules":[]}"#;
const ALL_CARRY_TWO: &str = r#"{"name":"Sword","range":0,"attacks":1,"count":3,"ap":0,"rules":["Parry(2)"]}"#;

/// RED: a Parry(1) weapon carried by one of three models draws ONE die from 75 (the table's 3.6 read).
#[test]
fn a_parry_weapon_counts_only_its_carriers_from_epoch_75() {
    assert_eq!(parry_dice(EPOCH_75_TABLE_FIXES, &[], ONE_CARRIER).0, 1);
}

/// CONTROLS at 75: every model carries Parry(2) = 6 dice; the unit-rule form still counts every model.
#[test]
fn full_carriers_and_the_unit_rule_are_unchanged_at_epoch_75() {
    assert_eq!(parry_dice(EPOCH_75_TABLE_FIXES, &[], ALL_CARRY_TWO).0, 6);
    assert_eq!(parry_dice(EPOCH_75_TABLE_FIXES, &["Parry(1)"], "").0, 3);
}

/// A record stamped 74 replays the old per-living-model draw: three dice for the one carrier.
#[test]
fn epoch_74_still_counts_every_living_model() {
    assert_eq!(parry_dice(EPOCH_74_CLIMB_COST, &[], ONE_CARRIER).0, 3);
}
