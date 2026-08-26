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
