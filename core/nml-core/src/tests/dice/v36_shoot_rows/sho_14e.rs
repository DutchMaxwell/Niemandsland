//! SHO-14e tests (rules 3.6, lane shoot): the AI's ESTIMATE twin of SHO-14. A Pierce weapon's
//! expected wounds drop the target's POSITIVE Defense modifiers (Cover, Shielded, Guarded) at
//! `EPOCH_73_V36`, while Armor and Fortified stay; below 73 the old numbers come back. The
//! over-half-range AP(+1) is pure data on the conditional-AP hook and reaches the estimate already.
use super::super::*;

use crate::acts::{read_act_header, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::combat::profile_ev;
use crate::rules::Registries;
use crate::unit::UnitStatic;

/// One unit with a 24" Pierce rifle (weapon 0) and an identical plain rifle (weapon 1).
const PIERCE_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "piercer":{"unit_id":"piercer","name":"Piercer","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":[],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Pierce Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":["Pierce"]},
      {"name":"Plain Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]}]}}}"#;

fn piercer(epoch: u32) -> UnitStatic {
    let header = read_act_header(PIERCE_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("piercer").expect("piercer");
    UnitStatic::build_for(&mut reg, p, epoch)
}

/// The estimate of weapon `keep` against `def` at `dist_in`.
fn ev(us: &UnitStatic, keep: usize, def: &Ctx, dist_in: f64) -> f64 {
    profile_ev(&us.shoot[keep], 6, &us.ctx, def, dist_in, false)
}

/// 6 Quality-4 attacks into Defense 4+ that is not otherwise modified.
fn bare() -> Ctx {
    defender(4, 5)
}

#[test]
fn a_covered_target_is_priced_at_armor_only_at_epoch_73() {
    // RED on main: the estimate still charges Cover +1 to the Pierce weapon.
    let us = piercer(EPOCH_73_V36);
    let covered = Ctx { in_cover: true, ..bare() };
    assert!((ev(&us, 0, &covered, 12.0) - ev(&us, 0, &bare(), 12.0)).abs() < 1e-9, "Pierce ignores Cover");
    // Control: the plain rifle keeps its Cover +1.
    assert!(ev(&us, 1, &covered, 12.0) < ev(&us, 1, &bare(), 12.0), "a non-Pierce weapon still pays for Cover");
}

#[test]
fn a_shielded_target_is_priced_at_armor_only_at_epoch_73() {
    // RED on main: the estimate still charges Shielded +1 to the Pierce weapon.
    let us = piercer(EPOCH_73_V36);
    let shielded = Ctx { shielded: true, ..defender(3, 5) };
    assert!((ev(&us, 0, &shielded, 12.0) - ev(&us, 0, &defender(3, 5), 12.0)).abs() < 1e-9, "Pierce ignores Shielded");
    assert!(ev(&us, 1, &shielded, 12.0) < ev(&us, 1, &defender(3, 5), 12.0), "a non-Pierce weapon still pays for Shielded");
}

#[test]
fn a_guarded_target_is_priced_at_armor_only_at_epoch_73() {
    // RED on main: the estimate still charges Guarded +1 to the Pierce weapon over 9".
    let us = piercer(EPOCH_73_V36);
    let guarded = Ctx { guarded: true, ..bare() };
    assert!((ev(&us, 0, &guarded, 12.0) - ev(&us, 0, &bare(), 12.0)).abs() < 1e-9, "Pierce ignores Guarded");
    assert!(ev(&us, 1, &guarded, 12.0) < ev(&us, 1, &bare(), 12.0), "a non-Pierce weapon still pays for Guarded");
}

#[test]
fn fortified_still_applies_to_a_pierce_weapon_at_epoch_73() {
    let us = piercer(EPOCH_73_V36);
    let fort = Ctx { fortified: true, ..bare() };
    let ap2 = ShootProfile { ap: 2, ..us.shoot[0].clone() };
    let ap1 = ShootProfile { ap: 1, ..us.shoot[0].clone() };
    let fortified = profile_ev(&ap2, 6, &us.ctx, &fort, 12.0, false);
    let plain = profile_ev(&ap1, 6, &us.ctx, &bare(), 12.0, false);
    assert!((fortified - plain).abs() < 1e-9, "Fortified takes AP(2) to AP(1); it is not a Defense modifier");
}

#[test]
fn the_old_numbers_come_back_at_epoch_72() {
    // Below 73 the Pierce flag is off, so the Pierce weapon prices exactly like the plain one.
    let us = piercer(EPOCH_72_PLAYTEST_RULES);
    for (covered, shielded, guarded) in [(true, true, true), (false, false, false)] {
        let def = Ctx { in_cover: covered, shielded, guarded, ..bare() };
        assert!((ev(&us, 0, &def, 12.0) - ev(&us, 1, &def, 12.0)).abs() < 1e-9, "72: the recorded fold stands");
    }
}

#[test]
fn the_over_half_range_ap_bonus_reaches_the_estimate_at_epoch_73() {
    // Part (b) is data: beyond half the 24" range the estimate saves at AP(+1).
    let us = piercer(EPOCH_73_V36);
    assert!((ev(&us, 0, &bare(), 18.0) - 2.0).abs() < 1e-9, "18\": AP(+1) lowers the save");
    assert!((ev(&us, 0, &bare(), 12.0) - 1.5).abs() < 1e-9, "exactly half the range is not beyond it");
}
