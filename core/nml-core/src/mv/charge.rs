//! NML-1073 M4-5 — `MovementPlanner.charge_contact_slots` (movement_planner.gd:938)
//! and `_nearest_base_dist` (:1004), a LITERAL transcription.
//!
//! Bug-31 (the maintainer's "Säulen-Formation"): a charging unit used to queue
//! at ONE shared body goal and lost every contact but the first. This hands each
//! mover its own point on a target base's contact circle, so the unit fans into
//! a battle line.
//!
//! It is NOT called by `plan_unit_step` — the CALLER runs it and passes the
//! answer in as `opts["charge_slots"]` (solo_controller.gd:6033), which is why
//! the recorded corpus carries both its inputs and its output on every charge
//! line and can gate it directly.
//!
//! THREE THINGS DECIDE PARITY:
//!
//!   * THE PICK ORDER (:943-945). Movers choose nearest-base-first, and each
//!     chosen slot then repels later picks by 95 % of the two base radii. The
//!     GDScript comparator is a bare `<` on `_nearest_base_dist` with NO index
//!     fallback, so on an exactly symmetric line Godot's unstable introsort may
//!     order equidistant movers arbitrarily. This port breaks that tie on the
//!     model INDEX, which is a total order and therefore reproducible. The
//!     16-game corpus contains ZERO ties (11 charge calls, every mover at a
//!     distinct distance), so the corpus cannot tell the two apart — see the
//!     unit test, which builds the symmetric case by hand.
//!   * THE FAN (:955-958). Five points around the near face normally; TEN
//!     (out to ±2.8 rad and the far pole) when the target is a single base or
//!     when slots are scarce (`bases * 5 < movers`), so a horde can ring a
//!     monster instead of losing contacts.
//!   * THE FALLBACK (:971-988). When every candidate is repelled, the mover
//!     aims at the facing point of the base it is EDGE-nearest to — not
//!     `tgt_bases[0]`, which used to march the far flank at the wrong enemy.
//!
//! PRECISION. `ucentre` accumulates in f32 and divides by an f32 divisor;
//! `Vector2::angle()` is an f32 `atan2`; the fan offsets, the radii sums and
//! every distance comparison are f64.

use super::geom2::{add, distance_to, div, length, mul, normalized, sub, V2};

/// `MovementPlanner._nearest_base_dist` — movement_planner.gd:1004. CENTRE
/// distance to the closest target base (the radius is NOT subtracted here — the
/// fallback branch at :977 is the one that measures to the edge).
pub fn nearest_base_dist(p: V2, tgt_bases: &[(V2, f64)]) -> f64 {
    let mut best = f64::INFINITY;
    for tb in tgt_bases {
        best = best.min(distance_to(p, tb.0));
    }
    best
}

/// `Vector2.INF` — the "no slot found" sentinel `best` starts at (:951).
const V_INF: V2 = [f32::INFINITY, f32::INFINITY];

/// `MovementPlanner.charge_contact_slots` — movement_planner.gd:938. One slot
/// per mover, in MOVER order. Empty when the target has no bases.
pub fn charge_contact_slots(mpos: &[V2], radii: &[f64], tgt_bases: &[(V2, f64)]) -> Vec<V2> {
    if tgt_bases.is_empty() {
        return Vec::new();
    }
    // :941-944 — the movers' centre, f32 sum over an f32 divisor.
    let mut ucentre: V2 = [0.0, 0.0];
    for p in mpos {
        ucentre = add(ucentre, *p);
    }
    ucentre = div(ucentre, 1.0f64.max(mpos.len() as f64));

    // :945-947 — nearest-to-the-target picks first. The GDScript comparator has
    // no fallback; the index tie-break here is a total order (see the header).
    let mut order: Vec<usize> = (0..mpos.len()).collect();
    order.sort_by(|&a, &b| {
        let da = nearest_base_dist(mpos[a], tgt_bases);
        let db = nearest_base_dist(mpos[b], tgt_bases);
        if da == db {
            a.cmp(&b)
        } else {
            da.partial_cmp(&db).unwrap()
        }
    });

    // :955-958 — the wide fan for a single base or a slot-scarce target.
    let narrow: [f64; 5] = [0.0, 0.7, -0.7, 1.4, -1.4];
    let wide: [f64; 10] =
        [0.0, 0.7, -0.7, 1.4, -1.4, 2.1, -2.1, 2.8, -2.8, std::f64::consts::PI];
    let wide_fan = tgt_bases.len() * 5 < mpos.len() || tgt_bases.len() == 1;
    let fan: &[f64] = if wide_fan { &wide } else { &narrow };

    let mut taken: Vec<(V2, f64)> = Vec::new();
    let mut out: Vec<(usize, V2)> = Vec::new();
    for idx in order {
        // :949 — a mover past the end of `radii` is assumed to be a 1" base.
        let ri = radii.get(idx).copied().unwrap_or(0.5);
        let mut best: V2 = V_INF;
        let mut best_d = f64::INFINITY;
        for tb in tgt_bases {
            let c = tb.0;
            let tr = tb.1;
            // :954 — the face points from the target base at the movers' centre.
            let to_u = sub(ucentre, c);
            let face = if length(to_u) > 0.001 { normalized(to_u) } else { [1.0, 0.0] };
            // `Vector2::angle()` is `Math::atan2(y, x)` at real_t = f32.
            let base_ang = face[1].atan2(face[0]) as f64;
            for k in fan {
                let ang = base_ang + *k;
                let unit: V2 = [ang.cos() as f32, ang.sin() as f32];
                let slot = add(c, mul(unit, tr + ri));
                let mut free = true;
                for t in &taken {
                    if distance_to(slot, t.0) < (ri + t.1) * 0.95 {
                        free = false;
                        break;
                    }
                }
                if !free {
                    continue;
                }
                let d = distance_to(mpos[idx], slot);
                if d < best_d {
                    best_d = d;
                    best = slot;
                }
            }
        }
        if best == V_INF {
            // :971-988 — every slot taken: aim at the EDGE-nearest base's face.
            let mut c0 = tgt_bases[0].0;
            let mut tr0 = tgt_bases[0].1;
            let mut near_d = f64::INFINITY;
            for tb2 in tgt_bases {
                let d2 = distance_to(mpos[idx], tb2.0) - tb2.1;
                if d2 < near_d {
                    near_d = d2;
                    c0 = tb2.0;
                    tr0 = tb2.1;
                }
            }
            let face0 = normalized(sub(mpos[idx], c0));
            best = add(c0, mul(face0, tr0 + ri));
        }
        taken.push((best, ri));
        out.push((idx, best));
    }
    // :991 — back into mover order. The keys are distinct indices, so the sort
    // is a total order and its stability does not matter.
    out.sort_by_key(|e| e.0);
    out.into_iter().map(|e| e.1).collect()
}
