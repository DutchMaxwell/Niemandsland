//! Rules 3.6 row UX-13 tests (Scout gap to enemies) for the deployment module; owned by lane ux.
//!
//! From `EPOCH_73_V36` on a Scout spot is only legal more than 9" (base edge to base edge) from
//! every placed enemy unit that is not itself a Scout. Below 73 nothing changes. All cases use a
//! single 32 mm scout on an empty board; the enemy stands beyond the scout band, so only the gap
//! rule can move the spot.

use super::empty_board;
use crate::acts::{EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::deployment::{deploy_phased, deploy_side_gated, ModelShape, Occupied, Rect, UnitSpec};

/// Side 1's 12"-deep zone along the -Z table edge; its forward edge is y = -0.3048.
fn scout_zone() -> Rect {
    Rect::new(-0.9144, -0.6096, 1.8288, 0.3048)
}

/// Side 2's mirror zone along the +Z table edge.
fn opposite_zone() -> Rect {
    Rect::new(-0.9144, 0.3048, 1.8288, 0.3048)
}

/// One single-model scout on a 32 mm round base.
fn scout_specs() -> Vec<UnitSpec> {
    vec![UnitSpec {
        key: "scouts".into(),
        model_count: 1,
        base_r_m: 0.016,
        footprint: vec![(0.0, 0.0)],
        scout: true,
        model_shapes: vec![ModelShape { is_oval: false, w_mm: 32, d_mm: 32, tough: 1, n: 1 }],
        ..Default::default()
    }]
}

/// The objective sits inside both the 9" and the 12" band, so the scout's objective-nearest spot
/// is the same row at either epoch; the enemy beyond the band is what the 3.6 rule adds.
const OBJECTIVE: (f64, f64) = (0.0, -0.09);

/// A 32 mm enemy model whose edge stands 8" from that spot.
fn enemy_eight_inches_away() -> Vec<Occupied> {
    vec![Occupied { pos: (0.0, 0.1416), radius: 0.016 }]
}

/// Round-base edge gap in inches, the table's f32 centre law.
fn round_gap_in(p: (f64, f64), enemy: &[Occupied]) -> f64 {
    enemy
        .iter()
        .map(|e| {
            let dx = (p.0 as f32 - e.pos.0 as f32) as f64;
            let dy = (p.1 as f32 - e.pos.1 as f32) as f64;
            ((dx * dx + dy * dy).sqrt() - 0.016 - e.radius) / 0.0254
        })
        .fold(f64::INFINITY, f64::min)
}

/// The gap of a side's only scout to `enemy`, in inches.
fn gap_at(epoch: u32, enemy: &[Occupied]) -> f64 {
    let sd = deploy_side_gated(
        &scout_specs(),
        &scout_zone(),
        None,
        None,
        enemy,
        &[OBJECTIVE],
        &empty_board(),
        7,
        epoch,
    );
    assert_eq!(sd.placements.len(), 1, "the scout deploys: {sd:?}");
    round_gap_in(sd.placements[0].spot, enemy)
}

#[test]
fn scout_gap_to_a_non_scout_enemy_is_ignored_at_epoch_72() {
    let gap = gap_at(EPOCH_72_PLAYTEST_RULES, &enemy_eight_inches_away());
    assert!((gap - 8.0).abs() < 0.5, "below 3.6 the 8\" spot is legal and taken, got {gap:.2}\"");
}

#[test]
fn scout_gap_to_a_non_scout_enemy_is_refused_at_epoch_73() {
    let gap = gap_at(EPOCH_73_V36, &enemy_eight_inches_away());
    assert!(gap > 9.0, "a 3.6 scout must end more than 9\" from a non-Scout enemy, got {gap:.2}\"");
}

#[test]
fn a_joined_hero_model_counts_at_epoch_73() {
    // The host stands far away; the hero's base is the one 8" from the scout's spot. A joined
    // unit counts with all its models.
    let enemy = vec![
        Occupied { pos: (0.0, 0.6), radius: 0.016 },
        Occupied { pos: (0.0, 0.1416), radius: 0.016 },
    ];
    let gap = gap_at(EPOCH_73_V36, &enemy);
    assert!(gap > 9.0, "the joined hero's model counts, got {gap:.2}\"");
}

/// Two scout-only sides at the table centre: an enemy SCOUT does not close the gap, so both
/// scouts may stand within 9" of each other at 73. Also pins the scout-phase order: it starts
/// with `first`, the roll-off winner who also takes round 1's first turn.
#[test]
fn enemy_scouts_do_not_count_and_the_scout_phase_starts_with_first_at_epoch_73() {
    let out = deploy_phased(
        &scout_specs(),
        &scout_specs(),
        &scout_zone(),
        &opposite_zone(),
        &[],
        [None, None],
        &[(0.0, 0.0)],
        &empty_board(),
        7,
        11,
        2,
        EPOCH_73_V36,
    );
    assert_eq!(out.sequence.len(), 2, "both scouts deploy: {out:?}");
    assert_eq!(out.sequence[0].0, 2, "the scout phase starts with `first`, got {:?}", out.sequence);
    assert_eq!(out.sequence[1].0, 1, "scouts alternate, got {:?}", out.sequence);
    let a = out.side1.placements[0].spot;
    let b = out.side2.placements[0].spot;
    let gap = ((a.0 - b.0).powi(2) + (a.1 - b.1).powi(2)).sqrt() - 0.032;
    assert!(gap < 9.0 * 0.0254, "an enemy Scout does not count, got {:.2}\"", gap / 0.0254);
}
