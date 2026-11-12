//! One-core P3 step 16: `NmlCore.step_activation` - marshalling only. The table's
//! inputs go in as plain dictionaries; `nml_core::activation::step_activation`
//! rules; the answer comes out as a plain dictionary (lines and landings included).
use crate::plain;
use godot::prelude::*;
use nml_core::activation::{step_activation, ActStep, Input};
use nml_core::io::Seams;
use nml_core::landing::Landing;
use nml_core::logline::LogLine;
use nml_core::state::State;
use nml_core::terrain::Terrain;
use nml_core::unit::UnitStatic;

fn input_of(v: &Variant) -> Option<Input> {
    let d = v.try_to::<VarDictionary>().ok()?;
    let field = |k: &str| d.get(k);
    Some(match plain::text(&field("t")?).as_str() {
        "begin" => Input::Begin,
        "cancel" => Input::Cancel,
        "intent" => Input::Intent { kind: plain::int(&field("kind")?), shoot: field("shoot").map(|s| plain::text(&s)).filter(|s| !s.is_empty()) },
        "faces" => Input::Faces(plain::any_array(&field("faces")?).iter_shared().map(|f| plain::int(&f).clamp(0, 6) as u8).collect()),
        "placed" => Input::Placed(plain::any_array(&field("positions")?).iter_shared().map(|p| p.try_to::<Vector3>().ok().map(|p| [p.x as f64, p.y as f64, p.z as f64])).collect::<Option<Vec<_>>>()?),
        _ => return None,
    })
}

/// The transcript off a Variant array; `Err(i)` = entry `i` is not an input the core knows (a refusal, never a silent drop).
pub fn inputs_of(t: &VarArray) -> Result<Vec<Input>, usize> {
    t.iter_shared().enumerate().map(|(i, v)| input_of(&v).ok_or(i)).collect()
}

fn lines_of(lines: &[LogLine]) -> VarArray {
    let mut out = VarArray::new();
    for l in lines {
        let mut d = VarDictionary::new();
        d.set("rule", l.rule);
        d.set("category", l.category as i64);
        d.set("side", l.side);
        d.set("text", l.text.as_str());
        d.set("detail", l.detail.as_deref().unwrap_or(""));
        out.push(&d.to_variant());
    }
    out
}

fn landings_of(state: &State, landings: &[Landing]) -> VarArray {
    let mut out = VarArray::new();
    for l in landings {
        let mut models = VarArray::new();
        for m in &l.models {
            let mut d = VarDictionary::new();
            d.set("at", Vector3::new(m.at[0] as f32, m.at[1] as f32, m.at[2] as f32));
            d.set("wounds_left", m.wounds_left);
            d.set("dead", m.dead);
            models.push(&d.to_variant());
        }
        let mut d = VarDictionary::new();
        d.set("unit", state.roster.keys[l.unit].as_str());
        d.set("models", &models);
        out.push(&d.to_variant());
    }
    out
}

/// One step. `Some(state)` only on `done`. `refused` carries the input's index and the sentence.
pub fn run(statics: &[UnitStatic], state: &State, unit: &str, terrain: &Terrain, seams: Seams, t: &[Input]) -> (VarDictionary, Option<State>) {
    let mut out = VarDictionary::new();
    let mut next = None;
    match step_activation(statics, state, unit, terrain, seams, t) {
        ActStep::NeedRoll { index, faces, kind, count, target, owner, lines, landings } => {
            out.set("step", "need_roll");
            out.set("index", index as i64);
            out.set("faces", faces as i64);
            out.set("kind", kind);
            out.set("count", count);
            out.set("target", target);
            out.set("owner", owner.as_str());
            out.set("lines", &lines_of(&lines));
            out.set("landings", &landings_of(state, &landings));
        }
        ActStep::Open => out.set("step", "open"),
        ActStep::Refused { index, reason } => out = refused(index, &reason),
        ActStep::Cancelled { lines } => {
            out.set("step", "cancelled");
            out.set("lines", &lines_of(&lines));
        }
        ActStep::Done { state: s, lines, landings } => {
            out.set("step", "done");
            out.set("lines", &lines_of(&lines));
            out.set("landings", &landings_of(state, &landings));
            next = Some(s);
        }
    }
    (out, next)
}

/// A refusal that is not the core's: the call itself was wrong (unknown handle, malformed entry).
pub fn refused(index: usize, reason: &str) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("step", "refused");
    d.set("index", index as i64);
    d.set("reason", reason);
    d
}
