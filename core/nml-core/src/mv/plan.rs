//! NML-1073 M4-5 — `MovementPlanner.plan_unit_step` (movement_planner.gd:499)
//! and `_plan_unit_step_unified` (:899), the TOP of the movement port.
//!
//! This is the whole pipeline in one place, and it is deliberately thin: every
//! stage below it was ported and gated on its own, so all this file owes is the
//! composition and the two guards the GDScript puts around it.
//!
//! ```text
//!   plan_sequential_flow   -> endpoints + trails + flow_order   (mv::flow, M4-4)
//!   solve_formation        -> the least-violating configuration (mv::form, M4-5)
//!   _append_trail_finals   -> the solver's move drawn onto the trail
//!   _cap_difficult_polylines -> the p.11 6" per-polyline cap     (mv::cap, M4-5)
//! ```
//!
//! THE TWO GUARDS, in the order the GDScript applies them (:501-508):
//!
//!   1. `delta.length() < EPS` or an EMPTY unit returns `model_pos` VERBATIM —
//!      before the `radii` dispatch, so `trails` is never even sized and
//!      `opts["flow_order"]` is never written. The recorder then stores an empty
//!      `trails` and an empty `flow_order` for that line. (No such line exists
//!      in the 16-game corpus: every recorded delta is well over EPS.)
//!   2. `opts.has("radii")` selects the unified pipeline. The legacy steer + A*
//!      branch below it belongs to `SoloSim` alone and is NOT ported — see the
//!      recon note, §E.
//!
//! WHAT THE SOLVER CAN STILL MOVE. The flow already places every model; the
//! solver only clears residual violations, and on 446 of the corpus's 1 101
//! calls it finds nothing to do and returns the flow's answer untouched. Where
//! it does run, it can and does move endpoints by inches — which is why the
//! flow-only gate (M4-4) could tie to `planned` on 399 calls and no more.

use super::cap::{cap_difficult_polylines, CapReport};
use super::cost::{Grid, Wall};
use super::flow::{plan_sequential_flow, FlowBend, FlowOpts};
use super::form::{solve_formation, FormBend, FormResult, SolveOpts};
use super::geom2::{distance_to, length, V2};
use super::io::MoveCall;
use super::theta::ThetaCfg;
use super::{EPS, FAST_PLANNER_GUARD};

/// What `plan_unit_step` hands back — the three channels
/// `MoveRecorder.finish` writes (move_recorder.gd:78-84), plus the two stage
/// reports the recording does not carry but a gate wants to count.
#[derive(Clone, Debug, Default)]
pub struct Planned {
    /// The returned per-model final positions — the recorder's `planned`.
    pub planned: Vec<V2>,
    /// The `trails` out-array as the pipeline left it — the recorder's `trails`.
    pub trails: Vec<Vec<V2>>,
    /// `opts["flow_order"]`, written back by `_plan_unit_step_unified` (:906).
    pub flow_order: Vec<i64>,
    /// `solve_formation`'s per-sweep trace — compared against
    /// `trace.solve_passes`. Empty when the solver short-circuited.
    pub solve: FormResult,
    /// What the p.11 difficult cap did. Not recorded; reported as a census.
    pub cap: CapReport,
}

/// DELIBERATE DAMAGE, for the red proofs — every field at its shipped value is
/// the shipped pipeline, byte for byte.
#[derive(Clone, Copy, Debug, Default)]
pub struct PlanBend {
    pub flow: FlowBend,
    pub form: FormBend,
    /// RED: shift the p.11 cap by this many inches (one plan cell = 1.0").
    /// Only applied where the caller actually set a cap.
    pub cap_delta_in: f64,
}

impl PlanBend {
    pub fn active(&self) -> bool {
        self.flow.active() || self.form.active() || self.cap_delta_in != 0.0
    }
}

/// `MovementPlanner._append_trail_finals` — movement_planner.gd:561. The
/// solver's own move is drawn onto each trail, so the animated route ends where
/// the model ends. An EMPTY `trails` array is left empty (guard 1's case).
pub fn append_trail_finals(trails: &mut [Vec<V2>], finals: &[V2]) {
    if trails.is_empty() {
        return;
    }
    for i in 0..trails.len().min(finals.len()) {
        let need = match trails[i].last() {
            None => true,
            Some(back) => distance_to(*back, finals[i]) > EPS,
        };
        if need {
            trails[i].push(finals[i]);
        }
    }
}

/// `MovementPlanner.plan_unit_step` — movement_planner.gd:499, the UNIFIED
/// (`opts["radii"]`) branch, on one recorded call.
///
/// The `ThetaCfg` is the shipped configuration the arena and the interactive
/// game both set (`fast_planner = true`, guard 320 — main.gd:2269-2275, and the
/// value every recorded header carries). `plan_unit_step_cfg` takes it
/// explicitly; the gate proves the two agree on all 1 101 calls.
pub fn plan_unit_step(call: &MoveCall) -> Planned {
    plan_unit_step_cfg(call, ThetaCfg::of(true, FAST_PLANNER_GUARD), PlanBend::default())
}

/// `plan_unit_step` with the search configuration and the red-proof knobs made
/// explicit.
pub fn plan_unit_step_cfg(call: &MoveCall, cfg: ThetaCfg, bend: PlanBend) -> Planned {
    // :501-503 — guard 1, BEFORE the radii dispatch: a sub-EPS delta returns the
    // input untouched and never sizes `trails` or writes `flow_order`.
    if length(call.delta) < EPS || call.model_pos.is_empty() {
        return Planned {
            planned: call.model_pos.clone(),
            trails: Vec::new(),
            flow_order: Vec::new(),
            ..Default::default()
        };
    }
    unified(
        &call.model_pos,
        call.delta,
        &call.walls,
        &call.grid,
        call.allow_contact,
        call.board_in,
        &call.opts.radii,
        &FlowOpts::of(call),
        &SolveOpts::of(call),
        call.opts.difficult_cap_in.unwrap_or(0.0),
        cfg,
        bend,
    )
}

/// `MovementPlanner._plan_unit_step_unified` — movement_planner.gd:899.
#[allow(clippy::too_many_arguments)]
pub fn unified(
    model_pos: &[V2],
    delta: V2,
    walls: &[Wall],
    grid: &Grid,
    allow_contact: bool,
    board_in: f64,
    radii: &[f64],
    flow_opts: &FlowOpts,
    solve_opts: &SolveOpts,
    difficult_cap_in: f64,
    cfg: ThetaCfg,
    bend: PlanBend,
) -> Planned {
    // :903-905 — PRIMARY: the sequential per-model flow owns the endpoints and
    // the trails; `order_out` becomes `opts["flow_order"]` at :906.
    let flowed = plan_sequential_flow(
        model_pos, delta, radii, walls, grid, flow_opts, board_in, allow_contact, cfg, bend.flow,
    );
    // :909 — SAFETY NET: the unified constraint solver, starting from the flow's
    // already-mostly-legal placement.
    let solve = solve_formation(
        &flowed.result, radii, walls, solve_opts, board_in, allow_contact, bend.form,
    );
    let mut planned = solve.best.clone();
    let mut trails = flowed.trails;
    // :910 — the solver's own move is drawn onto every trail.
    append_trail_finals(&mut trails, &planned);
    // :913 — NML-230 Breach B, LAST: the p.11 6" per-polyline cap, so a
    // solver-adjusted route that newly enters difficult can never keep the band.
    let cap_in = if difficult_cap_in > 0.0 {
        difficult_cap_in + bend.cap_delta_in
    } else {
        difficult_cap_in
    };
    let cap = cap_difficult_polylines(&mut trails, &mut planned, radii, grid, cap_in);
    Planned { planned, trails, flow_order: flowed.order, solve, cap }
}
