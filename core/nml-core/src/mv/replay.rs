//! Rebuilds the INPUTS of every Theta* search a recorded `plan_unit_step` call
//! made, so the port can be judged path-for-path against the recorded output.
//!
//! This is TRACE SCAFFOLDING, not planner code. `plan_sequential_flow`
//! (movement_planner.gd:1015) builds a fresh option dictionary per model
//! (:1091) and calls `_theta_star_b` with it; `MoveRecorder.trace_model`
//! (move_recorder.gd:198) records that search's OUTPUT (`theta`) but none of its
//! inputs. What is reproduced here is exactly the input half of :1044-1126 — the
//! flow's ORDER is not guessed, it is read straight off the trace entries.
//!
//! WHAT TRACE v1 CANNOT DETERMINE. The per-model zone set carries one body disc
//! per OTHER own model, centred on `result[j]` for an already-placed j
//! (:1084-1086). For a non-charge move `result[j]` is the endpoint AFTER
//! `_pull_into_placed` (:1141-1144) — and `trace_model` fires BEFORE that pull
//! (:1139), so from the SECOND placement on the centre of that disc is unknown.
//! Such searches are marked `determined = false` and the gate reports them
//! separately instead of guessing. Three families stay fully determined:
//!
//!   * every call's searches up to and including its second placement (the
//!     first placed model is never pulled — the pull needs a non-empty `placed`),
//!   * every search of an `allow_contact` call (a charge skips the pull, :1140),
//!   * every search of a one-model unit, and of a call without per-model radii
//!     (no body discs at all).
//!
//! When the recorder grows the post-pull endpoint (trace v2), feed it in through
//! `FlowEntry::pulled` and the determined set becomes the whole corpus — nothing
//! else here changes.
//!
//! NOT COVERED AT ALL: `untangle_endpoints`' re-route searches (:1168) are not
//! traced, so they are invisible to this replay.

use super::cost::{StepOpts, Zone};
use super::geom2::{add, distance_squared_to, length, V2};
use super::io::{MoveCall, MoveHeader};
use super::theta::{theta_star_b, theta_star_bent, ThetaBend, ThetaCfg, ThetaOpts};
use super::{cost::empty_cells, CONTACT_SLIDE_EPS_IN, PLAN_CELL_IN};

/// `plan_sequential_flow`'s `base_zones` — movement_planner.gd:1050, plus the
/// `fast_planner` reach cull at :1058-1069 (sweep-only, and explicitly NOT
/// byte-identical to an uncalled search — but it is what the corpus recorded).
pub fn base_zones(call: &MoveCall, header: &MoveHeader) -> Vec<Zone> {
    if call.opts.zones_rest_only {
        return Vec::new();
    }
    let zones = call.opts.zones.clone();
    if !(header.fast_planner && zones.len() > 8) {
        return zones;
    }
    let cull_reach = length(call.delta).max(call.opts.charge_allowance.unwrap_or(0.0))
        + call.opts.clearance
        + PLAN_CELL_IN;
    let mut kept = Vec::new();
    for z in &zones {
        let keep_r2 = (cull_reach + z.r).powf(2.0);
        for m in &call.model_pos {
            if distance_squared_to(*m, z.c) <= keep_r2 {
                kept.push(*z);
                break;
            }
        }
    }
    kept
}

/// One recorded Theta* search with the inputs it was made with.
#[derive(Clone, Debug)]
pub struct ReplaySearch {
    /// Index of the call inside its corpus.
    pub call: usize,
    /// Index of the entry inside `call.trace.flow` — the flow's PROCESSING
    /// order, deferrals included.
    pub entry: usize,
    pub model: usize,
    /// `model_pos[idx]` (:1130 / :1119).
    pub start: V2,
    /// `model_pos[idx] + delta`, or the charge branch's per-model contact slot
    /// (:1108-1111).
    pub goal: V2,
    /// `oi["zones"]` at the moment of the call (:1082-1091), charge bases
    /// included (:1113).
    pub zones: Vec<Zone>,
    /// `opts["reach_closest"]` — true only on the charge branch (:1114).
    pub reach_closest: bool,
    /// This entry came from the charge branch (:1096-1126).
    pub charge: bool,
    /// The recorded `_theta_star_b` return value.
    pub expected: Vec<V2>,
    /// Are these inputs EXACTLY what the GDScript search saw? See the module note.
    pub determined: bool,
}

impl ReplaySearch {
    /// The option dictionary `_theta_star_b` was called with. `avoid_fine` is
    /// empty on purpose: the flow's per-model `oi` (:1091) has no such key.
    pub fn opts<'a>(&'a self, call: &'a MoveCall) -> ThetaOpts<'a> {
        ThetaOpts {
            step: StepOpts {
                clearance: call.opts.clearance,
                zones: &self.zones,
                avoid_cells: &call.opts.avoid_cells,
                avoid_fine: empty_cells(),
            },
            reach_closest: self.reach_closest,
        }
    }

    /// Runs the port on these inputs.
    pub fn run(&self, call: &MoveCall, cfg: ThetaCfg) -> Vec<V2> {
        let o = self.opts(call);
        theta_star_b(self.start, self.goal, &call.walls, &call.grid, call.board(), &o, cfg)
    }

    /// Same, with the red-proof knobs.
    pub fn run_bent(&self, call: &MoveCall, cfg: ThetaCfg, bend: ThetaBend) -> Vec<V2> {
        let o = self.opts(call);
        theta_star_bent(
            self.start,
            self.goal,
            &call.walls,
            &call.grid,
            call.board(),
            &o,
            cfg,
            bend,
        )
    }
}

/// Every Theta* search the trace of `call` recorded, in flow order.
pub fn searches(call_idx: usize, call: &MoveCall, header: &MoveHeader) -> Vec<ReplaySearch> {
    let n = call.model_pos.len();
    let have_r = call.opts.radii.len() == n;
    let base = base_zones(call, header);
    // :1096 — the charge branch needs BOTH the flag and the body goal.
    let charge = call.allow_contact && call.opts.charge_goal.is_some();
    // :1140 — an allow_contact move never runs `_pull_into_placed`, so every one
    // of its endpoints is the recorded `walked` endpoint.
    let never_pulled = call.allow_contact || !have_r;

    let mut out = Vec::with_capacity(call.trace.flow.len());
    // `result[j]` for the models already settled, and whether it is EXACT.
    let mut result: Vec<V2> = call.model_pos.clone();
    let mut placed: Vec<usize> = Vec::new();
    let mut exact: Vec<bool> = vec![true; n];

    for (k, f) in call.trace.flow.iter().enumerate() {
        let idx = f.model as usize;
        if idx >= n {
            continue;
        }
        // :1082-1086 — one body disc per OTHER own model, placed ones at their
        // settled spot, the rest at their start.
        let mut zones = base.clone();
        if have_r {
            for j in 0..n {
                if j == idx {
                    continue;
                }
                zones.push(Zone {
                    c: result[j],
                    r: (call.opts.radii[j] + call.opts.radii[idx] - CONTACT_SLIDE_EPS_IN).max(0.0),
                });
            }
        }
        let determined = placed.iter().all(|j| exact[*j]);
        let (goal, reach_closest) = if charge {
            // :1108-1111 — the per-model contact slot, else the body centre.
            let body = call.opts.charge_goal.unwrap();
            let goal_pt = call.opts.charge_slots.get(idx).copied().unwrap_or(body);
            // :1112-1113 — the target's own bases become no-through zones.
            for tb in &call.opts.charge_tgt_bases {
                zones.push(Zone {
                    c: tb.0,
                    r: (tb.1 + call.opts.radii.get(idx).copied().unwrap_or(0.0)
                        - CONTACT_SLIDE_EPS_IN)
                        .max(0.0),
                });
            }
            (goal_pt, true)
        } else {
            // :1130 — the rigid slot.
            (add(call.model_pos[idx], call.delta), false)
        };
        out.push(ReplaySearch {
            call: call_idx,
            entry: k,
            model: idx,
            start: call.model_pos[idx],
            goal,
            zones,
            reach_closest,
            charge,
            expected: f.theta.clone(),
            determined,
        });
        // Advance the flow state exactly as :1120-1155 does.
        if !charge && f.deferred {
            continue;   // :1136 — back of the queue, position unchanged.
        }
        let end = *f.walked.last().unwrap_or(&call.model_pos[idx]);
        // trace v2 hook: the post-`_pull_into_placed` endpoint, when recorded.
        let (end, end_exact) = match f.pulled {
            Some(p) => (p, true),
            None => (end, never_pulled || placed.is_empty()),
        };
        result[idx] = end;
        exact[idx] = end_exact;
        placed.push(idx);
    }
    out
}
