//! MEL-10 tests (rules 3.6, lane melee): from EPOCH_73_V36 the melee loser is the unit that TOOK more wounds in
//! the whole activation. Wounds a unit dealt itself on the charge move (Dangerous terrain) count against it, and
//! Fear(X) lifts the enemy's tally. Below the epoch the loser stays the unit that dealt fewer wounds.
//!
//! Both units are unarmed so no die decides the strikes: the verdict is carried by the self-wounds and Fear alone.

use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

fn unarmed(name: &str, fear: i64) -> UnitStatic {
    UnitStatic {
        ctx: Ctx { quality: 4, defense: 4, tough: 1, models: 1, fear, ..Default::default() },
        name: name.into(),
        model_count: 1,
        wounds_max: vec![1],
        ..Default::default()
    }
}

/// A charger (unit 0) and a defender (unit 1), one model each, standing in base contact.
fn duel() -> State {
    let profile: Profile = serde_json::from_str(r#"{"unit_id": "u", "name": "u"}"#).unwrap();
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: vec!["a".into(), "b".into()], index: HashMap::new(), profile: vec![0, 1] });
    st.profiles = Rc::new(Profiles { list: vec![profile.clone(), profile], index: HashMap::new() });
    st.player = vec![0, 1];
    st.alive = vec![1, 1];
    st.attached = Rc::new(vec![vec![], vec![]]);
    st.attached_to = Rc::new(vec![None, None]);
    st.positions[0] = vec![[2.0 * IN2M, 0.0, 0.0]];
    st.wounds[0] = vec![1];
    Rc::make_mut(&mut st.radii)[0] = vec![IN2M];
    st.positions[1] = vec![[0.0, 0.0, 0.0]];
    st.wounds[1] = vec![1];
    Rc::make_mut(&mut st.radii)[1] = vec![IN2M];
    st
}

/// The loser of the charge melee and the log the tray kept; `self_wounds` = what the charger took from its own
/// Dangerous test on the charge move before the melee began.
fn charge(charger_fear: i64, defender_fear: i64, self_wounds: i64, epoch: u32) -> (Option<usize>, Vec<String>) {
    let statics = vec![unarmed("Charger", charger_fear), unarmed("Defender", defender_fear)];
    let mut st = duel();
    let seams = Seams { rules_epoch: epoch, ..Default::default() };
    let mut tray = Tray::seeded(11);
    let mut shot = ShootResult::default();
    let loser = tray_charge_with_self_wounds(
        &statics, &mut st, 0, 1, seams, &mut tray, &mut shot, 0.0, Cover::Recorded(None), self_wounds);
    (loser, shot.log)
}

/// The row's own example, stripped of dice: the charger took 3 Dangerous wounds on the charge move and nothing
/// else happened in the strikes, so it took 3 against the defender's 0 and loses the melee at 73.
#[test]
fn the_charger_that_took_dangerous_wounds_on_the_charge_loses_at_epoch_73() {
    let (loser, log) = charge(0, 0, 3, EPOCH_73_V36);
    assert_eq!(loser, Some(0), "3 wounds taken against 0: the charger loses");
    assert!(
        log.iter().any(|l| l.contains("Charger took 3") && l.contains("Defender took 0")),
        "the verdict names the comparison as wounds taken: {log:?}"
    );
}

/// The 72 leg stays as played: only the wounds a side DEALT are compared, so the charger's own Dangerous wounds
/// change nothing — 0 dealt against 0 dealt is a tie and nobody tests, and no 73 line is written.
#[test]
fn the_charge_move_wounds_are_ignored_at_epoch_72() {
    let (loser, log) = charge(0, 0, 3, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(loser, None, "a tie in wounds dealt: nobody tests");
    assert!(!log.iter().any(|l| l.contains("took")), "the 72 leg writes no wounds-taken line: {log:?}");
}

/// Fear(X) adds +X to the ENEMY's taken: a Fear(2) charger that dealt nothing and took 2 Dangerous wounds ties
/// 2 against 2 at 73 and nobody tests. At 72 its Fear counted as 2 dealt, so the defender lost.
#[test]
fn a_tie_in_wounds_taken_tests_nobody_at_epoch_73() {
    let (loser, _) = charge(2, 0, 2, EPOCH_73_V36);
    assert_eq!(loser, None, "charger took 2, defender took 2 (Fear): a tie");
}

#[test]
fn the_same_fear_charger_still_wins_on_dealt_wounds_at_epoch_72() {
    let (loser, _) = charge(2, 0, 2, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(loser, Some(1), "Fear(2) counted as 2 dealt against 0: the defender loses");
}

/// Fear on the defender lifts the charger's taken at both epochs (the comparison Fear always made, now named as
/// wounds taken); with no self-wounds the two legs agree.
#[test]
fn defender_fear_still_counts_against_the_charger_at_both_epochs() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        let (loser, _) = charge(0, 2, 0, epoch);
        assert_eq!(loser, Some(0), "epoch {epoch}: the charger took 2 (Fear) against 0");
    }
}
