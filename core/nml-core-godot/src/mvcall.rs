//! NML-1073 M4-6a — the MOVE seam's marshalling: one live `plan_unit_step`
//! input dictionary into the JSON line `scripts/solo/move_recorder.gd` writes.
//!
//! This file is `MoveRecorder.begin`'s return literal (move_recorder.gd:79-86)
//! plus `_flatten`/`_flatten_opts`/`_cell_list`/`_grid_list` (:150-200), in
//! Rust. The seam hands the port the SAME dictionary object the recorder
//! receives, so there is exactly one description of what a call is; the JSON is
//! then parsed by `mv::entry::read_call_line`, which is `io::read_moves` — the
//! corpus gate's own reader.
//!
//! ACCEPTS BOTH SHAPES. Live, a position is a `Vector2` and the terrain grid is
//! a `Vector2i`-keyed `Dictionary`; rebuilt from a recorded line by
//! `JSON.parse_string`, the same fields are already `[x, y]` arrays and row
//! lists. Every reader below takes either, which is what lets the round-trip
//! gate (tools/move_seam_roundtrip.gd) send a corpus line back through the live
//! door.
//!
//! TYPED ARRAYS. Every array is read through `plain::any_array` — gdext's
//! `try_to::<VarArray>()` refuses a typed `Array[Vector2]` or a
//! `PackedVector2Array` and answers EMPTY, which is how M2-5 silently lost 56
//! unit rules. The move call carries `Array[Vector2]`-shaped data everywhere,
//! so that path is not optional here.

use godot::prelude::*;
use serde_json::{Map, Value};

use crate::plain;
use crate::plain::{any_array, flag, int, num, text};

/// `MoveRecorder._flatten` — move_recorder.gd:184. `Vector2`/`Vector2i` become
/// `[x, y]`, arrays and dictionaries recurse, everything else is its JSON self.
/// A value no JSON can carry (a `Callable`, an `Object`) becomes `null`.
pub fn flat(v: &Variant) -> Value {
    match v.get_type() {
        VariantType::NIL => Value::Null,
        VariantType::BOOL => Value::Bool(flag(v)),
        VariantType::INT => Value::from(int(v)),
        VariantType::FLOAT => Value::from(num(v)),
        VariantType::STRING => Value::String(text(v)),
        VariantType::STRING_NAME => {
            Value::String(v.try_to::<StringName>().map(|s| s.to_string()).unwrap_or_default())
        }
        VariantType::VECTOR2 => {
            let p = v.try_to::<Vector2>().unwrap_or_default();
            Value::Array(vec![Value::from(p.x as f64), Value::from(p.y as f64)])
        }
        VariantType::VECTOR2I => {
            let p = v.try_to::<Vector2i>().unwrap_or_default();
            Value::Array(vec![Value::from(p.x as i64), Value::from(p.y as i64)])
        }
        VariantType::DICTIONARY => {
            let d = v.try_to::<VarDictionary>().unwrap_or_default();
            let mut m = Map::new();
            for (k, val) in d.iter_shared() {
                m.insert(text(&k), flat(&val));
            }
            Value::Object(m)
        }
        VariantType::ARRAY
        | VariantType::PACKED_BYTE_ARRAY
        | VariantType::PACKED_INT32_ARRAY
        | VariantType::PACKED_INT64_ARRAY
        | VariantType::PACKED_FLOAT32_ARRAY
        | VariantType::PACKED_FLOAT64_ARRAY
        | VariantType::PACKED_STRING_ARRAY
        | VariantType::PACKED_VECTOR2_ARRAY
        | VariantType::PACKED_VECTOR3_ARRAY
        | VariantType::PACKED_COLOR_ARRAY => {
            Value::Array(any_array(v).iter_shared().map(|e| flat(&e)).collect())
        }
        _ => Value::Null,
    }
}

/// `MoveRecorder._grid_list` (:177) and `_cell_list` (:169): a `Vector2i`-keyed
/// dictionary flattened to `[[cx, cy, type], …]` / `[[cx, cy], …]`, because a
/// `Vector2i` cannot be a JSON key.
///
/// A value that is ALREADY a row list — the round-trip gate's re-parsed corpus
/// line — is re-read as INTEGERS rather than passed through: `JSON.parse_string`
/// widens every JSON number to a Godot float, so `[[0, 8, 4]]` comes back as
/// `[[0.0, 8.0, 4.0]]` and `io::read_moves` (which wants `[i64; 3]`) would
/// refuse it. Cells are integers in both worlds; this is that fact, written down.
fn cell_rows(v: &Variant, with_value: bool) -> Value {
    let n = if with_value { 3 } else { 2 };
    if let Ok(d) = v.try_to::<VarDictionary>() {
        let mut out = Vec::with_capacity(d.len());
        for (k, val) in d.iter_shared() {
            let c = k.try_to::<Vector2i>().unwrap_or_default();
            let mut row = vec![Value::from(c.x as i64), Value::from(c.y as i64)];
            if with_value {
                row.push(Value::from(int(&val)));
            }
            out.push(Value::Array(row));
        }
        return Value::Array(out);
    }
    let a = any_array(v);
    let mut out = Vec::with_capacity(a.len());
    for e in a.iter_shared() {
        let r = any_array(&e);
        let mut row = Vec::with_capacity(n);
        for i in 0..n {
            row.push(Value::from(if i < r.len() { int(&r.at(i)) } else { 0 }));
        }
        out.push(Value::Array(row));
    }
    Value::Array(out)
}

/// `MoveRecorder._flatten_opts` — move_recorder.gd:150. Verbatim, EXCEPT the
/// three `Vector2i`-keyed sets (which become row lists) and `flow_order`, which
/// is an OUTPUT `plan_unit_step` writes back into this same dictionary and is
/// therefore never an input.
fn opts_json(d: &VarDictionary) -> Value {
    let mut m = Map::new();
    for (k, v) in d.iter_shared() {
        let key = text(&k);
        match key.as_str() {
            "flow_order" => continue,
            "avoid_cells" | "avoid_fine" | "forbid_cells" => {
                m.insert(key, cell_rows(&v, false));
            }
            _ => {
                m.insert(key, flat(&v));
            }
        }
    }
    Value::Object(m)
}

/// `MoveRecorder.begin`'s `{"kind": "call", …}` line — move_recorder.gd:79-86.
///
/// Built key by key rather than by walking the dictionary, so the shape is the
/// recorder's literal and not "whatever the caller happened to put in": the
/// live `ctx` also carries `terrain_cb` (a `Callable`, header-only) and that
/// must not leak into a call line.
pub fn call_json(d: &VarDictionary) -> Value {
    let get = |k: &str| d.get(k).unwrap_or_else(Variant::nil);
    // `walls` is either the wall list itself or the string "header" — the
    // recorder's back-reference to line 1 (move_recorder.gd:84).
    let walls_v = get("walls");
    let walls = if walls_v.get_type() == VariantType::STRING {
        Value::String(text(&walls_v))
    } else {
        flat(&walls_v)
    };
    let mut m = Map::new();
    m.insert("kind".into(), Value::String("call".into()));
    m.insert("unit".into(), Value::String(text(&get("unit"))));
    m.insert("act".into(), Value::from(int(&get("act"))));
    m.insert("round".into(), Value::from(int(&get("round"))));
    m.insert("rung".into(), Value::String(text(&get("rung"))));
    m.insert("model_pos".into(), flat(&get("model_pos")));
    m.insert("delta".into(), flat(&get("delta")));
    m.insert("walls".into(), walls);
    m.insert("grid".into(), cell_rows(&get("grid"), true));
    m.insert("allow_contact".into(), Value::Bool(flag(&get("allow_contact"))));
    m.insert("board_in".into(), Value::from(num(&get("board_in"))));
    m.insert("opts".into(), opts_json(&plain::sub_dict(d, "opts")));
    Value::Object(m)
}

/// The marshalled call as the one JSON line `mv::entry::read_call_line` reads.
pub fn call_line(d: &VarDictionary) -> String {
    call_json(d).to_string()
}

/// `[x, y]` back as a Godot `Vector2` — the planner's own frame is f32, so this
/// is the exact inverse of `flat`.
fn v2_out(p: [f32; 2]) -> Vector2 {
    Vector2::new(p[0], p[1])
}

/// `mv::entry::Planned` as the three values the caller assigns:
/// `planned` (the return), `trails` (`plan_trails`) and `flow_order`
/// (`opts["flow_order"]`) — solo_controller.gd:6070-6080.
pub fn planned_out(p: &nml_core::mv::entry::Planned) -> VarDictionary {
    let mut out = VarDictionary::new();
    out.set("ok", true);
    let mut planned = VarArray::new();
    for q in &p.planned {
        planned.push(&v2_out(*q).to_variant());
    }
    out.set("planned", &planned);
    let mut trails = VarArray::new();
    for t in &p.trails {
        let mut leg = VarArray::new();
        for q in t {
            leg.push(&v2_out(*q).to_variant());
        }
        trails.push(&leg.to_variant());
    }
    out.set("trails", &trails);
    let mut order = VarArray::new();
    for i in &p.flow_order {
        order.push(&i.to_variant());
    }
    out.set("flow_order", &order);
    out
}

// ------------------------------------------- the live shape, for the gate ---

fn v2_array(v: &[[f32; 2]]) -> VarArray {
    let mut a = VarArray::new();
    for p in v {
        a.push(&v2_out(*p).to_variant());
    }
    a
}

fn cell_dict(s: &nml_core::mv::CellSet) -> VarDictionary {
    let mut d = VarDictionary::new();
    for &(x, y) in s {
        d.set(Vector2i::new(x, y), true);
    }
    d
}

fn opts_dict(o: &nml_core::mv::CallOpts) -> VarDictionary {
    let mut d = VarDictionary::new();
    let mut radii = VarArray::new();
    for r in &o.radii {
        radii.push(&r.to_variant());
    }
    d.set("radii", &radii);
    d.set("clearance", o.clearance);
    let mut zones = VarArray::new();
    for z in &o.zones {
        let mut zd = VarDictionary::new();
        zd.set("c", v2_out(z.c));
        zd.set("r", z.r);
        zones.push(&zd.to_variant());
    }
    d.set("zones", &zones);
    d.set("avoid_cells", &cell_dict(&o.avoid_cells));
    d.set("avoid_fine", &cell_dict(&o.avoid_fine));
    d.set("forbid_cells", &cell_dict(&o.forbid_cells));
    d.set("board_y_in", o.board_y_in);
    // The optional keys are set only where the controller sets them
    // (solo_controller.gd:5986-6040) — key PRESENCE is part of the shape.
    if let Some(v) = o.difficult_cap_in {
        d.set("difficult_cap_in", v);
    }
    if o.zones_rest_only {
        d.set("zones_rest_only", true);
    }
    if let Some(v) = o.charge_allowance {
        d.set("charge_allowance", v);
    }
    if let Some(p) = o.charge_goal {
        d.set("charge_goal", v2_out(p));
    }
    if !o.charge_tgt_bases.is_empty() {
        let mut a = VarArray::new();
        for (p, r) in &o.charge_tgt_bases {
            let mut e = VarArray::new();
            e.push(&v2_out(*p).to_variant());
            e.push(&r.to_variant());
            a.push(&e.to_variant());
        }
        d.set("charge_tgt_bases", &a);
    }
    if !o.charge_slots.is_empty() {
        d.set("charge_slots", &v2_array(&o.charge_slots));
    }
    d
}

/// A parsed call back in the LIVE dictionary shape — the one
/// `SoloController._plan_positions` builds (solo_controller.gd:6062-6069):
/// `Vector2` positions, a `Vector2i`-keyed terrain grid and `Vector2i`-keyed
/// cell sets, nested option dictionaries.
///
/// GATE B leans on this. `JSON.parse_string` can only ever hand the seam plain
/// arrays and float-widened cells — never a `Vector2` and never a `Vector2i`
/// KEY, which is exactly the marshalling that has to be proven — and Godot's own
/// `String::to_double` is 1 ULP off on some 17-digit literals, so a corpus line
/// re-parsed in GDScript is not even the number that was recorded. Rebuilding
/// the dictionary HERE removes both, and what is left in the comparison is the
/// Variant boundary itself.
pub fn call_dict(c: &nml_core::mv::MoveCall) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("unit", &GString::from(c.unit.as_str()));
    d.set("act", c.act);
    d.set("round", c.round);
    d.set("rung", &GString::from(c.rung.as_str()));
    d.set("model_pos", &v2_array(&c.model_pos));
    d.set("delta", v2_out(c.delta));
    let mut walls = VarArray::new();
    for w in &c.walls {
        let mut seg = VarArray::new();
        seg.push(&v2_out(w[0]).to_variant());
        seg.push(&v2_out(w[1]).to_variant());
        walls.push(&seg.to_variant());
    }
    d.set("walls", &walls);
    let mut grid = VarDictionary::new();
    for (&(x, y), &t) in &c.grid {
        grid.set(Vector2i::new(x, y), t);
    }
    d.set("grid", &grid);
    d.set("allow_contact", c.allow_contact);
    d.set("board_in", c.board_in);
    d.set("opts", &opts_dict(&c.opts));
    d
}
