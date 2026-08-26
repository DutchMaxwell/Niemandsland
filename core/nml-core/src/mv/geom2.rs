//! Godot `Vector2` arithmetic at SINGLE precision — the movement planner's
//! geometry primitives, mirrored operation for operation from
//! `scripts/solo/movement_planner.gd:96-285`.
//!
//! The f32/f64 boundary is the whole point of this file. Godot's `Vector2` is
//! `real_t` = f32, so `distance_to`, `dot`, `lerp`, `normalized` and
//! `operator*(real_t)` all compute in f32; a GDScript `float` (and therefore a
//! Vector2 COMPONENT read through GDScript, e.g. `b.x - a.x` in `_orient`) is
//! f64. Every function below promotes at exactly the place the GDScript does.
//!
//! Positions travel as f32 pairs; the JSON corpus carries f64 numbers that are
//! all exactly-representable f32 values, so `to_f32` is lossless there.

use super::EPS;

/// Godot `Vector2` — `real_t` is a 32-bit float in the shipped engine build.
pub type V2 = [f32; 2];

#[inline]
pub fn to_f32(p: [f64; 2]) -> V2 {
    [p[0] as f32, p[1] as f32]
}

#[inline]
pub fn to_f64(p: V2) -> [f64; 2] {
    [p[0] as f64, p[1] as f64]
}

#[inline]
pub fn add(a: V2, b: V2) -> V2 {
    [a[0] + b[0], a[1] + b[1]]
}

#[inline]
pub fn sub(a: V2, b: V2) -> V2 {
    [a[0] - b[0], a[1] - b[1]]
}

/// `Vector2::operator*(real_t)` — the scalar narrows to f32 first, exactly like
/// the Variant multiply does when GDScript hands it an f64.
#[inline]
pub fn mul(a: V2, s: f64) -> V2 {
    let s = s as f32;
    [a[0] * s, a[1] * s]
}

/// `Vector2::operator/(real_t)` — the divisor narrows to f32 first, the same
/// way `mul` does. `_centroid` (movement_planner.gd:426) and
/// `_pull_into_placed`'s unit step (:1243) both divide a `Vector2` by a
/// GDScript `float`, so the division itself runs in f32.
#[inline]
pub fn div(a: V2, s: f64) -> V2 {
    let s = s as f32;
    [a[0] / s, a[1] / s]
}

/// `Vector2::length_squared()` — f32, promoted on the way out because GDScript
/// stores the result in a `float`.
#[inline]
pub fn length_squared(a: V2) -> f64 {
    (a[0] * a[0] + a[1] * a[1]) as f64
}

/// `Vector2::length()` — `Math::sqrt(x*x + y*y)` in f32.
#[inline]
pub fn length(a: V2) -> f64 {
    (a[0] * a[0] + a[1] * a[1]).sqrt() as f64
}

/// `Vector2::dot()` — f32 multiply-add, promoted on the way out.
#[inline]
pub fn dot(a: V2, b: V2) -> f64 {
    (a[0] * b[0] + a[1] * b[1]) as f64
}

/// `Vector2::cross()` — f32, promoted on the way out.
#[inline]
pub fn cross(a: V2, b: V2) -> f64 {
    (a[0] * b[1] - a[1] * b[0]) as f64
}

/// `Vector2::distance_to()` — `Math::sqrt((x-vx)^2 + (y-vy)^2)` in f32.
#[inline]
pub fn distance_to(a: V2, b: V2) -> f64 {
    let dx = a[0] - b[0];
    let dy = a[1] - b[1];
    (dx * dx + dy * dy).sqrt() as f64
}

/// `Vector2::distance_squared_to()` — f32.
#[inline]
pub fn distance_squared_to(a: V2, b: V2) -> f64 {
    let dx = a[0] - b[0];
    let dy = a[1] - b[1];
    (dx * dx + dy * dy) as f64
}

/// `Vector2::lerp()` — `res.x += weight * (to.x - x)` in f32, weight narrowed.
#[inline]
pub fn lerp(a: V2, b: V2, w: f64) -> V2 {
    let w = w as f32;
    [a[0] + w * (b[0] - a[0]), a[1] + w * (b[1] - a[1])]
}

/// `Vector2::normalized()` — Godot's guard returns the ZERO vector for a
/// zero-length input (it does not divide).
#[inline]
pub fn normalized(a: V2) -> V2 {
    let l = a[0] * a[0] + a[1] * a[1];
    if l == 0.0 {
        return [0.0, 0.0];
    }
    let l = l.sqrt();
    [a[0] / l, a[1] / l]
}

/// `MovementPlanner._orient` — movement_planner.gd:96. Signed area ×2 of abc.
/// The GDScript reads `.x`/`.y` as Variant floats, so this arithmetic is f64
/// over f32-exact components — NOT f32.
#[inline]
pub fn orient(a: V2, b: V2, c: V2) -> f64 {
    let (ax, ay) = (a[0] as f64, a[1] as f64);
    let (bx, by) = (b[0] as f64, b[1] as f64);
    let (cx, cy) = (c[0] as f64, c[1] as f64);
    (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
}

/// `MovementPlanner._on_segment` — movement_planner.gd:101.
#[inline]
pub fn on_segment(a: V2, b: V2, p: V2) -> bool {
    let (ax, ay) = (a[0] as f64, a[1] as f64);
    let (bx, by) = (b[0] as f64, b[1] as f64);
    let (px, py) = (p[0] as f64, p[1] as f64);
    px >= ax.min(bx) - EPS && px <= ax.max(bx) + EPS && py >= ay.min(by) - EPS && py <= ay.max(by) + EPS
}

/// `MovementPlanner.segments_cross` — movement_planner.gd:108. Touching and
/// collinear overlap count as crossing (the safe side).
pub fn segments_cross(p1: V2, p2: V2, p3: V2, p4: V2) -> bool {
    let d1 = orient(p3, p4, p1);
    let d2 = orient(p3, p4, p2);
    let d3 = orient(p1, p2, p3);
    let d4 = orient(p1, p2, p4);
    if ((d1 > 0.0 && d2 < 0.0) || (d1 < 0.0 && d2 > 0.0))
        && ((d3 > 0.0 && d4 < 0.0) || (d3 < 0.0 && d4 > 0.0))
    {
        return true;
    }
    if d1.abs() <= EPS && on_segment(p3, p4, p1) {
        return true;
    }
    if d2.abs() <= EPS && on_segment(p3, p4, p2) {
        return true;
    }
    if d3.abs() <= EPS && on_segment(p1, p2, p3) {
        return true;
    }
    if d4.abs() <= EPS && on_segment(p1, p2, p4) {
        return true;
    }
    false
}

/// `MovementPlanner.path_crosses_wall` — movement_planner.gd:141.
pub fn path_crosses_wall(a: V2, b: V2, walls: &[[V2; 2]]) -> bool {
    for w in walls {
        if segments_cross(a, b, w[0], w[1]) {
            return true;
        }
    }
    false
}

/// `MovementPlanner.point_seg_distance` — movement_planner.gd:168.
///
/// `len2` and the dot product are f32 results the GDScript stores in `float`
/// vars, so the division and the clamp run in f64; `ab * t` narrows `t` back to
/// f32 for the Vector2 multiply, and the final `distance_to` is f32 again.
pub fn point_seg_distance(p: V2, a: V2, b: V2) -> f64 {
    let ab = sub(b, a);
    let len2 = length_squared(ab);
    if len2 < EPS * EPS {
        return distance_to(p, a);
    }
    let t = (dot(sub(p, a), ab) / len2).clamp(0.0, 1.0);
    distance_to(p, add(a, mul(ab, t)))
}

/// `MovementPlanner.seg_seg_distance` — movement_planner.gd:178. Zero when the
/// segments cross, else the smallest of the four endpoint-to-segment distances.
pub fn seg_seg_distance(p1: V2, p2: V2, q1: V2, q2: V2) -> f64 {
    if segments_cross(p1, p2, q1, q2) {
        return 0.0;
    }
    point_seg_distance(p1, q1, q2)
        .min(point_seg_distance(p2, q1, q2))
        .min(point_seg_distance(q1, p1, p2).min(point_seg_distance(q2, p1, p2)))
}

/// `MovementPlanner._world_before` — movement_planner.gd:1326. The world-frame
/// canonical point order (smaller x, then y), with the same EPS band the cell
/// order does not need. The components are read as Variant floats, so the
/// comparison runs in f64 over f32-exact numbers.
#[inline]
pub fn world_before(a: V2, b: V2) -> bool {
    let (ax, ay) = (a[0] as f64, a[1] as f64);
    let (bx, by) = (b[0] as f64, b[1] as f64);
    ax < bx - EPS || ((ax - bx).abs() <= EPS && ay < by - EPS)
}

/// `MovementPlanner.polyline_length` — movement_planner.gd:253. Each leg is an
/// f32 `distance_to`; the sum accumulates in f64, left to right.
pub fn polyline_length(points: &[V2]) -> f64 {
    let mut total = 0.0;
    for i in 1..points.len() {
        total += distance_to(points[i - 1], points[i]);
    }
    total
}

/// `MovementPlanner.trim_polyline` — movement_planner.gd:263. The distance-truth
/// clamp: walk the legs, cut the final one at the exact remaining budget.
/// Legs shorter than EPS are skipped, exactly as the GDScript skips them.
pub fn trim_polyline(points: &[V2], max_len: f64) -> Vec<V2> {
    if points.len() <= 1 {
        return points.to_vec();
    }
    if max_len <= 0.0 {
        return vec![points[0]];
    }
    let mut out: Vec<V2> = vec![points[0]];
    let mut spent = 0.0f64;
    for i in 1..points.len() {
        let leg = distance_to(points[i - 1], points[i]);
        if leg <= EPS {
            continue;
        }
        if spent + leg <= max_len + EPS {
            out.push(points[i]);
            spent += leg;
            continue;
        }
        let frac = (max_len - spent) / leg;
        if frac > EPS {
            out.push(lerp(points[i - 1], points[i], frac));
        }
        break;
    }
    out
}
