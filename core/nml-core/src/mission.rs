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
use crate::{CONTROL_EPS, OBJECTIVE_CONTROL_IN};

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
