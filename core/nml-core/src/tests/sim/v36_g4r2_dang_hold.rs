//! Rules 3.6 row F-DANG-HOLD (G4 round 2, shooting acts): a unit that ACTIVATES standing in Dangerous
//! Terrain takes the test, a Hold included (ruling D2). The real activation path runs: a HOLD action on
//! a tray over a real Dangerous board, a real Rifle profile shooting after it.

use super::*;

/// `buff_line`'s unit "a" (two one-wound models, one Rifle) HOLDS and shoots "b", 8" away. With
/// `on_bar` its two bases stand on `dangerous_bar_board`'s Dangerous cells (x = 4"); without it they stay
/// at the origin, clear of the bar. `edit` adjusts the state before the activation runs.
fn hold_and_shoot(epoch: u32, on_bar: bool, edit: impl FnOnce(&mut State)) -> ShootResult {
    let (mut st, statics) = buff_line();
    if on_bar {
        st.positions[0] = vec![[4.0 * IN2M, 0.0, 0.0], [4.02 * IN2M, 0.0, 0.0]];
    }
    edit(&mut st);
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    let mut tray = Tray::seeded(11);
    let mut rng = crate::rng::GodotRng::new(0);
    let (_, shot) = resolve_stochastic_tray_on_board(
        &statics, &st, &buff_action(Some("b")), &dangerous_bar_board(), seams, &mut rng, &mut tray,
    )
    .unwrap();
    shot
}

/// The Dangerous test's own roll: an `attack` roll on the tray's success target 6, signed by the unit.
fn test_roll(shot: &ShootResult) -> Option<&crate::dice::Roll> {
    shot.rolls.iter().find(|r| r.kind == "attack" && r.target == DANGEROUS_TARGET)
}

/// The new leg: a Hold with the bases in a Dangerous cell draws one die per wound the unit has left (2)
/// BEFORE the volley, and the battle log names the rule.
#[test]
fn a_hold_on_dangerous_ground_takes_the_test_at_epoch_73() {
    let shot = hold_and_shoot(crate::acts::EPOCH_73_V36, true, |_| {});
    let r = test_roll(&shot).expect("a Hold activated in Dangerous Terrain must draw the test");
    assert_eq!((r.count, r.owner.as_str()), (2, "a"));
    assert!(std::ptr::eq(r, &shot.rolls[0]), "the test is the first thing the activation rolls");
    assert!(shot.log.iter().any(|l| l.starts_with("Dangerous terrain: a takes one test")), "{:?}", shot.log);
}

/// The control legs: below 73 the Hold stays untested (byte-identical), and a Hold clear of the bar never
/// tests, whatever the epoch.
#[test]
fn a_hold_tests_nothing_below_73_or_clear_of_the_bar() {
    let below = hold_and_shoot(crate::acts::EPOCH_72_PLAYTEST_RULES, true, |_| {});
    assert!(test_roll(&below).is_none(), "{:?}", below.rolls);
    assert!(below.log.iter().all(|l| !l.contains("Dangerous terrain")), "{:?}", below.log);
    let clear = hold_and_shoot(crate::acts::EPOCH_73_V36, false, |_| {});
    assert!(test_roll(&clear).is_none(), "{:?}", clear.rolls);
}

/// The table's `_dangerous_standing_counts` skips Aircraft and units still in reserve: neither tests when
/// it holds on the bar.
#[test]
fn an_aircraft_or_a_reserve_unit_on_the_bar_takes_no_standing_test() {
    let air = hold_and_shoot(crate::acts::EPOCH_73_V36, true, |st| st.aircraft[0] = true);
    assert!(test_roll(&air).is_none(), "{:?}", air.rolls);
    let reserve = hold_and_shoot(crate::acts::EPOCH_73_V36, true, |st| st.dormant[0] = true);
    assert!(test_roll(&reserve).is_none(), "{:?}", reserve.rolls);
}
