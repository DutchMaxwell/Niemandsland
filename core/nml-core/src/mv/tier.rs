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
//! the leg and the tier edge. A leg that starts or ends on a tier edge, or that
//! runs along one, reports nothing: its endpoints' own tiers are the caller's
//! business, and a collinear "hit" is not a crossing.

/// A point or direction in the inch frame, f64 throughout.
pub type P = [f64; 2];

/// What kind of tier edge this is. Carried through untouched; the CALLER decides
/// what a kind may pay or whether it may be crossed at all.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TierKind {
    /// A bare contour with no connector — a cliff unless a rule says otherwise.
    Cliff,
    /// A stair connector (one 3-inch rise per level).
    Stair,
    /// A short ladder connector.
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
        // Which side the leg arrives from: probe a hair short of the hit point.
        let probe = [a[0] + r[0] * (t * (1.0 - 1e-9)), a[1] + r[1] * (t * (1.0 - 1e-9))];
        let side = cross(s, sub(probe, e.a));
        let from_high = match e.high {
            HighSide::Left => side > 0.0,
            HighSide::Right => side < 0.0,
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
        let edge = east_border(3.0, TierKind::Stair);
        let got = tier_crossings([0.0, -1.0], [0.0, 1.0], &[edge]);
        assert_eq!(got.len(), 1);
        assert!((got[0].t - 0.5).abs() < 1e-12);
        assert_eq!(got[0].dy_in, 3.0);
        assert!(!got[0].down, "low -> high must be an UP crossing");
        assert_eq!(got[0].kind, TierKind::Stair);
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
        let west = TierEdge { a: [0.0, -5.0], b: [0.0, 5.0], dy_in: 3.0, high: HighSide::Right, kind: TierKind::Stair };
        let east = TierEdge { a: [1.0, -5.0], b: [1.0, 5.0], dy_in: 3.0, high: HighSide::Right, kind: TierKind::Ladder };
        // Feed them east-first so the sort, not the input order, decides.
        let got = tier_crossings([-1.0, 0.0], [2.0, 0.0], &[east, west]);
        assert_eq!(got.len(), 2);
        assert!(got[0].t < got[1].t);
        assert!((got[0].t - 1.0 / 3.0).abs() < 1e-12);
        assert!((got[1].t - 2.0 / 3.0).abs() < 1e-12);
        // High side is to the right (east) of each north-running edge; travelling
        // east means climbing both.
        assert!(!got[0].down && !got[1].down);
        assert_eq!(got[0].kind, TierKind::Stair);
        assert_eq!(got[1].kind, TierKind::Ladder);
    }
}
