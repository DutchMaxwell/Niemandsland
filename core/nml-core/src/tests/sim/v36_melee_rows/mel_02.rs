//! MEL-02 tests (rules 3.6, lane melee): Limited is one use per game across shooting and melee, and the
//! melee spend names itself in the log. The Assault melee copy (MEL-01) is the profile under test.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::state::Weapon;

fn assault_pistol(limited: bool) -> Weapon {
    let mut rules = vec!["Assault".to_string()];
    if limited {
        rules.push("Limited".to_string());
    }
    Weapon { name: "Assault Pistol".into(), range: 12.0, attacks: 2, count: 1, ap: 1, rules }
}

/// The melee set the resolver and the estimates share, built at the record's epoch (MEL-01's copy).
fn melee_at(epoch: u32, limited: bool) -> Vec<ShootProfile> {
    crate::unit::melee_profiles_at(&[assault_pistol(limited)], epoch)
}

fn strike(st: &mut State, statics: &[UnitStatic], epoch: u32) -> ShootResult {
    let mut tray = Tray::seeded(2);
    let mut shot = ShootResult::default();
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    strike_phase(statics, st, 0, 1, false, 0.0, seams, &mut tray, &mut shot, StrikeSet::All, Cover::Recorded(None));
    shot
}

/// An unused Limited Assault weapon is spent by its first melee at 73 — and the log says so.
#[test]
fn an_unused_limited_assault_weapon_is_spent_by_its_first_melee_at_73() {
    let (mut st, mut statics) = duel(0);
    statics[0].melee = melee_at(EPOCH_73_V36, true);
    assert_eq!(statics[0].melee.len(), 1, "the Assault melee copy carries the Limited flag");
    assert!(statics[0].melee[0].limited);
    let shot = strike(&mut st, &statics, EPOCH_73_V36);
    assert!(st.limited_used[0].iter().any(|n| n == "Assault Pistol"), "{:?}", st.limited_used[0]);
    assert!(
        shot.log.iter().any(|l| l == "Assault Pistol (Limited) is used up in melee"),
        "{:?}",
        shot.log
    );
}

/// At 72 the pistol only shoots: there is no melee copy, so nothing is spent and nothing is logged.
#[test]
fn a_limited_assault_weapon_makes_no_melee_and_stays_available_at_72() {
    assert!(melee_at(EPOCH_72_PLAYTEST_RULES, true).is_empty());
    let (mut st, mut statics) = duel(0);
    statics[0].melee = melee_at(EPOCH_72_PLAYTEST_RULES, true);
    let shot = strike(&mut st, &statics, EPOCH_72_PLAYTEST_RULES);
    assert!(st.limited_used[0].is_empty(), "nothing struck, nothing spent");
    assert!(shot.log.iter().all(|l| !l.contains("(Limited)")), "{:?}", shot.log);
}

/// A Limited Assault weapon already spent by shooting no longer strikes in melee at 73.
#[test]
fn a_limited_assault_weapon_spent_by_shooting_does_not_strike_in_melee_at_73() {
    let (mut st, mut statics) = duel(0);
    statics[0].melee = melee_at(EPOCH_73_V36, true);
    Rc::make_mut(&mut st.limited_used)[0].push("Assault Pistol".into());
    let shot = strike(&mut st, &statics, EPOCH_73_V36);
    assert!(shot.rolls.iter().all(|r| r.kind != "attack"), "a spent weapon draws no dice: {:?}", shot.log);
    assert!(shot.log.iter().all(|l| !l.starts_with("Assault:")), "{:?}", shot.log);
}

/// CONTROL: a non-Limited Assault weapon is never spent and strikes in every melee.
#[test]
fn a_non_limited_assault_weapon_strikes_in_every_melee_at_73() {
    let (mut st, mut statics) = duel(0);
    statics[0].melee = melee_at(EPOCH_73_V36, false);
    let first = strike(&mut st, &statics, EPOCH_73_V36);
    let second = strike(&mut st, &statics, EPOCH_73_V36);
    assert!(first.rolls.iter().any(|r| r.kind == "attack"), "{:?}", first.log);
    assert!(second.rolls.iter().any(|r| r.kind == "attack"), "{:?}", second.log);
    assert!(st.limited_used[0].is_empty(), "a non-Limited weapon spends nothing");
}
