//! Optional Stage A input on the existing MOVE seam, used only by the parity
//! harness. Marshalling only: the training core's movement executor owns every
//! endpoint. Missing post-move stages are advertised, never filled by GDScript.
use crate::plain;
use godot::prelude::*;
use nml_core::mv::step;
use nml_core::terrain::Terrain;
use std::rc::Rc;

pub fn run(input: &VarDictionary, fast: bool, guard: i64) -> Result<VarDictionary, String> {
    let state_input = plain::sub_dict(input, "state");
    let (profiles, roster) = plain::build_roster(&state_input)?;
    let captured = plain::build_state(&state_input, Rc::new(profiles), Rc::new(roster))?;
    let state = &captured.state;
    let action = crate::action_of(&plain::sub_dict(input, "action"));
    let si = *state
        .roster
        .index
        .get(&action.unit)
        .ok_or_else(|| "Stage A action names an unknown unit".to_string())?;
    let band = input
        .get("band_in")
        .map(|v| plain::num(&v))
        .filter(|x| x.is_finite() && *x >= 0.0)
        .ok_or_else(|| "Stage A requires a finite nonnegative band_in".to_string())?;
    let terrain = Terrain::build(&plain::terrain_of(&plain::sub_dict(input, "terrain")));
    let landing = match action.kind {
        0 => None,
        1 | 2 => Some(
            step::plain_move(
                state,
                &terrain,
                si,
                nml_core::geom::to_f32(
                    action
                        .dest
                        .ok_or_else(|| "Stage A move has no destination".to_string())?,
                ),
                band,
                true,
                fast,
                guard,
            )
            .ok_or_else(|| "Stage A movement needs a board and live models".to_string())?,
        ),
        3 => {
            let target = action
                .charge
                .as_ref()
                .and_then(|key| state.roster.index.get(key))
                .ok_or_else(|| "Stage A charge names no live target".to_string())?;
            Some(
                step::charge_move(state, &terrain, si, *target, band, true, fast, guard)
                    .ok_or_else(|| "Stage A charge needs a board and live models".to_string())?,
            )
        }
        _ => return Err("Stage A action kind must be HOLD/ADVANCE/RUSH/CHARGE".into()),
    };
    let mut out = VarDictionary::new();
    out.set("ok", true);
    let mut points = VarArray::new();
    let mut model_ids = VarArray::new();
    if let Some(ref land) = landing {
        for (m, p) in land.movers.iter().zip(&land.end) {
            points.push(&Vector3::new(p[0] as f32, p[1] as f32, p[2] as f32).to_variant());
            model_ids
                .push(&GString::from(&format!("{}:{}", state.key(m.unit), m.model)).to_variant());
        }
        out.set("budget_in", land.budget_in);
        out.set("arc_in", land.arc_in);
    } else {
        for u in std::iter::once(si).chain(state.attached[si].iter().copied()) {
            for (i, p) in state.positions[u].iter().enumerate() {
                points.push(&Vector3::new(p[0] as f32, p[1] as f32, p[2] as f32).to_variant());
                model_ids.push(&GString::from(&format!("{}:{i}", state.key(u))).to_variant());
            }
        }
        out.set("budget_in", 0.0);
        out.set("arc_in", 0.0);
    }
    out.set("position_end", &points);
    out.set("model_ids", &model_ids);
    // Coverage is explicit and versioned with the implementation, not inferred
    // from coordinate equality. A later port adds its capability with its code.
    let mut caps = VarArray::new();
    for name in ["formation", "terrain_cap", "gate_budget", "walls"] {
        caps.push(&GString::from(name).to_variant());
    }
    if action.kind != 3 {
        caps.push(&GString::from("final_placement").to_variant());
        caps.push(&GString::from("base_shapes").to_variant());
    }
    // step::Move::execute still skips shaped final placement on charges;
    // whole-unit shorten, skirmish chains and post-charge snap remain unported.
    out.set("stage_a_capabilities", &caps);
    Ok(out)
}
