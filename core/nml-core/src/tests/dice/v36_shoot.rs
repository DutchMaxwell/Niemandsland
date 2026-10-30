//! Rules 3.6 lane shoot tests for the dice module; owned by lane shoot.

use super::*;

/// Precise folds its +1 into the hit target silently today, so `out.log` never
/// names it. The volley leg must write one rules-must-log line; the recorded
/// target and the hit count stay exactly what they were (no dice change).
#[test]
fn a_precise_volley_logs_the_rule_and_keeps_the_dice_unchanged() {
    let faces = Tray::seeded(27).roll(6);
    let plain = faces_to_hits(&faces, 4) as i64;
    let better = faces_to_hits(&faces, 3) as i64;
    assert!(better > plain, "fixture seed cannot tell the two targets apart");
    let mut tray = Tray::seeded(27);
    let out = resolve_shooting_with_tray(
        &[ShootProfile { precise: true, ..rifle(6) }],
        &[0], &[6], &shooter(4), &defender(4, 6), 12.0, &mut tray,
    );
    assert_eq!(out.rolls[0].target, 4, "the recorded target is still the raw to-hit");
    assert_eq!(out.rolls[1].count, better, "the hit count is unchanged by the log line");
    assert!(
        out.log.iter().any(|l| l.contains("Precise")),
        "a Precise volley must name itself in out.log, got {:?}",
        out.log
    );
    assert!(
        out.log.iter().any(|l| l.contains("volley")),
        "the volley leg's line says volley, got {:?}",
        out.log
    );
}

/// The same weapon without Precise must not invent the line.
#[test]
fn a_non_precise_volley_does_not_log_precise() {
    let mut tray = Tray::seeded(27);
    let out = resolve_shooting_with_tray(
        &[rifle(6)], &[0], &[6], &shooter(4), &defender(4, 6), 12.0, &mut tray,
    );
    assert!(
        !out.log.iter().any(|l| l.contains("Precise")),
        "a non-Precise volley must stay quiet, got {:?}",
        out.log
    );
}

/// The melee leg folds the same flag (`_solo_hits` serves both), so it names
/// itself there too, with the strike wording and the striker's name.
#[test]
fn a_precise_melee_strike_logs_the_rule() {
    let p = [ShootProfile { precise: true, ..blade(6) }];
    let att = shooter(4);
    let sh = striker(&p, &[0], &[6], &att);
    let mut tray = Tray::seeded(27);
    let out = resolve_melee_with_tray(
        &[sh], &defender(4, 6), "Target", false, false, false, &mut tray,
    );
    assert!(
        out.log.iter().any(|l| l.contains("Precise") && l.contains("strikes")),
        "a Precise strike must name itself in out.log, got {:?}",
        out.log
    );
}
