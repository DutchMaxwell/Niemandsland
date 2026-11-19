//! One-core P4.0-11: `Core.step_activation` — marshalling only, the Python twin of the Godot seam's
//! `actcall::run`. The table's ordered inputs go in as plain Python lists/dicts; the core's
//! `activation::step_activation` rules; the answer comes out as a plain dict (lines and landings included).
//! The seams are the Godot binding's `seams_for_step`; positions cross the seam through f32, as a Godot
//! `Vector3` does, so the same transcript gives the same answer on both seams.
use nmlcore::activation::{delta_of, step_activation, ActStep, Input};
use nmlcore::acts::Knobs;
use nmlcore::io::Seams;
use nmlcore::landing::Landing;
use nmlcore::logline::LogLine;
use nmlcore::state::State;
use nmlcore::terrain::Terrain;
use nmlcore::unit::UnitStatic;
use pyo3::prelude::*;
use pyo3::types::PyDict;
use serde_json::{json, Value};

use crate::{to_py, value_of, Core, PyState, Unsupported};

/// The table's activation step path: the header epoch's seams with the moving shot ON and the table's sight.
pub fn seams_for_step(knobs: &Knobs) -> Seams {
    let base = nmlcore::plan::seams_of(knobs);
    let base = Seams { path: knobs.seam_path || base.path, ..base };
    Seams { moved_shoot: true, sighting: true, shelf_sight: true, ..base }
}

fn int(v: &Value) -> Option<i64> {
    v.as_i64().or_else(|| v.as_f64().map(|f| f as i64))
}

fn f64_of(v: &Value) -> Option<f64> {
    v.as_f64().or_else(|| v.as_i64().map(|i| i as f64))
}

/// A Godot `Vector3`'s coordinates: the f32 the binding would have carried.
fn coords(v: &Value, n: usize) -> Option<Vec<f64>> {
    let a = v.as_array().filter(|a| a.len() == n)?;
    a.iter().map(|x| f64_of(x).map(|f| f as f32 as f64)).collect()
}

/// A choice's `option`: text as it is, or an array of slots (ints, or `slot:<n>` text) joined as the core reads the owner's
/// ordered wound-allocation answer (`slot:2,slot:2,slot:0`); absent or null = "" (an ask). Any other shape is not understood:
/// a refusal, never an ask in disguise (the Godot seam's `option_of`).
fn option_of(v: Option<&Value>) -> Option<String> {
    match v {
        None | Some(Value::Null) => Some(String::new()),
        Some(Value::String(s)) => Some(s.clone()),
        Some(Value::Array(a)) => a.iter().map(|s| s.as_i64().map(|n| format!("slot:{n}")).or_else(|| s.as_str().map(str::to_string))).collect::<Option<Vec<_>>>().map(|s| s.join(",")),
        Some(_) => None,
    }
}

fn input_of(v: &Value) -> Option<Input> {
    let o = v.as_object()?;
    Some(match o.get("t")?.as_str()? {
        "begin" => Input::Begin,
        "cancel" => Input::Cancel,
        "intent" => Input::Intent { kind: int(o.get("kind")?)?, shoot: o.get("shoot").and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string), split: None, charge: o.get("charge").and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string) },
        "faces" => Input::Faces(o.get("faces")?.as_array()?.iter().map(|f| int(f).map(|n| n.clamp(0, 6) as u8)).collect::<Option<Vec<_>>>()?),
        // P4.0-5: `{"t": "choice", "id": ..., "option": ...}`; an empty/absent `option` asks the core.
        "choice" => Input::Choice { id: o.get("id")?.as_str()?.to_string(), option: option_of(o.get("option"))? },
        "placed" => {
            let at = o.get("positions")?.as_array()?.iter().map(|p| coords(p, 3).map(|c| [c[0], c[1], c[2]])).collect::<Option<Vec<_>>>()?;
            let trails = match o.get("trails") {
                None => Vec::new(),
                Some(t) => t.as_array()?.iter().map(|m| m.as_array()?.iter().map(|p| coords(p, 2).map(|c| [c[0], c[1]])).collect::<Option<Vec<_>>>()).collect::<Option<Vec<_>>>()?,
            };
            Input::Placed { at, trails }
        }
        _ => return None,
    })
}

/// The transcript off a plain Python list; `Err(i)` = entry `i` is not an input the core knows.
pub fn inputs_of(t: &[Value]) -> Result<Vec<Input>, usize> {
    t.iter().enumerate().map(|(i, v)| input_of(v).ok_or(i)).collect()
}

fn lines_of(lines: &[LogLine]) -> Value {
    Value::Array(lines.iter().map(|l| json!({"rule": l.rule, "category": l.category as i64, "side": l.side, "text": l.text, "detail": l.detail.as_deref().unwrap_or("")})).collect())
}

fn landings_of(state: &State, landings: &[Landing]) -> Value {
    Value::Array(landings.iter().map(|l| {
        let models = Value::Array(l.models.iter().map(|m| json!({"at": [m.at[0] as f32 as f64, m.at[1] as f32 as f64, m.at[2] as f32 as f64], "slot": m.slot as i64, "wounds_left": m.wounds_left, "dead": m.dead})).collect());
        json!({"unit": state.roster.keys[l.unit], "models": models, "loss_line": l.loss_line})
    }).collect())
}

fn delta_array(before: &State, after: &State) -> Value {
    Value::Array(delta_of(before, after).into_iter().map(|u| json!({"unit": u.key, "removed": u.removed.iter().map(|&i| i as i64).collect::<Vec<_>>(), "shaken": u.shaken, "alive": u.alive, "moved": u.moved, "unknown": u.unknown, "positions": u.positions, "surprise_attack_used": u.surprise_attack_used})).collect())
}

/// A refusal that is not the core's: the call itself was wrong (a malformed entry).
pub fn refused(index: usize, reason: &str) -> Value {
    json!({"step": "refused", "index": index as i64, "reason": reason})
}

/// One step. `Some(state)` only on `done`.
pub fn run(statics: &[UnitStatic], state: &State, unit: &str, terrain: &Terrain, seams: Seams, t: &[Input], enforce: bool) -> (Value, Option<State>) {
    let mut next = None;
    let out = match step_activation(statics, state, unit, terrain, seams, t, enforce) {
        ActStep::NeedRoll { index, faces, kind, count, target, owner, owner_key, lines, landings } => json!({
            "step": "need_roll", "index": index as i64, "faces": faces as i64, "kind": kind, "count": count,
            "target": target, "owner": owner, "owner_key": owner_key,
            "lines": lines_of(&lines), "landings": landings_of(state, &landings),
        }),
        ActStep::Open => json!({"step": "open"}),
        // P4.0-5: the same answer shape as the Godot seam's `need_choice`.
        ActStep::NeedChoice { id, options, owner } => json!({"step": "need_choice", "id": id, "options": options, "owner": owner}),
        ActStep::Refused { index, reason } => refused(index, &reason),
        ActStep::Cancelled { lines } => json!({"step": "cancelled", "lines": lines_of(&lines)}),
        ActStep::Done { state: s, lines, landings, .. } => {
            let answer = json!({"step": "done", "lines": lines_of(&lines), "landings": landings_of(state, &landings), "delta": delta_array(state, &s)});
            next = Some(s);
            answer
        }
    };
    (out, next)
}

/// `Core.step_activation`'s body: parse, run one step on the table's seams, hand the answer back. On `done`
/// the new state rides `"state"` (the binding's `"handle"`), keeping the caller's `prof` blocks as `copy` does.
pub(crate) fn answer(core: &mut Core, py: Python<'_>, state: &PyState, unit: &str, transcript: &Bound<'_, PyAny>, enforce: bool) -> PyResult<Py<PyAny>> {
    let transcript = value_of(transcript)?;
    let Some(t) = transcript.as_array() else { return Err(Unsupported::new_err("transcript must be a list of input dicts")) };
    let statics = core.statics_for(&state.inner)?;
    let (answer, next) = match inputs_of(t) {
        Err(at) => (refused(at, &format!("input {at} is not understood")), None),
        Ok(inputs) => run(&statics, &state.inner, unit, &core.terrain, seams_for_step(&core.knobs), &inputs, enforce),
    };
    let answer = to_py(py, &answer)?;
    if let Some(next) = next {
        let prof = state.prof.as_ref().map(|v| v.iter().map(|b| b.as_ref().map(|b| b.clone_ref(py))).collect());
        answer.bind(py).cast::<PyDict>()?.set_item("state", Py::new(py, PyState { inner: next, prof })?)?;
    }
    Ok(answer)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn choice(option: Value) -> Option<Input> {
        input_of(&json!({"t": "choice", "id": "wound_alloc:a:b:0", "option": option}))
    }

    /// The owner's wound-allocation answer reaches the core as the slot list it reads, however the caller spells it; any shape
    /// that is no text and no array of slots is refused (`None` = "input not understood"), never read as an ask.
    #[test]
    fn a_choice_option_is_a_slot_list_or_it_is_not_understood() {
        let option = |i: Option<Input>| match i {
            Some(Input::Choice { option, .. }) => Some(option),
            other => panic!("not a choice: {other:?}"),
        };
        assert_eq!(option(choice(json!([1, 1, 0]))).as_deref(), Some("slot:1,slot:1,slot:0"));
        assert_eq!(option(choice(json!(["slot:2", 0]))).as_deref(), Some("slot:2,slot:0"));
        assert_eq!(option(choice(json!("slot:1,slot:0"))).as_deref(), Some("slot:1,slot:0"));
        assert_eq!(option(choice(Value::Null)).as_deref(), Some(""), "null asks");
        assert_eq!(option(input_of(&json!({"t": "choice", "id": "x"}))).as_deref(), Some(""), "absent asks");
        for odd in [json!(3), json!(1.5), json!({"slot": 1}), json!([1.5]), json!(true)] {
            assert!(choice(odd.clone()).is_none(), "{odd}");
        }
    }
}
