//! MEL-09e: the AI's melee EV twin of MEL-09. From `EPOCH_73_V36` a fatigued striker's sixes still
//! hit but fire no rule, so `profile_ev` prices its whole on-6 AP sub-batch at zero (Rending's +4
//! included); epoch 72 keeps the bonus. The table twin is test/v36/mel_09e_test.gd.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

fn rending() -> ShootProfile {
    ShootProfile { rending: true, ..blade(12) }
}

/// The EV of a Quality 4 striker's 12-attack melee profile into a Defense 4 unit of 10.
fn ev(p: &ShootProfile, fatigued: bool, epoch: u32) -> f64 {
    let att = Ctx { quality: 4, fatigued, rules_epoch: epoch, ..Default::default() };
    crate::combat::profile_ev(p, 12, &att, &defender(4, 10), 0.0, false)
}

#[test]
fn fatigued_rending_ev_still_rends_at_epoch_72() {
    assert!(
        ev(&rending(), true, EPOCH_72_PLAYTEST_RULES) > ev(&blade(12), true, EPOCH_72_PLAYTEST_RULES),
        "72: a fatigued striker's sixes still save at AP(+4)"
    );
}

#[test]
fn fatigued_rending_ev_drops_the_on6_bonus_at_epoch_73() {
    let rending_ev = ev(&rending(), true, EPOCH_73_V36);
    let plain_ev = ev(&blade(12), true, EPOCH_73_V36);
    assert!(
        (rending_ev - plain_ev).abs() < 1e-12,
        "73: the muted sixes save at the plain Defense ({rending_ev} vs {plain_ev})"
    );
}

#[test]
fn a_fresh_rending_striker_still_rends_in_the_ev_at_epoch_73() {
    assert!(
        ev(&rending(), false, EPOCH_73_V36) > ev(&blade(12), false, EPOCH_73_V36),
        "a rested rending strike keeps the AP(+4) on its sixes"
    );
}

// --- MEL-09e-fix: every on-6 extra, live path --------------------------------
//
// The EV arms above build their own `Ctx`; these reach the same `profile_ev`
// through `melee_threat_at_epoch`, which builds the striker's profile with
// `UnitStatic::build_for` (the real registry stamp) and its fatigue from the
// live `State` via `ctx_of_melee`/`ctx_live`. Never a hand-set `Ctx` flag and
// never a hand-built `ShootProfile`.

use crate::acts::read_act_header;
use crate::rules::Registries;
use crate::sim::melee_threat_at_epoch;
use crate::state::{Profiles, Roster, State};
use crate::unit::UnitStatic;
use std::collections::HashMap;
use std::rc::Rc;

fn repo_root() -> String {
    format!("{}/../..", env!("CARGO_MANIFEST_DIR"))
}

/// A 12-attack melee striker through the REAL registry at `epoch`: `weapon_rules`
/// rides the weapon, `unit_rules` the unit's special-rule list.
fn striker(weapon_rules: &[&str], unit_rules: &[&str], epoch: u32) -> UnitStatic {
    let wr = weapon_rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let ur = unit_rules.iter().map(|r| format!("\"{r}\"")).collect::<Vec<_>>().join(",");
    let header = format!(
        r#"{{"kind":"header","knobs":{{}},"profiles":{{"s":{{"unit_id":"s","name":"Striker",
        "quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
        "base_radius":0.016,"game_system":"aof","faction_folder":"ogres",
        "special_rules":[{ur}],"item_grants":[],"attached_hero_rules":[],
        "move_bands":{{"advance":6.0,"rush":12.0}},
        "weapons":[{{"name":"Claw","range":0,"attacks":12,"count":1,"ap":0,"rules":[{wr}]}}]}}}}}}"#
    );
    let hdr = read_act_header(&header).expect("header parses");
    let mut reg = Registries::new(&repo_root());
    UnitStatic::build_for(&mut reg, hdr.profiles.get("s").expect("s"), epoch)
}

/// One striker in contact with a single Defense-4 target. `state.fatigued`
/// is the live state `ctx_of_melee` reads into the striker's `Ctx`.
fn line(
    weapon_rules: &[&str],
    unit_rules: &[&str],
    fatigued: bool,
    epoch: u32,
) -> (State, Vec<UnitStatic>) {
    let mut st = crate::sim::tests::four_unit_line();
    st.roster = Rc::new(Roster {
        keys: vec!["a".into(), "b".into()],
        index: HashMap::new(),
        profile: vec![0, 1],
    });
    st.profiles = Rc::new(Profiles::default());
    st.attached = Rc::new(vec![vec![], vec![], vec![], vec![]]);
    st.attached_to = Rc::new(vec![None; 4]);
    st.alive = vec![1, 1, 0, 0];
    st.shaken = vec![false; 4];
    st.fatigued = vec![fatigued, false, false, false];
    st.positions = vec![
        vec![[0.0, 0.0, 0.0]],
        vec![[crate::IN2M, 0.0, 0.0]],
        vec![],
        vec![],
    ];
    st.radii = Rc::new(vec![vec![crate::IN2M], vec![crate::IN2M], vec![], vec![]]);
    st.wounds = vec![vec![1], vec![1], vec![], vec![]];
    let mut target = UnitStatic { name: "Target".into(), model_count: 1, ..Default::default() };
    target.ctx = Ctx { quality: 4, defense: 4, tough: 1, models: 1, ..Default::default() };
    target.wounds_max = vec![1];
    (st, vec![striker(weapon_rules, unit_rules, epoch), target])
}

fn threat(weapon_rules: &[&str], unit_rules: &[&str], fatigued: bool, epoch: u32) -> f64 {
    let (st, statics) = line(weapon_rules, unit_rules, fatigued, epoch);
    melee_threat_at_epoch(&statics, &st, 0, 1, epoch)
}

#[test]
fn a_fatigued_surge_ev_drops_the_six_bonus_at_epoch_73() {
    let surge = threat(&["Surge"], &[], true, EPOCH_73_V36);
    let plain = threat(&[], &[], true, EPOCH_73_V36);
    assert!((surge - plain).abs() < 1e-12, "73: the muted sixes add no Surge hit ({surge} vs {plain})");
}

#[test]
fn a_fresh_surge_ev_keeps_the_six_bonus_at_epoch_73() {
    assert!(
        threat(&["Surge"], &[], false, EPOCH_73_V36) > threat(&[], &[], false, EPOCH_73_V36),
        "a rested Surge strike keeps the bonus hit"
    );
}

#[test]
fn a_fatigued_surge_ev_keeps_the_six_bonus_at_epoch_72() {
    assert!(
        threat(&["Surge"], &[], true, EPOCH_72_PLAYTEST_RULES)
            > threat(&[], &[], true, EPOCH_72_PLAYTEST_RULES),
        "72: a fatigued Surge strike still adds its six bonus"
    );
}

#[test]
fn a_fatigued_furious_ev_drops_the_six_bonus_at_epoch_73() {
    let furious = threat(&[], &["Furious"], true, EPOCH_73_V36);
    let plain = threat(&[], &[], true, EPOCH_73_V36);
    assert!((furious - plain).abs() < 1e-12, "73: the muted sixes add no Furious hit ({furious} vs {plain})");
}

#[test]
fn a_fresh_furious_ev_keeps_the_six_bonus_at_epoch_73() {
    assert!(
        threat(&[], &["Furious"], false, EPOCH_73_V36) > threat(&[], &[], false, EPOCH_73_V36),
        "a rested Furious charge keeps the bonus hit"
    );
}

#[test]
fn a_fatigued_furious_ev_keeps_the_six_bonus_at_epoch_72() {
    assert!(
        threat(&[], &["Furious"], true, EPOCH_72_PLAYTEST_RULES)
            > threat(&[], &[], true, EPOCH_72_PLAYTEST_RULES),
        "72: a fatigued Furious charge still adds its six bonus"
    );
}
