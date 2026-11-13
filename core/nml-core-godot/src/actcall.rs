//! One-core P3 step 16: `NmlCore.step_activation` - marshalling only. The table's
//! inputs go in as plain dictionaries; `nml_core::activation::step_activation`
//! rules; the answer comes out as a plain dictionary (lines and landings included).
use crate::plain;
use godot::prelude::*;
use nml_core::activation::{allowance, begin_check, check_move, delta_of, step_activation, ActStep, Check, Drop, Input};
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
        "placed" => Input::Placed {
            at: plain::any_array(&field("positions")?).iter_shared().map(|p| p.try_to::<Vector3>().ok().map(|p| [p.x as f64, p.y as f64, p.z as f64])).collect::<Option<Vec<_>>>()?,
            // Optional: per model its walked path (Vector2 = world XZ metres); absent = none.
            trails: match field("trails") {
                None => Vec::new(),
                Some(t) => plain::any_array(&t).iter_shared().map(|m| plain::any_array(&m).iter_shared().map(|p| p.try_to::<Vector2>().ok().map(|p| [p.x as f64, p.y as f64])).collect::<Option<Vec<_>>>()).collect::<Option<Vec<_>>>()?,
            },
        },
        _ => return None,
    })
}

/// The transcript off a Variant array; `Err(i)` = entry `i` is not an input the core knows (a refusal, never a silent drop).
pub fn inputs_of(t: &VarArray) -> Result<Vec<Input>, usize> {
    t.iter_shared().enumerate().map(|(i, v)| input_of(&v).ok_or(i)).collect()
}

pub(crate) fn lines_of(lines: &[LogLine]) -> VarArray {
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
        d.set("loss_line", l.loss_line);
        out.push(&d.to_variant());
    }
    out
}

fn delta_array(before: &State, after: &State) -> VarArray {
    let mut out = VarArray::new();
    for u in delta_of(before, after) {
        let mut removed = VarArray::new();
        for i in &u.removed {
            removed.push(&(*i as i64).to_variant());
        }
        let mut d = VarDictionary::new();
        d.set("unit", u.key.as_str());
        d.set("removed", &removed);
        d.set("shaken", u.shaken);
        d.set("alive", u.alive);
        d.set("moved", u.moved);
        d.set("unknown", u.unknown);
        out.push(&d.to_variant());
    }
    out
}

/// `NmlCore.move_allowance`: the unit's move allowance in inches per mode at its activation start, and the rules
/// that widen it. Empty for a unit the roster does not know.
pub fn allowance_of(statics: &[UnitStatic], state: &State, unit: &str, terrain: &Terrain, seams: Seams) -> VarDictionary {
    let mut d = VarDictionary::new();
    let Some(&si) = state.roster.index.get(unit) else { return d };
    let a = allowance(statics, state, si, seams, terrain);
    let mut by = VarArray::new();
    for n in &a.widened_by {
        by.push(&n.as_str().to_variant());
    }
    d.set("advance", a.advance);
    d.set("rush", a.rush);
    d.set("charge", a.charge);
    d.set("widened_by", &by);
    d
}

/// `{"ok": false, "reason"}`: a refusal that is not the core's own (unknown handle or unit, a drop that is not understood).
pub fn not_ok(reason: &str) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("ok", false);
    d.set("reason", reason);
    d
}

/// A drop off the table's dictionary: `mode` (int), `positions` (Vector3 per model) and `trails` (per model its path as Vector2,
/// x = world X, y = world Z, metres; absent or an empty entry = no trail).
fn drop_of(d: &VarDictionary) -> Result<Drop, &'static str> {
    let list = |k: &str| d.get(k).map(|v| plain::any_array(&v)).unwrap_or_default();
    let placed = list("positions").iter_shared().map(|p| p.try_to::<Vector3>().ok().map(|p| [p.x as f64, p.y as f64, p.z as f64])).collect::<Option<Vec<_>>>();
    let trail = |t: Variant| plain::any_array(&t).iter_shared().map(|p| p.try_to::<Vector2>().ok().map(|p| [p.x as f64, p.y as f64])).collect::<Option<Vec<_>>>();
    let trails = list("trails").iter_shared().map(trail).collect::<Option<Vec<_>>>();
    match (placed, trails) {
        (Some(placed), Some(trails)) => Ok(Drop { mode: d.get("mode").map_or(0, |m| plain::int(&m)), placed, trails }),
        (None, _) => Err("positions are not all Vector3"),
        _ => Err("trails are not all Vector2"),
    }
}

/// `NmlCore.check_move`: `{"ok": true, "lines"}` or `{"ok": false, "reason"}` for one drop of `unit` (its start is `state`).
pub fn check_of(statics: &[UnitStatic], state: &State, unit: &str, terrain: &Terrain, seams: Seams, drop: &VarDictionary, enforce: bool) -> VarDictionary {
    let Some(&si) = state.roster.index.get(unit) else { return not_ok("unknown unit") };
    let drop = match drop_of(drop) {
        Ok(d) => d,
        Err(why) => return not_ok(why),
    };
    match check_move(statics, state, si, seams, terrain, &drop, enforce) {
        Check::Ok { lines } => {
            let mut d = VarDictionary::new();
            d.set("ok", true);
            d.set("lines", &lines_of(&lines));
            d
        }
        Check::Refused { reason } => not_ok(&reason),
    }
}

/// `NmlCore.check_begin`: `{"ok": true}`, or `{"ok": false, "reason"}` while another unit's activation is open (`open_name` != "").
pub fn begin_of(open_name: &str) -> VarDictionary {
    match begin_check((!open_name.is_empty()).then_some(open_name)) {
        Ok(()) => {
            let mut d = VarDictionary::new();
            d.set("ok", true);
            d
        }
        Err(reason) => not_ok(&reason),
    }
}

/// One step. `Some(state)` only on `done`. `refused` carries the input's index and the sentence.
pub fn run(statics: &[UnitStatic], state: &State, unit: &str, terrain: &Terrain, seams: Seams, t: &[Input], enforce: bool) -> (VarDictionary, Option<State>) {
    let mut out = VarDictionary::new();
    let mut next = None;
    match step_activation(statics, state, unit, terrain, seams, t, enforce) {
        ActStep::NeedRoll { index, faces, kind, count, target, owner, owner_key, lines, landings } => {
            out.set("step", "need_roll");
            out.set("index", index as i64);
            out.set("faces", faces as i64);
            out.set("kind", kind);
            out.set("count", count);
            out.set("target", target);
            out.set("owner", owner.as_str());
            out.set("owner_key", owner_key.as_str());
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
            out.set("delta", &delta_array(state, &s));
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
