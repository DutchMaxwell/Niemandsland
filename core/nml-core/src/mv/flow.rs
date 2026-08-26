//! NML-1073 M4-4 — `MovementPlanner.plan_sequential_flow`
//! (movement_planner.gd:1014), `untangle_endpoints` (:1181),
//! `_pull_into_placed` (:1222), `_centroid` (:421) and `_linked_r` (:1648), a
//! LITERAL transcription.
//!
//! This is the stage that OWNS the per-model endpoints. Everything M4-1..M4-3
//! ported is a leaf it calls; what is new here is the SEQUENCING, and the
//! sequencing is the part a rewrite silently gets wrong:
//!
//!   * FLOW ORDER (:1041-1047) is nearest-to-`goal_anchor` first, ties by model
//!     index — but the tie is an EPS BAND on `distance_squared_to`, not on the
//!     distance, so two models 0.0001 in² apart count as tied and the LOWER
//!     INDEX goes first. `goal_anchor` is the centroid PLUS delta, and the
//!     centroid divides a `Vector2` by the model count, i.e. in f32.
//!   * BODY ZONES (:1082-1086) are rebuilt PER MODEL: one disc per OTHER own
//!     model at `r_i + r_j - CONTACT_SLIDE_EPS_IN`, centred on the settled
//!     endpoint for an already-placed model and on the START for one still
//!     waiting. The epsilon is not cosmetic — the deploy grid packs bases to
//!     exact contact, and a disc of exactly the radii sum makes every outgoing
//!     tangent step read as blocked (see the GDScript's own note at :1075-1081).
//!   * THE DEFERRAL RULE (:1145-1147): a model that wanted to travel more than
//!     `STEP_IN` and achieved less than `STUCK_FRACTION` of it goes to the BACK
//!     of the queue — once, and only while somebody else still waits. Its
//!     stalled attempt is recorded and then thrown away; `result` keeps the
//!     start position until the retry.
//!   * `_pull_into_placed` (:1222) is the progressive-coherency step, and it is
//!     the reason the trace needs a post-pull field at all: it moves the
//!     endpoint AFTER `trace_model` has already recorded the walk.
//!   * THE CHARGE BRANCH (:1103-1126) skips the deferral rule AND the pull, aims
//!     at a per-model contact slot, adds the target's own bases as no-through
//!     zones and appends the goal to the taut path UNCHECKED.
//!   * `untangle_endpoints` (:1181) runs `UNTANGLE_PASSES` = 4 sweeps of an
//!     endpoint 2-opt and then RE-ROUTES every trail whose end moved (:1168-
//!     1171) — those re-routes are extra Theta* searches, and they are why the
//!     recorded `theta_searches` list is longer than the flow's own entries.
//!
//! PRECISION. Positions are `Vector2` = f32; `allowance`, `intended`, every
//! distance and every radius sum are GDScript `float` = f64. The two places
//! where a `Vector2` is divided by a `float` (`_centroid`, the pull's unit step)
//! narrow the divisor to f32 first — see `geom2::div`.

use std::collections::VecDeque;

use super::cost::{empty_cells, step_blocked, CellSet, Grid, StepOpts, Wall, Zone};
use super::geom2::{
    add, distance_squared_to, distance_to, div, length, mul, polyline_length, sub, V2,
};
use super::io::{MoveCall, ThetaPop};
use super::pull::{board_clamp, string_pull_bent, walk_offset_bent, PullBend, WalkBend};
use super::theta::{board_extents, theta_star_traced_bent, ThetaBend, ThetaCfg, ThetaOpts};
use super::{
    COHERENCY_IN, COH_PULL_IN, CONTACT_SLIDE_EPS_IN, EPS, GATHER_PASSES, PLAN_CELL_IN, STEP_IN,
    STUCK_FRACTION, UNTANGLE_PASSES,
};

/// `MovementPlanner._centroid` — movement_planner.gd:421. The sum accumulates in
/// f32 (`Vector2 += Vector2`) and the divisor narrows to f32.
pub fn centroid(model_pos: &[V2]) -> V2 {
    if model_pos.is_empty() {
        return [0.0, 0.0];
    }
    let mut s: V2 = [0.0, 0.0];
    for m in model_pos {
        s = add(s, *m);
    }
    div(s, model_pos.len() as f64)
}

/// `MovementPlanner._linked_r` — movement_planner.gd:1648. Radii-aware 1" link:
/// the f32 `distance_to` against an f64 right-hand side.
#[inline]
pub fn linked_r(a: V2, b: V2, ra: f64, rb: f64) -> bool {
    distance_to(a, b) <= ra + rb + COHERENCY_IN + EPS
}

/// The `opts` keys `plan_sequential_flow` reads beyond the step layer —
/// solo_controller.gd:5979-6033, loaded by `mv::io::CallOpts`.
#[derive(Clone, Copy, Debug)]
pub struct FlowOpts<'a> {
    /// `opts["clearance"]`.
    pub clearance: f64,
    /// `opts["zones"]` — the OTHER units' spacing discs.
    pub zones: &'a [Zone],
    /// `opts["zones_rest_only"]` (:1051) — Traversal: no zones during the move.
    pub zones_rest_only: bool,
    /// `opts["avoid_cells"]`.
    pub avoid_cells: &'a CellSet,
    /// `opts["board_y_in"]` (#215).
    pub board_y_in: f64,
    /// `opts["charge_allowance"]` (:1039) — absent means the straight delta length.
    pub charge_allowance: Option<f64>,
    /// `opts["charge_goal"]` (:1096) — BOTH this and `allow_contact` arm the charge branch.
    pub charge_goal: Option<V2>,
    /// `opts["charge_tgt_bases"]` (:1112).
    pub charge_tgt_bases: &'a [(V2, f64)],
    /// `opts["charge_slots"]` (:1105).
    pub charge_slots: &'a [V2],
}

impl<'a> FlowOpts<'a> {
    /// The options one recorded call was made with.
    pub fn of(call: &'a MoveCall) -> FlowOpts<'a> {
        FlowOpts {
            clearance: call.opts.clearance,
            zones: &call.opts.zones,
            zones_rest_only: call.opts.zones_rest_only,
            avoid_cells: &call.opts.avoid_cells,
            board_y_in: call.opts.board_y_in,
            charge_allowance: call.opts.charge_allowance,
            charge_goal: call.opts.charge_goal,
            charge_tgt_bases: &call.opts.charge_tgt_bases,
            charge_slots: &call.opts.charge_slots,
        }
    }
}

/// DELIBERATE DAMAGE, for the red proofs — every field at its shipped value is
/// the shipped flow, byte for byte. Same convention as `ThetaBend`/`WalkBend`.
#[derive(Clone, Copy, Debug)]
pub struct FlowBend {
    /// `UNTANGLE_PASSES` — movement_planner.gd:43. Shipped: 4.
    pub untangle_passes: i64,
    /// RED: never defer a stalled lead model (movement_planner.gd:1145-1150).
    pub no_defer: bool,
    /// `CONTACT_SLIDE_EPS_IN` — movement_planner.gd:79. Shipped: 0.05.
    pub contact_slide_eps_in: f64,
    /// The leaf stages' own knobs, so one binary can bend the whole pipeline.
    pub theta: ThetaBend,
    pub pull: PullBend,
    pub walk: WalkBend,
}

impl Default for FlowBend {
    fn default() -> Self {
        FlowBend {
            untangle_passes: UNTANGLE_PASSES,
            no_defer: false,
            contact_slide_eps_in: CONTACT_SLIDE_EPS_IN,
            theta: ThetaBend::default(),
            pull: PullBend::default(),
            walk: WalkBend::default(),
        }
    }
}

impl FlowBend {
    /// Is anything bent? A gate reports "moved" counts only when it is.
    pub fn active(&self) -> bool {
        self.untangle_passes != UNTANGLE_PASSES
            || self.no_defer
            || self.contact_slide_eps_in != CONTACT_SLIDE_EPS_IN
            || self.theta.strict_open
            || self.theta.diag_swap.is_some()
            || self.pull.cost_break
            || self.walk.eps_swapped
            || self.walk.bisect_steps != WalkBend::default().bisect_steps
    }
}

/// One `MoveRecorder.trace_model` + `trace_pull` + `trace_walk_spent` entry —
/// move_recorder.gd:214-238. ONE PER MODEL PER ATTEMPT: a deferred model records
/// its stalled try and, later, its retry.
#[derive(Clone, Debug)]
pub struct FlowStep {
    pub model: usize,
    /// `_theta_star_b`'s returned polyline (:1130 / :1115).
    pub theta: Vec<V2>,
    /// `string_pull` of it, charge goal already appended (:1131 / :1116-1118).
    pub taut: Vec<V2>,
    /// `_walk_offset` of that, BEFORE `_pull_into_placed` may append to it.
    pub walked: Vec<V2>,
    /// This attempt went to the back of the queue (:1148-1151).
    pub deferred: bool,
    /// The endpoint AFTER `_pull_into_placed` (:1160-1163). Equal to `walked`'s
    /// last point on a charge, on a deferred attempt and whenever the pull was a
    /// no-op — exactly the recorder's `pull` field.
    pub pulled: V2,
    /// `_walk_offset`'s recomputed arc length of `walked` (:1561-1568).
    pub walk_spent: f64,
}

/// Everything one `plan_sequential_flow` call produces, including the three
/// trace channels the corpus recorded.
#[derive(Clone, Debug, Default)]
pub struct FlowResult {
    /// The returned per-model endpoints, untangle applied.
    pub result: Vec<V2>,
    /// The per-model polylines (`trails`), untangle re-routes applied.
    pub trails: Vec<Vec<V2>>,
    /// `order_out` — the value written back as `opts["flow_order"]` (:900-905).
    pub order: Vec<i64>,
    /// `MoveRecorder.trace_model` entries, in processing order.
    pub entries: Vec<FlowStep>,
    /// `MoveRecorder.trace_swap` entries (:1204).
    pub swaps: Vec<[i64; 2]>,
    /// `MoveRecorder.trace_theta_search` lists, in invocation order: every flow
    /// search that entered the expansion loop, then every untangle re-route
    /// that did. An early-out records nothing, exactly as the recorder does.
    pub searches: Vec<Vec<ThetaPop>>,
    /// How many of `searches` came from the QUEUE LOOP; the rest are
    /// `untangle_endpoints`' re-routes (:1168). The recording carries no such
    /// split — it is here so a gate can report the two populations apart.
    pub flow_searches: usize,
}

/// `plan_sequential_flow`'s `base_zones` — movement_planner.gd:1050-1069, the
/// `fast_planner` reach cull included (sweep-only, and explicitly NOT
/// byte-identical to an unculled search — but it is what the corpus recorded).
fn base_zones(model_pos: &[V2], delta: V2, opts: &FlowOpts, cfg: ThetaCfg) -> Vec<Zone> {
    if opts.zones_rest_only {
        return Vec::new();
    }
    let zones = opts.zones.to_vec();
    if !(cfg.fast_planner && zones.len() > 8) {
        return zones;
    }
    // :1059 — NOTE the default is 0.0 here, not the delta length.
    let cull_reach = length(delta).max(opts.charge_allowance.unwrap_or(0.0))
        + opts.clearance
        + PLAN_CELL_IN;
    let mut kept = Vec::new();
    for z in &zones {
        let keep_r2 = (cull_reach + z.r).powf(2.0);
        for m in model_pos {
            if distance_squared_to(*m, z.c) <= keep_r2 {
                kept.push(*z);
                break;
            }
        }
    }
    kept
}

/// The flow's processing order — movement_planner.gd:1041-1047.
///
/// The comparator is `|da - db| > EPS ? da < db : a < b` over
/// `distance_squared_to(goal_anchor)`, i.e. the tie band is in SQUARED inches.
pub fn flow_order(model_pos: &[V2], delta: V2) -> Vec<usize> {
    let goal_anchor = add(centroid(model_pos), delta);
    let mut order: Vec<usize> = (0..model_pos.len()).collect();
    order.sort_by(|&a, &b| {
        let da = distance_squared_to(model_pos[a], goal_anchor);
        let db = distance_squared_to(model_pos[b], goal_anchor);
        if (da - db).abs() > EPS {
            da.partial_cmp(&db).unwrap()
        } else {
            a.cmp(&b)
        }
    });
    order
}

/// `MovementPlanner.plan_sequential_flow` — movement_planner.gd:1014, including
/// the `untangle_endpoints` sweep and its trail re-routes at :1166-1171.
#[allow(clippy::too_many_arguments)]
pub fn plan_sequential_flow(
    model_pos: &[V2],
    delta: V2,
    radii: &[f64],
    walls: &[Wall],
    grid: &Grid,
    opts: &FlowOpts,
    board_in: f64,
    allow_contact: bool,
    cfg: ThetaCfg,
    bend: FlowBend,
) -> FlowResult {
    let n = model_pos.len();
    let mut out = FlowResult {
        result: model_pos.to_vec(),
        trails: model_pos.iter().map(|p| vec![*p]).collect(),
        ..Default::default()
    };
    if n == 0 {
        return out;
    }
    // :1029 — the board is resolved ONCE and handed down: the per-model option
    // dictionaries below are rebuilt from scratch.
    let board = board_extents(board_in, opts.board_y_in);
    // :1039 — a charge funds its detour arc from the full charge band.
    let allowance = opts.charge_allowance.unwrap_or_else(|| length(delta));
    let order = flow_order(model_pos, delta);

    let base_clearance = opts.clearance;
    let base = base_zones(model_pos, delta, opts, cfg);
    let have_r = radii.len() == n;
    // :1096 — the charge branch needs BOTH the flag and the body goal.
    let charging = allow_contact && opts.charge_goal.is_some();

    let mut placed: Vec<usize> = Vec::new();
    let mut is_placed: Vec<bool> = vec![false; n];
    let mut deferred: Vec<bool> = vec![false; n];
    let mut queue: VecDeque<usize> = order.iter().copied().collect();

    while let Some(idx) = queue.pop_front() {
        // :1082-1086 — one body disc per OTHER own model.
        let mut zones = base.clone();
        if have_r {
            for j in 0..n {
                if j == idx {
                    continue;
                }
                let jc = if is_placed[j] { out.result[j] } else { model_pos[j] };
                zones.push(Zone {
                    c: jc,
                    r: (radii[j] + radii[idx] - bend.contact_slide_eps_in).max(0.0),
                });
            }
        }
        // :1091 — `oi` carries NO `avoid_fine` key, so that set is empty here.
        let slot = add(model_pos[idx], delta);

        if charging {
            // :1103-1126 — the charge branch.
            let body = opts.charge_goal.unwrap();
            let goal_pt = opts.charge_slots.get(idx).copied().unwrap_or(body);
            let mut czones = zones.clone();
            for tb in opts.charge_tgt_bases {
                czones.push(Zone {
                    c: tb.0,
                    r: (tb.1 + radii.get(idx).copied().unwrap_or(0.0) - bend.contact_slide_eps_in)
                        .max(0.0),
                });
            }
            let cstep = StepOpts {
                clearance: base_clearance,
                zones: &czones,
                avoid_cells: opts.avoid_cells,
                avoid_fine: empty_cells(),
            };
            let coi = ThetaOpts { step: cstep, reach_closest: true };
            let (croute, pops) = theta_star_traced_bent(
                model_pos[idx], goal_pt, walls, grid, board, &coi, cfg, bend.theta,
            );
            if !pops.is_empty() {
                out.searches.push(pops);
            }
            let mut ctaut = string_pull_bent(&croute, walls, grid, &cstep, bend.pull);
            // :1117-1118 — appended UNCHECKED when the pull did not already end there.
            if ctaut.is_empty() || distance_to(*ctaut.last().unwrap(), goal_pt) > EPS {
                ctaut.push(goal_pt);
            }
            let cleg = walk_offset_bent(
                model_pos[idx], &ctaut, [0.0, 0.0], allowance, walls, grid, &cstep, board,
                bend.walk,
            );
            let end = *cleg.last().unwrap();
            out.entries.push(FlowStep {
                model: idx,
                theta: croute,
                taut: ctaut,
                walked: cleg.clone(),
                deferred: false,
                // :1130 (main) — a charge skips the pull, so post == pre.
                pulled: end,
                walk_spent: polyline_length(&cleg),
            });
            out.result[idx] = end;
            placed.push(idx);
            is_placed[idx] = true;
            out.trails[idx] = cleg;
            out.order.push(idx as i64);
            continue;
        }

        let step = StepOpts {
            clearance: base_clearance,
            zones: &zones,
            avoid_cells: opts.avoid_cells,
            avoid_fine: empty_cells(),
        };
        let oi = ThetaOpts { step, reach_closest: false };
        let (route, pops) =
            theta_star_traced_bent(model_pos[idx], slot, walls, grid, board, &oi, cfg, bend.theta);
        if !pops.is_empty() {
            out.searches.push(pops);
        }
        let taut = string_pull_bent(&route, walls, grid, &step, bend.pull);
        let mut leg = walk_offset_bent(
            model_pos[idx], &taut, [0.0, 0.0], allowance, walls, grid, &step, board, bend.walk,
        );
        let mut final_pt = *leg.last().unwrap();
        // :1145-1147 — the lead-stall deferral. `queue` has ALREADY been popped,
        // so "not empty" means somebody else is still waiting.
        let intended = allowance.min(distance_to(model_pos[idx], slot));
        let will_defer = !bend.no_defer
            && !queue.is_empty()
            && !deferred[idx]
            && intended > STEP_IN
            && distance_to(model_pos[idx], final_pt) < intended * STUCK_FRACTION;
        // :1148 — trace_model fires BEFORE the defer check and BEFORE the pull.
        out.entries.push(FlowStep {
            model: idx,
            theta: route,
            taut,
            walked: leg.clone(),
            deferred: will_defer,
            pulled: final_pt,
            walk_spent: polyline_length(&leg),
        });
        if will_defer {
            deferred[idx] = true;
            queue.push_back(idx);
            continue;
        }
        // :1157-1163 — progressive coherency. A charge is exempt, and so is the
        // very first placement (`placed` is still empty).
        if !allow_contact && have_r && !placed.is_empty() {
            let linked = pull_into_placed(
                final_pt, idx, radii, &placed, &out.result, walls, base_clearance, &base,
                opts.avoid_cells, board,
            );
            if distance_to(linked, final_pt) > EPS {
                leg.push(linked);
                final_pt = linked;
            }
        }
        out.entries.last_mut().unwrap().pulled = final_pt;
        out.result[idx] = final_pt;
        placed.push(idx);
        is_placed[idx] = true;
        out.trails[idx] = leg;
        out.order.push(idx as i64);
    }

    out.flow_searches = out.searches.len();
    // :1173-1179 — the endpoint 2-opt, then a re-route of every trail whose end
    // moved. `untangle_oi` carries the OTHER units' zones only, never the bodies.
    let ustep = StepOpts {
        clearance: base_clearance,
        zones: &base,
        avoid_cells: opts.avoid_cells,
        avoid_fine: empty_cells(),
    };
    if !allow_contact
        && n >= 2
        && untangle_endpoints(
            model_pos, &mut out.result, radii, allowance, walls, &ustep, bend.untangle_passes,
            &mut out.swaps,
        )
    {
        let uoi = ThetaOpts { step: ustep, reach_closest: false };
        for i in 0..n {
            let t_end = *out.trails[i].last().unwrap_or(&model_pos[i]);
            if distance_to(t_end, out.result[i]) > EPS {
                let (rroute, pops) = theta_star_traced_bent(
                    model_pos[i], out.result[i], walls, grid, board, &uoi, cfg, bend.theta,
                );
                if !pops.is_empty() {
                    out.searches.push(pops);
                }
                // NOTE: the re-route is string-pulled but NOT walked, so the
                // re-drawn corridor is not allowance-clipped (:1171).
                out.trails[i] = string_pull_bent(&rroute, walls, grid, &ustep, bend.pull);
            }
        }
    }
    out
}

/// `MovementPlanner.untangle_endpoints` — movement_planner.gd:1181. Mutates
/// `result`, appends every accepted swap to `swaps` (the recorder's
/// `trace_swap`), and returns whether anything swapped.
#[allow(clippy::too_many_arguments)]
pub fn untangle_endpoints(
    model_pos: &[V2],
    result: &mut [V2],
    radii: &[f64],
    allowance: f64,
    walls: &[Wall],
    step_opts: &StepOpts,
    passes: i64,
    swaps: &mut Vec<[i64; 2]>,
) -> bool {
    let n = model_pos.len();
    let mut any = false;
    for _ in 0..passes {
        let mut improved = false;
        for i in 0..n {
            for j in (i + 1)..n {
                // :1188 — same-radius pairs only; a unit WITHOUT radii skips the
                // test entirely (the index guard is false, so the `and` fails).
                if i < radii.len() && j < radii.len() && (radii[i] - radii[j]).abs() > 0.0005 {
                    continue;
                }
                let si = model_pos[i];
                let sj = model_pos[j];
                let ei = result[i];
                let ej = result[j];
                if distance_to(si, ej) > allowance + EPS || distance_to(sj, ei) > allowance + EPS {
                    continue;
                }
                if distance_to(si, ej) + distance_to(sj, ei) + EPS
                    < distance_to(si, ei) + distance_to(sj, ej)
                {
                    // :1199-1201 — the wall gate on BOTH new chords.
                    if !walls.is_empty()
                        && (step_blocked(si, ej, walls, step_opts)
                            || step_blocked(sj, ei, walls, step_opts))
                    {
                        continue;
                    }
                    result[i] = ej;
                    result[j] = ei;
                    improved = true;
                    any = true;
                    swaps.push([i as i64, j as i64]);
                }
            }
        }
        if !improved {
            break;
        }
    }
    any
}

/// `MovementPlanner._pull_into_placed` — movement_planner.gd:1222. Steps `pos`
/// toward the NEAREST already-placed own model (nearest by BASE EDGE, not by
/// centre) in `COH_PULL_IN` increments until they link, a step is blocked, or
/// `GATHER_PASSES` runs out. The neighbour's own body is deliberately NOT a
/// zone here, so base contact stays reachable.
#[allow(clippy::too_many_arguments)]
pub fn pull_into_placed(
    pos: V2,
    idx: usize,
    radii: &[f64],
    placed: &[usize],
    result: &[V2],
    walls: &[Wall],
    clearance: f64,
    other_zones: &[Zone],
    avoid_cells: &CellSet,
    board: V2,
) -> V2 {
    let mut nearest: i64 = -1;
    let mut nd = f64::INFINITY;
    for &j in placed {
        let edge = distance_to(pos, result[j]) - radii[idx] - radii[j];
        if edge < nd {
            nd = edge;
            nearest = j as i64;
        }
    }
    if nearest < 0 {
        return pos;
    }
    let near_i = nearest as usize;
    if linked_r(pos, result[near_i], radii[idx], radii[near_i]) {
        return pos;
    }
    let step = StepOpts {
        clearance,
        zones: other_zones,
        avoid_cells,
        avoid_fine: empty_cells(),
    };
    let target = result[near_i];
    let mut cur = pos;
    for _ in 0..GATHER_PASSES {
        if linked_r(cur, target, radii[idx], radii[near_i]) {
            break;
        }
        let to_n = sub(target, cur);
        let d = length(to_n);
        if d < EPS {
            break;
        }
        // :1246 — `to_n / d * minf(COH_PULL_IN, d)`, left to right, both scalars
        // narrowing to f32 for the Vector2 operators.
        let cand = board_clamp(add(cur, mul(div(to_n, d), COH_PULL_IN.min(d))), board);
        if step_blocked(cur, cand, walls, &step) {
            break;
        }
        cur = cand;
    }
    cur
}

/// Runs the whole flow on one RECORDED call — the gate's entry point.
pub fn run_call(call: &MoveCall, cfg: ThetaCfg, bend: FlowBend) -> FlowResult {
    let opts = FlowOpts::of(call);
    plan_sequential_flow(
        &call.model_pos,
        call.delta,
        &call.opts.radii,
        &call.walls,
        &call.grid,
        &opts,
        call.board_in,
        call.allow_contact,
        cfg,
        bend,
    )
}

/// The endpoints the RECORDING says the flow produced, rebuilt from the trace:
/// each model's last NON-DEFERRED entry's post-pull point, with the recorded
/// 2-opt swaps applied in order. `None` when the trace cannot supply one for
/// every model (a trace v1 line, or a model with no final entry).
///
/// This is the only endpoint truth the corpus carries at this stage — the
/// recorded `planned` is post-`solve_formation` and post-`_cap_difficult_-
/// polylines`, two stages M4-5/M4-6 still owe.
pub fn recorded_endpoints(call: &MoveCall) -> Option<Vec<V2>> {
    let n = call.model_pos.len();
    let mut out = call.model_pos.clone();
    let mut seen = vec![false; n];
    for f in &call.trace.flow {
        if f.deferred {
            continue;
        }
        let i = f.model as usize;
        if i >= n {
            return None;
        }
        out[i] = f.pulled?;
        seen[i] = true;
    }
    if seen.iter().any(|s| !s) {
        return None;
    }
    for s in &call.trace.untangle_swaps {
        let (i, j) = (s[0] as usize, s[1] as usize);
        if i >= n || j >= n {
            return None;
        }
        out.swap(i, j);
    }
    Some(out)
}
