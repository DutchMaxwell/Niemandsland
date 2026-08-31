//! NML-1152 step 2 — the arena pre-game's shared seam: the roll-off and the per-side
//! deploy seeds. The roll-off consumes the GAME stream (`solo._rng`, arena_match.gd:373
//! → :462) BEFORE deployment; each side's deployment gets a FRESH stream seeded
//! `game_seed + slot` attached to the SLOT (arena_match.gd:487), never the game stream.
//! `roll_off_traced` mirrors `SoloController.roll_off` (solo_controller.gd:7507-7524):
//! 2 `randi_range(1, 6)` draws per attempt, ties re-roll, cap 100 — trace kept because
//! the attempt count is data-dependent (the gate compares the FULL attempt list).

use crate::rng::GodotRng;
use std::collections::HashMap;
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

/// One shape group of a unit's deployment models (step 6c): the unit's OWN
/// models first, then each attached hero's (solo_controller.gd:_deploy_models
/// :10239-10245) — `n` models carry this group's base at the group's Tough
/// scale. Derived py-side (`list_to_profile.deploy_base_groups`); the corpus
/// carries ≤ 2 groups (host + one hero), per-model toughs uniform.
#[derive(Debug, Clone, PartialEq)]
pub struct ModelShape {
    pub is_oval: bool,
    pub w_mm: i64,
    pub d_mm: i64,
    pub tough: i64,
    pub n: usize,
}

/// Pregame input for one unit, built py-side from the list profile (§3.2).
#[derive(Debug, Clone, PartialEq, Default)]
pub struct UnitSpec {
    pub key: String,
    pub model_count: i64,
    /// After 6c this is NO production input (the ladder reads
    /// `deploy_base_radius_of`) — it stays as the gate's cross-check artifact
    /// (derived vs the dump's snapped value).
    pub base_r_m: f64,
    pub footprint: Vec<(f64, f64)>,
    pub scout: bool,
    pub ambush: bool,
    pub ignores_terrain: bool,
    pub vanguard: bool,
    pub transport_capacity: i64,
    /// The deploy yaw (the model node's `global_rotation.y`; 0.0 corpus-wide).
    pub facing_rad: f64,
    /// The true per-model shape groups (empty only for callers that never
    /// reach the settle pass — checked at the SettleUnit build).
    pub model_shapes: Vec<ModelShape>,
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

/// One probe-sphere-vs-blocker test (ai_deployment.gd:300-309). NML-1152 step
/// 4d: banks WITH `blocker_boxes` test the REAL collision footprints — exact
/// circle-vs-OBB, the sample point against the oriented box the dump harvested
/// from the body's CollisionShape3D + global transform (containers
/// terrain_overlay.gd:2886-2891/:3153-3158, shell + procedural walls
/// :1967-1972/:2062-2067, corner posts :1910-1915), dilated by that box's own
/// `reach` — the probe sphere's XZ reach past THIS box (0.02² − dy²)¹ᐟ² with
/// dy the sphere's y-gap to the box, dump-side per box). This closes the
/// 2.1 mm ring the WALL layer cannot: `walls` carries wall-body centrelines,
/// its band reaches only 0.02 − 0.125" past a wall surface, the probe reaches
/// 0.0189 m (measured). Banks WITHOUT the key keep the incircle-disc law below
/// (default-preserving); the box law REPLACES the discs when present — the
/// discs are the containers' incircles, strictly inside the wall band around
/// the box outline (the step-4c derivation), so mixing both would only add
/// boundary noise.
pub fn prop_blocked(board: &Terrain, p: (f64, f64)) -> bool {
    let boxes = board.blocker_boxes_m();
    if !boxes.is_empty() {
        return boxes.iter().any(|b| {
            let (dx, dy) = (p.0 - b[0], p.1 - b[1]);
            // The dump's angle θ = atan2(−basis.x.z, basis.x.x): the box's
            // local X axis is (cos θ, −sin θ) in the (x, z) frame, its local
            // Z axis (sin θ, cos θ) — Godot yaw (Basis from rotation.y).
            let (c, s) = (b[4].cos(), b[4].sin());
            let (lx, ly) = (dx * c - dy * s, dx * s + dy * c);
            let (qx, qy) = (lx.clamp(-b[2], b[2]), ly.clamp(-b[3], b[3]));
            let (ex, ey) = (lx - qx, ly - qy);
            (ex * ex + ey * ey).sqrt() < b[5]
        });
    }
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
/// `RulesRegistry.unit_param(unit, "Vanguard", "place_in", 9.0)`
/// (solo_controller.gd:9627), world metres.
pub const VANGUARD_PLACE_M: f64 = 9.0 * 0.0254;

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
pub fn nearest_objective_distance(p: (f64, f64), objectives: &[(f64, f64)], r: &Rect) -> f64 {
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

// ---- the veto, the push, the ladder (NML-1152 step 5b). Wall geometry runs in
// WORLD METRES — the shape `main.gd:2316`'s walls_provider hands the planner
// (`get_wall_segments_world()`, Vector2 = f32) — and its SCALAR arithmetic is
// f64 on widened f32 components (GDScript floats are doubles; only Vector2 ops
// are real_t — the deployment.rs:303-313 precedent).

/// One wall segment, world metres, f32 at the Vector2 boundary.
pub type WallSeg = [[f32; 2]; 2];

/// `MovementPlanner._orient` (movement_planner.gd:91-93): signed area ×2 of
/// triangle abc — >0 left turn, <0 right turn, ~0 collinear; f64 products of
/// widened f32 components.
fn orient(a: [f32; 2], b: [f32; 2], c: [f32; 2]) -> f64 {
    let (ax, ay, bx, by, cx, cy) =
        (a[0] as f64, a[1] as f64, b[0] as f64, b[1] as f64, c[0] as f64, c[1] as f64);
    (bx - ax) * (cy - ay) - (by - ay) * (cx - ax)
}

/// `MovementPlanner._on_segment` (:96-99): collinear point in the bbox + EPS.
fn on_segment(a: [f32; 2], b: [f32; 2], p: [f32; 2]) -> bool {
    let (ax, bx, px) = (a[0] as f64, b[0] as f64, p[0] as f64);
    let (ay, by, py) = (a[1] as f64, b[1] as f64, p[1] as f64);
    px >= ax.min(bx) - SCAN_EPS
        && px <= ax.max(bx) + SCAN_EPS
        && py >= ay.min(by) - SCAN_EPS
        && py <= ay.max(by) + SCAN_EPS
}

/// `MovementPlanner.segments_cross` (movement_planner.gd:104-133): touching
/// counts as crossing (a path grazing a wall end is blocked — the safe side).
fn segments_cross(p1: [f32; 2], p2: [f32; 2], p3: [f32; 2], p4: [f32; 2]) -> bool {
    let (d1, d2, d3, d4) =
        (orient(p3, p4, p1), orient(p3, p4, p2), orient(p1, p2, p3), orient(p1, p2, p4));
    if ((d1 > 0.0 && d2 < 0.0) || (d1 < 0.0 && d2 > 0.0))
        && ((d3 > 0.0 && d4 < 0.0) || (d3 < 0.0 && d4 > 0.0))
    {
        return true;
    }
    (d1.abs() <= SCAN_EPS && on_segment(p3, p4, p1))
        || (d2.abs() <= SCAN_EPS && on_segment(p3, p4, p2))
        || (d3.abs() <= SCAN_EPS && on_segment(p1, p2, p3))
        || (d4.abs() <= SCAN_EPS && on_segment(p1, p2, p4))
}

/// `MovementPlanner.path_crosses_wall` (movement_planner.gd:141-145).
fn path_crosses_wall(a: (f64, f64), b: (f64, f64), walls: &[WallSeg]) -> bool {
    let (af, bf) = ([a.0 as f32, a.1 as f32], [b.0 as f32, b.1 as f32]);
    walls.iter().any(|w| segments_cross(af, bf, w[0], w[1]))
}

/// `SoloController._deploy_footprint_bisected` (solo_controller.gd:9584-9598):
/// a formation grid a wall cuts in half is vetoed — any model-to-model link
/// within one grid pitch + slack (f64) that crosses a wall. `a`/`b` are
/// Vector2 adds (f32), the distance gate f32-vs-f64 exactly like `_spot_free`.
pub fn footprint_bisected(
    spot: (f64, f64),
    footprint: &[(f64, f64)],
    base_r: f64,
    walls: &[WallSeg],
) -> bool {
    if walls.is_empty() || footprint.len() <= 1 {
        return false;
    }
    let link_max = base_r * 3.0 + 0.03;
    for i in 0..footprint.len() {
        for j in i + 1..footprint.len() {
            let a = v2_add(spot, footprint[i]);
            let b = v2_add(spot, footprint[j]);
            if v2_dist(a, b) > link_max {
                continue;
            }
            if path_crosses_wall(a, b, walls) {
                return true;
            }
        }
    }
    false
}

/// `SoloController._deploy_spot_clear` (solo_controller.gd:9640-9652): the
/// vanguard candidate's legality — occupied rings, per-MODEL-CENTRE terrain
/// (no base edges: the table's own law) and no wall bisect.
#[allow(clippy::too_many_arguments)]
fn deploy_spot_clear(
    spot: (f64, f64),
    occupied: &[Occupied],
    blocked: &dyn Fn((f64, f64)) -> bool,
    radius: f64,
    footprint: &[(f64, f64)],
    base_r: f64,
    walls: &[WallSeg],
) -> bool {
    if occupied.iter().any(|o| v2_dist(spot, o.pos) < radius + o.radius) {
        return false;
    }
    let (sx, sy) = (spot.0 as f32, spot.1 as f32);
    if footprint
        .iter()
        .any(|off| blocked(((sx + off.0 as f32) as f64, (sy + off.1 as f32) as f64)))
    {
        return false;
    }
    !footprint_bisected(spot, footprint, base_r, walls)
}

/// `SoloController._vanguard_push` (solo_controller.gd:9620-9635): toward the
/// table centre at 100/75/50/25 % of the 9" placement (`push_m` — the
/// registry's place_in, 9.0 in the corpus), first legal candidate wins; the
/// pushed spot MAY leave the zone. Vector2·scalar narrows the scalar to f32.
#[allow(clippy::too_many_arguments)]
pub fn vanguard_push(
    spot: (f64, f64),
    zone: &Rect,
    occupied: &[Occupied],
    blocked: &dyn Fn((f64, f64)) -> bool,
    radius: f64,
    footprint: &[(f64, f64)],
    base_r: f64,
    walls: &[WallSeg],
    push_m: f64,
) -> (f64, f64) {
    let c = zone.centre();
    let (mut fx, mut fy) = (0.0f32 - c.0 as f32, 0.0f32 - c.1 as f32);
    let len = (fx * fx + fy * fy).sqrt();
    if (len as f64) < 0.001 {
        return spot;
    }
    fx /= len;
    fy /= len;
    for frac in [1.0f64, 0.75, 0.5, 0.25] {
        let s = (push_m * frac) as f32;
        let cand = v2_add(spot, ((fx * s) as f64, (fy * s) as f64));
        if deploy_spot_clear(cand, occupied, blocked, radius, footprint, base_r, walls) {
            return cand;
        }
    }
    spot
}

/// How the ladder landed: the spot, which rung produced it (0 = section scan,
/// 1 = whole-zone fallback, 2 = crowded/occupied-cleared, 3 = least_blocked —
/// the table's own `spot_why` ladder), how many wall-bisect marks were
/// appended (they persist in `occupied`, solo_controller.gd:9128), and whether
/// the Vanguard push moved the unit (the dump's `vanguard_pushed`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PlaceOutcome {
    pub spot: (f64, f64),
    pub rung: u8,
    pub bisect_marks: u8,
    pub pushed: bool,
}

/// `SoloController._deploy_place_id` (solo_controller.gd:9086-9170) for the
/// MAIN queue (the scout's 12" band is slice 6): objective-near scan in the
/// unit's section, then the LADDER in the table's exact order — wall-bisect
/// veto (≤4, marks at 0.6·radius PERSIST in `occupied`, :9128) → whole-zone
/// (:9132) → crowded, occupied CLEARED (:9138) → least_blocked at 0.05
/// (:9144) — then the Vanguard push and this spot joins `occupied` at full
/// radius (:9170).
#[allow(clippy::too_many_arguments)]
pub fn deploy_place_id(
    zone: &Rect,
    sec: &Rect,
    forward_y: f64,
    objectives: &[(f64, f64)],
    occupied: &mut Vec<Occupied>,
    board: &Terrain,
    walls: &[WallSeg],
    radius: f64,
    footprint: &[(f64, f64)],
    base_r: f64,
    flying: bool,
    vanguard: bool,
) -> PlaceOutcome {
    let blocked =
        |p: (f64, f64)| spot_blocked(board, p, flying, radius, footprint, base_r);
    let mut spot =
        best_spot(sec, objectives, occupied, radius, &blocked, DEPLOY_SPOT_STEP_M, footprint, base_r, forward_y);
    let (mut rung, mut marks, mut pushed) = (0u8, 0u8, false);
    for _ in 0..4 {
        if spot.0.is_infinite() || !footprint_bisected(spot, footprint, base_r, walls) {
            break;
        }
        occupied.push(Occupied { pos: spot, radius: radius * 0.6 });
        marks += 1;
        spot = best_spot(
            sec, objectives, occupied, radius, &blocked, DEPLOY_SPOT_STEP_M, footprint, base_r, forward_y,
        );
    }
    if spot.0.is_infinite() {
        rung = 1;
        spot = best_spot(
            zone, objectives, occupied, radius, &blocked, DEPLOY_SPOT_STEP_M, footprint, base_r, forward_y,
        );
    }
    if spot.0.is_infinite() {
        rung = 2;
        spot = best_spot(
            zone, objectives, &[], radius, &blocked, DEPLOY_SPOT_STEP_M, footprint, base_r, forward_y,
        );
    }
    if spot.0.is_infinite() {
        rung = 3;
        spot = least_blocked_spot(zone, objectives, radius, &blocked, LEAST_BLOCKED_STEP_M, base_r, footprint);
    }
    if vanguard {
        let v = vanguard_push(spot, zone, occupied, &blocked, radius, footprint, base_r, walls, VANGUARD_PLACE_M);
        if v != spot {
            spot = v;
            pushed = true;
        }
    }
    occupied.push(Occupied { pos: spot, radius });
    PlaceOutcome { spot, rung, bisect_marks: marks, pushed }
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

// ---- the SIDE PIPELINE (NML-1152 step 6a). `deploy_begin` + the queue drain +
// `_place_unit_at`, replayed end-to-end: one fresh GodotRng per side seeded
// `seed_value` (solo_controller.gd:8944-8945) drawn IN ORDER — transport fill
// (:8957-8976) → split_into_groups (:8986) → assign_sections (:8987) →
// placement_order (:9038) — then each unit lands through the step-5 ladder and
// drops its models on the FIXED 0.04 m place grid (:10329-10346). The OCCUPIED
// set is the twin's OWN placements (:9044 `occupied: []`, appended per unit at
// :9170) — no longer the recorded spots; this is what makes the replay
// end-to-end. Two dispatched deferrals: the `deploy_finish` settle pass is step
// 6b, so `models` here are the PRE-settle grid (the fixture's `models` are the
// SETTLED node positions — the comparison classifies, it does not bit-assert);
// the scouts' 12" forward band is step 6b too — until then a scout searches
// its own section rect (the corpus carries 0 scouts either way). Latent gap,
// corpus-inert: filled cargo must leave the deploying roster before groups
// (:8981-8982) — the spec list is post-fill in production, all caps 0 here.

/// `_place_unit_at`'s loose-formation branch (solo_controller.gd:10329-10346):
/// the unit's `n` models on the FIXED compact grid — `cols = min(n, 5)` ranks
/// of `DEPLOY_COLS`, model i at column `i % DEPLOY_COLS` / row
/// `i / DEPLOY_COLS`, centred on the spot. GDScript scalars are doubles, the
/// Vector3 ctor narrows once to f32 — the scalar expression runs f64 and
/// narrows at the ctor. (The regiment-tray branch above it never occurs in the
/// corpus — no regiments.)
pub fn place_unit_models(spot: (f64, f64), n: usize) -> Vec<(f64, f64)> {
    if n == 0 {
        return Vec::new();
    }
    let cols = n.min(DEPLOY_COLS) as f64;
    let rows = n.div_ceil(DEPLOY_COLS) as f64;
    (0..n)
        .map(|i| {
            let (col, row) = ((i % DEPLOY_COLS) as f64, (i / DEPLOY_COLS) as f64);
            (
                ((spot.0 as f32 as f64) + (col - (cols - 1.0) * 0.5) * DEPLOY_SPACING_M) as f32 as f64,
                ((spot.1 as f32 as f64) + (row - (rows - 1.0) * 0.5) * DEPLOY_SPACING_M) as f32 as f64,
            )
        })
        .collect()
}

/// One side's whole pregame (design §3.2): `deploy_begin`'s draw phases on a
/// FRESH stream, then the queue drain — normals first, scouts last, ambush
/// reserved — through the table's placement ladder, occupied growing from the
/// twin's OWN placements. Walls for the bisect veto ride the board's own
/// load-time world-metre store (`Terrain::walls_world_m` — re-deriving from
/// the inch frame would quantize twice and shift by the frame offset).
pub fn deploy_side(
    specs: &[UnitSpec],
    zone: &Rect,
    objectives: &[(f64, f64)],
    board: &Terrain,
    seed_value: i64,
) -> SideDeploy {
    let mut rng = GodotRng::new(seed_value);
    let caps: Vec<i64> = specs.iter().map(|s| s.transport_capacity).collect();
    let fills = transport_fill(&caps, &mut rng);
    let mut out = SideDeploy {
        seed_value,
        fills: fills
            .iter()
            .map(|&(t, c)| (specs[t].key.clone(), specs[c].key.clone()))
            .collect(),
        placements: Vec::new(),
        reserved: Vec::new(),
    };
    if specs.is_empty() {
        return out; // deploy_begin's empty-roster early return (:8984)
    }
    let groups = split_into_groups(specs.len(), &mut rng);
    let sections = assign_sections(groups.len(), &mut rng);
    let mut section_of = vec![0i64; specs.len()];
    for (g, members) in groups.iter().enumerate() {
        for &i in members {
            section_of[i] = sections[g];
        }
    }
    out.reserved = specs.iter().filter(|s| s.ambush).map(|s| s.key.clone()).collect();
    let end = zone.end();
    let forward_y = if zone.pos.1.abs() < end.1.abs() { zone.pos.1 } else { end.1 };
    let walls = board.walls_world_m();
    let mut occupied: Vec<Occupied> = Vec::new();
    // placement_order's sequence IS the drain order: the main queue fully,
    // then the scout queue (:9036-9042 builds them in this order, :9195-9198
    // drains main-then-scout).
    for &i in placement_order(specs, &mut rng).iter() {
        let s = &specs[i];
        // the ladder threads ONE unit-max radius (solo_controller.gd:9106) —
        // the derived deploy radius over host + attached heroes (:10263-10267)
        let base_r = deploy_base_radius_of(s);
        let radius = deploy_footprint_radius(s.model_count.max(0) as usize, base_r);
        // B9 Scout (:9098-9102): a scout searches its zone EXTENDED 12" forward
        // (whole-width band, `scout_extended_zone`), forward_y recomputed on the
        // band, and its zone-of-record for the settle containment is the band.
        let (unit_zone, sec, fwd) = if s.scout {
            let ext = scout_extended_zone(zone, forward_y);
            let e = ext.end();
            let fwd_ext = if ext.pos.1.abs() < e.1.abs() { ext.pos.1 } else { e.1 };
            (ext, ext, fwd_ext)
        } else {
            (*zone, section_rect(zone, section_of[i]), forward_y)
        };
        let o = deploy_place_id(
            &unit_zone, &sec, fwd, objectives, &mut occupied, board, walls,
            radius, &s.footprint, base_r, s.ignores_terrain, s.vanguard,
        );
        out.placements.push(Placement {
            key: s.key.clone(),
            section: section_of[i],
            scout: s.scout,
            spot: o.spot,
            vanguard_pushed: o.pushed,
            models: place_unit_models(o.spot, s.model_count.max(0) as usize),
        });
    }
    // The FINISH (deploy_finish, solo_controller.gd:9180-9188) is NOT run
    // here — step 6d split placement from the finish so the caller drives the
    // table's per-side finish order: the first finish sweeps the first
    // deployer's units (the other army stands on its side tray and IS swept —
    // its nodes are live — but that sweep is ERASED by the side's later
    // placement, `_place_unit_at` rewrites every model), the second finish
    // re-sweeps BOTH rosters (the repair and the resolve CROSS SLOTS,
    // :9228-9232). `settle_units` rebuilds the live state,
    // `deploy_finish_all` runs one finish pass.
    out
}

// ---- the SETTLE pass (NML-1152 step 6b): `deploy_finish` →
// `_resolve_deploy_overlaps` (solo_controller.gd:9497-9577), 4 Gauss-Seidel
// sweeps over every on-table unit: (a) separate the unit's OWN bases to
// contact, (b) shift the WHOLE unit rigidly out of every other unit's bases
// (wall-clamped), per-model projected out of forbidden rest, (c) re-separate
// own, (d) minimal whole-unit re-shift into the recorded zone. Step 6c: every
// model carries its TRUE base shape — `shape_for_model`'s ROUND/OVAL law
// (separation_checker.gd:267-279) at the model's Tough scale, the host's
// models first then each attached hero's (`_deploy_models` :10239-10245).
// Godot's Vector2 is f32 (real_t) while GDScript scalars are f64 — centres and
// the resultant accumulate in f32, radii and edge gaps in f64, narrowed at
// every Vector2 boundary, exactly like the table.

/// `OPRApiClient._base_size_from_tough` (opr_api_client.gd:704-715) — the base
/// long edge (mm) a model's Tough alone justifies. 0 = normal infantry.
pub fn base_size_from_tough(tough: i64) -> f64 {
    if tough >= 18 {
        150.0
    } else if tough >= 12 {
        120.0
    } else if tough >= 9 {
        80.0
    } else if tough >= 6 {
        60.0
    } else if tough >= 3 {
        40.0
    } else {
        0.0
    }
}

/// One model's settle geometry: `SeparationChecker.shape_for_model`
/// (separation_checker.gd:267-279) at the group's Tough scale
/// (`OPRArmyManager.model_base_long_mm`, opr_army_manager.gd:1459-1460 — the
/// unit base vs the Tough-justified edge, never smaller) and the unit's deploy
/// yaw. Round reads the long edge (base_size_round); oval keeps w×d.
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SettleShapeGeom {
    pub oval: bool,
    pub radius: f64,
    pub semi_x: f64,
    pub semi_z: f64,
    pub yaw: f32,
}

impl SettleShapeGeom {
    fn build(is_oval: bool, w_mm: i64, d_mm: i64, tough: i64, yaw: f64) -> Self {
        let long = (w_mm.max(d_mm)) as f64;
        let scale = long.max(base_size_from_tough(tough)) / long.max(1.0);
        if is_oval {
            SettleShapeGeom {
                oval: true,
                radius: 0.0,
                semi_x: (w_mm as f64 / 2.0) * 0.001 * scale,
                semi_z: (d_mm as f64 / 2.0) * 0.001 * scale,
                yaw: yaw as f32,
            }
        } else {
            SettleShapeGeom {
                oval: false,
                radius: long / 2.0 * 0.001 * scale,
                semi_x: 0.0,
                semi_z: 0.0,
                yaw: yaw as f32,
            }
        }
    }

    /// `BaseShape.bounding_radius` (separation_checker.gd:137-140).
    fn bounding_radius(&self) -> f64 {
        if !self.oval {
            return self.radius;
        }
        (self.semi_x * self.semi_x + self.semi_z * self.semi_z).sqrt()
    }

    /// `SeparationChecker._min_extent` (:331-334) — the concentric fallback.
    fn min_extent(&self) -> f64 {
        if !self.oval {
            return self.radius;
        }
        self.semi_x.min(self.semi_z)
    }

    fn settle_shape(&self, center: [f32; 2]) -> SettleShape {
        SettleShape {
            center,
            oval: self.oval,
            radius: self.radius,
            semi_x: self.semi_x,
            semi_z: self.semi_z,
            yaw: self.yaw,
        }
    }
}

/// Per-model settle geometry for one spec, expanded in `_deploy_models` order
/// (:10239-10245 — host models first, then each attached hero's).
pub fn settle_shape_geoms(spec: &UnitSpec) -> Vec<SettleShapeGeom> {
    let mut out = Vec::new();
    for g in &spec.model_shapes {
        for _ in 0..g.n {
            out.push(SettleShapeGeom::build(g.is_oval, g.w_mm, g.d_mm, g.tough, spec.facing_rad));
        }
    }
    out
}

/// `solo_controller.gd:_deploy_base_radius` (:10263-10267): the largest
/// bounding radius among the unit's deployment models (host + attached
/// heroes), floored at `SeparationChecker.DEFAULT_BASE_RADIUS_M` (0.016) —
/// the scalar the footprint/ladder law consumes.
pub fn deploy_base_radius_of(spec: &UnitSpec) -> f64 {
    let mut r = 0.016f64;
    for g in &spec.model_shapes {
        r = r.max(SettleShapeGeom::build(g.is_oval, g.w_mm, g.d_mm, g.tough, spec.facing_rad).bounding_radius());
    }
    r
}

/// One on-table unit during the settle: live model centres (f32, the
/// `Vector3.global_position` boundary), each model's base geometry (same
/// order as `models`), its recorded containment zone (`_deploy_zone_of` —
/// the side zone, the scout's extended band for scouts; Vanguard pushes
/// erase it, :9159 — corpus-inert).
#[derive(Debug, Clone)]
pub struct SettleUnit {
    pub models: Vec<[f32; 2]>,
    pub geoms: Vec<SettleShapeGeom>,
    pub zone: Rect,
    /// The unit's Strider/Flying law (:9246 picks the coherency repair's
    /// blocked variant from it) — `UnitSpec.ignores_terrain`'s predicate.
    pub flying: bool,
}

/// A base for the settle math: f32 centre (Vector2), f64 extents (the
/// BaseShape's Variant floats), f32 yaw.
#[derive(Debug, Clone, Copy)]
struct SettleShape {
    center: [f32; 2],
    oval: bool,
    radius: f64,
    semi_x: f64,
    semi_z: f64,
    yaw: f32,
}

impl SettleShape {
    fn bounding_radius(&self) -> f64 {
        if !self.oval {
            return self.radius;
        }
        (self.semi_x * self.semi_x + self.semi_z * self.semi_z).sqrt()
    }

    /// `SeparationChecker._min_extent` (:331-334).
    fn min_extent(&self) -> f64 {
        if !self.oval {
            return self.radius;
        }
        self.semi_x.min(self.semi_z)
    }
}

/// `SeparationChecker._support_extent` (:307-319) — distance (metres) from the
/// shape's centre to its boundary along unit-direction `dir`: round exact;
/// oval the ellipse support, `dir.rotated(-yaw)` computed in f32 (Vector2 is
/// real_t — the angle narrows BEFORE the f32 sin/cos), then the formula in f64
/// with the table's left-to-right product order.
fn support_extent(shape: &SettleShape, dir: [f32; 2]) -> f64 {
    if !shape.oval {
        return shape.radius;
    }
    let ang = -shape.yaw;
    let (sn, c) = (ang.sin(), ang.cos());
    let lx = (dir[0] * c - dir[1] * sn) as f64;
    let ly = (dir[0] * sn + dir[1] * c) as f64;
    let a = shape.semi_x;
    let b = shape.semi_z;
    let denom = ((b * b * lx) * lx + (a * a * ly) * ly).sqrt();
    if denom < 0.00001 {
        return (a + b) * 0.5;
    }
    (a * b) / denom
}

/// `SeparationChecker._edge_distance_meters` (:290-302) + `edge_distance`
/// (:147-150): round-round exact (:294-295); oval-involved via centre-line
/// support witnesses (:297-302, concentric fallback −min extent :300) — no
/// RECT branch exists (`shape_for_model` has none). Vector2 f32 centres and
/// direction, f64 extents, ÷ INCHES_TO_METERS → inches, f64.
fn edge_distance_in(a: &SettleShape, b: &SettleShape) -> f64 {
    if !a.oval && !b.oval {
        let (dx, dy) = (a.center[0] - b.center[0], a.center[1] - b.center[1]);
        return (((dx * dx + dy * dy).sqrt()) as f64 - a.radius - b.radius) / 0.0254;
    }
    let dx = b.center[0] - a.center[0];
    let dy = b.center[1] - a.center[1];
    let center_dist = (dx * dx + dy * dy).sqrt();
    if (center_dist as f64) < 0.00001 {
        return -a.min_extent().min(b.min_extent());
    }
    let dir = [dx / center_dist, dy / center_dist];
    (center_dist as f64 - support_extent(a, dir) - support_extent(b, [-dir[0], -dir[1]])) / 0.0254
}

/// B9: the deployment zone extended 12" toward the table centre — the Scout
/// band (solo_controller.gd:9051-9055; Rect2 ctor + Vector2 size add f32).
pub fn scout_extended_zone(zone: &Rect, forward_y: f64) -> Rect {
    let ext = 12.0 * 0.0254;
    let e = zone.end();
    if (forward_y - e.1).abs() < (forward_y - zone.pos.1).abs() {
        Rect::new(zone.pos.0, zone.pos.1, zone.size.0, zone.size.1 + ext)
    } else {
        Rect::new(zone.pos.0, zone.pos.1 - ext, zone.size.0, zone.size.1 + ext)
    }
}

/// `SeparationResolver` constants (separation_resolver.gd:46-59).
const RESOLVE_EPSILON_IN: f64 = 0.01;
const MAX_OVERLAP_ITERATIONS: usize = 24;
const ESCAPE_SCAN_DIRECTIONS: usize = 24;
/// `SeparationZone.EPSILON_M` (separation_zone.gd:44) squared, f32 like the
/// `length_squared` it is compared against.
const SEP_EPSILON_M2: f32 = 1.0e-10;

/// `SeparationResolver.resolve_overlaps` (separation_resolver.gd:98-128): the
/// item is RIGID — every relaxation step translates ALL its shapes by one
/// f32 Vector2 — so the returned translation applies to the caller's own
/// copy. Resultant of penetration vectors (inches, f32 accumulation) ×
/// INCHES_TO_METERS per step; ≤ 24 iterations; the symmetric-wedge case
/// (resultant cancels, overlap remains) breaks to the escape scan; the scan
/// also runs after a completed non-clearing loop. Returns the total applied
/// translation (metres, f32 components).
fn resolve_overlaps(item: &mut [SettleShape], obstacles: &[SettleShape]) -> [f32; 2] {
    if item.is_empty() || obstacles.is_empty() {
        return [0.0, 0.0];
    }
    let mut applied = [0.0f32, 0.0];
    for _ in 0..MAX_OVERLAP_ITERATIONS {
        let mut resultant = [0.0f32, 0.0];
        let mut deepest = 0.0f64;
        for s in item.iter() {
            for o in obstacles {
                let overlap = -edge_distance_in(s, o);
                if overlap <= RESOLVE_EPSILON_IN {
                    continue;
                }
                let mut axis = [s.center[0] - o.center[0], s.center[1] - o.center[1]];
                if axis[0] * axis[0] + axis[1] * axis[1] < SEP_EPSILON_M2 {
                    axis = [1.0, 0.0]; // Vector2.RIGHT — concentric escape axis
                }
                let len = (axis[0] * axis[0] + axis[1] * axis[1]).sqrt();
                let ov = overlap as f32; // Vector2 * float narrows the scalar
                resultant[0] += axis[0] / len * ov;
                resultant[1] += axis[1] / len * ov;
                deepest = deepest.max(overlap);
            }
        }
        if deepest <= RESOLVE_EPSILON_IN {
            return applied; // cleared
        }
        let rlen = (resultant[0] * resultant[0] + resultant[1] * resultant[1]).sqrt() as f64;
        if rlen < RESOLVE_EPSILON_IN {
            break; // symmetric wedge — the escape scan takes over
        }
        let step = [resultant[0] * 0.0254, resultant[1] * 0.0254];
        for s in item.iter_mut() {
            s.center[0] += step[0];
            s.center[1] += step[1];
        }
        applied[0] += step[0];
        applied[1] += step[1];
    }
    let esc = escape_to_clear(item, obstacles);
    applied[0] += esc[0];
    applied[1] += esc[1];
    applied
}

/// `SeparationResolver._travel_to_clear_along` (:156-170): the smallest slide
/// along unit direction `u` that clears every pair on BOUNDING circles — per
/// pair the quadratic's upper root, max across pairs. f32 centre math, f64
/// travel.
fn travel_to_clear_along(item: &[SettleShape], obstacles: &[SettleShape], u: [f32; 2]) -> f64 {
    let mut travel = 0.0f64;
    for s in item {
        for o in obstacles {
            let r_sum = s.bounding_radius() + o.bounding_radius();
            let (ex, ey) = (s.center[0] - o.center[0], s.center[1] - o.center[1]);
            let e_len_sq = (ex * ex + ey * ey) as f64;
            if e_len_sq >= r_sum * r_sum {
                continue;
            }
            let e_dot_u = (ex * u[0] + ey * u[1]) as f64;
            let disc = e_dot_u * e_dot_u - e_len_sq + r_sum * r_sum;
            let t_pair = -e_dot_u + disc.max(0.0).sqrt();
            travel = travel.max(t_pair);
        }
    }
    travel
}

/// `SeparationResolver._escape_to_clear` (:136-150): scan 24 directions, take
/// the one needing the least travel, translate the item there. Returns the
/// step (metres) — ZERO when already clear.
fn escape_to_clear(item: &mut [SettleShape], obstacles: &[SettleShape]) -> [f32; 2] {
    let (mut best_dir, mut best_travel) = ([0.0f32, 0.0], f64::INFINITY);
    for k in 0..ESCAPE_SCAN_DIRECTIONS {
        let ang = std::f64::consts::TAU * k as f64 / ESCAPE_SCAN_DIRECTIONS as f64;
        let u = [ang.cos() as f32, ang.sin() as f32]; // Vector2 ctor narrows
        let travel = travel_to_clear_along(item, obstacles, u);
        if travel < best_travel {
            best_travel = travel;
            best_dir = u;
        }
    }
    if !(best_travel > 0.0) || best_travel == f64::INFINITY {
        return [0.0, 0.0];
    }
    let step = [best_dir[0] * best_travel as f32, best_dir[1] * best_travel as f32];
    for s in item.iter_mut() {
        s.center[0] += step[0];
        s.center[1] += step[1];
    }
    step
}

/// `_world_forbidden` (solo_controller.gd:6790-6800): (i) terrain —
/// `TerrainRules.base_in_terrain` (:108-122): the base CENTRE plus a 16-point
/// ring at the base edge, `is_forbidden_rest` = CONTAINER only
/// (terrain_rules.gd:80-88; the ring offset narrows at the Vector3 ctor);
/// (ii) wall segments at `radius + WALL_REST_CLEARANCE_M` (0.002 m,
/// solo_controller.gd:6775) — `MovementPlanner.point_seg_distance` called with
/// world-metre walls, so the metre EPS applies (the planner helper is
/// frame-free; `point_seg_distance_in` with in2m = 1 reproduces it).
fn world_forbidden(board: &Terrain, walls: &[WallSeg], p: (f64, f64), r: f64) -> bool {
    let on_container = |q: [f32; 2]| board.type_at([q[0], 0.0, q[1]]) == CONTAINER;
    if on_container([p.0 as f32, p.1 as f32]) {
        return true;
    }
    if r > 0.0
        && (0..16).any(|k| {
            let ang = std::f64::consts::TAU * k as f64 / 16.0;
            let e = [(p.0 as f32) + (ang.cos() * r) as f32, (p.1 as f32) + (ang.sin() * r) as f32];
            on_container(e)
        })
    {
        return true;
    }
    let q = [p.0 as f32, p.1 as f32];
    walls.iter().any(|w| {
        (point_seg_distance_in(q, w[0], w[1], 1.0) as f64) <= r + 0.002
    })
}

/// `_resolve_deploy_overlaps` (solo_controller.gd:9497-9577): 4 sweeps
/// (`OVERLAP_GATE_PASSES`, :149) over every on-table unit in array order.
/// External obstacles = every OTHER unit's CURRENT bases (live positions,
/// `:6676-6695`; aircraft excluded — none in the corpus).
pub fn resolve_deploy_overlaps(units: &mut [SettleUnit], board: &Terrain, walls: &[WallSeg]) {
    for _sweep in 0..4 {
        for ui in 0..units.len() {
            let n = units[ui].models.len();
            if n == 0 {
                continue;
            }
            // (a) INTERNAL (:9511-9524): 4 passes of per-model Gauss-Seidel —
            // each model's shape against ALL its own unit's others, shapes
            // mutated in place, cfg written back after the passes.
            {
                let mut shapes: Vec<SettleShape> = units[ui]
                    .models
                    .iter()
                    .zip(&units[ui].geoms)
                    .map(|(m, g)| g.settle_shape(*m))
                    .collect();
                for _p in 0..4 {
                    for i in 0..n {
                        let others: Vec<SettleShape> = (0..n)
                            .filter(|&j| j != i)
                            .map(|j| shapes[j])
                            .collect();
                        let mut item = [shapes[i]];
                        resolve_overlaps(&mut item, &others);
                        shapes[i] = item[0];
                    }
                }
                for (i, s) in shapes.iter().enumerate() {
                    units[ui].models[i] = s.center;
                }
            }
            // (b) EXTERNAL (:9525-9542): the whole unit as ONE rigid item
            // against every other unit's live bases; the returned translation
            // is wall-clamped (ANY model's path crossing → dropped entirely,
            // overlap debt stays, :9529-9538), then every model is projected
            // out of forbidden rest (:9539-9542).
            let obstacles: Vec<SettleShape> = units
                .iter()
                .enumerate()
                .filter(|&(uj, _)| uj != ui)
                .flat_map(|(_, u)| {
                    u.models
                        .iter()
                        .zip(&u.geoms)
                        .map(move |(m, g)| g.settle_shape(*m))
                })
                .collect();
            let mut shapes: Vec<SettleShape> = units[ui]
                .models
                .iter()
                .zip(&units[ui].geoms)
                .map(|(m, g)| g.settle_shape(*m))
                .collect();
            let delta = resolve_overlaps(&mut shapes, &obstacles);
            let mut delta = delta;
            if (delta[0] * delta[0] + delta[1] * delta[1]).sqrt() as f64 > 0.0005 {
                for m in units[ui].models.iter() {
                    if path_crosses_wall(
                        (m[0] as f64, m[1] as f64),
                        ((m[0] + delta[0]) as f64, (m[1] + delta[1]) as f64),
                        walls,
                    ) {
                        delta = [0.0, 0.0];
                        break;
                    }
                }
            }
            for (m, g) in units[ui]
                .models
                .iter_mut()
                .zip(&units[ui].geoms)
            {
                let projected = project_out_forbidden(
                    board,
                    walls,
                    ((m[0] + delta[0]) as f64, (m[1] + delta[1]) as f64),
                    g.bounding_radius(),
                );
                *m = [projected.0 as f32, projected.1 as f32];
            }
            // (c) re-separate own to contact (:9543-9557) — same shape as (a).
            {
                let mut shapes: Vec<SettleShape> = units[ui]
                    .models
                    .iter()
                    .zip(&units[ui].geoms)
                    .map(|(m, g)| g.settle_shape(*m))
                    .collect();
                for _p in 0..4 {
                    for i in 0..n {
                        let others: Vec<SettleShape> = (0..n)
                            .filter(|&j| j != i)
                            .map(|j| shapes[j])
                            .collect();
                        let mut item = [shapes[i]];
                        resolve_overlaps(&mut item, &others);
                        shapes[i] = item[0];
                    }
                }
                for (i, s) in shapes.iter().enumerate() {
                    units[ui].models[i] = s.center;
                }
            }
            // (d) ZONE containment (:9558-9576, Bug 8): if any base left the
            // unit's recorded zone, shift the WHOLE unit minimally back in —
            // dropped when the shift would tunnel any model through a wall.
            // Per-model radius both here and in the shift (`_deploy_cfg_in_zone`
            // :9466-9476 and `_deploy_zone_reshift` :9482-9496 walk
            // `model_base_radius_m(models[i])` inside their loops).
            let zone = units[ui].zone;
            let zend = zone.end();
            let radius_at =
                |i: usize| -> f64 { units[ui].geoms[i].bounding_radius() };
            let out_of_zone = units[ui]
                .models
                .iter()
                .enumerate()
                .any(|(i, m)| {
                    let r = radius_at(i);
                    (m[0] as f64 - r) < zone.pos.0
                        || (m[0] as f64 + r) > zend.0
                        || (m[1] as f64 - r) < zone.pos.1
                        || (m[1] as f64 + r) > zend.1
                });
            if out_of_zone {
                let mut shift = (0.0f64, 0.0f64);
                for (i, m) in units[ui].models.iter().enumerate() {
                    let r = radius_at(i);
                    let (px, pz) = (m[0] as f64, m[1] as f64);
                    shift.0 = shift.0.max(zone.pos.0 - (px - r + shift.0));
                    shift.0 = shift.0.min(zend.0 - (px + r + shift.0));
                    shift.1 = shift.1.max(zone.pos.1 - (pz - r + shift.1));
                    shift.1 = shift.1.min(zend.1 - (pz + r + shift.1));
                }
                let zshift = [shift.0 as f32, shift.1 as f32]; // Vector2 ctor
                let wall_ok = !units[ui].models.iter().any(|m| {
                    path_crosses_wall(
                        (m[0] as f64, m[1] as f64),
                        ((m[0] + zshift[0]) as f64, (m[1] + zshift[1]) as f64),
                        walls,
                    )
                });
                if wall_ok {
                    for m in units[ui].models.iter_mut() {
                        *m = [m[0] + zshift[0], m[1] + zshift[1]];
                    }
                }
            }
        }
    }
}

/// `_project_out_forbidden_world` (solo_controller.gd:6807-6825): a base at
/// rest in forbidden ground walks OUT on 16 compass directions × expanding
/// 1 cm rings up to 0.20 m (`TERRAIN_OUT_STEP/MAX/DIRS`, :151-154), lowest-x
/// then lowest-z within a ring (OVERLAP_EPS_M 5e-4 tie-break), clamped to the
/// table (BOUNDS_MARGIN_M 0.02 inside the 6×4 ft half-extents, :8894-8897).
/// Returns the input unchanged when clear or when no clear point is in range.
fn project_out_forbidden(board: &Terrain, walls: &[WallSeg], p: (f64, f64), r: f64) -> (f64, f64) {
    if !world_forbidden(board, walls, p, r) {
        return p;
    }
    let eps = 5.0e-4;
    let clamp = |q: (f64, f64)| {
        // clampf in f64, narrowed by the Vector3 ctor (solo_controller.gd:8894-8897)
        (
            (q.0).clamp(-0.9144 + 0.02, 0.9144 - 0.02) as f32 as f64,
            (q.1).clamp(-0.6096 + 0.02, 0.6096 - 0.02) as f32 as f64,
        )
    };
    let mut dist = 0.01f64;
    while dist <= 0.20 + eps {
        let mut best = p;
        let mut found = false;
        for k in 0..16 {
            let ang = std::f64::consts::TAU * k as f64 / 16.0;
            // pos + Vector3(cos·dist, 0, sin·dist): the offset narrows at the ctor
            let c = clamp((
                ((p.0 as f32) + (ang.cos() * dist) as f32) as f64,
                ((p.1 as f32) + (ang.sin() * dist) as f32) as f64,
            ));
            if world_forbidden(board, walls, c, r) {
                continue;
            }
            if !found
                || c.0 < best.0 - eps
                || ((c.0 - best.0).abs() <= eps && c.1 < best.1 - eps)
            {
                best = c;
                found = true;
            }
        }
        if found {
            return best;
        }
        dist += 0.01;
    }
    p
}

/// The live settle state of one finished side, rebuilt from its `SideDeploy`
/// — the builder step 6d lifted OUT of `deploy_side`: the table settles
/// through `deploy_finish` per side and the SECOND side's finish re-sweeps
/// the FIRST side's live units (:9228-9232), so the caller drives the
/// finishes. Roster order, non-ambush units, each paired with its placement
/// index for the write-back; the recorded zone is the side zone (the scout's
/// extended band for scouts — the `zone_of_record` law, :9098-9102); the
/// repair's blocked variant rides `ignores_terrain` (= Strider/Flying,
/// :9246). The f64 placement models re-narrow to the f32 state losslessly
/// (they were widened from it); the group-sum mismatch fails loudly (6c).
pub fn settle_units(specs: &[UnitSpec], sd: &SideDeploy, zone: &Rect) -> Vec<(usize, SettleUnit)> {
    let end = zone.end();
    let forward_y = if zone.pos.1.abs() < end.1.abs() { zone.pos.1 } else { end.1 };
    let place_at: HashMap<String, usize> = sd
        .placements
        .iter()
        .enumerate()
        .map(|(i, p)| (p.key.clone(), i))
        .collect();
    specs
        .iter()
        .enumerate()
        .filter(|(_, s)| !s.ambush)
        .map(|(si, s)| {
            let pi = place_at[&s.key];
            let p = &sd.placements[pi];
            let geoms = settle_shape_geoms(&specs[si]);
            assert_eq!(
                geoms.len(), p.models.len(),
                "unit {}: model_shapes sum {} != model_count {}",
                specs[si].key, geoms.len(), p.models.len()
            );
            (
                pi,
                SettleUnit {
                    models: p.models.iter().map(|m| [m.0 as f32, m.1 as f32]).collect(),
                    geoms,
                    zone: if s.scout { scout_extended_zone(zone, forward_y) } else { *zone },
                    flying: s.ignores_terrain,
                },
            )
        })
        .collect()
}

/// One `deploy_finish` pass (solo_controller.gd:9180-9188) over the ON-TABLE
/// units in `get_all_game_units` order (slot-1 roster then slot-2 —
/// opr_army_manager.gd:2061-2065 walks `game_units.values()` insertion order;
/// the 6b UNSURE-(a) assumption is thereby PROVEN: main.gd:1785/:1806-1810
/// insert slot 1 before slot 2, and each army's roster order matches the
/// dump's). The overlap resolve, then ≤ 2 repair rounds —
/// `_repair_deploy_coherency` (:9227-9312), each REPAIRING round followed by
/// another resolve (:9184-9188). The repair's RETURN is `forced_any` — set
/// ONLY by FORCED (overlap-allowed) re-placements (:9265-9266, :9295-9296),
/// not by free ones — so a free-only repair still ends the loop.
pub fn deploy_finish_all(units: &mut [SettleUnit], board: &Terrain, walls: &[WallSeg]) {
    resolve_deploy_overlaps(units, board, walls);
    for _round in 0..2 {
        if repair_deploy_coherency(units, board, walls) {
            resolve_deploy_overlaps(units, board, walls);
        } else {
            break;
        }
    }
}

// ---- NML-1152 step 6d2: `_repair_deploy_coherency` (solo_controller.gd
// :9227-9312) — the post-settle coherency repair. Draw-free. Every unit
// outside its largest 1"-link component gets its stragglers re-placed onto
// the nearest legal free ring spot around the component; a link-coherent but
// over-spread unit pulls its farthest-out model to FORCED contact beside the
// innermost one (the SPREAD case, diagnosis run 8). Skips: reserve/ambush
// units never enter `units`; regiments and attached (separate) heroes are
// corpus-absent — unported with the 6b branches (:9242-9245). The pass
// crosses slots (the SECOND side's finish re-heals the FIRST side's,
// :9228-9232) — the caller's array IS the cross-slot walk order.

/// `CoherencyChecker` constants (:10, :13): the 1" edge link and the 9" max
/// chain. The skirmish variant (:18, 6" — `is_skirmish_system` :64-65 reads
/// game_system gff/aofs) is corpus-absent; unported with the regiments so a
/// future skirmish corpus trips loudly instead of silently.
pub const COHERENCY_LINK_IN: f64 = 1.0;
pub const COHERENCY_CHAIN_IN: f64 = 9.0;

/// `MoveIntent.anchor_of` (move_intent.gd:18-24): the table-plane centroid —
/// Vector3 sum accumulated in f32 per component, divided by `float(n)`
/// narrowed to real_t (f32 division). Empty set → ZERO (unreachable here).
fn anchor_of(pts: &[[f32; 2]]) -> [f32; 2] {
    let (mut sx, mut sy) = (0.0f32, 0.0f32);
    for p in pts {
        sx += p[0];
        sy += p[1];
    }
    let n = pts.len() as f32;
    [sx / n, sy / n]
}

/// `_deploy_spot_free` (:9350-9367): NO on-table base (any unit, any side —
/// both slots' units incl. attached heroes) overlaps a base of radius `r` at
/// `cand`. `all` is the LIVE flat snapshot of every model (centre, bounding
/// radius); ONLY the moving model itself is excluded (`mi == moving`, :9362)
/// — the straggler's own unit's other models DO block. The Vector2 gap
/// length is f32, the radii sum f64 (`model_base_radius_m` = the shape's
/// bounding radius), narrowed at the comparison (:9364-9365); the 0.002 m is
/// the wall-rest clearance constant reused inline (:9365, :6775).
fn deploy_spot_free(cand: (f32, f32), r: f64, moving: usize, all: &[([f32; 2], f64)]) -> bool {
    for (k, (pos, r_m)) in all.iter().enumerate() {
        if k == moving {
            continue;
        }
        let (dx, dy) = (cand.0 - pos[0], cand.1 - pos[1]);
        let gap = (dx * dx + dy * dy).sqrt(); // Vector2.length — f32
        if (gap as f64) < r + r_m + 0.002 {
            return false;
        }
    }
    true
}

/// `_deploy_ring_spot` (:9317-9346): the nearest legal free ring spot for the
/// straggler `idx` around the component's models — component models nearest
/// the straggler FIRST (the smallest legal correction wins; the sort key is
/// `Vector3.distance_to` in f32 — every model of a unit shares one y, so the
/// 3D distance equals this 2D one; GDScript's sort is UNSTABLE, exact f32
/// ties are an accepted residual), two ring slack radii (0.5"/0.85", both
/// inside the 1" link band) × 24 angles. FORCED mode (`require_free = false`)
/// skips BOTH gates — terrain and bases — and always returns the FIRST
/// candidate (comp non-empty ⇒ Some). The blocked test is the SINGLE-POINT
/// callable (:9341 — no disc sampling here, unlike the ladder): walls at
/// 0.02 m, cells by the unit's Strider/Flying variant, props. The Vector3
/// ctor narrows the f64 candidate (centre f32 widened, cos·ring f64).
#[allow(clippy::too_many_arguments)]
fn deploy_ring_spot(
    geoms: &[SettleShapeGeom],
    pts: &[[f32; 2]],
    comp: &[usize],
    idx: usize,
    board: &Terrain,
    walls: &[WallSeg],
    flying: bool,
    all: &[([f32; 2], f64)],
    moving: usize,
    require_free: bool,
) -> Option<(f32, f32)> {
    let r_i = geoms[idx].bounding_radius();
    let straggler = pts[idx];
    let key = |j: usize| -> f32 {
        let (dx, dy) = (straggler[0] - pts[j][0], straggler[1] - pts[j][1]);
        (dx * dx + dy * dy).sqrt()
    };
    let mut order: Vec<usize> = comp.to_vec();
    order.sort_by(|&a, &b| key(a).partial_cmp(&key(b)).unwrap());
    for &j in &order {
        let r_j = geoms[j].bounding_radius();
        let centre = pts[j];
        for slack_in in [0.5f64, 0.85f64] {
            let ring = r_i + r_j + slack_in * 0.0254;
            for step in 0..24 {
                let ang = std::f64::consts::TAU * step as f64 / 24.0;
                let cand = (
                    (centre[0] as f64 + ang.cos() * ring) as f32,
                    (centre[1] as f64 + ang.sin() * ring) as f32,
                );
                if require_free {
                    // the single-point callable takes the f32 candidate (the
                    // Vector2 ctor adds no narrowing — widened for the f64
                    // helpers without drift)
                    let p64 = (cand.0 as f64, cand.1 as f64);
                    if wall_blocked(board, p64)
                        || cell_blocked(board, p64, flying)
                        || prop_blocked(board, p64)
                    {
                        continue;
                    }
                    if !deploy_spot_free(cand, r_i, moving, all) {
                        continue;
                    }
                }
                return Some(cand);
            }
        }
    }
    None
}

/// `_largest_link_component_world` (:6529-6552): the largest 1"-edge-link
/// component (CoherencyChecker's link graph, BFS with a STACK — pop_back,
/// seen marked when PUSHED, starts ascending 0..n, strict > keeps the
/// first-largest). `edge_distance_in` = SeparationChecker.edge_distance.
fn largest_link_component(shapes: &[SettleShape]) -> Vec<usize> {
    let n = shapes.len();
    let mut seen = vec![false; n];
    let mut best: Vec<usize> = Vec::new();
    for start in 0..n {
        if seen[start] {
            continue;
        }
        let mut comp = vec![start];
        let mut queue = vec![start];
        seen[start] = true;
        while let Some(cur) = queue.pop() {
            for other in 0..n {
                if seen[other] {
                    continue;
                }
                if edge_distance_in(&shapes[cur], &shapes[other]) <= COHERENCY_LINK_IN {
                    seen[other] = true;
                    queue.push(other);
                    comp.push(other);
                }
            }
        }
        if comp.len() > best.len() {
            best = comp;
        }
    }
    best
}

/// `_config_coherent_world` (:6832-6860) via `unit_coherent_now` (:8514-8520,
/// the 9" chain for non-skirmish units): a SINGLE 1"-link component (BFS from
/// model 0 ONLY — a smaller model-0 component fails even when a larger one
/// exists, :6841-6854) AND every pair's edge gap within the max chain
/// (:6856-6859). n ≤ 1 is coherent.
fn config_coherent(shapes: &[SettleShape], max_chain_in: f64) -> bool {
    let n = shapes.len();
    if n <= 1 {
        return true;
    }
    let mut visited = vec![false; n];
    visited[0] = true;
    let mut queue = vec![0usize];
    let mut seen = 1usize;
    while let Some(cur) = queue.pop() {
        for other in 0..n {
            if visited[other] {
                continue;
            }
            if edge_distance_in(&shapes[cur], &shapes[other]) <= COHERENCY_LINK_IN {
                visited[other] = true;
                seen += 1;
                queue.push(other);
            }
        }
    }
    if seen < n {
        return false;
    }
    for i in 0..n {
        for j in (i + 1)..n {
            if edge_distance_in(&shapes[i], &shapes[j]) > max_chain_in {
                return false;
            }
        }
    }
    true
}

/// `_repair_deploy_coherency` (:9227-9312). Per pass (≤ 8 — each re-links one
/// straggler or shrinks the span one step, :9247): the coherent gate and the
/// component are computed from the LIVE positions at the TOP of the pass;
/// `pts` is then a STALE snapshot — ring-spot centres, sort keys, the
/// straggler position and the SPREAD anchor all read it (:9251, :9276-9290),
/// while the spot-free check sees LIVE positions (the node is written
/// immediately, :9270 — earlier same-pass moves block at their NEW spots).
/// `all` is rebuilt per straggler (live). The return is `forced_any`.
pub fn repair_deploy_coherency(
    units: &mut [SettleUnit],
    board: &Terrain,
    walls: &[WallSeg],
) -> bool {
    let mut forced_any = false;
    for ui in 0..units.len() {
        let flying = units[ui].flying;
        for _pass in 0..8 {
            let n = units[ui].models.len();
            if n <= 1 {
                break;
            }
            let shapes: Vec<SettleShape> = units[ui]
                .models
                .iter()
                .zip(&units[ui].geoms)
                .map(|(m, g)| g.settle_shape(*m))
                .collect();
            if config_coherent(&shapes, COHERENCY_CHAIN_IN) {
                break;
            }
            let pts: Vec<[f32; 2]> = units[ui].models.clone(); // stale snapshot
            let comp = largest_link_component(&shapes);
            let mut in_comp = vec![false; n];
            for &c in &comp {
                in_comp[c] = true;
            }
            let prefix: usize = units[..ui].iter().map(|u| u.models.len()).sum();
            let mut moved_one = false;
            for i in 0..n {
                if in_comp[i] {
                    continue;
                }
                let all: Vec<([f32; 2], f64)> = units
                    .iter()
                    .flat_map(|u| {
                        u.models
                            .iter()
                            .zip(&u.geoms)
                            .map(move |(m, g)| (*m, g.bounding_radius()))
                    })
                    .collect();
                let moving = prefix + i;
                let mut spot = deploy_ring_spot(
                    &units[ui].geoms, &pts, &comp, i, board, walls, flying, &all, moving, true,
                );
                if spot.is_none() {
                    // packed zone — FORCE contact beside the group (:9262-9266);
                    // forced_any only on SUCCESS (:9265-9266)
                    spot = deploy_ring_spot(
                        &units[ui].geoms, &pts, &comp, i, board, walls, flying, &all, moving,
                        false,
                    );
                    if spot.is_some() {
                        forced_any = true;
                    }
                }
                if let Some(s) = spot {
                    units[ui].models[i] = [s.0, s.1]; // Vector3 ctor — f32
                    moved_one = true;
                }
            }
            if !moved_one && comp.len() == n {
                // SPREAD case (:9272-9296): link-coherent but wider than the
                // 9" span — pull the farthest-out model to FORCED contact
                // beside the innermost one; every pass shrinks the span. The
                // forced call cannot fail (comp = [near_j] non-empty).
                let anchor = anchor_of(&pts);
                let (mut far_i, mut near_j) = (0usize, 0usize);
                let (mut dmax, mut dmin) = (-1.0f64, f64::INFINITY);
                for (i, p) in pts.iter().enumerate() {
                    let (dx, dy) = (anchor[0] - p[0], anchor[1] - p[1]);
                    let dd = ((dx * dx + dy * dy).sqrt()) as f64; // distance_to f32
                    if dd > dmax {
                        dmax = dd;
                        far_i = i;
                    }
                    if dd < dmin {
                        dmin = dd;
                        near_j = i;
                    }
                }
                if far_i != near_j {
                    let all: Vec<([f32; 2], f64)> = units
                        .iter()
                        .flat_map(|u| {
                            u.models
                                .iter()
                                .zip(&u.geoms)
                                .map(move |(m, g)| (*m, g.bounding_radius()))
                        })
                        .collect();
                    if let Some(s2) = deploy_ring_spot(
                        &units[ui].geoms, &pts, &[near_j], far_i, board, walls, flying, &all,
                        prefix + far_i, false,
                    ) {
                        units[ui].models[far_i] = [s2.0, s2.1];
                        moved_one = true;
                        forced_any = true;
                    }
                }
            }
            if moved_one {
                // _broadcast_positions + the deploy decision records are
                // harness cosmetics — no positions (:9297-9302).
            } else {
                break; // FAILED record + avoid spinning (:9303-9311)
            }
        }
    }
    forced_any
}
