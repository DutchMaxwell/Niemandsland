//! NML-1073 M4-6a — the MOVE seam's entry point.
//!
//! One `MovementPlanner.plan_unit_step` call in, one plan out. This is the ONLY
//! door the GDExtension knocks on: everything the live game sends is first
//! turned into the JSON shape `scripts/solo/move_recorder.gd` writes and then
//! read back through `io::read_moves` — the SAME reader the corpus gate uses —
//! so the seam and the gate can never disagree about what a call IS.
//!
//! The solver itself lands in M4-5 (flow/untangle, formation, charge extras).
//! Until then `plan_unit_step_call` declines, the GDScript planner answers every
//! call, and the plumbing below is what gets proven: the marshalling, the
//! reader, and the fallback.

use super::cost::{CellSet, Grid};
use super::geom2::{to_f64, V2};
use super::io::{read_moves, MoveCall};

/// What `MovementPlanner.plan_unit_step` hands back — the three things
/// `MoveRecorder.finish` records (move_recorder.gd:92-95): the per-model final
/// positions it RETURNS, the per-model polylines it appended to `plan_trails`,
/// and the `opts["flow_order"]` it wrote back into the caller's own dictionary.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct Planned {
    /// The returned array — one final position per model, in model order.
    pub planned: Vec<V2>,
    /// `plan_trails` — one polyline per model, in model order.
    pub trails: Vec<Vec<V2>>,
    /// `opts["flow_order"]` — the order the sequential flow filed the models in.
    pub flow_order: Vec<i64>,
}

/// The port's answer for ONE recorded/live call.
///
/// M4-6a ships the seam, not the solver: this declines until M4-5 lands the
/// flow/untangle and formation stages it stands on. A decline is not a failure
/// — the caller falls back to `MovementPlanner.plan_unit_step` and the game is
/// byte-identical either way (rule R1: the port is never load-bearing).
pub fn plan_unit_step_call(call: &MoveCall) -> Result<Planned, String> {
    let _ = call;
    Err("M4-5 pending".into())
}

// ------------------------------------------------------------------ reader --

/// The synthetic line-1 header `read_moves` insists on, built from THIS crate's
/// own constants.
///
/// A live seam call carries its walls inline, so it needs no header at all —
/// but the reader is the corpus reader and the corpus has a header, so one is
/// synthesised rather than a second parser written. Its `walls` are empty: a
/// recorded line whose `"walls"` is the string `"header"` therefore resolves to
/// NO walls here. Both halves of the round-trip gate go through this same door,
/// so that resolution is identical on both sides; the live seam never sends
/// `"header"` at all.
fn header_line() -> String {
    let diag: Vec<[i64; 2]> = super::THETA_DIAG.iter().map(|d| [d.0 as i64, d.1 as i64]).collect();
    serde_json::json!({
        "kind": "header",
        "board_in": [0.0, 0.0],
        "board_y_in": 0.0,
        "inches_to_meters": 0.0254,
        "fast_planner": false,
        "fast_planner_guard": super::FAST_PLANNER_GUARD,
        "walls": Vec::<[[f64; 2]; 2]>::new(),
        "constants": {
            "EPS": super::EPS,
            "BASE_CONTACT_IN": super::BASE_CONTACT_IN,
            "COHERENCY_IN": super::COHERENCY_IN,
            "MAX_CHAIN_IN": super::MAX_CHAIN_IN,
            "LINK_IN": super::LINK_IN,
            "SPREAD_IN": super::SPREAD_IN,
            "STEP_IN": super::STEP_IN,
            "STUCK_FRACTION": super::STUCK_FRACTION,
            "COH_PULL_IN": super::COH_PULL_IN,
            "COH_PASSES": super::COH_PASSES,
            "LAG_FRACTION": super::LAG_FRACTION,
            "GATHER_PASSES": super::GATHER_PASSES,
            "UNTANGLE_PASSES": super::UNTANGLE_PASSES,
            "SLIDE_ANGLES": super::SLIDE_ANGLES,
            "PLAN_CELL_IN": super::PLAN_CELL_IN,
            "FAST_PLANNER_GUARD": super::FAST_PLANNER_GUARD,
            "DIFFICULT_COST_MULT": super::DIFFICULT_COST_MULT,
            "DANGEROUS_COST_MULT": super::DANGEROUS_COST_MULT,
            "THETA_DIAG": diag,
            "SOLVE_PASSES": super::SOLVE_PASSES,
            "CONTACT_SLIDE_EPS_IN": super::CONTACT_SLIDE_EPS_IN,
            "TERRAIN_PUSH_MAX_IN": super::TERRAIN_PUSH_MAX_IN,
            "TERRAIN_PUSH_STEP_IN": super::TERRAIN_PUSH_STEP_IN,
            "RADIAL_DIRS": super::RADIAL_DIRS,
            "W_TERRAIN": super::W_TERRAIN,
            "W_COHERENCY": super::W_COHERENCY,
            "W_OVERLAP": super::W_OVERLAP,
            "W_ZONE": super::W_ZONE,
            "COHERENCY_BISECT_STEPS": super::COHERENCY_BISECT_STEPS,
            "CLEARANCE_EPS_IN": super::CLEARANCE_EPS_IN,
        }
    })
    .to_string()
}

/// Reads ONE `{"kind":"call", …}` JSON line — a recorded corpus line, or the
/// live seam's own marshalled dictionary — through `io::read_moves`.
pub fn read_call_line(line: &str) -> Result<MoveCall, String> {
    let mut buf = header_line();
    buf.push('\n');
    buf.push_str(line.trim_end());
    buf.push('\n');
    let corpus = read_moves(buf.as_bytes(), "<seam>")?;
    corpus.calls.into_iter().next().ok_or_else(|| "<seam>: no call line".to_string())
}

// -------------------------------------------------------------- canonical ---

fn pts(v: &[V2]) -> Vec<[f64; 2]> {
    v.iter().map(|p| to_f64(*p)).collect()
}

fn cells(s: &CellSet) -> Vec<[i64; 2]> {
    let mut out: Vec<[i64; 2]> = s.iter().map(|&(x, y)| [x as i64, y as i64]).collect();
    out.sort_unstable();
    out
}

fn grid_rows(g: &Grid) -> Vec<[i64; 3]> {
    let mut out: Vec<[i64; 3]> = g.iter().map(|(&(x, y), &t)| [x as i64, y as i64, t]).collect();
    out.sort_unstable();
    out
}

/// The INPUT half of a `MoveCall`, as one deterministic JSON string.
///
/// Two calls print identically iff the port parsed the same inputs out of them.
/// The cell sets and the terrain grid are HashSet/HashMap, so they are SORTED
/// here — insertion order is not part of what a call is. The recorded OUTPUTS
/// (`planned`/`trails`/`flow_order`) and the trace are deliberately left out:
/// the live seam sends inputs only, and this string is what the round-trip gate
/// compares its dictionary against.
pub fn canonical_input(c: &MoveCall) -> String {
    let o = &c.opts;
    let v = serde_json::json!({
        "unit": c.unit,
        "act": c.act,
        "round": c.round,
        "rung": c.rung,
        "model_pos": pts(&c.model_pos),
        "delta": to_f64(c.delta),
        "walls": c.walls.iter().map(|w| [to_f64(w[0]), to_f64(w[1])]).collect::<Vec<_>>(),
        "grid": grid_rows(&c.grid),
        "allow_contact": c.allow_contact,
        "board_in": c.board_in,
        "opts": {
            "radii": o.radii,
            "clearance": o.clearance,
            "zones": o.zones.iter()
                .map(|z| serde_json::json!({"c": to_f64(z.c), "r": z.r}))
                .collect::<Vec<_>>(),
            "avoid_cells": cells(&o.avoid_cells),
            "avoid_fine": cells(&o.avoid_fine),
            "forbid_cells": cells(&o.forbid_cells),
            "board_y_in": o.board_y_in,
            "difficult_cap_in": o.difficult_cap_in,
            "zones_rest_only": o.zones_rest_only,
            "charge_allowance": o.charge_allowance,
            "charge_goal": o.charge_goal.map(to_f64),
            "charge_tgt_bases": o.charge_tgt_bases.iter()
                .map(|(p, r)| serde_json::json!([to_f64(*p), r]))
                .collect::<Vec<_>>(),
            "charge_slots": pts(&o.charge_slots),
        }
    });
    v.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A minimal but complete call line — every required `PlainCall` field.
    fn line() -> String {
        serde_json::json!({
            "kind": "call", "unit": "Alpha", "act": 3, "round": 2, "rung": "reach_in=6.0000",
            "model_pos": [[10.5, 20.25], [12.0, 20.25]],
            "delta": [3.5, -1.25],
            "walls": [[[1.0, 2.0], [3.0, 4.0]]],
            "grid": [[4, 5, 2], [1, 1, 3]],
            "allow_contact": false, "board_in": 72.0,
            "opts": {
                "radii": [0.5, 0.75], "clearance": 0.6, "board_y_in": 48.0,
                "zones": [{"c": [30.0, 30.0], "r": 2.5}],
                "avoid_cells": [[2, 2], [1, 1]], "avoid_fine": [], "forbid_cells": [[9, 9]],
                "difficult_cap_in": 6.0
            }
        })
        .to_string()
    }

    /// The synthetic header carries THIS crate's constants — `Constants::check`
    /// is the corpus gate's own guard, so a header that fails it would gate the
    /// seam on different numbers than the corpus.
    #[test]
    fn synthetic_header_passes_the_constant_check() {
        let mut buf = header_line();
        buf.push('\n');
        buf.push_str(&line());
        buf.push('\n');
        let corpus = read_moves(buf.as_bytes(), "<test>").expect("header parses");
        corpus.header.constants.check().expect("constants match");
        assert_eq!(corpus.calls.len(), 1);
    }

    /// Reading a line and printing it back is a fixed point: the second pass
    /// through the reader sees exactly what the first one did. That is what the
    /// round-trip gate leans on when it compares a dictionary to a line.
    #[test]
    fn canonical_input_is_a_fixed_point() {
        let c1 = read_call_line(&line()).expect("call parses");
        let s1 = canonical_input(&c1);
        let c2 = read_call_line(&s1).expect("canonical parses");
        assert_eq!(s1, canonical_input(&c2));
        assert!(s1.contains("\"unit\":\"Alpha\""), "{s1}");
        // Sorted, not insertion order — the corpus wrote [[2,2],[1,1]].
        assert!(s1.contains("\"avoid_cells\":[[1,1],[2,2]]"), "{s1}");
    }

    /// The solver is M4-5's; until then the seam declines and the caller falls
    /// back. A green gate here must not read as "the port planned the move".
    #[test]
    fn the_solver_declines_until_m4_5() {
        let c = read_call_line(&line()).expect("call parses");
        assert_eq!(plan_unit_step_call(&c), Err("M4-5 pending".to_string()));
    }
}
