//! Signed tier crossings on a heightfield board — FIREFIGHT 16-19, their "15b".
//!
//! Heightfield stage 3 ([`crate::boardgen`]) puts every 3-inch cell on one of
//! three levels, so a walkable surface is never above another: `y = f(x, z)`
//! holds. A [`TierEdge`] is one contour between two neighbouring cells of
//! DIFFERENT level. Unlike the climbable [`super::cost::Ledge`], a tier edge is
//! DIRECTED in meaning: it knows which side is the higher tier, so a leg that
//! crosses it can be told apart as going UP (low -> high) or DOWN (high -> low).
//! That sign is the whole query — a move that steps off a roof must not be
//! mistaken for one that climbs onto it.
//!
//! This module is new, has no GDScript origin and no caller yet. It is PURE
//! f64, not the f32-Godot boundary the rest of [`super`] mirrors, because the
//! answer feeds a rules decision, not a byte-exact playback.
//!
//! A crossing is reported only when the leg passes through the INTERIOR of both
//! the leg and the tier edge. A leg that starts or ends on a tier edge, that
//! runs along one, or that passes exactly through an edge ENDPOINT (a grid
//! vertex) reports nothing for that edge: its endpoints' own tiers are the
//! caller's business, and a collinear "hit" is not a crossing. This is stricter
//! about touches than `cost::ledge_crossings` (which counts them); a caller that
//! must not miss a leg through a corner has to merge collinear edges and decide
//! the corner case itself.

/// A point or direction in the inch frame, f64 throughout.
pub type P = [f64; 2];

/// What kind of tier edge this is. Carried through untouched; the CALLER decides
/// what a kind may pay or whether it may be crossed at all.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TierKind {
    /// A bare contour with no connector — a cliff unless a rule says otherwise.
    Cliff,
    /// A ladder: the only connector. There are no stairs (maintainer decision 20.11.): models stand on flat
    /// whole cells only and every level change is a ladder, so a tier edge is a cliff or a ladder.
    Ladder,
}

/// Which side of the directed edge `a -> b` carries the HIGH tier.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum HighSide {
    /// The high tier lies to the LEFT of `a -> b` (positive cross product).
    Left,
    /// The high tier lies to the RIGHT of `a -> b` (negative cross product).
    Right,
}

/// One contour between a low and a high tier. `dy_in` is the RISE in inches
/// (always positive); [`HighSide`] says which side is up. `kind` is the
/// connector class, passed through for the caller.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct TierEdge {
    pub a: P,
    pub b: P,
    pub dy_in: f64,
    pub high: HighSide,
    pub kind: TierKind,
}

/// One crossing of a query leg with a tier edge, at fraction `t` along the leg
/// (`0 < t < 1`). `dy_in` is the edge's rise; `down` is `true` when the leg
/// crosses FROM the high side TO the low side (a descent), `false` on a climb.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Crossing {
    pub t: f64,
    pub dy_in: f64,
    pub down: bool,
    pub kind: TierKind,
}

#[inline]
fn cross(u: P, v: P) -> f64 {
    u[0] * v[1] - u[1] * v[0]
}

#[inline]
fn sub(u: P, v: P) -> P {
    [u[0] - v[0], u[1] - v[1]]
}

/// Every tier edge the straight leg `a -> b` crosses, sorted by `t` along the
/// leg, f64 throughout. Parallel/collinear legs and hits on an edge ENDPOINT are
/// not crossings; see the module header. A `t` tie keeps input order.
pub fn tier_crossings(a: P, b: P, edges: &[TierEdge]) -> Vec<Crossing> {
    let r = sub(b, a);
    if r[0] == 0.0 && r[1] == 0.0 {
        return Vec::new();
    }
    let mut out: Vec<Crossing> = Vec::new();
    for e in edges {
        let s = sub(e.b, e.a);
        let denom = cross(r, s);
        if denom == 0.0 {
            continue;
        }
        let qp = sub(e.a, a);
        let t = cross(qp, s) / denom;
        let u = cross(qp, r) / denom;
        if !(t > 0.0 && t < 1.0 && u > 0.0 && u < 1.0) {
            continue;
        }
        // The leg arrives from the LEFT of `e.a -> e.b` exactly when `cross(r, s) > 0` (the leg points to
        // the right of the edge). It is the sign `t` is divided by: no probe point, no rounding.
        let from_high = match e.high {
            HighSide::Left => denom > 0.0,
            HighSide::Right => denom < 0.0,
        };
        out.push(Crossing { t, dy_in: e.dy_in, down: from_high, kind: e.kind });
    }
    out.sort_by(|x, y| x.t.total_cmp(&y.t));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A border running east along `y = 0`, high ground to the north (left of
    /// `a -> b`, since `cross((1, 0), (x, y)) = y`).
    fn east_border(dy_in: f64, kind: TierKind) -> TierEdge {
        TierEdge { a: [-5.0, 0.0], b: [5.0, 0.0], dy_in, high: HighSide::Left, kind }
    }

    #[test]
    fn a_leg_that_climbs_reports_an_up_crossing() {
        let edge = east_border(3.0, TierKind::Ladder);
        let got = tier_crossings([0.0, -1.0], [0.0, 1.0], &[edge]);
        assert_eq!(got.len(), 1);
        assert!((got[0].t - 0.5).abs() < 1e-12);
        assert_eq!(got[0].dy_in, 3.0);
        assert!(!got[0].down, "low -> high must be an UP crossing");
        assert_eq!(got[0].kind, TierKind::Ladder);
    }

    #[test]
    fn a_leg_off_a_roof_is_a_down_crossing() {
        let edge = east_border(3.0, TierKind::Cliff);
        let got = tier_crossings([0.0, 1.0], [0.0, -1.0], &[edge]);
        assert_eq!(got.len(), 1);
        assert!((got[0].t - 0.5).abs() < 1e-12);
        assert!(got[0].down, "high -> low must be a DOWN crossing");
        assert_eq!(got[0].dy_in, 3.0);
    }

    #[test]
    fn a_leg_along_a_tier_edge_does_not_cross() {
        let edges = [east_border(3.0, TierKind::Cliff), {
            let mut e = east_border(3.0, TierKind::Cliff);
            e.high = HighSide::Right;
            e
        }];
        assert!(tier_crossings([-2.0, 0.0], [2.0, 0.0], &edges).is_empty());
    }

    #[test]
    fn two_tiers_in_one_leg_come_out_sorted() {
        let west = TierEdge { a: [0.0, -5.0], b: [0.0, 5.0], dy_in: 3.0, high: HighSide::Right, kind: TierKind::Cliff };
        let east = TierEdge { a: [1.0, -5.0], b: [1.0, 5.0], dy_in: 6.0, high: HighSide::Right, kind: TierKind::Ladder };
        // Feed them east-first so the sort, not the input order, decides.
        let got = tier_crossings([-1.0, 0.0], [2.0, 0.0], &[east, west]);
        assert_eq!(got.len(), 2);
        assert!(got[0].t < got[1].t);
        assert!((got[0].t - 1.0 / 3.0).abs() < 1e-12);
        assert!((got[1].t - 2.0 / 3.0).abs() < 1e-12);
        // High side is to the right (east) of each north-running edge; travelling
        // east means climbing both.
        assert!(!got[0].down && !got[1].down);
        assert_eq!(got[0].kind, TierKind::Cliff);
        assert_eq!(got[1].kind, TierKind::Ladder);
        assert_eq!((got[0].dy_in, got[1].dy_in), (3.0, 6.0));
    }

    #[test]
    fn a_tier_edge_is_a_cliff_or_a_ladder_and_nothing_else() {
        // Exhaustive on purpose: there are no stairs (maintainer decision 20.11.), so a new kind is a deliberate change here.
        let n = |k: TierKind| match k { TierKind::Cliff => 0, TierKind::Ladder => 1 };
        assert_eq!((n(TierKind::Cliff), n(TierKind::Ladder)), (0, 1));
    }

    #[test]
    fn touching_an_edge_is_not_a_crossing() {
        let e = [east_border(3.0, TierKind::Cliff)];
        // Leg ends on the edge (t = 1), starts on it (t = 0), passes through its endpoints (u = 0, u = 1).
        assert!(tier_crossings([0.0, -1.0], [0.0, 0.0], &e).is_empty());
        assert!(tier_crossings([0.0, 0.0], [0.0, 1.0], &e).is_empty());
        assert!(tier_crossings([-5.0, -1.0], [-5.0, 1.0], &e).is_empty());
        assert!(tier_crossings([5.0, -1.0], [5.0, 1.0], &e).is_empty());
    }

    #[test]
    fn a_leg_that_stops_short_or_passes_beside_an_edge_is_empty() {
        let e = [east_border(3.0, TierKind::Cliff)];
        assert!(tier_crossings([0.0, -3.0], [0.0, -1.0], &e).is_empty(), "stops short");
        assert!(tier_crossings([0.0, 1.0], [0.0, 3.0], &e).is_empty(), "starts past it");
        assert!(tier_crossings([6.0, -1.0], [6.0, 1.0], &e).is_empty(), "beside the edge");
        assert!(tier_crossings([1.0, 1.0], [1.0, 1.0], &e).is_empty(), "zero-length leg");
    }

    #[test]
    fn a_hill_gives_up_then_down_and_reversing_flips_both() {
        let up_edge = TierEdge { a: [0.0, -5.0], b: [0.0, 5.0], dy_in: 3.0, high: HighSide::Right, kind: TierKind::Ladder };
        let down_edge = TierEdge { a: [2.0, -5.0], b: [2.0, 5.0], dy_in: 6.0, high: HighSide::Left, kind: TierKind::Cliff };
        let there = tier_crossings([-1.0, 0.0], [3.0, 0.0], &[down_edge, up_edge]);
        let got: Vec<_> = there.iter().map(|c| (c.t, c.dy_in, c.down, c.kind)).collect();
        assert_eq!(got, [(0.25, 3.0, false, TierKind::Ladder), (0.75, 6.0, true, TierKind::Cliff)]);
        let back = tier_crossings([3.0, 0.0], [-1.0, 0.0], &[down_edge, up_edge]);
        let got: Vec<_> = back.iter().map(|c| (c.t, c.dy_in, c.down, c.kind)).collect();
        assert_eq!(got, [(0.25, 6.0, false, TierKind::Cliff), (0.75, 3.0, true, TierKind::Ladder)]);
    }

    #[test]
    fn a_nearly_parallel_leg_far_from_the_origin_keeps_its_sign() {
        // 4e-7 in of slope over 8 in: a probe point a hair short of the hit lands on the wrong side here.
        let (ox, oy) = (37.3, -21.7);
        let edge = TierEdge { a: [ox - 5.0, oy], b: [ox + 5.0, oy], dy_in: 3.0, high: HighSide::Left, kind: TierKind::Cliff };
        let got = tier_crossings([ox - 4.0, oy + 4e-7], [ox + 4.0, oy - 4e-7], &[edge]);
        assert_eq!(got.len(), 1);
        assert!(got[0].down, "north (high) to south (low) is a descent");
        let got = tier_crossings([ox - 4.0, oy - 4e-7], [ox + 4.0, oy + 4e-7], &[edge]);
        assert!(!got[0].down);
    }
}
