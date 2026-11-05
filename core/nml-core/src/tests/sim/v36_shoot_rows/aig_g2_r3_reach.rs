//! AIG-G2 row R3, fault 2 (rules 3.6): the move-through volley of a Crossing Strike weapon has no range gate.
use super::super::*;

use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::rules::Registries;

// The weapon's target is the unit the bearer moved through, so its printed range does not apply to that
// volley. A range-0 weapon (Drop Bombs) used to roll nothing; the advance below flies over the enemy
// and ends 7" past it.

/// The carrier's REAL profile through the import's stamp: one Crossing Strike weapon of the given range.
fn bomber_at(epoch: u32, range: f64) -> UnitStatic {
    let json = format!(
        r#"{{"unit_id": "a", "name": "Strafer", "model_count": 1, "quality": 4, "defense": 4, "tough": 1,
            "weapons": [{{"name": "Drop Bombs", "range": {range}, "attacks": 4, "count": 1,
                          "rules": ["Crossing Strike"]}}]}}"#
    );
    let p: Profile = serde_json::from_str(&json).expect("the bomber's profile parses");
    let mut reg = Registries::new(&format!("{}/../..", env!("CARGO_MANIFEST_DIR")));
    UnitStatic::build_for(&mut reg, &p, epoch)
}

/// Fly the 12" advance over the enemy parked on the lane; returns the carrier's rolls and the log.
fn fly_over(epoch: u32, range: f64) -> (Vec<String>, Vec<String>) {
    let (st, mut statics) = super::super::strafing::strafe_line();
    statics[0] = bomber_at(epoch, range);
    let mut tray = Tray::seeded(1);
    let mut rng = crate::rng::GodotRng::new(0);
    let (_next, shot) = resolve_stochastic_tray_on_board(
        &statics, &st, &advance_to(12.0), &crate::terrain::Terrain::default(),
        Seams { rules_epoch: epoch, ..Seams::default() }, &mut rng, &mut tray,
    )
    .unwrap();
    let owners = shot.rolls.iter().filter(|r| r.owner == "Strafer").map(|r| r.owner.clone()).collect();
    (owners, shot.log)
}

#[test]
fn a_range_zero_crossing_strike_weapon_rolls_on_the_move_through_at_epoch_73() {
    let (rolls, log) = fly_over(EPOCH_73_V36, 0.0);
    assert!(log.iter().any(|l| l.starts_with("Crossing Strike: Strafer passes over")), "the trigger names the rule: {log:?}");
    assert!(!rolls.is_empty(), "the volley at the crossed unit rolled nothing: {log:?}");
}

/// Below the gate the old reading replays byte for byte: the trigger fires and the volley stays silent.
#[test]
fn a_range_zero_crossing_strike_weapon_stays_silent_at_epoch_72() {
    let (rolls, log) = fly_over(EPOCH_72_PLAYTEST_RULES, 0.0);
    assert!(log.iter().any(|l| l.starts_with("Crossing Strike: Strafer passes over")), "{log:?}");
    assert!(rolls.is_empty(), "epoch 72 keeps the reach gate: {rolls:?}");
}

/// Control: a weapon with a printed range keeps rolling at both epochs.
#[test]
fn a_ranged_crossing_strike_weapon_rolls_at_both_epochs() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        let (rolls, log) = fly_over(epoch, 24.0);
        assert!(!rolls.is_empty(), "epoch {epoch}: {log:?}");
    }
}
