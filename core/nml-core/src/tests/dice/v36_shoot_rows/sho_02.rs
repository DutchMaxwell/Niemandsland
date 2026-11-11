//! SHO-02 (rules 3.6, lane shoot): from `EPOCH_73_V36` a moved Indirect shooter hits at its base
//! quality — the 3.5 "-1 after moving" is gone, and neither its line nor the Quick Readjustment
//! opt-out line is logged. Below 73 (`EPOCH_72_PLAYTEST_RULES`) both keep the old reading.
//! The EV/twin (`profile_ev`, ai_ev.gd) never priced the moved -1; the sim file pins that it stays
//! epoch-blind.
use super::super::*;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};

/// The wave-4 fixture from `indirect_moved.rs`: a plain "Indirect when Shooting" carrier
/// (gf/robot_legions, the common `moved_hit_penalty: 1`) and a "Quick Readjustment" bearer
/// (gf/human_inquisition, `no_moved_penalty: true`), each with one 24" rifle.
const IM_HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
  "indirect_shooter":{"unit_id":"indirect_shooter","name":"Indirect Shooter","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions",
    "special_rules":["Indirect when Shooting"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]},
  "quick_readj":{"unit_id":"quick_readj","name":"Quick Readjustment","quality":4,
    "defense":3,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":0,
    "base_radius":0.016,"game_system":"gf","faction_folder":"human_inquisition",
    "special_rules":["Quick Readjustment","Indirect when Shooting"],"item_grants":[],
    "attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},
    "weapons":[{"name":"Rifle","range":24,"attacks":1,"count":1,"ap":0,"rules":[]}]}}}"#;

fn im_static(id: &str, epoch: u32) -> UnitStatic {
    let header = read_act_header(IM_HEADER).expect("header");
    let mut reg = Registries::new(&repo_root());
    let p = header.profiles.get(id).expect(id);
    UnitStatic::build_for(&mut reg, p, epoch)
}

fn volley_at(p: &ShootProfile, att: &Ctx) -> ShootResult {
    let ps = [p.clone()];
    let mut tray = Tray::seeded(27);
    resolve_shooting_with_tray(&ps, &[0], &[1], att, &defender(4, 5), 12.0, &mut tray)
}

/// NEW leg: at 73 the moved shooter hits at Quality 4+ and nothing logs the moved penalty.
#[test]
fn a_moved_indirect_shooter_hits_at_base_at_epoch_73() {
    let us = im_static("indirect_shooter", EPOCH_73_V36);
    let moved = Ctx { moved_this_round: true, ..us.ctx };
    let out = volley_at(&us.shoot[0], &moved);
    assert_eq!(out.rolls[0].target, 4, "rules 3.6: moved Indirect shoots at base Quality");
    assert!(
        !out.log.iter().any(|l| l.contains("Indirect moved")),
        "no moved line at 73: {:?}", out.log
    );
    assert!(
        out.log.iter().any(|l| l.contains("no moved penalty")),
        "the hit-info names the non-application: {:?}", out.log
    );
}

/// NEW leg: the moved shooter still takes the 3.5 -1 at 72 (the flipped old test's twin).
#[test]
fn a_moved_indirect_shooter_hits_at_minus_one_at_epoch_72() {
    let us = im_static("indirect_shooter", EPOCH_72_PLAYTEST_RULES);
    let moved = Ctx { moved_this_round: true, ..us.ctx };
    let out = volley_at(&us.shoot[0], &moved);
    assert_eq!(out.rolls[0].target, 5, "rules 3.5: Quality 4+ -> 5+");
    assert!(
        out.log.iter().any(|l| l.contains("Indirect moved -1")),
        "the applied rule names itself: {:?}", out.log
    );
}

/// NEW leg: at 73 the Quick Readjustment opt-out no longer logs its irrelevant waiver.
#[test]
fn the_quick_readjustment_opt_out_logs_nothing_at_epoch_73() {
    let us = im_static("quick_readj", EPOCH_73_V36);
    let moved = Ctx { moved_this_round: true, ..us.ctx };
    let out = volley_at(&us.shoot[0], &moved);
    assert_eq!(out.rolls[0].target, 4, "the bearer hits at base");
    assert!(
        !out.log.iter().any(|l| l.contains("Quick Readjustment")),
        "no opt-out line at 73: {:?}", out.log
    );
}

/// The opt-out still names itself at 72 (the line the 73 leg removes).
#[test]
fn the_quick_readjustment_opt_out_still_names_itself_at_epoch_72() {
    let us = im_static("quick_readj", EPOCH_72_PLAYTEST_RULES);
    let moved = Ctx { moved_this_round: true, ..us.ctx };
    let out = volley_at(&us.shoot[0], &moved);
    assert_eq!(out.rolls[0].target, 4, "the bearer ignores the 3.5 moved penalty");
    assert!(
        out.log.iter().any(|l| l.contains("Quick Readjustment")),
        "the opt-out names itself at 72: {:?}", out.log
    );
}

/// NEW leg: the table twin at 73 — the hit chance is the base composition, no moved -1.
#[test]
fn the_table_twin_has_no_moved_penalty_at_epoch_73() {
    let us = im_static("indirect_shooter", EPOCH_73_V36);
    let moved = Ctx { moved_this_round: true, ..us.ctx };
    let out = volley_at(&us.shoot[0], &moved);
    assert_eq!(
        crate::combat::success_chance(out.rolls[0].target),
        crate::combat::success_chance(modified_hit_target(4, 0)),
        "the core's moved-Indirect hit chance equals the table's composition at 73"
    );
}

/// CONTROL: a moved NON-Indirect shooter is unchanged at 73.
#[test]
fn a_moved_non_indirect_shooter_is_unchanged_at_epoch_73() {
    let us = im_static("indirect_shooter", EPOCH_73_V36);
    let mut plain = us.shoot[0].clone();
    plain.indirect = false;
    let moved = Ctx { moved_this_round: true, ..us.ctx };
    let out = volley_at(&plain, &moved);
    assert_eq!(out.rolls[0].target, 4, "only Indirect weapons ever carried the moved penalty");
    assert!(!out.log.iter().any(|l| l.contains("Indirect moved")), "log: {:?}", out.log);
}

/// CONTROL: a shooter that HELD is unchanged at 73 (and at 72).
#[test]
fn a_held_indirect_shooter_is_unchanged_at_epoch_73() {
    for epoch in [EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36] {
        let us = im_static("indirect_shooter", epoch);
        let held = Ctx { moved_this_round: false, ..us.ctx };
        let out = volley_at(&us.shoot[0], &held);
        assert_eq!(out.rolls[0].target, 4, "epoch {epoch}: no move, no penalty");
        assert!(!out.log.iter().any(|l| l.contains("Indirect moved")), "log: {:?}", out.log);
    }
}
