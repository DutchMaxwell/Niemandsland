//! Rules 3.6 lane shoot tests for the dice module; owned by lane shoot.
use super::*;
use crate::unit::CondAp;

// ------------- Rules 3.6 conditional-AP target hook: `over_half_range` and
// `def_5_6`, the first two 3.6 condition spellings the weapon-family data rows
// will use. No shipped 3.5 entry spells either name, so the hook carries no
// epoch gate: the `_at_epoch_72` tests pin what every existing condition and
// shipped entry answers (unchanged), the `_at_epoch_73` tests the new answers.
// RED before the hook: an unknown condition answered 0, so every 3.6 leg
// below saved at the plain Defense.

/// A 24" rifle carrying ONE conditional-AP entry spelled `condition`, AP(+1).
/// The name makes the volley's rules-must-log line fire.
fn cond_rifle(condition: &str) -> ShootProfile {
    let c = CondAp { ap_bonus: 1, condition: condition.into(), name: "Probe Gun".into(), ..Default::default() };
    ShootProfile { cond_ap: vec![c], ..rifle(8) }
}

/// One seeded volley of `p` at `d` inches against `def`, the shipped knob pack.
fn volley_at(p: &ShootProfile, def: &Ctx, d: f64) -> ShootResult {
    let ps = [p.clone()];
    let mut tray = Tray::seeded(27);
    resolve_volley_with_tray(&[striker(&ps, &[0], &[8], &shooter(4))], def, "Target", d, d, true, true, true, false, &mut tray)
}

#[test]
fn over_half_range_raises_the_save_ap_only_beyond_half_the_weapon_range_at_epoch_73() {
    let p = cond_rifle("over_half_range");
    assert_eq!(volley_at(&p, &defender(4, 5), 18.0).rolls[1].target, 5, "18\" > 12\": AP(+1), Defense 4+ -> 5+");
    assert_eq!(volley_at(&p, &defender(4, 5), 12.0).rolls[1].target, 4, "exactly half the range is not beyond it");
    assert_eq!(volley_at(&p, &defender(4, 5), 6.0).rolls[1].target, 4, "inside half the range: no bonus");
}

#[test]
fn def_5_6_raises_the_save_ap_only_against_a_5_plus_or_6_plus_target_at_epoch_73() {
    let p = cond_rifle("def_5_6");
    assert_eq!(volley_at(&p, &defender(5, 5), 6.0).rolls[1].target, 6, "Defense 5+ target: AP(+1) -> 6+");
    assert_eq!(volley_at(&p, &defender(4, 5), 6.0).rolls[1].target, 4, "Defense 4+ target: no bonus");
}

/// The melee leg reaches the same hook with the target's Defense: `def_5_6`
/// is a target property, so a blade carrying it pays in melee too, and
/// `over_half_range` (shooting only) never does.
#[test]
fn def_5_6_pays_in_melee_and_over_half_range_never_does_at_epoch_73() {
    let strike = |cond: &str, def: &Ctx| {
        let c = CondAp { ap_bonus: 1, condition: cond.into(), ..Default::default() };
        let p = [ShootProfile { cond_ap: vec![c], ..blade(6) }];
        let mut tray = Tray::seeded(27);
        resolve_melee_with_tray(&[striker(&p, &[0], &[6], &shooter(4))], def, "Target", false, true, true, &mut tray)
            .rolls[1]
            .target
    };
    assert_eq!(strike("def_5_6", &defender(5, 5)), 6, "Defense 5+ target in melee: AP(+1) -> 6+");
    assert_eq!(strike("def_5_6", &defender(4, 5)), 4);
    assert_eq!(strike("over_half_range", &defender(4, 5)), 4, "a melee strike has no range to measure");
}

/// Rules-must-log: the volley's conditional-AP line names the rule AND the
/// 3.6 condition that fired.
#[test]
fn the_volley_log_names_the_condition_that_fired_at_epoch_73() {
    let r = volley_at(&cond_rifle("over_half_range"), &defender(4, 5), 18.0);
    assert!(
        r.log.iter().any(|l| l == "Probe Gun: AP(+1) on Striker's volley (target beyond half the weapon's range)"),
        "log: {:?}", r.log
    );
    let r = volley_at(&cond_rifle("def_5_6"), &defender(5, 5), 6.0);
    assert!(r.log.iter().any(|l| l == "Probe Gun: AP(+1) on Striker's volley (target defends on 5+ or 6+)"), "log: {:?}", r.log);
}

/// The EV twin (`profile_ev`) prices the same hook: beyond half the range the
/// shot is worth more, inside it nothing moves.
#[test]
fn over_half_range_moves_the_ev_only_beyond_half_the_weapon_range_at_epoch_73() {
    let armed = cond_rifle("over_half_range");
    let plain = rifle(8);
    let ev = |p: &ShootProfile, d: f64| crate::combat::profile_ev(p, 8, &shooter(4), &defender(4, 5), d, false);
    assert!(ev(&armed, 18.0) > ev(&plain, 18.0), "18\": the AP(+1) must lower the save");
    assert_eq!(ev(&armed, 12.0), ev(&plain, 12.0));
    assert_eq!(ev(&armed, 6.0), ev(&plain, 6.0));
    let d56 = cond_rifle("def_5_6");
    let ev_vs = |p: &ShootProfile, def: i64| crate::combat::profile_ev(p, 8, &shooter(4), &defender(def, 5), 6.0, false);
    assert!(ev_vs(&d56, 5) > ev_vs(&plain, 5));
    assert_eq!(ev_vs(&d56, 4), ev_vs(&plain, 4));
}

/// Control: every condition that exists before the hook answers exactly as
/// before, through the volley and the six-argument function alike.
#[test]
fn existing_conditions_answer_unchanged_at_epoch_72() {
    let spec = |cond: &str, threshold: i64| CondAp { ap_bonus: 2, condition: cond.into(), threshold, over_in: 9.0, within_in: 12.0, ..Default::default() };
    assert_eq!(conditional_ap_bonus(&spec("vs_tough_ge", 3), 3, 4, false, 0.0, true), 2);
    assert_eq!(conditional_ap_bonus(&spec("vs_tough_ge", 3), 2, 4, false, 0.0, true), 0);
    assert_eq!(conditional_ap_bonus(&spec("vs_armor", 3), 1, 3, false, 0.0, true), 2);
    assert_eq!(conditional_ap_bonus(&spec("vs_armor", 3), 1, 5, false, 0.0, true), 0);
    assert_eq!(conditional_ap_bonus(&spec("ranged_over", 0), 1, 5, false, 12.0, false), 2);
    assert_eq!(conditional_ap_bonus(&spec("ranged_within", 0), 1, 5, false, 12.0, false), 2);
    assert_eq!(conditional_ap_bonus(&spec("on_charge", 0), 1, 5, true, 0.0, true), 2);
    assert_eq!(conditional_ap_bonus(&spec("on_charge", 0), 1, 5, false, 0.0, true), 0);
    let over9 = ShootProfile { cond_ap: vec![spec("ranged_over", 0)], ..rifle(8) };
    assert_eq!(volley_at(&over9, &defender(4, 5), 12.0).rolls[1].target, 6, "ranged_over past 9\": AP(+2)");
    assert_eq!(volley_at(&over9, &defender(4, 5), 6.0).rolls[1].target, 4);
}
