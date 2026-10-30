//! Rules 3.6 lane morale tests for the sim module; owned by lane morale.

use super::*;

// ------------------- MOR-08: Banner helps only shooting- or melee-caused tests ---

/// The Mind Control line with a Banner target: bearer "a" carries only the
/// registry's own "Mind Control" entry, target "b" (Quality 4, three models
/// 5" away) carries the capture stamp a lone Banner writes (`morale_bonus` 1,
/// no Morale(X) share).
fn banner_target_line(rules_epoch: u32) -> (State, Vec<UnitStatic>) {
    let (mut st, _) = storm_line("Storm of Change", "wormhole_daemons_of_change", rules_epoch);
    st.morale_bonus[2] = 1;
    let mut b = UnitStatic { name: "b".into(), ..Default::default() };
    b.ctx.quality = 4;
    b.ctx.defense = 4;
    b.ctx.tough = 1;
    let bearer = storm_bearer("Mind Control", "jackals", rules_epoch);
    (st, vec![bearer, UnitStatic { name: "ah".into(), ..Default::default() }, b, UnitStatic { name: "bh".into(), ..Default::default() }])
}

/// The first seed whose first tray face is a 3: a pass only with the Banner's +1.
fn seed_rolling_a_three() -> i64 {
    (0..500).find(|&s| Tray::seeded(s).roll(1)[0] == 3).expect("some seed rolls a 3") as i64
}

/// The Mind Control test die: one die, signed by the bearer.
fn mind_control_die(shot: &ShootResult) -> &crate::dice::Roll {
    shot.rolls.iter().find(|r| r.count == 1 && r.owner == "a").expect("the Mind Control morale die is drawn")
}

/// RED: from epoch 73 Mind Control is neither shooting nor melee, so the
/// Banner unit tests on its plain Quality 4+ and the 3 fails it.
#[test]
fn mind_control_tests_a_banner_unit_on_its_plain_quality_at_epoch_73() {
    let epoch = crate::acts::EPOCH_73_V36;
    let (st, statics) = banner_target_line(epoch);
    let (next, shot) = run_storm(&st, &statics, seed_rolling_a_three(), epoch);
    let die = mind_control_die(&shot);
    assert_eq!(die.faces[0], 3, "the seed must roll the 3 only the Banner turns into a pass: {die:?}");
    assert_eq!(die.target, 4, "epoch 73: no Banner +1 against Mind Control, the plain Quality 4+ binds: {die:?}");
    assert!(next.shaken[2], "the 3 fails the plain Quality test, so the target is Shaken");
    assert!(
        shot.log.iter().any(|l| l.contains("Banner") && l.contains("b:") && l.contains("Mind Control")),
        "rules-must-log: the skipped Banner is named with its cause — got {:#?}",
        shot.log
    );
}

/// Control: below epoch 73 the Banner still helps against Mind Control.
#[test]
fn mind_control_keeps_the_banner_at_epoch_72() {
    let (st, statics) = banner_target_line(72);
    let (next, shot) = run_storm(&st, &statics, seed_rolling_a_three(), 72);
    let die = mind_control_die(&shot);
    assert_eq!((die.faces[0], die.target), (3, 3), "epoch 72: the Banner's +1 makes the 3 a pass: {die:?}");
    assert!(!next.shaken[2], "epoch 72: the target holds");
    assert!(shot.log.iter().all(|l| !(l.contains("Banner") && l.contains("Mind Control"))), "{:#?}", shot.log);
}

/// One morale test on "b" through the shared resolver, the call a volley
/// (`melee` false) or a lost melee (`melee` true) makes.
fn combat_morale(melee: bool) -> (State, ShootResult) {
    let epoch = crate::acts::EPOCH_73_V36;
    let (mut st, statics) = banner_target_line(epoch);
    let mut tray = Tray::seeded(seed_rolling_a_three());
    let mut shot = ShootResult::default();
    let seams = Seams { rules_epoch: epoch, ..Seams::default() };
    tray_morale(&mut st, &statics, 2, melee, seams, &mut tray, &mut shot);
    (st, shot)
}

/// Control: a morale test caused by shooting keeps the Banner at epoch 73.
#[test]
fn a_shooting_morale_test_keeps_the_banner_at_epoch_73() {
    let (st, shot) = combat_morale(false);
    let die = shot.rolls.iter().find(|r| r.count == 1).expect("the morale die is drawn");
    assert_eq!((die.faces[0], die.target), (3, 3), "shooting: the Banner's +1 makes the 3 a pass: {die:?}");
    assert!(!st.shaken[2], "shooting: the target holds");
}

/// Control: a morale test caused by melee keeps the Banner at epoch 73.
#[test]
fn a_melee_morale_test_keeps_the_banner_at_epoch_73() {
    let (st, shot) = combat_morale(true);
    let die = shot.rolls.iter().find(|r| r.count == 1).expect("the morale die is drawn");
    assert_eq!((die.faces[0], die.target), (3, 3), "melee: the Banner's +1 makes the 3 a pass: {die:?}");
    assert_eq!(st.alive[2], 3, "melee: the target holds");
    assert!(!st.shaken[2], "melee: the target holds");
}
