//! The REFEREE's round end — the four `BattleSim` helpers `AiPlanner.
//! _imagined_round_end` (ai_planner.gd:355-380) calls, so an imagined boundary
//! books the same round end the real game books:
//! `playout_seize` (battle_sim.gd:268-292), `apply_destroy_step` (:405-423),
//! `vp_round_add` (:329-334), `vp_end_bonus` (:337-348) and `vp_score_round`
//! (:358-395).
//!
//! Two things here are order-dependent and both are reproduced verbatim:
//! objectives are walked in LIST order and units in CAPTURE order, and the
//! `sides` set of `playout_seize` is an insertion-ordered set whose SIZE (1 =
//! seized, >1 = neutral, 0 = the owner keeps it) is the whole decision.
//!
//! `control_gap_in` and `can_hold_marker` are not re-ported: `score.rs` already
//! carries them, and the referee and the eval MUST measure a marker the same way
//! (HEAD_QUEUE #12/#13, battle_sim.gd:294-302).

use serde_json::Value;

use crate::score::{can_hold_marker, control_gap_in};
use crate::state::{Marker, State};
use crate::{CONTROL_EPS, IN2M, OBJECTIVE_CONTROL_IN};

/// GDScript `int(Variant)` for the two places a recorded number reaches this
/// file: a JSON integer, or a float that `int()` truncates toward zero.
fn gd_int(v: &Value) -> i64 {
    if let Some(i) = v.as_i64() {
        return i;
    }
    v.as_f64().map(|f| f as i64).unwrap_or(0)
}

fn str_of<'a>(flavour: &'a Value, key: &str, fallback: &'a str) -> &'a str {
    flavour.get(key).and_then(|v| v.as_str()).unwrap_or(fallback)
}

/// `BattleSim.playout_seize` battle_sim.gd:268-292 — SIDES PRESENT, not bodies
/// present: one side within the 3" ring seizes the marker, both sides make it
/// NEUTRAL, nobody near leaves the owner as it was. Writes the verdict into
/// BOTH `owners` and the state's objective dicts, because the eval reads the
/// objectives and the VP scorer reads `owners`.
pub fn playout_seize(state: &mut State, owners: &mut [i64]) {
    let round_no = state.round;
    for i in 0..state.objectives.len() {
        if let Some(mk) = state.markers_meta.get(i) {
            if mk.carry && mk.carried_by >= 0 {
                let k = mk.carried_by as usize;
                if k < state.units() && state.alive[k] > 0 && !state.shaken[k] {
                    if i < owners.len() {
                        owners[i] = state.player[k];
                        state.objectives[i].owner = owners[i];
                    }
                    continue;
                }
            }
        }
        let op = state.objectives[i].pos;
        // An insertion-ordered SET of player ids — a `Vec` is the honest shape:
        // it never holds more than two entries and only its size is read.
        let mut sides: Vec<i64> = Vec::new();
        for k in 0..state.units() {
            if !can_hold_marker(state, k, round_no) {
                continue;
            }
            let pid = state.player[k];
            if sides.contains(&pid) {
                continue;
            }
            if control_gap_in(state, k, op) <= OBJECTIVE_CONTROL_IN + CONTROL_EPS {
                sides.push(pid);
            }
        }
        if i < owners.len() {
            if sides.len() == 1 {
                owners[i] = sides[0];
            } else if sides.len() > 1 {
                owners[i] = 0;
            }
            state.objectives[i].owner = owners[i];
        }
    }
}

/// Pick up each newly seized relic with the closest eligible unit; capture order breaks ties.
pub fn apply_carry_step(state: &mut State, owners: &[i64]) {
    for (i, &side) in owners.iter().enumerate().take(state.markers_meta.len().min(state.objectives.len())) {
        if !state.markers_meta[i].carry || state.markers_meta[i].carried_by != -1 {
            continue;
        }
        if side != 1 && side != 2 { continue; }
        let op = state.objectives[i].pos;
        let mut best = None;
        let mut best_gap = f64::INFINITY;
        for k in 0..state.units() {
            if state.player[k] != side || !can_hold_marker(state, k, state.round) { continue; }
            let gap = control_gap_in(state, k, op);
            if gap < best_gap {
                best = Some(k);
                best_gap = gap;
            }
        }
        if let Some(k) = best {
            state.markers_meta[i].carried_by = k as i64;
            if let Some(&p) = state.positions[k].first() { state.objectives[i].pos = p; }
        }
    }
}

/// Drop every relic held by a unit past its first base edge toward the nearest living opposing model,
/// measured horizontally (plan amendment M-C1): 1 inch, or the marker's own `drop_in` (D14.5, Rescue: 6").
/// The distance is the FIRST held marker's, one drop point serves them all.
pub fn drop_carried(state: &mut State, unit: usize) {
    if unit >= state.units() { return; }
    if !state.markers_meta.iter().any(|m| m.carry && m.carried_by == unit as i64) { return; }
    let Some(&centre) = state.positions[unit].first() else { return; };
    let mut direction = [1.0, 0.0];
    let mut closest = f64::INFINITY;
    for enemy in 0..state.units() {
        if state.player[enemy] == state.player[unit] || state.alive[enemy] <= 0 { continue; }
        for p in state.positions[enemy].iter().take(state.alive[enemy] as usize) {
            let dx = p[0] - centre[0];
            let dz = p[2] - centre[2];
            let d2 = dx * dx + dz * dz;
            if d2 < closest && d2 > 0.000001 {
                closest = d2;
                let d = d2.sqrt();
                direction = [dx / d, dz / d];
            }
        }
    }
    let radius = state.radii[unit].first().copied().unwrap_or(0.016);
    let drop_in = state.markers_meta.iter().find(|m| m.carry && m.carried_by == unit as i64).map_or(0.0, |m| m.drop_in);
    let distance = radius + if drop_in > 0.0 { drop_in } else { 1.0 } * crate::IN2M;
    let point = [centre[0] + direction[0] * distance, centre[1], centre[2] + direction[1] * distance];
    for i in 0..state.markers_meta.len() {
        if state.markers_meta[i].carry && state.markers_meta[i].carried_by == unit as i64 {
            state.markers_meta[i].carried_by = -1;
            if i < state.objectives.len() { state.objectives[i].pos = point; }
        }
    }
}

/// Keep each held marker at its carrier's first living model after a resolve.
pub fn sync_carried_positions(state: &mut State) {
    for i in 0..state.markers_meta.len().min(state.objectives.len()) {
        let mk = &state.markers_meta[i];
        if !mk.carry || mk.carried_by < 0 { continue; }
        let k = mk.carried_by as usize;
        if let Some(&p) = state.positions.get(k).and_then(|ps| ps.first()) {
            state.objectives[i].pos = p;
        }
    }
}

/// `BattleSim.apply_destroy_step` battle_sim.gd:405-423 — an owned destructible
/// marker the ENEMY alone holds at a round end falls on the spot and never
/// scores again; `owners[i]` is zeroed so no later scorer counts a ghost.
///
/// `seq` is the state's shared one-element counter. An EMPTY vector is the case
/// `BattleSim.clone_state` (:523) cannot produce — it only writes `destroy_seq`
/// alongside `markers_meta` — so it is seeded here rather than panicking.
pub fn apply_destroy_step(markers: &mut [Marker], owners: &mut [i64], seq: &mut Vec<i64>) {
    for i in 0..markers.len() {
        if !markers[i].destructible || markers[i].destroyed {
            continue;
        }
        let owner_side = markers[i].owned_by;
        if owner_side <= 0 || i >= owners.len() {
            continue;
        }
        if owners[i] == 3 - owner_side {
            markers[i].destroyed = true;
            if seq.is_empty() {
                seq.push(0);
            }
            seq[0] += 1;
            markers[i].destroyed_seq = seq[0];
            owners[i] = 0;
        }
    }
}

/// `BattleSim.vp_round_add` battle_sim.gd:329-334 — 1 VP per controlled marker.
pub fn vp_round_add(owners: &[i64], vp: &mut [i64; 2]) {
    for &o in owners {
        if o == 1 {
            vp[0] += 1;
        } else if o == 2 {
            vp[1] += 1;
        }
    }
}

/// `BattleSim.vp_end_bonus` battle_sim.gd:337-348 — +1 VP for holding MORE
/// markers; an exact tie pays nobody.
pub fn vp_end_bonus(owners: &[i64], vp: &mut [i64; 2]) {
    let (mut m1, mut m2) = (0i64, 0i64);
    for &o in owners {
        if o == 1 {
            m1 += 1;
        } else if o == 2 {
            m2 += 1;
        }
    }
    if m1 > m2 {
        vp[0] += 1;
    } else if m2 > m1 {
        vp[1] += 1;
    }
}

/// `BattleSim.vp_score_round` battle_sim.gd:358-395 — one entry point for every
/// `round_vp` mission flavour. An ABSENT flavour is the v1 rule: 1 VP per
/// marker, the majority bonus deferred to game end, no first-seize bounty.
pub fn vp_score_round(
    owners: &[i64],
    vp: &mut [i64; 2],
    flavour: &Value,
    memo: &mut serde_json::Map<String, Value>,
    markers: &[Marker],
) {
    if str_of(flavour, "mode", "") == "demolition" {
        // Demolition: 1 VP per round while the OWN marker stands; once both are
        // gone, the side whose marker fell FIRST collects from that round on.
        for side in [1i64, 2] {
            let mut own_alive = false;
            let mut own_seq = 0i64;
            let mut enemy_destroyed = false;
            let mut enemy_seq = 0i64;
            for mk in markers {
                if mk.owned_by == side {
                    own_alive = !mk.destroyed;
                    own_seq = mk.destroyed_seq;
                } else if mk.owned_by == 3 - side {
                    enemy_destroyed = mk.destroyed;
                    enemy_seq = mk.destroyed_seq;
                }
            }
            if own_alive {
                vp[(side - 1) as usize] += 1;
            } else if enemy_destroyed && own_seq < enemy_seq {
                vp[(side - 1) as usize] += 1;
            }
        }
        return;
    }
    vp_round_add(owners, vp);
    if str_of(flavour, "majority", "end") == "round" {
        vp_end_bonus(owners, vp);
    }
    let first_seize = flavour.get("first_seize").and_then(|v| v.as_bool()).unwrap_or(false);
    let claimed = memo.get("first_seizer").map(gd_int).unwrap_or(0);
    if first_seize && claimed == 0 {
        for &o in owners {
            if o == 1 || o == 2 {
                memo.insert("first_seizer".to_string(), Value::from(o));
                vp[(o - 1) as usize] += 1;
                break;
            }
        }
    }
}

/// Reads a recorded `vp` blob back as the two-slot ledger. Anything that is not
/// a two-element array is `[0, 0]` — `_imagined_round_end`'s own guard
/// (ai_planner.gd:369-372).
pub fn vp_of(v: Option<&Value>) -> [i64; 2] {
    match v.and_then(|v| v.as_array()) {
        Some(a) if a.len() == 2 => [gd_int(&a[0]), gd_int(&a[1])],
        _ => [0, 0],
    }
}

/// `BattleSim.vp_score_end` battle_sim.gd:395-397 — the book's game-end bonus,
/// paid only when the flavour defers the majority to the END (the default).
pub fn vp_score_end(owners: &[i64], vp: &mut [i64; 2], flavour: &Value) {
    if str_of(flavour, "majority", "end") == "end" {
        vp_end_bonus(owners, vp);
    }
}

/// `BattleSim.sabotage_winner` battle_sim.gd:428-440 — you win by destroying
/// THEIR marker whilst keeping YOURS; anything else is a draw.
///
/// The GDScript walks a `{1: false, 2: false}` dictionary and OVERWRITES the
/// entry per marker, so with several markers on a side the LAST one decides.
/// That is mirrored, not corrected.
pub fn sabotage_winner(markers: &[Marker]) -> &'static str {
    let mut alive = [false, false];
    for mk in markers {
        let side = mk.owned_by;
        if side == 1 || side == 2 {
            alive[(side - 1) as usize] = !mk.destroyed;
        }
    }
    if alive[0] && !alive[1] {
        return "p1";
    }
    if alive[1] && !alive[0] {
        return "p2";
    }
    "draw"
}

/// `BattleSim.mission_winner` battle_sim.gd:450-471 — THE end-of-game referee,
/// branch order intact: sabotage by its own verdict, a progressive mission by
/// the `round_vp` ledger, every other mission by markers held, and a board with
/// NO markers at all by surviving models.
pub fn mission_winner(
    scoring: &str,
    owners: &[i64],
    vp: [i64; 2],
    markers: &[Marker],
    alive1: i64,
    alive2: i64,
) -> &'static str {
    if scoring == "sabotage" {
        return sabotage_winner(markers);
    }
    if scoring == "round_vp" {
        return if vp[0] != vp[1] {
            if vp[0] > vp[1] {
                "p1"
            } else {
                "p2"
            }
        } else {
            "draw"
        };
    }
    let (mut p1, mut p2) = (0i64, 0i64);
    for &o in owners {
        if o == 1 {
            p1 += 1;
        } else if o == 2 {
            p2 += 1;
        }
    }
    if p1 != p2 {
        return if p1 > p2 { "p1" } else { "p2" };
    }
    if owners.is_empty() && alive1 != alive2 {
        return if alive1 > alive2 { "p1" } else { "p2" };
    }
    "draw"
}

/// R11a: a marker's horizontal point in inches — a CARRIED marker sits at its
/// carrier's first model, less that model's base radius (the carrier's nearest
/// base edge, the same measure as `control_gap_in`); a free one at its spot.
pub(crate) fn marker_point_in(state: &State, i: usize) -> Option<([f64; 2], f64)> {
    let mk = state.markers_meta.get(i)?;
    if mk.destroyed {
        return None;
    }
    if mk.carry && mk.carried_by >= 0 {
        let k = mk.carried_by as usize;
        let p = *state.positions.get(k)?.first()?;
        let r = state.radii.get(k).and_then(|rs| rs.first()).copied().unwrap_or(0.0);
        return Some(([p[0] / IN2M, p[2] / IN2M], r / IN2M));
    }
    let p = state.objectives.get(i)?.pos;
    Some(([p[0] / IN2M, p[2] / IN2M], 0.0))
}

/// Attack & Defend VIP verdict: a marker within 6" of the edge OPPOSITE the
/// one the defender deployed on (`deploy_edge` = the z sign of that edge,
/// +1/-1) means the defender wins, otherwise the attacker. No roles = draw.
pub fn escort_winner(state: &State, deploy_edge: i64, table_d_in: f64) -> &'static str {
    let att = state.attacker;
    if (att != 1 && att != 2) || deploy_edge == 0 {
        return "draw";
    }
    let target = -(deploy_edge.signum() as f64);
    let home = (0..state.markers_meta.len()).filter_map(|i| marker_point_in(state, i)).any(
        |(p, r)| table_d_in / 2.0 - target * p[1] - r <= 6.0 + CONTROL_EPS,
    );
    if home { if att == 1 { "p2" } else { "p1" } } else if att == 1 { "p1" } else { "p2" }
}

/// Smash & Grab / Rescue verdict: a marker within 6" of ANY table edge means
/// the attacker wins, otherwise the defender. No roles = draw.
pub fn extract_winner(state: &State, table_w_in: f64, table_d_in: f64) -> &'static str {
    let att = state.attacker;
    if att != 1 && att != 2 {
        return "draw";
    }
    let out = (0..state.markers_meta.len()).filter_map(|i| marker_point_in(state, i)).any(|(p, r)| {
        let gap = (table_w_in / 2.0 - p[0].abs()).min(table_d_in / 2.0 - p[1].abs()) - r;
        gap <= 6.0 + CONTROL_EPS
    });
    if out == (att == 1) { "p1" } else { "p2" }
}

/// The `escort` / `extract` scoring ids of `BattleSim.mission_winner`; `None`
/// for every other id, which keeps its own referee.
pub fn role_winner(scoring: &str, state: &State, deploy_edge: i64, table_w_in: f64, table_d_in: f64) -> Option<&'static str> {
    match scoring {
        "escort" => Some(escort_winner(state, deploy_edge, table_d_in)),
        "extract" => Some(extract_winner(state, table_w_in, table_d_in)),
        _ => None,
    }
}

/// D10b (R10a): the z a VIP marker walks to — straight toward the edge OPPOSITE
/// `deploy_edge` (its z sign), up to 12", stopping 6" short of that edge; x is
/// untouched. A marker already inside the 6" stays. The twin of
/// `SoloController.vip_walk_z`.
pub fn vip_walk_z(z_in: f64, deploy_edge: i64, depth_in: f64) -> f64 {
    let dir = -(deploy_edge.signum() as f64);
    let to_stop = (depth_in / 2.0 - 6.0) * dir - z_in;
    z_in + dir * (to_stop * dir).clamp(0.0, 12.0)
}

/// D10b: the round-START move of every mobile marker the DEFENDER (`3 - attacker`)
/// controls, before any activation. No roles, no table depth or no deploy edge = no move.
pub fn apply_marker_move(state: &mut State, table_d_in: f64) {
    let att = state.attacker;
    if (att != 1 && att != 2) || table_d_in <= 0.0 {
        return;
    }
    for i in 0..state.markers_meta.len().min(state.objectives.len()) {
        let mk = &state.markers_meta[i];
        if !mk.mobile || mk.destroyed || mk.deploy_edge == 0 || state.objectives[i].owner != 3 - att {
            continue;
        }
        let z_in = state.objectives[i].pos[2] / IN2M;
        state.objectives[i].pos[2] = vip_walk_z(z_in, mk.deploy_edge, table_d_in) * IN2M;
    }
}

/// One secret marker turned up by `apply_reveal_step`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Reveal {
    pub index: usize,
    pub secret: String,
    pub unit: usize,
}

/// D12b — the round-end reveal, the twin of `SoloController.secret_reveal_step` plus the trap's
/// dice. Every unrevealed secret marker the ATTACKER holds (`owners`) is turned up by its nearest
/// eligible attacker unit (`can_hold_marker`, strict `<` in capture order): a relic stays (the carry
/// step picks it up next); a trap or an empty marker is removed (`destroyed`, owner zeroed). A trap
/// then hits the revealing unit: one tray die, D6+1 hits, saved on the same tray and landed. Without
/// a tray (expected-value dice) the trap costs nothing — the tray path only, like Mend.
pub fn apply_reveal_step(
    statics: &[crate::unit::UnitStatic],
    state: &mut State,
    owners: &mut [i64],
    mut tray: Option<&mut crate::dice::Tray>,
) -> (Vec<Reveal>, Vec<crate::dice::Roll>) {
    let att = state.attacker;
    let (mut events, mut rolls) = (Vec::new(), Vec::new());
    if att != 1 && att != 2 {
        return (events, rolls);
    }
    for i in 0..state.markers_meta.len().min(state.objectives.len()) {
        let mk = &state.markers_meta[i];
        let Some(kind) = mk.secret.clone() else { continue };
        if mk.revealed || mk.destroyed || owners.get(i).copied() != Some(att) {
            continue;
        }
        let obj = state.objectives[i].pos;
        let mut best: Option<(usize, f64)> = None;
        for k in 0..state.units() {
            if state.player[k] != att || !can_hold_marker(state, k, state.round) {
                continue;
            }
            let gap = control_gap_in(state, k, obj);
            if best.map_or(true, |(_, g)| gap < g) {
                best = Some((k, gap));
            }
        }
        let Some((unit, _)) = best else { continue };
        state.markers_meta[i].revealed = true;
        if kind != "relic" {
            state.markers_meta[i].destroyed = true;
            owners[i] = 0;
        }
        events.push(Reveal { index: i, secret: kind.clone(), unit });
        if kind != "trap" {
            continue;
        }
        let Some(t) = tray.as_deref_mut() else { continue };
        let die = t.roll(1);
        let hits = i64::from(die[0]) + 1;
        let us = &statics[state.roster.profile[unit]];
        rolls.push(crate::dice::Roll { kind: "attack", count: 1, target: 1, faces: die, owner: us.name.to_string() });
        let def = crate::sim::ctx_of(us, state, unit);
        let out = crate::dice::resolve_storm_hits_with_tray(hits, 0, false, false, &def, &us.name, t);
        rolls.extend(out.rolls.iter().cloned());
        crate::sim::land_wounds(state, unit, out.wounds);
    }
    (events, rolls)
}
