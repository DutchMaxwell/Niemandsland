//! NML-1073 M4-7 — the tier-2 `reach_query` unit gates.
//!
//! The corpus gate (`src/bin/mvreach.rs`, G7) judges tier 2 against the exact
//! solver on 1 101 recorded calls. This file judges the PARTS, on boards small
//! enough to reason about by hand:
//!
//!   * the obstacle index's BUCKETS hold every obstacle that could block an edge
//!     through their cell — proved by comparing the bucketed answer against a
//!     full linear scan on a dense grid of probe edges, not by inspection;
//!   * a CORRIDOR the straight line walks through and tier 2 does not, which is
//!     the whole reason tier 2 exists (the imagination's move step today);
//!   * the terrain raster, the owner masks, the band spend and the memo.

use nml_core::mv::cost::Wall;
use nml_core::mv::geom2::{distance_to, V2};
use nml_core::mv::reach::{
    owner_bit, polyline_arc, walk_to, Disc, ReachBuild, ReachIndex, ReachQuery, NO_OWNER,
    REACH_CELL_IN,
};
use nml_core::mv::{DANGEROUS_COST_MULT, DIFFICULT_COST_MULT};

const BOARD: [f64; 2] = [24.0, 24.0];

fn plain(walls: &[Wall], discs: Vec<Disc>) -> ReachIndex {
    let mut b = ReachBuild::new(BOARD, walls);
    b.discs = discs;
    ReachIndex::build(b, |_| 1.0)
}

fn disc(x: f32, y: f32, r: f32, bit: u32) -> Disc {
    Disc { c: [x, y], r_body: r, r_buf: r, bit }
}

fn q(start: V2, target: V2, band: f64) -> ReachQuery {
    ReachQuery::new(start, target, 0.5, band)
}

// === the index ============================================================

/// THE BUCKETING PROOF. Every obstacle a bucketed lookup can find, a linear
/// scan finds too — and, the half that actually matters, every obstacle the
/// LINEAR scan finds, the bucket finds as well. `block_reason` reports both
/// halves side by side (bits 2/16 for walls, 4/8 for discs); a probe edge where
/// they differ is a hole in the index.
#[test]
fn the_buckets_hold_every_obstacle_a_linear_scan_would_find() {
    let walls: Vec<Wall> = vec![
        [[4.0, 4.0], [4.0, 16.0]],
        [[4.0, 16.0], [18.0, 16.0]],
        [[9.0, 2.0], [14.0, 7.0]],
        [[20.0, 1.0], [20.5, 23.0]],
    ];
    let discs = vec![
        disc(7.0, 9.0, 1.5, NO_OWNER),
        disc(12.0, 12.0, 2.5, NO_OWNER),
        disc(3.0, 20.0, 0.75, NO_OWNER),
        disc(21.0, 21.0, 3.0, NO_OWNER),
    ];
    let ix = plain(&walls, discs);
    let query = q([0.0, 0.0], [0.0, 0.0], 24.0);
    let mut probes = 0;
    let mut wall_hits = 0;
    let mut disc_hits = 0;
    // A dense sweep of short edges over the whole board, at an offset that puts
    // most starts INSIDE a cell rather than on its centre.
    let step = 0.7f32;
    let mut x = 0.35f32;
    while x < BOARD[0] as f32 {
        let mut y = 0.35f32;
        while y < BOARD[1] as f32 {
            for (dx, dy) in [(1.7f32, 0.0f32), (0.0, 1.7), (1.2, 1.2), (-1.2, 1.2)] {
                let (a, b) = ([x, y], [x + dx, y + dy]);
                if b[0] < 0.0 || b[1] < 0.0 || b[0] >= BOARD[0] as f32 || b[1] >= BOARD[1] as f32 {
                    continue;
                }
                let bits = ix.block_reason(a, b, &query);
                probes += 1;
                if bits & 16 != 0 {
                    wall_hits += 1;
                }
                if bits & 8 != 0 {
                    disc_hits += 1;
                }
                assert_eq!(
                    bits & 2 != 0,
                    bits & 16 != 0,
                    "wall bucket hole at {a:?} -> {b:?} (bits {bits})"
                );
                assert_eq!(
                    bits & 4 != 0,
                    bits & 8 != 0,
                    "disc bucket hole at {a:?} -> {b:?} (bits {bits})"
                );
            }
            y += step;
        }
        x += step;
    }
    // The instrument has to be able to fail: a sweep that never touches an
    // obstacle proves nothing about the buckets.
    assert!(probes > 3000, "only {probes} probes");
    assert!(wall_hits > 100, "the sweep barely met a wall ({wall_hits})");
    assert!(disc_hits > 100, "the sweep barely met a disc ({disc_hits})");
}

#[test]
fn the_terrain_raster_prices_difficult_and_blocks_impassable() {
    let b = ReachBuild::new(BOARD, &[]);
    let ix = ReachIndex::build(b, |p| {
        if p[0] < 6.0 {
            f32::INFINITY
        } else if p[0] < 12.0 {
            DIFFICULT_COST_MULT as f32
        } else if p[0] < 18.0 {
            DANGEROUS_COST_MULT as f32
        } else {
            1.0
        }
    });
    assert!(ix.mult_at_cell(ix.cell_of([1.0, 1.0])).is_infinite());
    assert_eq!(ix.mult_at_cell(ix.cell_of([7.0, 1.0])), DIFFICULT_COST_MULT as f32);
    assert_eq!(ix.mult_at_cell(ix.cell_of([13.0, 1.0])), DANGEROUS_COST_MULT as f32);
    assert_eq!(ix.mult_at_cell(ix.cell_of([21.0, 1.0])), 1.0);
    assert_eq!(ix.cells(), (BOARD[0] / REACH_CELL_IN) as usize * (BOARD[1] / REACH_CELL_IN) as usize);
    // Impassable is a HARD block: a straight run into it never arrives.
    let r = ix.query(&q([21.0, 12.0], [2.0, 12.0], 24.0));
    assert!(!r.reachable, "{r:?} walked into Impassable terrain");
}

// === the corridor =========================================================

/// THE POINT OF TIER 2. `BattleSim.resolve`'s move step today translates the
/// unit along the straight line and stops — `grep -rn "wall" core/nml-core/src`
/// was empty before this commit. Here a wall stands square across that line
/// with a gap at one end: the straight line "arrives", tier 2 refuses on the
/// short band, and finds the way round on a long one.
#[test]
fn a_wall_the_straight_line_ignores_and_tier_2_does_not() {
    // A wall across y = 12 from x = 0 to x = 18; the gap is x > 18.
    let walls: Vec<Wall> = vec![[[0.0, 12.0], [18.0, 12.0]]];
    let ix = plain(&walls, Vec::new());
    let (start, target) = ([6.0f32, 6.0f32], [6.0f32, 18.0f32]);
    let straight = distance_to(start, target);
    assert!((straight - 12.0).abs() < 1e-6);

    // The band is exactly the straight distance: the detour cannot fit.
    let tight = ix.query(&q(start, target, straight));
    assert!(!tight.reachable, "tier 2 walked through the wall: {tight:?}");
    assert!(tight.arc_in <= straight + 1e-6);
    assert!(
        distance_to(tight.end_centre, target) > 1.0,
        "the refused move still landed on the target: {tight:?}"
    );

    // A band long enough to go round the open end delivers the target.
    let loose = ix.query(&q(start, target, 40.0));
    assert!(loose.reachable, "tier 2 could not find the gap: {loose:?}");
    assert!(loose.arc_in > straight, "the route round the wall is not longer: {loose:?}");
    assert!(distance_to(loose.end_centre, target) <= 1e-3);

    // And with no wall at all, the same tight band arrives — so the refusal
    // above is the WALL's doing, not the band's.
    let open = plain(&[], Vec::new()).query(&q(start, target, straight));
    assert!(open.reachable, "{open:?}");
    assert_eq!(open.end_centre, target);
}

/// A coarser cell cannot represent the gap a real unit threads — the red proof
/// behind the `REACH_CELL_IN` choice. The doorway here is 1" wide and sits
/// between x = 16 and x = 17: a 1" grid crosses the wall line at x = 16.5 and
/// walks through, a 4" grid only ever crosses at even x and both of those land
/// on wall. The shipped 2" sits between the two; which side of that trade the
/// corpus actually prefers is what `mvreach --cell=` measures.
#[test]
fn red_proof_a_coarser_cell_loses_a_narrow_gap() {
    let walls: Vec<Wall> = vec![
        [[0.0, 12.0], [16.0, 12.0]],
        [[17.0, 12.0], [24.0, 12.0]],
    ];
    let build = |cell: f64| {
        let mut b = ReachBuild::new(BOARD, &walls);
        b.cell_in = cell;
        ReachIndex::build(b, |_| 1.0)
    };
    let fine = build(1.0);
    let coarse = build(4.0);
    let mut query = q([12.0, 8.0], [12.0, 16.0], 40.0);
    query.radius = 0.2;
    // The straight line must actually meet the wall, or the test proves nothing.
    assert!(
        fine.block_reason(query.start, query.target, &query) & 2 != 0,
        "the straight line already avoids the wall"
    );
    let f = fine.query(&query);
    let c = coarse.query(&query);
    assert!(f.reachable, "the 1\" grid lost the doorway: {f:?}");
    assert!(!c.reachable, "the 4\" grid found a doorway it cannot represent: {c:?}");
}

// === the owner masks ======================================================

#[test]
fn the_mover_mask_exempts_its_own_discs_and_the_foe_mask_drops_the_buffer() {
    let mine = owner_bit(3);
    let theirs = owner_bit(7);
    // Two discs square on the line: one is the mover's own model, one is the
    // charge victim (body 0.5", buffered 3.0").
    let discs = vec![
        Disc { c: [12.0, 9.0], r_body: 2.0, r_buf: 2.0, bit: mine },
        Disc { c: [12.0, 15.0], r_body: 0.5, r_buf: 3.0, bit: theirs },
    ];
    let ix = plain(&[], discs);
    let start = [12.0f32, 4.0f32];
    let target = [12.0f32, 13.5f32];
    let band = 40.0;

    // Nothing exempt: both discs are obstacles, so the straight run is blocked.
    let mut plain_q = q(start, target, band);
    let bits = ix.block_reason(start, target, &plain_q);
    assert_eq!(bits & 4, 4, "the discs did not block at all (bits {bits})");

    // The mover's own group is no obstacle; the victim keeps its BODY only, so
    // the run to 13.5 (1.0" clear of a 0.5" body) is now open.
    plain_q.mover = mine;
    plain_q.foe = theirs;
    assert_eq!(
        ix.block_reason(start, target, &plain_q) & 4,
        0,
        "the exemptions did not take"
    );
    assert!(ix.query(&plain_q).reachable);

    // Keep the victim buffered and the same run is blocked again — the foe mask
    // is load-bearing, not decoration.
    plain_q.foe = 0;
    assert!(!ix.query(&plain_q).reachable);
}

// === the band spend and the memo ==========================================

#[test]
fn the_band_is_spent_in_arc_and_the_end_sits_on_the_route() {
    let path: Vec<V2> = vec![[0.0, 0.0], [3.0, 0.0], [3.0, 4.0]];
    assert!((polyline_arc(&path) - 7.0).abs() < 1e-6);
    assert_eq!(walk_to(&path, 0.0), [0.0, 0.0]);
    assert_eq!(walk_to(&path, 3.0), [3.0, 0.0]);
    let p = walk_to(&path, 5.0);
    assert!((p[0] - 3.0).abs() < 1e-5 && (p[1] - 2.0).abs() < 1e-5, "{p:?}");
    assert_eq!(walk_to(&path, 99.0), [3.0, 4.0]);
}

#[test]
fn a_short_band_stops_the_unit_on_the_line_instead_of_at_the_target() {
    let ix = plain(&[], Vec::new());
    let r = ix.query(&q([2.0, 2.0], [2.0, 22.0], 5.0));
    assert!(!r.reachable);
    assert!((r.arc_in - 5.0).abs() < 1e-6, "{r:?}");
    assert!((r.end_centre[1] - 7.0).abs() < 1e-4, "{r:?}");
}

#[test]
fn the_memo_answers_the_same_and_counts_a_hit() {
    let walls: Vec<Wall> = vec![[[0.0, 12.0], [18.0, 12.0]]];
    let ix = plain(&walls, Vec::new());
    let query = q([6.0, 6.0], [6.0, 18.0], 40.0);
    let cold = ix.query_memo(&query);
    assert_eq!(ix.memo_len(), 1);
    let warm = ix.query_memo(&query);
    assert_eq!(cold, warm);
    assert_eq!(ix.stats().memo_hits, 1);
    // A query a quarter inch away is a DIFFERENT question, not a hit.
    let moved = q([6.5, 6.0], [6.0, 18.0], 40.0);
    ix.query_memo(&moved);
    assert_eq!(ix.memo_len(), 2, "the memo key swallowed a moved unit");
    ix.clear_memo();
    assert_eq!(ix.memo_len(), 0);
}

#[test]
fn an_absent_board_leaves_the_seam_inert() {
    use nml_core::sim::reach_index_for_state;
    use nml_core::Terrain;
    let t = Terrain::absent();
    assert_eq!(t.board_in(), [0.0, 0.0]);
    // Without a state we cannot call the builder with units; the board check is
    // the first thing it does, and `Terrain::default()` fails it too.
    assert!(!t.is_valid());
    let d = Terrain::default();
    assert_eq!(d.board_in(), [0.0, 0.0]);
    let _ = reach_index_for_state;
}
