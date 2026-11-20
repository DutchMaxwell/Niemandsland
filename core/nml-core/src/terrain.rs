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


use serde::{Deserialize, Serialize};

use crate::acts::{rule_on, EPOCH_72_PLAYTEST_RULES, EPOCH_73_V36};
use crate::geom::V3;
use crate::mv::tier::{HighSide, TierEdge, TierKind};

/// `TerrainRules.TerrainType` — terrain_rules.gd:24.
pub const NONE: i32 = 0;
pub const RUINS: i32 = 1;
pub const FOREST: i32 = 2;
pub const CONTAINER: i32 = 3;
/// One wall segment in the planner's inch frame, as `Terrain::walls_in` stores it.
pub type WallSeg = [[f32; 2]; 2];
/// `TerrainRules.CONTAINER_HEIGHT_INCHES` - what a climb over a container's edge costs a move.
pub const CONTAINER_HEIGHT_IN: f64 = 2.5;
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

/// Rules 3.6 (EPOCH_73_V36) — the p.12 terrain class ruins join at 3.6: a
/// model that walks into or through one risks the Dangerous test.
#[inline]
pub fn is_unstable(t: i32) -> bool {
    t == RUINS
}

/// The untyped class — "within 1\" of terrain" with NO kind restriction
/// (aof "Grounded Speed", `rules_mechanics_aof.json`'s own
/// `terrain_within_in` proximity): any cell type but NONE.
#[inline]
pub fn is_any(t: i32) -> bool {
    t != NONE
}

/// `TerrainRules.is_forbidden_rest` terrain_rules.gd:80-89 — the class a model
/// may not END its move standing in. RUINS was struck off in 2026-07-16 (a
/// model MAY stand in a ruin; only its WALL segments block) and DANGEROUS in
/// Windows playtest bug 4b (OPR p.12 allows ending a move there, it only costs
/// the test), so only the solid CONTAINER is left.
#[inline]
pub fn is_forbidden_rest(t: i32) -> bool {
    t == CONTAINER
}

/// One freely placed shelf piece — `TerrainOverlay._sandbox_shapes()`, flattened
/// by `AiActRecorder._terrain_line` (act_recorder.gd:143-149).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Obb {
    pub c: [f64; 2],
    pub he: [f64; 2],
    pub yaw: f64,
    #[serde(rename = "type")]
    pub kind: i32,
    /// The walkable floor slabs of a multi-storey free ruin (`TerrainOverlay._sandbox_volumes`): absent from every
    /// header before step 22c, and from every piece without upper floors.
    #[serde(default)]
    pub slabs: Vec<Slab>,
}

/// One floor slab of a free ruin - a thin SOLID box from `y0` to `y1` (metres), `yaw` as in `Obb`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Slab {
    pub c: [f64; 2],
    pub he: [f64; 2],
    pub yaw: f64,
    pub y0: f64,
    pub y1: f64,
}

/// F-CONT (rules 3.6, `EPOCH_73_V36`) — one placed container's exact 6"x3" box, `TerrainOverlay._blocker_obbs`
/// flattened by `AiActRecorder._container_boxes`: world metres, `yaw` as in `Obb`. Always solid, 2.5" tall.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContainerObb {
    pub c: [f64; 2],
    pub he: [f64; 2],
    pub yaw: f64,
}

/// `TerrainOverlay`'s grid geometry — act_recorder.gd:150-153.
///
/// `Default` (all zeros) exists only so `PlainTerrain` can derive it for the `..Default::default()` filler of a
/// literal; a board always states its own `cell_params`.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct CellParams {
    pub table_size_feet: [f64; 2],
    pub grid_rotation_degrees: f64,
    pub grid_size_inches: f64,
    pub inches_to_meters: f64,
}

/// Heightfield plan step 1 - a generated tier board as the header carries it (`boardgen::Layout`, materialised): one
/// level per (x, z), row-major, board-centred, grid yaw 0. Data only; nothing reads it yet.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct TierGrid {
    pub nx: u16,
    pub nz: u16,
    /// Edge of one tier cell, inches.
    pub cell_in: f64,
    /// Height of each cell above the table, inches; `nx * nz` entries, row-major.
    pub level_in: Vec<f64>,
    /// `[low, high]` cell indices of every ladder (one level apart).
    #[serde(default)]
    pub ladders: Vec<[u16; 2]>,
    /// `[low, high]` cell indices of every stair (one level apart).
    #[serde(default)]
    pub stairs: Vec<[u16; 2]>,
}

/// One solid block of a tier board: board-centred inches, rising from the table to `top_in`. Sight and the planner see
/// the same blocks (steps 10b, 11).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct TierBox {
    pub lo: [f64; 2],
    pub hi: [f64; 2],
    pub top_in: f64,
}

impl TierGrid {
    fn level(&self, x: usize, z: usize) -> f64 {
        self.level_in.get(z * usize::from(self.nx) + x).copied().unwrap_or(0.0)
    }

    /// The corner of grid vertex `(i, j)`, board-centred inches.
    fn vertex(&self, i: usize, j: usize) -> [f64; 2] {
        [(i as f64 - f64::from(self.nx) / 2.0) * self.cell_in, (j as f64 - f64::from(self.nz) / 2.0) * self.cell_in]
    }

    /// Heightfield plan step 6 - the raised cells as solid blocks: a row run of one level is one block, and the same run
    /// in the next row grows it (fewer blocks = fewer sight zones). Ground cells make no block.
    pub fn boxes(&self) -> Vec<TierBox> {
        let (nx, nz) = (usize::from(self.nx), usize::from(self.nz));
        let mut runs: Vec<(usize, usize, usize, usize, f64)> = Vec::new(); // x0, x1, z0, z1 (all exclusive end), level
        for z in 0..nz {
            let mut x = 0;
            while x < nx {
                let level = self.level(x, z);
                let mut end = x + 1;
                while level > 0.0 && end < nx && self.level(end, z) == level {
                    end += 1;
                }
                if level > 0.0 {
                    match runs.iter_mut().find(|r| r.3 == z && (r.0, r.1, r.4) == (x, end, level)) {
                        Some(r) => r.3 = z + 1,
                        None => runs.push((x, end, z, z + 1, level)),
                    }
                }
                x = end;
            }
        }
        runs.into_iter().map(|(x0, x1, z0, z1, top_in)| TierBox { lo: self.vertex(x0, z0), hi: self.vertex(x1, z1), top_in }).collect()
    }

    /// Heightfield plan step 6 - every cell border whose two sides differ, as `mv::tier` edges in board-centred inches.
    /// A border with a ladder is a `Ladder` edge of its own; every other one is a `Cliff`, and a straight contour of
    /// equal height and side is ONE edge (so a leg through a grid vertex on it still crosses). Vertical contours first
    /// (running +z), then horizontal ones (running +x), each in grid order.
    pub fn edges(&self) -> Vec<TierEdge> {
        let (nx, nz) = (usize::from(self.nx), usize::from(self.nz));
        let ladder = |lo: usize, hi: usize| self.ladders.iter().any(|p| (usize::from(p[0]), usize::from(p[1])) == (lo, hi));
        let mut out = Vec::new();
        for vertical in [true, false] {
            for line in 1..if vertical { nx } else { nz } {
                // runs along this line: (first position, end position, rise, high side is the positive one, ladder)
                let mut runs: Vec<(usize, usize, f64, bool, bool)> = Vec::new();
                for p in 0..if vertical { nz } else { nx } {
                    let (before, after) = if vertical { ((line - 1, p), (line, p)) } else { ((p, line - 1), (p, line)) };
                    let (lb, la) = (self.level(before.0, before.1), self.level(after.0, after.1));
                    if lb == la {
                        continue;
                    }
                    let (high_after, ids) = (la > lb, (before.1 * nx + before.0, after.1 * nx + after.0));
                    let lad = if high_after { ladder(ids.0, ids.1) } else { ladder(ids.1, ids.0) };
                    match runs.last_mut() {
                        Some(r) if !lad && !r.4 && r.1 == p && r.2 == (la - lb).abs() && r.3 == high_after => r.1 = p + 1,
                        _ => runs.push((p, p + 1, (la - lb).abs(), high_after, lad)),
                    }
                }
                for (p0, p1, dy_in, high_after, lad) in runs {
                    let (a, b) = if vertical { (self.vertex(line, p0), self.vertex(line, p1)) } else { (self.vertex(p0, line), self.vertex(p1, line)) };
                    // `Left` = positive cross product of (b - a, point - a) in the (x, z) frame: east of a +z run is Right, south of a +x run is Left
                    let high = if high_after == vertical { HighSide::Right } else { HighSide::Left };
                    out.push(TierEdge { a, b, dy_in, high, kind: if lad { TierKind::Ladder } else { TierKind::Cliff } });
                }
            }
        }
        out
    }
}

/// The header's `"terrain"` object, deserialized as written.
///
/// Build a literal with `..Default::default()` after the fields you set (`cell_params` always among them): a field
/// added later then does not break it.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
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
    /// NML-1163 — the BANK's own drawing list, `[kind, cx_in, cz_in, w_in,
    /// h_in, rot_deg]` in table-centred INCHES (`SchoolTerrain.generate(seed)
    /// ["pieces"]`, the list `selfplay.load_board` returns third). A banked
    /// board paints its terrain into `cells` and leaves `sandbox` EMPTY, so
    /// `tokens::build` had no pieces to export and wrote 18 zero rows on every
    /// live state. Absent from every act header ever recorded — hence
    /// `default`, and hence `Terrain::pieces`'s fall-back to `sandbox`.
    #[serde(default)]
    pub pieces: Vec<[f64; 6]>,
    /// F-CONT — the header's `containers` (written from `EPOCH_73_V36`; absent from every older recording).
    #[serde(default)]
    pub containers: Vec<ContainerObb>,
    /// Heightfield plan step 1 - the generated tier board, absent from every header written so far = today's flat
    /// behaviour (`None`).
    #[serde(default)]
    pub tiers: Option<TierGrid>,
    pub cell_params: CellParams,
}

/// The board, precomputed the way `terrain_at_from_plain` precomputes it before
/// it returns the lambda (node_recheck.gd:237-251).
#[derive(Debug, Clone, Default)]
pub struct Terrain {
    /// Lookup-only on the hot path (`type_at`, `los_blocked`, the move gates). Its iteration order reaches no outcome:
    /// `painted_cells` feeds callers that re-collect into their own maps (`objectives::Cells`, `sight::zones_of`), and
    /// `pieces_from_cells` sorts its keys before use.
    cells: crate::fasthash::FastMap<(i64, i64), i32>,
    sandbox: Vec<Obb>,
    /// NML-1163 — `PlainTerrain::pieces` in the same WORLD-METRE frame
    /// `sandbox` uses, so `Terrain::pieces` can answer with one slice type.
    bank: Vec<Obb>,
    /// F-CONT — `PlainTerrain::containers`; read by the sight volumes only (`type_at` never looks at them, as the table's
    /// `get_terrain_at_world_position` does not).
    containers: Vec<ContainerObb>,
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
    /// NML-1152 step 6a — the same segments in WORLD METRES at the f32 Vector2
    /// boundary (main.gd:2316 `get_wall_segments_world()`'s own shape): the
    /// raw f64 product narrowed ONCE at load. `deployment` reads this for the
    /// wall-bisect veto — re-deriving from `walls_in` would round-trip through
    /// the corner-origin inch frame (two extra f32 quantizations + a
    /// `board_in/2` offset) and no longer be the values the step-5b parity
    /// replay verified. Filled together with `walls_in`; empty under the same
    /// conditions.
    walls_world: Vec<[[f32; 2]; 2]>,
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
    /// Heightfield plan step 5 - `PlainTerrain::tiers` as written (`tier_in_at` reads it); `None` = a flat board.
    tiers: Option<TierGrid>,
    /// Heightfield plan step 6 - the blocks and the contours of `tiers`, derived once at `build` (empty on a flat board).
    tier_boxes: Vec<TierBox>,
    tier_edges: Vec<TierEdge>,
    /// Heightfield plan step 11b - `walls_in` plus the tier cliffs, for the readers that must keep a base off a sheer edge
    /// (`walls_in_tiered`). Filled only on a board with tier edges; a flat board answers `walls_in` itself.
    walls_tiered_in: Vec<WallSeg>,
    /// Content identity for memos keyed on a board: every `build` / `absent` / content-changing setter mints a fresh
    /// value, a clone keeps it. 0 = a bare `Default`, which no memo trusts.
    uid: u64,
}

static NEXT_UID: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(1);

fn fresh_uid() -> u64 {
    NEXT_UID.fetch_add(1, std::sync::atomic::Ordering::Relaxed)
}

impl Terrain {
    /// See the `uid` field: equal non-zero values mean equal content.
    #[inline]
    pub fn uid(&self) -> u64 {
        self.uid
    }

    /// The state of affairs when the recorder found no `TerrainOverlay`
    /// (`AiActRecorder._terrain_line` returns null): the Callable is invalid, so
    /// `_safe_advance`'s cover bonus never fires and `_crosses_difficult_plain`
    /// answers "never crosses" (battle_sim.gd:1595-1596).
    pub fn absent() -> Terrain {
        Terrain { absent: true, uid: fresh_uid(), ..Terrain::default() }
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

    /// Heightfield plan step 5 - the height of the tier under a point, inches above the table; `0.0` on a board without
    /// tiers and off the grid. `x_in` / `z_in` are the world frame in inches: the grid is board-centred with yaw 0.
    /// A cell is half open, so a point exactly on a border belongs to the cell on its positive side. Nothing reads this
    /// yet; `surface_y_m` (step 10) will.
    pub fn tier_in_at(&self, x_in: f64, z_in: f64) -> f64 {
        let Some(t) = &self.tiers else { return 0.0 };
        let (fx, fz) = ((x_in / t.cell_in) + f64::from(t.nx) / 2.0, (z_in / t.cell_in) + f64::from(t.nz) / 2.0);
        // written as "inside" so a NaN, an infinite cell edge or an empty grid all fall out as ground
        if !(fx >= 0.0 && fz >= 0.0 && fx < f64::from(t.nx) && fz < f64::from(t.nz)) {
            return 0.0;
        }
        t.level_in.get(fz as usize * usize::from(t.nx) + fx as usize).copied().unwrap_or(0.0)
    }

    /// Heightfield plan step 6 - the solid blocks of the tier board (board-centred inches). Empty on a flat board.
    #[inline]
    pub fn tier_boxes(&self) -> &[TierBox] {
        &self.tier_boxes
    }

    /// Heightfield plan step 6 - the cliffs and ladders between tiers (board-centred inches, see `TierGrid::edges`).
    #[inline]
    pub fn tier_edges(&self) -> &[TierEdge] {
        &self.tier_edges
    }

    /// The board's wall segments in the planner's INCH frame. Empty = the
    /// header carried none (NOT "the board has none" — see `walls_in`).
    #[inline]
    pub fn walls_in(&self) -> &[[[f32; 2]; 2]] {
        &self.walls_in
    }

    /// Heights B2 (GF p.11): `walls_in` split into the walls and the container EDGES, which the table's planner
    /// climbs (`solo_controller._is_ledge_edge`). The header carries no container list, only the painted cells and the
    /// wall segments, so an edge is a segment with container ground a hair (1 cm) to either side of its midpoint.
    pub fn walls_and_ledges(&self) -> (Vec<WallSeg>, Vec<WallSeg>) {
        let (mut walls, mut ledges) = (Vec::new(), Vec::new());
        for (w, m) in self.walls_in.iter().zip(&self.walls_world) {
            let d = [m[1][0] - m[0][0], m[1][1] - m[0][1]];
            let len = d[0].hypot(d[1]).max(f32::EPSILON);
            let (mid, n) = ([(m[0][0] + m[1][0]) * 0.5, (m[0][1] + m[1][1]) * 0.5], [-d[1] / len * 0.01, d[0] / len * 0.01]);
            let edge = [1.0f32, -1.0].iter().any(|s| self.type_at([mid[0] + s * n[0], 0.0, mid[1] + s * n[1]]) == CONTAINER);
            if edge { ledges.push(*w) } else { walls.push(*w) }
        }
        (walls, ledges)
    }

    /// Heightfield plan step 11 - a tier edge as a planner segment: board-centred inches into the 0-origin inch frame.
    fn tier_seg_in(&self, e: &crate::mv::tier::TierEdge) -> WallSeg {
        let h = [self.board_in[0] * 0.5, self.board_in[1] * 0.5];
        [[(e.a[0] + h[0]) as f32, (e.a[1] + h[1]) as f32], [(e.b[0] + h[0]) as f32, (e.b[1] + h[1]) as f32]]
    }

    /// Heightfield plan step 11 - the ladders of a tier board as priced climbs: `(segment, rise in inches)` in the
    /// planner's inch frame (the frame of `walls_in`). Empty on a flat board.
    pub fn tier_ledges_in(&self) -> Vec<(WallSeg, f64)> {
        let ladders = self.tier_edges.iter().filter(|e| e.kind == crate::mv::tier::TierKind::Ladder);
        ladders.map(|e| (self.tier_seg_in(e), e.dy_in)).collect()
    }

    /// Heightfield plan step 11 - the cliffs of a tier board (every tier edge that is not a ladder: sheer, not
    /// climbable, both ways) as wall segments in the planner's inch frame. Empty on a flat board.
    pub fn tier_walls_in(&self) -> Vec<WallSeg> {
        let cliffs = self.tier_edges.iter().filter(|e| e.kind == crate::mv::tier::TierKind::Cliff);
        cliffs.map(|e| self.tier_seg_in(e)).collect()
    }

    /// Heightfield plan step 11b - the walls a base may not rest against or be pushed through: `walls_in` plus the cliffs
    /// of a tier board (R10: a base never ends partly over a sheer edge). A ladder is no wall. On a board with no tier
    /// edges this IS `walls_in`, so every flat board and corpus reads exactly what it read.
    #[inline]
    pub fn walls_in_tiered(&self) -> &[WallSeg] {
        if self.tier_edges.is_empty() { &self.walls_in } else { &self.walls_tiered_in }
    }

    /// `walls_in_tiered` from `EPOCH_94_PARITY_BATCH`, `walls_in` below it (the epoch-gated readers).
    #[inline]
    pub fn walls_in_at(&self, rules_epoch: u32) -> &[WallSeg] {
        if rule_on(rules_epoch, crate::acts::EPOCH_94_PARITY_BATCH) { self.walls_in_tiered() } else { &self.walls_in }
    }

    /// The board's wall segments in WORLD METRES, f32 at the Vector2 boundary
    /// — the load-time narrowing of the raw values (step 6a, see the field doc).
    #[inline]
    pub fn walls_world_m(&self) -> &[[[f32; 2]; 2]] {
        &self.walls_world
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
        self.uid = fresh_uid();
        self.walls_in = raw
            .iter()
            .map(|w| {
                [
                    self.to_inch([w[0][0] as f32, 0.0, w[0][1] as f32]),
                    self.to_inch([w[1][0] as f32, 0.0, w[1][1] as f32]),
                ]
            })
            .collect();
        self.walls_world = raw
            .iter()
            .map(|w| {
                [
                    [w[0][0] as f32, w[0][1] as f32],
                    [w[1][0] as f32, w[1][1] as f32],
                ]
            })
            .collect();
        self.walls_tiered_in = if self.tier_edges.is_empty() { Vec::new() } else { self.walls_in.iter().copied().chain(self.tier_walls_in()).collect() };
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
        self.uid = fresh_uid();
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

    /// The pieces themselves — `tokens::terrain_token` (NML-1073 M3-6b) reads
    /// `c`/`he`/`yaw`/`kind` straight off them, the same `Obb`s `type_at` walks.
    #[inline]
    pub fn sandbox(&self) -> &[Obb] {
        &self.sandbox
    }

    /// F-CONT — the placed containers' exact boxes the header carried (empty before `EPOCH_73_V36` recordings).
    #[inline]
    pub fn containers(&self) -> &[ContainerObb] {
        &self.containers
    }

    /// NML-1163 — the pieces `tokens::terrain_token` exports: the BANKED
    /// drawing list when the board carried one, else the header's freely
    /// placed `sandbox` (the pre-NML-1163 reading, and still the only one an
    /// act-corpus header has). The two never coexist — a bank writes `cells` +
    /// `pieces` with `sandbox: []`, a header writes `sandbox` with no
    /// `pieces` — so the fall-back is a choice, not a merge.
    pub fn pieces(&self) -> &[Obb] {
        if self.bank.is_empty() {
            &self.sandbox
        } else {
            &self.bank
        }
    }

    pub fn build(p: &PlainTerrain) -> Terrain {
        let mut cells = crate::fasthash::FastMap::with_capacity_and_hasher(p.cells.len(), Default::default());
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
        let mut bank: Vec<Obb> = p
            .pieces
            .iter()
            .map(|q| Obb {
                c: [q[1] * crate::IN2M, q[2] * crate::IN2M],
                he: [q[3] * 0.5 * crate::IN2M, q[4] * 0.5 * crate::IN2M],
                yaw: q[5].to_radians(),
                kind: q[0] as i32,
                slabs: Vec::new(),
            })
            .collect();
        if bank.is_empty() && p.sandbox.is_empty() {
            bank = pieces_from_cells(&cells, cell_m, rot_rad, grid_size as f64 / 2.0);
        }
        let mut out = Terrain {
            cells,
            sandbox: p.sandbox.clone(),
            bank,
            containers: p.containers.clone(),
            cell_m,
            neg_rot: -rot_rad,
            half_grid: grid_size as f64 / 2.0,
            n: grid_size,
            absent: false,
            board_in: [width_in, height_in],
            in2m: cp.inches_to_meters,
            walls_in: Vec::new(),
            walls_world: Vec::new(),
            blockers_m: Vec::new(),
            blocker_boxes_m: Vec::new(),
            tiers: p.tiers.clone(),
            tier_boxes: p.tiers.as_ref().map_or_else(Vec::new, TierGrid::boxes),
            tier_edges: p.tiers.as_ref().map_or_else(Vec::new, TierGrid::edges),
            walls_tiered_in: Vec::new(),
            uid: fresh_uid(),
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

/// aifix B1 — the live overlay paints `cells` and hands no drawing list, so the
/// net saw an empty table. Merge same-type neighbours into rectangles (greedy,
/// row-major) and answer them as pieces in the world frame, largest first so
/// the `N_TERR` cut drops the smallest.
fn pieces_from_cells(cells: &crate::fasthash::FastMap<(i64, i64), i32>, cell_m: f64, rot_rad: f64, half_grid: f64) -> Vec<Obb> {
    let mut keys: Vec<(i64, i64)> = cells.iter().filter(|(_, &k)| k != NONE).map(|(&c, _)| c).collect();
    keys.sort_by_key(|&(x, z)| (z, x));
    let mut used: std::collections::HashSet<(i64, i64)> = std::collections::HashSet::new();
    let mut rects: Vec<(i64, i64, i64, i64, i32)> = Vec::new(); // x0, z0, w, h, kind
    for &(x0, z0) in &keys {
        if used.contains(&(x0, z0)) {
            continue;
        }
        let kind = cells[&(x0, z0)];
        let free = |c: (i64, i64)| !used.contains(&c) && cells.get(&c) == Some(&kind);
        let mut w = 1;
        while free((x0 + w, z0)) {
            w += 1;
        }
        let mut h = 1;
        while (0..w).all(|dx| free((x0 + dx, z0 + h))) {
            h += 1;
        }
        for dz in 0..h {
            for dx in 0..w {
                used.insert((x0 + dx, z0 + dz));
            }
        }
        rects.push((x0, z0, w, h, kind));
    }
    rects.sort_by_key(|r| std::cmp::Reverse(r.2 * r.3));
    let (sin, cos) = rot_rad.sin_cos();
    rects
        .into_iter()
        .map(|(x0, z0, w, h, kind)| {
            let rx = (x0 as f64 + w as f64 * 0.5 - half_grid) * cell_m;
            let rz = (z0 as f64 + h as f64 * 0.5 - half_grid) * cell_m;
            Obb {
                c: [rx * cos - rz * sin, rx * sin + rz * cos],
                he: [w as f64 * 0.5 * cell_m, h as f64 * 0.5 * cell_m],
                yaw: rot_rad,
                kind,
                slabs: Vec::new(),
            }
        })
        .collect()
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
    ///
    /// The pre-3.6 reading, for callers that cannot know an epoch (the sight unit tests); a game asks
    /// `los_blocked_at`.
    pub fn los_blocked(&self, a: V3, b: V3) -> bool {
        self.los_blocked_at(a, b, EPOCH_72_PLAYTEST_RULES)
    }

    /// `los_blocked` as the game at `rules_epoch` reads the board (rules 3.6 = `EPOCH_73_V36`): a ruin still
    /// gives cover but no longer BLOCKS the centre line, while a container and a forest block at every epoch.
    pub fn los_blocked_at(&self, a: V3, b: V3, rules_epoch: u32) -> bool {
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
            if (t == RUINS && !rule_on(rules_epoch, EPOCH_73_V36)) || t == CONTAINER || t == FOREST {
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

/// Test board of the heightfield steps: an `nx` x `nz` tier grid of 3 in cells on a table of the same size (yaw 0,
/// board-centred), no painted terrain. `level_in` is row-major; `ladders` are `[low, high]` cell indices.
#[cfg(test)]
pub(crate) fn tier_board_for_test(nx: u16, nz: u16, level_in: Vec<f64>, ladders: Vec<[u16; 2]>) -> Terrain {
    Terrain::build(&PlainTerrain {
        cell_params: CellParams {
            table_size_feet: [f64::from(nx) * 0.25, f64::from(nz) * 0.25],
            grid_rotation_degrees: 0.0,
            grid_size_inches: 3.0,
            inches_to_meters: crate::IN2M,
        },
        tiers: Some(TierGrid { nx, nz, cell_in: 3.0, level_in, ladders, stairs: Vec::new() }),
        ..Default::default()
    })
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
            pieces: vec![],
            containers: Vec::new(),
            walls: vec![],
            cell_params: CellParams {
                table_size_feet: [6.0, 4.0],
                grid_rotation_degrees: 0.0,
                grid_size_inches: 3.0,
                inches_to_meters: IN2M,
            },
            ..Default::default()
        })
    }

    fn at(x_in: f64, z_in: f64) -> V3 {
        [(x_in * IN2M) as f32, 0.0, (z_in * IN2M) as f32]
    }

    /// A header's `terrain` object as the recorder writes it, with or without the heightfield key.
    fn header(tiers: Option<serde_json::Value>) -> serde_json::Value {
        let mut h = serde_json::json!({"cells": [[0.0, 0.0, RUINS as f64]], "sandbox": [], "walls": [],
            "cell_params": {"table_size_feet": [6.0, 4.0], "grid_rotation_degrees": 0.0, "grid_size_inches": 3.0,
                "inches_to_meters": IN2M}});
        if let Some(t) = tiers {
            h["tiers"] = t;
        }
        h
    }

    /// Heightfield plan step 1: the tier grid rides in the header and comes back as written. Red before the step:
    /// `PlainTerrain` had no `tiers` field, the test did not compile.
    #[test]
    fn a_header_with_tiers_keeps_them() {
        let tiers = serde_json::json!({"nx": 2, "nz": 2, "cell_in": 3.0, "level_in": [0.0, 3.0, 6.0, 3.0],
            "ladders": [[0, 1]], "stairs": [[1, 2]]});
        let p: PlainTerrain = serde_json::from_value(header(Some(tiers))).unwrap();
        let want = TierGrid { nx: 2, nz: 2, cell_in: 3.0, level_in: vec![0.0, 3.0, 6.0, 3.0], ladders: vec![[0, 1]], stairs: vec![[1, 2]] };
        assert_eq!(p.tiers, Some(want));
        // a grid without connectors is a legal board: both lists default to empty
        let bare = serde_json::json!({"nx": 1, "nz": 1, "cell_in": 3.0, "level_in": [0.0]});
        let q: PlainTerrain = serde_json::from_value(header(Some(bare))).unwrap();
        assert!(q.tiers.is_some_and(|t| t.ladders.is_empty() && t.stairs.is_empty()));
    }

    /// Every header written so far has no `tiers` key: it reads as `None`, and the data is inert at this step - a board
    /// built with a grid answers every terrain lookup like the same board without one.
    #[test]
    fn a_header_without_tiers_is_today_and_tiers_change_no_lookup_yet() {
        let flat: PlainTerrain = serde_json::from_value(header(None)).unwrap();
        assert!(flat.tiers.is_none());
        let tiers = serde_json::json!({"nx": 1, "nz": 1, "cell_in": 3.0, "level_in": [6.0]});
        let high: PlainTerrain = serde_json::from_value(header(Some(tiers))).unwrap();
        let (a, b) = (Terrain::build(&flat), Terrain::build(&high));
        for p in [(0.0, 0.0), (1.5, 1.5), (-4.0, 7.0), (20.0, -9.0)] {
            assert_eq!(a.type_at(at(p.0, p.1)), b.type_at(at(p.0, p.1)));
        }
    }

    /// Heightfield plan step 2: a header written by the core reads back as the same board (step 3 writes one, the hash
    /// of step 3 and the save of step 21 are taken over exactly these bytes). Every optional key is filled, tiers
    /// included. Red before: `PlainTerrain` and the structs inside it had no `Serialize` / `PartialEq`, no compile.
    #[test]
    fn plain_terrain_round_trips() {
        let mut h = header(Some(serde_json::json!({"nx": 2, "nz": 2, "cell_in": 3.0, "level_in": [0.0, 3.0, 6.0, 3.0],
            "ladders": [[0, 1], [1, 2]]})));
        h["sandbox"] = serde_json::json!([{"c": [0.5, -0.25], "he": [0.1, 0.2], "yaw": 0.7, "type": RUINS,
            "slabs": [{"c": [0.5, -0.25], "he": [0.1, 0.2], "yaw": 0.7, "y0": 0.05, "y1": 0.08}]}]);
        h["walls"] = serde_json::json!([[[0.0, 0.0], [1.0, 0.0]], [[1.0, 0.0], [1.0, 2.5]]]);
        h["pieces"] = serde_json::json!([[1.0, 4.5, -7.5, 3.0, 6.0, 90.0], [2.0, -3.0, 1.5, 6.0, 3.0, 0.0]]);
        h["containers"] = serde_json::json!([{"c": [0.1, 0.2], "he": [0.0762, 0.1524], "yaw": 1.5}]);
        let before: PlainTerrain = serde_json::from_value(h).unwrap();
        assert!(before.tiers.is_some() && !before.pieces.is_empty() && !before.containers.is_empty() && !before.walls.is_empty());
        let json = serde_json::to_string(&before).unwrap();
        let after: PlainTerrain = serde_json::from_str(&json).unwrap();
        assert_eq!(after, before, "serialize then parse must return the same board");
        // a flat header (no tiers) writes `tiers: null` and reads back as None, not as a missing grid
        let flat: PlainTerrain = serde_json::from_value(header(None)).unwrap();
        let flat_back: PlainTerrain = serde_json::from_str(&serde_json::to_string(&flat).unwrap()).unwrap();
        assert_eq!(flat_back, flat);
        assert!(flat_back.tiers.is_none());
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

    /// A 4 x 4 board of 3 in cells (board-centred, x and z from -6 to 6 in): the two columns at x >= 0 are a 3 in tier, a ladder
    /// joins it in the row z -3..0 (cells 5 and 6), the rest of the border at x = 0 is a cliff.
    fn laddered() -> Terrain {
        tier_board_for_test(4, 4, (0..16).map(|i| if i % 4 >= 2 { 3.0 } else { 0.0 }).collect(), vec![[5, 6]])
    }

    /// Heightfield plan step 11b: the cliffs are walls for the readers that keep a base off a sheer edge, the ladder is not;
    /// the epoch-gated view carries them from the height gate only; a flat board answers `walls_in` itself.
    #[test]
    fn the_cliffs_join_the_resting_walls_and_the_gated_view_only_at_the_gate() {
        use crate::acts::EPOCH_94_PARITY_BATCH as gate;
        let t = laddered();
        assert!(t.walls_in().is_empty());
        assert_eq!(t.walls_in_tiered().len(), 2, "the cliffs z -6..-3 and z 0..6; the ladder is no wall");
        assert_eq!((t.walls_in_at(gate).len(), t.walls_in_at(gate - 1).len()), (2, 0));
        let flat = school(&[(15, 15, FOREST)]);
        assert_eq!(flat.walls_in_tiered(), flat.walls_in());
    }

    /// The same sentence for rest legality (R10): a base does not end 0.2 in from a cliff, on either side of it, but may
    /// stand as close to the ladder; a flat board has no such wall. Planner frame = board-centred + 6 in.
    #[test]
    fn a_base_may_not_rest_against_a_cliff_but_may_beside_a_ladder() {
        let (t, flat) = (laddered(), Terrain::build(&PlainTerrain { cell_params: CellParams { table_size_feet: [1.0, 1.0], grid_rotation_degrees: 0.0, grid_size_inches: 3.0, inches_to_meters: IN2M }, ..Default::default() }));
        let rest = |t: &Terrain, x: f64, z: f64| crate::mv::gate::rest_forbidden([x, z], 0.5, t);
        assert!(rest(&t, 5.8, 9.0), "0.2 in from the cliff, low side");
        assert!(rest(&t, 6.2, 9.0), "and on the roof side");
        assert!(!rest(&t, 4.0, 9.0), "2 in away");
        assert!(!rest(&t, 5.8, 4.5), "beside the ladder: no wall");
        assert!(!rest(&flat, 5.8, 9.0), "a flat board has no such wall");
    }

    /// A 3 x 3 board of 3 in cells, rows are z, columns are x: deliberately not symmetric under x <-> z.
    fn tiered(level_in: Vec<f64>) -> Terrain {
        let tiers = serde_json::json!({"nx": 3, "nz": 3, "cell_in": 3.0, "level_in": level_in});
        Terrain::build(&serde_json::from_value::<PlainTerrain>(header(Some(tiers))).unwrap())
    }

    /// Heightfield plan step 5: the level under each cell centre, half-open borders, the world's rim, NaN. Red before:
    /// `tier_in_at` did not exist; a swapped x/z or a `round` instead of `floor` in it fails this test.
    #[test]
    fn tier_in_at_reads_the_cell_under_the_point() {
        let b = tiered(vec![0.0, 3.0, 6.0, 0.0, 6.0, 3.0, 3.0, 0.0, 6.0]);
        // centres of columns x = -3, 0, 3 and rows z = -3, 0, 3
        let want = [[0.0, 3.0, 6.0], [0.0, 6.0, 3.0], [3.0, 0.0, 6.0]];
        for (iz, z) in [-3.0, 0.0, 3.0].into_iter().enumerate() {
            for (ix, x) in [-3.0, 0.0, 3.0].into_iter().enumerate() {
                assert_eq!(b.tier_in_at(x, z), want[iz][ix], "cell ({ix}, {iz})");
                assert_eq!(b.tier_in_at(x + 1.4, z - 1.4), want[iz][ix], "inside the same cell, away from the centre");
            }
        }
        // a border belongs to the cell on its positive side (x = -1.5 is column 1's west edge, x = 1.5 column 2's)
        assert_eq!(b.tier_in_at(-1.5, -3.0), 3.0);
        assert_eq!(b.tier_in_at(-1.5 - 1e-9, -3.0), 0.0);
        assert_eq!(b.tier_in_at(1.5, 3.0), 6.0);
        assert_eq!(b.tier_in_at(0.0, 1.5), 0.0, "z = 1.5 is row 2's north edge: row 2, column 1");
        // the grid covers [-4.5, 4.5): its own corner is in, the far edge and beyond are ground
        assert_eq!(b.tier_in_at(-4.5, -4.5), 0.0);
        assert_eq!(b.tier_in_at(4.5 - 1e-9, 4.5 - 1e-9), 6.0);
        assert_eq!(b.tier_in_at(4.5, 3.0), 0.0);
        assert_eq!(b.tier_in_at(3.0, -4.5 - 1e-9), 0.0);
        assert_eq!(b.tier_in_at(f64::NAN, 0.0), 0.0);
        assert_eq!(b.tier_in_at(0.0, f64::INFINITY), 0.0);
    }

    #[test]
    fn tier_in_at_is_ground_without_tiers_and_survives_a_short_level_list() {
        let flat = Terrain::build(&serde_json::from_value::<PlainTerrain>(header(None)).unwrap());
        assert_eq!(flat.tier_in_at(0.0, 0.0), 0.0);
        assert_eq!(Terrain::absent().tier_in_at(0.0, 0.0), 0.0);
        let short = tiered(vec![6.0, 6.0]);
        assert_eq!(short.tier_in_at(-3.0, -4.0), 6.0);
        assert_eq!(short.tier_in_at(3.0, 3.0), 0.0, "a level the list does not carry reads as ground, no panic");
    }

    /// 4 x 3 cells; rows are z. Raised cells: (1,0)=3 (2,0)=3 (1,1)=3 (2,1)=6, the rest is ground.
    fn small_grid(ladders: Vec<[u16; 2]>) -> TierGrid {
        let level_in = vec![0.0, 3.0, 3.0, 0.0, 0.0, 3.0, 6.0, 0.0, 0.0, 0.0, 0.0, 0.0];
        TierGrid { nx: 4, nz: 3, cell_in: 3.0, level_in, ladders, stairs: vec![] }
    }

    fn edge(a: [f64; 2], b: [f64; 2], dy_in: f64, high: HighSide, kind: TierKind) -> TierEdge {
        TierEdge { a, b, dy_in, high, kind }
    }

    /// Heightfield plan step 6: a straight cliff of one height is ONE edge, a ladder border stays its own edge and
    /// splits the run, and every edge names its high side. Red before: `edges` did not exist; a swapped high side or no
    /// run merge fails this exact list.
    #[test]
    fn a_cliff_run_is_one_edge_and_a_ladder_border_is_its_own() {
        use HighSide::{Left, Right};
        use TierKind::{Cliff, Ladder};
        // board spans x -6..6, z -4.5..4.5; vertex (i, j) = (-6 + 3i, -4.5 + 3j)
        let plain = small_grid(vec![]).edges();
        assert_eq!(plain, vec![
            edge([-3.0, -4.5], [-3.0, 1.5], 3.0, Right, Cliff), // west face of the block, rows 0-1 in one edge
            edge([0.0, -1.5], [0.0, 1.5], 3.0, Right, Cliff),   // between (1,1)=3 and (2,1)=6, row 1 only
            edge([3.0, -4.5], [3.0, -1.5], 3.0, Left, Cliff),   // east face of (2,0)
            edge([3.0, -1.5], [3.0, 1.5], 6.0, Left, Cliff),    // east face of (2,1): 6 in, no merge with the 3 in run
            edge([0.0, -1.5], [3.0, -1.5], 3.0, Left, Cliff),   // (2,0)=3 north of (2,1)=6, high side south
            edge([-3.0, 1.5], [0.0, 1.5], 3.0, Right, Cliff),   // south face of (1,1), high side north
            edge([0.0, 1.5], [3.0, 1.5], 6.0, Right, Cliff),    // south face of (2,1)
        ]);
        // a ladder from the ground cell (0,0) (index 0) up to (1,0) (index 1)
        let laddered = small_grid(vec![[0, 1]]).edges();
        assert_eq!(laddered.len(), plain.len() + 1, "the ladder splits the west run in two");
        assert!(laddered.contains(&edge([-3.0, -4.5], [-3.0, -1.5], 3.0, Right, Ladder)));
        assert!(laddered.contains(&edge([-3.0, -1.5], [-3.0, 1.5], 3.0, Right, Cliff)));
        // a ladder between cells of the SAME level is no border at all
        assert_eq!(small_grid(vec![[1, 2]]).edges(), plain);
    }

    #[test]
    fn boxes_are_row_runs_grown_by_identical_rows() {
        let boxes = small_grid(vec![]).boxes();
        assert_eq!(boxes, vec![
            TierBox { lo: [-3.0, -4.5], hi: [3.0, -1.5], top_in: 3.0 }, // (1,0) (2,0)
            TierBox { lo: [-3.0, -1.5], hi: [0.0, 1.5], top_in: 3.0 },  // (1,1): a different run than row 0's two cells
            TierBox { lo: [0.0, -1.5], hi: [3.0, 1.5], top_in: 6.0 },   // (2,1)
        ]);
        let tall = TierGrid { nx: 2, nz: 3, cell_in: 3.0, level_in: vec![3.0, 3.0, 3.0, 3.0, 0.0, 6.0], ladders: vec![], stairs: vec![] };
        assert_eq!(tall.boxes(), vec![
            TierBox { lo: [-3.0, -4.5], hi: [3.0, 1.5], top_in: 3.0 }, // rows 0 and 1 are the same run: one block
            TierBox { lo: [0.0, 1.5], hi: [3.0, 4.5], top_in: 6.0 },
        ]);
    }

    #[test]
    fn a_flat_board_has_no_blocks_and_no_edges() {
        let flat = Terrain::build(&serde_json::from_value::<PlainTerrain>(header(None)).unwrap());
        assert!(flat.tier_boxes().is_empty() && flat.tier_edges().is_empty());
        let level = tiered(vec![3.0; 9]);
        assert_eq!(level.tier_boxes().len(), 1);
        assert!(level.tier_edges().is_empty(), "no border differs, the board edge is no contour");
    }

    /// The grid of a generated board, built here from the layout (`boardgen::plain::to_plain` is step 3's).
    fn generated_grid(seed: i64, sym: crate::boardgen::Symmetry) -> TierGrid {
        let l = crate::boardgen::generate(seed, sym);
        TierGrid {
            nx: l.nx as u16, nz: l.nz as u16, cell_in: f64::from(l.cell_in), stairs: vec![],
            level_in: l.cells.iter().map(|c| f64::from(crate::boardgen::LEVEL_IN[usize::from(c.level)])).collect(),
            ladders: l.connectors.iter().map(|c| [c.low, c.high]).collect(),
        }
    }

    /// Heightfield plan step 6 on real boards: walking from the centre of any cell to the centre of its neighbour crosses
    /// exactly ONE edge when the two levels differ (up or down as the levels say, its rise, a ladder exactly where the
    /// generator wired one) and none when they are equal; the blocks tile the raised cells exactly.
    #[test]
    fn every_border_with_a_level_difference_has_exactly_one_edge_on_generated_boards() {
        use crate::mv::tier::tier_crossings;
        let mut counts = Vec::new();
        for (seed, sym) in [(42, crate::boardgen::Symmetry::Point180), (7, crate::boardgen::Symmetry::BalancedFree), (1000, crate::boardgen::Symmetry::Point180)] {
            let g = generated_grid(seed, sym);
            let (edges, boxes) = (g.edges(), g.boxes());
            let centre = |x: usize, z: usize| [g.vertex(x, z)[0] + 1.5, g.vertex(x, z)[1] + 1.5];
            let (mut borders, mut ladders) = (0, 0);
            for z in 0..16 {
                for x in 0..16 {
                    for (nx, nz) in [(x + 1, z), (x, z + 1)] {
                        if nx > 15 || nz > 15 {
                            continue;
                        }
                        let (l0, l1) = (g.level(x, z), g.level(nx, nz));
                        let got = tier_crossings(centre(x, z), centre(nx, nz), &edges);
                        if l0 == l1 {
                            assert!(got.is_empty(), "seed {seed}: ({x},{z})-({nx},{nz}) are level but cross {got:?}");
                            continue;
                        }
                        borders += 1;
                        assert_eq!(got.len(), 1, "seed {seed}: ({x},{z})-({nx},{nz}) must cross exactly one edge, got {got:?}");
                        let (c, (lo, hi)) = (got[0], if l0 < l1 { ((x, z), (nx, nz)) } else { ((nx, nz), (x, z)) });
                        assert_eq!((c.dy_in, c.down), ((l1 - l0).abs(), l0 > l1), "seed {seed}: ({x},{z})-({nx},{nz})");
                        let wired = g.ladders.contains(&[(lo.1 * 16 + lo.0) as u16, (hi.1 * 16 + hi.0) as u16]);
                        assert_eq!(c.kind == TierKind::Ladder, wired, "seed {seed}: ({x},{z})-({nx},{nz}) ladder or cliff");
                        ladders += usize::from(wired);
                    }
                }
            }
            assert!(borders > 40 && ladders > 0, "seed {seed}: the board must have contours and ladders ({borders}, {ladders})");
            assert_eq!(ladders, g.ladders.len(), "seed {seed}: every ladder sits on one border");
            // the blocks cover every raised cell once, at its own level, and no ground cell
            for z in 0..16 {
                for x in 0..16 {
                    let c = centre(x, z);
                    let inside: Vec<_> = boxes.iter().filter(|b| c[0] > b.lo[0] && c[0] < b.hi[0] && c[1] > b.lo[1] && c[1] < b.hi[1]).collect();
                    assert_eq!(inside.len(), usize::from(g.level(x, z) > 0.0), "seed {seed}: cell ({x},{z}) under {} blocks", inside.len());
                    assert!(inside.iter().all(|b| b.top_in == g.level(x, z)));
                }
            }
            counts.push(boxes.len());
        }
        assert!(counts.iter().all(|&n| n <= 80), "a board's blocks are sight zones, keep them few: {counts:?}");
    }
}
