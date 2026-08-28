//! Godot `Vector3` arithmetic at SINGLE precision.
//!
//! The engine's `Vector3` is `float` (Godot builds `real_t` as 32-bit), so every
//! position the sim writes is an f32 value. `resolve()` moves a unit through
//! four `Vector3` operations (sum, divide, normalize, add) and the recorded
//! `state_after` carries the f32 result — doing that arithmetic in f64 lands
//! ~1e-7 away, a hundred times the 1e-9 parity bar. So the move math, and every
//! distance that feeds an integer gate (`ceilf(dist_in)`, the over-9" rules),
//! runs in `f32` here and only widens to f64 where GDScript widens: a
//! `Variant` float is f64, so `length()` promotes as soon as it leaves the
//! `Vector3`.
//!
//! Positions are stored as f64 because that is what the JSON carries; every one
//! of them is an exactly-representable f32 value, so the casts are lossless.

use crate::IN2M;

pub type V3 = [f32; 3];

#[inline]
pub fn to_f32(p: [f64; 3]) -> V3 {
    [p[0] as f32, p[1] as f32, p[2] as f32]
}

#[inline]
pub fn to_f64(p: V3) -> [f64; 3] {
    [p[0] as f64, p[1] as f64, p[2] as f64]
}

#[inline]
pub fn add(a: V3, b: V3) -> V3 {
    [a[0] + b[0], a[1] + b[1], a[2] + b[2]]
}

#[inline]
pub fn sub(a: V3, b: V3) -> V3 {
    [a[0] - b[0], a[1] - b[1], a[2] - b[2]]
}

/// `Vector3::operator*(real_t)` — the scalar is narrowed to f32 first, exactly
/// like the Variant multiply does when GDScript hands it an f64.
#[inline]
pub fn mul(a: V3, s: f64) -> V3 {
    let s = s as f32;
    [a[0] * s, a[1] * s, a[2] * s]
}

#[inline]
pub fn div(a: V3, s: f64) -> V3 {
    let s = s as f32;
    [a[0] / s, a[1] / s, a[2] / s]
}

/// `Vector3::length()` — `Math::sqrt(x*x + y*y + z*z)` in f32, summed left to right.
#[inline]
pub fn length(a: V3) -> f32 {
    (a[0] * a[0] + a[1] * a[1] + a[2] * a[2]).sqrt()
}

/// `Vector3::normalized()` — zero length returns the zero vector (Godot's guard).
#[inline]
pub fn normalized(a: V3) -> V3 {
    let lensq = a[0] * a[0] + a[1] * a[1] + a[2] * a[2];
    if lensq == 0.0 {
        return [0.0, 0.0, 0.0];
    }
    let len = lensq.sqrt();
    [a[0] / len, a[1] / len, a[2] / len]
}

/// `BattleSim._centre_of` battle_sim.gd:673-680 — the arithmetic mean of the
/// snapshot positions; an empty array is `Vector3.ZERO`.
pub fn centre(ps: &[[f64; 3]]) -> V3 {
    let mut c: V3 = [0.0, 0.0, 0.0];
    if ps.is_empty() {
        return c;
    }
    for p in ps {
        c = add(c, to_f32(*p));
    }
    div(c, ps.len() as f64)
}

/// `BattleSim.dist_in` battle_sim.gd:758-764 — nearest MODEL-to-model gap of two
/// snapshot position arrays in inches. `minf` is an f64 min over f32 lengths,
/// and the division by `IN2M` is the one f64 step.
pub fn dist_in(a: &[[f64; 3]], b: &[[f64; 3]]) -> f64 {
    let mut best = f64::INFINITY;
    for pa in a {
        let pa = to_f32(*pa);
        for pb in b {
            let d = length(sub(pa, to_f32(*pb))) as f64;
            if d < best {
                best = d;
            }
        }
    }
    best / IN2M
}

/// `BattleSim.edge_gap_in` battle_sim.gd:766-785 — nearest BASE-EDGE gap of two
/// snapshot position arrays in inches: min over all model pairs of (HORIZONTAL
/// centre distance - r_a - r_b), a radii array shorter than its positions
/// falling back to `default_radius` per missing entry. Negative = the bases
/// already overlap; either array empty -> INFINITY, same as `dist_in`.
///
/// Precision path, identical to the spacing clamp's own probe: the x/z
/// difference and `Vector3(...).length()` run in f32 (the engine's `real_t`),
/// and only the radius subtraction and the division by `IN2M` widen — a Variant
/// float is f64 the moment the length leaves the `Vector3`.
pub fn edge_gap_in(
    a_pos: &[[f64; 3]],
    a_radii: &[f64],
    b_pos: &[[f64; 3]],
    b_radii: &[f64],
    default_radius: f64,
) -> f64 {
    let mut best = f64::INFINITY;
    for (ai, pa) in a_pos.iter().enumerate() {
        let pa = to_f32(*pa);
        let ra = a_radii.get(ai).copied().unwrap_or(default_radius);
        for (bi, pb) in b_pos.iter().enumerate() {
            let pb = to_f32(*pb);
            let rb = b_radii.get(bi).copied().unwrap_or(default_radius);
            let flat: V3 = [pa[0] - pb[0], 0.0, pa[2] - pb[2]];
            let gap = length(flat) as f64 - ra - rb;
            if gap < best {
                best = gap;
            }
        }
    }
    best / IN2M
}

// ===== NML-1073 M5 D5-2b — base SHAPE, not just a radius =====

/// `SeparationChecker.EPSILON_M` separation_checker.gd:87 — the near-zero guard
/// the centre-line method uses for concentric bases and a vanishing denominator.
pub const SHAPE_EPSILON_M: f64 = 0.00001;

/// A model's base footprint, as `SeparationChecker.BaseShape`
/// (separation_checker.gd:98-140) describes it and as the act header records it
/// per unit since #447 (`base_shape` / `base_w_mm` / `base_d_mm`).
///
/// `Round` is the whole of today's path: the recorded per-model radius IS the
/// base. `Oval` carries the unit's UNSCALED axes in millimetres; the per-model
/// Tough scale rides in the recorded radius, and `semis` divides it back out —
/// `bounding_radius()` (separation_checker.gd:134-138) is
/// `sqrt(semi_x^2 + semi_z^2)`, so `semi_x = r * w / hypot(w, d)` recovers the
/// axis exactly, scale and all.
///
/// A `base_shape` the recorder never writes ("rect") is READ as `Round`, which
/// is what the table does: `shape_for_model` (:267-278) has no RECT branch and
/// measures a `base_is_square` unit off `base_size_round`.
///
/// FACING: `shape_for_model` takes `yaw` from `model.node.global_rotation.y`,
/// and the capture carries no per-model rotation. It does not have to: nothing
/// on the AI path ever writes a model node's rotation (`SoloController` only
/// ever assigns `global_position`; the oval alignment
/// `OPRArmyManager._align_to_oval_long_axis` :2539 turns the GLB CHILD inside
/// the wrapper, never the wrapper the ModelInstance points at). So every AI-
/// moved base stands yaw 0 — axis-aligned, `base_w_mm` along world X and
/// `base_d_mm` along world Z — and that is what the header's two axes mean.
/// The field is kept because the math is the table's whole function, and a
/// hand-dragged model in a human game DOES turn (`ObjectManager` :1597).
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum BaseShape {
    Round,
    Oval { w_mm: f64, d_mm: f64, yaw: f32 },
}

impl BaseShape {
    /// The half-axes in METRES for a model whose recorded (circumscribing)
    /// radius is `r`. A degenerate axis pair falls back to the circle.
    #[inline]
    fn semis(self, r: f64) -> (f64, f64) {
        match self {
            BaseShape::Round => (r, r),
            BaseShape::Oval { w_mm, d_mm, .. } => {
                let hyp = (w_mm * w_mm + d_mm * d_mm).sqrt();
                if hyp <= 0.0 {
                    (r, r)
                } else {
                    (r * w_mm / hyp, r * d_mm / hyp)
                }
            }
        }
    }

    /// `SeparationChecker._min_extent` :331-334.
    #[inline]
    fn min_extent(self, r: f64) -> f64 {
        match self {
            BaseShape::Round => r,
            BaseShape::Oval { .. } => {
                let (sx, sz) = self.semis(r);
                sx.min(sz)
            }
        }
    }

    /// `SeparationChecker._support_extent` :307-329 — the distance from the
    /// centre to the boundary along the unit world-XZ direction `dir`. The
    /// ellipse radius along a local direction is `(a*b) / sqrt(b^2 lx^2 + a^2 lz^2)`.
    #[inline]
    fn support_extent(self, r: f64, dir: [f32; 2]) -> f64 {
        let yaw = match self {
            BaseShape::Round => return r,
            BaseShape::Oval { yaw, .. } => yaw,
        };
        // `dir.rotated(-yaw)` — a Vector2 method, so f32 like the engine's.
        let (s, c) = (-yaw).sin_cos();
        let local = [dir[0] * c - dir[1] * s, dir[0] * s + dir[1] * c];
        let (sx, sz) = self.semis(r);
        let (lx, lz) = (local[0] as f64, local[1] as f64);
        let denom = (sz * sz * lx * lx + sx * sx * lz * lz).sqrt();
        if denom < SHAPE_EPSILON_M {
            return (sx + sz) * 0.5;
        }
        sx * sz / denom
    }
}

/// `SeparationChecker._edge_distance_meters` separation_checker.gd:285-302 for
/// ONE model pair, in METRES. Two round bases take the early exact branch (:291),
/// which is bit-for-bit the arithmetic `edge_gap_in` already ran; anything
/// oval-involved takes the directional support along the line joining the
/// centres (:296-302), including its concentric guard.
#[inline]
pub fn pair_gap_m(pa: V3, ra: f64, sa: BaseShape, pb: V3, rb: f64, sb: BaseShape) -> f64 {
    if matches!(sa, BaseShape::Round) && matches!(sb, BaseShape::Round) {
        let flat: V3 = [pa[0] - pb[0], 0.0, pa[2] - pb[2]];
        return length(flat) as f64 - ra - rb;
    }
    let d: [f32; 2] = [pb[0] - pa[0], pb[2] - pa[2]];
    let center_dist = (d[0] * d[0] + d[1] * d[1]).sqrt() as f64;
    if center_dist < SHAPE_EPSILON_M {
        return -sa.min_extent(ra).min(sb.min_extent(rb));
    }
    let cd32 = center_dist as f32;
    let dir = [d[0] / cd32, d[1] / cd32];
    center_dist - sa.support_extent(ra, dir) - sb.support_extent(rb, [-dir[0], -dir[1]])
}

/// `SoloController.nearest_melee_gap_in` :8536 / `nearest_charge_vector` :8560 —
/// the nearest base-EDGE gap in inches over all model pairs, measured through
/// the recorded base SHAPES instead of their circumscribing circles.
///
/// With both sides round this is `edge_gap_in` itself, delegated so a corpus
/// that carries no `base_shape` (every recording before #447) replays byte for
/// byte, INCLUDING its missing-radius fallback and its lack of a concentric
/// guard — `BattleSim.edge_gap_in` (battle_sim.gd:869) has neither and this
/// path is its port.
#[allow(clippy::too_many_arguments)]
pub fn edge_gap_shaped_in(
    a_pos: &[[f64; 3]],
    a_radii: &[f64],
    a_shape: BaseShape,
    b_pos: &[[f64; 3]],
    b_radii: &[f64],
    b_shape: BaseShape,
    default_radius: f64,
) -> f64 {
    if matches!(a_shape, BaseShape::Round) && matches!(b_shape, BaseShape::Round) {
        return edge_gap_in(a_pos, a_radii, b_pos, b_radii, default_radius);
    }
    let mut best = f64::INFINITY;
    for (ai, pa) in a_pos.iter().enumerate() {
        let pa = to_f32(*pa);
        let ra = a_radii.get(ai).copied().unwrap_or(default_radius);
        for (bi, pb) in b_pos.iter().enumerate() {
            let rb = b_radii.get(bi).copied().unwrap_or(default_radius);
            let gap = pair_gap_m(pa, ra, a_shape, to_f32(*pb), rb, b_shape);
            if gap < best {
                best = gap;
            }
        }
    }
    best / IN2M
}

#[cfg(test)]
mod base_shape_tests {
    use super::*;

    /// The Battle Tank of `qbg_ref` — a 92 x 120 mm oval, the header's own
    /// numbers (`base_w_mm` 92, `base_d_mm` 120, `base_radius`
    /// 0.07560423268574319).
    const TANK_R: f64 = 0.07560423268574319;
    const TANK: BaseShape = BaseShape::Oval { w_mm: 92.0, d_mm: 120.0, yaw: 0.0 };

    fn at(x: f64, z: f64) -> [f64; 3] {
        [x, 0.0, z]
    }

    /// The residue the whole rung is about: `base_radius` is the CIRCUMSCRIBING
    /// circle, so across its SHORT axis the twin used to claim 1.17 more inches
    /// of base than the table measures.
    #[test]
    fn the_circumscribing_circle_is_pessimistic_on_the_battle_tank_axes() {
        let sx = TANK.support_extent(TANK_R, [1.0, 0.0]);
        let sz = TANK.support_extent(TANK_R, [0.0, 1.0]);
        assert!((sx - 0.046).abs() < 1e-12, "short semi-axis {sx}");
        assert!((sz - 0.060).abs() < 1e-12, "long semi-axis {sz}");
        assert!((TANK_R - 0.0756042326857432).abs() < 1e-12);
        assert!((TANK_R - sx) / IN2M > 1.16 && (TANK_R - sx) / IN2M < 1.17);
        assert!((TANK_R - sz) / IN2M > 0.61 && (TANK_R - sz) / IN2M < 0.62);
    }

    /// Two tanks 10" apart, measured across the SHORT axes and along the LONG
    /// ones. The circle reading is the same both times and wrong both times.
    #[test]
    fn oval_against_oval_reads_its_short_and_its_long_axis() {
        let ten = 10.0 * IN2M;
        let short =
            edge_gap_shaped_in(&[at(0.0, 0.0)], &[TANK_R], TANK, &[at(ten, 0.0)], &[TANK_R], TANK, 0.0);
        let long =
            edge_gap_shaped_in(&[at(0.0, 0.0)], &[TANK_R], TANK, &[at(0.0, ten)], &[TANK_R], TANK, 0.0);
        let circle = edge_gap_in(&[at(0.0, 0.0)], &[TANK_R], &[at(ten, 0.0)], &[TANK_R], 0.0);
        assert!((short - (10.0 - 2.0 * 0.046 / IN2M)).abs() < 1e-6, "short {short}");
        assert!((long - (10.0 - 2.0 * 0.060 / IN2M)).abs() < 1e-6, "long {long}");
        assert!(short > long, "the short axis leaves MORE gap: {short} vs {long}");
        assert!((circle - (10.0 - 2.0 * TANK_R / IN2M)).abs() < 1e-6);
        assert!(circle < long, "the circle is the most pessimistic of the three");
    }

    /// Oval against a plain 32 mm round base: only the oval's side changes.
    #[test]
    fn oval_against_round_only_shrinks_the_oval_side() {
        let ten = 10.0 * IN2M;
        let r = 0.016;
        let g = edge_gap_shaped_in(
            &[at(0.0, 0.0)],
            &[TANK_R],
            TANK,
            &[at(ten, 0.0)],
            &[r],
            BaseShape::Round,
            0.0,
        );
        assert!((g - (10.0 - (0.046 + r) / IN2M)).abs() < 1e-6, "{g}");
    }

    /// The facing the capture does not carry, proven to be carried by the math:
    /// a tank turned a quarter turn presents its LONG axis to a neighbour that
    /// stood across its short one.
    #[test]
    fn a_turned_oval_swaps_which_axis_faces_the_enemy() {
        let turned = BaseShape::Oval {
            w_mm: 92.0,
            d_mm: 120.0,
            yaw: std::f32::consts::FRAC_PI_2,
        };
        let across = turned.support_extent(TANK_R, [1.0, 0.0]);
        assert!((across - 0.060).abs() < 1e-7, "turned short axis now reads {across}");
    }

    /// The whole no-shape path, byte for byte: a corpus without `base_shape`
    /// answers exactly what `edge_gap_in` answered before the rung.
    #[test]
    fn two_round_bases_are_the_old_function_bit_for_bit() {
        let pos_a = [at(0.0, 0.0), at(0.05, 0.02)];
        let pos_b = [at(0.3, 0.11)];
        let ra = [0.016, 0.02];
        let rb = [0.0125];
        assert_eq!(
            edge_gap_shaped_in(&pos_a, &ra, BaseShape::Round, &pos_b, &rb, BaseShape::Round, 0.016),
            edge_gap_in(&pos_a, &ra, &pos_b, &rb, 0.016)
        );
    }
}
