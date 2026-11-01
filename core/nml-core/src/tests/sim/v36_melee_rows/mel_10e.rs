//! MEL-10e: the AI's melee-morale ESTIMATE twin of MEL-10. From `EPOCH_73_V36` the loser is the
//! side that TOOK more wounds over the whole activation: the enemy's strikes, the enemy's Fear(X)
//! (which rides the ENEMY's tally) and the charger's own charge-move wounds. Below 73 the side that
//! dealt fewer loses and self-wounds are ignored. The table twin is
//! `scripts/solo/battle_sim.gd` `_expected_melee_morale`.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// Two 1-model units in contact: unit 0 (the charger) with `charger_fear` and unit 2 (the
/// defender) with `defender_fear`. `wounds[0]`/`wounds[2]` are what is LEFT after the strikes, so
/// `su_before`/`tu_before` = 10 fixes the melee tallies. Both statics are Q6, so a loser fails its
/// morale test and routes (`alive == 0`) — the marker of which side was made to test.
fn duel(charger_fear: i64, defender_fear: i64, su_left: i64, tu_left: i64) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster {
        keys: st.roster.keys.clone(),
        index: HashMap::new(),
        profile: vec![0, 0, 1, 0],
    });
    st.wounds[0] = vec![su_left];
    st.wounds[2] = vec![tu_left];
    let statics = vec![
        UnitStatic { ctx: Ctx { fear: charger_fear, ..Ctx::default() }, quality: 6, ..UnitStatic::default() },
        UnitStatic { ctx: Ctx { fear: defender_fear, ..Ctx::default() }, quality: 6, ..UnitStatic::default() },
    ];
    (st, statics)
}

/// The side the estimate sent to test: 0 = charger, 2 = defender, 99 = nobody (a live tie).
fn loser(
    charger_fear: i64,
    defender_fear: i64,
    su_left: i64,
    tu_left: i64,
    self_wounds: i64,
    rules_epoch: u32,
) -> i64 {
    let (mut st, statics) = duel(charger_fear, defender_fear, su_left, tu_left);
    expected_melee_morale(
        &mut st,
        &statics,
        0,
        10,
        2,
        10,
        self_wounds,
        Seams { rules_epoch, ..Default::default() },
    );
    if st.alive[0] == 0 {
        0
    } else if st.alive[2] == 0 {
        2
    } else {
        99
    }
}

/// The charger's own charge-move wounds are part of what it TOOK: 2 self-wounds against the
/// defender's 0 decide the melee at 73, so the charger is the side that tests and routes.
#[test]
fn the_chargers_own_self_wounds_count_as_taken_at_epoch_73() {
    assert_eq!(loser(0, 0, 10, 10, 2, EPOCH_73_V36), 0,
        "2 wounds taken against 0: the charger loses the estimate");
}

/// The 72 leg keeps the caused reading: self-wounds never entered the comparison, so 0 dealt
/// against 0 dealt is a tie and nobody tests.
#[test]
fn the_chargers_own_self_wounds_are_ignored_at_epoch_72() {
    assert_eq!(loser(0, 0, 10, 10, 2, EPOCH_72_PLAYTEST_RULES), 99,
        "72: a tie in wounds dealt, self-wounds are not caused");
}

/// The row's different-loser case: a Fear(2) charger that took 2 self-wounds. At 73 the defender
/// took 2 (the charger's Fear) against the charger's 2 — a tie, nobody tests. At 72 the Fear counted
/// as 2 DEALT against 0, so the defender lost.
#[test]
fn a_fear_chargers_self_wounds_tie_the_enemys_fear_tally_at_epoch_73() {
    assert_eq!(loser(2, 0, 10, 10, 2, EPOCH_73_V36), 99,
        "73: charger took 2, defender took 2 (Fear): nobody tests");
    assert_eq!(loser(2, 0, 10, 10, 2, EPOCH_72_PLAYTEST_RULES), 2,
        "72: Fear(2) counted as 2 dealt against 0: the defender loses");
}

/// A pure Fear case with no self-wounds: the two readings agree — the enemy of a Fear(2) unit took
/// 2, so the plain unit is the loser at both epochs.
#[test]
fn a_pure_fear_case_reads_the_same_loser_at_both_epochs() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        assert_eq!(loser(2, 0, 10, 10, 0, epoch), 2,
            "epoch {epoch}: the plain unit took the Fear(2) tally and loses");
    }
}

/// Fear on the DEFENDER lifts the charger's taken at both epochs: 0 strikes, 0 self-wounds, so the
/// charger took the defender's Fear(2) and loses.
#[test]
fn defender_fear_still_counts_against_the_charger_at_both_epochs() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        assert_eq!(loser(0, 2, 10, 10, 0, epoch), 0,
            "epoch {epoch}: the charger took Fear(2) against 0");
    }
}
