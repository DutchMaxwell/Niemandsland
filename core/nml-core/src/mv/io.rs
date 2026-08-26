//! Loader for the move corpus written by `scripts/solo/move_recorder.gd`
//! (NML-1073 M4-0a): line 1 is the `{"kind":"header", ...}` static per-game
//! block, every line after it one `{"kind":"call", ...}` — a full
//! `MovementPlanner.plan_unit_step` invocation with its inputs, its outputs and
//! (under `NML_MOVE_TRACE=1`) its per-stage trace.
//!
//! The JSON carries f64 numbers; every position is an exactly-representable f32
//! (the recorder flattened Godot `Vector2`s), so the narrowing here is lossless.
//!
//! FORWARD COMPATIBILITY. No struct here uses `deny_unknown_fields`, and every
//! field the recorder may not write yet is `#[serde(default)]` or `Option<>`.
//! A trace v2 line carrying extra keys (per-node `g`, the parent index, the
//! open-list size per pop, the post-pull endpoint, the walk's spent arc) loads
//! unchanged through this loader. Trace v2 (move_recorder.gd:24-26, commit
//! 023e3e2) is READ here in full: `pull`, `walk_spent` and `theta_searches`.

use std::fs::File;
use std::io::{BufRead, BufReader};

use serde::Deserialize;

use super::cost::{CellSet, Grid, Wall, Zone};
use super::geom2::{to_f32, V2};

fn v2(p: [f64; 2]) -> V2 {
    to_f32(p)
}

fn walls_of(raw: &[[[f64; 2]; 2]]) -> Vec<Wall> {
    raw.iter().map(|w| [v2(w[0]), v2(w[1])]).collect()
}

fn cells_of(raw: &[[i64; 2]]) -> CellSet {
    raw.iter().map(|c| (c[0] as i32, c[1] as i32)).collect()
}

/// `MoveRecorder._constants` — move_recorder.gd:117. Every planner constant the
/// `plan_unit_step` pipeline reads, so the port can prove it shares them.
#[derive(Clone, Debug, Deserialize)]
pub struct Constants {
    #[serde(rename = "EPS")]
    pub eps: f64,
    #[serde(rename = "BASE_CONTACT_IN")]
    pub base_contact_in: f64,
    #[serde(rename = "COHERENCY_IN")]
    pub coherency_in: f64,
    #[serde(rename = "MAX_CHAIN_IN")]
    pub max_chain_in: f64,
    #[serde(rename = "LINK_IN")]
    pub link_in: f64,
    #[serde(rename = "SPREAD_IN")]
    pub spread_in: f64,
    #[serde(rename = "STEP_IN")]
    pub step_in: f64,
    #[serde(rename = "STUCK_FRACTION")]
    pub stuck_fraction: f64,
    #[serde(rename = "COH_PULL_IN")]
    pub coh_pull_in: f64,
    #[serde(rename = "COH_PASSES")]
    pub coh_passes: i64,
    #[serde(rename = "LAG_FRACTION")]
    pub lag_fraction: f64,
    #[serde(rename = "GATHER_PASSES")]
    pub gather_passes: i64,
    #[serde(rename = "UNTANGLE_PASSES")]
    pub untangle_passes: i64,
    #[serde(rename = "SLIDE_ANGLES")]
    pub slide_angles: Vec<f64>,
    #[serde(rename = "PLAN_CELL_IN")]
    pub plan_cell_in: f64,
    #[serde(rename = "FAST_PLANNER_GUARD")]
    pub fast_planner_guard: i64,
    #[serde(rename = "DIFFICULT_COST_MULT")]
    pub difficult_cost_mult: f64,
    #[serde(rename = "DANGEROUS_COST_MULT")]
    pub dangerous_cost_mult: f64,
    #[serde(rename = "THETA_DIAG")]
    pub theta_diag: Vec<[i64; 2]>,
    #[serde(rename = "SOLVE_PASSES")]
    pub solve_passes: i64,
    #[serde(rename = "CONTACT_SLIDE_EPS_IN")]
    pub contact_slide_eps_in: f64,
    #[serde(rename = "TERRAIN_PUSH_MAX_IN")]
    pub terrain_push_max_in: f64,
    #[serde(rename = "TERRAIN_PUSH_STEP_IN")]
    pub terrain_push_step_in: f64,
    #[serde(rename = "RADIAL_DIRS")]
    pub radial_dirs: i64,
    #[serde(rename = "W_TERRAIN")]
    pub w_terrain: f64,
    #[serde(rename = "W_COHERENCY")]
    pub w_coherency: f64,
    #[serde(rename = "W_OVERLAP")]
    pub w_overlap: f64,
    #[serde(rename = "W_ZONE")]
    pub w_zone: f64,
    #[serde(rename = "COHERENCY_BISECT_STEPS")]
    pub coherency_bisect_steps: i64,
    #[serde(rename = "CLEARANCE_EPS_IN")]
    pub clearance_eps_in: f64,
}

impl Constants {
    /// Every recorded constant against its Rust twin. `Err` names the first
    /// mismatch — a corpus recorded under different numbers is not a corpus this
    /// port may be gated on.
    pub fn check(&self) -> Result<(), String> {
        macro_rules! same {
            ($got:expr, $want:expr, $name:literal) => {
                if $got != $want {
                    return Err(format!("{}: corpus {:?} != rust {:?}", $name, $got, $want));
                }
            };
        }
        same!(self.eps, super::EPS, "EPS");
        same!(self.base_contact_in, super::BASE_CONTACT_IN, "BASE_CONTACT_IN");
        same!(self.coherency_in, super::COHERENCY_IN, "COHERENCY_IN");
        same!(self.max_chain_in, super::MAX_CHAIN_IN, "MAX_CHAIN_IN");
        same!(self.link_in, super::LINK_IN, "LINK_IN");
        same!(self.spread_in, super::SPREAD_IN, "SPREAD_IN");
        same!(self.step_in, super::STEP_IN, "STEP_IN");
        same!(self.stuck_fraction, super::STUCK_FRACTION, "STUCK_FRACTION");
        same!(self.coh_pull_in, super::COH_PULL_IN, "COH_PULL_IN");
        same!(self.coh_passes, super::COH_PASSES, "COH_PASSES");
        same!(self.lag_fraction, super::LAG_FRACTION, "LAG_FRACTION");
        same!(self.gather_passes, super::GATHER_PASSES, "GATHER_PASSES");
        same!(self.untangle_passes, super::UNTANGLE_PASSES, "UNTANGLE_PASSES");
        same!(&self.slide_angles[..], &super::SLIDE_ANGLES[..], "SLIDE_ANGLES");
        same!(self.plan_cell_in, super::PLAN_CELL_IN, "PLAN_CELL_IN");
        same!(self.fast_planner_guard, super::FAST_PLANNER_GUARD, "FAST_PLANNER_GUARD");
        same!(self.difficult_cost_mult, super::DIFFICULT_COST_MULT, "DIFFICULT_COST_MULT");
        same!(self.dangerous_cost_mult, super::DANGEROUS_COST_MULT, "DANGEROUS_COST_MULT");
        let diag: Vec<[i64; 2]> =
            super::THETA_DIAG.iter().map(|d| [d.0 as i64, d.1 as i64]).collect();
        same!(self.theta_diag, diag, "THETA_DIAG");
        same!(self.solve_passes, super::SOLVE_PASSES, "SOLVE_PASSES");
        same!(self.contact_slide_eps_in, super::CONTACT_SLIDE_EPS_IN, "CONTACT_SLIDE_EPS_IN");
        same!(self.terrain_push_max_in, super::TERRAIN_PUSH_MAX_IN, "TERRAIN_PUSH_MAX_IN");
        same!(self.terrain_push_step_in, super::TERRAIN_PUSH_STEP_IN, "TERRAIN_PUSH_STEP_IN");
        same!(self.radial_dirs, super::RADIAL_DIRS, "RADIAL_DIRS");
        same!(self.w_terrain, super::W_TERRAIN, "W_TERRAIN");
        same!(self.w_coherency, super::W_COHERENCY, "W_COHERENCY");
        same!(self.w_overlap, super::W_OVERLAP, "W_OVERLAP");
        same!(self.w_zone, super::W_ZONE, "W_ZONE");
        same!(self.coherency_bisect_steps, super::COHERENCY_BISECT_STEPS, "COHERENCY_BISECT_STEPS");
        same!(self.clearance_eps_in, super::CLEARANCE_EPS_IN, "CLEARANCE_EPS_IN");
        Ok(())
    }
}

/// `MoveRecorder._header_line` — move_recorder.gd:107.
#[derive(Clone, Debug)]
pub struct MoveHeader {
    pub board_in: [f64; 2],
    pub board_y_in: f64,
    pub inches_to_meters: f64,
    pub fast_planner: bool,
    pub fast_planner_guard: i64,
    pub walls: Vec<Wall>,
    pub constants: Constants,
}

#[derive(Deserialize)]
struct PlainHeader {
    board_in: [f64; 2],
    board_y_in: f64,
    inches_to_meters: f64,
    fast_planner: bool,
    fast_planner_guard: i64,
    walls: Vec<[[f64; 2]; 2]>,
    constants: Constants,
}

/// The `opts` dictionary one `plan_unit_step` call was made with —
/// solo_controller.gd:5979-6033, flattened by `MoveRecorder._flatten_opts`
/// (move_recorder.gd:150).
#[derive(Clone, Debug, Default)]
pub struct CallOpts {
    pub radii: Vec<f64>,
    pub clearance: f64,
    pub zones: Vec<Zone>,
    pub avoid_cells: CellSet,
    pub avoid_fine: CellSet,
    pub forbid_cells: CellSet,
    pub board_y_in: f64,
    pub difficult_cap_in: Option<f64>,
    pub zones_rest_only: bool,
    pub charge_allowance: Option<f64>,
    pub charge_goal: Option<V2>,
    /// `opts["charge_tgt_bases"]` — `[[centre, radius], …]`.
    pub charge_tgt_bases: Vec<(V2, f64)>,
    pub charge_slots: Vec<V2>,
}

#[derive(Deserialize)]
struct PlainZone {
    c: [f64; 2],
    r: f64,
}

#[derive(Deserialize)]
struct PlainOpts {
    #[serde(default)]
    radii: Vec<f64>,
    #[serde(default)]
    clearance: f64,
    #[serde(default)]
    zones: Vec<PlainZone>,
    #[serde(default)]
    avoid_cells: Vec<[i64; 2]>,
    #[serde(default)]
    avoid_fine: Vec<[i64; 2]>,
    #[serde(default)]
    forbid_cells: Vec<[i64; 2]>,
    #[serde(default)]
    board_y_in: f64,
    #[serde(default)]
    difficult_cap_in: Option<f64>,
    #[serde(default)]
    zones_rest_only: bool,
    #[serde(default)]
    charge_allowance: Option<f64>,
    #[serde(default)]
    charge_goal: Option<[f64; 2]>,
    #[serde(default)]
    charge_tgt_bases: Vec<serde_json::Value>,
    #[serde(default)]
    charge_slots: Vec<[f64; 2]>,
}

/// One `MoveRecorder.trace_model` entry — move_recorder.gd:198. A model's
/// Theta* route, its string-pulled taut form and the walked leg, for ONE
/// attempt (a deferred model records twice).
#[derive(Clone, Debug, Deserialize)]
pub struct PlainFlowEntry {
    model: i64,
    theta: Vec<[f64; 2]>,
    taut: Vec<[f64; 2]>,
    walked: Vec<[f64; 2]>,
    deferred: bool,
    /// trace v2, optional: the endpoint AFTER `_pull_into_placed`
    /// (movement_planner.gd:1164), which trace v1 could not see because
    /// `trace_model` fires before the pull. Charges and deferred attempts never
    /// pull, so there it equals `walked`'s last point.
    #[serde(default, rename = "pull", alias = "pulled")]
    pulled: Option<[f64; 2]>,
    /// trace v2, optional: the TRUE arc length of `walked`, recomputed by the
    /// recorder from the returned polyline (movement_planner.gd:1561-1568) —
    /// NOT the planner's internal `spent`, which a clipped final leg leaves one
    /// step stale.
    #[serde(default)]
    walk_spent: Option<f64>,
}

#[derive(Clone, Debug)]
pub struct FlowEntry {
    pub model: i64,
    /// `_theta_star_b`'s returned polyline (world points, movement_planner.gd:1344).
    pub theta: Vec<V2>,
    /// `string_pull` of it (movement_planner.gd:1461).
    pub taut: Vec<V2>,
    /// `_walk_offset` of that (movement_planner.gd:1494).
    pub walked: Vec<V2>,
    /// This attempt sent the model to the back of the queue (movement_planner.gd:1138).
    pub deferred: bool,
    /// trace v2 only — `None` on a v1 line. See `PlainFlowEntry::pulled`.
    pub pulled: Option<V2>,
    /// trace v2 only — the arc length of `walked`.
    pub walk_spent: Option<f64>,
}

/// One popped node of one `_theta_star_b` search — trace v2,
/// movement_planner.gd:1405-1409.
#[derive(Clone, Copy, Debug, Deserialize)]
pub struct ThetaPop {
    /// `g[cur]` at the moment of the pop.
    pub g: f64,
    /// Index of `parent[cur]` in THIS search's own pop order, or -1 when the
    /// node is its own parent (the start).
    pub parent: i64,
    /// `open.size()` BEFORE the pop's `remove_at`.
    pub open: i64,
}

/// One `MoveRecorder.trace_solve_pass` entry — move_recorder.gd:208.
#[derive(Clone, Debug)]
pub struct SolvePass {
    pub pass: i64,
    pub positions: Vec<V2>,
    pub score: f64,
}

#[derive(Deserialize)]
struct PlainSolvePass {
    pass: i64,
    positions: Vec<[f64; 2]>,
    score: f64,
}

/// The `trace` block of one call (`NML_MOVE_TRACE=1` only).
#[derive(Clone, Debug, Default)]
pub struct Trace {
    pub flow: Vec<FlowEntry>,
    pub untangle_swaps: Vec<[i64; 2]>,
    pub solve_passes: Vec<SolvePass>,
    /// trace v2: one pop list per `_theta_star_b` call that ACTUALLY RAN a
    /// search, in invocation order — the early-outs (movement_planner.gd:1355,
    /// :1364) record nothing, and `untangle_endpoints`' re-routes (:1235) append
    /// after every flow entry. There is no key linking a list to a flow entry;
    /// see `mv::replay::align_searches`.
    pub theta_searches: Vec<Vec<ThetaPop>>,
}

#[derive(Deserialize, Default)]
struct PlainTrace {
    #[serde(default)]
    flow: Vec<PlainFlowEntry>,
    #[serde(default)]
    untangle_swaps: Vec<[i64; 2]>,
    #[serde(default)]
    solve_passes: Vec<PlainSolvePass>,
    #[serde(default)]
    theta_searches: Vec<Vec<ThetaPop>>,
}

/// One recorded `MovementPlanner.plan_unit_step` call.
#[derive(Clone, Debug)]
pub struct MoveCall {
    pub unit: String,
    pub act: i64,
    pub round: i64,
    /// The controller's ladder rung label (solo_controller.gd:4603-4700).
    pub rung: String,
    pub model_pos: Vec<V2>,
    pub delta: V2,
    /// Resolved: `"header"` in the JSON means the header's wall list.
    pub walls: Vec<Wall>,
    pub grid: Grid,
    pub allow_contact: bool,
    pub board_in: f64,
    pub opts: CallOpts,
    /// The returned per-model final positions.
    pub planned: Vec<V2>,
    /// The returned per-model polylines.
    pub trails: Vec<Vec<V2>>,
    /// `opts["flow_order"]`, written back by the planner.
    pub flow_order: Vec<i64>,
    pub trace: Trace,
}

#[derive(Deserialize)]
struct PlainCall {
    unit: String,
    act: i64,
    round: i64,
    #[serde(default)]
    rung: String,
    model_pos: Vec<[f64; 2]>,
    delta: [f64; 2],
    walls: serde_json::Value,
    grid: Vec<[i64; 3]>,
    allow_contact: bool,
    board_in: f64,
    opts: PlainOpts,
    #[serde(default)]
    planned: Vec<[f64; 2]>,
    #[serde(default)]
    trails: Vec<Vec<[f64; 2]>>,
    #[serde(default)]
    flow_order: Vec<i64>,
    #[serde(default)]
    trace: PlainTrace,
}

/// A whole move corpus: one header plus every recorded call, in file order.
#[derive(Clone, Debug)]
pub struct MoveCorpus {
    pub header: MoveHeader,
    pub calls: Vec<MoveCall>,
}

/// Reads `moves_calls.jsonl` from disk.
pub fn load_moves(path: &str) -> Result<MoveCorpus, String> {
    let file = File::open(path).map_err(|e| format!("{path}: {e}"))?;
    read_moves(BufReader::new(file), path)
}

/// Same, from any reader — `origin` only labels the error messages.
pub fn read_moves<R: BufRead>(reader: R, origin: &str) -> Result<MoveCorpus, String> {
    let path = origin;
    let mut lines = reader.lines();
    let head = lines
        .next()
        .ok_or_else(|| format!("{path}: empty file"))?
        .map_err(|e| e.to_string())?;
    let ph: PlainHeader =
        serde_json::from_str(&head).map_err(|e| format!("{path}:1 move header: {e}"))?;
    let header = MoveHeader {
        board_in: ph.board_in,
        board_y_in: ph.board_y_in,
        inches_to_meters: ph.inches_to_meters,
        fast_planner: ph.fast_planner,
        fast_planner_guard: ph.fast_planner_guard,
        walls: walls_of(&ph.walls),
        constants: ph.constants,
    };
    let mut calls = Vec::new();
    for (i, line) in lines.enumerate() {
        let line = line.map_err(|e| e.to_string())?;
        if line.trim().is_empty() {
            continue;
        }
        let pc: PlainCall =
            serde_json::from_str(&line).map_err(|e| format!("{path}:{}: {e}", i + 2))?;
        calls.push(call_of(pc, &header, path, i + 2)?);
    }
    Ok(MoveCorpus { header, calls })
}

fn call_of(pc: PlainCall, header: &MoveHeader, path: &str, ln: usize) -> Result<MoveCall, String> {
    let walls = match &pc.walls {
        serde_json::Value::String(s) if s == "header" => header.walls.clone(),
        serde_json::Value::Array(_) => {
            let raw: Vec<[[f64; 2]; 2]> = serde_json::from_value(pc.walls.clone())
                .map_err(|e| format!("{path}:{ln} walls: {e}"))?;
            walls_of(&raw)
        }
        other => return Err(format!("{path}:{ln} walls: unexpected {other}")),
    };
    let mut grid = Grid::with_capacity(pc.grid.len());
    for c in &pc.grid {
        grid.insert((c[0] as i32, c[1] as i32), c[2]);
    }
    let o = pc.opts;
    let mut charge_tgt_bases = Vec::new();
    for tb in &o.charge_tgt_bases {
        let arr = tb.as_array().ok_or_else(|| format!("{path}:{ln} charge_tgt_bases"))?;
        let c = arr[0].as_array().ok_or_else(|| format!("{path}:{ln} charge base centre"))?;
        charge_tgt_bases.push((
            to_f32([
                c[0].as_f64().unwrap_or(0.0),
                c[1].as_f64().unwrap_or(0.0),
            ]),
            arr[1].as_f64().unwrap_or(0.0),
        ));
    }
    let opts = CallOpts {
        radii: o.radii,
        clearance: o.clearance,
        zones: o.zones.iter().map(|z| Zone { c: v2(z.c), r: z.r }).collect(),
        avoid_cells: cells_of(&o.avoid_cells),
        avoid_fine: cells_of(&o.avoid_fine),
        forbid_cells: cells_of(&o.forbid_cells),
        board_y_in: o.board_y_in,
        difficult_cap_in: o.difficult_cap_in,
        zones_rest_only: o.zones_rest_only,
        charge_allowance: o.charge_allowance,
        charge_goal: o.charge_goal.map(v2),
        charge_tgt_bases,
        charge_slots: o.charge_slots.into_iter().map(v2).collect(),
    };
    let trace = Trace {
        flow: pc
            .trace
            .flow
            .into_iter()
            .map(|f| FlowEntry {
                model: f.model,
                theta: f.theta.into_iter().map(v2).collect(),
                taut: f.taut.into_iter().map(v2).collect(),
                walked: f.walked.into_iter().map(v2).collect(),
                deferred: f.deferred,
                pulled: f.pulled.map(v2),
                walk_spent: f.walk_spent,
            })
            .collect(),
        untangle_swaps: pc.trace.untangle_swaps,
        theta_searches: pc.trace.theta_searches,
        solve_passes: pc
            .trace
            .solve_passes
            .into_iter()
            .map(|s| SolvePass {
                pass: s.pass,
                positions: s.positions.into_iter().map(v2).collect(),
                score: s.score,
            })
            .collect(),
    };
    Ok(MoveCall {
        unit: pc.unit,
        act: pc.act,
        round: pc.round,
        rung: pc.rung,
        model_pos: pc.model_pos.into_iter().map(v2).collect(),
        delta: v2(pc.delta),
        walls,
        grid,
        allow_contact: pc.allow_contact,
        board_in: pc.board_in,
        opts,
        planned: pc.planned.into_iter().map(v2).collect(),
        trails: pc.trails.into_iter().map(|t| t.into_iter().map(v2).collect()).collect(),
        flow_order: pc.flow_order,
        trace,
    })
}

impl MoveCall {
    /// `plan_sequential_flow`'s arc budget — movement_planner.gd:1039:
    /// `opts.charge_allowance` for a charge, else the straight delta length.
    pub fn allowance(&self) -> f64 {
        self.opts
            .charge_allowance
            .unwrap_or_else(|| super::geom2::length(self.delta))
    }

    /// `MovementPlanner.board_extents` — movement_planner.gd:471.
    pub fn board(&self) -> V2 {
        super::theta::board_extents(self.board_in, self.opts.board_y_in)
    }
}
