//! SHO-01b tests (rules 3.6, lane shoot): an Indirect weapon drops the target's cover only after a
//! Hold. Blast and Ignores Cover keep dropping it at every epoch.
use super::super::*;

use crate::acts::{read_act_header, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::rules::Registries;
use crate::unit::UnitStatic;

/// A plain "Indirect when Shooting" carrier (gf/robot_legions — the entry's `cover_needs_hold`
/// sits in the gf common block) with one 24" rifle. The unit-level name stamps `indirect` on the
/// rifle at epoch 6+, so the cover fold sees a real Indirect weapon.
const COVER_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "indirect_shooter":{"unit_id":"indirect_shooter","name":"Indirect Shooter","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":["Indirect when Shooting"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":6,"count":1,"ap":0,"rules":[]}]}}}"#;

fn cover_static(epoch: u32) -> UnitStatic {
    let header = read_act_header(COVER_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get("indirect_shooter").expect("indirect_shooter");
    UnitStatic::build_for(&mut reg, p, epoch)
}

/// The save target the volley's first defense batch rolled against. Defense 4 with no Shielded
/// folds and no AP reads as 3+ when cover counts and 4+ when the shot drops it.
fn save_target_of(out: &ShootResult) -> i64 {
    out.rolls.iter().find(|r| r.kind == "defense").expect("a save batch").target
}

fn covered_defender() -> Ctx {
    Ctx { in_cover: true, ..defender(4, 5) }
}

/// A moved Indirect shooter (not Held): its target keeps its cover at epoch 73.
#[test]
fn a_moved_indirect_shooter_lets_the_target_keep_cover_at_epoch_73() {
    let us = cover_static(EPOCH_73_V36);
    assert!(us.shoot[0].indirect, "the fixture carries a real Indirect weapon");
    let moved = Ctx { held: false, ..us.ctx };
    let mut tray = Tray::seeded(27);
    let out = resolve_shooting_with_tray(
        &us.shoot, &[0], &[6], &moved, &covered_defender(), 12.0, &mut tray);
    assert_eq!(save_target_of(&out), 3, "a moved Indirect shot counts the target's cover");
    assert!(
        out.log.iter().any(|l| l.contains("cover counts") && l.contains("moved")),
        "the kept cover names itself (rules-must-log): {:?}",
        out.log
    );
    assert!(
        !out.log.iter().any(|l| l.contains("cover save is skipped")),
        "and nothing claims the cover was skipped: {:?}",
        out.log
    );
}

/// The same moved Indirect shooter at epoch 72 keeps today's behaviour: cover ignored.
#[test]
fn a_moved_indirect_shooter_ignores_cover_at_epoch_72() {
    let us = cover_static(EPOCH_72_PLAYTEST_RULES);
    let moved = Ctx { held: false, ..us.ctx };
    let mut tray = Tray::seeded(27);
    let out = resolve_shooting_with_tray(
        &us.shoot, &[0], &[6], &moved, &covered_defender(), 12.0, &mut tray);
    assert_eq!(save_target_of(&out), 4, "epoch 72 ignores cover for every Indirect shot");
    assert!(
        !out.log.iter().any(|l| l.contains("cover counts")),
        "the pre-73 leg stays silent: {:?}",
        out.log
    );
}

/// After a Hold the Indirect shot ignores cover again at epoch 73.
#[test]
fn a_held_indirect_shooter_ignores_cover_at_epoch_73() {
    let us = cover_static(EPOCH_73_V36);
    let held = Ctx { held: true, ..us.ctx };
    let mut tray = Tray::seeded(27);
    let out = resolve_shooting_with_tray(
        &us.shoot, &[0], &[6], &held, &covered_defender(), 12.0, &mut tray);
    assert_eq!(save_target_of(&out), 4, "a Hold drops the target's cover at epoch 73");
    assert!(
        !out.log.iter().any(|l| l.contains("cover counts")),
        "no kept-cover line after a Hold: {:?}",
        out.log
    );
}

/// CONTROL: Blast(3) drops cover at both epochs whether the shooter moved or held.
#[test]
fn blast_drops_cover_at_both_epochs_whether_moved_or_held() {
    let blast = ShootProfile { blast: 3, ..rifle(6) };
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        for held in [false, true] {
            let att = Ctx { held, ..shooter(4) };
            let mut tray = Tray::seeded(27);
            let out = resolve_shooting_with_tray(
                &std::slice::from_ref(&blast), &[0], &[6], &att, &covered_defender(), 12.0, &mut tray);
            assert_eq!(save_target_of(&out), 4, "Blast(3) drops cover (epoch {epoch}, held {held})");
        }
    }
}

/// CONTROL: a plain non-Indirect weapon never drops cover, at either epoch.
#[test]
fn a_plain_weapon_never_drops_cover() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        for held in [false, true] {
            let _ = epoch;
            let att = Ctx { held, ..shooter(4) };
            let mut tray = Tray::seeded(27);
            let out = resolve_shooting_with_tray(
                &[rifle(6)], &[0], &[6], &att, &covered_defender(), 12.0, &mut tray);
            assert_eq!(save_target_of(&out), 3, "a plain rifle counts cover (held {held})");
        }
    }
}
