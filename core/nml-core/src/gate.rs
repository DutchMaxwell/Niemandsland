//! The CHARGE GATE as a pure function of the capture — the twin of
//! `BattleSim.charge_illegal_plain` (battle_sim.gd:1547-1568), which is itself
//! `SoloController.charge_candidate_illegal` (:1434-1447) read off the recorded
//! inputs. Ported line for line, in the live ORDER, with the live arithmetic.
//!
//! The five per-unit reads come from `State` (`aircraft`, `bands`, `shroud`,
//! `charge_no_difficult`, `charge_probe_r`); the board comes from `Terrain`,
//! the header's `terrain_at` Callable. Only `gap_in` / `from` / `to` are
//! imagined, which is exactly why a recorded root pair matrix cannot answer the
//! gate and this port has to exist.

use crate::combat::shrouded_reach;
use crate::geom::{self, V3};
use crate::state::State;
use crate::terrain::{base_in_terrain, is_difficult, Terrain, CELL_IN};

/// `SoloController.DIFFICULT_MOVE_CAP_IN` solo_controller.gd:63.
pub const DIFFICULT_MOVE_CAP_IN: f64 = 6.0;
/// `SoloController.INCHES_TO_METERS` solo_controller.gd:20.
pub const INCHES_TO_METERS: f64 = 0.0254;
/// The half-cell detour `_corridor_forced_through` probes on either side —
/// solo_controller.gd:2761 / battle_sim.gd:1585.
pub const CORRIDOR_DETOUR_IN: f64 = 4.0;

/// `BattleSim.charge_illegal_plain` battle_sim.gd:1547-1568.
///
/// `from`/`to` default to the pair's own snapshot centres when `None`, exactly
/// as the GDScript's `Vector3.INF` sentinel does (:1566-1567).
pub fn charge_illegal(
    state: &State,
    terrain: &Terrain,
    attacker: usize,
    victim: usize,
    gap_in: f64,
    from: Option<V3>,
    to: Option<V3>,
) -> bool {
    charge_illegal_tuned(state, terrain, attacker, victim, gap_in, from, to, true)
}

/// Same gate with the p.13 Strider/Flying exemption switchable — `honour_no_difficult`
/// is `true` in every shipping call. The `false` arm exists so the parity test can
/// PROVE the exemption is load-bearing instead of asserting green against a gate
/// that might be answering "legal" for the wrong reason (solo_controller.gd:2749).
#[allow(clippy::too_many_arguments)]
pub fn charge_illegal_tuned(
    state: &State,
    terrain: &Terrain,
    attacker: usize,
    victim: usize,
    gap_in: f64,
    from: Option<V3>,
    to: Option<V3>,
    honour_no_difficult: bool,
) -> bool {
    if state.aircraft[victim] {
        return true;
    }
    let band = state.bands[attacker].rush;
    if gap_in > melee_shroud_charge_in(band, state, victim) {
        return true;
    }
    // `_charge_capped_by_difficult` (solo_controller.gd:2746-2757)
    if gap_in <= DIFFICULT_MOVE_CAP_IN || gap_in.is_infinite() {
        return false;
    }
    if honour_no_difficult && state.charge_no_difficult[attacker] {
        return false;
    }
    let probe_r = state.charge_probe_r[attacker];
    let a = from.unwrap_or_else(|| geom::centre(&state.positions[attacker]));
    let b = to.unwrap_or_else(|| geom::centre(&state.positions[victim]));
    corridor_forced_through(a, b, probe_r, terrain)
}

/// `BattleSim._melee_shroud_charge_in_plain` battle_sim.gd:1572-1576 — an absent
/// pair means the victim carries no rule of the family, so the reach is the raw
/// band.
fn melee_shroud_charge_in(rush_in: f64, state: &State, victim: usize) -> f64 {
    match state.shroud[victim] {
        None => rush_in,
        Some([pen, floor]) => shrouded_reach(rush_in, pen, floor),
    }
}

/// `BattleSim._corridor_forced_through_plain` battle_sim.gd:1580-1594 — the
/// straight line AND both 4"-offset detours cross difficult ground.
pub fn corridor_forced_through(from: V3, to: V3, probe_r: f64, terrain: &Terrain) -> bool {
    if !crosses_difficult(from, to, probe_r, terrain) {
        return false;
    }
    // `Vector2(to.x - from.x, to.z - from.z)` — the Variant subtraction is f64,
    // the `Vector2` constructor narrows it back to real_t.
    let dirv: [f32; 2] = [
        (to[0] as f64 - from[0] as f64) as f32,
        (to[2] as f64 - from[2] as f64) as f32,
    ];
    if v2_length(dirv) < 0.001 {
        return false;
    }
    let perp = v2_normalized([-dirv[1], dirv[0]]);
    let mid = geom::mul(geom::add(from, to), 0.5);
    for side in [1.0f64, -1.0] {
        // `perp * (4.0 * INCHES_TO_METERS) * float(side)` — two separate f32
        // scalar multiplies, left to right.
        let scaled = v2_mul(perp, CORRIDOR_DETOUR_IN * INCHES_TO_METERS);
        let off = v2_mul(scaled, side);
        let m2: V3 = [
            (mid[0] as f64 + off[0] as f64) as f32,
            mid[1],
            (mid[2] as f64 + off[1] as f64) as f32,
        ];
        if !crosses_difficult(from, m2, probe_r, terrain)
            && !crosses_difficult(m2, to, probe_r, terrain)
        {
            return false;
        }
    }
    true
}

/// `BattleSim._crosses_difficult_plain` battle_sim.gd:1598-1612 —
/// `SoloController._path_crosses_terrain` (:6481) for `PathCheck.DIFFICULT`:
/// half-a-cell steps, edge-aware base probe, no terrain seam = never crosses.
pub fn crosses_difficult(a: V3, b: V3, radius_m: f64, terrain: &Terrain) -> bool {
    if !terrain.is_valid() {
        return false;
    }
    let span = v2_length([
        (b[0] as f64 - a[0] as f64) as f32,
        (b[2] as f64 - a[2] as f64) as f32,
    ]) as f64;
    let cell_m = CELL_IN * INCHES_TO_METERS;
    let steps = ((span / (cell_m * 0.5)).ceil() as i64).max(1);
    for i in 0..=steps {
        let p = lerp(a, b, i as f64 / steps as f64);
        if radius_m > 0.0 {
            if base_in_terrain(p, radius_m, terrain, is_difficult) {
                return true;
            }
        } else if is_difficult(terrain.type_at(p)) {
            return true;
        }
    }
    false
}

/// `Vector3::lerp` — `res.x += weight * (to.x - x)` in real_t; the f64 weight
/// narrows at the call boundary.
#[inline]
fn lerp(a: V3, b: V3, w: f64) -> V3 {
    let w = w as f32;
    [
        a[0] + w * (b[0] - a[0]),
        a[1] + w * (b[1] - a[1]),
        a[2] + w * (b[2] - a[2]),
    ]
}

#[inline]
fn v2_length(a: [f32; 2]) -> f32 {
    (a[0] * a[0] + a[1] * a[1]).sqrt()
}

#[inline]
fn v2_normalized(a: [f32; 2]) -> [f32; 2] {
    let lensq = a[0] * a[0] + a[1] * a[1];
    if lensq == 0.0 {
        return [0.0, 0.0];
    }
    let len = lensq.sqrt();
    [a[0] / len, a[1] / len]
}

#[inline]
fn v2_mul(a: [f32; 2], s: f64) -> [f32; 2] {
    let s = s as f32;
    [a[0] * s, a[1] * s]
}
