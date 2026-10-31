//! Rules 3.6 row UX-14 tests (Vanguard gap to enemies) for the deployment module; owned by lane ux.
//!
//! From `EPOCH_73_V36` on a Vanguard re-placement is only legal more than 9" (base edge to edge)
//! from every placed enemy unit that does not itself have Vanguard. Below 73 nothing changes. The
//! free placement only moves when a legal spot is strictly nearer the nearest objective, so the
//! fixtures put the objective beyond the enemy and pin the gap the unit actually ends on.

use super::empty_board;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::deployment::{
    deploy_footprint_radius, deploy_interleaved_gated, deploy_place_id_gated, deploy_side_gated,
    ModelShape, Occupied, Rect, UnitSpec,
};

const PUSH_M: f64 = 9.0 * 0.0254;
const BASE_R: f64 = 0.016;

fn vanguard_spec(key: &str) -> UnitSpec {
    UnitSpec {
        key: key.into(),
        model_count: 1,
        base_r_m: BASE_R,
        footprint: vec![(0.0, 0.0)],
        vanguard: true,
        model_shapes: vec![ModelShape { is_oval: false, w_mm: 32, d_mm: 32, tough: 1, n: 1 }],
        ..Default::default()
    }
}

fn plain_spec(key: &str) -> UnitSpec {
    UnitSpec { vanguard: false, ..vanguard_spec(key) }
}

/// Round-base edge gap in inches, the table's f32 centre law.
fn round_gap_in(p: (f64, f64), enemy: &[Occupied]) -> f64 {
    enemy
        .iter()
        .map(|e| {
            let dx = (p.0 as f32 - e.pos.0 as f32) as f64;
            let dy = (p.1 as f32 - e.pos.1 as f32) as f64;
            ((dx * dx + dy * dy).sqrt() - BASE_R - e.radius) / 0.0254
        })
        .fold(f64::INFINITY, f64::min)
}

/// Side 1's 1 ft deep band along the -Z edge; its forward edge is y = -0.3.
fn zone() -> Rect {
    Rect::new(-0.55, -0.6, 1.1, 0.30)
}

/// One Vanguard placement against an explicit enemy list; returns the gap.
fn gap_at(epoch: u32, enemy: &[Occupied]) -> f64 {
    let board = empty_board();
    let zone = zone();
    let forward_y = zone.end().1;
    let radius = deploy_footprint_radius(1, BASE_R);
    let mut occupied = Vec::new();
    let out = deploy_place_id_gated(
        &zone,
        &zone,
        forward_y,
        &[(0.0, 0.10)],
        &mut occupied,
        &board,
        &[],
        radius,
        &[(0.0, 0.0)],
        BASE_R,
        false,
        true,
        PUSH_M,
        epoch,
        None,
        None,
        enemy,
    );
    round_gap_in(out.spot, enemy)
}

#[test]
fn a_vanguard_spot_six_inches_from_a_non_vanguard_enemy_is_taken_at_epoch_72() {
    let enemy = vec![Occupied { pos: (0.0, 0.05), radius: BASE_R }];
    let gap = gap_at(EPOCH_72_PLAYTEST_RULES, &enemy);
    assert!(gap < 7.5, "below 3.6 the close spot is legal and taken, got {gap:.2}\"");
}

#[test]
fn a_vanguard_spot_six_inches_from_a_non_vanguard_enemy_is_refused_at_epoch_73() {
    let enemy = vec![Occupied { pos: (0.0, 0.05), radius: BASE_R }];
    let gap = gap_at(EPOCH_73_V36, &enemy);
    assert!(gap > 9.0, "a 3.6 Vanguard must end more than 9\" from a non-Vanguard enemy, got {gap:.2}\"");
}

#[test]
fn a_joined_hero_model_counts_at_epoch_73() {
    // The host stands far behind; the hero's base is the one 6" from the close spot.
    let enemy = vec![
        Occupied { pos: (0.0, 0.6), radius: BASE_R },
        Occupied { pos: (0.0, 0.05), radius: BASE_R },
    ];
    let gap = gap_at(EPOCH_73_V36, &enemy);
    assert!(gap > 9.0, "the joined hero's model counts, got {gap:.2}\"");
}

/// Two one-unit sides at the table centre: the enemy unit stands exactly on the objective, so its
/// free placement barely moves. Our Vanguard replaces itself toward that objective second. When
/// the enemy has Vanguard it does not count (our unit may end close); when it does not, the gap
/// pushes our unit back.
fn interleaved_gap(epoch: u32, enemy_vanguard: bool) -> f64 {
    let board = empty_board();
    let ours_zone = Rect::new(-0.05, -0.35, 0.10, 0.30);
    let enemy_zone = Rect::new(-0.05, 0.05, 0.10, 0.30);
    let ours = vanguard_spec("ours");
    let enemy_spec = if enemy_vanguard { vanguard_spec("enemy") } else { plain_spec("enemy") };
    let out = deploy_interleaved_gated(
        &[ours],
        &[enemy_spec],
        &ours_zone,
        &enemy_zone,
        [None, None],
        [None, None],
        &[(0.0, 0.07)],
        &board,
        7,
        11,
        2,
        epoch,
    );
    let our_spot = out.side1.placements[0].spot;
    let enemy_spot = out.side2.placements[0].spot;
    let enemy = vec![Occupied { pos: enemy_spot, radius: BASE_R }];
    round_gap_in(our_spot, &enemy)
}

#[test]
fn an_enemy_vanguard_does_not_count_at_epoch_73() {
    let with_vanguard = interleaved_gap(EPOCH_73_V36, true);
    let without_vanguard = interleaved_gap(EPOCH_73_V36, false);
    assert!(with_vanguard < 9.0, "an enemy Vanguard does not close the gap, got {with_vanguard:.2}\"");
    assert!(
        without_vanguard > 9.0,
        "a non-Vanguard enemy closes the gap, got {without_vanguard:.2}\""
    );
}

/// The decision record names the 9" gap at 73 and keeps the old free-placement words at 72.
fn decide_rule_at(epoch: u32) -> String {
    let board = empty_board();
    let zone = Rect::new(-0.55, -0.35, 1.1, 0.30);
    let sd = deploy_side_gated(
        &[vanguard_spec("vanguard")],
        &zone,
        None,
        None,
        &[],
        &[(0.0, 5.0)],
        &board,
        7,
        epoch,
    );
    let ev = sd.events.iter().find(|e| e.why == "vanguard free placement").expect("the free placement moved");
    ev.rule.clone()
}

#[test]
fn the_decision_record_names_the_nine_inch_gap_at_epoch_73() {
    let rule = decide_rule_at(EPOCH_73_V36);
    assert!(rule.contains("do not have Vanguard"), "the 3.6 Vanguard line must name the gap, got: {rule}");
}

#[test]
fn the_decision_record_keeps_the_free_placement_words_at_epoch_72() {
    let rule = decide_rule_at(EPOCH_72_PLAYTEST_RULES);
    assert!(!rule.contains("do not have Vanguard"), "below 3.6 the old words stay, got: {rule}");
}
