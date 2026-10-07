//! The HAND mission score, ported line by line from
//! `AiMissionEval.score/_score_hand/_objective_p/_presence`
//! (scripts/solo/ai_mission_eval.gd:344-422 and :586-617) plus the two
//! `BattleSim` helpers it calls: `control_gap_in` (:277-292) and
//! `can_hold_marker` (:297-302).
//!
//! Operation order matters and is reproduced verbatim: units accumulate in
//! CAPTURE order into two separate sums (`mine`, `theirs`), objectives
//! accumulate in list order into `total`, wounds accumulate in array order.
//!
//! `AiMissionEval.fit_mode` (:324) selects the E4.2 BLEND instead — see
//! `score_with`, whose fitted half lives in `fitted.rs` (NML-1142). `score()`
//! is that call with no net, i.e. `fit_mode == false`.

use crate::fitted::{FitMode, Fitted};
use crate::mission::vp_of;
use crate::state::State;
use crate::unit::UnitStatic;
use crate::{CONTROL_EPS, DESTROY_DEFENCE_WEIGHT, DISCOUNT, IN2M, OBJECTIVE_CONTROL_IN};

/// `incoming` (ai_mission_eval.gd:344) — expected reply wounds per unit, indexed
/// by CAPTURE order instead of by key. An empty slice is the GDScript `{}`
/// default: `incoming.get(str(key), 0.0)` reads 0 for every unit.
pub type Incoming<'a> = &'a [f64];

pub const NO_INCOMING: Incoming<'static> = &[];

#[inline]
fn threat_of(incoming: Incoming, i: usize) -> f64 {
    incoming.get(i).copied().unwrap_or(0.0)
}

/// `BattleSim.control_gap_in` battle_sim.gd:277-292 — nearest BASE EDGE gap to
/// the marker in inches, measured HORIZONTALLY (y dropped before the length).
pub fn control_gap_in(state: &State, i: usize, obj_pos: [f64; 3]) -> f64 {
    let ps = &state.positions[i];
    if ps.is_empty() {
        return f64::INFINITY;
    }
    let radii = &state.radii[i];
    let mut best = f64::INFINITY;
    for (pi, p) in ps.iter().enumerate() {
        let dx = p[0] - obj_pos[0];
        let dz = p[2] - obj_pos[2];
        let d_in = (dx * dx + dz * dz).sqrt() / IN2M;
        let r_in = if pi < radii.len() { radii[pi] / IN2M } else { 0.0 };
        best = best.min(d_in - r_in);
    }
    best
}

/// `BattleSim.can_hold_marker` battle_sim.gd:297-302 — the referee's
/// eligibility set for holding a marker at a round end.
pub fn can_hold_marker(state: &State, i: usize, round_no: i64) -> bool {
    if state.alive[i] <= 0 || state.shaken[i] {
        return false;
    }
    if state.aircraft[i] {
        return false;
    }
    state.ambush_arrived_round[i] != round_no
}

/// The activation count `_presence` (ai_mission_eval.gd:591-614) needs to put
/// unit `i` inside marker `obj_pos`'s ring, or `None` for every case that
/// function drops to zero before it ever reads the unit's wounds. Extracted
/// VERBATIM out of `presence` — same order, same comparisons, same saturation —
/// so `presence` below is unchanged to the bit and variant 1 can ask the same
/// reachability question without a second, drifting copy of it.
fn activations_needed(
    state: &State, statics: &[UnitStatic], i: usize, obj_pos: [f64; 3],
) -> Option<i64> {
    if state.alive[i] <= 0 {
        return None;
    }
    if state.aircraft[i] {
        return None;
    }
    let rounds_total = state.rounds_total;
    let round_now = state.round;
    let arrived_now = state.ambush_arrived_round[i] == round_now;
    if arrived_now && round_now >= rounds_total {
        return None;
    }
    let d = control_gap_in(state, i, obj_pos);
    // `float(SoloController.sim_move_bands(su["unit"]).get("rush", 12))`
    // (ai_mission_eval.gd:602) — the LIVE read, which is what `State.bands`
    // carries (io.rs falls back to the profile's copy of the same call when a
    // corpus predates the per-activation stamp). Reading the profile directly
    // would answer 12" for a unit that picked up a `Slow` aura mid-game.
    // evmove — and the granted solo family's delta rides the same read
    // (`sim::live_bands_of`, quiet): a Slow/Fast grant moves the reach.
    let (_, rush) = crate::sim::live_bands_of(statics, state, i);
    // An empty position array gives d = INF; the cast then saturates at i64::MAX
    // and `needed > moves_left` drops the unit — the same answer GDScript's
    // int(ceil(INF)) path produces.
    let mut needed: i64 = 0;
    if d > OBJECTIVE_CONTROL_IN + CONTROL_EPS {
        needed = ((d - OBJECTIVE_CONTROL_IN) / rush.max(1.0)).ceil() as i64;
    }
    if arrived_now {
        needed = needed.max(1);
    }
    if state.shaken[i] {
        needed += 1;
    }
    let moves_left = rounds_total - round_now + if state.activated[i] { 0 } else { 1 };
    if needed > moves_left {
        return None;
    }
    Some(needed)
}

/// `AiMissionEval._presence` ai_mission_eval.gd:591-617 — one unit's projected
/// hold strength at one marker, discounted per future activation still needed.
pub fn presence(
    state: &State, statics: &[UnitStatic], i: usize, obj_pos: [f64; 3], threat: f64,
) -> f64 {
    let Some(needed) = activations_needed(state, statics, i, obj_pos) else {
        return 0.0;
    };
    let mut strength = 0.0f64;
    for w in &state.wounds[i] {
        strength += *w as f64;
    }
    (strength - threat).max(0.0) * DISCOUNT.powf(needed as f64)
}

/// `AiMissionEval._objective_p` ai_mission_eval.gd:415-431 — the soft control
/// ratio at one marker; an unreachable marker keeps its owner (seize rule).
/// `carry_term` = the C7 carrier branch; only `eval_variant = 2` turns it off.
fn objective_p(
    state: &State, statics: &[UnitStatic], obj_index: usize, player: i64, incoming: Incoming,
    carry_term: bool,
) -> f64 {
    let obj = state.objectives[obj_index];
    if let Some(marker) = state.markers_meta.get(obj_index).filter(|_| carry_term) {
        if marker.carry && marker.carried_by >= 0 {
            let carrier = marker.carried_by as usize;
            if carrier < state.units() {
                let strength: f64 = state.wounds[carrier].iter().map(|&w| w as f64).sum();
                let holds = if state.alive[carrier] > 0 && !state.shaken[carrier] && strength > 0.0 {
                    ((strength - threat_of(incoming, carrier)) / strength).clamp(0.0, 1.0)
                } else { 0.0 };
                return if state.player[carrier] == player { holds } else { 1.0 - holds };
            }
        }
    }
    let mut mine = 0.0f64;
    let mut theirs = 0.0f64;
    for i in 0..state.units() {
        let p = presence(state, statics, i, obj.pos, threat_of(incoming, i));
        if state.player[i] == player {
            mine += p;
        } else {
            theirs += p;
        }
    }
    if mine + theirs <= 0.0 {
        return if obj.owner == 0 {
            0.5
        } else if obj.owner == player {
            1.0
        } else {
            0.0
        };
    }
    mine / (mine + theirs)
}

/// D13: the table the role terms measure on, inches. The state carries no table, so the eval
/// reads the default 6x4 ft one (the same constants the referee twins take as arguments).
const ROLE_TABLE_W_IN: f64 = 72.0;
const ROLE_TABLE_D_IN: f64 = 48.0;
/// D13: the share of the score the role term carries; the rest is the reserve-aware control mean.
const ROLE_TERM_WEIGHT: f64 = 0.5;

/// D12c: what stepping on an unknown marker may cost the attacker, in value units — the trap's
/// D6+1 hits, spread over the `n` hidden markers (each is the trap with probability 1/n).
const TRAP_COST: f64 = 0.1;

/// D13: a unit still in reserve projects `strength x DISCOUNT x rounds_left / rounds_total` of
/// future presence at every marker (it arrives next round and holds from then on).
fn reserve_presence(state: &State, i: usize) -> f64 {
    if !state.dormant[i] {
        return 0.0;
    }
    let strength: f64 = state.dormant_wounds[i].iter().map(|&w| w as f64).sum();
    let left = (state.rounds_total - state.round).max(0) as f64;
    strength * DISCOUNT * left / (state.rounds_total.max(1) as f64)
}

/// D13: `objective_p` with the reserves counted — twin of `AiMissionEval._objective_p_roles`.
fn objective_p_roles(
    state: &State, statics: &[UnitStatic], i: usize, player: i64, incoming: Incoming,
) -> f64 {
    if state.markers_meta.get(i).is_some_and(|m| m.carry && m.carried_by >= 0) {
        return objective_p(state, statics, i, player, incoming, true);
    }
    let obj = state.objectives[i];
    let (mut mine, mut theirs) = (0.0f64, 0.0f64);
    for u in 0..state.units() {
        let p = presence(state, statics, u, obj.pos, threat_of(incoming, u)) + reserve_presence(state, u);
        if state.player[u] == player { mine += p } else { theirs += p }
    }
    if mine + theirs <= 0.0 {
        return if obj.owner == 0 { 0.5 } else if obj.owner == player { 1.0 } else { 0.0 };
    }
    mine / (mine + theirs)
}

/// D13: the role term. `escort`: the DEFENDER's value is `1 - dist(marker, target edge) / depth`
/// (the target edge is opposite `deploy_edge`), the attacker's the mirror. `extract`: the ATTACKER's
/// value is `1 - dist(relic, nearest edge) / half depth` (the relic = the `secret: relic` marker,
/// else every live marker; the best one counts), the defender's the mirror. Carried markers are
/// measured at the carrier's base edge (R11a). `None` = not a role mission.
fn role_term(state: &State, player: i64) -> Option<f64> {
    let att = state.attacker;
    if (att != 1 && att != 2) || !matches!(&*state.scoring, "escort" | "extract") {
        return None;
    }
    let live: Vec<([f64; 2], f64, bool)> = (0..state.markers_meta.len())
        .filter_map(|i| {
            let (p, r) = crate::mission::marker_point_in(state, i)?;
            Some((p, r, state.markers_meta[i].secret.as_deref() == Some("relic")))
        })
        .collect();
    let attacker_side = player == att;
    if &*state.scoring == "escort" {
        let edge = state.markers_meta.iter().find(|m| m.mobile).map_or(0, |m| m.deploy_edge);
        if edge == 0 {
            return Some(0.5);
        }
        let target = -(edge.signum() as f64);
        let defender_value = live
            .iter()
            .map(|(p, r, _)| (1.0 - (ROLE_TABLE_D_IN / 2.0 - target * p[1] - r) / ROLE_TABLE_D_IN).clamp(0.0, 1.0))
            .fold(0.0f64, f64::max);
        return Some(if attacker_side { 1.0 - defender_value } else { defender_value });
    }
    let value_at = |p: &[f64; 2], r: f64| {
        let gap = (ROLE_TABLE_W_IN / 2.0 - p[0].abs()).min(ROLE_TABLE_D_IN / 2.0 - p[1].abs()) - r;
        (1.0 - gap / (ROLE_TABLE_D_IN / 2.0)).clamp(0.0, 1.0)
    };
    let any_relic = live.iter().any(|m| m.2);
    // R9a fog: the attacker cannot tell the hidden markers apart, so while no relic is known each is
    // the relic with probability 1/n (the MEAN value) and the trap with probability 1/n (TRAP_COST/n).
    let hidden: Vec<f64> = (0..state.markers_meta.len())
        .filter(|&i| state.markers_meta[i].secret_hidden && !state.markers_meta[i].destroyed)
        .filter_map(|i| crate::mission::marker_point_in(state, i).map(|(p, r)| value_at(&p, r)))
        .collect();
    let attacker_value = if attacker_side && !any_relic && !hidden.is_empty() {
        let n = hidden.len() as f64;
        (hidden.iter().sum::<f64>() / n - TRAP_COST / n).clamp(0.0, 1.0)
    } else {
        live.iter().filter(|m| m.2 || !any_relic).map(|(p, r, _)| value_at(p, *r)).fold(0.0f64, f64::max)
    };
    Some(if attacker_side { attacker_value } else { 1.0 - attacker_value })
}

/// `AiMissionEval._is_destroy_mission` ai_mission_eval.gd:413-416.
fn is_destroy_mission(state: &State) -> bool {
    if &*state.scoring == "sabotage" {
        return true;
    }
    state
        .vp_flavour
        .as_deref()
        .and_then(|v| v.get("mode"))
        .and_then(|v| v.as_str())
        .map(|m| m == "demolition")
        .unwrap_or(false)
}

/// `AiMissionEval._score_hand` ai_mission_eval.gd:356-407.
pub fn score_hand(
    state: &State, statics: &[UnitStatic], player: i64, incoming: Incoming,
) -> f64 {
    score_hand_carry(state, statics, player, incoming, true)
}

/// `score_hand` with the C7 carry term switchable — `eval_variant = 2` (wave C
/// G-AB, plan amendment C9-gate) is `carry_term = false`: a carried marker is
/// priced by presence like any other, the hand eval exactly as before C7.
fn score_hand_carry(
    state: &State, statics: &[UnitStatic], player: i64, incoming: Incoming, carry_term: bool,
) -> f64 {
    if state.objectives.is_empty() {
        return 0.5;
    }
    if !state.markers_meta.is_empty() && is_destroy_mission(state) {
        // NML-1010 W3b: destroy missions score my grip on THEIR marker minus
        // their grip on MINE, destroyed states locked at 1/0.
        let mut att = 0.0f64;
        let mut deff = 0.0f64;
        for i in 0..state.objectives.len().min(state.markers_meta.len()) {
            let meta = &state.markers_meta[i];
            let ob = meta.owned_by;
            if ob == 0 {
                continue;
            }
            if meta.destroyed {
                if ob == player {
                    deff = 1.0;
                } else {
                    att = 1.0;
                }
                continue;
            }
            let pctrl = objective_p(state, statics, i, player, incoming, carry_term);
            if ob == player {
                deff = 1.0 - pctrl;
            } else {
                att = pctrl;
            }
        }
        return (0.5 + 0.5 * (att - DESTROY_DEFENCE_WEIGHT * deff)).clamp(0.0, 1.0);
    }
    if let Some(role) = role_term(state, player) {
        let n = state.objectives.len() as f64;
        let control: f64 = (0..state.objectives.len())
            .map(|i| objective_p_roles(state, statics, i, player, incoming))
            .sum::<f64>() / n;
        return ROLE_TERM_WEIGHT * role + (1.0 - ROLE_TERM_WEIGHT) * control;
    }
    let mut total = 0.0f64;
    for i in 0..state.objectives.len() {
        total += objective_p(state, statics, i, player, incoming, carry_term);
    }
    total / state.objectives.len() as f64
}

/// `AiMissionEval.score` ai_mission_eval.gd:344-354 with `fit_mode == false`.
/// The doctrine arm — an EMPTY statics slice keeps its signature, and the
/// helper's `.get` guard reads the static band there: the synth states carry
/// no buffs, so nothing could fold anyway.
pub fn score(state: &State, player: i64, incoming: Incoming) -> f64 {
    score_hand(state, &[], player, incoming)
}

/// Variant 1's per-unit half — the probability that unit `i` is one of the
/// bodies the REFEREE finds inside marker `obj_pos`'s ring at the deciding
/// round end. `activations_needed` is `presence`'s own reachability, so
/// `can_hold_marker`'s shaken refusal (`battle_sim.gd:297-302`) falls out
/// without a second rule: shaken already costs one activation, and a shaken
/// unit that has spent its activation in the final round has `moves_left = 0`,
/// so the `needed > moves_left` drop answers `None`. `survive` is the same
/// `incoming` reply threat `presence` subtracts, read as "will any model of
/// this unit still be standing" instead of "how much strength is left".
fn hold_p(
    state: &State, statics: &[UnitStatic], i: usize, obj_pos: [f64; 3], threat: f64,
) -> f64 {
    let Some(needed) = activations_needed(state, statics, i, obj_pos) else {
        return 0.0;
    };
    let mut strength = 0.0f64;
    for w in &state.wounds[i] {
        strength += *w as f64;
    }
    if strength <= 0.0 {
        return 0.0;
    }
    let survive = (((strength - threat).max(0.0)) / strength).min(1.0);
    survive * DISCOUNT.powf(needed as f64)
}

/// Variant 1's per-marker half — `mission::playout_seize` (mission.rs:41-69) in
/// EXPECTATION. That function reads the SET of sides inside the ring, never the
/// count of bodies: one side alone seizes, both sides make the marker NEUTRAL
/// (worth nothing to either), nobody leaves the current owner in place. With
/// `A`/`B` the chance each side puts at least one eligible unit in the ring,
/// the referee's three outcomes are `A(1-B)`, `B(1-A)` and `(1-A)(1-B)`, and
/// the contested mass `A*B` is priced at zero — its honest value in a marker
/// COUNT difference. `A(1-B) - B(1-A)` collapses to `A - B`, which is why mass
/// cancels here exactly the way `mission_winner` (mission.rs:247-257) cancels
/// it. Same [0, 1] scale as `objective_p`, 0.5 = level.
fn objective_own(
    state: &State, statics: &[UnitStatic], obj_index: usize, player: i64, incoming: Incoming,
) -> f64 {
    let obj = state.objectives[obj_index];
    let mut mine_absent = 1.0f64;
    let mut theirs_absent = 1.0f64;
    for i in 0..state.units() {
        let q = hold_p(state, statics, i, obj.pos, threat_of(incoming, i)).clamp(0.0, 1.0);
        if state.player[i] == player {
            mine_absent *= 1.0 - q;
        } else {
            theirs_absent *= 1.0 - q;
        }
    }
    let a = 1.0 - mine_absent;
    let b = 1.0 - theirs_absent;
    let keep = if obj.owner == 0 {
        0.0
    } else if obj.owner == player {
        1.0
    } else {
        -1.0
    };
    (0.5 + 0.5 * ((a - b) + mine_absent * theirs_absent * keep)).clamp(0.0, 1.0)
}

/// `eval_variant = 4` (aifix A3) COMPOSES with variant 3: a plain `round_vp`
/// mission keeps the VP-aware leaf whole (its `objective_own` already carries
/// the held-marker `keep` term), every state variant 3 hands back to the hand
/// eval gets the held-marker rule below instead.
fn score_hand_vp_hold(
    state: &State, statics: &[UnitStatic], player: i64, incoming: Incoming,
) -> f64 {
    if !state.objectives.is_empty() && &*state.scoring == "round_vp" && !is_destroy_mission(state) {
        return score_hand_vp(state, statics, player, incoming);
    }
    score_hand_hold(state, statics, player, incoming)
}

/// The hand eval with a held marker that stays
/// held until contested (GF v3.5.1 p.6: markers stay under the player's control
/// even if the unit moves away). `objective_p` reads `owner` only when nobody
/// can reach, so a marker I stand on drops below 0.5 the moment an enemy mob
/// could walk there. Here the owner's side keeps at least half of it, and the
/// other side's owner at most half; presence only moves it past 0.5 for the
/// side that out-weighs the owner. Destroy and role missions are handed back
/// to variant 0 whole.
fn score_hand_hold(
    state: &State, statics: &[UnitStatic], player: i64, incoming: Incoming,
) -> f64 {
    if state.objectives.is_empty()
        || (!state.markers_meta.is_empty() && is_destroy_mission(state))
        || role_term(state, player).is_some()
    {
        return score_hand(state, statics, player, incoming);
    }
    let total: f64 = (0..state.objectives.len())
        .map(|i| hold_owner_p(state, objective_p(state, statics, i, player, incoming, true), i, player))
        .sum();
    total / state.objectives.len() as f64
}

/// Variant 4's per-marker rule: the owner keeps at least half until contested.
fn hold_owner_p(state: &State, share: f64, obj_index: usize, player: i64) -> f64 {
    let carried = state.markers_meta.get(obj_index).is_some_and(|m| m.carry && m.carried_by >= 0);
    match state.objectives[obj_index].owner {
        _ if carried => share,
        0 => share,
        o if o == player => share.max(0.5),
        _ => share.min(0.5),
    }
}

/// `eval_variant = 1` (ledger row 7) — the marker term the REFEREE would book,
/// blended into the frozen mean share by how much game is left. `w` rises from
/// `1/rounds_total` at the opening round to 1.0 at the round that decides the
/// game, so the search keeps `objective_p`'s continuous gradient early and is
/// priced by `playout_seize`'s own verdict where it counts. The destroy /
/// sabotage branch is NOT this rung's business and is handed back to variant 0
/// whole.
fn score_hand_majority(
    state: &State, statics: &[UnitStatic], player: i64, incoming: Incoming,
) -> f64 {
    if state.objectives.is_empty() {
        return 0.5;
    }
    if !state.markers_meta.is_empty() && is_destroy_mission(state) {
        return score_hand(state, statics, player, incoming);
    }
    let total_rounds = state.rounds_total.max(1) as f64;
    let left = (state.rounds_total - state.round).max(0) as f64;
    let w = (1.0 - left / total_rounds).clamp(0.0, 1.0);
    let mut total = 0.0f64;
    for i in 0..state.objectives.len() {
        let share = objective_p(state, statics, i, player, incoming, true);
        let own = objective_own(state, statics, i, player, incoming);
        total += (1.0 - w) * share + w * own;
    }
    total / state.objectives.len() as f64
}

/// `eval_variant = 3` (mission-play lane, step 2; DESIGN_missions §8) — the
/// currency the `round_vp` referee books, in EXPECTATION: the VP already
/// banked (`state.vp`, which `imagined_round_end` writes at every rollout
/// boundary) plus the rounds still to be scored times each marker's expected
/// yield (`2 * objective_own - 1`, the referee's three-way seize), plus the
/// majority bonus the flavour pays (every round, at the end, or never) and an
/// unclaimed first-seize bounty. `left` counts the rounds the referee has NOT
/// booked yet: a rollout boundary arrives with every unit activated and its
/// round already in the ledger, a mid-round leaf (tail cap, live pick) still
/// has this round to score. Everything that is not a plain `round_vp`
/// mission — END scoring, sabotage, the demolition flavour, no markers — is
/// handed back to variant 0 whole, so those states score byte-identical.
fn score_hand_vp(
    state: &State, statics: &[UnitStatic], player: i64, incoming: Incoming,
) -> f64 {
    if state.objectives.is_empty() || &*state.scoring != "round_vp" || is_destroy_mission(state) {
        return score_hand(state, statics, player, incoming);
    }
    let n = state.objectives.len() as f64;
    let vp = vp_of(state.vp.as_deref());
    let banked = (if player == 1 { vp[0] - vp[1] } else { vp[1] - vp[0] }) as f64;
    let open = (0..state.units()).any(|i| state.alive[i] > 0 && !state.activated[i]);
    let left = ((state.rounds_total - state.round).max(0) + i64::from(open)) as f64;
    let mut sum = 0.0f64;
    for i in 0..state.objectives.len() {
        sum += 2.0 * objective_own(state, statics, i, player, incoming) - 1.0;
    }
    let lead = (sum / n).clamp(-1.0, 1.0);
    let flavour = state.vp_flavour.as_deref();
    let majority = flavour.and_then(|v| v.get("majority")).and_then(|v| v.as_str()).unwrap_or("end");
    let (bonus, bonus_max) = match majority {
        "round" => (left * lead, left),
        "end" => (lead, 1.0),
        _ => (0.0, 0.0),
    };
    let first_seize =
        flavour.and_then(|v| v.get("first_seize")).and_then(|v| v.as_bool()).unwrap_or(false);
    let claimed = state
        .vp_memo
        .as_deref()
        .and_then(|m| m.get("first_seizer"))
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);
    let (bounty, bounty_max) = if first_seize && claimed == 0.0 { (lead, 1.0) } else { (0.0, 0.0) };
    let denom = (n * left + bonus_max + bounty_max).max(1.0);
    0.5 + 0.5 * ((banked + left * sum + bonus + bounty) / denom).clamp(-1.0, 1.0)
}

/// The evolved-hand-eval registry (NML-1073 evolved-eval lane, step 2). Every
/// call site keeps calling `score_hand`/`score_with` at variant 0 unchanged;
/// only `Rollout::blend_score` reads `Knobs::eval_variant` and comes through
/// here. Arm 1 (ledger row 7) is the marker term above, arm 2 the wave-C
/// no-carry ablation, arm 3 the `round_vp` currency; every value past the
/// registered arms is refused by `acts::read_act_header` before a header is
/// ever played, so the fallback arm is an invariant, not a live path.
pub fn score_hand_variant(
    state: &State, statics: &[UnitStatic], player: i64, incoming: Incoming, eval_variant: i64,
) -> f64 {
    match eval_variant {
        0 => score_hand(state, statics, player, incoming),
        1 => score_hand_majority(state, statics, player, incoming),
        2 => score_hand_carry(state, statics, player, incoming, false),
        3 => score_hand_vp(state, statics, player, incoming),
        4 => score_hand_vp_hold(state, statics, player, incoming),
        other => unreachable!("eval_variant {other}: read_act_header should have refused this"),
    }
}

/// NML-1158a — the RESIDUAL combination, the one scale definition in the crate:
/// the net's sigmoid `p` ships as `(delta + 1) / 2` where `delta` is the
/// trained residual `outcome - f(hand)` on the [0, 1] hand scale, so `delta =
/// 2*p - 1` (neutral at 0.5) and the played score is `hand + delta`, clamped
/// back into the hand eval's range. `p_scaled` is the net's answer times the
/// red-proof `scale` (`score_fit` returns exactly that), hence `scale*(2p-1) =
/// 2*p_scaled - scale` — the scale multiplies the DELTA here (in Blend it
/// multiplies the net's probability; `scale = 0` is pure hand in both). The
/// trainer's base is THIS crate's own `score()` on the state passed to
/// `score_with` — the corpus `value` field is the same hand eval, and `f` is
/// only its calibration onto the outcome scale — so the rolled-forward
/// arrival gap is absorbed by the residual itself. A residual can un-lock the
/// destroy branch's locked 1/0 scores; that is its job.
fn combine_residual(hand: f64, p_scaled: f64, scale: f64) -> f64 {
    (hand + 2.0 * p_scaled - scale).clamp(0.0, 1.0)
}

/// `AiMissionEval.score` ai_mission_eval.gd:344-354 in FULL (NML-1142): with a
/// net, the E4.2 blend `(1 - fb) * hand + fb * fit`; NML-1158a adds the
/// RESIDUAL mode, `hand + delta` (see `combine_residual`) — the net can only
/// add what the hand eval misses. Without a net, the hand eval alone.
/// `fit == None` IS `fit_mode == false` — the caller decides, because the
/// GDScript's `fit_mode` is a per-activation static and the net is not.
pub fn score_with(
    state: &State,
    statics: &[UnitStatic],
    player: i64,
    incoming: Incoming,
    fit: Option<&Fitted>,
) -> f64 {
    score_with_variant(state, statics, player, incoming, fit, 0)
}

/// `score_with` at an explicit `eval_variant` — the evolved-eval lane's other
/// read site (`Rollout::blend_score`). Every other caller keeps calling
/// `score_with` above, unchanged, so this function existing moves nothing
/// until something passes a nonzero variant.
pub fn score_with_variant(
    state: &State,
    statics: &[UnitStatic],
    player: i64,
    incoming: Incoming,
    fit: Option<&Fitted>,
    eval_variant: i64,
) -> f64 {
    let Some(fit) = fit else {
        return score_hand_variant(state, statics, player, incoming, eval_variant);
    };
    match fit.mode {
        FitMode::Residual => combine_residual(
            score_hand_variant(state, statics, player, incoming, eval_variant),
            fit.score_fit(state, statics, player, incoming),
            fit.scale,
        ),
        FitMode::Blend => {
            let fb = fit.blend;
            (1.0 - fb) * score_hand_variant(state, statics, player, incoming, eval_variant)
                + fb * fit.score_fit(state, statics, player, incoming)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{combine_residual, score_hand, score_hand_variant, NO_INCOMING};
    use crate::acts::read_act_header;
    use crate::io::state_from_json;
    use crate::rules::Registries;
    use crate::state::ProfileCache;
    use crate::unit::UnitStatic;

    /// The tiny test net's constant answer (`test_fitted.py::FIT`, the
    /// sigmoid(2) any state with a living own unit scores) — the arithmetic
    /// the Python-side divergence gate rides on.
    const FIT: f64 = 0.880_797_077_977_882_3;

    /// The evolved-eval seam's RED proof — variant 0 is exactly `score_hand`,
    /// nothing routed through the seam. One unit, no objectives, so
    /// `score_hand` takes its trivial 0.5 branch (io.rs's own tests build the
    /// identical minimal fixture): the point here is the DISPATCH, not the
    /// arithmetic.
    #[test]
    fn variant_0_is_exactly_score_hand() {
        const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
          "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":3,
            "wounds_max":[3],"model_count":1,"caster_value":0,"base_radius":0.016,
            "game_system":"gf","faction_folder":"robot_legions","special_rules":[],
            "item_grants":[],"attached_hero_rules":[],
            "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;
        const PLAIN: &str = r#"{"round":1,"rounds_total":4,"scoring":"end",
          "units":{"p1_0_a":{"player":1,"alive":1,"wounds":[3],"radii":[0.016],
            "positions":[[0.0,0.0,0.0]],"in_cover":false,"shaken":false,
            "fatigued":false,"activated":false,"casts":0,"morale_bonus":0,
            "aircraft":false,"dormant":false,"ambush_arrived_round":-1,
            "earliest_arrival_round":-1,"wound_frac":0.0,"mods":{},"mods_base":{},
            "bands":{"advance":6.0,"rush":12.0}}}}"#;
        let header = read_act_header(HEADER).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        let state = state_from_json(PLAIN, &mut cache, &mut roster).expect("state");
        let direct = score_hand(&state, &[], 1, NO_INCOMING);
        let via_seam = score_hand_variant(&state, &[], 1, NO_INCOMING, 0);
        assert_eq!(direct, via_seam, "variant 0 must be byte-identical to the direct call");
        assert_eq!(direct, 0.5, "no objectives -> score_hand's trivial branch");
    }

    /// afpoints step 1 — the Army Forge points cost rides the profile into the
    /// `UnitStatic` closure, the value the `strength_by_points` eval arm reads.
    /// RED before the plumb: `UnitStatic` had no `cost` at all.
    #[test]
    fn the_profile_cost_reaches_unit_static() {
        const HEADER: &str = r#"{"kind":"header","knobs":{},"profiles":{
          "p1_0_a":{"unit_id":"p1_0_a","name":"A","quality":4,"defense":3,"tough":3,
            "cost":123,"wounds_max":[3],"model_count":1,"caster_value":0,"base_radius":0.016,
            "game_system":"gf","faction_folder":"robot_legions","special_rules":[],
            "item_grants":[],"attached_hero_rules":[],
            "move_bands":{"advance":6.0,"rush":12.0},"weapons":[]}}}"#;
        let header = read_act_header(HEADER).expect("header");
        let mut reg = Registries::default();
        let statics: Vec<UnitStatic> =
            header.profiles.list.iter().map(|p| UnitStatic::build(&mut reg, p)).collect();
        assert_eq!(statics[0].cost, 123, "the list cost reaches UnitStatic.cost");
    }

    /// Wave C G-AB: variant 2 is variant 0 WITHOUT the C7 carry term. My unit
    /// carries the one relic 0.9 m off the marker's stale spot, the enemy
    /// stands on that spot. With the term the carrier holds it outright (1.0);
    /// without it the marker is priced by presence at the spot, where the
    /// enemy is (< 0.5). With nothing carried, 2 and 0 are the same number.
    #[test]
    fn variant_2_prices_a_carried_marker_without_the_carry_term() {
        let mut st = marker_state(
            &[U("p1_0_a", 1, 0.9, 6, false, false), U("p2_0_a", 2, 0.02, 6, false, false)],
            1, 1,
        );
        let plain_eq = score_hand_variant(&st, &[], 1, NO_INCOMING, 2)
            == score_hand_variant(&st, &[], 1, NO_INCOMING, 0);
        assert!(plain_eq, "nothing carried: variant 2 must equal variant 0");
        st.markers_meta = vec![crate::state::Marker { carry: true, carried_by: 0, ..Default::default() }];
        assert_eq!(score_hand_variant(&st, &[], 1, NO_INCOMING, 0), 1.0);
        assert!(score_hand_variant(&st, &[], 1, NO_INCOMING, 2) < 0.5);
    }

    /// A 4-round PROGRESSIVE fixture for the mission-play arm: the given units
    /// on the x axis (`U`, metres), neutral markers at `marker_x`, the flavour
    /// blob and the banked ledger, through the real reader like `marker_state`.
    fn vp_state(
        units: &[U], marker_x: &[f64], round: i64, scoring: &str, flavour: &str, vp: [i64; 2],
    ) -> crate::state::State {
        let profiles: Vec<String> = units
            .iter()
            .map(|u| {
                format!(
                    r#""{id}":{{"unit_id":"{id}","name":"U","quality":4,"defense":3,"tough":6,
                     "wounds_max":[6],"model_count":1,"caster_value":0,"base_radius":0.016,
                     "game_system":"gf","faction_folder":"robot_legions","special_rules":[],
                     "item_grants":[],"attached_hero_rules":[],
                     "move_bands":{{"advance":6.0,"rush":12.0}},"weapons":[]}}"#,
                    id = u.0
                )
            })
            .collect();
        let plain_units: Vec<String> = units
            .iter()
            .map(|u| {
                format!(
                    r#""{id}":{{"player":{p},"alive":1,"wounds":[{w}],"radii":[0.016],
                     "positions":[[{x},0.0,0.0]],"in_cover":false,"shaken":{sh},
                     "fatigued":false,"activated":{ac},"casts":0,"morale_bonus":0,
                     "aircraft":false,"dormant":false,"ambush_arrived_round":-1,
                     "earliest_arrival_round":-1,"wound_frac":0.0,"mods":{{}},"mods_base":{{}},
                     "bands":{{"advance":6.0,"rush":12.0}}}}"#,
                    id = u.0, p = u.1, x = u.2, w = u.3, sh = u.4, ac = u.5
                )
            })
            .collect();
        let markers: Vec<String> =
            marker_x.iter().map(|x| format!(r#"{{"pos":[{x},0.0,0.0],"owner":0}}"#)).collect();
        let head = format!(r#"{{"kind":"header","knobs":{{}},"profiles":{{{}}}}}"#, profiles.join(","));
        let plain = format!(
            r#"{{"round":{round},"rounds_total":4,"scoring":"{scoring}","vp":[{},{}],
             "vp_flavour":{flavour},"vp_memo":{{}},"objectives":[{}],"units":{{{}}}}}"#,
            vp[0], vp[1], markers.join(","), plain_units.join(",")
        );
        let header = read_act_header(&head).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        state_from_json(&plain, &mut cache, &mut roster).expect("state")
    }

    /// aifix A3 composes with variant 3: on a `round_vp` mission variant 4 IS
    /// variant 3 (the banked VP lead still moves the score), not variant 0.
    #[test]
    fn variant_4_keeps_the_vp_term_of_variant_3() {
        let units = [U("p1_0_a", 1, 0.0, 6, false, false), U("p2_0_a", 2, 5.0, 6, false, false)];
        let behind = vp_state(&units, &[0.0], 2, "round_vp", r#"{"majority":"end"}"#, [0, 9]);
        let ahead = vp_state(&units, &[0.0], 2, "round_vp", r#"{"majority":"end"}"#, [9, 0]);
        for st in [&behind, &ahead] {
            assert_eq!(
                score_hand_variant(st, &[], 1, NO_INCOMING, 4),
                score_hand_variant(st, &[], 1, NO_INCOMING, 3),
                "round_vp: variant 4 is variant 3 to the bit"
            );
        }
        let (b, a) = (score_hand_variant(&behind, &[], 1, NO_INCOMING, 4), score_hand_variant(&ahead, &[], 1, NO_INCOMING, 4));
        assert!(b < 0.5 && a > 0.5, "variant 4 still reads the ledger: {b} vs {a}");
    }

    /// aifix A3 RED: a marker I hold, my weak unit on it, a strong enemy mob in
    /// reach — variant 0 scores it below half for me (owner read only when
    /// nobody can reach), variant 4 keeps it mine until contested and leaves the
    /// enemy's side at most half.
    #[test]
    fn variant_4_keeps_a_held_marker_mine_until_contested() {
        let mut st = vp_state(
            &[U("p1_0_a", 1, 0.0, 1, false, false), U("p2_0_a", 2, 0.3, 6, false, false)],
            &[0.0], 2, "end", "{}", [0, 0],
        );
        st.objectives[0].owner = 1;
        let v = |st: &crate::state::State, p, var| score_hand_variant(st, &[], p, NO_INCOMING, var);
        let v = |p, var| v(&st, p, var);
        assert!(v(1, 0) < 0.5, "variant 0 today: {}", v(1, 0));
        assert_eq!(v(1, 4), 0.5);
        assert!(v(2, 4) <= 0.5 && v(2, 0) > 0.5);
        st.objectives[0].owner = 0;
        let unowned = |var| score_hand_variant(&st, &[], 1, NO_INCOMING, var);
        assert_eq!(unowned(4), unowned(0), "an unowned marker is priced as before");
    }

    /// RED-1 (mission-play step 2): my unit holds the one marker, theirs is far
    /// out of reach, round 2 of a `round_vp` game. Variant 0 scores the same
    /// board whether I am 9 VP behind or 9 ahead — it never reads the ledger;
    /// variant 3 must price the deficit below the lead.
    #[test]
    fn variant_3_reads_the_banked_vp_where_variant_0_is_blind() {
        let units = [U("p1_0_a", 1, 0.0, 6, false, false), U("p2_0_a", 2, 5.0, 6, false, false)];
        let behind = vp_state(&units, &[0.0], 2, "round_vp", r#"{"majority":"end"}"#, [0, 9]);
        let ahead = vp_state(&units, &[0.0], 2, "round_vp", r#"{"majority":"end"}"#, [9, 0]);
        let v0 = (
            score_hand_variant(&behind, &[], 1, NO_INCOMING, 0),
            score_hand_variant(&ahead, &[], 1, NO_INCOMING, 0),
        );
        assert_eq!(v0.0, v0.1, "variant 0 is VP-blind by construction");
        let v3 = (
            score_hand_variant(&behind, &[], 1, NO_INCOMING, 3),
            score_hand_variant(&ahead, &[], 1, NO_INCOMING, 3),
        );
        assert!(v3.0 < v3.1, "variant 3 must read the ledger: behind {} vs ahead {}", v3.0, v3.1);
        assert!(v3.0 < 0.5 && v3.1 > 0.5, "9 VP down is losing, 9 up is winning: {v3:?}");
    }

    /// NULL: off the `round_vp` currency (END scoring, the demolition flavour)
    /// variant 3 hands the whole state to variant 0 — the same bits, so every
    /// face-off and destroy corpus replays unchanged under the new arm.
    #[test]
    fn variant_3_is_variant_0_off_the_round_vp_currency() {
        let units = [U("p1_0_a", 1, 0.0, 6, false, false), U("p2_0_a", 2, 0.3, 6, false, false)];
        let end = vp_state(&units, &[0.0, 0.5], 3, "end", "{}", [0, 4]);
        assert_eq!(
            score_hand_variant(&end, &[], 1, NO_INCOMING, 3),
            score_hand_variant(&end, &[], 1, NO_INCOMING, 0),
            "END scoring: variant 3 must be variant 0 to the bit"
        );
        let demo = vp_state(&units, &[0.0, 0.5], 3, "round_vp", r#"{"mode":"demolition"}"#, [0, 4]);
        assert_eq!(
            score_hand_variant(&demo, &[], 1, NO_INCOMING, 3),
            score_hand_variant(&demo, &[], 1, NO_INCOMING, 0),
            "demolition flavour: variant 3 must be variant 0 to the bit"
        );
    }

    /// ROUND: three markers nobody can reach (every yield 0), 1 VP banked for
    /// me, majority at the end. A BOOKED final boundary (all activated, round
    /// 4) has nothing left to score: 1 VP over a 1-VP bonus denominator = 1.0.
    /// The same board mid-round (one unit free) still scores this round:
    /// denominator 3 + 1, so 0.625; one round earlier 6 + 1, so 0.5 + 1/14.
    #[test]
    fn variant_3_counts_the_rounds_the_referee_has_not_booked() {
        let far = [U("p1_0_a", 1, 5.0, 6, false, true), U("p2_0_a", 2, -5.0, 6, false, true)];
        let open = [U("p1_0_a", 1, 5.0, 6, false, false), U("p2_0_a", 2, -5.0, 6, false, true)];
        let markers = [0.0, 0.5, 1.0];
        let fl = r#"{"majority":"end"}"#;
        let booked = score_hand_variant(&vp_state(&far, &markers, 4, "round_vp", fl, [1, 0]), &[], 1, NO_INCOMING, 3);
        let last = score_hand_variant(&vp_state(&open, &markers, 4, "round_vp", fl, [1, 0]), &[], 1, NO_INCOMING, 3);
        let third = score_hand_variant(&vp_state(&open, &markers, 3, "round_vp", fl, [1, 0]), &[], 1, NO_INCOMING, 3);
        assert!((booked - 1.0).abs() < 1e-12, "booked final boundary: {booked}");
        assert!((last - 0.625).abs() < 1e-12, "open final round: {last}");
        assert!((third - (0.5 + 0.5 / 7.0)).abs() < 1e-12, "open round 3: {third}");
    }

    /// One one-model unit for the ledger-row-7 fixtures: id, player, x in
    /// METRES (the state's own unit), remaining wounds, shaken, activated.
    struct U(&'static str, i64, f64, i64, bool, bool);

    /// A 4-round face-off with ONE marker at the origin and the given units on
    /// the x axis, built through the real `read_act_header` / `state_from_json`
    /// path so the fixture cannot drift from what a corpus produces.
    fn marker_state(units: &[U], marker_owner: i64, round: i64) -> crate::state::State {
        let profiles: Vec<String> = units
            .iter()
            .map(|u| {
                format!(
                    r#""{id}":{{"unit_id":"{id}","name":"U","quality":4,"defense":3,"tough":6,
                     "wounds_max":[6],"model_count":1,"caster_value":0,"base_radius":0.016,
                     "game_system":"gf","faction_folder":"robot_legions","special_rules":[],
                     "item_grants":[],"attached_hero_rules":[],
                     "move_bands":{{"advance":6.0,"rush":12.0}},"weapons":[]}}"#,
                    id = u.0
                )
            })
            .collect();
        let plain_units: Vec<String> = units
            .iter()
            .map(|u| {
                format!(
                    r#""{id}":{{"player":{p},"alive":1,"wounds":[{w}],"radii":[0.016],
                     "positions":[[{x},0.0,0.0]],"in_cover":false,"shaken":{sh},
                     "fatigued":false,"activated":{ac},"casts":0,"morale_bonus":0,
                     "aircraft":false,"dormant":false,"ambush_arrived_round":-1,
                     "earliest_arrival_round":-1,"wound_frac":0.0,"mods":{{}},"mods_base":{{}},
                     "bands":{{"advance":6.0,"rush":12.0}}}}"#,
                    id = u.0, p = u.1, x = u.2, w = u.3, sh = u.4, ac = u.5
                )
            })
            .collect();
        let head = format!(
            r#"{{"kind":"header","knobs":{{}},"profiles":{{{}}}}}"#,
            profiles.join(",")
        );
        let plain = format!(
            r#"{{"round":{round},"rounds_total":4,"scoring":"end",
             "objectives":[{{"pos":[0.0,0.0,0.0],"owner":{marker_owner}}}],
             "units":{{{}}}}}"#,
            plain_units.join(",")
        );
        let header = read_act_header(&head).expect("header");
        let mut cache = ProfileCache::new(header.profiles);
        let mut roster = None;
        state_from_json(&plain, &mut cache, &mut roster).expect("state")
    }

    /// The reply threat `presence` and `hold_p` both subtract, addressed by
    /// SIDE rather than by index so the fixture does not depend on capture
    /// order: every enemy model is expected to lose `threat` wounds.
    fn threat_on_p2(state: &crate::state::State, threat: f64) -> Vec<f64> {
        (0..state.units())
            .map(|i| if state.player[i] == 2 { threat } else { 0.0 })
            .collect()
    }

    /// RED, ledger row 7. ONE contested marker in the deciding round: my
    /// 3-wound unit and their 6-wound unit both stand on it, and their unit is
    /// expected to lose 3 of those wounds to the reply. The frozen eval reads
    /// the MASS SHARE 3/(3+3) = exactly 0.5 — the "contested = 0.5" the ledger
    /// names. `playout_seize` (mission.rs:41-69) never weighs mass; it asks who
    /// is STILL THERE, and a unit half expected to die is a coin flip, so
    /// variant 1 reads 0.75. Doubling my mass then moves the frozen eval and
    /// leaves variant 1 exactly where it was: the referee counts sides.
    #[test]
    fn a_contested_marker_is_priced_by_presence_not_by_mass() {
        let light = marker_state(
            &[
                U("p1_0_a", 1, 0.0, 3, false, false),
                U("p2_0_a", 2, 0.0, 6, false, false),
            ],
            0,
            4,
        );
        let inc = threat_on_p2(&light, 3.0);
        let old = score_hand_variant(&light, &[], 1, &inc, 0);
        let new = score_hand_variant(&light, &[], 1, &inc, 1);
        assert_eq!(old, 0.5, "the frozen eval's mass share on a contested marker");
        assert!((new - 0.75).abs() < 1e-12, "variant 1 prices presence, got {new}");

        let heavy = marker_state(
            &[
                U("p1_0_a", 1, 0.0, 3, false, false),
                U("p1_1_a", 1, 0.0, 3, false, false),
                U("p2_0_a", 2, 0.0, 6, false, false),
            ],
            0,
            4,
        );
        let inc = threat_on_p2(&heavy, 3.0);
        let old_heavy = score_hand_variant(&heavy, &[], 1, &inc, 0);
        let new_heavy = score_hand_variant(&heavy, &[], 1, &inc, 1);
        assert!(old_heavy > old, "the frozen eval pays for mass: {old} -> {old_heavy}");
        assert!(
            (new_heavy - new).abs() < 1e-12,
            "variant 1 must not pay for mass: {new} -> {new_heavy}"
        );
    }

    /// RED — `can_hold_marker` (battle_sim.gd:297-302, score.rs) refuses a
    /// SHAKEN unit, so variant 1 must refuse it too: a body inside the ring is
    /// not a holder. Deciding round, the marker theirs, my only unit already
    /// activated and standing on it, their unit 30" away and out of reach.
    /// Shaken, my unit cannot recover in time and the owner keeps the marker;
    /// clear the one flag on the same fixture and the identical unit seizes it.
    #[test]
    fn a_shaken_unit_does_not_hold_the_marker() {
        const FAR: f64 = 0.762; // 30" in metres
        let shaken = marker_state(
            &[
                U("p1_0_a", 1, 0.0, 3, true, true),
                U("p2_0_a", 2, FAR, 3, false, false),
            ],
            2,
            4,
        );
        let steady = marker_state(
            &[
                U("p1_0_a", 1, 0.0, 3, false, true),
                U("p2_0_a", 2, FAR, 3, false, false),
            ],
            2,
            4,
        );
        assert_eq!(
            score_hand_variant(&shaken, &[], 1, NO_INCOMING, 1),
            0.0,
            "a shaken holder cannot hold: the owner keeps the marker"
        );
        assert_eq!(
            score_hand_variant(&steady, &[], 1, NO_INCOMING, 1),
            1.0,
            "the same unit, unshaken, seizes it"
        );
    }

    /// The end-of-game weighting: with rounds still to play, variant 1 is a
    /// BLEND of the frozen share and the referee's verdict, so an opening-round
    /// read sits strictly between the two and the search keeps its gradient.
    #[test]
    fn the_ownership_term_rises_as_the_rounds_run_out() {
        let units = || {
            [
                U("p1_0_a", 1, 0.0, 3, false, false),
                U("p2_0_a", 2, 0.0, 6, false, false),
            ]
        };
        let early = marker_state(&units(), 0, 1);
        let late = marker_state(&units(), 0, 4);
        let inc = threat_on_p2(&early, 3.0);
        let share = score_hand_variant(&early, &[], 1, &inc, 0);
        let blended = score_hand_variant(&early, &[], 1, &inc, 1);
        let decided = score_hand_variant(&late, &[], 1, &inc, 1);
        assert!(
            share < blended && blended < decided,
            "round 1 must sit between the share {share} and the verdict {decided}, got {blended}"
        );
    }

    #[test]
    fn residual_is_hand_plus_the_centred_delta() {
        // delta = 2*sigmoid(2) - 1; the score moves the hand value by exactly
        // that while the sum stays inside [0, 1].
        let delta = 2.0 * FIT - 1.0;
        assert!((combine_residual(0.2, FIT, 1.0) - (0.2 + delta)).abs() < 1e-12);
        assert!((combine_residual(0.1, FIT, 1.0) - (0.1 + delta)).abs() < 1e-12);
        // p = 0.5 (the trainer's "hand is right") leaves the hand value alone.
        assert_eq!(combine_residual(0.5, 0.5, 1.0), 0.5);
        // The red-proof scale multiplies the DELTA, not the score.
        assert!((combine_residual(0.5, 0.5 * FIT, 0.5) - (0.5 + 0.5 * delta)).abs() < 1e-12);
        // Clamped into the hand range at both ends (0.5 + delta = 1.26).
        assert_eq!(combine_residual(0.5, FIT, 1.0), 1.0);
        assert_eq!(combine_residual(0.0, 0.0, 1.0), 0.0);
    }

    /// D13 fixture: both units activated in the LAST round and far from the marker, so no one can
    /// project presence and the control mean is the neutral 0.5 — the score is then
    /// `0.5 * role + 0.25`, which isolates the role term.
    fn role_state(scoring: &str, att: i64, x_in: f64, z_in: f64, marker: crate::state::Marker) -> crate::state::State {
        let mut st = vp_state(
            &[U("p1_0_a", 1, 5.0, 6, false, true), U("p2_0_a", 2, -5.0, 6, false, true)],
            &[0.0], 4, scoring, "{}", [0, 0],
        );
        st.attacker = att;
        st.objectives[0].pos = [x_in * crate::IN2M, 0.0, z_in * crate::IN2M];
        st.markers_meta = vec![marker];
        st
    }

    fn hand(st: &crate::state::State, player: i64) -> f64 {
        score_hand(st, &[], player, NO_INCOMING)
    }

    /// escort: defender value `1 - dist / depth` to the edge opposite the deploy edge, the
    /// attacker the mirror.
    #[test]
    fn escort_prices_the_defenders_progress_toward_the_target_edge() {
        let vip = crate::state::Marker { mobile: true, deploy_edge: 1, ..Default::default() };
        let near = role_state("escort", 1, 0.0, -18.0, vip.clone());
        assert_eq!(hand(&near, 2), 0.5 * 0.875 + 0.25, "defender: 6\" from the target edge");
        assert_eq!(hand(&near, 1), 0.5 * 0.125 + 0.25, "attacker: the mirror");
        let centre = role_state("escort", 1, 0.0, 0.0, vip.clone());
        assert_eq!(hand(&centre, 2), 0.5, "mid-table: even");
        let home = role_state("escort", 1, 0.0, 20.0, vip);
        assert!(hand(&home, 2) < 0.5 && hand(&home, 1) > 0.5, "still at home: the attacker leads");
    }

    /// extract: attacker value `1 - dist(relic, nearest edge) / half depth`; the relic marker is the
    /// one that counts when a marker is flagged `secret: relic`.
    #[test]
    fn extract_prices_the_relics_distance_to_the_nearest_edge() {
        let relic = crate::state::Marker { secret: Some("relic".into()), ..Default::default() };
        let out = role_state("extract", 1, 30.0, 0.0, relic.clone());
        assert_eq!(hand(&out, 1), 0.5 * 0.75 + 0.25, "attacker: 6\" from the +x edge");
        assert_eq!(hand(&out, 2), 0.5 * 0.25 + 0.25, "defender: the mirror");
        let mid = role_state("extract", 1, 0.0, 0.0, relic);
        assert_eq!(hand(&mid, 1), 0.25, "table centre: no progress");
        let mut two = role_state("extract", 1, 0.0, 0.0, crate::state::Marker { secret: Some("trap".into()), ..Default::default() });
        two.objectives.push(crate::state::Objective { pos: [30.0 * crate::IN2M, 0.0, 0.0], owner: 0 });
        two.markers_meta.push(crate::state::Marker { secret: Some("relic".into()), ..Default::default() });
        assert_eq!(hand(&two, 1), 0.5 * 0.75 + 0.25, "only the relic counts, not the trap at the edge-far spot");
    }

    /// A destroyed marker (the plain/trap one) and no roles both leave the old arithmetic alone.
    #[test]
    fn role_term_stands_down_without_roles_or_live_markers() {
        let relic = crate::state::Marker { secret: Some("relic".into()), ..Default::default() };
        let mut gone = role_state("extract", 1, 30.0, 0.0, relic.clone());
        gone.markers_meta[0].destroyed = true;
        assert_eq!(hand(&gone, 1), 0.25, "no live marker: the attacker has nothing to extract");
        let no_roles = role_state("extract", 0, 30.0, 0.0, relic);
        assert_eq!(hand(&no_roles, 1), 0.5, "attacker 0: the generic control mean alone");
    }

    /// Reserves are future presence: `strength x DISCOUNT x rounds_left / rounds_total`.
    #[test]
    fn a_reserve_counts_as_rounds_left_weighted_future_presence() {
        let relic = crate::state::Marker { secret: Some("relic".into()), ..Default::default() };
        let mut st = role_state("extract", 1, 0.0, 0.0, relic);
        st.round = 1;
        for a in st.activated.iter_mut() { *a = false; }
        st.positions[1] = vec![[100.0, 0.0, 0.0]];
        st.positions[0] = vec![[100.0, 0.0, 0.0]];
        let before = hand(&st, 2);
        st.alive[1] = 0;
        st.dormant[1] = true;
        st.dormant_wounds[1] = vec![6];
        assert_eq!(super::reserve_presence(&st, 1), 6.0 * 0.5 * 3.0 / 4.0);
        assert!(hand(&st, 2) > before, "the arriving reserve lifts its side's control share");
        assert_eq!(hand(&st, 2) + hand(&st, 1), 1.0 + 0.0, "a zero-sum pair");
    }

    /// D12c: the attacker's fogged view prices the hidden markers at 1/n relic value (the mean) minus
    /// 1/n trap cost, not at the best marker as if it were the known relic.
    #[test]
    fn hidden_markers_are_priced_at_one_over_n_relic_and_one_over_n_trap() {
        let hidden = crate::state::Marker { secret_hidden: true, ..Default::default() };
        let mut st = role_state("extract", 1, 30.0, 0.0, hidden.clone());
        for (x, z) in [(0.0, 0.0), (0.0, 18.0)] {
            st.objectives.push(crate::state::Objective { pos: [x * crate::IN2M, 0.0, z * crate::IN2M], owner: 0 });
            st.markers_meta.push(hidden.clone());
        }
        let mean = (0.75 + 0.0 + 0.75) / 3.0;
        let want = 0.5 * (mean - super::TRAP_COST / 3.0) + 0.25;
        assert!((hand(&st, 1) - want).abs() < 1e-12, "{} vs {want}", hand(&st, 1));
        assert!(want < 0.5 * 0.75 + 0.25, "less than the peeking value of the nearest marker");
        st.markers_meta[0].secret = Some("relic".into());
        st.markers_meta[0].secret_hidden = false;
        assert_eq!(hand(&st, 1), 0.5 * 0.75 + 0.25, "a known relic ends the guessing");
        let mut one = role_state("extract", 1, 30.0, 0.0, hidden);
        one.attacker = 1;
        assert!((hand(&one, 1) - (0.5 * (0.75 - super::TRAP_COST) + 0.25)).abs() < 1e-12, "n = 1: the marker IS the relic or the trap");
    }

    #[test]
    fn secret_hidden_round_trips_and_stays_out_of_older_records() {
        let mut st = role_state("extract", 1, 0.0, 0.0, crate::state::Marker::default());
        assert!(crate::io::plain_of(&st)["markers_meta"][0].get("secret_hidden").is_none());
        st.markers_meta[0].secret_hidden = true;
        assert_eq!(crate::io::plain_of(&st)["markers_meta"][0]["secret_hidden"], serde_json::json!(true));
    }
}
