//! MEL-01 tests (rules 3.6, lane melee); empty until the row lands - start with `use super::super::*;`.
use super::super::*;

// MEL-01 (lead ruling D-ASSAULT, rules-must-log): the strike names an Assault weapon's melee copy (the
// profile carrying its printed range apart) every time it strikes.

fn strike_log(melee: Vec<ShootProfile>) -> Vec<String> {
    let (mut st, mut statics) = duel(0);
    statics[0].melee = melee;
    let mut shot = ShootResult::default();
    strike_phase(&statics, &mut st, 0, 1, false, 0.0, Seams::default(), &mut Tray::seeded(2), &mut shot, StrikeSet::All, Cover::Recorded(None));
    shot.log
}

#[test]
fn the_strike_names_the_assault_weapon_striking_in_melee() {
    let copy = ShootProfile { name: "Assault Pistol".into(), attacks: 6, count: 3, printed_range: 12, ..Default::default() };
    let log = strike_log(vec![copy]);
    assert!(log.iter().any(|l| l == "Assault: Assault Pistol also strikes in melee"), "{log:?}");
}

#[test]
fn a_plain_melee_weapon_logs_no_assault_line() {
    let blade = ShootProfile { name: "Blade".into(), attacks: 8, count: 1, ..Default::default() };
    let log = strike_log(vec![blade]);
    assert!(log.iter().all(|l| !l.starts_with("Assault:")), "{log:?}");
}
