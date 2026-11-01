//! SHO-17e tests (rules 3.6, lane shoot): the AI's expected-wounds estimate is the twin of
//! SHO-17. The Guarded family's +1 Defense and the Screened alias's -1 to hit are only paid
//! when the attack crossed the stamped distance gate — a shot over 9", a charge over the
//! 6" charge threshold from `EPOCH_73_V36`. The melee leg reads the W1.5b pre-charge edge
//! gap it is handed (`charge_from_in`), never a new measure; below the epoch the stamped
//! gate is 0.0 and the estimate keeps its old numbers.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::combat::{melee_ev, profile_ev};

/// The engine's own charge gate: 6.0 from the epoch, 0.0 (no charge read) below it —
/// `sim::ctx_live` / `sim::ctx_of_melee` stamp it on the defender's context.
const SIX_IN: f64 = 6.0;
const OLD_READ: f64 = 0.0;

/// Quality 4+ striker of 5 models at `rules_epoch`.
fn gunner(epoch: u32) -> Ctx {
    Ctx { quality: 4, models: 5, rules_epoch: epoch, ..Default::default() }
}

/// The SHO-17 context: the Guarded family on, carrying the stamped charge gate.
fn guarded(gate_in: f64) -> Ctx {
    Ctx { guarded: true, guarded_name: "Guarded", guarded_charge_over_in: gate_in, ..defender(4, 5) }
}

/// A Screened-kind Stealth alias: -1 to hit, its own over-9" entry, charge leg on.
fn screened() -> Ctx {
    Ctx {
        stealth_alias_penalty: 1,
        stealth_alias_over_in: 9.0,
        stealth_alias_applies_charged: true,
        ..defender(4, 5)
    }
}

/// 10 attacks at 4+ into Defense 4+: 5 hits, half saved.
const BARE: f64 = 2.5;
/// 10 attacks at 4+ into the Guarded Defense 3+: 5 hits, a third saved.
const GUARDED: f64 = 5.0 / 3.0;
/// 10 attacks at 5+ (the Screened -1) into Defense 4+: 10/3 hits, half saved.
const SCREENED: f64 = 5.0 / 3.0;

/// RED on main: a Guarded defender charged from 7" saves one better at rules 3.6, because the
/// estimate reads the stamped 6" charge gate against the pre-charge gap it is handed.
#[test]
fn a_guarded_defender_charged_from_seven_inches_saves_one_better_at_epoch_73() {
    let att = gunner(EPOCH_73_V36);
    let ev = profile_ev(&blade(10), 10, &att, &guarded(SIX_IN), 7.0, true);
    assert!((ev - GUARDED).abs() < 1e-9, "charged from over 6\": 4+ becomes 3+, got {ev}");
    assert!(ev < profile_ev(&blade(10), 10, &att, &defender(4, 5), 7.0, true));
}

/// A charge from 5" lies inside the gate: the bare Defense stays.
#[test]
fn a_guarded_defender_charged_from_five_inches_keeps_the_bare_save_at_epoch_73() {
    let att = gunner(EPOCH_73_V36);
    let ev = profile_ev(&blade(10), 10, &att, &guarded(SIX_IN), 5.0, true);
    assert!((ev - BARE).abs() < 1e-9, "5\" is not over the 6\" gate, got {ev}");
}

/// The shot leg keeps its shared over-9" gate at the epoch: 7" earns nothing, 10" the +1.
#[test]
fn a_guarded_target_shot_from_seven_inches_gets_no_bonus_at_epoch_73() {
    let att = gunner(EPOCH_73_V36);
    let ev = profile_ev(&rifle(10), 10, &att, &guarded(SIX_IN), 7.0, false);
    assert!((ev - BARE).abs() < 1e-9, "the charge gate never reaches a shot, got {ev}");
}

#[test]
fn a_guarded_target_shot_from_over_nine_inches_gets_the_bonus_at_epoch_73() {
    let att = gunner(EPOCH_73_V36);
    let ev = profile_ev(&rifle(10), 10, &att, &guarded(SIX_IN), 10.0, false);
    assert!((ev - GUARDED).abs() < 1e-9, "over 9\" still pays the +1, got {ev}");
}

/// THE OLD SIDE: below the epoch the stamped gate is 0.0, so the melee estimate keeps its old
/// numbers at every gap.
#[test]
fn below_epoch_73_a_guarded_charge_keeps_the_old_numbers() {
    let att = gunner(EPOCH_72_PLAYTEST_RULES);
    for gap in [5.0, 7.0, 10.0] {
        let ev = profile_ev(&blade(10), 10, &att, &guarded(OLD_READ), gap, true);
        assert!((ev - BARE).abs() < 1e-9, "{gap}\" at 72: the old unconditional number, got {ev}");
    }
}

/// The W1.5b parameter is the one the estimate reads: `melee_ev` forwards its pre-charge gap.
#[test]
fn melee_ev_reads_the_pre_charge_gap_it_is_handed() {
    let att = gunner(EPOCH_73_V36);
    let def = guarded(SIX_IN);
    let far = melee_ev(&[blade(10)], &[10], &att, &def, true, 7.0);
    let near = melee_ev(&[blade(10)], &[10], &att, &def, true, 5.0);
    assert!(far < near, "7\" is over the gate, 5\" is not: {far} vs {near}");
    assert!((far - GUARDED).abs() < 1e-9, "the 7\" charge saves at 3+, got {far}");
    assert!((near - BARE).abs() < 1e-9, "the 5\" charge keeps the 4+, got {near}");
}

/// RED on main: the Screened alias's charge leg reads the same 6" gate from the epoch on.
#[test]
fn a_screened_defender_charged_from_seven_inches_costs_the_hit_at_epoch_73() {
    let att = gunner(EPOCH_73_V36);
    let ev = profile_ev(&blade(10), 10, &att, &screened(), 7.0, true);
    assert!((ev - SCREENED).abs() < 1e-9, "charged from over 6\": 4+ becomes 5+, got {ev}");
    assert!(ev < profile_ev(&blade(10), 10, &att, &defender(4, 5), 7.0, true));
}

#[test]
fn a_screened_defender_charged_from_five_inches_keeps_the_hit_at_epoch_73() {
    let att = gunner(EPOCH_73_V36);
    let ev = profile_ev(&blade(10), 10, &att, &screened(), 5.0, true);
    assert!((ev - BARE).abs() < 1e-9, "5\" is not over the 6\" gate, got {ev}");
}

/// THE OLD SIDE: below the epoch the alias's charge leg prices nothing, as before.
#[test]
fn below_epoch_73_a_screened_charge_keeps_the_old_numbers() {
    let att = gunner(EPOCH_72_PLAYTEST_RULES);
    for gap in [5.0, 7.0, 10.0] {
        let ev = profile_ev(&blade(10), 10, &att, &screened(), gap, true);
        assert!((ev - BARE).abs() < 1e-9, "{gap}\" at 72: the old unconditional number, got {ev}");
    }
}
