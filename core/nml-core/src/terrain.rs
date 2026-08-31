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

/// `TerrainRules.is_dangerous` terrain_rules.gd:68-69 — the p.12 test's class.
#[inline]
pub fn is_dangerous(t: i32) -> bool {
    t == DANGEROUS
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
    /// NML-1073 M5 D5-2a — `TerrainOverlay.get_wall_segments_world()` flattened
    /// (act_recorder.gd:210-218): one `[[ax, az], [bx, az]]` per segment in
    /// WORLD METRES. Absent from every corpus recorded before that rung, and the
    /// charge-move seam then plans on a board with no ruin walls at all.
    #[serde(default)]
    pub walls: Vec<[[f64; 2]; 2]>,
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
    /// `map_layout._calculate_grid_dimensions().x` — the grid is `n` x `n` cells.
    /// `SchoolTerrain.generate` stores exactly this number as `world["n"]`, and
    /// `NodeRecheck.los_blocked_from_plain` (node_recheck.gd:287-316) derives it
    /// back out of `cell_params` the same way `build` does below.
    n: i64,
    /// True when the header carried no terrain at all — `terrain_at.is_valid()`
    /// is then false and every caller takes its "no terrain seam" branch.
    absent: bool,
    /// The table in INCHES, `[x, y]` — `table_size_feet * 12`. This is the
    /// extent of the movement planner's 0-origin inch frame
    /// (solo_controller.gd:5960-5968 converts world metres + half-extents into
    /// it), which `mv::reach` rasterises onto.
    board_in: [f64; 2],
    /// `cell_params.inches_to_meters`.
    in2m: f64,
    /// NML-1073 M5 D5-2 — `TerrainOverlay.get_wall_segments_world()` in the
    /// movement planner's 0-origin INCH frame, the shape `plan_unit_step` wants
    /// (`walls_in`, solo_controller.gd:6165-6169). The act header writes the
    /// segments in WORLD METRES (act_recorder.gd, rung D5-2a); the conversion
    /// happens ONCE here so no caller can repeat it with the wrong offset.
    /// Empty when the header carried no `walls` key — every corpus recorded
    /// before D5-2a, and the reason the charge-move seam warns instead of
    /// pretending the board has no ruins.
    walls_in: Vec<[[f32; 2]; 2]>,
    /// NML-1155 — the bank's optional prop layer: each SOLID deployment prop's
    /// XZ incircle disc as `[centre_x_m, centre_z_m, radius_m]`, world metres
    /// (the dump writes table-centred inches — the bank `pieces` frame — and
    /// `set_bank_props` converts with the board's own `in2m`). Empty when the
    /// bank carried no `blockers` key: every bank recorded before NML-1155,
    /// which keeps the twin's blocked law byte-identical to before
    /// (default-preserving, like `walls_in` above).
    blockers_m: Vec<[f64; 3]>,
    /// NML-1152 step 4d — the bank's optional `blocker_boxes`: per probe-visible
    /// collider its REAL XZ footprint `[cx, cy, half_w, half_h, angle_rad,
    /// reach_m]`, world metres (the dump writes table-centred inches — the bank
    /// `pieces` frame — and `set_bank_props` converts with the board's own
    /// `in2m`; the angle rides as-is). Harvested from the bodies' actual
    /// CollisionShape3D + global transform (tools/terrain_bank_dump.gd
    /// `_collider_boxes`), so a wall body's 0.25" thickness and a container's
    /// exact outline ride the box — not the centreline `walls_in` carries nor
    /// the incircle `blockers_m` approximates. Empty when the bank carried no
    /// `blocker_boxes` key: every bank recorded before step 4d
    /// (default-preserving, like `blockers_m` above).
    blocker_boxes_m: Vec<[f64; 6]>,
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

    /// The table in inches, `[x, y]`. `[0, 0]` when the header carried no
    /// terrain — the caller must then not build a reach index.
    #[inline]
    pub fn board_in(&self) -> [f64; 2] {
        self.board_in
    }

    /// The board's wall segments in the planner's INCH frame. Empty = the
    /// header carried none (NOT "the board has none" — see `walls_in`).
    #[inline]
    pub fn walls_in(&self) -> &[[[f32; 2]; 2]] {
        &self.walls_in
    }

    /// `cell_params.inches_to_meters` — the metre-per-inch scale this board's
    /// inch frame was built with, so callers converting a METRE threshold into
    /// this frame (deployment wall clearance) use the board's own scale.
    #[inline]
    pub fn in2m(&self) -> f64 {
        self.in2m
    }

    /// Converts `TerrainOverlay.get_wall_segments_world()` — WORLD METRES,
    /// `[[ax, az], [bx, bz]]` per segment — into the inch frame and stores it.
    /// The conversion is `to_inch` itself, so a wall and a model position can
    /// never land in two different frames.
    pub fn set_walls_world_m(&mut self, raw: &[[[f64; 2]; 2]]) {
        self.walls_in = raw
            .iter()
            .map(|w| {
                [
                    self.to_inch([w[0][0] as f32, 0.0, w[0][1] as f32]),
                    self.to_inch([w[1][0] as f32, 0.0, w[1][1] as f32]),
                ]
            })
            .collect();
    }

    /// NML-1155 — loads the bank v2 keys (`tools/terrain_bank_dump.gd`):
    /// `walls` as `[x1, y1, x2, y2]` and `blockers` as `[x, y, r]`, both
    /// TABLE-CENTRED INCHES — the same centred inch frame as the bank's
    /// `pieces` (SchoolTerrain cell centres, school_terrain.gd:47-49). The
    /// scale is the board's own `in2m` (the school grid's 0.0254 — the same
    /// constant the dump divided by), so a wall, a blocker and a model
    /// position can never land in two different frames; the walls then ride
    /// `set_walls_world_m` (world metres → the planner inch frame) exactly
    /// like an act header's walls do. NML-1152 step 4d adds `blocker_boxes`
    /// (`[cx, cy, half_w, half_h, angle, reach]`, inches + radians) — the
    /// probe's real footprints, see the field doc. All keys are OPTIONAL — a
    /// bank dumped before NML-1155 carries none, and empty slices leave the
    /// board unchanged (default-preserving). NOTE: this OVERWRITES `walls_in`
    /// — the bank header's own `terrain.walls` is `[]` (act_recorder.gd:290),
    /// so don't call it on a board whose header walls matter. An absent/default
    /// board (in2m 0) keeps its empty layers — the no-overlay behaviour.
    pub fn set_bank_props(
        &mut self,
        walls: &[[f64; 4]],
        blockers: &[[f64; 3]],
        blocker_boxes: &[[f64; 6]],
    ) {
        if self.in2m <= 0.0 {
            return;
        }
        let world_walls: Vec<[[f64; 2]; 2]> = walls
            .iter()
            .map(|w| {
                [
                    [w[0] * self.in2m, w[1] * self.in2m],
                    [w[2] * self.in2m, w[3] * self.in2m],
                ]
            })
            .collect();
        self.set_walls_world_m(&world_walls);
        self.blockers_m = blockers
            .iter()
            .map(|b| [b[0] * self.in2m, b[1] * self.in2m, b[2] * self.in2m])
            .collect();
        self.blocker_boxes_m = blocker_boxes
            .iter()
            .map(|b| {
                [
                    b[0] * self.in2m,
                    b[1] * self.in2m,
                    b[2] * self.in2m,
                    b[3] * self.in2m,
                    b[4],
                    b[5] * self.in2m,
                ]
            })
            .collect();
    }

    /// The banked blocker discs, world metres — `deployment::prop_blocked`'s
    /// input. Empty = the bank carried no `blockers` key (NOT "the board has
    /// no props" — the mirror of the `walls_in` caveat).
    #[inline]
    pub fn blockers_m(&self) -> &[[f64; 3]] {
        &self.blockers_m
    }

    /// The banked blocker OBBs, world metres — `deployment::prop_blocked`'s
    /// input when present (`[cx, cz, half_w, half_h, angle_rad, reach]`; it
    /// falls back to the `blockers_m` discs when this is empty). Empty = the
    /// bank carried no `blocker_boxes` key (NOT "the board has no props" —
    /// the mirror of the `walls_in` caveat).
    #[inline]
    pub fn blocker_boxes_m(&self) -> &[[f64; 6]] {
        &self.blocker_boxes_m
    }

    /// A world point (metres, `x`/`z`) in the movement planner's 0-origin INCH
    /// frame: `(world + half_extent) / INCHES_TO_METERS`
    /// (solo_controller.gd:5960-5968).
    #[inline]
    pub fn to_inch(&self, p: V3) -> [f32; 2] {
        [
            (p[0] as f64 / self.in2m + self.board_in[0] * 0.5) as f32,
            (p[2] as f64 / self.in2m + self.board_in[1] * 0.5) as f32,
        ]
    }

    /// The inverse, at the caller's own height.
    #[inline]
    pub fn from_inch(&self, p: [f32; 2], y: f32) -> V3 {
        [
            ((p[0] as f64 - self.board_in[0] * 0.5) * self.in2m) as f32,
            y,
            ((p[1] as f64 - self.board_in[1] * 0.5) * self.in2m) as f32,
        ]
    }

    /// The grid width in cells — `SchoolTerrain.generate`'s `world["n"]`.
    #[inline]
    pub fn n(&self) -> i64 {
        self.n
    }

    // --- NML-1073 M5 D6a: the grid as `TerrainOverlay` itself holds it, for
    // `sight::zones_of`. `type_at` answers ONE point; the sight volumes need the
    // painted cells whole, in the grid's own frame and at the grid's own yaw.

    /// Every painted cell as `((cx, cz), type)`, in the RECORDED 0-based grid
    /// index — `AiActRecorder._terrain_line` act_recorder.gd:137-139.
    pub fn painted_cells(&self) -> impl Iterator<Item = ((i64, i64), i32)> + '_ {
        self.cells.iter().map(|(&c, &k)| (c, k))
    }

    /// Half the grid width in cells — the offset `TerrainOverlay._zone_volumes`
    /// (:1240) subtracts to key a cell in the grid's own centred frame.
    #[inline]
    pub fn half_grid_cells(&self) -> i64 {
        self.n / 2
    }

    /// One cell's edge in METRES (`GRID_SIZE_INCHES * INCHES_TO_METERS`).
    #[inline]
    pub fn cell_m(&self) -> f64 {
        self.cell_m
    }

    /// `deg_to_rad(grid_rotation_degrees)` — the grid's own yaw, which
    /// `VolumetricLos.cells_key` rotates a world point back by.
    #[inline]
    pub fn grid_yaw(&self) -> f64 {
        -self.neg_rot
    }

    /// How many freely placed sandbox pieces the header carried. NON-ZERO is a
    /// SEAM for the sight port: `TerrainOverlay._sandbox_volumes` (:1255-1273)
    /// turns each into its own box volume, and `sight::zones_of` builds grid
    /// zones only. Empty on every board of the reference corpus.
    #[inline]
    pub fn sandbox_pieces(&self) -> usize {
        self.sandbox.len()
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
        let mut out = Terrain {
            cells,
            sandbox: p.sandbox.clone(),
            cell_m,
            neg_rot: -rot_rad,
            half_grid: grid_size as f64 / 2.0,
            n: grid_size,
            absent: false,
            board_in: [width_in, height_in],
            in2m: cp.inches_to_meters,
            walls_in: Vec::new(),
            blockers_m: Vec::new(),
            blocker_boxes_m: Vec::new(),
        };
        out.set_walls_world_m(&p.walls);
        out
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

// ------------------------------------------------- the school 3" LOS grid ---
//
// `SchoolTerrain` (scripts/solo/school_terrain.gd) is the board `core_selfplay`
// plays on: the game's own symmetric map layouter, converted to a plain
// `{cells, n}` dict. It reads the SAME cells the header carries, but through
// its own two constants (`CELL_IN` 3.0, `IN2M` 0.0254) rather than through
// `cell_params` — the school table never rotates and its grid is always the 3"
// one, which is why `NodeRecheck.los_blocked_from_plain` (node_recheck.gd:
// 287-316) can rebuild the whole seam from `cells` plus a derived `n`.
//
// Precision, expression by expression (GDScript `float` is f64, `Vector2`/
// `Vector3` are `real_t` = f32):
//   `Vector2(a.x / IN2M, a.z / IN2M)` — f32 in, f64 divide, f32 back out.
//   `cell_of(av.x, av.y, n)`         — the f32 widens to f64 at the typed
//                                      `float` parameter, then `floor` in f64.
//   `av.distance_to(bv)`             — `Math::sqrt` in f32, widened on return.
//   `av.lerp(bv, float(i)/float(steps))` — the weight narrows to f32 and the
//                                      whole lerp runs in f32.

impl Terrain {
    /// `SchoolTerrain.cell_of` school_terrain.gd:52-53 — inches (relative to the
    /// TABLE CENTRE) to a cell index. `int(floor(...))` floors toward -inf.
    #[inline]
    pub fn school_cell_of(&self, x_in: f64, z_in: f64) -> (i64, i64) {
        (
            (x_in / CELL_IN + self.half_grid).floor() as i64,
            (z_in / CELL_IN + self.half_grid).floor() as i64,
        )
    }

    /// `SchoolTerrain.cell_centre_in` school_terrain.gd:48-49 — the inverse, in
    /// inches. `Vector2` is f32, so the product narrows.
    #[inline]
    pub fn school_cell_centre_in(&self, cell: (i64, i64)) -> [f32; 2] {
        [
            ((cell.0 as f64 - self.half_grid + 0.5) * CELL_IN) as f32,
            ((cell.1 as f64 - self.half_grid + 0.5) * CELL_IN) as f32,
        ]
    }

    /// `SchoolTerrain.los_blocked` school_terrain.gd:65-83 — centre-line block,
    /// v0: any RUINS, CONTAINER or FOREST cell STRICTLY between the endpoints
    /// blocks, sampled at 1"-ish steps. The two endpoint cells never block, so a
    /// unit inside a ruin sees out of it and can be seen.
    ///
    /// This is the seam `tools/core_selfplay.gd:675-679` stamps as
    /// `state["los_blocked"]`, read by `BattleSim._los_clear` on every scored
    /// candidate. An ABSENT board has no cells, so it answers "clear" for every
    /// pair — the same fall-open an invalid Callable gives `_los_clear`.
    pub fn los_blocked(&self, a: V3, b: V3) -> bool {
        // `Vector2(a.x / IN2M, a.z / IN2M)`: f64 divide, f32 store.
        let av = [(a[0] as f64 / crate::IN2M) as f32, (a[2] as f64 / crate::IN2M) as f32];
        let bv = [(b[0] as f64 / crate::IN2M) as f32, (b[2] as f64 / crate::IN2M) as f32];
        let ca = self.school_cell_of(av[0] as f64, av[1] as f64);
        let cb = self.school_cell_of(bv[0] as f64, bv[1] as f64);
        // `Vector2::distance_to` — sqrtf over the f32 squares, then widened.
        let (dx, dy) = (av[0] - bv[0], av[1] - bv[1]);
        let dist = (dx * dx + dy * dy).sqrt() as f64;
        // `maxi(int(dist), 1)` — `int()` truncates toward zero.
        let steps = (dist as i64).max(1);
        for i in 1..steps {
            // `av.lerp(bv, float(i) / float(steps))` — Godot's
            // `res.x += weight * (to.x - x)`, weight narrowed to f32 first.
            let w = (i as f64 / steps as f64) as f32;
            let px = av[0] + w * (bv[0] - av[0]);
            let py = av[1] + w * (bv[1] - av[1]);
            let c = self.school_cell_of(px as f64, py as f64);
            if c == ca || c == cb {
                continue;
            }
            let t = self.cells.get(&c).copied().unwrap_or(NONE);
            if t == RUINS || t == CONTAINER || t == FOREST {
                return true;
            }
        }
        false
    }

    /// `BattleSim.state_to_plain`'s `"los_pairs"` block, battle_sim.gd:1492-1506
    /// — one row per unit, one character per unit, `"0"` = the `los_blocked`
    /// seam says blocked, `"1"` = clear. Row/column `i` is the unit at index `i`
    /// of the KEY-SORTED unit keys (NML-1073 M3-0b, PR #383): a live Dictionary
    /// iterates in insertion order, but `JSON.stringify(sort_keys)` writes
    /// `"units"` back out key-sorted, so a reader keyed off the round-tripped
    /// dict read the wrong row past ~10 units ("p1_10" sorts before "p1_2").
    ///
    /// The unit centres are `BattleSim._centre_of` (battle_sim.gd:799-806), the
    /// arithmetic mean of the snapshot positions in f32. Godot's `Array.sort()`
    /// on Strings compares codepoint by codepoint; unit keys are ASCII, so
    /// Rust's byte-wise `str` ordering is the same order.
    pub fn los_pairs(&self, units: &[(String, Vec<[f64; 3]>)]) -> Vec<String> {
        let mut order: Vec<usize> = (0..units.len()).collect();
        order.sort_by(|a, b| units[*a].0.cmp(&units[*b].0));
        let centres: Vec<V3> = order.iter().map(|i| crate::geom::centre(&units[*i].1)).collect();
        let mut rows = Vec::with_capacity(centres.len());
        for a in &centres {
            let mut row = String::with_capacity(centres.len());
            for b in &centres {
                row.push(if self.los_blocked(*a, *b) { '0' } else { '1' });
            }
            rows.push(row);
        }
        rows
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::IN2M;

    /// The school table: 6x4 ft on the 3" grid — `cell_params` as
    /// `AiActRecorder._school_terrain_line` (act_recorder.gd:188-197) writes it.
    fn school(cells: &[(i64, i64, i32)]) -> Terrain {
        Terrain::build(&PlainTerrain {
            cells: cells.iter().map(|c| [c.0 as f64, c.1 as f64, c.2 as f64]).collect(),
            sandbox: vec![],
            walls: vec![],
            cell_params: CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
        })
    }

    fn at(x_in: f64, z_in: f64) -> V3 {
        [(x_in * IN2M) as f32, 0.0, (z_in * IN2M) as f32]
    }

    /// `map_layout._calculate_grid_dimensions()`: the 6x4 ft diagonal is 86.53",
    /// / 3" = 28.84 -> 29, rounded up to even -> 30. `SchoolTerrain.generate`
    /// stores that as `world["n"]`, and the terrain bank dump carries it so this
    /// derivation can be checked against the generator instead of assumed.
    #[test]
    fn the_school_grid_width_is_derived_from_the_table_diagonal() {
        assert_eq!(school(&[]).n(), 30);
        // and the two cell mappings are each other's inverse
        let t = school(&[]);
        for cell in [(0i64, 0i64), (13, 15), (14, 15), (29, 29)] {
            let c = t.school_cell_centre_in(cell);
            assert_eq!(t.school_cell_of(c[0] as f64, c[1] as f64), cell);
        }
    }

    /// The miniature red-green pair PR #386 pinned in GDScript
    /// (`test_los_blocked_rebuilds_from_terrain_and_answers_a_moved_point`):
    /// one RUINS cell at x in [-3", 0"), A at -6", B at +12". The root pair is
    /// blocked THROUGH the ruin; A rushed to +2" is past it and sees clear.
    #[test]
    fn one_ruin_between_two_units_blocks_and_a_rush_past_it_does_not() {
        let t = school(&[(14, 15, RUINS)]);
        let (a, b, moved) = (at(-6.0, 0.0), at(12.0, 0.0), at(2.0, 0.0));
        assert!(t.los_blocked(a, b));
        assert!(t.los_blocked(b, a));
        assert!(!t.los_blocked(moved, b));
        // a unit's own centre is never blocked from itself (steps == 1, no
        // sample in between)
        assert!(!t.los_blocked(a, a));
    }

    /// school_terrain.gd:64 — "endpoint cells never block: a unit inside a ruin
    /// or wood sees out of it and can be seen".
    #[test]
    fn the_endpoint_cells_never_block() {
        let t = school(&[(13, 15, FOREST), (19, 15, CONTAINER)]);
        assert!(!t.los_blocked(at(-6.0, 0.0), at(12.0, 0.0)));
        // ... but one cell further in does
        let t = school(&[(13, 15, FOREST), (16, 15, CONTAINER)]);
        assert!(t.los_blocked(at(-6.0, 0.0), at(12.0, 0.0)));
    }

    /// DANGEROUS is terrain but not a sight blocker (school_terrain.gd:80-82
    /// names RUINS, CONTAINER and FOREST, nothing else).
    #[test]
    fn only_ruins_container_and_forest_block_the_line() {
        for (kind, blocks) in
            [(RUINS, true), (FOREST, true), (CONTAINER, true), (DANGEROUS, false), (NONE, false)]
        {
            assert_eq!(
                school(&[(15, 15, kind)]).los_blocked(at(-6.0, 0.0), at(12.0, 0.0)),
                blocks,
                "terrain type {kind}"
            );
        }
    }

    /// battle_sim.gd:1492-1506 — row/column `i` is the `i`-th KEY-SORTED unit,
    /// not the `i`-th inserted one (NML-1073 M3-0b). "p1_10" sorts before
    /// "p1_2", which is exactly where the pre-PR-#383 reader went wrong.
    #[test]
    fn los_pairs_rows_follow_the_sorted_unit_keys() {
        let t = school(&[(14, 15, RUINS)]);
        // insertion order p1_2 (right of the ruin), p1_10 (left of it), p1_1
        // (left of it too); sorted order is p1_1, p1_10, p1_2.
        let units = vec![
            ("p1_2".to_string(), vec![[12.0 * IN2M, 0.0, 0.0]]),
            ("p1_10".to_string(), vec![[-6.0 * IN2M, 0.0, 0.0]]),
            ("p1_1".to_string(), vec![[-9.0 * IN2M, 0.0, 0.0]]),
        ];
        assert_eq!(t.los_pairs(&units), vec!["110", "110", "001"]);
    }

    /// `BattleSim._centre_of` — a multi-model unit is seen from the mean of its
    /// model positions, so two models straddling the ruin are read at the middle.
    #[test]
    fn los_pairs_reads_a_unit_from_its_model_centre() {
        let t = school(&[(14, 15, RUINS)]);
        let units = vec![
            ("a".to_string(), vec![[-9.0 * IN2M, 0.0, 0.0], [-3.0 * IN2M, 0.0, 0.0]]),
            ("b".to_string(), vec![[12.0 * IN2M, 0.0, 0.0]]),
        ];
        // the centre is -6", the same point the single-model case blocks from
        assert_eq!(t.los_pairs(&units), vec!["10", "01"]);
    }
}
