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
    (0..500).find(|&s| Tray::seeded(s).roll(1)[0] == 3).expect("some seed rolls a 3")
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

// --- MOR-13 (rules 3.6, lead ruling D-SPELL-LOS): the casters and token
// batteries that boost a cast, and the enemy casters that resist it, count
// on their reach alone; line of sight no longer matters. The rules 3.5
// reading stays pinned at EPOCH_72 in caster_boost.rs and
// caster_interference.rs (the `_at_epoch_72` cases), on the same boards.
fn mor13_seams(e: u32) -> Seams {
    Seams { rules_epoch: e, cast_fold: true, hero_attach: true, ..Seams::default() }
}

fn mor13_logged(st: &State, needle: &str) -> bool {
    st.cast_events
        .iter()
        .any(|e| e["log"].as_str().map(|l| l.contains(needle)).unwrap_or(false))
}

/// The battery 2" from the caster, hidden from the caster's unit: at 3.6 it
/// still lends the boost's second token (own leftover first, then the
/// battery, the draw order the 3.5 board pins).
#[test]
fn a_helper_without_line_of_sight_lends_to_the_boost_at_epoch_73() {
    let (mut st, statics) = super::caster_boost::caster_and_battery();
    let los = vec![true, false, true, true];
    cast_phase(&statics, &mut st, 0, &los, mor13_seams(crate::acts::EPOCH_73_V36), None);
    assert_eq!(st.casts[0], 0, "the caster's own leftover still pays first: {:?}", st.casts);
    assert_eq!(st.casts[1], 1, "a hidden helper within reach lends at 3.6: {:?}", st.casts);
}

/// The enemy caster 9" away, hidden from the caster's unit: at 3.6 it still
/// spends both tokens against the cast (the spell itself picks the seen 12"
/// enemy, so only the resist pool reads the hidden foe).
#[test]
fn a_foe_without_line_of_sight_resists_the_cast_at_epoch_73() {
    let (mut st, statics) = super::caster_interference::caster_and_foe();
    let los = vec![true, true, true, false];
    cast_phase(&statics, &mut st, 0, &los, mor13_seams(crate::acts::EPOCH_73_V36), None);
    assert_eq!(st.casts[3], 0, "a hidden foe within 18\" resists at 3.6: {:?}", st.casts);
}

/// The reach still binds at 3.6: a foe 20" out keeps every token, seen or not.
#[test]
fn a_foe_past_the_aura_never_resists_at_epoch_73() {
    let (mut st, statics) = super::caster_interference::caster_and_foe();
    st.positions[3] = vec![[20.0 * IN2M, 0.0, 0.0]];
    let los = vec![true, true, true, false];
    cast_phase(&statics, &mut st, 0, &los, mor13_seams(crate::acts::EPOCH_73_V36), None);
    assert_eq!(st.casts[3], 2, "a foe past 18\" keeps every token: {:?}", st.casts);
}

/// Rules-must-log: at 3.6 the boost line with a helper's share and the
/// resist line name the reach that let the pool in, sight not needed; at
/// EPOCH_72 both lines stay as they were.
#[test]
fn the_pool_lines_name_the_reach_without_sight_at_epoch_73() {
    let note = "(casters within 18\", no line of sight needed)";
    let (mut st, statics) = super::caster_boost::caster_and_battery();
    let los = vec![true; st.units()];
    cast_phase(&statics, &mut st, 0, &los, mor13_seams(crate::acts::EPOCH_73_V36), None);
    assert!(mor13_logged(&st, &format!("helpers 1), target 4+ -> 2+ {note}")), "boost line: {:?}", st.cast_events);
    let (mut st, statics) = super::caster_interference::caster_and_foe();
    let los = vec![true; st.units()];
    cast_phase(&statics, &mut st, 0, &los, mor13_seams(crate::acts::EPOCH_73_V36), None);
    assert!(mor13_logged(&st, &format!("target 4+ -> 6+ {note}")), "resist line: {:?}", st.cast_events);

    for (mut st, statics) in [super::caster_boost::caster_and_battery(), super::caster_interference::caster_and_foe()] {
        let los = vec![true; st.units()];
        cast_phase(&statics, &mut st, 0, &los, mor13_seams(EPOCH_72_PLAYTEST_RULES), None);
        assert!(mor13_logged(&st, "Caster: "), "epoch 72 still logs the pool line: {:?}", st.cast_events);
        assert!(!mor13_logged(&st, note), "epoch 72 keeps the 3.5 line: {:?}", st.cast_events);
    }
}

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::combat::FEARLESS_RECOVER_TARGET;

// -------- MOR-01: Fearless counts MOST living models of a joined unit (ruling D-MOST) ----------
// From rules 3.6 a joined unit is Fearless when a strict majority of its living models carry the rule, a joined
// hero counting as one model; below EPOCH_73_V36 every living model has to carry it.

/// Unit 0 is a Q4 host of `host` living models with one joined hero (unit 1); `shaken` makes the morale test
/// fail for certain, so only the Fearless recovery die can save it.
fn joined_line(host: i64, host_fearless: bool, hero_fearless: bool, shaken: bool) -> (State, Vec<UnitStatic>) {
    let mut st = four_unit_line();
    st.roster = Rc::new(Roster { keys: st.roster.keys.clone(), index: HashMap::new(), profile: vec![0, 1, 0, 0] });
    st.alive[0] = host;
    st.wounds[0] = vec![1; host as usize];
    st.shaken[0] = shaken;
    let statics = vec![
        UnitStatic {
            name: "Squad".into(), quality: 4, model_count: host, fearless_own: host_fearless,
            ctx: Ctx { quality: 4, ..Ctx::default() }, ..UnitStatic::default()
        },
        UnitStatic {
            name: "Captain".into(), quality: 4, model_count: 1, fearless_own: hero_fearless,
            ctx: Ctx { quality: 4, ..Ctx::default() }, ..UnitStatic::default()
        },
    ];
    (st, statics)
}

/// The Fearless recovery dice the Shaken host draws in one morale test, and the battle log it writes.
fn recovery_dice(host: i64, host_fearless: bool, hero_fearless: bool, rules_epoch: u32) -> (usize, Vec<String>) {
    let (mut st, statics) = joined_line(host, host_fearless, hero_fearless, true);
    let mut shot = ShootResult::default();
    let seams = Seams { rules_epoch, hero_attach: true, ..Default::default() };
    tray_morale(&mut st, &statics, 0, false, seams, &mut Tray::seeded(7), &mut shot);
    (shot.rolls.iter().filter(|r| r.target == FEARLESS_RECOVER_TARGET).count(), shot.log)
}

/// The imagined test of the same unit, not Shaken: Q4 fails at a 50 % chance, Fearless halves it and holds.
fn fails_expected(host: i64, host_fearless: bool, hero_fearless: bool, rules_epoch: u32) -> bool {
    let (st, statics) = joined_line(host, host_fearless, hero_fearless, false);
    morale_fails_expected(&st, &statics, 0, Seams { rules_epoch, hero_attach: true, ..Default::default() })
}

#[test]
fn most_models_decide_fearless_at_epoch_73() {
    let (dice, log) = recovery_dice(5, true, false, EPOCH_73_V36);
    assert_eq!(dice, 1, "5 of 6 models carry Fearless: the Shaken unit rolls its recovery die");
    assert!(log.iter().any(|l| l.contains("Fearless: 5 of 6 models of Squad")), "the count is logged: {log:?}");
    assert!(!fails_expected(5, true, false, EPOCH_73_V36), "the imagined test halves the fail chance too");
    let (dice, log) = recovery_dice(1, true, false, EPOCH_73_V36);
    assert_eq!(dice, 0, "1 Fearless model and 1 plain hero is an exact half: no die");
    assert!(!log.iter().any(|l| l.starts_with("Fearless:")), "no count line without the rule: {log:?}");
    assert!(fails_expected(1, true, false, EPOCH_73_V36));
    assert_eq!(recovery_dice(3, false, true, EPOCH_73_V36).0, 0, "a Fearless hero in a plain 3-model unit is 1 of 4: no die");
    assert!(fails_expected(3, false, true, EPOCH_73_V36));
    let (dice, log) = recovery_dice(5, true, true, EPOCH_73_V36);
    assert_eq!(dice, 1, "every model Fearless still rolls");
    assert!(!log.iter().any(|l| l.starts_with("Fearless:")), "no count line when every model has it: {log:?}");
}

#[test]
fn fearless_needs_every_model_at_epoch_72() {
    let (dice, log) = recovery_dice(5, true, false, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(dice, 0, "a plain joined hero withholds Fearless from the whole unit");
    assert!(!log.iter().any(|l| l.starts_with("Fearless:")), "{log:?}");
    assert!(fails_expected(5, true, false, EPOCH_72_PLAYTEST_RULES));
    assert_eq!(recovery_dice(5, true, true, EPOCH_72_PLAYTEST_RULES).0, 1, "every model Fearless rolls");
}
