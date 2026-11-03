//! FAB-A3 tests (rules 3.6, lane shoot): the Indirect entry lifts cover granted by SIGHT BLOCKERS
//! only. The engine grants Cover terrain and nothing else, so from epoch 73 a Held Indirect shot
//! keeps the target's Cover +1 too. Below 73 the unconditional skip stays byte-identical, and
//! Blast / Ignores Cover keep dropping cover at every epoch.
use super::super::*;

use crate::acts::{read_act_header, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::rules::Registries;
use crate::unit::UnitStatic;

/// The same plain "Indirect when Shooting" carrier SHO-01b uses (gf/robot_legions): the entry's
/// `cover_needs_hold` sits in the gf common block, and the unit-level name stamps `indirect` on
/// the rifle at epoch 6+, so the cover fold sees a real Indirect weapon.
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

/// RED: a HELD Indirect shooter at epoch 73 saves the target WITH its cover — the engine has no
/// sight-blocker cover to ignore, so the Hold no longer drops terrain cover.
#[test]
fn a_held_indirect_shooter_keeps_cover_at_epoch_73() {
    let us = cover_static(EPOCH_73_V36);
    assert!(us.shoot[0].indirect, "the fixture carries a real Indirect weapon");
    let held = Ctx { held: true, ..us.ctx };
    let mut tray = Tray::seeded(27);
    let out = resolve_shooting_with_tray(
        &us.shoot, &[0], &[6], &held, &covered_defender(), 12.0, &mut tray);
    assert_eq!(save_target_of(&out), 3, "a held Indirect shot counts the target's terrain cover");
    assert!(
        out.log.iter().any(|l| l.contains("cover counts")),
        "the kept cover names itself (rules-must-log): {:?}",
        out.log
    );
}

/// The mirror control: the same HELD Indirect shooter below 73 keeps today's unconditional skip.
#[test]
fn a_held_indirect_shooter_ignores_cover_at_epoch_72() {
    let us = cover_static(EPOCH_72_PLAYTEST_RULES);
    let held = Ctx { held: true, ..us.ctx };
    let mut tray = Tray::seeded(27);
    let out = resolve_shooting_with_tray(
        &us.shoot, &[0], &[6], &held, &covered_defender(), 12.0, &mut tray);
    assert_eq!(save_target_of(&out), 4, "epoch 72 ignores cover for every Indirect shot");
    assert!(
        !out.log.iter().any(|l| l.contains("cover counts")),
        "the pre-73 leg stays silent: {:?}",
        out.log
    );
}

/// CONTROL: Blast(3) and Ignores Cover drop cover at both epochs, held or moved.
#[test]
fn blast_and_ignores_cover_drop_cover_at_both_epochs() {
    let profiles = [
        ShootProfile { name: "Blast".into(), blast: 3, ..rifle(6) },
        ShootProfile { name: "Ignores Cover".into(), ignores_cover: true, ..rifle(6) },
    ];
    for p in &profiles {
        for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
            for held in [false, true] {
                let att = Ctx { held, ..shooter(4) };
                let mut tray = Tray::seeded(27);
                let out = resolve_shooting_with_tray(
                    std::slice::from_ref(p), &[0], &[6], &att, &covered_defender(), 12.0, &mut tray);
                assert_eq!(
                    save_target_of(&out), 4,
                    "{} drops cover (epoch {epoch}, held {held})", p.name);
            }
        }
    }
}
