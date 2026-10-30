//! Rules 3.6 row MOR-10 tests (sim module); owned by lane morale.

use super::*;

// MOR-10 (CORE 15a): from EPOCH_73_V36 a friendly unit within 6" of a not-Shaken Tough(9)+ Hero may test
// morale on that Hero's Quality. The Hero is its own unit (a Tough(9)+ Hero cannot be joined), so the
// reading needs positions, not the attachment list. Below 73 the unit keeps its own Quality.

/// Unit 0 = a Q5 squad, unit 1 = its friendly Q3 Tough(9) Hero five base-edge inches away (both bases are
/// 1" radius, so the centres sit seven inches apart). `tweak` bends one thing per test; the morale test
/// is played on the tray and the die's target is what the unit tested on.
fn aura_round(epoch: u32, tweak: impl FnOnce(&mut State, &mut Vec<UnitStatic>)) -> (Option<i64>, Vec<String>) {
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: st.roster.keys.clone(), index: HashMap::new(), profile: vec![0, 1, 0, 0] });
    st.attached = Rc::new(vec![vec![]; 4]);
    st.attached_to = Rc::new(vec![None; 4]);
    st.positions[1] = vec![[7.0 * IN2M, 0.0, 0.0]];
    let mut statics = vec![
        UnitStatic { name: "Squad".into(), quality: 5, ctx: Ctx { quality: 5, ..Ctx::default() }, model_count: 1, wounds_max: vec![1], ..UnitStatic::default() },
        UnitStatic {
            name: "Warlord".into(), quality: 3, is_hero: true, ctx: Ctx { quality: 3, tough: 9, ..Ctx::default() },
            model_count: 1, wounds_max: vec![1], ..UnitStatic::default()
        },
    ];
    tweak(&mut st, &mut statics);
    let mut shot = ShootResult::default();
    let seams = Seams { rules_epoch: epoch, hero_attach: true, ..Default::default() };
    tray_morale(&mut st, &statics, 0, false, seams, &mut Tray::seeded(7), &mut shot);
    (shot.rolls.first().map(|r| r.target), shot.log)
}

/// RED on origin/main: the unit tests on its own Q5 whatever stands next to it.
#[test]
fn a_unit_five_inches_from_a_tough_nine_hero_tests_on_the_hero_quality() {
    let (target, _) = aura_round(crate::acts::EPOCH_73_V36, |_, _| {});
    assert_eq!(target, Some(3), "5\" from a Tough(9) Hero: the Hero's Q3 is the test");
}

/// Control: below 73 the same table keeps the unit's own Quality.
#[test]
fn a_unit_five_inches_from_a_tough_nine_hero_keeps_its_quality_at_epoch_72() {
    let (target, _) = aura_round(crate::acts::EPOCH_72_PLAYTEST_RULES, |_, _| {});
    assert_eq!(target, Some(5));
}

/// Control: the aura ends past six inches (base edge to base edge).
#[test]
fn a_unit_seven_inches_from_the_hero_keeps_its_own_quality() {
    let (target, _) = aura_round(crate::acts::EPOCH_73_V36, |st, _| st.positions[1] = vec![[9.0 * IN2M, 0.0, 0.0]]);
    assert_eq!(target, Some(5), "7\" is outside the 6\" aura");
}

/// Control: a Shaken Hero lends nothing.
#[test]
fn a_shaken_hero_lends_nothing() {
    let (target, _) = aura_round(crate::acts::EPOCH_73_V36, |st, _| st.shaken[1] = true);
    assert_eq!(target, Some(5));
}

/// Control: the aura starts at Tough(9) — Tough(6) is not enough.
#[test]
fn a_tough_six_hero_lends_nothing() {
    let (target, _) = aura_round(crate::acts::EPOCH_73_V36, |_, s| s[1].ctx.tough = 6);
    assert_eq!(target, Some(5));
}

/// Control: only a Hero lends it — the same Tough(9) body without the Hero stamp does not.
#[test]
fn a_tough_nine_unit_that_is_no_hero_lends_nothing() {
    let (target, _) = aura_round(crate::acts::EPOCH_73_V36, |_, s| s[1].is_hero = false);
    assert_eq!(target, Some(5));
}

/// Control: an enemy Hero and a dead Hero lend nothing.
#[test]
fn an_enemy_hero_and_a_dead_hero_lend_nothing() {
    let (enemy, _) = aura_round(crate::acts::EPOCH_73_V36, |st, _| st.player[1] = 1);
    assert_eq!(enemy, Some(5), "an enemy Hero");
    let (dead, _) = aura_round(crate::acts::EPOCH_73_V36, |st, _| st.alive[1] = 0);
    assert_eq!(dead, Some(5), "a dead Hero");
}

/// Control: the unit keeps a better Quality of its own.
#[test]
fn a_unit_with_a_better_quality_than_the_hero_keeps_it() {
    let (target, _) = aura_round(crate::acts::EPOCH_73_V36, |_, s| { s[0].ctx.quality = 2; s[0].quality = 2; });
    assert_eq!(target, Some(2));
}

/// rules-must-log (RED on main): the applied aura names the Hero and the unit.
#[test]
fn the_aura_writes_a_battle_log_line() {
    let (_, log) = aura_round(crate::acts::EPOCH_73_V36, |_, _| {});
    let line = log.iter().find(|l| l.contains("lends its Quality"));
    assert!(line.is_some_and(|l| l.contains("Warlord") && l.contains("Squad") && l.contains("Q3+")), "log: {log:?}");
}

/// The aura line is silent when the Hero does not help (7" away).
#[test]
fn no_aura_line_is_written_when_the_hero_does_not_help() {
    let (_, log) = aura_round(crate::acts::EPOCH_73_V36, |st, _| st.positions[1] = vec![[9.0 * IN2M, 0.0, 0.0]]);
    assert!(!log.iter().any(|l| l.contains("lends its Quality")), "log: {log:?}");
}
