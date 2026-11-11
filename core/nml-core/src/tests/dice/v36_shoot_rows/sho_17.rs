//! SHO-17 tests (rules 3.6, lane shoot): the Guarded family (Guarded, Versatile Defense,
//! Sturdy) raises the charged side's save by 1 only when the charge started over 6" away
//! from `EPOCH_73_V36` on; below it the old over-9" reading stays. The shot leg keeps its
//! shared over-9" gate at every epoch.
use super::super::*;

/// The engine's own melee threshold: 6.0 from `EPOCH_73_V36`, 0.0 (the old over-9" read)
/// below it. `sim::ctx_live` / `sim::ctx_of_melee` stamp it on the defender's context.
const SIX_IN: f64 = 6.0;
const OLD_READ: f64 = 0.0;

fn guarded(defense: i64, charge_gate_in: f64) -> Ctx {
    Ctx {
        guarded: true,
        guarded_name: "Guarded",
        guarded_charge_over_in: charge_gate_in,
        ..defender(defense, 10)
    }
}

/// The target of the first defense batch — the number the save is really rolled on.
fn save_target(r: &ShootResult) -> i64 {
    r.rolls.iter().find(|x| x.kind == "defense").map(|x| x.target).unwrap_or(-1)
}

fn melee_charge(gap_in: f64, charge_gate_in: f64, exact: bool) -> ShootResult {
    let att = Ctx { quality: 2, ..Default::default() };
    let blade = [blade(20)];
    resolve_melee_leg(
        &[striker(&blade, &[0], &[20], &att)],
        &guarded(4, charge_gate_in),
        "Target",
        true,
        true,
        true,
        true,
        gap_in,
        false,
        exact,
        false,
        false,
        false,
        &mut Tray::seeded(3),
    )
}

fn volley_at(d_in: f64) -> ShootResult {
    let rifle = [rifle(20)];
    resolve_volley_with_tray(
        &[Shooter { profiles: &rifle, keep: &[0], attacks: &[20], att: &shooter(2), owner: "Striker" }],
        &guarded(4, SIX_IN),
        "Target",
        d_in,
        d_in,
        true,
        true,
        true,
        true,
        &mut Tray::seeded(3),
    )
}

/// RED on main: a Guarded defender charged from 7" gets the +1 at rules 3.6, because the
/// charge leg reads the shared 6" gate.
#[test]
fn a_guarded_defender_charged_from_seven_inches_saves_one_better_at_epoch_73() {
    let r = melee_charge(7.0, SIX_IN, true);
    assert!(r.rolls.iter().any(|x| x.kind == "defense"), "fixture: the strike must reach the saves: {:?}", r.rolls);
    assert_eq!(save_target(&r), 3, "charged from over 6\": 4+ becomes 3+: {:?}", r.log);
}

/// RED on main: the applied gate names the rule and its six-inch band.
#[test]
fn the_applied_charge_gate_names_the_rule_and_the_six_inch_band() {
    let r = melee_charge(7.0, SIX_IN, true);
    assert!(
        r.log.iter().any(|l| l.contains("Guarded") && l.contains("over 6")),
        "rules-must-log: the gate line names Guarded and the 6\" band: {:?}",
        r.log
    );
}

/// A charge from 5" lies inside the gate: the save stays at the bare Defense.
#[test]
fn a_guarded_defender_charged_from_five_inches_keeps_its_save() {
    assert_eq!(save_target(&melee_charge(5.0, SIX_IN, true)), 4);
}

/// THE OLD SIDE: below the epoch the charge leg still needs over 9", so 7" changes nothing.
#[test]
fn below_epoch_73_a_charge_from_seven_inches_keeps_its_save() {
    assert_eq!(save_target(&melee_charge(7.0, OLD_READ, true)), 4);
}

/// THE OLD SIDE, control: over 9" the old reading still pays the +1.
#[test]
fn below_epoch_73_a_charge_from_over_nine_inches_still_saves_one_better() {
    assert_eq!(save_target(&melee_charge(10.0, OLD_READ, true)), 3);
}

/// The shot leg is untouched: 7" earns nothing, over 9" earns the +1, at every epoch.
#[test]
fn a_guarded_target_shot_from_seven_inches_gets_no_bonus() {
    assert_eq!(save_target(&volley_at(7.0)), 4);
}

#[test]
fn a_guarded_target_shot_from_over_nine_inches_gets_the_bonus() {
    assert_eq!(save_target(&volley_at(10.0)), 3);
}

/// Impact is a charge leg too: the same 6" gate raises the pool's save.
#[test]
fn guarded_impact_from_seven_inches_saves_one_better_at_epoch_73() {
    let r = resolve_impact_pool_at(
        20, 0, "Charger", &guarded(4, SIX_IN), "Target", Some((7.0, false)), &mut Tray::seeded(3),
    );
    assert_eq!(save_target(&r), 3, "Impact charged from over 6\": {:?}", r.log);
}

#[test]
fn guarded_impact_from_five_inches_keeps_its_save() {
    let r = resolve_impact_pool_at(
        20, 0, "Charger", &guarded(4, SIX_IN), "Target", Some((5.0, false)), &mut Tray::seeded(3),
    );
    assert_eq!(save_target(&r), 4);
}
