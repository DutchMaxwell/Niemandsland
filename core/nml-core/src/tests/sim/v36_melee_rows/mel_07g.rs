//! MEL-07g tests (`EPOCH_75_TABLE_FIXES`, core twin of the table's `AiEv._parry_carrier_dice`): the AI's melee
//! estimate counts the Parry dice the dice path rolls (`parry_dice_total`, MEL-07f): a Parry WEAPON brings X per
//! model that carries it, capped at the living models, not X per living model. 74 and below keep the old estimate.
use super::super::*;
use crate::acts::{EPOCH_74_CLIMB_COST, EPOCH_75_TABLE_FIXES};
use crate::combat::melee_ev;
use crate::rules::Registries;

/// A five-model gf defender through the REAL stamp, as unit 1 of a four-unit line with `alive` living models.
fn defender(rules: &[&str], weapons: &str, epoch: u32, alive: i64) -> (Vec<UnitStatic>, State) {
    let listed = rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let json = format!(
        r#"{{"unit_id":"u","name":"Defender","model_count":5,"quality":4,"defense":4,"tough":1,"game_system":"gf","faction_folder":"","special_rules":[{listed}],"weapons":[{weapons}]}}"#
    );
    let p: Profile = serde_json::from_str(&json).expect("the profile parses");
    let mut reg = Registries::new(&repo_root());
    let statics = vec![UnitStatic::build_for(&mut reg, &p, epoch)];
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into(), "c".into(), "d".into()], index: HashMap::new(), profile: vec![0; 4] });
    st.profiles = Rc::new(Profiles { list: vec![p], index: HashMap::new() });
    st.alive = vec![0, alive, 0, 0];
    st.attached = Rc::new(vec![vec![]; 4]);
    st.attached_to = Rc::new(vec![None; 4]);
    (statics, st)
}

/// The estimate's Parry dice off the live `ctx_of`: a 10-attack 4+ strike lands 5 expected hits and the Defense 4+
/// save halves what the dice leave, so the melee EV is (5 - dice/6) / 2 for up to five dice.
fn estimate_dice(statics: &[UnitStatic], st: &State) -> i64 {
    let att = Ctx { quality: 4, models: 1, ..Default::default() };
    let blade = ShootProfile { name: "Blade".into(), range: 0, attacks: 10, ..Default::default() };
    let ev = melee_ev(&[blade], &[10], &att, &ctx_of(&statics[0], st, 1), false, 0.0);
    ((5.0 - 2.0 * ev) * 6.0).round() as i64
}

const ONE: &str = r#"{"name":"Sword","range":0,"attacks":1,"count":1,"ap":0,"rules":["Parry(1)"]},{"name":"Hand","range":0,"attacks":1,"count":4,"ap":0,"rules":[]}"#;
const TWO: &str = r#"{"name":"Sword","range":0,"attacks":1,"count":2,"ap":0,"rules":["Parry(2)"]},{"name":"Hand","range":0,"attacks":1,"count":3,"ap":0,"rules":[]}"#;
const ALL: &str = r#"{"name":"Sword","range":0,"attacks":1,"count":5,"ap":0,"rules":["Parry(1)"]}"#;
const HAND: &str = r#"{"name":"Hand","range":0,"attacks":1,"count":5,"ap":0,"rules":[]}"#;

/// RED: one Parry(1) carrier in five models is priced as ONE die from 75, and every case matches the dice path's
/// count (`parry_dice_total`) at full strength and after losses; the unit-rule form is the control.
#[test]
fn the_estimate_counts_only_the_carriers_from_epoch_75() {
    let (statics, st) = defender(&[], ONE, EPOCH_75_TABLE_FIXES, 5);
    assert_eq!(estimate_dice(&statics, &st), 1, "1 of 5 carries Parry(1)");
    for (rules, weapons) in [(&[][..], ONE), (&[][..], TWO), (&[][..], ALL), (&["Parry(1)"][..], HAND)] {
        for alive in [5, 2, 1] {
            let (statics, st) = defender(rules, weapons, EPOCH_75_TABLE_FIXES, alive);
            assert_eq!(estimate_dice(&statics, &st), parry_dice_total(&statics, &st, 1), "{weapons} {rules:?} with {alive} alive");
        }
    }
}

/// A record stamped 74 keeps the old estimate: X per LIVING model (5, then 2), byte-exact EV 25/12 at full strength.
#[test]
fn the_estimate_is_unchanged_at_epoch_74() {
    let (statics, st) = defender(&[], ONE, EPOCH_74_CLIMB_COST, 5);
    assert_eq!(statics[0].ctx.parry_carrier_dice, 0, "the carrier stamp is off below 75");
    assert_eq!(estimate_dice(&statics, &st), 5);
    let att = Ctx { quality: 4, models: 1, ..Default::default() };
    let blade = ShootProfile { name: "Blade".into(), range: 0, attacks: 10, ..Default::default() };
    let ev = melee_ev(&[blade], &[10], &att, &ctx_of(&statics[0], &st, 1), false, 0.0);
    assert_eq!(ev.to_bits(), (25.0f64 / 12.0).to_bits(), "epoch 74 EV: {ev}");
    let (statics, st) = defender(&[], ONE, EPOCH_74_CLIMB_COST, 2);
    assert_eq!(estimate_dice(&statics, &st), 2);
}
