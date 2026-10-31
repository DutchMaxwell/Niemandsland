//! MEL-13 tests (rules 3.6, lane melee); empty until the row lands - start with `use super::super::*;`.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// MEL-13 (F 26b): one strike phase of the `duel` striker (Quality 4) at a defender built from
/// the flags. Returns the to-hit target the striker rolled and the log lines.
fn strike_at(epoch: u32, dodge: bool, melee_evasion: bool, fatigued: bool) -> (i64, Vec<String>) {
    let (mut st, mut statics) = duel(0);
    statics[1].ctx.dodge = dodge;
    statics[1].ctx.melee_evasion = melee_evasion;
    st.fatigued[1] = fatigued;
    let mut tray = Tray::seeded(2);
    let mut shot = ShootResult::default();
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    strike_phase(&statics, &mut st, 0, 1, false, 0.0, seams, &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
    let hit = shot.rolls.iter().find(|r| r.kind == "attack").expect("the striker rolls to hit");
    (hit.target, shot.log)
}

#[test]
fn a_rested_dodge_unit_costs_the_attacker_one_to_hit_at_epoch_73() {
    let (target, log) = strike_at(EPOCH_73_V36, true, false, false);
    assert_eq!(target, 5, "Quality 4 with -1 hits on 5+");
    assert!(log.iter().any(|l| l.contains("Dodge")), "rules-must-log: the line names Dodge: {log:?}");
}

#[test]
fn a_fatigued_dodge_unit_gives_no_penalty_and_says_so_at_epoch_73() {
    let (target, log) = strike_at(EPOCH_73_V36, true, false, true);
    assert_eq!(target, 4, "Fatigued: the plain Quality 4+");
    assert!(log.iter().any(|l| l.contains("Dodge") && l.contains("Fatigued")), "the no-effect line: {log:?}");
}

#[test]
fn a_dodge_unit_gives_no_penalty_at_epoch_72() {
    let (target, log) = strike_at(EPOCH_72_PLAYTEST_RULES, true, false, false);
    assert_eq!(target, 4, "below 73 Dodge is not played");
    assert!(log.iter().all(|l| !l.contains("Dodge")), "no Dodge line below 73: {log:?}");
}

#[test]
fn plain_melee_evasion_keeps_its_penalty_while_fatigued_at_both_epochs() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        assert_eq!(strike_at(epoch, false, true, true).0, 5, "epoch {epoch}: no Fatigued gate on Melee Evasion");
    }
}
