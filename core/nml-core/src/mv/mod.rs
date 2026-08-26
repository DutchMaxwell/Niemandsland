//! NML-1073 M4 — the Rust port of `scripts/solo/movement_planner.gd`.
//!
//! Stage 1 (M4-1) is the LEAF layer every later stage stands on: the Godot
//! `Vector2` geometry primitives (`geom2`), the step/terrain/segment predicates
//! and costs (`cost`), and the loader for the move corpus written by
//! `scripts/solo/move_recorder.gd` (`io`).
//!
//! Nothing here is loaded by the game. Every ported function names its GDScript
//! origin as `file:line`.
//!
//! PRECISION. Godot builds `real_t` as 32-bit, so a `Vector2` and every
//! operation on it (`distance_to`, `lerp`, `dot`, `normalized`, `operator*`)
//! is f32; a GDScript `float` is f64. The port mirrors that boundary exactly,
//! the way `crate::geom` already does for `Vector3`: vector math in f32, every
//! value that leaves a `Vector2` promoted to f64 at the same place the GDScript
//! promotes it, and all cost accumulation in f64.

pub mod cost;
pub mod flow;
pub mod geom2;
pub mod io;
pub mod pull;
pub mod replay;
pub mod theta;

pub use cost::{
    cell_of, cspace_blocked, legs_cost, path_crosses_wall_opt, segment_cost, segment_cost_at,
    step_blocked, terrain_cost_at, CellSet, Grid, StepOpts, Wall, Zone,
};
pub use flow::{
    centroid, flow_order, linked_r, plan_sequential_flow, pull_into_placed, recorded_endpoints,
    untangle_endpoints, FlowBend, FlowOpts, FlowResult, FlowStep,
};
pub use geom2::{
    add, distance_to, div, dot, length, length_squared, lerp, mul, normalized, orient,
    path_crosses_wall, point_seg_distance, polyline_length, seg_seg_distance, segments_cross, sub,
    to_f32, to_f64, trim_polyline, V2,
};
pub use io::{load_moves, read_moves, CallOpts, Constants, FlowEntry, MoveCall, MoveCorpus,
    MoveHeader, SolvePass, ThetaPop, Trace};
pub use pull::{
    board_clamp, furthest_clear, furthest_clear_steps, string_pull, string_pull_bent, walk_offset,
    walk_offset_bent, PullBend, WalkBend,
};
pub use replay::{align_searches, searches, ReplaySearch};
pub use theta::{
    board_extents, cell_before, cell_center_fine, theta_reconstruct, theta_star, theta_star_b,
    theta_star_bent, theta_star_traced, theta_star_traced_bent, Cell, ThetaBend, ThetaCfg, ThetaOpts,
};

// === movement_planner.gd constants (:25-90) ===============================

/// `MovementPlanner.EPS` — movement_planner.gd:24.
pub const EPS: f64 = 0.0001;

/// `MovementPlanner.BASE_CONTACT_IN` — movement_planner.gd:27.
pub const BASE_CONTACT_IN: f64 = 2.0;
/// `MovementPlanner.COHERENCY_IN` — movement_planner.gd:28.
pub const COHERENCY_IN: f64 = 1.0;
/// `MovementPlanner.MAX_CHAIN_IN` — movement_planner.gd:29.
pub const MAX_CHAIN_IN: f64 = 9.0;
/// `MovementPlanner.LINK_IN` — movement_planner.gd:30.
pub const LINK_IN: f64 = BASE_CONTACT_IN + COHERENCY_IN;
/// `MovementPlanner.SPREAD_IN` — movement_planner.gd:31.
pub const SPREAD_IN: f64 = BASE_CONTACT_IN + MAX_CHAIN_IN;

/// `MovementPlanner.STEP_IN` — movement_planner.gd:34.
pub const STEP_IN: f64 = 0.75;
/// `MovementPlanner.STUCK_FRACTION` — movement_planner.gd:35.
pub const STUCK_FRACTION: f64 = 0.25;
/// `MovementPlanner.COH_PULL_IN` — movement_planner.gd:36.
pub const COH_PULL_IN: f64 = 1.0;
/// `MovementPlanner.COH_PASSES` — movement_planner.gd:37.
pub const COH_PASSES: i64 = 8;
/// `MovementPlanner.LAG_FRACTION` — movement_planner.gd:41.
pub const LAG_FRACTION: f64 = 0.5;
/// `MovementPlanner.GATHER_PASSES` — movement_planner.gd:42.
pub const GATHER_PASSES: i64 = 16;
/// `MovementPlanner.UNTANGLE_PASSES` — movement_planner.gd:43.
pub const UNTANGLE_PASSES: i64 = 4;
/// `MovementPlanner.SLIDE_ANGLES` — movement_planner.gd:45.
pub const SLIDE_ANGLES: [f64; 9] = [0.0, 20.0, -20.0, 45.0, -45.0, 70.0, -70.0, 90.0, -90.0];

/// `MovementPlanner.PLAN_CELL_IN` — movement_planner.gd:54, the 1" any-angle search grid.
pub const PLAN_CELL_IN: f64 = 1.0;
/// `MovementPlanner.FAST_PLANNER_GUARD` — movement_planner.gd:61.
pub const FAST_PLANNER_GUARD: i64 = 320;
/// `MovementPlanner.DIFFICULT_COST_MULT` — movement_planner.gd:70.
pub const DIFFICULT_COST_MULT: f64 = 2.0;
/// `MovementPlanner.DANGEROUS_COST_MULT` — movement_planner.gd:71.
pub const DANGEROUS_COST_MULT: f64 = 6.0;
/// `MovementPlanner.THETA_DIAG` — movement_planner.gd:72-73, 8-connected, ORDER IS LOAD-BEARING.
pub const THETA_DIAG: [(i32, i32); 8] = [
    (1, 0),
    (-1, 0),
    (0, 1),
    (0, -1),
    (1, 1),
    (1, -1),
    (-1, 1),
    (-1, -1),
];
/// `MovementPlanner.SOLVE_PASSES` — movement_planner.gd:74.
pub const SOLVE_PASSES: i64 = 24;
/// `MovementPlanner.CONTACT_SLIDE_EPS_IN` — movement_planner.gd:79.
pub const CONTACT_SLIDE_EPS_IN: f64 = 0.05;
/// `MovementPlanner.TERRAIN_PUSH_MAX_IN` — movement_planner.gd:80.
pub const TERRAIN_PUSH_MAX_IN: f64 = 6.0;
/// `MovementPlanner.TERRAIN_PUSH_STEP_IN` — movement_planner.gd:81.
pub const TERRAIN_PUSH_STEP_IN: f64 = 0.5;
/// `MovementPlanner.RADIAL_DIRS` — movement_planner.gd:84.
pub const RADIAL_DIRS: i64 = 16;
/// `MovementPlanner.W_TERRAIN` — movement_planner.gd:87.
pub const W_TERRAIN: f64 = 100.0;
/// `MovementPlanner.W_COHERENCY` — movement_planner.gd:88.
pub const W_COHERENCY: f64 = 60.0;
/// `MovementPlanner.W_OVERLAP` — movement_planner.gd:89.
pub const W_OVERLAP: f64 = 40.0;
/// `MovementPlanner.W_ZONE` — movement_planner.gd:90.
pub const W_ZONE: f64 = 30.0;
/// `MovementPlanner.COHERENCY_BISECT_STEPS` — movement_planner.gd:347, the `_furthest_clear` bisection count.
pub const COHERENCY_BISECT_STEPS: i64 = 14;
/// `SoloController.CLEARANCE_EPS_IN` — solo_controller.gd:87, folded into `opts["clearance"]` at :5979.
pub const CLEARANCE_EPS_IN: f64 = 0.1;

/// `TerrainRules.CELL_IN` — terrain_rules.gd:23, the typed 3" terrain grid.
pub const CELL_IN: f64 = 3.0;

/// `TerrainRules.TerrainType` — terrain_rules.gd:21.
pub const T_NONE: i64 = 0;
/// `TerrainRules.TerrainType.RUINS`.
pub const T_RUINS: i64 = 1;
/// `TerrainRules.TerrainType.FOREST` — the Difficult type (`is_difficult`, terrain_rules.gd:64).
pub const T_FOREST: i64 = 2;
/// `TerrainRules.TerrainType.CONTAINER` — Impassable (`is_impassable`, terrain_rules.gd:72).
pub const T_CONTAINER: i64 = 3;
/// `TerrainRules.TerrainType.DANGEROUS` — `is_dangerous`, terrain_rules.gd:68.
pub const T_DANGEROUS: i64 = 4;

/// `TerrainRules.is_difficult` — terrain_rules.gd:64.
#[inline]
pub fn is_difficult(t: i64) -> bool {
    t == T_FOREST
}

/// `TerrainRules.is_dangerous` — terrain_rules.gd:68.
#[inline]
pub fn is_dangerous(t: i64) -> bool {
    t == T_DANGEROUS
}

/// `TerrainRules.is_impassable` — terrain_rules.gd:72.
#[inline]
pub fn is_impassable(t: i64) -> bool {
    t == T_CONTAINER
}
