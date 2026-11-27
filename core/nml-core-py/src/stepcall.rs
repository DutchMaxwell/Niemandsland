//! One-core P4.0-11: `Core.step_activation` — marshalling only, the Python twin of the Godot seam's
//! `actcall::run`. The table's ordered inputs go in as plain Python lists/dicts; the core's
//! `activation::step_activation` rules; the answer comes out as a plain dict (lines and landings included).
//! The seams are the Godot binding's `seams_for_step`; positions cross the seam through f32, as a Godot
//! `Vector3` does, so the same transcript gives the same answer on both seams.
use nmlcore::activation::{delta_of, step_activation, ActStep, CastInput, ConsolidatePlan, Input};
use nmlcore::acts::Knobs;
use nmlcore::io::Seams;
use nmlcore::landing::Landing;
use nmlcore::logline::LogLine;
use nmlcore::mv::legal;
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

/// A cast's text list (`targets`, `conduit_shaken`): absent or null = none; any other shape is not understood.
fn texts_of(v: Option<&Value>) -> Option<Vec<String>> {
    match v {
        None | Some(Value::Null) => Some(Vec::new()),
        Some(Value::Array(a)) => a.iter().map(|s| s.as_str().map(str::to_string)).collect(),
        Some(_) => None,
    }
}

/// A cast's payers, `[[unit key, tokens]..]` in spend order: absent or null = none; any other shape is not understood.
fn payers_of(v: Option<&Value>) -> Option<Vec<(String, i64)>> {
    match v {
        None | Some(Value::Null) => Some(Vec::new()),
        Some(Value::Array(a)) => a.iter().map(|p| match p.as_array()?.as_slice() { [k, n] => Some((k.as_str()?.to_string(), int(n)?)), _ => None }).collect(),
        Some(_) => None,
    }
}

/// A cast's interference pools as `CastInput` holds them: per foe slot its payers.
type Pools = Vec<(i64, Vec<(String, i64)>)>;

/// A cast's interference pools, `[[foe slot, payers]..]`: absent or null = none; any other shape is not understood.
fn pools_of(v: Option<&Value>) -> Option<Pools> {
    match v {
        None | Some(Value::Null) => Some(Vec::new()),
        Some(Value::Array(a)) => a.iter().map(|p| match p.as_array()?.as_slice() { [slot, list] => Some((int(slot)?, payers_of(Some(list))?)), _ => None }).collect(),
        Some(_) => None,
    }
}

/// CC-4: `{"t": "cast", ..}`, one planned cast. `seq`, `caster`, `spell`, `targets`, `base` and `threshold` are required; the
/// token and conduit lists, `once` and `open` default to none / false when absent. A present field of the wrong shape is not
/// understood (a refusal, never a default in disguise). The Godot seam's `cast_of` reads the same fields.
fn cast_of(o: &serde_json::Map<String, Value>) -> Option<CastInput> {
    let (num, text, flag) = (|k: &str| o.get(k).map_or(Some(0), int), |k: &str| o.get(k).map_or(Some(String::new()), |v| v.as_str().map(str::to_string)), |k: &str| o.get(k).map_or(Some(false), Value::as_bool));
    Some(CastInput {
        seq: int(o.get("seq")?)?,
        caster: o.get("caster")?.as_str()?.to_string(),
        spell: o.get("spell")?.as_str()?.to_string(),
        targets: texts_of(Some(o.get("targets")?))?,
        base: int(o.get("base")?)?,
        threshold: int(o.get("threshold")?)?,
        boost: num("boost")?,
        boost_sources: payers_of(o.get("boost_sources"))?,
        interference: num("interference")?,
        interference_sources: payers_of(o.get("interference_sources"))?,
        conduit: text("conduit")?,
        conduit_shaken: texts_of(o.get("conduit_shaken"))?,
        pools: pools_of(o.get("pools"))?,
        once: flag("once")?,
        open: flag("open")?,
    })
}

/// meleefix: the Godot seam's `consolidate` entry, field for field (`unit` required); also the record's `consolidate` line plans.
pub(crate) fn consolidate_of(o: &serde_json::Map<String, Value>) -> Option<ConsolidatePlan> {
    Some(ConsolidatePlan {
        unit: o.get("unit")?.as_str()?.to_string(),
        planner: o.get("planner").and_then(Value::as_bool).unwrap_or(false),
        task: o.get("task").and_then(Value::as_str).unwrap_or("").to_string(),
        marker: o.get("marker").and_then(int).unwrap_or(-1),
        lane: o.get("lane").and_then(Value::as_bool).unwrap_or(false),
        spread: o.get("spread").and_then(Value::as_bool).unwrap_or(false),
        runners: o.get("runners").and_then(Value::as_array).map_or(Some(Vec::new()), |a| a.iter().map(int).collect())?,
    })
}

fn input_of(v: &Value) -> Option<Input> {
    let o = v.as_object()?;
    Some(match o.get("t")?.as_str()? {
        "begin" => Input::Begin,
        "cancel" => Input::Cancel,
        "intent" => Input::Intent { kind: int(o.get("kind")?)?, shoot: o.get("shoot").and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string), split: None, charge: o.get("charge").and_then(Value::as_str).filter(|s| !s.is_empty()).map(str::to_string), no_step: o.get("no_step").and_then(Value::as_bool).unwrap_or(false) },
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
        "cast" => Input::Cast(cast_of(o)?),
        // meleefix: the Godot seam's `consolidate` entry, field for field; `unit` is required.
        "consolidate" => Input::Consolidate(consolidate_of(o)?),
        // D-PAR3 14a: the Godot seam's `paid` entry; each flag absent = false.
        "paid" => {
            let on = |k: &str| o.get(k).and_then(Value::as_bool).unwrap_or(false);
            Input::Paid { start: on("start"), dangerous: on("dangerous"), beats: on("beats") }
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
        json!({"unit": state.roster.keys[l.unit], "models": models, "loss_line": l.loss_line, "moved_to": l.moved_to})
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
        // P4.0-5 / CC-9a: the same answer shape as the Godot seam's `need_choice`, with lines and landings before the choice.
        ActStep::NeedChoice { id, options, owner, lines, landings } => json!({
            "step": "need_choice", "id": id, "options": options, "owner": owner,
            "lines": lines_of(&lines), "landings": landings_of(state, &landings),
        }),
        ActStep::Refused { index, reason } => refused(index, &reason),
        ActStep::Cancelled { lines } => json!({"step": "cancelled", "lines": lines_of(&lines)}),
        ActStep::Done { state: s, lines, landings, .. } => {
            let answer = json!({"step": "done", "lines": lines_of(&lines), "landings": landings_of(state, &landings), "delta": delta_array(state, &s),
                "illegal": legal::illegal_json(&s, &legal::landing_illegal(state, &s, terrain))});
            next = Some(s);
            answer
        }
    };
    (out, next)
}

/// `Core.check_rest`'s body: `{"ok", "illegal"}` over the named unit keys, the Godot binding's shape.
pub(crate) fn rest(core: &Core, py: Python<'_>, state: &PyState, unit_ids: &[String]) -> PyResult<Py<PyAny>> {
    let units = unit_ids.iter().map(|k| state.inner.roster.index.get(k).copied()
        .ok_or_else(|| Unsupported::new_err(format!("unknown unit {k}")))).collect::<PyResult<Vec<usize>>>()?;
    let found = legal::rest_illegal(&state.inner, &core.terrain, &units);
    to_py(py, &json!({"ok": found.is_empty(), "illegal": legal::illegal_json(&state.inner, &found)}))
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

    /// A cast input with every field set to a non-default value.
    fn full_cast() -> Value {
        json!({
            "t": "cast", "seq": 2, "caster": "u1", "spell": "Fireball", "targets": ["e1", "e2"], "base": 4, "threshold": 3,
            "boost": 1, "boost_sources": [["u1", 1]], "interference": 2, "interference_sources": [["f1", 1], ["f2", 1]],
            "conduit": "u3", "conduit_shaken": ["u4"], "pools": [[1, [["f1", 2], ["f2", 1]]], [0, []]], "once": true, "open": true,
        })
    }

    /// CC-4: every field of the cast input reaches the core, in its order. RED: one field not read in `cast_of` -> it
    /// parses as its default and this equality fails.
    #[test]
    fn a_cast_input_keeps_every_field() {
        let pay = |k: &str, n: i64| (k.to_string(), n);
        let want = CastInput {
            seq: 2, caster: "u1".into(), spell: "Fireball".into(), targets: vec!["e1".into(), "e2".into()], base: 4, threshold: 3,
            boost: 1, boost_sources: vec![pay("u1", 1)], interference: 2, interference_sources: vec![pay("f1", 1), pay("f2", 1)],
            conduit: "u3".into(), conduit_shaken: vec!["u4".into()], pools: vec![(1, vec![pay("f1", 2), pay("f2", 1)]), (0, vec![])], once: true, open: true,
        };
        assert_eq!(input_of(&full_cast()), Some(Input::Cast(want)));
    }

    /// The optional fields default when absent or null; the required ones do not, and a present field of the wrong shape is
    /// not understood.
    #[test]
    fn a_cast_input_defaults_what_is_optional_and_refuses_what_is_malformed() {
        let min = json!({"t": "cast", "seq": 0, "caster": "u1", "spell": "Bolt", "targets": ["e1"], "base": 4, "threshold": 1});
        let want = CastInput { seq: 0, caster: "u1".into(), spell: "Bolt".into(), targets: vec!["e1".into()], base: 4, threshold: 1, ..Default::default() };
        assert_eq!(input_of(&min), Some(Input::Cast(want.clone())));
        let mut nulled = min.clone();
        for k in ["boost_sources", "interference_sources", "pools", "conduit_shaken"] {
            nulled[k] = Value::Null;
        }
        assert_eq!(input_of(&nulled), Some(Input::Cast(want)), "null = absent for the lists");
        for k in ["seq", "caster", "spell", "targets", "base", "threshold"] {
            let mut gone = full_cast();
            gone.as_object_mut().unwrap().remove(k);
            assert!(input_of(&gone).is_none(), "{k} is required");
        }
        for (k, odd) in [("targets", json!("e1")), ("targets", json!([1])), ("boost_sources", json!([["u1"]])), ("boost_sources", json!([["u1", "x"]])), ("interference_sources", json!({"u1": 1})), ("pools", json!([[1]])), ("pools", json!([[1, [["f1"]]]])), ("conduit", json!(3)), ("once", json!("yes")), ("open", json!(1)), ("seq", json!("0")), ("boost", json!([1]))] {
            let mut bad = full_cast();
            bad[k] = odd.clone();
            assert!(input_of(&bad).is_none(), "{k} = {odd}");
        }
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

    /// CC-9a/9c: `stepcall::run` serializes `lines` and `landings` onto `need_choice` answers (matching `actcall::run`),
    /// both empty (Takedown) and populated (cast interference lines before the choice).
    #[test]
    fn need_choice_carries_lines_and_landings_arrays() {
        let header = nmlcore::read_act_header(
            r#"{"kind":"header","knobs":{},"profiles":{"a":{"unit_id":"a","name":"Mystic","quality":4,"defense":4,"tough":1,"wounds_max":[1],"model_count":1,"caster_value":2,"base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[]},"b":{"unit_id":"b","name":"Foe","quality":4,"defense":4,"tough":1,"wounds_max":[3,3],"model_count":2,"caster_value":0,"base_radius":0.016,"game_system":"gf","faction_folder":"robot_legions","special_rules":[],"item_grants":[],"attached_hero_rules":[],"move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#,
        )
        .expect("header");
        let mut cache = nmlcore::state::ProfileCache::new(header.profiles);
        let mut roster = None;
        let st = nmlcore::io::state_from_json(
            r#"{"round":1,"rounds_total":4,"scoring":"end","units":{"a":{"player":1,"alive":1,"wounds":[1],"radii":[0.016],"positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,"activated":false,"casts":4,"morale_bonus":0,"aircraft":false,"dormant":false,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":1.0,"mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}},"b":{"player":2,"alive":2,"wounds":[3,3],"radii":[0.016,0.016],"positions":[[0.2,0.0,0.0],[0.25,0.0,0.0]],"in_cover":false,"shaken":false,"fatigued":false,"activated":false,"casts":2,"morale_bonus":0,"aircraft":false,"dormant":false,"ambush_arrived_round":-1,"earliest_arrival_round":-1,"wound_frac":1.0,"mods":{},"mods_base":{},"bands":{"advance":6.0,"rush":12.0}}}}"#,
            &mut cache,
            &mut roster,
        )
        .expect("state");
        let mut caster = UnitStatic { name: "Mystic".into(), is_caster: true, ..Default::default() };
        caster.spells.push(nmlcore::rules::Spell { name: "Bolt".into(), effect_kind: "damage".into(), threshold: 1, target_count: 1, ..Default::default() });
        let statics = vec![caster, UnitStatic { name: "Foe".into(), ..Default::default() }];
        let cast = CastInput { seq: 0, caster: "a".into(), spell: "Bolt".into(), targets: vec!["b".into()], base: 4, threshold: 1, open: true, pools: vec![(2, vec![("b".into(), 2)])], ..Default::default() };
        let t = [
            Input::Begin,
            Input::Intent { kind: 0, shoot: None, split: None, charge: None, no_step: false },
            Input::Cast(cast),
            Input::Choice { id: "interference:0:a:2".into(), option: String::new() },
        ];
        let (ans, next) = run(&statics, &st, "a", &Terrain::default(), Seams::default(), &t, false);
        assert!(next.is_none());
        assert_eq!(ans["step"], "need_choice");
        assert_eq!(ans["id"], "interference:0:a:2");
        assert_eq!(ans["options"], json!(["0", "1", "2"]));
        assert_eq!(ans["owner"], "b");
        assert_eq!(ans["landings"], json!([]));
        let texts: Vec<&str> = ans["lines"].as_array().unwrap().iter().map(|l| l["text"].as_str().unwrap()).collect();
        assert_eq!(texts, ["Mystic casts Bolt at Foe", "Mystic casts Bolt at Foe \u{2014} needs 4+ (1 token)"]);
    }
}
