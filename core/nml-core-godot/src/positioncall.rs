//! Optional Stage A input on the existing MOVE seam, used only by the parity
//! harness. Marshalling only: the training core's movement executor owns every
//! endpoint. Missing post-move stages are advertised, never filled by GDScript.
use crate::plain;
use godot::prelude::*;
use nml_core::mv::step;
use nml_core::acts::{rule_on, EPOCH_6_TABLE_RULES};
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
    let rules_epoch = input.get("rules_epoch").map(|v| plain::num(&v))
        .unwrap_or(EPOCH_6_TABLE_RULES as f64);
    if !rules_epoch.is_finite() || rules_epoch < 0.0
        || rules_epoch > u32::MAX as f64 || rules_epoch.fract() != 0.0
    {
        return Err("Stage A rules_epoch must be a nonnegative integer".into());
    }
    let rules_epoch = rules_epoch as u32;
    let mut snap_in = None;
    let landing = match action.kind {
        0 => None,
        1 | 2 => Some(
            (step::MoveRules { rules_epoch }).plain_move(
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
            let mut land = (step::MoveRules { rules_epoch })
                .charge_move(state, &terrain, si, *target, band, true, fast, guard)
                .ok_or_else(|| "Stage A charge needs a board and live models".to_string())?;
            snap_in = land.snap_charge(state, *target, rules_epoch);
            Some(land)
        }
        _ => return Err("Stage A action kind must be HOLD/ADVANCE/RUSH/CHARGE".into()),
    };
    let mut out = VarDictionary::new();
    out.set("ok", true);
    out.set("snap_in", &snap_in.map_or(Variant::nil(), |v| v.to_variant()));
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
    if action.kind != 3 || rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
        caps.push(&GString::from("final_placement").to_variant());
        caps.push(&GString::from("base_shapes").to_variant());
        if action.kind == 3 {
            caps.push(&GString::from("charge_final_placement").to_variant());
            caps.push(&GString::from("charge_snap").to_variant());
        }
        // Both arms now measure the acting unit's chain, so the capability is
        // no longer charge-only.
        if rule_on(rules_epoch, EPOCH_6_TABLE_RULES) {
            caps.push(&GString::from("skirmish_chain").to_variant());
        }
        if action.kind != 3 && rule_on(rules_epoch, EPOCH_6_TABLE_RULES)
            && landing.as_ref().is_none_or(|land| land.shorten_covered)
        {
            caps.push(&GString::from("whole_unit_shorten").to_variant());
            caps.push(&GString::from("boxed_escape").to_variant());
        }
    }
    // Non-charge skirmish chains remain a separate port.
    out.set("stage_a_capabilities", &caps);
    Ok(out)
}
