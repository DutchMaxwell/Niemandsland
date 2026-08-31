//! NML-1140 steps 1-3 — doctrine skeleton: the mode enum, the canonical
//! per-army summary and the style label, extracted ONCE here from the
//! act-header profiles (`battle_sim.gd:_unit_profile` schema,
//! loader_gate.py parity-gated, field names pinned to list_to_profile.py).
//! Value in, ints out — means x2, half-integers exact. No callers yet, zero
//! RNG. UNSURE: label calibration probe-deferred like FAIRNESS_EPS; shots =
//! attacks x count on range > 0 weapons, 24" / 12" bands.
use serde_json::Value;
use std::{collections::HashMap, rc::Rc};

use crate::state::{Bands, Mods, Objective, Profile, Profiles, Roster, State};
use crate::{IN2M, objectives, score};

/// Doctrine mode (design 4/5); "random" is today's byte-identical path.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Mode { Random, Style, Search }

impl Mode {
    pub fn as_str(self) -> &'static str {
        match self { Mode::Random => "random", Mode::Style => "style", Mode::Search => "search" }
    }
    pub fn of_str(s: &str) -> Option<Mode> {
        match s { "random" => Some(Mode::Random), "style" => Some(Mode::Style), "search" => Some(Mode::Search), _ => None }
    }
}

/// Style label: argmax shooting / fast / tough, ties in that fixed order (design 2).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum StyleLabel { Shooting, Fast, Tough }

/// Canonical per-army summary (design 2); `*_x2` = doubled means, exact ints.
/// Field order is the signature tuple the canonical roster order sorts by.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, PartialOrd, Ord)]
pub struct Summary {
    pub shots_far: i64,     // ranged volume (attacks x count) at >= 24"
    pub shots_mid: i64,     // ranged volume at 12-24"
    pub advance_x2: i64,    // mean move_bands.advance over units, x2
    pub rush_x2: i64,       // mean move_bands.rush over units, x2
    pub wounds_total: i64,  // sum of wounds_max over all models
    pub models: i64,        // sum of model_count over units
    pub tough_mean_x2: i64, // mean unit-level tough over units, x2
}

const MOVE_REF_IN: i64 = 12; // label fast scale: the OPR baseline rush band
const WOUND_REF: i64 = 4; // label tough scale: a 4-wound model line

/// Half-up doubled mean, integer arithmetic only.
fn mean_x2(sum: i64, n: i64) -> i64 {
    if n <= 0 { 0 } else { (2 * sum + n / 2) / n }
}

impl Summary {
    /// One army's summary off the header's `profiles` object; missing -> 0.
    pub fn of_profiles(profiles: &Value) -> Summary {
        let int_of = |v: &Value, k: &str| v.get(k).and_then(Value::as_i64).unwrap_or(0);
        let units: Vec<&Value> = profiles.as_object().map(|m| m.values().collect()).unwrap_or_default();
        let (mut far, mut mid, mut adv, mut rush, mut tough, mut wounds, mut models) = (0, 0, 0, 0, 0, 0, 0);
        for p in &units {
            for w in p.get("weapons").and_then(Value::as_array).into_iter().flatten() {
                let vol = int_of(w, "attacks") * int_of(w, "count");
                let r = int_of(w, "range");
                if r >= 24 { far += vol; } else if r >= 12 { mid += vol; }
            }
            adv += p.get("move_bands").and_then(|b| b.get("advance")).and_then(Value::as_f64).unwrap_or(0.0).round() as i64;
            rush += p.get("move_bands").and_then(|b| b.get("rush")).and_then(Value::as_f64).unwrap_or(0.0).round() as i64;
            wounds += p.get("wounds_max").and_then(Value::as_array).map(|ws| ws.iter().filter_map(Value::as_i64).sum::<i64>()).unwrap_or(0);
            models += int_of(p, "model_count");
            tough += int_of(p, "tough");
        }
        let n = units.len() as i64;
        Summary {
            shots_far: far, shots_mid: mid, advance_x2: mean_x2(adv, n), rush_x2: mean_x2(rush, n),
            tough_mean_x2: mean_x2(tough, n), wounds_total: wounds, models,
        }
    }

    /// Label: cross-multiplied integer shares, ties to the earlier arm.
    pub fn label(&self) -> StyleLabel {
        let sh = 4 * MOVE_REF_IN * WOUND_REF * (self.shots_far + self.shots_mid);
        let fa = WOUND_REF * self.models * (self.advance_x2 + self.rush_x2);
        let tu = 4 * MOVE_REF_IN * self.wounds_total;
        if sh >= fa && sh >= tu { StyleLabel::Shooting } else if fa >= tu { StyleLabel::Fast } else { StyleLabel::Tough }
    }
}

/// Design 3 — the synthetic zone fill and the edge-fairness leaf inputs.
/// Zone rectangles and marker positions are in INCHES (the objective_gate.py
/// bands and the doctrine grid); `State` positions are metres.
#[derive(Clone, Copy, Debug)]
pub struct Zone { pub x_min: f64, pub x_max: f64, pub z_min: f64, pub z_max: f64 }

const DEFAULT_RADIUS_IN: f64 = 0.032 / IN2M; // the 32 mm default (design 3)

fn radius_in(p: &Profile) -> f64 {
    if p.base_radius > 0.0 { p.base_radius / IN2M } else { DEFAULT_RADIUS_IN }
}

/// The fixed fill: units in capture order along the zone's centre row, each
/// in a slot of 2 x base-radius + 1", rows wrapping toward the zone's table
/// edge. All models cluster on the unit's slot centre (control_gap_in takes
/// the nearest model, so clustering moves nothing).
fn fill(zone: &Zone, profs: &[Profile]) -> Vec<Vec<[f64; 3]>> {
    let mut out = Vec::new();
    let (mut x, mut z) = (zone.x_min, (zone.z_min + zone.z_max) / 2.0);
    let dz = if zone.z_max > 0.0 { 1.0 } else { -1.0 };
    for p in profs {
        let r = radius_in(p);
        let slot = 2.0 * r + 1.0;
        if x + slot > zone.x_max { x = zone.x_min; z += dz * slot; }
        out.push(vec![[(x + r) * IN2M, 0.0, z * IN2M]; p.model_count.max(1) as usize]);
        x += slot;
    }
    out
}

/// One army's roster slice in profile-map order (capture order) plus its fill.
fn army_units(army: &Value, zone: &Zone, keys: &mut Vec<String>, profs: &mut Vec<Profile>) -> Vec<Vec<[f64; 3]>> {
    let start = profs.len();
    for (k, v) in army.as_object().expect("profiles object") {
        keys.push(k.clone());
        profs.push(serde_json::from_value(v.clone()).expect("profile schema"));
    }
    fill(zone, &profs[start..])
}

/// The synthetic state (design 3): army `a` stood up in `zone_a` as player 1,
/// army `b` in `zone_b` as player 2, `markers` (inches) as owner-0 objectives.
/// Horizon = round 1 of ROUNDS = 4 (core_selfplay.gd:23). Zero RNG, zero
/// draws — the streamed roll-off stays at the call site (design 1).
pub fn synth_state(a: &Value, b: &Value, zone_a: &Zone, zone_b: &Zone, markers: &[[f64; 3]]) -> State {
    let mut keys = Vec::new();
    let mut profs: Vec<Profile> = Vec::new();
    let mut spots = army_units(a, zone_a, &mut keys, &mut profs);
    let na = profs.len();
    spots.extend(army_units(b, zone_b, &mut keys, &mut profs));
    let n = keys.len();
    let idx: HashMap<String, usize> = keys.iter().enumerate().map(|(i, k)| (k.clone(), i)).collect();
    let alive: Vec<i64> = profs.iter().map(|p| p.model_count.max(1)).collect();
    let wounds: Vec<Vec<i64>> = profs.iter().map(|p| p.wounds_max.clone()).collect();
    let radii: Vec<Vec<f64>> = profs.iter().map(|p| vec![radius_in(p) * IN2M; p.model_count.max(1) as usize]).collect();
    let bands: Vec<Bands> = profs.iter().map(|p| Bands { advance: p.move_bands.advance, rush: p.move_bands.rush }).collect();
    State {
        roster: Rc::new(Roster { keys, index: idx.clone(), profile: (0..n).collect() }),
        profiles: Rc::new(Profiles { list: profs, index: idx }),
        round: 1,
        rounds_total: 4,
        scoring: Rc::from("markers"),
        objectives: markers.iter().map(|m| Objective { pos: [m[0] * IN2M, m[1] * IN2M, m[2] * IN2M], owner: 0 }).collect(),
        markers_meta: Vec::new(), destroy_seq: Vec::new(),
        vp: None, vp_flavour: None, vp_memo: None, cast_events: Vec::new(),
        player: (0..n).map(|i| if i < na { 1 } else { 2 }).collect(),
        alive,
        activated: vec![false; n], shaken: vec![false; n], fatigued: vec![false; n],
        in_cover: vec![false; n], aircraft: vec![false; n], dormant: vec![false; n],
        casts: vec![0; n], morale_bonus: vec![0; n],
        ambush_arrived_round: vec![0; n], earliest_arrival_round: vec![0; n],
        wound_frac: vec![1.0; n],
        positions: spots,
        wounds,
        radii,
        mods: vec![Mods::default(); n], mods_base: vec![Rc::new(Mods::default()); n],
        attached: Rc::new(vec![Vec::new(); n]), attached_to: Rc::new(vec![None; n]),
        los: vec![None; n], los_pairs: None,
        bands,
        shroud: vec![None; n], charge_no_difficult: vec![false; n], charge_probe_r: vec![0.0; n],
    }
}

/// Design 3 leaf inputs: S1 = A in zone1 / B in zone2, S2 = the swap;
/// returns (a1, a2), army A's hand score on each edge. On the non-destroy
/// hand path b1 = 1 - a1 and b2 = 1 - a2 — asserted by the tests.
pub fn edge_scores(a: &Value, b: &Value, zone1: &Zone, zone2: &Zone, markers: &[[f64; 3]]) -> (f64, f64) {
    let s1 = synth_state(a, b, zone1, zone2, markers);
    let s2 = synth_state(b, a, zone1, zone2, markers);
    (score::score(&s1, 1, score::NO_INCOMING), score::score(&s2, 2, score::NO_INCOMING))
}

/// Design 4 mode "style" — the edge-fairness epsilon and the 3" grid step.
pub const FAIRNESS_EPS: f64 = 0.10;
const GRID_STEP_IN: i64 = 3;

/// The doctrine's output: placed cells in inches (`Layout.positions` shape)
/// plus the sweep-honest count (design 1).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Placed { pub cells: Vec<(i64, i64)>, pub swept: usize }

/// One side's fill rectangle (design 3): bbox of that side's zone polygons.
fn zone_rect(style: &Value, side: &str) -> Zone {
    let mut z = Zone { x_min: f64::INFINITY, x_max: f64::NEG_INFINITY, z_min: f64::INFINITY, z_max: f64::NEG_INFINITY };
    let polys = style.get("zones").and_then(|s| s.get(side)).and_then(Value::as_array);
    for poly in polys.into_iter().flatten() {
        for p in poly.as_array().into_iter().flatten().filter(|p| p.as_array().is_some_and(|a| a.len() >= 2)) {
            let (x, zz) = (p.get(0).and_then(Value::as_f64).unwrap_or(0.0), p.get(1).and_then(Value::as_f64).unwrap_or(0.0));
            z.x_min = z.x_min.min(x); z.x_max = z.x_max.max(x);
            z.z_min = z.z_min.min(zz); z.z_max = z.z_max.max(zz);
        }
    }
    z
}

/// Design 4 — canonical roster order: signature tuple, ties by each army's
/// lexicographically first unit name. doctrine(a, b) = doctrine(b, a).
fn canonical<'x>(a: &'x Value, b: &'x Value) -> (&'x Value, &'x Value) {
    let name = |v: &Value| v.as_object().and_then(|m| m.keys().min().cloned()).unwrap_or_default();
    if (Summary::of_profiles(a), name(a)) <= (Summary::of_profiles(b), name(b)) { (a, b) } else { (b, a) }
}

/// The per-cell style preference, integer-only (the D8a lesson): ascending
/// sort = better, ties by x then z (design 4's pinned order). Shooting takes
/// the centre band, fast spreads from the placed markers, tough the centre
/// mass. UNSURE: calibration probe-deferred like FAIRNESS_EPS.
fn pref_key(label: StyleLabel, x: i64, z: i64, placed: &[(i64, i64)]) -> (i64, i64, i64) {
    let spread = placed.iter().map(|p| { let (dx, dz) = (p.0 - x, p.1 - z); dx * dx + dz * dz }).min().unwrap_or(i64::MAX);
    let first = match label {
        StyleLabel::Shooting => x.abs() + z.abs(),
        StyleLabel::Fast => -spread,
        StyleLabel::Tough => x * x + z * z,
    };
    (first, x, z)
}

/// Mode "style" (design 4): plies alternate in canonical order; each placer
/// takes the best-ranked legal grid cell whose marker set keeps |a1 - a2| —
/// army A's edge bias, B's is complementary (design 3) — within FAIRNESS_EPS,
/// checked on the GROWING set. If no legal cell passes, the guard is waived
/// for the top-preference cell (still doctrine-placed); only a ply with NO
/// legal grid cell falls to the deterministic sweep and counts in `swept`
/// (design 1); none at all = fewer markers. Zero RNG, legality = is_legal.
pub fn place_style(a: &Value, b: &Value, style: &Value, cells: &objectives::Cells, count: usize, table_w_in: f64, table_d_in: f64) -> Placed {
    let zones = objectives::zones_of_style(style);
    let (z1, z2) = (zone_rect(style, "1"), zone_rect(style, "2"));
    let (hx, hz) = ((table_w_in / 2.0) as i64 - objectives::EDGE_MARGIN_IN, (table_d_in / 2.0) as i64 - objectives::EDGE_MARGIN_IN);
    let (first, second) = canonical(a, b);
    let (lab_a, lab_b) = (Summary::of_profiles(first).label(), Summary::of_profiles(second).label());
    let mut placed: Vec<(i64, i64)> = Vec::new();
    let mut swept = 0usize;
    for ply in 0..count {
        let label = if ply % 2 == 0 { lab_a } else { lab_b };
        let mut cands: Vec<(i64, i64)> = Vec::new();
        for x in (-hx..=hx).step_by(GRID_STEP_IN as usize) {
            for z in (-hz..=hz).step_by(GRID_STEP_IN as usize) {
                if objectives::is_legal(x, z, &placed, &zones, cells) { cands.push((x, z)); }
            }
        }
        cands.sort_by_key(|&(x, z)| pref_key(label, x, z, &placed));
        let fair = cands.iter().copied().find(|&c| {
            let m: Vec<[f64; 3]> = placed.iter().chain(std::iter::once(&c)).map(|&(x, z)| [x as f64, 0.0, z as f64]).collect();
            let (a1, a2) = edge_scores(first, second, &z1, &z2, &m);
            (a1 - a2).abs() <= FAIRNESS_EPS
        });
        let (cell, swept_now) = match fair {
            Some(c) => (Some(c), false),
            None => match cands.first() {
                Some(&c) => (Some(c), false),
                None => (objectives::sweep(hx, hz, &placed, &zones, cells), true),
            },
        };
        match cell {
            Some(c) => { placed.push(c); if swept_now { swept += 1; } }
            None => break,
        }
    }
    Placed { cells: placed, swept }
}

/// Design 4 mode "search" — branching cap per ply, and the quantum the
/// argmax compares in (an argmax never hangs on a float hair; D8a generalized).
const SEARCH_K: usize = 8;
const QUANT: f64 = 1e-6;

fn quant(v: f64) -> i64 { (v / QUANT).round() as i64 }

/// Markers in inches — the `edge_scores` input shape.
fn inch_markers(placed: &[(i64, i64)]) -> Vec<[f64; 3]> {
    placed.iter().map(|&(x, z)| [x as f64, 0.0, z as f64]).collect()
}

/// Leaf values: v_X = min over the two edges (design 3); B's hand score is
/// complementary (gate-tested), so v_B = 1 - max(a1, a2). Integer compare only.
fn leaf_vals(a1: f64, a2: f64) -> [i64; 2] {
    [quant(a1.min(a2)), quant(1.0 - a1.max(a2))]
}

/// The search's frozen inputs: grid bounds, legality, the canonical pair with
/// their zone rectangles and style labels. Zero RNG by construction.
struct SearchCtx<'x> {
    hx: i64, hz: i64, zones: Vec<objectives::Poly>, cells: &'x objectives::Cells,
    z1: Zone, z2: Zone, first: &'x Value, second: &'x Value,
    lab_a: StyleLabel, lab_b: StyleLabel,
}

/// One max^N node (design 4): the placer at `ply` — canonical order, ply
/// parity — expands its top-K legal cells by the style preference, one eval
/// per candidate that is BOTH the fairness guard DURING expansion (a set
/// pushing |a1 - a2| past FAIRNESS_EPS is pruned, not merely scored) and, at
/// the last ply, the leaf. Each node maximizes the PLACER's own side-blind
/// value; the node's value is the whole outcome vector of the line its argmax
/// picks (general-sum max^N — a componentwise max would report vectors no
/// legal set achieves), and the path follows that same argmax, ties keeping
/// the first ranked child (preference, then x, z — lexicographic). Guard
/// starvation (no candidate passes) = the K ranked candidates compete
/// unguarded, still doctrine-placed, never swept (step 3's reading).
fn search_node(ctx: &SearchCtx, ply: usize, last: usize, placed: &[(i64, i64)]) -> ([i64; 2], Vec<(i64, i64)>) {
    let label = if ply % 2 == 0 { ctx.lab_a } else { ctx.lab_b };
    let mut cands: Vec<(i64, i64)> = Vec::new();
    for x in (-ctx.hx..=ctx.hx).step_by(GRID_STEP_IN as usize) {
        for z in (-ctx.hz..=ctx.hz).step_by(GRID_STEP_IN as usize) {
            if objectives::is_legal(x, z, placed, &ctx.zones, ctx.cells) { cands.push((x, z)); }
        }
    }
    cands.sort_by_key(|&(x, z)| pref_key(label, x, z, placed));
    cands.truncate(SEARCH_K);
    if cands.is_empty() {
        // Dead grid: the game ends here with fewer markers (design 1), valued
        // on the set placed so far; the root answers such a ply with the sweep.
        let (a1, a2) = edge_scores(ctx.first, ctx.second, &ctx.z1, &ctx.z2, &inch_markers(placed));
        return (leaf_vals(a1, a2), Vec::new());
    }
    let kids: Vec<((i64, i64), (f64, f64))> = cands.into_iter().map(|c| {
        let mut m = inch_markers(placed);
        m.push([c.0 as f64, 0.0, c.1 as f64]);
        (c, edge_scores(ctx.first, ctx.second, &ctx.z1, &ctx.z2, &m))
    }).collect();
    let mut alive: Vec<((i64, i64), (f64, f64))> = kids.clone();
    alive.retain(|(_, (a1, a2))| (a1 - a2).abs() <= FAIRNESS_EPS);
    if alive.is_empty() { alive = kids; }
    let (leaf, placer) = (ply + 1 == last, ply & 1);
    let (mut val, mut best_v, mut path) = ([i64::MIN; 2], i64::MIN, Vec::new());
    for &(c, es) in &alive {
        let (cv, cp) = if leaf {
            (leaf_vals(es.0, es.1), vec![c])
        } else {
            let mut next = placed.to_vec();
            next.push(c);
            let (v, sub) = search_node(ctx, ply + 1, last, &next);
            let mut p = Vec::with_capacity(sub.len() + 1);
            p.push(c);
            p.extend(sub);
            (v, p)
        };
        if cv[placer] > best_v { best_v = cv[placer]; val = cv; path = cp; }
    }
    (val, path)
}

/// Mode "search" (design 4): the max^N mini-game over the alternating
/// placement — `count` plies in canonical roster order, both rosters open.
/// The sweep stays the last resort for a ply the doctrine cannot place
/// (no legal grid cell at all; the 1" lattice may still admit what the 3"
/// grid does not), counted honestly in `swept`; otherwise fewer markers
/// (design 1). Zero RNG — same inputs, same cells, bit for bit.
pub fn place_search(a: &Value, b: &Value, style: &Value, cells: &objectives::Cells, count: usize, table_w_in: f64, table_d_in: f64) -> Placed {
    let zones = objectives::zones_of_style(style);
    let (z1, z2) = (zone_rect(style, "1"), zone_rect(style, "2"));
    let (hx, hz) = ((table_w_in / 2.0) as i64 - objectives::EDGE_MARGIN_IN, (table_d_in / 2.0) as i64 - objectives::EDGE_MARGIN_IN);
    let (first, second) = canonical(a, b);
    let ctx = SearchCtx {
        hx, hz, zones, cells, z1, z2, first, second,
        lab_a: Summary::of_profiles(first).label(), lab_b: Summary::of_profiles(second).label(),
    };
    let mut placed: Vec<(i64, i64)> = Vec::new();
    let mut swept = 0usize;
    while placed.len() < count {
        let (_, path) = search_node(&ctx, placed.len(), count, &placed);
        if path.is_empty() {
            match objectives::sweep(hx, hz, &placed, &ctx.zones, cells) {
                Some(c) => { placed.push(c); swept += 1; }
                None => break,
            }
        } else {
            placed.extend(path);
        }
    }
    Placed { cells: placed, swept }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    /// Pinned fixture, schema exactly as battle_sim._unit_profile stamps it
    /// (list_to_profile.py:1015-1059): a two-unit shooting army.
    const SHOOTY: &str = r#"{
        "p1_0_inf": {"unit_id": "p1_0_inf", "name": "Line Infantry",
            "quality": 4, "defense": 4, "tough": 1,
            "wounds_max": [1, 1, 1, 1, 1], "model_count": 5,
            "weapons": [
                {"name": "Rifle", "range": 30, "attacks": 2, "count": 1, "ap": 1, "rules": []},
                {"name": "Carbine", "range": 18, "attacks": 1, "count": 2, "ap": 0, "rules": []}],
            "special_rules": [], "caster_value": 0,
            "move_bands": {"advance": 6.0, "rush": 12.0},
            "base_radius": 0.016, "game_system": "gf", "faction_folder": "gf_test",
            "item_grants": [], "attached_hero_rules": [],
            "shooting_range_bonus": 0, "max_activation_advance_bonus_in": 0.0},
        "p1_1_walker": {"unit_id": "p1_1_walker", "name": "Heavy Walker",
            "quality": 4, "defense": 4, "tough": 6, "wounds_max": [6],
            "model_count": 1,
            "weapons": [
                {"name": "Cannon", "range": 24, "attacks": 6, "count": 1, "ap": 2, "rules": []}],
            "special_rules": [], "caster_value": 0,
            "move_bands": {"advance": 6.0, "rush": 12.0},
            "base_radius": 0.025, "game_system": "gf", "faction_folder": "gf_test",
            "item_grants": [], "attached_hero_rules": [],
            "shooting_range_bonus": 0, "max_activation_advance_bonus_in": 0.0}
    }"#;

    #[test]
    fn summary_fields_on_pinned_fixture() {
        let s = Summary::of_profiles(&serde_json::from_str(SHOOTY).unwrap());
        assert_eq!(s.shots_far, 8); // 2x1 @30" + 6x1 @24"
        assert_eq!(s.shots_mid, 2); // 1x2 @18"
        assert_eq!(s.advance_x2, 12); // (6+6)/2 = 6
        assert_eq!(s.rush_x2, 24);
        assert_eq!(s.wounds_total, 11); // 5x1 + 6
        assert_eq!(s.models, 6);
        assert_eq!(s.tough_mean_x2, 7); // (1+6)/2 = 3.5, x2 exact
    }

    #[test]
    fn label_shooting_on_pinned_fixture() {
        let s = Summary::of_profiles(&serde_json::from_str(SHOOTY).unwrap());
        assert_eq!(s.label(), StyleLabel::Shooting);
    }

    #[test]
    fn label_fast_army() {
        let army = json!({
            "u1": {"model_count": 3, "wounds_max": [1, 1, 1], "tough": 1,
                   "weapons": [], "move_bands": {"advance": 12.0, "rush": 24.0}},
            "u2": {"model_count": 3, "wounds_max": [1, 1, 1], "tough": 1,
                   "weapons": [], "move_bands": {"advance": 12.0, "rush": 24.0}}
        });
        assert_eq!(Summary::of_profiles(&army).label(), StyleLabel::Fast);
    }

    #[test]
    fn label_tough_army() {
        let army = json!({
            "u1": {"model_count": 4, "wounds_max": [6, 6, 6, 6], "tough": 6,
                   "weapons": [{"range": 12, "attacks": 1, "count": 1}],
                   "move_bands": {"advance": 4.0, "rush": 8.0}},
            "u2": {"model_count": 4, "wounds_max": [6, 6, 6, 6], "tough": 6,
                   "weapons": [{"range": 12, "attacks": 1, "count": 1}],
                   "move_bands": {"advance": 4.0, "rush": 8.0}}
        });
        assert_eq!(Summary::of_profiles(&army).label(), StyleLabel::Tough);
    }

    #[test]
    fn ties_resolve_in_fixed_order() {
        let all_zero = Summary { models: 5, ..Default::default() };
        assert_eq!(all_zero.label(), StyleLabel::Shooting);
        // fast == tough > shooting -> Fast (the earlier arm wins ties).
        let tie = Summary {
            advance_x2: 16,
            rush_x2: 32,
            wounds_total: 16,
            models: 4,
            tough_mean_x2: 8,
            ..Default::default()
        };
        assert_eq!(tie.label(), StyleLabel::Fast);
    }

    #[test]
    fn empty_and_missing_fields_answer_zero() {
        assert_eq!(Summary::of_profiles(&json!({})), Summary::default());
        assert_eq!(Summary::of_profiles(&json!({})).label(), StyleLabel::Shooting);
        let sparse = Summary::of_profiles(&json!({"u": {}}));
        assert_eq!(sparse.models, 0);
        assert_eq!(sparse.shots_far, 0);
    }

    #[test]
    fn mode_strings_roundtrip() {
        for (m, word) in [
            (Mode::Random, "random"),
            (Mode::Style, "style"),
            (Mode::Search, "search"),
        ] {
            assert_eq!(m.as_str(), word);
            assert_eq!(Mode::of_str(word), Some(m));
        }
        assert_eq!(Mode::of_str("aggressive"), None);
    }

    /// objective_gate.py:53-58 front-line bands; x spans the hx = 33 lattice.
    fn front_line_zones() -> (Zone, Zone) {
        (
            Zone { x_min: -33.0, x_max: 33.0, z_min: -24.0, z_max: -12.0 },
            Zone { x_min: -33.0, x_max: 33.0, z_min: 12.0, z_max: 24.0 },
        )
    }

    #[test]
    fn mirrored_armies_edge_scores_complementary() {
        let a: Value = serde_json::from_str(SHOOTY).unwrap();
        let b: Value = serde_json::from_str(&SHOOTY.replace("p1_", "p2_")).unwrap();
        let (z1, z2) = front_line_zones();
        // Owner-0 marker set, z-symmetric so the mirrored armies must tie.
        let m = [
            [0.0, 0.0, 0.0],
            [-10.0, 0.0, 5.0],
            [-10.0, 0.0, -5.0],
            [10.0, 0.0, 5.0],
            [10.0, 0.0, -5.0],
        ];
        let s1 = synth_state(&a, &b, &z1, &z2, &m);
        let s2 = synth_state(&b, &a, &z1, &z2, &m);
        let a1 = score::score(&s1, 1, score::NO_INCOMING);
        let b1 = score::score(&s1, 2, score::NO_INCOMING);
        let a2 = score::score(&s2, 2, score::NO_INCOMING);
        let b2 = score::score(&s2, 1, score::NO_INCOMING);
        // Design 3: the hand eval is complementary per state.
        assert!((a1 + b1 - 1.0).abs() < 1e-9, "a1+b1 = {}", a1 + b1);
        assert!((a2 + b2 - 1.0).abs() < 1e-9, "a2+b2 = {}", a2 + b2);
        // Identical armies on mirrored zones over a z-symmetric set: dead even.
        assert!((a1 - 0.5).abs() < 1e-9 && (a2 - 0.5).abs() < 1e-9, "a1 = {a1}, a2 = {a2}");
        // edge_scores exposes exactly (a1, a2).
        let (e1, e2) = edge_scores(&a, &b, &z1, &z2, &m);
        assert_eq!(e1, a1);
        assert_eq!(e2, a2);
        // The identity: v_X = min over the two edges, v_A + v_B = 1 - |a1 - a2|.
        let (v_a, v_b) = (a1.min(a2), b1.min(b2));
        assert!((v_a + v_b - (1.0 - (a1 - a2).abs())).abs() < 1e-9);
    }

    /// A fast-labelled army with slow feet (no guns, advance 6 / rush 12 —
    /// still label Fast by the signature): the spread preference's unguarded
    /// first pick is the z-edge corner (-33, -9), which an army this slow
    /// cannot hold from the far edge — that edge bias is the fairness test's
    /// tooth; a rush-24 army would hold it from both edges and stay fair.
    const SLOWY: &str = r#"{
        "p1_0_spears": {"unit_id": "p1_0_spears", "name": "Spear Line", "quality": 4, "defense": 4,
            "tough": 1, "wounds_max": [1, 1, 1], "model_count": 3, "weapons": [],
            "special_rules": [], "caster_value": 0, "move_bands": {"advance": 6.0, "rush": 12.0},
            "base_radius": 0.016, "game_system": "gf", "faction_folder": "gf_test",
            "item_grants": [], "attached_hero_rules": [], "shooting_range_bonus": 0,
            "max_activation_advance_bonus_in": 0.0},
        "p1_1_spears": {"unit_id": "p1_1_spears", "name": "Spear Screen", "quality": 4, "defense": 4,
            "tough": 1, "wounds_max": [1, 1, 1], "model_count": 3, "weapons": [],
            "special_rules": [], "caster_value": 0, "move_bands": {"advance": 6.0, "rush": 12.0},
            "base_radius": 0.016, "game_system": "gf", "faction_folder": "gf_test",
            "item_grants": [], "attached_hero_rules": [], "shooting_range_bonus": 0,
            "max_activation_advance_bonus_in": 0.0}
    }"#;

    /// objective_gate.py:53-58 front-line bands, full-width rectangles in inches.
    fn front_line_style() -> Value {
        json!({"zones": {
            "1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
            "2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]]
        }})
    }

    fn place(a: &str, b: &str, count: usize) -> Placed {
        let cells = crate::objectives::Cells::from_pairs(&[], 24);
        place_style(&serde_json::from_str(a).unwrap(), &serde_json::from_str(b).unwrap(), &front_line_style(), &cells, count, 72.0, 48.0)
    }

    /// The same roster under the other seat's key prefix (step 2's trick).
    fn mirror(s: &str) -> String { s.replace("p1_", "p2_") }

    #[test]
    fn style_output_is_legal() {
        use crate::objectives::{is_legal, zones_of_style};
        let (zones, cells) = (zones_of_style(&front_line_style()), crate::objectives::Cells::from_pairs(&[], 24));
        let b = mirror(SLOWY);
        for (a, b, count) in [(SLOWY, b.as_str(), 3), (SLOWY, SHOOTY, 5)] {
            let p = place(a, b, count);
            assert_eq!(p.cells.len(), count);
            assert_eq!(p.swept, 0, "no sweep expected on open terrain");
            for (i, c) in p.cells.iter().enumerate() {
                let others: Vec<(i64, i64)> = p.cells.iter().enumerate().filter(|(j, _)| *j != i).map(|(_, c)| *c).collect();
                assert!(is_legal(c.0, c.1, &others, &zones, &cells), "cell {c:?} illegal");
            }
        }
    }

    #[test]
    fn style_placement_is_deterministic() {
        let b = mirror(SLOWY);
        assert_eq!(place(SLOWY, &b, 5), place(SLOWY, &b, 5));
    }

    #[test]
    fn style_symmetric_in_army_order() {
        let b = mirror(SLOWY);
        assert_eq!(place(SLOWY, &b, 3).cells, place(&b, SLOWY, 3).cells);
        // distinct armies: canonical roster order, not seat order, drives plies
        assert_eq!(place(SLOWY, SHOOTY, 3).cells, place(SHOOTY, SLOWY, 3).cells);
    }

    /// The guard's property on the output; RED tooth — bypassing the guard
    /// makes the count-1 fast opening the z-edge corner (-33, -9) and this
    /// assertion fails on |a1 - a2| > FAIRNESS_EPS.
    #[test]
    fn style_output_respects_edge_fairness() {
        let b = mirror(SLOWY);
        let (z1, z2) = (zone_rect(&front_line_style(), "1"), zone_rect(&front_line_style(), "2"));
        for count in [1, 3] {
            let p = place(SLOWY, &b, count);
            assert_eq!(p.swept, 0);
            let m: Vec<[f64; 3]> = p.cells.iter().map(|&(x, z)| [x as f64, 0.0, z as f64]).collect();
            let (a1, a2) = edge_scores(&serde_json::from_str(SLOWY).unwrap(), &serde_json::from_str(&b).unwrap(), &z1, &z2, &m);
            assert!((a1 - a2).abs() <= FAIRNESS_EPS, "count {count}: |a1 - a2| = {}", (a1 - a2).abs());
        }
    }

    fn place_s(a: &str, b: &str, count: usize) -> Placed {
        let cells = crate::objectives::Cells::from_pairs(&[], 24);
        place_search(&serde_json::from_str(a).unwrap(), &serde_json::from_str(b).unwrap(), &front_line_style(), &cells, count, 72.0, 48.0)
    }

    #[test]
    fn search_output_is_legal_and_capped_at_five() {
        use crate::objectives::{is_legal, zones_of_style};
        let (zones, cells) = (zones_of_style(&front_line_style()), crate::objectives::Cells::from_pairs(&[], 24));
        let b = mirror(SLOWY);
        for count in [3, 5] {
            let p = place_s(SLOWY, &b, count);
            assert_eq!(p.cells.len(), count, "open terrain places every marker");
            assert!(p.cells.len() <= 5);
            assert_eq!(p.swept, 0, "no sweep expected on open terrain");
            for (i, c) in p.cells.iter().enumerate() {
                let others: Vec<(i64, i64)> = p.cells.iter().enumerate().filter(|(j, _)| *j != i).map(|(_, c)| *c).collect();
                assert!(is_legal(c.0, c.1, &others, &zones, &cells), "cell {c:?} illegal");
            }
        }
    }

    #[test]
    fn search_placement_is_deterministic_and_seat_blind() {
        let b = mirror(SLOWY);
        assert_eq!(place_s(SLOWY, &b, 3), place_s(SLOWY, &b, 3));
        assert_eq!(place_s(SLOWY, &b, 5), place_s(SLOWY, &b, 5));
        // Canonical roster order, not seat order, drives the plies.
        assert_eq!(place_s(SLOWY, &b, 3).cells, place_s(&b, SLOWY, 3).cells);
        assert_eq!(place_s(SLOWY, SHOOTY, 3).cells, place_s(SHOOTY, SLOWY, 3).cells);
    }

    /// One-unit army for constructing asymmetric pairs: model_count models of
    /// `wounds` wounds each, no guns, the given move bands.
    fn army_json(prefix: &str, models: i64, wounds: i64, adv: f64, rush: f64) -> String {
        let ws: Vec<String> = (0..models).map(|_| wounds.to_string()).collect();
        format!(r#"{{"{p}_0_h": {{"unit_id": "{p}_0_h", "name": "Horde", "quality": 4, "defense": 4, "tough": 1,
            "wounds_max": [{ws}], "model_count": {m}, "weapons": [], "special_rules": [], "caster_value": 0,
            "move_bands": {{"advance": {a}, "rush": {r}}}, "base_radius": 0.025, "game_system": "gf", "faction_folder": "gf_test",
            "item_grants": [], "attached_hero_rules": [], "shooting_range_bonus": 0, "max_activation_advance_bonus_in": 0.0}}}}"#,
            p = prefix, ws = ws.join(","), m = models, a = adv, r = rush)
    }

    /// The RED tooth (design 7 step 4): a constructed asymmetric pair on which
    /// the in-expansion guard demonstrably prunes. Probe-verified: bypassing
    /// the guard flips the argmax line to the z-edge-hugging sets — count 2 =
    /// [(0, 0), (33, -9)], count 3 = [(-3, -3), (33, 9), (-6, 6)] — so these
    /// pinned guarded outputs fail the moment the guard is removed. (For a
    /// MIRRORED pair that flip is impossible: v_first = v_second =
    /// (1 - |a1 - a2|)/2 at every leaf makes the unguarded maximin argmax
    /// itself the guard — see the mirrored fairness test above.)
    #[test]
    fn search_guard_prunes_the_edge_hugging_line() {
        let a = army_json("p1", 3, 2, 6.0, 12.0);
        let b = army_json("p2", 2, 4, 4.0, 8.0);
        assert_eq!(place_s(&a, &b, 2).cells, vec![(3, 0), (-33, 0)]);
        assert_eq!(place_s(&a, &b, 3).cells, vec![(3, 0), (-33, 0), (-6, -3)]);
    }

    /// The guard's property on the search output — the RED tooth: for a
    /// MIRRORED pair v_first = v_second = (1 - |a1 - a2|)/2 at every leaf, so
    /// the unguarded maximin argmax is itself the guard and this stays green;
    /// the guard-during-expansion RED therefore lives on the ASYMMETRIC pair
    /// (`search_output_respects_edge_fairness`).
    #[test]
    fn search_output_respects_edge_fairness_mirrored() {
        let b = mirror(SLOWY);
        let (z1, z2) = (zone_rect(&front_line_style(), "1"), zone_rect(&front_line_style(), "2"));
        for count in [1, 3, 5] {
            let p = place_s(SLOWY, &b, count);
            assert_eq!(p.swept, 0);
            let m: Vec<[f64; 3]> = p.cells.iter().map(|&(x, z)| [x as f64, 0.0, z as f64]).collect();
            let (a1, a2) = edge_scores(&serde_json::from_str(SLOWY).unwrap(), &serde_json::from_str(&b).unwrap(), &z1, &z2, &m);
            assert!((a1 - a2).abs() <= FAIRNESS_EPS, "count {count}: |a1 - a2| = {}", (a1 - a2).abs());
        }
    }
}

