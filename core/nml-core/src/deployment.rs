//! NML-1152 step 2 — the arena pre-game's shared seam: the roll-off and the per-side
//! deploy seeds. The roll-off consumes the GAME stream (`solo._rng`, arena_match.gd:373
//! → :462) BEFORE deployment; each side's deployment gets a FRESH stream seeded
//! `game_seed + slot` attached to the SLOT (arena_match.gd:487), never the game stream.
//! `roll_off_traced` mirrors `SoloController.roll_off` (solo_controller.gd:7507-7524):
//! 2 `randi_range(1, 6)` draws per attempt, ties re-roll, cap 100 — trace kept because
//! the attempt count is data-dependent (the gate compares the FULL attempt list).

use crate::rng::GodotRng;
use crate::terrain::{CONTAINER, DANGEROUS, RUINS, Terrain};

/// `SoloController.roll_off`'s tie cap (solo_controller.gd:7508).
pub const ROLL_OFF_CAP: usize = 100;

/// One roll-off outcome: every d6 pair in order, then the winner (1 or 2) —
/// the fixture's `roll_off_attempts` + `opener` (research knobs unset).
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RollOff {
    pub attempts: Vec<(i64, i64)>,
    pub winner: i64,
}

/// Pregame input for one unit, built py-side from the list profile (§3.2).
#[derive(Debug, Clone, PartialEq, Default)]
pub struct UnitSpec {
    pub key: String,
    pub model_count: i64,
    pub base_r_m: f64,
    pub footprint: Vec<(f64, f64)>,
    pub scout: bool,
    pub ambush: bool,
    pub ignores_terrain: bool,
    pub vanguard: bool,
    pub transport_capacity: i64,
}

/// One unit's deployed result (slice 5/6 fill this; the gate compares it).
#[derive(Debug, Clone, PartialEq, Default)]
pub struct Placement {
    pub key: String,
    pub section: i64,
    pub scout: bool,
    pub spot: (f64, f64),
    pub vanguard_pushed: bool,
    pub models: Vec<(f64, f64)>,
}

/// One side's full deployment result — the fixture's `sides[slot]`.
#[derive(Debug, Clone, PartialEq, Default)]
pub struct SideDeploy {
    pub seed_value: i64,
    pub fills: Vec<(String, String)>,
    pub placements: Vec<Placement>,
    pub reserved: Vec<String>,
}

/// `SoloController.roll_off` with the trace kept (fallback winner 1 after the cap).
pub fn roll_off_traced(rng: &mut GodotRng) -> RollOff {
    let mut attempts = Vec::new();
    for _ in 0..ROLL_OFF_CAP {
        let d1 = rng.randi_range(1, 6);
        let d2 = rng.randi_range(1, 6);
        attempts.push((d1, d2));
        if d1 != d2 {
            return RollOff { attempts, winner: if d1 > d2 { 1 } else { 2 } };
        }
    }
    RollOff { attempts, winner: 1 }
}

/// The per-side deploy seed, attached to the SLOT: `_seed + slot`
/// (arena_match.gd:487 → pregame_dump.gd `seed_value = seed_v + slot`).
pub fn side_seed_value(game_seed: i64, slot: i64) -> i64 {
    game_seed + slot
}

/// Roll-off winner deploys first (arena_match.gd:500).
pub fn deploy_order(winner: i64) -> [i64; 2] {
    if winner == 1 {
        [1, 2]
    } else {
        [2, 1]
    }
}

// ---- the per-side deploy stream's draw phases (NML-1152 step 3). `deploy_begin`
// (solo_controller.gd:8943-9047) seeds a FRESH rng per side (:8944-8945) and
// consumes it IN ORDER: transport fill (:8957-8976) → split_into_groups (:8986)
// → assign_sections (:8987) → placement_order (:9038, step 3b). Placement draws NOTHING.

/// `AiDeployment._shuffle` (ai_deployment.gd:239-244): Fisher-Yates, one
/// `randi_range(0, i)` draw per swap, top index down to 1.
fn shuffle(v: &mut [usize], rng: &mut GodotRng) {
    for i in (1..v.len()).rev() {
        let j = rng.randi_range(0, i as i64) as usize;
        v.swap(i, j);
    }
}

/// `AiDeployment.split_into_groups` (ai_deployment.gd:15-23): indices shuffled,
/// then dealt into 3 groups of equal size as far as possible (`k % 3`).
pub fn split_into_groups(count: usize, rng: &mut GodotRng) -> Vec<Vec<usize>> {
    let mut idx: Vec<usize> = (0..count).collect();
    shuffle(&mut idx, rng);
    let mut groups: Vec<Vec<usize>> = vec![Vec::new(), Vec::new(), Vec::new()];
    for (k, &i) in idx.iter().enumerate() {
        groups[k % 3].push(i);
    }
    groups
}

/// `AiDeployment.assign_sections` (ai_deployment.gd:27-43): one D3 per group,
/// the whole roll re-done while ALL groups would share one section; a single
/// group returns after its one draw (:34-35).
pub fn assign_sections(group_count: usize, rng: &mut GodotRng) -> Vec<i64> {
    if group_count == 0 {
        return Vec::new();
    }
    loop {
        let sections: Vec<i64> = (0..group_count).map(|_| rng.randi_range(1, 3)).collect();
        if group_count == 1 || sections.iter().any(|&s| s != sections[0]) {
            return sections;
        }
    }
}

/// `AiDeployment.placement_order` (ai_deployment.gd:54-67, called at
/// solo_controller.gd:9038): units deploy one at a time in RANDOM order —
/// normals shuffled, scouts shuffled after them, scouts deploy LAST, ambush
/// units excluded entirely (reserve, arrive round 2). Draw order: n_normal−1
/// Fisher-Yates draws, then n_scout−1. Returns spec indices in deploy order.
pub fn placement_order(specs: &[UnitSpec], rng: &mut GodotRng) -> Vec<usize> {
    let mut normal: Vec<usize> = Vec::new();
    let mut scouts: Vec<usize> = Vec::new();
    for (i, s) in specs.iter().enumerate() {
        if s.ambush {
            continue;
        }
        if s.scout {
            scouts.push(i);
        } else {
            normal.push(i);
        }
    }
    shuffle(&mut normal, rng);
    shuffle(&mut scouts, rng);
    normal.extend(scouts);
    normal
}

/// `deploy_begin`'s transport fill (solo_controller.gd:8957-8976). The caller
/// passes capacities of alive, unattached, not-already-embarked units in
/// game-unit list order. Each transport (capacity > 0, list order) loads random
/// non-transport units up to its cargo limit: one `randi_range(0, len-1)` draw
/// per pop from a duplicated candidate pool until drained — the final pop (one
/// candidate left) draws NOTHING (the engine's `randi_range(0,0)` fast path).
/// The capacity gate is a unit-count stand-in for the engine's space-count
/// can_embark (opr_army_manager.gd:2930: `unit_embark_spaces` vs
/// `cap − transport_used_spaces`, plus untransportable/pre-embarked failures
/// not mirrored) — exact for the transport-free corpus lists. Returns
/// (transport, cargo) index pairs.
pub fn transport_fill(capacities: &[i64], rng: &mut GodotRng) -> Vec<(usize, usize)> {
    let mut fills: Vec<(usize, usize)> = Vec::new();
    let mut pool: Vec<usize> = (0..capacities.len()).filter(|&i| capacities[i] <= 0).collect();
    for tr in 0..capacities.len() {
        if capacities[tr] <= 0 {
            continue;
        }
        let mut tries = pool.clone();
        let mut loaded = 0usize;
        while !tries.is_empty() {
            let pick = tries.remove(rng.randi_range(0, tries.len() as i64 - 1) as usize);
            if loaded < capacities[tr] as usize {
                loaded += 1;
                let at = pool.iter().position(|&p| p == pick).expect("pick in pool");
                pool.remove(at);
                fills.push((tr, pick));
            }
        }
    }
    fills
}

// ---- the deployment terrain geometry (NML-1152 step 4a). A spot must pass the
// blocked test of `make_blocked_tests` (ai_deployment.gd:292-331): the Godot
// physics probe against SOLID props (hits_prop, :300-309 — not directly
// portable; banked as blocker discs since NML-1155, see the PROP layer below),
// the container/ruin WALL segments at 0.02 m clearance (:301-316), and the
// terrain class (:317-330). Strider/Flying units take the FLYING class test
// instead of the walker one (solo_controller.gd:9110-9112). All sample-point
// math mirrors GDScript's f32 `Vector2` at the narrowing boundary. The
// invalid-Callable path (ai_deployment.gd:175, terrain ignored entirely) has no
// twin here — the caller decides per UnitSpec whether to test at all.

/// `DEPLOY_WALL_CLEARANCE_M` (ai_deployment.gd:268).
pub const DEPLOY_WALL_CLEARANCE_M: f64 = 0.02;
/// `TERRAIN_SAMPLE_STEP_M` — half a 3" terrain cell (ai_deployment.gd:211).
const TERRAIN_SAMPLE_STEP_M: f64 = 0.0381;

// ---- the PROP layer (NML-1155): the banked stand-in for `hits_prop`
// (ai_deployment.gd:300-309), the Godot physics probe that is NOT directly
// portable (design §4.3). The bank v2 (`tools/terrain_bank_dump.gd`) carries
// each solid prop's XZ incircle disc (`Terrain::blockers_m`, world metres);
// the probe is a 0.02 m sphere hovering at 0.07 m over a 2.5"-high box (top
// ≈ 0.0615 m, terrain_overlay.gd:19 + :2890), so the sphere's 2D reach past
// the box surface is sqrt(0.02² − 0.0085²) ≈ 0.0181 m — the twin's full
// 0.02 over-blocks that sliver by 1.9 mm, BUT the wall layer already blocks
// a 0.02 m band around every banked prop's own OBB edges (the dump harvests
// `walls` from the same overlay pass that spawns the boxes,
// terrain_overlay.gd:2834-2843), so prop_blocked ⊆ wall_blocked for every
// banked disc and the twin mirrors the TABLE's law, not the probe's sliver.
// Measured on the 100 fixture dumps: 0 of the 1036 table-tested recorded
// spots flip.

/// The probe sphere's radius (ai_deployment.gd:296).
pub const PROBE_RADIUS_M: f64 = 0.02;

/// One probe-sphere-vs-blocker-disc test: the sample point is blocked when
/// the disc around it (the sphere's 2D projection) reaches a blocker disc.
/// `p` is world metres, the blockers ride the board in world metres.
pub fn prop_blocked(board: &Terrain, p: (f64, f64)) -> bool {
    board.blockers_m().iter().any(|b| {
        let (dx, dy) = (p.0 - b[0], p.1 - b[1]);
        (dx * dx + dy * dy).sqrt() < b[2] + PROBE_RADIUS_M
    })
}

/// `AiDeployment.footprint_margins` (ai_deployment.gd:78-87): per-axis zone
/// margins from the REAL footprint (the Bug-19 fix); an empty footprint
/// (regiment tray) falls back to the circumradius on both axes.
pub fn footprint_margins(radius: f64, footprint: &[(f64, f64)], base_r: f64) -> (f64, f64) {
    if footprint.is_empty() {
        return (radius, radius);
    }
    let (mut mx, mut my) = (0.0f64, 0.0f64);
    for off in footprint {
        mx = mx.max(off.0.abs());
        my = my.max(off.1.abs());
    }
    (mx + base_r, my + base_r)
}

/// `AiDeployment._base_edge_offsets` (ai_deployment.gd:200-205): the centre plus
/// the eight base-edge points (cardinals + diagonals) at radius `r`; a zero
/// radius collapses to the centre alone. f32 at every Vector2 boundary.
fn base_edge_offsets(r: f64) -> Vec<[f32; 2]> {
    if r <= 0.0 {
        return vec![[0.0, 0.0]];
    }
    let diag = (r * 0.70710678) as f32;
    let rr = r as f32;
    vec![
        [0.0, 0.0],
        [rr, 0.0],
        [-rr, 0.0],
        [0.0, rr],
        [0.0, -rr],
        [diag, diag],
        [diag, -diag],
        [-diag, diag],
        [-diag, -diag],
    ]
}

/// `AiDeployment._disc_sample_offsets` (ai_deployment.gd:217-234, Bug 29): a
/// COMPLETE sampler for a base disc of radius `r`. A small base (r ≤ one step)
/// reduces to the 9-point check; a large base densifies on a grid no coarser
/// than half a terrain cell so no blocked cell can hide between samples, then
/// appends the exact edge ring — NOT de-duplicated (the table's sample
/// multiset is mirrored verbatim; `_blocked_count` shares it in slice 5).
pub fn disc_sample_offsets(r: f64) -> Vec<[f32; 2]> {
    if r <= TERRAIN_SAMPLE_STEP_M {
        return base_edge_offsets(r);
    }
    let mut offsets = vec![[0.0f32, 0.0]];
    let n = (r / TERRAIN_SAMPLE_STEP_M).ceil() as i64;
    let step = r / n as f64;
    for i in -n..=n {
        for j in -n..=n {
            if i == 0 && j == 0 {
                continue;
            }
            let o = [(i as f64 * step) as f32, (j as f64 * step) as f32];
            let len = (o[0] * o[0] + o[1] * o[1]).sqrt();
            if len as f64 <= r + 0.0001 {
                offsets.push(o);
            }
        }
    }
    for e in base_edge_offsets(r) {
        if e != [0.0f32, 0.0] {
            offsets.push(e);
        }
    }
    offsets
}

/// `MovementPlanner.point_seg_distance` (movement_planner.gd:168-174) in the
/// planner's 0-origin INCH frame — the frame `Terrain::walls_in` stores wall
/// segments in. Distances scale by 1/in2m exactly, so the metre EPS
/// (movement_planner.gd:24) rescales with them for the degenerate-segment gate;
/// `in2m` is the board's own scale (the one `set_walls_world_m` used).
fn point_seg_distance_in(p: [f32; 2], a: [f32; 2], b: [f32; 2], in2m: f64) -> f32 {
    let eps2 = (0.0001f64 * 0.0001 / (in2m * in2m)) as f32;
    let (abx, aby) = (b[0] - a[0], b[1] - a[1]);
    let len2 = abx * abx + aby * aby;
    if len2 < eps2 {
        return ((p[0] - a[0]) * (p[0] - a[0]) + (p[1] - a[1]) * (p[1] - a[1])).sqrt();
    }
    // GDScript divides in f64 (Vector2 dot/length_squared widen at the Variant),
    // clamps in f64, then narrows back for the `ab * t` multiply (:173-174).
    let dot = (p[0] - a[0]) * abx + (p[1] - a[1]) * aby;
    let t = ((dot as f64 / len2 as f64).clamp(0.0, 1.0)) as f32;
    let (qx, qy) = (a[0] + abx * t, a[1] + aby * t);
    ((p[0] - qx) * (p[0] - qx) + (p[1] - qy) * (p[1] - qy)).sqrt()
}

/// The WALL layer (`near_wall`, ai_deployment.gd:312-316): a point within
/// `DEPLOY_WALL_CLEARANCE_M` of any wall segment is blocked. Segments ride the
/// banked board (`Terrain::walls_in`); the test runs in the inch frame where
/// distances are frame-exact and only the threshold converts — frame-equivalent
/// to the table's metre-space test up to f32 storage noise, NOT bit-identical.
pub fn wall_blocked(board: &Terrain, p: (f64, f64)) -> bool {
    let q = board.to_inch([p.0 as f32, 0.0, p.1 as f32]);
    let clear_in = DEPLOY_WALL_CLEARANCE_M / board.in2m();
    let in2m = board.in2m();
    board
        .walls_in()
        .iter()
        .any(|s| (point_seg_distance_in(q, s[0], s[1], in2m) as f64) < clear_in)
}

/// The CELL layer of `blocked_normal` / `blocked_flying` (ai_deployment.gd:317-330):
/// a walker rejects DANGEROUS + CONTAINER, a Strider/Flying unit rejects
/// CONTAINER + RUINS; FOREST floors are legal for both (deploy doctrine).
/// `p` is world metres, exactly what `get_terrain_at_world_position` takes.
pub fn cell_blocked(board: &Terrain, p: (f64, f64), flying: bool) -> bool {
    let t = board.type_at([p.0 as f32, 0.0, p.1 as f32]);
    if flying {
        t == CONTAINER || t == RUINS
    } else {
        t == DANGEROUS || t == CONTAINER
    }
}

/// `AiDeployment._blocked_at` (ai_deployment.gd:174-195): the per-spot TERRAIN
/// test. The centre first; then, with a model grid, EVERY model's base (centre
/// + dense disc samples, edges computed once and NOT zero-filtered — the model
/// centre itself is a sample) with sample points added in f32 like the table's
/// `p + off + e`; else the dense disc of `probe_radius` (regiment trays, centre
/// already tested). Each sample runs the three layers: props (the banked
/// probe stand-in), walls, cells — the table's order is probe → walls → cells
/// (ai_deployment.gd:317-330); OR is order-free.
pub fn spot_blocked(
    board: &Terrain,
    p: (f64, f64),
    flying: bool,
    probe_radius: f64,
    footprint: &[(f64, f64)],
    base_r: f64,
) -> bool {
    if wall_blocked(board, p) || cell_blocked(board, p, flying) || prop_blocked(board, p) {
        return true;
    }
    let (px, py) = (p.0 as f32, p.1 as f32);
    let hit = |q: [f32; 2]| {
        cell_blocked(board, (q[0] as f64, q[1] as f64), flying)
            || wall_blocked(board, (q[0] as f64, q[1] as f64))
            || prop_blocked(board, (q[0] as f64, q[1] as f64))
    };
    if !footprint.is_empty() {
        let edges = disc_sample_offsets(base_r);
        for off in footprint {
            let m = [px + off.0 as f32, py + off.1 as f32];
            if edges.iter().any(|e| hit([m[0] + e[0], m[1] + e[1]])) {
                return true;
            }
        }
        return false;
    }
    if probe_radius <= 0.0 {
        return false;
    }
    disc_sample_offsets(probe_radius)
        .iter()
        .any(|e| *e != [0.0f32, 0.0] && hit([px + e[0], py + e[1]]))
}

// ---- the compact deployment grid (NML-1152 step 4b). TWO grids exist on the
// table: the CHECK grid below (base-aware spacing, squarest √n columns above
// 10 models, whole footprint shrunk under the coherency span cap) that the
// spot search tests every model base against (solo_controller.gd:10273-10303),
// and the FIXED 0.04 m place grid that actually drops the models
// (`_place_unit_at`, :10329-10346) — the settle pass then repairs overlaps.
// The twin's UnitSpec.footprint carries the check grid; models come from slice 6.

/// `DEPLOY_SPACING_M` — model-centre spacing of the compact grid
/// (solo_controller.gd:10233).
pub const DEPLOY_SPACING_M: f64 = 0.04;
/// `DEPLOY_COLS` — models per rank in the fixed place grid (:10234).
pub const DEPLOY_COLS: usize = 5;

/// `_deploy_footprint_radius` (solo_controller.gd:10251-10258): the circumradius
/// of the compact grid at FIXED `DEPLOY_COLS` ranks (not the √n law below — the
/// table's two helpers disagree there; mirrored as-is), plus the largest base
/// radius and a 1 cm allowance. This is best_spot's `radius`/`probe_radius`.
pub fn deploy_footprint_radius(model_count: usize, base_r: f64) -> f64 {
    let n = model_count.max(1);
    let cols = n.min(DEPLOY_COLS) as f64;
    let rows = ((n as f64) / (DEPLOY_COLS as f64)).ceil();
    let half_w = (cols - 1.0) * DEPLOY_SPACING_M * 0.5;
    let half_d = (rows - 1.0) * DEPLOY_SPACING_M * 0.5;
    (half_w * half_w + half_d * half_d).sqrt() + base_r + 0.01
}

/// `_deploy_footprint_offsets` (solo_controller.gd:10281-10303): the per-model
/// XZ offsets the spot search CHECKS. Spacing adapts to the base
/// (≥ 2·base_r + 6 mm), the grid goes squarest-√n above 10 models, and the
/// whole footprint is shrunk under the coherency span cap (9", or 6" for the
/// skirmish systems — CoherencyChecker.gd:13/:18) so a fresh deploy passes its
/// own gate. GDScript floats are f64 throughout — no f32 boundary here.
pub fn deploy_footprint_offsets(model_count: usize, base_r: f64, skirmish: bool) -> Vec<(f64, f64)> {
    let n = model_count;
    if n == 0 {
        return Vec::new();
    }
    let mut spacing = DEPLOY_SPACING_M.max(2.0 * base_r + 0.006);
    let cols = if n <= 2 * DEPLOY_COLS {
        n.min(DEPLOY_COLS)
    } else {
        ((n as f64).sqrt().ceil()) as usize
    };
    let rows = (n + cols - 1) / cols;
    let chain_cap_in = if skirmish { 6.0 } else { 9.0 };
    let span_cap = (chain_cap_in - 0.5) * 0.0254;
    let grid_diag = (((cols - 1) as f64).powi(2) + ((rows - 1) as f64).powi(2)).sqrt();
    if grid_diag > 0.001 && grid_diag * spacing + 2.0 * base_r > span_cap {
        spacing = (2.0 * base_r + 0.002).max((span_cap - 2.0 * base_r) / grid_diag);
    }
    (0..n)
        .map(|i| {
            let (col, row) = ((i % cols) as f64, (i / cols) as f64);
            (
                (col - (cols - 1) as f64 * 0.5) * spacing,
                (row - (rows - 1) as f64 * 0.5) * spacing,
            )
        })
        .collect()
}

// ---- the SPOT SEARCH (NML-1152 step 5). `SoloController._deploy_place_id`
// (solo_controller.gd:9086-9170) minus the scout band (slice 6) and the M2b
// zone-test composite (the arena harness passes NO zone test,
// tools/arena_match.gd:989 — default invalid Callable): the objective-near
// scan (ai_deployment.gd:97-115), the fallback ladder (:9131-9145) and
// least_blocked_spot (ai_deployment.gd:125-165). Draw-free; f32 at every
// Godot Vector2/Rect2 boundary (real_t), f64 arithmetic between them —
// exactly GDScript's floats (its scalar `float` is a double).

/// `best_spot`'s scan step at the call site (solo_controller.gd:9121).
pub const DEPLOY_SPOT_STEP_M: f64 = 0.025;
/// `least_blocked_spot`'s coarser step (solo_controller.gd:9144).
pub const LEAST_BLOCKED_STEP_M: f64 = 0.05;
/// `AiDeployment.FORWARD_EDGE_W` (ai_deployment.gd:94): A/B-REJECTED at any
/// other weight, 0 keeps the plumbing.
const FORWARD_EDGE_W: f64 = 0.0;
/// The scan boundary slop (ai_deployment.gd:102/:104/:132/:134 literal 0.0001).
const SCAN_EPS: f64 = 0.0001;

/// Godot `Rect2` at the real_t boundary: construction and `end`/`get_center`
/// narrow to f32; the scan arithmetic between boundaries runs f64.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Rect {
    pub pos: (f64, f64),
    pub size: (f64, f64),
}

impl Rect {
    pub fn new(x: f64, y: f64, w: f64, h: f64) -> Rect {
        Rect {
            pos: (x as f32 as f64, y as f32 as f64),
            size: (w as f32 as f64, h as f32 as f64),
        }
    }
    /// `Rect2.end` — position + size (Vector2 add, f32).
    pub fn end(&self) -> (f64, f64) {
        (
            (self.pos.0 as f32 + self.size.0 as f32) as f64,
            (self.pos.1 as f32 + self.size.1 as f32) as f64,
        )
    }
    /// `Rect2.get_center` — position + size/2 (f32).
    pub fn centre(&self) -> (f64, f64) {
        (
            (self.pos.0 as f32 + self.size.0 as f32 / 2.0) as f64,
            (self.pos.1 as f32 + self.size.1 as f32 / 2.0) as f64,
        )
    }
}

/// `Vector2.distance_to` — subtract, dot, sqrt all at real_t.
fn v2_dist(a: (f64, f64), b: (f64, f64)) -> f64 {
    let (dx, dy) = (b.0 as f32 - a.0 as f32, b.1 as f32 - a.1 as f32);
    (dx * dx + dy * dy).sqrt() as f64
}

/// `Vector2 + Vector2` at the real_t boundary.
fn v2_add(a: (f64, f64), b: (f64, f64)) -> (f64, f64) {
    ((a.0 as f32 + b.0 as f32) as f64, (a.1 as f32 + b.1 as f32) as f64)
}

/// One `occupied` entry — `{"pos": Vector2, "radius": float}` (solo_controller.gd:9170).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Occupied {
    pub pos: (f64, f64),
    pub radius: f64,
}

/// `AiDeployment.section_rect` (ai_deployment.gd:47-49): the zone's third-strip
/// for section 1-3; `w` divides in f64, the Rect2 ctor narrows.
pub fn section_rect(zone: &Rect, section: i64) -> Rect {
    let w = zone.size.0 / 3.0;
    Rect::new(
        zone.pos.0 + w * (section.clamp(1, 3) - 1) as f64,
        zone.pos.1,
        w,
        zone.size.1,
    )
}

/// `AiDeployment._nearest_objective_distance` (ai_deployment.gd:257-263): the
/// nearest marker; none at all → the rect centre (coherent form-up).
fn nearest_objective_distance(p: (f64, f64), objectives: &[(f64, f64)], r: &Rect) -> f64 {
    if objectives.is_empty() {
        return v2_dist(p, r.centre());
    }
    objectives.iter().map(|o| v2_dist(p, *o)).fold(f64::INFINITY, f64::min)
}

/// `AiDeployment._spot_free` (ai_deployment.gd:247-252): `<` blocks, so free
/// is the f32 distance NOT below the f64 radius sum.
fn spot_free(p: (f64, f64), radius: f64, occupied: &[Occupied]) -> bool {
    occupied.iter().all(|o| v2_dist(p, o.pos) >= radius + o.radius)
}

/// `AiDeployment.best_spot` (ai_deployment.gd:97-115): y-outer/x-inner scan,
/// `x` restarting per row from the same expression (:103), repeated `+= step`
/// in f64, and a strict `<` that keeps the FIRST minimum in scan order — the
/// iteration order and tie rule are part of the law. Candidates narrow to f32
/// like the `Vector2(x, y)` ctor; the margins narrow like the Vector2
/// `footprint_margins` returns. Blocked law via `blocked` (the caller binds
/// board + unit shape — the invalid-Callable path of :106 is `|_| false`).
#[allow(clippy::too_many_arguments)]
pub fn best_spot(
    section: &Rect,
    objectives: &[(f64, f64)],
    occupied: &[Occupied],
    radius: f64,
    blocked: &dyn Fn((f64, f64)) -> bool,
    step: f64,
    footprint: &[(f64, f64)],
    base_r: f64,
    forward_y: f64,
) -> (f64, f64) {
    let (mut best, mut best_score) = ((f64::INFINITY, f64::INFINITY), f64::INFINITY);
    let (mx, my) = footprint_margins(radius, footprint, base_r);
    let (mx, my) = (mx as f32 as f64, my as f32 as f64);
    let end = section.end();
    let mut y = section.pos.1 + my;
    while y <= end.1 - my + SCAN_EPS {
        let mut x = section.pos.0 + mx;
        while x <= end.0 - mx + SCAN_EPS {
            let p = (x as f32 as f64, y as f32 as f64);
            if spot_free(p, radius, occupied) && !blocked(p) {
                let mut score = nearest_objective_distance(p, objectives, section);
                if forward_y != f64::INFINITY {
                    score += FORWARD_EDGE_W * (p.1 - forward_y).abs();
                }
                if score < best_score {
                    best_score = score;
                    best = p;
                }
            }
            x += step;
        }
        y += step;
    }
    best
}

/// `AiDeployment._blocked_count` (ai_deployment.gd:151-165): blocked SAMPLE
/// count over the exact multiset `_blocked_at` early-returns on — "0 here" ==
/// "clear there". Neither branch skips the zero edge (:157-165), so the centre
/// counts too. `(p + off) + e` stays left-associated f32.
fn blocked_count(
    p: (f64, f64),
    blocked: &dyn Fn((f64, f64)) -> bool,
    base_r: f64,
    footprint: &[(f64, f64)],
) -> i64 {
    let edges = disc_sample_offsets(base_r);
    let (px, py) = (p.0 as f32, p.1 as f32);
    let mut n = 0i64;
    if !footprint.is_empty() {
        for off in footprint {
            let m = [px + off.0 as f32, py + off.1 as f32];
            for e in &edges {
                if blocked(((m[0] + e[0]) as f64, (m[1] + e[1]) as f64)) {
                    n += 1;
                }
            }
        }
        return n;
    }
    for e in &edges {
        if blocked(((px + e[0]) as f64, (py + e[1]) as f64)) {
            n += 1;
        }
    }
    n
}

/// `AiDeployment.least_blocked_spot` (ai_deployment.gd:125-144): fewest blocked
/// samples, tie toward the nearest objective. THE DEGENERATE INITIAL VALUE is
/// law: `best` starts at the zone centre, and a footprint whose margins cannot
/// fit the zone never reaches a candidate — the centre returns UNTESTED (the
/// fixture's 20 zone-centre landings pin it).
#[allow(clippy::too_many_arguments)]
pub fn least_blocked_spot(
    zone: &Rect,
    objectives: &[(f64, f64)],
    radius: f64,
    blocked: &dyn Fn((f64, f64)) -> bool,
    step: f64,
    base_r: f64,
    footprint: &[(f64, f64)],
) -> (f64, f64) {
    let mut best = zone.centre();
    let (mut best_blocked, mut best_score) = (f64::INFINITY, f64::INFINITY);
    let (mx, my) = footprint_margins(radius, footprint, base_r);
    let (mx, my) = (mx as f32 as f64, my as f32 as f64);
    let end = zone.end();
    let mut y = zone.pos.1 + my;
    while y <= end.1 - my + SCAN_EPS {
        let mut x = zone.pos.0 + mx;
        while x <= end.0 - mx + SCAN_EPS {
            let p = (x as f32 as f64, y as f32 as f64);
            let bc = blocked_count(p, blocked, base_r, footprint);
            let score = nearest_objective_distance(p, objectives, zone);
            if (bc as f64) < best_blocked || ((bc as f64) == best_blocked && score < best_score) {
                best_blocked = bc as f64;
                best_score = score;
                best = p;
            }
            x += step;
        }
        y += step;
    }
    best
}
