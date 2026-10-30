//! MEL-IPS tests (rules 3.6, lane melee): a carrier of Infiltrating Precision Strike (gf elven_jesters) arrives
//! as an infiltrator and its melee strikes hit one better in its arrival round; nothing before EPOCH_73_V36.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

const IPS: &str = "Infiltrating Precision Strike";

/// A one-model gf elven_jesters unit built through the REAL registry at `epoch`, Quality 4, one big blade.
fn carrier(rules: &[&str], epoch: u32) -> UnitStatic {
    let mut p: Profile = serde_json::from_str(r#"{"unit_id": "a", "name": "a"}"#).unwrap();
    p.quality = 4;
    p.defense = 4;
    p.model_count = 1;
    p.wounds_max = vec![1];
    p.special_rules = rules.iter().map(|r| r.to_string()).collect();
    p.game_system = "gf".into();
    p.faction_folder = "elven_jesters".into();
    let mut reg = crate::rules::Registries::new(&repo_root());
    let mut us = UnitStatic::build_for(&mut reg, &p, epoch);
    us.melee = vec![ShootProfile { name: "Blade".into(), attacks: 12, count: 1, range: 0, ..Default::default() }];
    us
}

/// The carrier (unit 0) charges a lone Defense-4 target (unit 1) in round `round`; the carrier's arrival stamp
/// is `arrived` (-1 = deployed normally). Returns the strike's tray report.
fn charge(us: UnitStatic, epoch: u32, round: i64, arrived: i64, fatigued: bool) -> ShootResult {
    let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
    let target = UnitStatic {
        ctx: Ctx { defense: 4, tough: 1, models: 1, ..Default::default() },
        name: "Target".into(),
        model_count: 1,
        wounds_max: vec![1],
        ..Default::default()
    };
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 1];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions[0] = vec![[0.0, 0.0, 0.0]];
    st.positions[1] = vec![[1.0 * IN2M, 0.0, 0.0]];
    st.wounds[0] = vec![1];
    st.wounds[1] = vec![1];
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M];
    Rc::make_mut(&mut st.radii)[1] = vec![IN2M];
    st.round = round;
    st.ambush_arrived_round[0] = arrived;
    st.fatigued[0] = fatigued;
    let statics = vec![us, target];
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    let mut tray = Tray::seeded(7);
    let mut shot = ShootResult::default();
    strike_phase(&statics, &mut st, 0, 1, true, 0.0, seams, &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
    shot
}

fn hit_targets(shot: &ShootResult) -> Vec<i64> {
    shot.rolls.iter().filter(|r| r.kind == "attack").map(|r| r.target).collect()
}

fn logged(shot: &ShootResult) -> bool {
    shot.log.iter().any(|l| l.contains(IPS))
}

#[test]
fn arrival_round_charge_hits_on_three_at_epoch_73() {
    let shot = charge(carrier(&[IPS], EPOCH_73_V36), EPOCH_73_V36, 2, 2, false);
    let t = hit_targets(&shot);
    assert!(!t.is_empty(), "the blade rolls: {:?}", shot.rolls);
    assert!(t.iter().all(|&x| x == 3), "Quality 4 with +1 hits on 3+: {t:?}");
    assert!(logged(&shot), "rules-must-log: {:?}", shot.log);
}

#[test]
fn arrival_round_charge_hits_on_four_at_epoch_72() {
    let shot = charge(carrier(&[IPS], EPOCH_72_PLAYTEST_RULES), EPOCH_72_PLAYTEST_RULES, 2, 2, false);
    let t = hit_targets(&shot);
    assert!(!t.is_empty() && t.iter().all(|&x| x == 4), "rules 3.5: plain Quality 4+: {t:?}");
    assert!(!logged(&shot), "no rule applied, no line: {:?}", shot.log);
}

#[test]
fn the_round_after_arrival_hits_on_four_at_epoch_73() {
    let t = hit_targets(&charge(carrier(&[IPS], EPOCH_73_V36), EPOCH_73_V36, 3, 2, false));
    assert!(!t.is_empty() && t.iter().all(|&x| x == 4), "only the arrival round gets the +1: {t:?}");
}

#[test]
fn a_unit_deployed_normally_hits_on_four_at_epoch_73() {
    let t = hit_targets(&charge(carrier(&[IPS], EPOCH_73_V36), EPOCH_73_V36, 2, -1, false));
    assert!(!t.is_empty() && t.iter().all(|&x| x == 4), "no arrival, no +1: {t:?}");
}

#[test]
fn an_arrival_without_the_rule_hits_on_four_at_epoch_73() {
    let t = hit_targets(&charge(carrier(&[], EPOCH_73_V36), EPOCH_73_V36, 2, 2, false));
    assert!(!t.is_empty() && t.iter().all(|&x| x == 4), "a plain arriver gets nothing: {t:?}");
}

#[test]
fn a_fatigued_arrival_keeps_a_flat_six_at_epoch_73() {
    let shot = charge(carrier(&[IPS], EPOCH_73_V36), EPOCH_73_V36, 2, 2, true);
    let t = hit_targets(&shot);
    assert!(!t.is_empty() && t.iter().all(|&x| x == 6), "fatigue means an unmodified 6: {t:?}");
    assert!(!logged(&shot), "the bonus never reached the striker, no line: {:?}", shot.log);
}

#[test]
fn the_rule_counts_as_infiltrate_only_from_epoch_73() {
    assert!(carrier(&[IPS], EPOCH_73_V36).infiltrate_min_enemy_dist_in > 0.0, "an infiltrator's arrival ring");
    assert_eq!(carrier(&[IPS], EPOCH_72_PLAYTEST_RULES).infiltrate_min_enemy_dist_in, 0.0, "rules 3.5: no ring");
    assert_eq!(carrier(&[], EPOCH_73_V36).infiltrate_min_enemy_dist_in, 0.0, "a plain unit is no infiltrator");
}
