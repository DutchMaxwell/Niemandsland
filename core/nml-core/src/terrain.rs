//! The board as a pure lookup — `terrain_overlay.get_terrain_at_world_position`
//! + `world_to_cell` (scripts/terrain_overlay.gd:1090-1116) over the recorded
//! cells/sandbox/cell_params, exactly the way `NodeRecheck.terrain_at_from_plain`
//! (tools/node_recheck.gd:236-266) rebuilds the Callable for a replay.
//!
//! Precision: the lookup's input is a Godot `Vector3`, so its components are
//! f32; `world_pos.x` then promotes to a f64 Variant and the rotation, the cell
//! division and the floor all run in f64. The sandbox half stays in f32 because
//! `Vector2` is `real_t` too (`TerrainRules.point_in_obb`
//! scripts/solo/terrain_rules.gd:139-144).

use std::collections::HashMap;

use serde::Deserialize;

use crate::geom::V3;

/// `TerrainRules.TerrainType` — terrain_rules.gd:24.
pub const NONE: i32 = 0;
pub const RUINS: i32 = 1;
pub const FOREST: i32 = 2;
pub const CONTAINER: i32 = 3;
pub const DANGEROUS: i32 = 4;

/// `TerrainRules.CELL_IN` terrain_rules.gd:26 — one terrain cell is 3"x3".
pub const CELL_IN: f64 = 3.0;
/// `TerrainRules.BASE_RING_SAMPLES` terrain_rules.gd:113.
pub const BASE_RING_SAMPLES: usize = 16;

/// `TerrainRules.gives_cover` terrain_rules.gd:54-55.
#[inline]
pub fn gives_cover(t: i32) -> bool {
    t == RUINS || t == FOREST
}

/// `TerrainRules.is_difficult` terrain_rules.gd:66-67.
#[inline]
pub fn is_difficult(t: i32) -> bool {
    t == FOREST
}

/// One freely placed shelf piece — `TerrainOverlay._sandbox_shapes()`, flattened
/// by `AiActRecorder._terrain_line` (act_recorder.gd:143-149).
#[derive(Debug, Clone, Deserialize)]
pub struct Obb {
    pub c: [f64; 2],
    pub he: [f64; 2],
    pub yaw: f64,
    #[serde(rename = "type")]
    pub kind: i32,
}

/// `TerrainOverlay`'s grid geometry — act_recorder.gd:150-153.
#[derive(Debug, Clone, Deserialize)]
pub struct CellParams {
    pub table_size_feet: [f64; 2],
    pub grid_rotation_degrees: f64,
    pub grid_size_inches: f64,
    pub inches_to_meters: f64,
}

/// The header's `"terrain"` object, deserialized as written.
#[derive(Debug, Clone, Deserialize)]
pub struct PlainTerrain {
    /// `[cx, cz, type]` triples — act_recorder.gd:137-139.
    pub cells: Vec<[f64; 3]>,
    pub sandbox: Vec<Obb>,
    pub cell_params: CellParams,
}

/// The board, precomputed the way `terrain_at_from_plain` precomputes it before
/// it returns the lambda (node_recheck.gd:237-251).
#[derive(Debug, Clone, Default)]
pub struct Terrain {
    cells: HashMap<(i64, i64), i32>,
    sandbox: Vec<Obb>,
    cell_m: f64,
    /// `-deg_to_rad(grid_rotation_degrees)`, i.e. the `-rot_rad` the lambda uses.
    neg_rot: f64,
    /// `grid_size / 2.0`, the half-offset the cell index adds.
    half_grid: f64,
    /// True when the header carried no terrain at all — `terrain_at.is_valid()`
    /// is then false and every caller takes its "no terrain seam" branch.
    absent: bool,
}

impl Terrain {
    /// The state of affairs when the recorder found no `TerrainOverlay`
    /// (`AiActRecorder._terrain_line` returns null): the Callable is invalid, so
    /// `_safe_advance`'s cover bonus never fires and `_crosses_difficult_plain`
    /// answers "never crosses" (battle_sim.gd:1595-1596).
    pub fn absent() -> Terrain {
        Terrain { absent: true, ..Terrain::default() }
    }

    #[inline]
    pub fn is_valid(&self) -> bool {
        !self.absent
    }

    pub fn build(p: &PlainTerrain) -> Terrain {
        let mut cells = HashMap::with_capacity(p.cells.len());
        for c in &p.cells {
            cells.insert((c[0] as i64, c[1] as i64), c[2] as i32);
        }
        let cp = &p.cell_params;
        let width_in = cp.table_size_feet[0] * 12.0;
        let height_in = cp.table_size_feet[1] * 12.0;
        let grid_in = cp.grid_size_inches;
        let cell_m = grid_in * cp.inches_to_meters;
        let rot_rad = cp.grid_rotation_degrees.to_radians();
        let mut grid_size =
            ((width_in * width_in + height_in * height_in).sqrt() / grid_in).ceil() as i64;
        if grid_size % 2 != 0 {
            grid_size += 1;
        }
        Terrain {
            cells,
            sandbox: p.sandbox.clone(),
            cell_m,
            neg_rot: -rot_rad,
            half_grid: grid_size as f64 / 2.0,
            absent: false,
        }
    }

    /// The lambda `terrain_at_from_plain` returns (node_recheck.gd:251-266).
    /// An absent board answers `NONE`, which is what an invalid Callable's
    /// callers fall back to on every path that reaches this at all.
    pub fn type_at(&self, p: V3) -> i32 {
        if self.absent {
            return NONE;
        }
        let (x, z) = (p[0] as f64, p[2] as f64);
        let rx = x * self.neg_rot.cos() - z * self.neg_rot.sin();
        let rz = x * self.neg_rot.sin() + z * self.neg_rot.cos();
        let cell = (
            (rx / self.cell_m + self.half_grid).floor() as i64,
            (rz / self.cell_m + self.half_grid).floor() as i64,
        );
        let t = self.cells.get(&cell).copied().unwrap_or(NONE);
        if t != NONE {
            return t;
        }
        // `Vector2(world_pos.x, world_pos.z)` — back to f32, `Vector2` is real_t.
        let q = [p[0], p[2]];
        for s in &self.sandbox {
            if point_in_obb(q, s) {
                return s.kind;
            }
        }
        NONE
    }
}

/// `TerrainRules.point_in_obb` terrain_rules.gd:139-144, in `Vector2`'s own f32.
fn point_in_obb(p: [f32; 2], s: &Obb) -> bool {
    let (yc, ys) = (s.yaw.cos() as f32, s.yaw.sin() as f32);
    let dx = [yc, -ys];
    let dz = [ys, yc];
    let d = [p[0] - s.c[0] as f32, p[1] - s.c[1] as f32];
    let dot_x = d[0] * dx[0] + d[1] * dx[1];
    let dot_z = d[0] * dz[0] + d[1] * dz[1];
    (dot_x as f64).abs() <= s.he[0] && (dot_z as f64).abs() <= s.he[1]
}

/// `TerrainRules.base_in_terrain` terrain_rules.gd:116-131 — the base CENTRE
/// plus a 16-point ring at the base edge; any sample of the wanted class counts,
/// because a base even slightly inside a piece of terrain is in it.
///
/// `class_check` is a plain fn pointer, the same specialisation the GDScript
/// gets from passing `TerrainRules.is_difficult` as the Callable.
pub fn base_in_terrain(centre: V3, radius: f64, t: &Terrain, class_check: fn(i32) -> bool) -> bool {
    if !t.is_valid() {
        return false;
    }
    if class_check(t.type_at(centre)) {
        return true;
    }
    if radius <= 0.0 {
        return false;
    }
    for k in 0..BASE_RING_SAMPLES {
        let ang = std::f64::consts::TAU * k as f64 / BASE_RING_SAMPLES as f64;
        // `Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)` — the f64 product
        // narrows in the constructor, then the add is f32.
        let off: V3 = [(ang.cos() * radius) as f32, 0.0, (ang.sin() * radius) as f32];
        let edge = crate::geom::add(centre, off);
        if class_check(t.type_at(edge)) {
            return true;
        }
    }
    false
}
