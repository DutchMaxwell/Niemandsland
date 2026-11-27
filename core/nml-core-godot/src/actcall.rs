//! One-core P3 step 16: `NmlCore.step_activation` - marshalling only. The table's
//! inputs go in as plain dictionaries; `nml_core::activation::step_activation`
//! rules; the answer comes out as a plain dictionary (lines and landings included).
use crate::plain;
use godot::prelude::*;
use nml_core::activation::{allowance, begin_check, check_move, delta_of, drop_difficult, step_activation, ActStep, CastInput, Check, ConsolidatePlan, Drop, Input};
use nml_core::io::{Seams, SplitShot};
use nml_core::landing::Landing;
use nml_core::logline::LogLine;
use nml_core::mv::legal;
use nml_core::state::State;
use nml_core::terrain::Terrain;
use nml_core::unit::UnitStatic;

/// An intent's optional `split`: an array of `{member, weapon, target}` text entries, absent = none. A value that is not
/// such an array makes the whole input not understood (a refusal, never a silent drop).
fn split_of(v: Option<Variant>) -> Option<Vec<SplitShot>> {
    let Some(v) = v else { return Some(Vec::new()) };
    if v.get_type() != VariantType::ARRAY {
        return None;
    }
    plain::any_array(&v)
        .iter_shared()
        .map(|e| {
            let d = e.try_to::<VarDictionary>().ok()?;
            let text = |k: &str| Some(d.get(k)?.try_to::<GString>().ok()?.to_string());
            Some(SplitShot { member: text("member")?, weapon: text("weapon")?, target: text("target")? })
        })
        .collect()
}

/// A choice's `option`: text as it is, or an array of slots (ints, or `slot:<n>` text) joined as the core reads the owner's
/// ordered wound-allocation answer (`slot:2,slot:2,slot:0`); absent = "" (an ask). Any other shape is not understood: a
/// refusal, never an ask in disguise.
fn option_of(v: Option<Variant>) -> Option<String> {
    let Some(v) = v else { return Some(String::new()) };
    if let Ok(s) = v.try_to::<GString>() {
        return Some(s.to_string());
    }
    if !matches!(v.get_type(), VariantType::ARRAY | VariantType::PACKED_INT32_ARRAY | VariantType::PACKED_INT64_ARRAY | VariantType::PACKED_STRING_ARRAY) {
        return None;
    }
    let slot = |s: Variant| s.try_to::<i64>().map(|n| format!("slot:{n}")).ok().or_else(|| s.try_to::<GString>().ok().map(|t| t.to_string()));
    plain::any_array(&v).iter_shared().map(slot).collect::<Option<Vec<_>>>().map(|s| s.join(","))
}

/// An array's entries; `None` when the value is no array (a refusal, never a silent empty list).
fn list_of(v: &Variant) -> Option<Vec<Variant>> {
    matches!(v.get_type(), VariantType::ARRAY | VariantType::PACKED_STRING_ARRAY).then(|| plain::any_array(v).iter_shared().collect())
}

/// A cast's text list (`targets`, `conduit_shaken`): absent = none, any other shape is not understood.
fn texts_of(v: Option<Variant>) -> Option<Vec<String>> {
    v.map_or(Some(Vec::new()), |v| list_of(&v)?.iter().map(|s| s.try_to::<GString>().ok().map(|s| s.to_string())).collect())
}

/// A cast's payers, `[[unit key, tokens]..]` in spend order: absent = none, any other shape is not understood.
fn payers_of(v: Option<Variant>) -> Option<Vec<(String, i64)>> {
    v.map_or(Some(Vec::new()), |v| list_of(&v)?.iter().map(|p| match list_of(p)?.as_slice() { [k, n] => Some((k.try_to::<GString>().ok()?.to_string(), plain::int(n))), _ => None }).collect())
}

/// A cast's interference pools as `CastInput` holds them: per foe slot its payers.
type Pools = Vec<(i64, Vec<(String, i64)>)>;

/// A cast's interference pools, `[[foe slot, payers]..]`: absent = none, any other shape is not understood.
fn pools_of(v: Option<Variant>) -> Option<Pools> {
    v.map_or(Some(Vec::new()), |v| list_of(&v)?.iter().map(|p| match list_of(p)?.as_slice() { [slot, list] => Some((plain::int(slot), payers_of(Some(list.clone()))?)), _ => None }).collect())
}

/// CC-4: `{"t": "cast", ..}`, one planned cast, read field for field as the Python seam's `cast_of` does: `seq`, `caster`,
/// `spell`, `targets`, `base` and `threshold` are required; the token and conduit lists, `once` and `open` default to none /
/// false when absent. A present field of the wrong shape is not understood (a refusal, never a default in disguise).
fn cast_of(d: &VarDictionary) -> Option<CastInput> {
    let text = |k: &str| d.get(k).map_or(Some(String::new()), |v| v.try_to::<GString>().ok().map(|s| s.to_string()));
    let (num, flag) = (|k: &str| d.get(k).map_or(0, |v| plain::int(&v)), |k: &str| d.get(k).is_some_and(|v| plain::flag(&v)));
    Some(CastInput {
        seq: plain::int(&d.get("seq")?),
        caster: d.get("caster")?.try_to::<GString>().ok()?.to_string(),
        spell: d.get("spell")?.try_to::<GString>().ok()?.to_string(),
        targets: texts_of(Some(d.get("targets")?))?,
        base: plain::int(&d.get("base")?),
        threshold: plain::int(&d.get("threshold")?),
        boost: num("boost"),
        boost_sources: payers_of(d.get("boost_sources"))?,
        interference: num("interference"),
        interference_sources: payers_of(d.get("interference_sources"))?,
        conduit: text("conduit")?,
        conduit_shaken: texts_of(d.get("conduit_shaken"))?,
        pools: pools_of(d.get("pools"))?,
        once: flag("once"),
        open: flag("open"),
    })
}

/// meleefix: `{"t": "consolidate", "unit", "planner", "task", "marker", "lane", "spread", "runners"}`, one melee unit's planner
/// inputs (`SoloController.consolidation_input`); `unit` is required, the rest default to none.
pub(crate) fn consolidate_of(d: &VarDictionary) -> Option<ConsolidatePlan> {
    let flag = |k: &str| d.get(k).is_some_and(|v| plain::flag(&v));
    Some(ConsolidatePlan {
        unit: plain::text(&d.get("unit")?),
        planner: flag("planner"),
        task: d.get("task").map_or(String::new(), |v| plain::text(&v)),
        marker: d.get("marker").map_or(-1, |v| plain::int(&v)),
        lane: flag("lane"),
        spread: flag("spread"),
        runners: d.get("runners").map_or(Vec::new(), |v| plain::any_array(&v).iter_shared().map(|n| plain::int(&n)).collect()),
    })
}

fn input_of(v: &Variant) -> Option<Input> {
    let d = v.try_to::<VarDictionary>().ok()?;
    let field = |k: &str| d.get(k);
    Some(match plain::text(&field("t")?).as_str() {
        "begin" => Input::Begin,
        "cancel" => Input::Cancel,
        "intent" => Input::Intent {
            kind: plain::int(&field("kind")?),
            shoot: field("shoot").map(|s| plain::text(&s)).filter(|s| !s.is_empty()),
            split: Some(split_of(field("split"))?).filter(|l| !l.is_empty()),
            // A CHARGE names its target by roster key (`charge`); absent or "" = none (the core refuses a charge without one).
            charge: field("charge").map(|s| plain::text(&s)).filter(|s| !s.is_empty()),
            // Step 20: `"no_step": true` = no core Hit & Run step (the player drags it); absent = false.
            no_step: field("no_step").is_some_and(|v| plain::flag(&v)),
        },
        "faces" => Input::Faces(plain::any_array(&field("faces")?).iter_shared().map(|f| plain::int(&f).clamp(0, 6) as u8).collect()),
        // P4.0-5: `{"t": "choice", "id": ..., "option": ...}`; an empty/absent `option` asks the core.
        "choice" => Input::Choice { id: plain::text(&field("id")?), option: option_of(field("option"))? },
        "placed" => Input::Placed {
            at: plain::any_array(&field("positions")?).iter_shared().map(|p| p.try_to::<Vector3>().ok().map(|p| [p.x as f64, p.y as f64, p.z as f64])).collect::<Option<Vec<_>>>()?,
            // Optional: per model its walked path (Vector2 = world XZ metres); absent = none.
            trails: match field("trails") {
                None => Vec::new(),
                Some(t) => plain::any_array(&t).iter_shared().map(|m| plain::any_array(&m).iter_shared().map(|p| p.try_to::<Vector2>().ok().map(|p| [p.x as f64, p.y as f64])).collect::<Option<Vec<_>>>()).collect::<Option<Vec<_>>>()?,
            },
        },
        "cast" => Input::Cast(cast_of(&d)?),
        // meleefix: `{"t": "consolidate", "unit", "planner", "task", "marker", "lane", "spread", "runners"}`; `unit` is required.
        "consolidate" => Input::Consolidate(consolidate_of(&d)?),
        // D-PAR3 14a: `{"t": "paid", "start", "dangerous", "beats"}`, each absent = false.
        "paid" => {
            let on = |k: &str| field(k).is_some_and(|v| plain::flag(&v));
            Input::Paid { start: on("start"), dangerous: on("dangerous"), beats: on("beats") }
        }
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
            d.set("slot", m.slot as i64);
            d.set("wounds_left", m.wounds_left);
            d.set("dead", m.dead);
            models.push(&d.to_variant());
        }
        let mut d = VarDictionary::new();
        d.set("unit", state.roster.keys[l.unit].as_str());
        d.set("models", &models);
        d.set("loss_line", l.loss_line);
        let mut moved_to = VarArray::new();   // H-8: a beat's push (Mind Control), landed before later landings
        for p in &l.moved_to {
            moved_to.push(&Vector3::new(p[0] as f32, p[1] as f32, p[2] as f32).to_variant());
        }
        d.set("moved_to", &moved_to);
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
        let mut positions = VarArray::new();
        for p in &u.positions {
            positions.push(&Vector3::new(p[0] as f32, p[1] as f32, p[2] as f32).to_variant());
        }
        d.set("positions", &positions);
        d.set("fatigued", u.fatigued);
        d.set("casts", u.casts);
        let mut stamps = VarDictionary::new();
        for (key, value) in &u.stamps {
            stamps.set(*key, *value);
        }
        d.set("stamps", &stamps.to_variant());
        d.set("versatile_pick_mode", u.versatile_pick_mode);
        let mut pools = VarDictionary::new();
        for (key, value) in &u.pools {
            pools.set(*key, *value);
        }
        d.set("pools", &pools.to_variant());
        let mut feats = VarArray::new();
        for name in &u.feats_used {
            feats.push(&name.as_str().to_variant());
        }
        d.set("feats_used", &feats);
        for (key, names) in [("limited_used", &u.limited_used), ("storm_used", &u.storm_used), ("precision_used", &u.precision_used)] {
            let mut list = VarArray::new();
            for name in names {
                list.push(&name.as_str().to_variant());
            }
            d.set(key, &list);
        }
        d.set("growth_markers", u.growth_markers);
        d.set("piercing_tag_used", u.piercing_tag_used);
        d.set("piercing_tag_persistent", u.piercing_tag_persistent);
        d.set("surprise_attack_used", u.surprise_attack_used);
        let mut spent = VarArray::new();
        for (spell, scope) in &u.buffs_spent {
            spent.push(&varray![spell.as_str(), scope.as_str()].to_variant());
        }
        d.set("buffs_spent", &spent);
        let mut gained = VarArray::new();
        for name in &u.buffs_gained {
            gained.push(&name.as_str().to_variant());
        }
        d.set("buffs_gained", &gained);
        let mut left = VarArray::new();
        for (name, scope, grant) in &u.marks_left {
            left.push(&varray![name.as_str(), scope.as_str(), grant.as_str()].to_variant());
        }
        d.set("marks_left", &left);
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

/// `regroup_around`'s answer: the unit's positions after the core's 1 in placer and its line, or `not_ok` for an unknown
/// unit or model slot.
pub fn regroup_of(state: &State, unit: &str, model_slot: i64, terrain: &Terrain) -> VarDictionary {
    let Some(&u) = state.roster.index.get(unit) else { return not_ok(&format!("unknown unit {unit}")) };
    let Some(m) = usize::try_from(model_slot).ok().filter(|&m| m < state.positions[u].len()) else { return not_ok("unknown model slot") };
    let (pos, line) = nml_core::sim::regroup_around(state, u, m, terrain);
    let mut positions = VarArray::new();
    for p in &pos {
        positions.push(&Vector3::new(p[0] as f32, p[1] as f32, p[2] as f32).to_variant());
    }
    let mut d = VarDictionary::new();
    d.set("ok", true);
    d.set("positions", &positions);
    d.set("line", line.as_str());
    d
}

/// `{"ok": false, "reason"}`: a refusal that is not the core's own (unknown handle or unit, a drop that is not understood).
/// `check_rest`'s answer: `{"ok", "illegal": [..]}` by `legal::rest_illegal` over the named unit keys, or `not_ok` naming an
/// unknown key.
pub fn rest_of(state: &State, terrain: &Terrain, keys: &PackedStringArray) -> VarDictionary {
    let mut units = Vec::new();
    for k in keys.as_slice() {
        let Some(&u) = state.roster.index.get(&k.to_string()) else { return not_ok(&format!("unknown unit {k}")) };
        units.push(u);
    }
    let found = legal::rest_illegal(state, terrain, &units);
    let mut d = VarDictionary::new();
    d.set("ok", found.is_empty());
    d.set("illegal", &plain::variant_of(&legal::illegal_json(state, &found)));
    d
}

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

/// `NmlCore.move_difficult`: `{"ok": true, "difficult": bool}` (does `check_move` hold this drop to the 6" Difficult cap?)
/// or `{"ok": false, "reason"}`. `drop` as `check_move` takes it; its mode is not read.
pub fn difficult_of(statics: &[UnitStatic], state: &State, unit: &str, terrain: &Terrain, drop: &VarDictionary) -> VarDictionary {
    let Some(&si) = state.roster.index.get(unit) else { return not_ok("unknown unit") };
    match drop_of(drop) {
        Ok(d) => {
            let mut out = VarDictionary::new();
            out.set("ok", true);
            out.set("difficult", drop_difficult(statics, state, si, terrain, &d));
            out
        }
        Err(why) => not_ok(why),
    }
}

/// `NmlCore.check_begin`: `{"ok": true}`, or `{"ok": false, "reason", "lines"}` when another
/// unit's activation is open (`open_name` != "") or the loaded game header mixes game systems.
pub fn begin_of(open_name: &str, systems: &[&str]) -> VarDictionary {
    match begin_check((!open_name.is_empty()).then_some(open_name), systems) {
        Ok(()) => {
            let mut d = VarDictionary::new();
            d.set("ok", true);
            d
        }
        Err(refused) => {
            let mut d = not_ok(&refused.reason);
            d.set("lines", &lines_of(&[refused.line]));
            d
        }
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
        ActStep::NeedChoice { id, options, owner, lines, landings } => {
            out.set("step", "need_choice");
            out.set("id", id.as_str());
            let mut all = VarArray::new();
            for o in &options {
                all.push(&o.as_str().to_variant());
            }
            out.set("options", &all);
            out.set("owner", owner.as_str());
            out.set("lines", &lines_of(&lines));
            out.set("landings", &landings_of(state, &landings));
        }
        ActStep::Refused { index, reason } => out = refused(index, &reason),
        ActStep::Cancelled { lines } => {
            out.set("step", "cancelled");
            out.set("lines", &lines_of(&lines));
        }
        ActStep::Done { state: s, lines, landings, unported } => {
            out.set("step", "done");
            out.set("lines", &lines_of(&lines));
            let mut marks = VarArray::new();
            for m in &unported {
                marks.push(&m.to_variant());
            }
            out.set("unported", &marks);
            out.set("landings", &landings_of(state, &landings));
            out.set("delta", &delta_array(state, &s));
            out.set("illegal", &plain::variant_of(&legal::illegal_json(&s, &legal::landing_illegal(state, &s, terrain))));
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
