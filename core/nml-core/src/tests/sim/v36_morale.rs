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
    tray_morale(&mut st, &statics, 2, melee, seams, &mut tray, &mut shot, None, None);
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
    tray_morale(&mut st, &statics, 0, false, seams, &mut Tray::seeded(7), &mut shot, None, None);
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

// -------- MOR-16a: Spell Drain spends two spell tokens on a failed Morale
// test, once per activation, at the attack seam (owner: lane morale). --------
mod mor_16a {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::rules::Registries;

    /// The bearer read through the LIVE registry (pattern 11).
    fn bearer(faction: &str, epoch: u32) -> UnitStatic {
        let p = Profile {
            cost: 0, unit_id: "a".into(), name: "a".into(),
            quality: 4, defense: 4, tough: 1, wounds_max: vec![1], model_count: 1,
            weapons: vec![], special_rules: vec!["Spell Drain".into()],
            caster_value: 0, base_radius: 0.0, base_shape: String::new(),
            base_w_mm: 0.0, base_d_mm: 0.0, game_system: "gf".into(),
            faction_folder: faction.into(), item_grants: vec![],
            attached_hero_rules: vec![], move_bands: MoveBands::default(),
        };
        let mut reg = Registries::new(&super::super::repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch)
    }

    /// Unit 0 carries Spell Drain, unit 2 is the picked enemy with `quality`
    /// and `tokens` spell tokens; units 1/3 are empty dummies.
    fn line(faction: &str, epoch: u32, quality: i64, tokens: i64) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(Roster { keys: r.keys.clone(), index: HashMap::new(),
            profile: vec![0, 1, 2, 3] });
        st.casts[2] = tokens;
        let mut target = UnitStatic { name: "target".into(), ..Default::default() };
        target.quality = quality;
        target.ctx.quality = quality;
        target.model_count = 1;
        target.wounds_max = vec![1];
        (st, vec![bearer(faction, epoch), UnitStatic::default(), target, UnitStatic::default()])
    }

    /// The first seed whose FIRST tray face fails `quality` (the real die path).
    fn seed_failing(quality: u8) -> i64 {
        (0..500)
            .find(|&s| Tray::seeded(s).roll(1)[0] < quality)
            .expect("some seed fails the quality")
    }

    /// The first seed whose first tray face passes `quality` (a 1 always fails).
    fn seed_passing(quality: u8) -> i64 {
        (0..500)
            .find(|&s| {
                let f = Tray::seeded(s).roll(1)[0];
                f != 1 && f >= quality
            })
            .expect("some seed passes the quality")
    }

    fn drain(
        st: &mut State, statics: &[UnitStatic], epoch: u32, dist: f64, seed: i64,
    ) -> ShootResult {
        let seams = Seams { rules_epoch: epoch, ..Seams::default() };
        let mut tray = Tray::seeded(seed);
        let mut shot = ShootResult::default();
        crate::sim::tray_vs_marks(statics, st, 0, 2, dist, seams, &mut tray, &mut shot);
        shot
    }

    /// GREEN: a failed test costs exactly the two printed tokens.
    #[test]
    fn spell_drain_spends_two_tokens_on_a_failed_test() {
        let (mut st, statics) = line("blessed_sisters", EPOCH_73_V36, 4, 5);
        st.round = 1;
        let shot = drain(&mut st, &statics, EPOCH_73_V36, 10.0, seed_failing(4));
        assert_eq!(st.casts[2], 3, "two tokens");
        assert!(shot.log.iter().any(|l| l.contains("loses 2 spell tokens")), "{:?}", shot.log);
    }

    /// A passed test spends nothing and leaves the target standing.
    #[test]
    fn a_passed_test_keeps_the_token_store() {
        let (mut st, statics) = line("blessed_sisters", EPOCH_73_V36, 4, 5);
        st.round = 1;
        let shot = drain(&mut st, &statics, EPOCH_73_V36, 10.0, seed_passing(4));
        assert_eq!(st.casts[2], 5, "no loss");
        assert!(!st.shaken[2], "a pass does not Shake");
        assert!(shot.log.iter().any(|l| l.contains("passes the Morale test")), "{:?}", shot.log);
    }

    /// The store floors at zero: one token in, the two out.
    #[test]
    fn spell_drain_floors_the_token_store_at_zero() {
        let (mut st, statics) = line("blessed_sisters", EPOCH_73_V36, 4, 1);
        st.round = 1;
        drain(&mut st, &statics, EPOCH_73_V36, 10.0, seed_failing(4));
        assert_eq!(st.casts[2], 0);
    }

    /// Range and line of sight gate the pick exactly like a Mark.
    #[test]
    fn out_of_range_or_hidden_targets_lose_nothing() {
        let (mut st, statics) = line("blessed_sisters", EPOCH_73_V36, 4, 5);
        st.round = 1;
        drain(&mut st, &statics, EPOCH_73_V36, 19.0, seed_failing(4));
        assert_eq!(st.casts[2], 5, "19\" is outside the 18\" reach");
        let (mut st, statics) = line("blessed_sisters", EPOCH_73_V36, 4, 5);
        st.round = 1;
        st.los_pairs = Some(Rc::new(vec![false; 16]));
        drain(&mut st, &statics, EPOCH_73_V36, 10.0, seed_failing(4));
        assert_eq!(st.casts[2], 5, "no line of sight, no pick");
    }

    /// The once latch: a second attack in the same round drains nothing.
    #[test]
    fn a_second_activation_in_the_same_round_drains_nothing() {
        let (mut st, statics) = line("blessed_sisters", EPOCH_73_V36, 4, 5);
        st.round = 1;
        let first = drain(&mut st, &statics, EPOCH_73_V36, 10.0, seed_failing(4));
        assert!(!first.rolls.is_empty(), "the first attack rolls the test");
        let after_first = st.casts[2];
        assert!(after_first < 5, "the first attack drains");
        let second = drain(&mut st, &statics, EPOCH_73_V36, 10.0, seed_passing(4));
        assert_eq!(st.casts[2], after_first, "the latch holds");
        assert!(second.rolls.is_empty(), "no second test in the round");
    }

    /// Pattern 12: below 73 the entry is inert, draws no die and the tokens stay.
    #[test]
    fn spell_drain_is_inert_at_epoch_72() {
        let (mut st, statics) = line("blessed_sisters", EPOCH_72_PLAYTEST_RULES, 4, 5);
        st.round = 1;
        let shot = drain(&mut st, &statics, EPOCH_72_PLAYTEST_RULES, 10.0, seed_failing(4));
        assert_eq!(st.casts[2], 5);
        assert!(!st.shaken[2], "the branch is inert");
        assert!(shot.rolls.is_empty(), "no die below 73");
    }
}


// -------- MOR-16c: the core Spell Drain rolls the REAL tray Morale test and
// leaves the target Shaken (rules 3.6), once per activation (owner: lane
// morale). --------
mod mor_16c {
    use super::super::*;
    use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
    use crate::rules::Registries;

    /// The bearer read through the LIVE registry (pattern 11).
    fn bearer(epoch: u32) -> UnitStatic {
        let p = Profile {
            cost: 0, unit_id: "a".into(), name: "a".into(),
            quality: 4, defense: 4, tough: 1, wounds_max: vec![1], model_count: 1,
            weapons: vec![], special_rules: vec!["Spell Drain".into()],
            caster_value: 0, base_radius: 0.0, base_shape: String::new(),
            base_w_mm: 0.0, base_d_mm: 0.0, game_system: "gf".into(),
            faction_folder: "blessed_sisters".into(), item_grants: vec![],
            attached_hero_rules: vec![], move_bands: MoveBands::default(),
        };
        let mut reg = Registries::new(&super::super::repo_root());
        UnitStatic::build_for(&mut reg, &p, epoch)
    }

    /// Unit 0 carries Spell Drain, unit 2 is the picked enemy with `quality`
    /// and `tokens` spell tokens; units 1/3 are empty dummies.
    fn line(epoch: u32, quality: i64, tokens: i64) -> (State, Vec<UnitStatic>) {
        let mut st = four_unit_line();
        let r = &*st.roster;
        st.roster = Rc::new(Roster { keys: r.keys.clone(), index: HashMap::new(),
            profile: vec![0, 1, 2, 3] });
        st.casts[2] = tokens;
        let mut target = UnitStatic { name: "target".into(), ..Default::default() };
        target.quality = quality;
        target.ctx.quality = quality;
        target.model_count = 1;
        target.wounds_max = vec![1];
        (st, vec![bearer(epoch), UnitStatic::default(), target, UnitStatic::default()])
    }

    /// The first seed above zero whose FIRST tray face fails `quality` (a 1
    /// always fails, so a joined hero at Quality 6 keeps the target at 6).
    fn seed_failing(quality: u8) -> i64 {
        (1..500)
            .find(|&s| Tray::seeded(s).roll(1)[0] < quality)
            .expect("some seed fails the quality")
    }

    /// The first seed above zero whose first tray face passes `quality`.
    fn seed_passing(quality: u8) -> i64 {
        (1..500)
            .find(|&s| {
                let f = Tray::seeded(s).roll(1)[0];
                f != 1 && f >= quality
            })
            .expect("some seed passes the quality")
    }

    /// One drain on a REAL tray seeded by `seed` (also the round, so the latch
    /// key is stable across the two calls a latch test makes).
    fn drain(st: &mut State, statics: &[UnitStatic], epoch: u32, dist: f64, seed: i64)
        -> (Tray, ShootResult) {
        st.round = seed;
        let seams = Seams { rules_epoch: epoch, ..Seams::default() };
        let mut tray = Tray::seeded(seed);
        let mut shot = ShootResult::default();
        crate::sim::tray_vs_marks(statics, st, 0, 2, dist, seams, &mut tray, &mut shot);
        (tray, shot)
    }

    /// GREEN: a forced-fail drain rolls the production Morale die, Shakes the
    /// target and spends exactly two tokens.
    #[test]
    fn a_failed_spell_drain_rolls_the_tray_die_and_shakes_the_target() {
        let (mut st, statics) = line(EPOCH_73_V36, 6, 5);
        let seed = seed_failing(6);
        let (_tray, shot) = drain(&mut st, &statics, EPOCH_73_V36, 10.0, seed);
        let die = shot.rolls.iter()
            .find(|r| r.count == 1 && r.target == 6 && r.owner == "a")
            .expect("the drain rolls the tray Morale die");
        assert!(die.faces[0] < 6, "the seed fails Quality 6: {die:?}");
        assert!(st.shaken[2], "a failed drain leaves the target Shaken (rules 3.6)");
        assert_eq!(st.casts[2], 3, "exactly two spell tokens on a failure");
    }

    /// A forced-pass drain: one die, no Shaken, the pool untouched.
    #[test]
    fn a_passed_spell_drain_keeps_the_tokens_and_leaves_the_target_steady() {
        let (mut st, statics) = line(EPOCH_73_V36, 6, 5);
        let (_tray, shot) = drain(&mut st, &statics, EPOCH_73_V36, 10.0, seed_passing(6));
        assert_eq!(shot.rolls.iter().filter(|r| r.target == 6).count(), 1, "one Morale die");
        assert!(!st.shaken[2], "a passed test does not Shake");
        assert_eq!(st.casts[2], 5, "a passed test costs no tokens");
    }

    /// The failed test Shakes the target AND its joined chain.
    #[test]
    fn the_failed_drain_shakes_the_attached_chain() {
        let (mut st, mut statics) = line(EPOCH_73_V36, 6, 5);
        statics[3].quality = 6;
        let seed = seed_failing(6);
        st.round = seed;
        let seams = Seams { rules_epoch: EPOCH_73_V36, hero_attach: true, ..Seams::default() };
        let mut tray = Tray::seeded(seed);
        let mut shot = ShootResult::default();
        crate::sim::tray_vs_marks(&statics, &mut st, 0, 2, 10.0, seams, &mut tray, &mut shot);
        assert!(st.shaken[2] && st.shaken[3], "the target and its joined hero");
    }

    /// The once-per-round latch: a second attack draws no die and drains nothing.
    #[test]
    fn the_drain_latch_holds_a_second_attack_in_the_same_round() {
        let (mut st, statics) = line(EPOCH_73_V36, 6, 5);
        let seed = seed_failing(6);
        let (_f, _first) = drain(&mut st, &statics, EPOCH_73_V36, 10.0, seed);
        assert_eq!(st.casts[2], 3);
        let after = st.casts[2];
        let (_s, second) = drain(&mut st, &statics, EPOCH_73_V36, 10.0, seed);
        assert!(second.rolls.iter().all(|r| r.target != 6), "no second Morale die");
        assert_eq!(st.casts[2], after, "the latch stops the second drain");
    }

    /// Pattern 12: below 73 the whole branch is inert — no die, no Shaken, no
    /// token loss, and the tray never moves.
    #[test]
    fn the_epoch_72_control_stays_inert() {
        let (mut st, statics) = line(EPOCH_72_PLAYTEST_RULES, 6, 5);
        let (tray, shot) = drain(&mut st, &statics, EPOCH_72_PLAYTEST_RULES, 10.0, 1);
        assert!(shot.rolls.is_empty(), "no die below 73");
        assert!(!st.shaken[2]);
        assert_eq!(st.casts[2], 5);
        assert_eq!(tray.state_i64(), Tray::seeded(1).state_i64(), "the tray did not move");
    }

    /// Floor: two tokens out of a one-token store still leaves zero.
    #[test]
    fn a_failed_drain_floors_the_token_store_at_zero() {
        let (mut st, statics) = line(EPOCH_73_V36, 6, 1);
        drain(&mut st, &statics, EPOCH_73_V36, 10.0, 1);
        assert_eq!(st.casts[2], 0);
    }
}
