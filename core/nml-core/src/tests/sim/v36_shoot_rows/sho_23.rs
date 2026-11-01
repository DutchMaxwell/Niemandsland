//! SHO-23 tests (rules 3.6, lane shoot): one Target token per marked unit gives a flat +1, and the Spotter rolls
//! before the bearer's own attacks. Rules 3.5 (the EPOCH_72 leg) keeps the stacking reading.
use super::super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

fn seams_at(epoch: u32) -> Seams {
    Seams { rules_epoch: epoch, ..Seams::default() }
}

/// A second living enemy (unit 3, 9" out) beside `tag_line`'s victim, so a Target's "up to X units" has two picks.
fn two_enemy_lines(rule: &str, markers: i64, range_in: f64) -> (State, Vec<UnitStatic>) {
    let (mut st, statics) = tag_line(rule, markers, range_in);
    st.alive[3] = 1;
    st.positions[3] = vec![[9.0 * IN2M, 0.0, 0.0]];
    Rc::make_mut(&mut st.radii)[3] = vec![IN2M];
    st.wounds[3] = vec![1];
    (st, statics)
}

fn run_volley(st: &State, statics: &[UnitStatic], action: &Action, seed: i64, epoch: u32) -> (State, ShootResult) {
    let terrain = crate::terrain::Terrain::default();
    let mut tray = Tray::seeded(seed);
    let mut rng = crate::rng::GodotRng::new(0);
    resolve_stochastic_tray_on_board(statics, st, action, &terrain, seams_at(epoch), &mut rng, &mut tray).unwrap()
}

/// Rules 3.6: the Target places ONE token on each of up to X units; the first volley folds a flat +1 AP (Defense 4
/// saves on 5) and the standing token is never spent.
#[test]
fn piercing_target_puts_one_token_on_each_of_two_units_and_gives_flat_ap_at_epoch_73() {
    let (st, statics) = two_enemy_lines("Piercing Target", 2, 18.0);
    let (next, shot) = tag_volley(&statics, &st, seams_at(EPOCH_73_V36));
    assert_eq!(next.piercing_tag_markers[2], 1, "one token on the toughest pick");
    assert_eq!(next.piercing_tag_markers[3], 1, "one token on the second unit");
    assert!(next.piercing_tag_persistent[2] && next.piercing_tag_persistent[3], "both tokens stand while the units live");
    assert_eq!(shot.rolls[1].target, 5, "ONE token: flat AP(+1) on the Defense-4 save, never +2");
    assert!(
        shot.log.iter().any(|l| l.contains("+1 (Target)")),
        "rules-must-log: the attack line says +1 (Target) — got {:#?}",
        shot.log
    );
    let placed = shot
        .log
        .iter()
        .find(|l| l.starts_with("Piercing Target: tagger places 1 token on each of"))
        .unwrap_or_else(|| panic!("rules-must-log: the placement line names the Target and each unit — got {:#?}", shot.log));
    assert!(placed.contains('b') && placed.contains("bh"), "every tagged unit is named: {placed}");
}

/// RED on main: two tokens on the same standing Target still return two +1s (stacking). From 73 the spend is flat 1.
#[test]
fn piercing_target_spends_one_flat_ap_however_many_tokens_stand_at_epoch_73() {
    let (mut st, _statics) = tag_line("Piercing Target", 1, 18.0);
    st.piercing_tag_markers[2] = 2;
    st.piercing_tag_persistent[2] = true;
    assert_eq!(piercing_tag_spend(&mut st, 2, EPOCH_73_V36), 1, "rules 3.6: one token, flat +1");
}

/// The pinned 3.5 leg: the same two tokens stack into AP(+2) and the pool is read, never zeroed.
#[test]
fn piercing_target_still_stacks_two_tokens_at_epoch_72() {
    let (mut st, _statics) = tag_line("Piercing Target", 1, 18.0);
    st.piercing_tag_markers[2] = 2;
    st.piercing_tag_persistent[2] = true;
    assert_eq!(piercing_tag_spend(&mut st, 2, EPOCH_72_PLAYTEST_RULES), 2, "rules 3.5: the stack reads whole");
    assert_eq!(st.piercing_tag_markers[2], 2, "a standing Target is never spent");
}

/// The 3.5 control volley over the same fixture: both markers land on the toughest pick and ride the save whole.
#[test]
fn piercing_target_piles_and_reads_two_markers_at_epoch_72() {
    let (st, statics) = two_enemy_lines("Piercing Target", 2, 18.0);
    let (next, shot) = tag_volley(&statics, &st, seams_at(EPOCH_72_PLAYTEST_RULES));
    assert_eq!(next.piercing_tag_markers[2..], [2, 0], "3.5: every marker on the toughest pick");
    assert_eq!(shot.rolls[1].target, 6, "3.5: AP(+2) from the two markers");
}

/// `buff_line` with a living second enemy (unit 3, 9") for the Target's "up to X units" pick.
fn precision_target_line() -> (State, Vec<UnitStatic>) {
    let (mut st, mut statics) = buff_line();
    statics[0].shoot = vec![gun("Rifle", 1, 24)];
    statics[0].utility_buffs = vec![UtilityBuff {
        bonus: "per_placed_marker".into(),
        markers: 2,
        uses_per_game: 1,
        range_in: 18.0,
        target: "enemy".into(),
        ..ub("Precision Target")
    }];
    st.alive[3] = 1;
    st.positions[3] = vec![[9.0 * IN2M, 0.0, 0.0]];
    Rc::make_mut(&mut st.radii)[3] = vec![IN2M];
    st.wounds[3] = vec![1];
    (st, statics)
}

/// Rules 3.6: one +1-to-hit token on each of two units, named in the placement line.
#[test]
fn precision_target_puts_one_token_on_each_of_two_units_at_epoch_73() {
    let (st, statics) = precision_target_line();
    let (next, volley) = run_volley(&st, &statics, &buff_action(Some("b")), 13, EPOCH_73_V36);
    assert_eq!(next.buffs[2].len(), 1, "the persistent record lands on the toughest pick");
    assert_eq!(next.buffs[2][0].hit_mod, 1, "rules 3.6: flat +1, not +2");
    assert_eq!(next.buffs[3].len(), 1, "the second unit gets its own token");
    assert_eq!(next.buffs[3][0].hit_mod, 1);
    assert_eq!(volley.rolls[0].target, 3, "Quality 4 + ONE token");
    let placed = volley
        .log
        .iter()
        .find(|l| l.starts_with("Precision Target: a places 1 token on each of"))
        .unwrap_or_else(|| panic!("rules-must-log: the placement names the Target and each unit — got {:#?}", volley.log));
    assert!(placed.contains('b') && placed.contains("bh"), "every tagged unit is named: {placed}");
}

/// The pinned 3.5 leg: a double-marker Target rides +2 on one pick.
#[test]
fn precision_target_still_gives_plus_two_at_epoch_72() {
    let (st, statics) = precision_target_line();
    let (next, volley) = run_volley(&st, &statics, &buff_action(Some("b")), 13, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(next.buffs[2].len(), 1);
    assert_eq!(next.buffs[2][0].hit_mod, 2, "rules 3.5: both markers ride one record");
    assert!(next.buffs[3].is_empty(), "3.5: one pick only");
    assert_eq!(volley.rolls[0].target, 2, "Quality 4 + two markers");
}

/// A Spotter beside the shooter; seed 1's first tray face is a 4.
fn spotter_line() -> (State, Vec<UnitStatic>) {
    let (st, mut statics) = buff_line();
    statics[0].shoot = vec![gun("Rifle", 6, 24)];
    statics[0].utility_buffs = vec![UtilityBuff {
        bonus: "per_removed_marker".into(),
        markers: 1,
        place_roll: 4,
        range_in: 30.0,
        target: "enemy".into(),
        ..ub("Precision Spotter")
    }];
    (st, statics)
}

/// Rules 3.6: the spot fires BEFORE the bearer's own attacks, so this same volley spends the marker for +1.
#[test]
fn precision_spotter_marks_before_the_bearers_own_volley_at_epoch_73() {
    let (st, statics) = spotter_line();
    let (next, volley) = run_volley(&st, &statics, &buff_action(Some("b")), 1, EPOCH_73_V36);
    assert_eq!(volley.rolls[0].target, 3, "the marker is available to the same volley: Quality 4 + 1");
    assert!(
        volley.log.iter().any(|l| l.starts_with("Precision Spotter: 1 marker removed")),
        "rules-must-log: the same volley spends the fresh marker — got {:#?}",
        volley.log
    );
    assert_eq!(next.spot_markers[2], 0, "the marker was spent by this volley");
}

/// The pinned 3.5 leg: the spot fires at the END, so the same volley rolls plain and the marker survives for later.
#[test]
fn precision_spotter_still_marks_at_the_end_of_activation_at_epoch_72() {
    let (st, statics) = spotter_line();
    let (next, volley) = run_volley(&st, &statics, &buff_action(Some("b")), 1, EPOCH_72_PLAYTEST_RULES);
    assert_eq!(volley.rolls[0].target, 4, "3.5: the marker lands after this volley, the roll stays plain");
    assert!(!volley.log.iter().any(|l| l.contains("marker removed")), "nothing to spend yet");
    assert!(next.spot_markers[2] >= 1, "the end-of-activation spot lands the marker for the next attack");
}
