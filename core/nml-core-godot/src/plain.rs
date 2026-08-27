//! Marshalling between the Godot `Dictionary` plain form and `nml_core::State`.
//!
//! The plain form is EXACTLY what `BattleSim.state_to_plain` (battle_sim.gd:1255)
//! produces: dynamic per-unit fields verbatim, `positions` as `[x, y, z]` float
//! arrays, one flattened static `profile` per unit, plus the recorded `los_pairs`
//! matrix. The same shape the node corpus carries — the JSONL loader in
//! `nml_core::io` reads it through serde, this module reads it through Variants.
//!
//! Precision: a Godot `Variant` float IS an `f64` (the engine stores doubles in
//! Variants even in single-precision builds), so no value is rounded on the way
//! in or out. `Vector3` never appears in the plain form — `state_to_plain` has
//! already split every position into three floats.

use std::collections::HashMap;
use std::rc::Rc;

use godot::prelude::*;
use godot::builtin::VariantType;

use nml_core::io::los_positions;
use nml_core::state::{Bands, MoveBands, Roster};
use nml_core::terrain::{CellParams, Obb, PlainTerrain};
use nml_core::{Knobs, Marker, Mods, Objective, Profile, ProfileDyn, Profiles, State, Weapon};

/// The dynamic per-unit keys `BattleSim._UNIT_DYNAMIC` (battle_sim.gd:1247-1250)
/// writes, minus the two this port does not model (see `DROPPED`). Bit `i` of a
/// capture mask says "the plain form carried key `i`", so `plain_of` writes back
/// exactly the key set that came in — `state_to_plain` is `if su.has(k)` too.
pub const UNIT_KEYS: [&str; 19] = [
    "alive",
    "wounds",
    "radii",
    "in_cover",
    "shaken",
    "fatigued",
    "activated",
    "casts",
    "mods",
    "mods_base",
    "aircraft",
    "ambush_arrived_round",
    "player",
    "morale_bonus",
    "dormant",
    "earliest_arrival_round",
    "wound_frac",
    // NML-1073 S1: appended, never inserted — a mask bit is a POSITION, so an
    // insert would rename every key above it (battle_sim.gd:1353-1354 appends too).
    "attached",
    "attached_to",
];

/// Keys of `_UNIT_DYNAMIC` the Rust state does not carry. Reported by
/// `NmlCore.dropped_keys()` rather than silently swallowed.
pub const DROPPED: [&str; 2] = ["dormant_models", "dormant_wounds"];

/// The state-level blobs nothing in `resolve`/`score` reads: kept verbatim and
/// handed back by `plain_of` unchanged (`markers_meta` and `destroy_seq` are
/// ALSO parsed into the state, because `score` reads them).
pub const EXTRA_KEYS: [&str; 5] = ["vp", "vp_flavour", "vp_memo", "markers_meta", "destroy_seq"];

// ---------------------------------------------------------------- readers ---

pub fn num(v: &Variant) -> f64 {
    if let Ok(f) = v.try_to::<f64>() {
        return f;
    }
    if let Ok(i) = v.try_to::<i64>() {
        return i as f64;
    }
    if let Ok(b) = v.try_to::<bool>() {
        return if b { 1.0 } else { 0.0 };
    }
    0.0
}

pub fn int(v: &Variant) -> i64 {
    if let Ok(i) = v.try_to::<i64>() {
        return i;
    }
    if let Ok(f) = v.try_to::<f64>() {
        return f as i64;
    }
    if let Ok(b) = v.try_to::<bool>() {
        return b as i64;
    }
    0
}

pub fn flag(v: &Variant) -> bool {
    if let Ok(b) = v.try_to::<bool>() {
        return b;
    }
    if let Ok(i) = v.try_to::<i64>() {
        return i != 0;
    }
    if let Ok(f) = v.try_to::<f64>() {
        return f != 0.0;
    }
    false
}

pub fn text(v: &Variant) -> String {
    v.try_to::<GString>().map(|s| s.to_string()).unwrap_or_default()
}

fn dnum(d: &VarDictionary, k: &str, dflt: f64) -> f64 {
    d.get(k).map(|v| num(&v)).unwrap_or(dflt)
}

fn dint(d: &VarDictionary, k: &str, dflt: i64) -> i64 {
    d.get(k).map(|v| int(&v)).unwrap_or(dflt)
}

fn dflag(d: &VarDictionary, k: &str) -> bool {
    d.get(k).map(|v| flag(&v)).unwrap_or(false)
}

fn dtext(d: &VarDictionary, k: &str) -> String {
    d.get(k).map(|v| text(&v)).unwrap_or_default()
}

/// Reads ANY Godot array as a `VarArray` — untyped `Array`, a TYPED `Array[T]`,
/// or a `Packed*Array`.
///
/// gdext's `try_to::<VarArray>()` is STRICT: an `Array[String]` is not an
/// `Array<Variant>` and the conversion fails, answering an empty array. The
/// JSONL corpus cannot carry that distinction — JSON has one kind of array — so
/// the corpus gate was green while the LIVE seam read
/// `BattleSim._unit_profile`'s `special_rules` (`Array[String]`, game_unit.gd:
/// 245 over opr_api_client.gd:220), every weapon's `rules` and every attached
/// hero's rule list as EMPTY. Measured on a live arena game, NML-1073 M2-5:
/// 56 unit rules, 40 weapon rules and 28 hero rules silently became 0.
/// Every builtin array answers `size()`/`get(i)`, so one reader covers all.
pub fn any_array(v: &Variant) -> VarArray {
    if let Ok(a) = v.try_to::<VarArray>() {
        return a;
    }
    let t = v.get_type();
    let is_array = matches!(
        t,
        VariantType::ARRAY
            | VariantType::PACKED_BYTE_ARRAY
            | VariantType::PACKED_INT32_ARRAY
            | VariantType::PACKED_INT64_ARRAY
            | VariantType::PACKED_FLOAT32_ARRAY
            | VariantType::PACKED_FLOAT64_ARRAY
            | VariantType::PACKED_STRING_ARRAY
            | VariantType::PACKED_VECTOR2_ARRAY
            | VariantType::PACKED_VECTOR3_ARRAY
            | VariantType::PACKED_COLOR_ARRAY
    );
    if !is_array {
        return VarArray::new();
    }
    let n = v.call("size", &[]).try_to::<i64>().unwrap_or(0);
    let mut out = VarArray::new();
    for i in 0..n {
        out.push(&v.call("get", &[i.to_variant()]));
    }
    out
}

fn darr(d: &VarDictionary, k: &str) -> VarArray {
    d.get(k).map(|v| any_array(&v)).unwrap_or_default()
}

/// A sub-dictionary of a plain object — an absent or wrongly typed key answers
/// an EMPTY dictionary, so every reader below sees its own defaults.
pub fn sub_dict(d: &VarDictionary, k: &str) -> VarDictionary {
    ddict(d, k)
}

fn ddict(d: &VarDictionary, k: &str) -> VarDictionary {
    d.get(k)
        .and_then(|v| v.try_to::<VarDictionary>().ok())
        .unwrap_or_default()
}

fn strings(a: &VarArray) -> Vec<String> {
    a.iter_shared().map(|v| text(&v)).collect()
}

fn vec3(v: &Variant) -> [f64; 3] {
    if let Ok(p) = v.try_to::<Vector3>() {
        return [p.x as f64, p.y as f64, p.z as f64];
    }
    let a = any_array(v);
    let mut out = [0.0f64; 3];
    for (i, slot) in out.iter_mut().enumerate() {
        if i < a.len() {
            *slot = num(&a.at(i));
        }
    }
    out
}

fn mods_of(d: &VarDictionary) -> Mods {
    Mods {
        hit: dnum(d, "hit", 0.0),
        def: dnum(d, "def", 0.0),
        morale: dnum(d, "morale", 0.0),
        range_in: dnum(d, "range_in", 0.0),
        advance: dnum(d, "advance", 0.0),
        rush: dnum(d, "rush", 0.0),
    }
}

/// `BattleSim._unit_profile` battle_sim.gd:1304-1330, read off a Variant.
pub fn profile_of(d: &VarDictionary) -> Profile {
    let bands = ddict(d, "move_bands");
    Profile {
        unit_id: dtext(d, "unit_id"),
        name: dtext(d, "name"),
        quality: dint(d, "quality", 0),
        defense: dint(d, "defense", 0),
        tough: dint(d, "tough", 0),
        wounds_max: darr(d, "wounds_max").iter_shared().map(|v| int(&v)).collect(),
        model_count: dint(d, "model_count", 0),
        weapons: darr(d, "weapons")
            .iter_shared()
            .filter_map(|v| v.try_to::<VarDictionary>().ok())
            .map(|w| Weapon {
                name: dtext(&w, "name"),
                range: dnum(&w, "range", 0.0),
                attacks: dint(&w, "attacks", 0),
                count: dint(&w, "count", 0),
                ap: dint(&w, "ap", 0),
                rules: strings(&darr(&w, "rules")),
            })
            .collect(),
        special_rules: strings(&darr(d, "special_rules")),
        caster_value: dint(d, "caster_value", 0),
        base_radius: dnum(d, "base_radius", 0.0),
        game_system: dtext(d, "game_system"),
        faction_folder: dtext(d, "faction_folder"),
        item_grants: strings(&darr(d, "item_grants")),
        attached_hero_rules: darr(d, "attached_hero_rules")
            .iter_shared()
            .map(|v| strings(&any_array(&v)))
            .collect(),
        move_bands: MoveBands {
            advance: dnum(&bands, "advance", 0.0),
            // `_presence` reads `bands.get("rush", 12)` (ai_mission_eval.gd:610).
            rush: dnum(&bands, "rush", 12.0),
        },
    }
}

/// NML-1073 M2-5b — this activation's DYNAMIC profile reading per unit, in the
/// state's own key order (= roster order).
///
/// `AiActRecorder._stamp_gate_reads` (act_recorder.gd) stamps it under the unit
/// key `"prof"`; the live seam calls the very same function before it hands the
/// state over, so the corpus the gate replays and the dictionary the game sends
/// are one shape. A unit without the key keeps the header's deployment reading.
pub fn dyn_profiles(plain: &VarDictionary) -> Vec<Option<ProfileDyn>> {
    let units = ddict(plain, "units");
    units
        .keys_array()
        .iter_shared()
        .map(|k| {
            let u = units.get(&k).and_then(|v| v.try_to::<VarDictionary>().ok())?;
            let d = u.get("prof").and_then(|v| v.try_to::<VarDictionary>().ok())?;
            Some(ProfileDyn {
                special_rules: strings(&darr(&d, "special_rules")),
                tough: dint(&d, "tough", 0),
                caster_value: dint(&d, "caster_value", 0),
                item_grants: strings(&darr(&d, "item_grants")),
                attached_hero_rules: darr(&d, "attached_hero_rules")
                    .iter_shared()
                    .map(|v| strings(&any_array(&v)))
                    .collect(),
            })
        })
        .collect()
}

/// What one `capture_plain` call produced, beyond the state itself.
pub struct Captured {
    pub state: State,
    /// The state-level blobs, verbatim, for `plain_of` to hand back.
    pub extras: VarDictionary,
    /// Per unit, bit `i` = `UNIT_KEYS[i]` was present in the plain form.
    /// `state_to_plain` writes `if su.has(k)` PER UNIT (battle_sim.gd:1262-1264),
    /// so the key set is not uniform across a state and a union mask would
    /// invent keys on the units that never had them.
    pub mask: Vec<u32>,
    /// Any unit carried a `los` row (`BattleSim.sees`).
    pub has_los: bool,
    /// Keys of `DROPPED` seen in the input; empty is the normal case.
    pub dropped: Vec<String>,
}

/// Reads the ordered unit keys of a plain state — Godot dictionaries iterate in
/// INSERTION order, which is the capture order `BattleSim.capture()` wrote.
pub fn unit_keys(plain: &VarDictionary) -> Vec<String> {
    ddict(plain, "units").keys_array().iter_shared().map(|k| text(&k)).collect()
}

/// Builds the immutable profile table + roster for one plain state. Fails when a
/// unit carries no `profile` sub-dictionary (`state_to_plain(state, false)`).
pub fn build_roster(plain: &VarDictionary) -> Result<(Profiles, Roster), String> {
    let units = ddict(plain, "units");
    let mut profiles = Profiles::default();
    let mut roster = Roster::default();
    for k in units.keys_array().iter_shared() {
        let key = text(&k);
        let u = units.get(&k).and_then(|v| v.try_to::<VarDictionary>().ok()).unwrap_or_default();
        let pd = match u.get("profile").and_then(|v| v.try_to::<VarDictionary>().ok()) {
            Some(p) => p,
            None => return Err(format!("unit {key} carries no \"profile\" — capture needs state_to_plain(state, true)")),
        };
        roster.index.insert(key.clone(), roster.keys.len());
        roster.profile.push(profiles.list.len());
        profiles.index.insert(key.clone(), profiles.list.len());
        profiles.list.push(profile_of(&pd));
        roster.keys.push(key);
    }
    Ok((profiles, roster))
}

/// The dynamic layer: everything but the profile table and the roster, which the
/// caller supplies (they are interned across every node of one game).
pub fn build_state(
    plain: &VarDictionary,
    profiles: Rc<Profiles>,
    roster: Rc<Roster>,
) -> Result<Captured, String> {
    let units = ddict(plain, "units");
    let n = roster.keys.len();
    if units.len() != n {
        return Err(format!("roster mismatch: {} units, roster has {n}", units.len()));
    }
    let mut extras = VarDictionary::new();
    for k in EXTRA_KEYS {
        if let Some(v) = plain.get(k) {
            extras.set(k, &v);
        }
    }
    let markers_meta: Vec<Marker> = darr(plain, "markers_meta")
        .iter_shared()
        .filter_map(|v| v.try_to::<VarDictionary>().ok())
        .map(|m| Marker {
            owned_by: dint(&m, "owned_by", 0),
            destructible: dflag(&m, "destructible"),
            destroyed: dflag(&m, "destroyed"),
            // `BattleSim.apply_destroy_step` (:405-423) stamps the destruction
            // ORDER here; `vp_score_round` reads it back.
            destroyed_seq: dint(&m, "destroyed_seq", 0),
        })
        .collect();
    // NML-1073 seam: the matrix is KEY-SORTED (`state_to_plain` sorts it
    // explicitly, battle_sim.gd:1492-1506) while `roster` above is the live
    // dictionary's INSERTION order, i.e. capture order. Same two orders
    // `io::state_of` tells apart, same helper — under eleven units a side the
    // mapping is the identity, and past it row i answers for another unit.
    let pos = los_positions(&roster.keys);
    let los_pairs = plain.get("los_pairs").map(|v| any_array(&v)).filter(|r| !r.is_empty()).map(|rows| {
        // Read in the matrix's own (key-sorted) order, STORE in roster order,
        // so `_los_clear`'s port can index it with roster indices.
        let raw: Vec<Vec<u8>> = rows.iter_shared().map(|r| text(&r).into_bytes()).collect();
        let mut m = Vec::with_capacity(n * n);
        for i in 0..n {
            for j in 0..n {
                let (ri, rj) = (pos[i], pos[j]);
                m.push(raw.get(ri).and_then(|r| r.get(rj)).copied() == Some(b'1'));
            }
        }
        Rc::new(m)
    });
    let prof_table = Rc::clone(&profiles);
    let mut st = State {
        roster: Rc::clone(&roster),
        profiles,
        round: dint(plain, "round", 0),
        rounds_total: dint(plain, "rounds_total", 0),
        scoring: Rc::from(dtext(plain, "scoring").as_str()),
        objectives: darr(plain, "objectives")
            .iter_shared()
            .filter_map(|v| v.try_to::<VarDictionary>().ok())
            .map(|o| Objective {
                pos: o.get("pos").map(|p| vec3(&p)).unwrap_or([0.0; 3]),
                owner: dint(&o, "owner", 0),
            })
            .collect(),
        markers_meta,
        destroy_seq: darr(plain, "destroy_seq").iter_shared().map(|v| int(&v)).collect(),
        vp: None,
        vp_flavour: None,
        vp_memo: None,
        cast_events: Vec::new(),
        player: Vec::with_capacity(n),
        alive: Vec::with_capacity(n),
        activated: Vec::with_capacity(n),
        shaken: Vec::with_capacity(n),
        fatigued: Vec::with_capacity(n),
        in_cover: Vec::with_capacity(n),
        aircraft: Vec::with_capacity(n),
        dormant: Vec::with_capacity(n),
        casts: Vec::with_capacity(n),
        morale_bonus: Vec::with_capacity(n),
        ambush_arrived_round: Vec::with_capacity(n),
        earliest_arrival_round: Vec::with_capacity(n),
        wound_frac: Vec::with_capacity(n),
        positions: Vec::with_capacity(n),
        wounds: Vec::with_capacity(n),
        radii: Vec::with_capacity(n),
        mods: Vec::with_capacity(n),
        mods_base: Vec::with_capacity(n),
        attached: Rc::new(Vec::new()),
        attached_to: Rc::new(Vec::new()),
        los: Vec::with_capacity(n),
        bands: Vec::with_capacity(n),
        shroud: Vec::with_capacity(n),
        charge_no_difficult: Vec::with_capacity(n),
        charge_probe_r: Vec::with_capacity(n),
        los_pairs,
    };
    let mut mask: Vec<u32> = Vec::with_capacity(n);
    let mut has_los = false;
    let mut dropped: Vec<String> = Vec::new();
    // The attachment keys only resolve once every unit key is known.
    let mut attached_keys: Vec<Vec<String>> = Vec::with_capacity(n);
    let mut host_keys: Vec<String> = Vec::with_capacity(n);
    for key in roster.keys.iter() {
        let u = units
            .get(key.as_str())
            .and_then(|v| v.try_to::<VarDictionary>().ok())
            .ok_or_else(|| format!("unit {key} vanished between roster and state"))?;
        let mut m = 0u32;
        for (i, k) in UNIT_KEYS.iter().enumerate() {
            if u.contains_key(*k) {
                m |= 1 << i;
            }
        }
        mask.push(m);
        for k in DROPPED {
            if u.contains_key(k) && !dropped.iter().any(|d| d == k) {
                dropped.push(k.to_string());
            }
        }
        st.player.push(dint(&u, "player", 0));
        st.alive.push(dint(&u, "alive", 0));
        st.activated.push(dflag(&u, "activated"));
        st.shaken.push(dflag(&u, "shaken"));
        st.fatigued.push(dflag(&u, "fatigued"));
        st.in_cover.push(dflag(&u, "in_cover"));
        st.aircraft.push(dflag(&u, "aircraft"));
        st.dormant.push(dflag(&u, "dormant"));
        st.casts.push(dint(&u, "casts", 0));
        st.morale_bonus.push(dint(&u, "morale_bonus", 0));
        st.ambush_arrived_round.push(dint(&u, "ambush_arrived_round", -1));
        st.earliest_arrival_round.push(dint(&u, "earliest_arrival_round", -1));
        st.wound_frac.push(dnum(&u, "wound_frac", 0.0));
        st.positions.push(darr(&u, "positions").iter_shared().map(|v| vec3(&v)).collect());
        st.wounds.push(darr(&u, "wounds").iter_shared().map(|v| int(&v)).collect());
        st.radii.push(darr(&u, "radii").iter_shared().map(|v| num(&v)).collect());
        st.mods.push(mods_of(&ddict(&u, "mods")));
        st.mods_base.push(Rc::new(mods_of(&ddict(&u, "mods_base"))));
        attached_keys.push(strings(&darr(&u, "attached")));
        host_keys.push(dtext(&u, "attached_to"));
        // NML-1073 M2-0c/M2-0d gate reads (`AiActRecorder._stamp_gate_reads`,
        // battle_sim.gd:1402). `state_to_plain` always writes `bands`; the three
        // charge-gate reads are stamped by the recorder / by the M2-5 seam. An
        // ABSENT `bands` falls back to the PROFILE's copy of the same
        // `SoloController.sim_move_bands` call, exactly as `io::state_of` does —
        // a defaulted 6"/12" would answer for a Slow unit the profile reads as 4"/8".
        st.bands.push(match u.get("bands").and_then(|v| v.try_to::<VarDictionary>().ok()) {
            Some(b) => Bands { advance: dnum(&b, "advance", 6.0), rush: dnum(&b, "rush", 12.0) },
            None => {
                let mb = prof_table.list[roster.profile[st.bands.len()]].move_bands;
                Bands { advance: mb.advance, rush: mb.rush }
            }
        });
        // `_melee_shroud_charge_in_plain` (battle_sim.gd:1572) takes the pair only
        // when the recorded array holds BOTH numbers; anything shorter is "absent".
        st.shroud.push(match u.get("shroud").and_then(|v| v.try_to::<VarArray>().ok()) {
            Some(a) if a.len() >= 2 => Some([num(&a.at(0)), num(&a.at(1))]),
            _ => None,
        });
        st.charge_no_difficult.push(dflag(&u, "charge_no_difficult"));
        // `SeparationChecker.DEFAULT_BASE_RADIUS_M` — the fallback
        // `BattleSim.charge_illegal_plain` (battle_sim.gd:1563) reads.
        st.charge_probe_r.push(dnum(&u, "charge_probe_r", 0.016));
        match u.get("los").and_then(|v| v.try_to::<VarDictionary>().ok()) {
            Some(m) => {
                has_los = true;
                let mut row: HashMap<String, bool> = HashMap::with_capacity(m.len());
                for k in m.keys_array().iter_shared() {
                    let name = text(&k);
                    let val = m.get(&k).map(|v| flag(&v)).unwrap_or(true);
                    row.insert(name, val);
                }
                st.los.push(Some(Rc::new(row)));
            }
            None => st.los.push(None),
        }
    }
    // A key the roster does not carry is dropped — `_unit_group` (battle_sim.gd:
    // 528-547) puts it in its key set too, but the obstacle walk over
    // `next["units"]` can never match it. `plain_of` therefore writes back the
    // keys it could resolve; an unresolvable one does not survive the round trip.
    st.attached = Rc::new(
        attached_keys
            .iter()
            .map(|ks| ks.iter().filter_map(|k| roster.index.get(k.as_str()).copied()).collect())
            .collect(),
    );
    st.attached_to =
        Rc::new(host_keys.iter().map(|k| roster.index.get(k.as_str()).copied()).collect());
    Ok(Captured { state: st, extras, mask, has_los, dropped })
}

// ---------------------------------------------------------------- writers ---

fn vec3_out(p: &[f64; 3]) -> VarArray {
    let mut a = VarArray::new();
    a.push(&p[0].to_variant());
    a.push(&p[1].to_variant());
    a.push(&p[2].to_variant());
    a
}

fn mods_out(m: &Mods) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("hit", m.hit);
    d.set("def", m.def);
    d.set("morale", m.morale);
    d.set("range_in", m.range_in);
    d.set("advance", m.advance);
    d.set("rush", m.rush);
    d
}

/// The inverse of `build_state` — the plain form `BattleSim.state_to_plain(state,
/// false)` would have written for this state, key set included (`mask`).
pub fn plain_of(cap: &Captured) -> VarDictionary {
    let st = &cap.state;
    let mut out = VarDictionary::new();
    out.set("round", st.round);
    out.set("rounds_total", st.rounds_total);
    let mut units = VarDictionary::new();
    for i in 0..st.units() {
        let mut u = VarDictionary::new();
        let bits = cap.mask.get(i).copied().unwrap_or(0);
        let has = |k: &str| -> bool {
            UNIT_KEYS.iter().position(|x| *x == k).map(|b| bits & (1 << b) != 0).unwrap_or(false)
        };
        if has("alive") {
            u.set("alive", st.alive[i]);
        }
        if has("wounds") {
            let mut a = VarArray::new();
            for w in &st.wounds[i] {
                a.push(&w.to_variant());
            }
            u.set("wounds", &a);
        }
        if has("radii") {
            let mut a = VarArray::new();
            for r in &st.radii[i] {
                a.push(&r.to_variant());
            }
            u.set("radii", &a);
        }
        if has("in_cover") {
            u.set("in_cover", st.in_cover[i]);
        }
        if has("shaken") {
            u.set("shaken", st.shaken[i]);
        }
        if has("fatigued") {
            u.set("fatigued", st.fatigued[i]);
        }
        if has("activated") {
            u.set("activated", st.activated[i]);
        }
        if has("casts") {
            u.set("casts", st.casts[i]);
        }
        if has("mods") {
            u.set("mods", &mods_out(&st.mods[i]));
        }
        if has("mods_base") {
            u.set("mods_base", &mods_out(&st.mods_base[i]));
        }
        if has("aircraft") {
            u.set("aircraft", st.aircraft[i]);
        }
        if has("ambush_arrived_round") {
            u.set("ambush_arrived_round", st.ambush_arrived_round[i]);
        }
        if has("player") {
            u.set("player", st.player[i]);
        }
        if has("morale_bonus") {
            u.set("morale_bonus", st.morale_bonus[i]);
        }
        if has("dormant") {
            u.set("dormant", st.dormant[i]);
        }
        if has("earliest_arrival_round") {
            u.set("earliest_arrival_round", st.earliest_arrival_round[i]);
        }
        if has("attached") {
            let mut a = VarArray::new();
            for &h in &st.attached[i] {
                a.push(&GString::from(st.key(h)).to_variant());
            }
            u.set("attached", &a);
        }
        if has("attached_to") {
            let host = st.attached_to[i].map(|h| st.key(h)).unwrap_or("");
            u.set("attached_to", &GString::from(host));
        }
        // `_apply_expected_wounds` (battle_sim.gd:1050-1059) CREATES the key on
        // the target the first time a volley lands, so a state that had none can
        // grow one; a zero carry it also writes is indistinguishable from "never
        // touched" here and stays absent (the checker reports that separately).
        if has("wound_frac") || st.wound_frac[i] != 0.0 {
            u.set("wound_frac", st.wound_frac[i]);
        }
        let mut pos = VarArray::new();
        for p in &st.positions[i] {
            pos.push(&vec3_out(p).to_variant());
        }
        u.set("positions", &pos);
        if let Some(row) = &st.los[i] {
            let mut m = VarDictionary::new();
            for (k, v) in row.iter() {
                m.set(k.as_str(), *v);
            }
            u.set("los", &m);
        }
        units.set(st.key(i), &u);
    }
    out.set("units", &units);
    out.set("scoring", &*st.scoring);
    let mut objs = VarArray::new();
    for o in &st.objectives {
        let mut od = VarDictionary::new();
        od.set("pos", &vec3_out(&o.pos));
        od.set("owner", o.owner);
        objs.push(&od.to_variant());
    }
    out.set("objectives", &objs);
    for k in EXTRA_KEYS {
        if let Some(v) = cap.extras.get(k) {
            out.set(k, &v);
        }
    }
    if let Some(m) = &st.los_pairs {
        // Written back KEY-SORTED, the one order `state_to_plain` produces and
        // the reader above expects — the state carries it in ROSTER order.
        let n = st.units();
        let pos = los_positions(&st.roster.keys);
        let mut at = vec![0usize; n];
        for (i, &row) in pos.iter().enumerate() {
            at[row] = i;
        }
        let mut rows = VarArray::new();
        for &i in &at {
            let mut s = String::with_capacity(n);
            for &j in &at {
                s.push(if m[i * n + j] { '1' } else { '0' });
            }
            rows.push(&GString::from(s.as_str()).to_variant());
        }
        out.set("los_pairs", &rows);
    }
    out
}

// -------------------------------------------------- the M2-5 game header ---

/// `AiActRecorder._header_line`'s `"profiles"` (act_recorder.gd:120-126) — the
/// per-unit STATIC table, written ONCE per game and keyed by the unit key. The
/// insertion order of the Godot dictionary is the capture order the recorder
/// walked, so the profile INDEX of a unit is its position here.
pub fn profiles_of_header(d: &VarDictionary) -> Profiles {
    let mut profiles = Profiles::default();
    for k in d.keys_array().iter_shared() {
        let key = text(&k);
        let pd = d.get(&k).and_then(|v| v.try_to::<VarDictionary>().ok()).unwrap_or_default();
        profiles.index.insert(key, profiles.list.len());
        profiles.list.push(profile_of(&pd));
    }
    profiles
}

/// `io::roster_of` for the live seam: the roster is the STATE's key order, each
/// unit pointing at the HEADER's profile of the same key. A key with no profile
/// is a header that does not belong to this game, and is refused rather than
/// defaulted.
pub fn roster_of_keys(keys: &[String], profiles: &Profiles) -> Result<Roster, String> {
    let mut roster = Roster::default();
    for k in keys {
        let pi = *profiles
            .index
            .get(k.as_str())
            .ok_or_else(|| format!("no profile for unit key {k} — stale game header"))?;
        roster.index.insert(k.clone(), roster.keys.len());
        roster.profile.push(pi);
        roster.keys.push(k.clone());
    }
    Ok(roster)
}

/// `AiActRecorder._terrain_line` (act_recorder.gd:136-154) read off a Variant.
pub fn terrain_of(d: &VarDictionary) -> PlainTerrain {
    let cells: Vec<[f64; 3]> = darr(d, "cells")
        .iter_shared()
        .map(|v| {
            let a = any_array(&v);
            let mut out = [0.0f64; 3];
            for (i, slot) in out.iter_mut().enumerate() {
                if i < a.len() {
                    *slot = num(&a.at(i));
                }
            }
            out
        })
        .collect();
    let pair = |a: &VarArray| -> [f64; 2] {
        [
            if a.is_empty() { 0.0 } else { num(&a.at(0)) },
            if a.len() < 2 { 0.0 } else { num(&a.at(1)) },
        ]
    };
    let sandbox: Vec<Obb> = darr(d, "sandbox")
        .iter_shared()
        .filter_map(|v| v.try_to::<VarDictionary>().ok())
        .map(|s| Obb {
            c: pair(&darr(&s, "c")),
            he: pair(&darr(&s, "he")),
            yaw: dnum(&s, "yaw", 0.0),
            kind: dint(&s, "type", 0) as i32,
        })
        .collect();
    let cp = ddict(d, "cell_params");
    PlainTerrain {
        cells,
        sandbox,
        cell_params: CellParams {
            table_size_feet: pair(&darr(&cp, "table_size_feet")),
            grid_rotation_degrees: dnum(&cp, "grid_rotation_degrees", 0.0),
            grid_size_inches: dnum(&cp, "grid_size_inches", 3.0),
            inches_to_meters: dnum(&cp, "inches_to_meters", 0.0254),
        },
    }
}

/// `AiActRecorder._header_line`'s `"knobs"` (act_recorder.gd:126-133). Every
/// default is the one `acts::Knobs::default()` carries, so an absent key answers
/// what a corpus without that knob answers.
pub fn knobs_of(d: &VarDictionary) -> Knobs {
    let dflt = Knobs::default();
    Knobs {
        top_k: dint(d, "top_k", dflt.top_k),
        horizon: dint(d, "horizon", dflt.horizon),
        tail_cap_p1: dint(d, "tail_cap_p1", dflt.tail_cap_p1),
        tail_cap_p2: dint(d, "tail_cap_p2", dflt.tail_cap_p2),
        imagined_round_end: d
            .get("imagined_round_end")
            .map(|v| flag(&v))
            .unwrap_or(dflt.imagined_round_end),
        depth_discount: dnum(d, "depth_discount", dflt.depth_discount),
        seat_mode: dint(d, "seat_mode", dflt.seat_mode),
        playout_margin: dnum(d, "playout_margin", dflt.playout_margin),
        playout_rich: d.get("playout_rich").map(|v| flag(&v)).unwrap_or(dflt.playout_rich),
        seam_cast: dflag(d, "seam_cast"),
        seam_spacing: dflag(d, "seam_spacing"),
        // NML-1073 M4-7. No recorder writes this key yet (ai_planner.gd:607
        // stamps only spacing and cast); `NmlCore::plan_inner` ORs the
        // NML_SIM_PATH environment on top, so the seam is reachable from a
        // shipped build without a GDScript change.
        seam_path: dflag(d, "seam_path"),
        // NML-1073 M3-5. The GDScript seam runs INSIDE the game, whose
        // SoloController always wires `state["charge_illegal"]` — so the gate
        // is on, which is also `Knobs::default()`. The knob exists for the
        // Godot-free harness, whose GDScript twin (tools/core_selfplay.gd)
        // wires no gate; a header that carries the key is honoured either way.
        charge_gate: d.get("charge_gate").map(|v| flag(&v)).unwrap_or(dflt.charge_gate),
    }
}

/// One menu candidate as the GDScript builds it (`AiPlanner.candidates`
/// ai_planner.gd:951-985): the OPTIONAL keys exist only when they carry
/// something, because `_solve_planner` (solo_controller.gd:3423-3428) and
/// `_describe` (:930-941) branch on `has()`, not on the value.
pub fn candidate_out(c: &nml_core::Candidate) -> VarDictionary {
    let mut d = VarDictionary::new();
    d.set("unit", &GString::from(c.unit.as_str()));
    d.set("kind", c.kind);
    if let Some(p) = c.dest {
        d.set("dest", &vec3_out(&p));
    }
    if let Some(s) = &c.shoot {
        d.set("shoot", &GString::from(s.as_str()));
    }
    if let Some(s) = &c.charge {
        d.set("charge", &GString::from(s.as_str()));
    }
    if c.patient {
        d.set("patient", true);
    }
    if let Some(w) = &c.wave {
        d.set("wave", &GString::from(w.as_str()));
    }
    d
}

/// `plain_of` for a state the caller did not capture — the winning rollout's
/// LEAF. It has the same roster and the same per-unit key set as the root it
/// grew from (a rollout only ever writes values), so the root's mask and its
/// verbatim state-level blobs are the right ones to write it back with.
pub fn plain_of_derived(state: &State, root: &Captured) -> VarDictionary {
    plain_of(&Captured {
        state: state.clone(),
        extras: root.extras.clone(),
        mask: root.mask.clone(),
        has_los: root.has_los,
        dropped: Vec::new(),
    })
}
