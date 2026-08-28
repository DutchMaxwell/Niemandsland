//! NML-1073 M5 D6a — PER-MODEL, PER-WEAPON SIGHTING for shooting.
//!
//! The table decides a volley's die count PER MODEL, not per unit: "All models
//! in a unit with line of sight to the target, and that have a weapon that is
//! within range of it, may fire at it" (GF Advanced Rules v3.5.1 p.8). The
//! trainer has always put `alive` in that slot (`sim::profiles_of`), so a unit
//! with three of five models behind a wood rolled five models' worth of dice.
//!
//! This module is the port of the two GDScript halves the table uses:
//!
//!   * `SoloController.sighted_models` (solo_controller.gd:7749-7770) — per
//!     ALIVE shooter model, the target's models sorted by distance, break at the
//!     first out-of-range one, count the model when `los` holds for any in-range
//!     target model. The range test is HORIZONTAL (x/z) only.
//!   * `VolumetricLos.has_los` (scripts/solo/volumetric_los.gd) — ONE 3D segment
//!     eye->eye between two cylinders, blocked by terrain VOLUMES and by the base
//!     cylinder of every OTHER unit's alive models, with the `<1"` closed-gap
//!     pass for two models of the same unit.
//!
//! WHAT THE PLAIN STATE CAN AND CANNOT CARRY. Three inputs of the table's own
//! query are not in the capture, and each one is an approximation stated here
//! rather than hidden in the code:
//!
//!   1. CONTAINER BOXES. `terrain_overlay._build_los_volumes` (:1183-1186) uses
//!      the exact 6"x3" OBB a placed container recorded in `_blocker_obbs`
//!      (:2841), and DROPS the container's painted cells that the OBB covers
//!      (:1238-1241). The OBB comes from the placed-object list, which no act
//!      line carries; only the 3"-quantised cells survive into `terrain.cells`.
//!      This port therefore builds containers from those cells, solid, at the
//!      same 2.5" height. Measured on `~/selfplay_out/qbe_ref`: keeping them
//!      agrees with the recorded per-shot `sighted` on 9 more shots than dropping
//!      them, and never on fewer.
//!   2. MODEL HEIGHTS. `_solo_model_base_mm` (main.gd:4243-4252) reads the base
//!      size off the army data; the capture carries only `radii`, the
//!      CIRCUMSCRIBING radius (`SeparationChecker.bounding_radius`
//!      separation_checker.gd:137-140). For a ROUND base the two are the same
//!      number (`radius = effective_mm / 2`), so `base_mm = r * 2000` is exact;
//!      for an OVAL base the circumscribed radius over-states the mean the
//!      height table wants, and this port therefore over-states an oval model's
//!      height.
//!   3. WEAPON BEARERS. `SoloController.alive_bearers_of` (:7720-7739) reads the
//!      per-MODEL loadout, which the capture does not carry — see
//!      `sim::sighted_profiles_of` for the approximation and its measured cost.
//!
//! PRECISION. Godot runs this query in `Vector2`/`Vector3`, i.e. f32; every
//! number here is f64. Only a pair sitting exactly on a range or footprint
//! boundary can part on that, and no such pair was seen on the reference corpus.

use std::collections::{HashMap, HashSet};

use crate::state::State;
use crate::terrain::{self, Terrain};

/// `VolumetricLos.INCHES_TO_METERS`.
pub const IN2M: f64 = 0.0254;
/// `VolumetricLos.MIN_SPAN_M` — nothing fits between two all-but-touching eyes.
const MIN_SPAN_M: f64 = 0.02;
/// `VolumetricLos.CLOSED_GAP_INCHES` 1.0, in metres.
const CLOSED_GAP_M: f64 = 0.0254;
/// `VolumetricLos.Y_EPS_M`.
const Y_EPS_M: f64 = 1e-6;
/// `SoloController.AIRCRAFT_TARGET_RANGE_PENALTY_IN` :110.
pub const AIRCRAFT_TARGET_RANGE_PENALTY_IN: f64 = 12.0;
/// `main.SOLO_LOS_DEFAULT_BASE_MM` :4237 — the floor `_solo_unit_los_height_m`
/// starts from, so a unit is never shorter than 32 mm infantry.
const DEFAULT_BASE_MM: f64 = 32.0;
/// `VolumetricLos.BASE_HEIGHT_TABLE` — (base mm, model height in inches).
const BASE_HEIGHT_TABLE: [[f64; 2]; 6] =
    [[25.0, 1.0], [32.0, 1.25], [40.0, 1.5], [50.0, 2.0], [60.0, 3.0], [100.0, 4.0]];
/// `TerrainRules.FOREST_HEIGHT_INCHES` / `RUIN_ZONE_HEIGHT_INCHES` /
/// `CONTAINER_HEIGHT_INCHES` (terrain_rules.gd:29-31), read through
/// `TerrainOverlay.terrain_volume_height_inches` (:1168-1176).
fn volume_height_in(kind: i32) -> f64 {
    match kind {
        terrain::FOREST => 3.4,
        terrain::RUINS => 6.0,
        terrain::CONTAINER => 2.5,
        _ => 0.0,
    }
}

/// `VolumetricLos.height_in_for_base_mm` — linear between rows, clamped outside.
pub fn height_in_for_base_mm(base_mm: f64) -> f64 {
    if base_mm <= BASE_HEIGHT_TABLE[0][0] {
        return BASE_HEIGHT_TABLE[0][1];
    }
    for i in 1..BASE_HEIGHT_TABLE.len() {
        let [hx, hy] = BASE_HEIGHT_TABLE[i];
        if base_mm <= hx {
            let [lx, ly] = BASE_HEIGHT_TABLE[i - 1];
            return ly + (hy - ly) * (base_mm - lx) / (hx - lx);
        }
    }
    BASE_HEIGHT_TABLE[BASE_HEIGHT_TABLE.len() - 1][1]
}

/// A model's volumetric height in METRES, off its captured base radius — see
/// approximation 2 in the module header.
#[inline]
pub fn model_height_m(radius_m: f64) -> f64 {
    height_in_for_base_mm(radius_m * 2000.0) * IN2M
}

/// One model as `VolumetricLos` sees it: a base circle extruded from where it
/// stands to its own height. The eye is the centre of the top disc.
#[derive(Clone, Copy, Debug)]
pub struct Cyl {
    pub c: [f64; 2],
    pub r: f64,
    pub y0: f64,
    pub y1: f64,
}

impl Cyl {
    #[inline]
    fn eye(&self) -> [f64; 3] {
        [self.c[0], self.y1, self.c[1]]
    }
}

/// A blocking model — `main._solo_los_blockers` :4192-4207. `unit` is the roster
/// index, which is all the `<1"` gap pass needs to tell two units apart.
#[derive(Clone, Copy, Debug)]
pub struct Blocker {
    pub cyl: Cyl,
    pub unit: usize,
    pub aircraft: bool,
}

/// One grid-painted terrain zone as an upright prism —
/// `TerrainOverlay._zone_volumes` :1225-1249. Cells are keyed in the GRID's own
/// frame (the world cell index minus half the grid), so a rotated table stays
/// exact; `solid` is `not terrain_is_area(type)` (:1140-1141).
#[derive(Debug)]
pub struct Zone {
    cells: HashSet<(i64, i64)>,
    cell_m: f64,
    yaw: f64,
    y1: f64,
    solid: bool,
}

/// `TerrainRules.cell_of(p.rotated(-yaw), cell_size)` — `VolumetricLos.cells_key`.
#[inline]
fn cell_of(p: [f64; 2], yaw: f64, cell_m: f64) -> (i64, i64) {
    let q = if yaw == 0.0 {
        p
    } else {
        let (s, c) = (-yaw).sin_cos();
        [p[0] * c - p[1] * s, p[0] * s + p[1] * c]
    };
    ((q[0] / cell_m).floor() as i64, (q[1] / cell_m).floor() as i64)
}

impl Zone {
    /// `VolumetricLos.segment_hits_cells` — the quarter-cell walk of the flat
    /// segment, each sample's interpolated height tested against the slab.
    fn hits(&self, a: [f64; 3], b: [f64; 3]) -> bool {
        let (dx, dz) = (b[0] - a[0], b[2] - a[2]);
        let span = (dx * dx + dz * dz).sqrt();
        if span < MIN_SPAN_M {
            return false;
        }
        let steps = (((span / (self.cell_m * 0.25)).ceil()) as i64).max(4);
        for i in 1..steps {
            let t = i as f64 / steps as f64;
            let y = a[1] + (b[1] - a[1]) * t;
            if y < -Y_EPS_M || y > self.y1 + Y_EPS_M {
                continue; // the line passes over (or under) the zone here
            }
            if self.cells.contains(&cell_of([a[0] + dx * t, a[2] + dz * t], self.yaw, self.cell_m)) {
                return true;
            }
        }
        false
    }

    /// `VolumetricLos.cyl_in_volume` — the model's EYE at or below the zone top
    /// and its BASE FOOTPRINT (not merely its centre) overlapping a painted
    /// cell. The footprint half is NML-1086 (#415, merged 27.08. 21:51): "a base
    /// planted in the wood is in the wood".
    ///
    /// THE RULES-VERSION FLIP, in the source the way `tools/los_gate.py` keeps
    /// its blocker-rule flip: `~/selfplay_out/qbe_ref` was recorded 27.08. 19:51,
    /// two hours BEFORE #415, so the table that played it used the CENTRE test.
    /// Substituting `0.0` for `cy.r` below reproduces that table and scores
    /// 513/525 recorded shots exactly, against 484/525 for the shipped rule —
    /// the whole of that 29-shot gap is the corpus predating the fix, not the
    /// port. This port follows the SHIPPED table; the gap closes on a re-record.
    fn holds(&self, cy: &Cyl) -> bool {
        if cy.y1 > self.y1 + Y_EPS_M {
            return false;
        }
        let (lo, hi) = (
            cell_of([cy.c[0] - cy.r, cy.c[1] - cy.r], self.yaw, self.cell_m),
            cell_of([cy.c[0] + cy.r, cy.c[1] + cy.r], self.yaw, self.cell_m),
        );
        let q = if self.yaw == 0.0 {
            cy.c
        } else {
            let (s, c) = (-self.yaw).sin_cos();
            [cy.c[0] * c - cy.c[1] * s, cy.c[0] * s + cy.c[1] * c]
        };
        for cx in lo.0..=hi.0 {
            for cz in lo.1..=hi.1 {
                if !self.cells.contains(&(cx, cz)) {
                    continue;
                }
                let cs = self.cell_m;
                let near = [
                    q[0].clamp(cx as f64 * cs, (cx + 1) as f64 * cs),
                    q[1].clamp(cz as f64 * cs, (cz + 1) as f64 * cs),
                ];
                if (near[0] - q[0]).hypot(near[1] - q[1]) <= cy.r {
                    return true;
                }
            }
        }
        false
    }
}

/// `VolumetricLos.slab_t_range` — the part of a->b inside the y-slab `[0, y1]`,
/// as `(t_low, t_high)`. `t_low > t_high` means the segment never enters it.
fn slab_t(a: [f64; 3], b: [f64; 3], y0: f64, y1: f64) -> (f64, f64) {
    let (lo, hi) = (y0 - Y_EPS_M, y1 + Y_EPS_M);
    let dy = b[1] - a[1];
    if dy.abs() < 1e-9 {
        return if a[1] >= lo && a[1] <= hi { (0.0, 1.0) } else { (1.0, 0.0) };
    }
    let (ta, tb) = ((lo - a[1]) / dy, (hi - a[1]) / dy);
    (0.0f64.max(ta.min(tb)), 1.0f64.min(ta.max(tb)))
}

/// `VolumetricLos.segment_intersects_circle`, flat.
fn seg_circle(p: [f64; 2], q: [f64; 2], c: [f64; 2], r: f64) -> bool {
    let s = [q[0] - p[0], q[1] - p[1]];
    let l2 = s[0] * s[0] + s[1] * s[1];
    let t = if l2 > 0.0 {
        (((c[0] - p[0]) * s[0] + (c[1] - p[1]) * s[1]) / l2).clamp(0.0, 1.0)
    } else {
        0.0
    };
    (p[0] + s[0] * t - c[0]).hypot(p[1] + s[1] * t - c[1]) <= r
}

/// `VolumetricLos.segment_hits_cyl` — slab-clip, then the flat circle test.
fn hits_cyl(a: [f64; 3], b: [f64; 3], cy: &Cyl) -> bool {
    let (t0, t1) = slab_t(a, b, cy.y0, cy.y1);
    if t0 > t1 {
        return false;
    }
    let at = |t: f64| [a[0] + (b[0] - a[0]) * t, a[2] + (b[2] - a[2]) * t];
    seg_circle(at(t0), at(t1), cy.c, cy.r)
}

/// `Geometry2D.segment_intersects_segment` — the crossing point, or `None`.
fn seg_seg(p1: [f64; 2], p2: [f64; 2], p3: [f64; 2], p4: [f64; 2]) -> Option<[f64; 2]> {
    let d1 = [p2[0] - p1[0], p2[1] - p1[1]];
    let d2 = [p4[0] - p3[0], p4[1] - p3[1]];
    let den = d1[0] * d2[1] - d1[1] * d2[0];
    if den.abs() < 1e-12 {
        return None;
    }
    let v = [p3[0] - p1[0], p3[1] - p1[1]];
    let t = (v[0] * d2[1] - v[1] * d2[0]) / den;
    let u = (v[0] * d1[1] - v[1] * d1[0]) / den;
    if !(0.0..=1.0).contains(&t) || !(0.0..=1.0).contains(&u) {
        return None;
    }
    Some([p1[0] + d1[0] * t, p1[1] + d1[1] * t])
}

/// `VolumetricLos.first_blocking_unit_key` — a model standing in the line, then
/// the closed-gap pass: a gap of less than 1" between two models of the SAME
/// unit counts as closed, and in 3D that wall is only as tall as the shorter of
/// the pair. `blockers` are pre-excluded (the shooter's and the target's own
/// units never block), so there is no per-call exclude list.
fn blocked_by_model(a: [f64; 3], b: [f64; 3], blockers: &[Blocker]) -> bool {
    let mut by_unit: HashMap<usize, Vec<&Blocker>> = HashMap::new();
    for bl in blockers {
        if bl.aircraft {
            continue; // an Aircraft base is transparent (GF v3.5.1 p.13)
        }
        if hits_cyl(a, b, &bl.cyl) {
            return true;
        }
        by_unit.entry(bl.unit).or_default().push(bl);
    }
    let (a2, b2) = ([a[0], a[2]], [b[0], b[2]]);
    let seg = [b2[0] - a2[0], b2[1] - a2[1]];
    let l2 = seg[0] * seg[0] + seg[1] * seg[1];
    for models in by_unit.values() {
        for i in 0..models.len() {
            for j in i + 1..models.len() {
                let (m, n) = (&models[i].cyl, &models[j].cyl);
                if (m.c[0] - n.c[0]).hypot(m.c[1] - n.c[1]) - m.r - n.r >= CLOSED_GAP_M {
                    continue;
                }
                let Some(hit) = seg_seg(a2, b2, m.c, n.c) else { continue };
                let t = if l2 > 0.0 {
                    (((hit[0] - a2[0]) * seg[0] + (hit[1] - a2[1]) * seg[1]) / l2).clamp(0.0, 1.0)
                } else {
                    0.0
                };
                if a[1] + (b[1] - a[1]) * t < m.y1.min(n.y1) {
                    return true;
                }
            }
        }
    }
    false
}

/// `VolumetricLos.has_los`. `to_aircraft` is the P6 rule: an Aircraft is
/// abstract, so nothing on the table hides one.
pub fn has_los(
    from: &Cyl,
    to: &Cyl,
    to_aircraft: bool,
    zones: &[Zone],
    blockers: &[Blocker],
) -> bool {
    let (a, b) = (from.eye(), to.eye());
    let d2 = (a[0] - b[0]).powi(2) + (a[1] - b[1]).powi(2) + (a[2] - b[2]).powi(2);
    if d2 < MIN_SPAN_M * MIN_SPAN_M {
        return true;
    }
    if to_aircraft {
        return true;
    }
    if blocked_by_model(a, b, blockers) {
        return false;
    }
    for z in zones {
        if !z.hits(a, b) {
            continue;
        }
        if z.solid {
            return false; // containers hard-block, own zone or not
        }
        // P4 area terrain: see INTO and OUT OF the zone you are in, just not
        // through someone else's.
        if z.holds(from) || z.holds(to) {
            continue;
        }
        return false;
    }
    true
}

/// `SoloController.sighted_models` — shooter models with BOTH range and sight to
/// at least one target model. `los` is injected so the geometry stays pure.
pub fn sighted_models(
    shooters: &[[f64; 3]],
    targets: &[[f64; 3]],
    range_m: f64,
    mut los: impl FnMut([f64; 3], [f64; 3]) -> bool,
) -> i64 {
    if shooters.is_empty() || targets.is_empty() {
        return 0;
    }
    let range2 = range_m * range_m;
    let mut order: Vec<usize> = Vec::with_capacity(targets.len());
    let mut n = 0;
    for sp in shooters {
        // Nearest target model first — most likely visible, cheapest to confirm.
        order.clear();
        order.extend(0..targets.len());
        order.sort_by(|&x, &y| {
            let d = |t: &[f64; 3]| {
                (t[0] - sp[0]).powi(2) + (t[1] - sp[1]).powi(2) + (t[2] - sp[2]).powi(2)
            };
            d(&targets[x]).total_cmp(&d(&targets[y]))
        });
        for &ti in &order {
            let tp = targets[ti];
            // HORIZONTAL range (solo_controller.gd:7765) — sorted by distance,
            // so everything after the first miss is farther still.
            if (tp[0] - sp[0]).powi(2) + (tp[2] - sp[2]).powi(2) > range2 {
                break;
            }
            if los(*sp, tp) {
                n += 1;
                break;
            }
        }
    }
    n
}

// ------------------------------------------- B3: assembly from the State ---

/// The board's sight volumes — one per contiguous zone of one painted type
/// (`TerrainOverlay._terrain_zones` :1307-1325 flood-fills 4-connected cells of
/// EQUAL type, and the see-in/out rule keys on the whole zone, so a merged one
/// would let a model see out of a FOREIGN wood). DANGEROUS is open ground and
/// never appears (`terrain_blocks_los` :1130-1133).
pub fn zones_of(t: &Terrain) -> Vec<Zone> {
    if !t.is_valid() {
        return Vec::new();
    }
    let cells: HashMap<(i64, i64), i32> = t
        .painted_cells()
        .filter(|&(_, k)| volume_height_in(k) > 0.0)
        .map(|(c, k)| ((c.0 - t.half_grid_cells(), c.1 - t.half_grid_cells()), k))
        .collect();
    let (mut seen, mut out) = (HashSet::new(), Vec::new());
    for (&start, &kind) in cells.iter() {
        if !seen.insert(start) {
            continue;
        }
        let (mut stack, mut comp) = (vec![start], HashSet::new());
        while let Some(c) = stack.pop() {
            comp.insert(c);
            for nb in [(c.0 + 1, c.1), (c.0 - 1, c.1), (c.0, c.1 + 1), (c.0, c.1 - 1)] {
                if cells.get(&nb) == Some(&kind) && seen.insert(nb) {
                    stack.push(nb);
                }
            }
        }
        out.push(Zone {
            cells: comp,
            cell_m: t.cell_m(),
            yaw: t.grid_yaw(),
            y1: volume_height_in(kind) * IN2M,
            solid: !(kind == terrain::FOREST || kind == terrain::RUINS),
        });
    }
    out
}

/// The largest base radius among a unit's alive models —
/// `main._solo_unit_base_radius_m` :4227-4234, the width of its sight cylinder.
pub fn unit_radius_m(state: &State, i: usize) -> f64 {
    state.radii[i].iter().copied().fold(0.0, f64::max)
}

/// The TALLEST alive model of a unit and its attached heroes, in metres —
/// `main._solo_unit_los_height_m` :4262-4275, floored at 32 mm infantry.
pub fn unit_height_m(state: &State, i: usize) -> f64 {
    let mut h = height_in_for_base_mm(DEFAULT_BASE_MM) * IN2M;
    for &m in std::iter::once(&i).chain(state.attached[i].iter()) {
        for &r in &state.radii[m] {
            h = h.max(model_height_m(r));
        }
    }
    h
}

/// Every OTHER unit's alive models as blocker cylinders —
/// `main._solo_los_blockers` :4192-4207. The two named units and their attached
/// heroes never block (p.5: you always see through your own unit and can always
/// see the target); a unit still in Ambush reserve is off-table and blocks
/// nothing (`dormant`).
pub fn blockers_of(state: &State, from: usize, to: usize) -> Vec<Blocker> {
    let mut excluded = HashSet::new();
    for &u in &[from, to] {
        excluded.insert(u);
        excluded.extend(state.attached[u].iter().copied());
    }
    let mut out = Vec::new();
    for i in 0..state.units() {
        if excluded.contains(&i) || state.dormant[i] {
            continue;
        }
        for (k, p) in state.positions[i].iter().enumerate() {
            let r = state.radii[i].get(k).copied().unwrap_or(0.016);
            out.push(Blocker {
                cyl: Cyl { c: [p[0], p[2]], r, y0: p[1], y1: p[1] + model_height_m(r) },
                unit: i,
                aircraft: state.aircraft[i],
            });
        }
    }
    out
}

/// `main._solo_sighted_count` :4125-4147 for ONE weapon: the member's alive
/// models that have both range and sight to the target unit, whose models
/// INCLUDE its attached heroes' (:4131-4135).
///
/// `reach_in` is the weapon's already-shortened reach; the base-EDGE slack
/// (:4141-4145, GF v3.5.1 p.4 "measure from the closest point") is added here,
/// which is also the fix for the port's centre-to-centre range gate.
/// `indirect` waives the sight half and keeps the range gate (:4136-4138).
#[allow(clippy::too_many_arguments)]
pub fn sighted_count(
    state: &State,
    zones: &[Zone],
    blockers: &[Blocker],
    member: usize,
    target: usize,
    reach_in: f64,
    indirect: bool,
) -> i64 {
    let mut targets: Vec<[f64; 3]> = Vec::new();
    for &t in std::iter::once(&target).chain(state.attached[target].iter()) {
        targets.extend(state.positions[t].iter().copied());
    }
    let (from_r, to_r) = (unit_radius_m(state, member), unit_radius_m(state, target));
    let (from_h, to_h) = (unit_height_m(state, member), unit_height_m(state, target));
    let to_air = state.aircraft[target];
    let range_m = reach_in * IN2M + from_r + to_r;
    sighted_models(&state.positions[member], &targets, range_m, |sp, tp| {
        indirect
            || has_los(
                &Cyl { c: [sp[0], sp[2]], r: from_r, y0: sp[1], y1: sp[1] + from_h },
                &Cyl { c: [tp[0], tp[2]], r: to_r, y0: tp[1], y1: tp[1] + to_h },
                to_air,
                zones,
                blockers,
            )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::terrain::{CellParams, Obb, PlainTerrain};

    const M: f64 = IN2M;

    fn at(x_in: f64, z_in: f64) -> [f64; 3] {
        [x_in * M, 0.0, z_in * M]
    }

    fn cyl(x_in: f64, z_in: f64, base_mm: f64) -> Cyl {
        let r = base_mm / 2000.0;
        Cyl { c: [x_in * M, z_in * M], r, y0: 0.0, y1: model_height_m(r) }
    }

    fn blocker(x_in: f64, z_in: f64, base_mm: f64, unit: usize) -> Blocker {
        Blocker { cyl: cyl(x_in, z_in, base_mm), unit, aircraft: false }
    }

    /// `VolumetricLos.BASE_HEIGHT_TABLE` — the rows, the clamps and one
    /// interpolation between rows.
    #[test]
    fn base_height_table_interpolates_between_rows_and_clamps_outside() {
        assert_eq!(height_in_for_base_mm(25.0), 1.0);
        assert_eq!(height_in_for_base_mm(10.0), 1.0);
        assert_eq!(height_in_for_base_mm(32.0), 1.25);
        assert_eq!(height_in_for_base_mm(60.0), 3.0);
        assert_eq!(height_in_for_base_mm(160.0), 4.0);
        assert!((height_in_for_base_mm(36.0) - 1.375).abs() < 1e-12);
    }

    /// `test_sighted_models_gates_per_model_behind_a_blocker`
    /// (test/solo_controller_test.gd:792-811), the counting half: the same four
    /// shooters, the same two targets, the same three answers.
    #[test]
    fn sighted_models_gates_per_model_and_by_range() {
        let shooters = [at(2.0, 0.0), at(5.0, 0.0), at(26.0, 0.0), at(29.0, 0.0)];
        let targets = [at(2.0, 12.0), at(26.0, 12.0)];
        // The gdUnit board's CONTAINER strip spans x in [0, 24)": the two
        // shooters past its end see, the two behind it do not.
        let blocked = |a: [f64; 3], _b: [f64; 3]| a[0] / M >= 24.0;
        assert_eq!(sighted_models(&shooters, &targets, 24.0 * M, blocked), 2);
        // Range gates too: at 6" nothing reaches a target 12" away.
        assert_eq!(sighted_models(&shooters, &targets, 6.0 * M, blocked), 0);
        // Open field: everyone in range fires.
        assert_eq!(sighted_models(&shooters, &targets, 24.0 * M, |_, _| true), 4);
        // RED for the caller: no shooters, or no targets, is silence.
        assert_eq!(sighted_models(&[], &targets, 24.0 * M, |_, _| true), 0);
        assert_eq!(sighted_models(&shooters, &[], 24.0 * M, |_, _| true), 0);
    }

    /// A model of a THIRD unit standing in the line blocks it — and dropping the
    /// blocker list (the RED of B2) opens the same line.
    #[test]
    fn a_third_units_model_blocks_the_line_and_only_the_blocker_list_says_so() {
        let (from, to) = (cyl(0.0, 0.0, 32.0), cyl(0.0, 12.0, 32.0));
        let wall = [blocker(0.0, 6.0, 32.0, 7)];
        assert!(!has_los(&from, &to, false, &[], &wall));
        assert!(has_los(&from, &to, false, &[], &[])); // RED: no blockers, clear
        // A blocker off the line does not block it.
        assert!(has_los(&from, &to, false, &[], &[blocker(4.0, 6.0, 32.0, 7)]));
        // P6: an Aircraft base is transparent, and an Aircraft TARGET is always
        // visible however the board is packed.
        let air = [Blocker { aircraft: true, ..wall[0] }];
        assert!(has_los(&from, &to, false, &[], &air));
        assert!(has_los(&from, &to, true, &[], &wall));
    }

    /// The Asgard height rule, as pure geometry: a 25 mm model (1.0" eye) does
    /// not stop two 60 mm models (3.0" eyes) looking at each other, and the same
    /// pair at the same height does.
    #[test]
    fn a_shorter_model_is_seen_over() {
        let (big_a, big_b) = (cyl(0.0, 0.0, 60.0), cyl(0.0, 12.0, 60.0));
        assert!(has_los(&big_a, &big_b, false, &[], &[blocker(0.0, 6.0, 25.0, 7)]));
        assert!(!has_los(&big_a, &big_b, false, &[], &[blocker(0.0, 6.0, 60.0, 7)]));
    }

    /// The closed-gap pass: two models of the SAME unit less than 1" apart close
    /// the lane between them, and the same two of DIFFERENT units do not.
    #[test]
    fn a_sub_inch_gap_between_two_models_of_one_unit_is_closed() {
        let (from, to) = (cyl(0.0, 0.0, 32.0), cyl(0.0, 12.0, 32.0));
        // 40 mm bases (0.787" radius, 1.5" eye — taller than the 1.25" line)
        // whose centres sit 2.0" apart: neither disc touches the lane at x = 0,
        // and the gap between their edges is 0.43".
        let pair = [blocker(-1.0, 6.0, 40.0, 7), blocker(1.0, 6.0, 40.0, 7)];
        assert!(has_los(&from, &to, false, &[], &[pair[0]])); // neither alone blocks
        assert!(!has_los(&from, &to, false, &[], &pair));
        let split = [pair[0], Blocker { unit: 8, ..pair[1] }];
        assert!(has_los(&from, &to, false, &[], &split)); // two units, no wall
        // Widen the same pair past 1" and the lane opens again.
        let wide = [blocker(-1.5, 6.0, 40.0, 7), blocker(1.5, 6.0, 40.0, 7)];
        assert!(has_los(&from, &to, false, &[], &wide));
    }

    fn board(cells: &[(i64, i64, i32)]) -> Terrain {
        Terrain::build(&PlainTerrain {
            cells: cells.iter().map(|&(x, z, k)| [x as f64, z as f64, k as f64]).collect(),
            sandbox: Vec::<Obb>::new(),
            cell_params: CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    /// `zones_of`: one volume per contiguous zone of one type, DANGEROUS never a
    /// volume, and the grid frame centred the way `_zone_volumes` centres it
    /// (a 6x4 table is a 30x30 grid, so cell 15 is world cell 0).
    #[test]
    fn zones_are_one_volume_per_contiguous_painted_patch() {
        let t = board(&[
            (15, 15, terrain::FOREST),
            (16, 15, terrain::FOREST),
            (20, 20, terrain::FOREST), // a SECOND wood, not touching the first
            (15, 20, terrain::DANGEROUS), // open ground, never a sight volume
            (10, 10, terrain::CONTAINER),
        ]);
        let z = zones_of(&t);
        assert_eq!(z.len(), 3);
        assert_eq!(z.iter().filter(|v| v.solid).count(), 1); // the container
        assert_eq!(z.iter().map(|v| v.cells.len()).sum::<usize>(), 4);
        let wood = z.iter().find(|v| v.cells.len() == 2).unwrap();
        assert!(wood.cells.contains(&(0, 0)) && wood.cells.contains(&(1, 0)));
        assert!((wood.y1 - 3.4 * M).abs() < 1e-12);
        assert!(zones_of(&Terrain::absent()).is_empty());
    }

    /// GF/AoF v3.5.1 p.12 — "units can see into and out of forests, but not
    /// through them", and a CONTAINER hard-blocks either way.
    #[test]
    fn area_terrain_is_seen_into_and_out_of_but_not_through() {
        let wood = zones_of(&board(&[(15, 15, terrain::FOREST)]));
        // World cell (0, 0) is x/z in [0, 3)". Two models on either side of it.
        let (west, east) = (cyl(-3.0, 1.5, 32.0), cyl(6.0, 1.5, 32.0));
        assert!(!has_los(&west, &east, false, &wood, &[]));
        let inside = cyl(1.5, 1.5, 32.0);
        assert!(has_los(&west, &inside, false, &wood, &[])); // see INTO
        assert!(has_los(&inside, &east, false, &wood, &[])); // see OUT OF
        let box_ = zones_of(&board(&[(15, 15, terrain::CONTAINER)]));
        assert!(!has_los(&west, &east, false, &box_, &[]));
        assert!(!has_los(&inside, &east, false, &box_, &[])); // solid, own zone or not
    }

    /// NML-1086 (#415): a base PLANTED in the wood is in the wood — the see-out
    /// exception reads the footprint, not the centre. A 60 mm model whose centre
    /// sits 0.2" outside the painted cell still sees out.
    #[test]
    fn a_base_overlapping_the_zone_edge_counts_as_inside_it() {
        let wood = zones_of(&board(&[(15, 15, terrain::FOREST)]));
        let west = cyl(-3.0, 1.5, 32.0);
        let edge = cyl(-0.2, 1.5, 60.0); // r = 1.18", centre 0.2" west of the cell
        assert!(edge.r > 0.2 * M);
        assert!(has_los(&edge, &west, false, &wood, &[]));
        // A 25 mm model at the same spot does NOT reach the cell (r = 0.49").
        let small = cyl(-0.6, 1.5, 25.0);
        assert!(small.r < 0.6 * M);
        let east = cyl(6.0, 1.5, 32.0);
        assert!(!has_los(&small, &east, false, &wood, &[]));
    }

    /// A model standing ON something taller than the wood looks OVER it — the
    /// whole point of the volumetric query (the slab clip comes up empty).
    #[test]
    fn an_eye_above_the_zone_looks_over_it() {
        let wood = zones_of(&board(&[(15, 15, terrain::FOREST)]));
        let mut west = cyl(-3.0, 1.5, 32.0);
        let mut east = cyl(6.0, 1.5, 32.0);
        assert!(!has_los(&west, &east, false, &wood, &[]));
        for c in [&mut west, &mut east] {
            c.y0 += 4.0 * M;
            c.y1 += 4.0 * M; // both on a 4" roof, eyes above the 3.4" canopy
        }
        assert!(has_los(&west, &east, false, &wood, &[]));
    }
}
