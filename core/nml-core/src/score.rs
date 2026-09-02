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

/// `AiMissionEval._presence` ai_mission_eval.gd:591-617 — one unit's projected
/// hold strength at one marker, discounted per future activation still needed.
pub fn presence(state: &State, i: usize, obj_pos: [f64; 3], threat: f64) -> f64 {
    if state.alive[i] <= 0 {
        return 0.0;
    }
    if state.aircraft[i] {
        return 0.0;
    }
    let rounds_total = state.rounds_total;
    let round_now = state.round;
    let arrived_now = state.ambush_arrived_round[i] == round_now;
    if arrived_now && round_now >= rounds_total {
        return 0.0;
    }
    let d = control_gap_in(state, i, obj_pos);
    // `float(SoloController.sim_move_bands(su["unit"]).get("rush", 12))`
    // (ai_mission_eval.gd:602) — the LIVE read, which is what `State.bands`
    // carries (io.rs falls back to the profile's copy of the same call when a
    // corpus predates the per-activation stamp). Reading the profile directly
    // would answer 12" for a unit that picked up a `Slow` aura mid-game.
    let rush = state.bands[i].rush;
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
        return 0.0;
    }
    let mut strength = 0.0f64;
    for w in &state.wounds[i] {
        strength += *w as f64;
    }
    (strength - threat).max(0.0) * DISCOUNT.powf(needed as f64)
}

/// `AiMissionEval._objective_p` ai_mission_eval.gd:415-431 — the soft control
/// ratio at one marker; an unreachable marker keeps its owner (seize rule).
fn objective_p(state: &State, obj_index: usize, player: i64, incoming: Incoming) -> f64 {
    let obj = state.objectives[obj_index];
    let mut mine = 0.0f64;
    let mut theirs = 0.0f64;
    for i in 0..state.units() {
        let p = presence(state, i, obj.pos, threat_of(incoming, i));
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
pub fn score_hand(state: &State, player: i64, incoming: Incoming) -> f64 {
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
            let pctrl = objective_p(state, i, player, incoming);
            if ob == player {
                deff = 1.0 - pctrl;
            } else {
                att = pctrl;
            }
        }
        return (0.5 + 0.5 * (att - DESTROY_DEFENCE_WEIGHT * deff)).clamp(0.0, 1.0);
    }
    let mut total = 0.0f64;
    for i in 0..state.objectives.len() {
        total += objective_p(state, i, player, incoming);
    }
    total / state.objectives.len() as f64
}

/// `AiMissionEval.score` ai_mission_eval.gd:344-354 with `fit_mode == false`.
pub fn score(state: &State, player: i64, incoming: Incoming) -> f64 {
    score_hand(state, player, incoming)
}

/// v303 — survival-discounted presence: same projection as `presence`, times
/// ((S - threat) / S)^needed, the odds of still being alive after `needed`
/// rounds of the same reply fire on the way in (S = current strength).
fn presence_v303(state: &State, i: usize, obj_pos: [f64; 3], threat: f64) -> f64 {
    let base = presence(state, i, obj_pos, threat);
    // Round-by-round mirror of _presence's needed arithmetic (score.rs:88-97).
    let d = control_gap_in(state, i, obj_pos);
    let raw = (d - OBJECTIVE_CONTROL_IN) / state.bands[i].rush.max(1.0);
    let mut needed = if d > OBJECTIVE_CONTROL_IN + CONTROL_EPS { raw.ceil() as i64 } else { 0 };
    if state.ambush_arrived_round[i] == state.round { needed = needed.max(1); }
    if state.shaken[i] { needed += 1; }
    let s: f64 = state.wounds[i].iter().map(|w| *w as f64).sum();
    if base <= 0.0 || s <= 0.0 || needed <= 0 { return base; }
    base * ((s - threat) / s).clamp(0.0, 1.0).powf(needed as f64)
}

/// v303 — `score_hand` over the survival-discounted presence (normal scoring);
/// destroy missions keep the v0 attack/defence formula, out of scope here.
fn score_hand_v303(state: &State, player: i64, incoming: Incoming) -> f64 {
    if state.objectives.is_empty() { return 0.5; }
    if !state.markers_meta.is_empty() && is_destroy_mission(state) {
        return score_hand(state, player, incoming);
    }
    let mut total = 0.0f64;
    for oi in 0..state.objectives.len() {
        let obj = state.objectives[oi];
        let mut mine = 0.0f64;
        let mut theirs = 0.0f64;
        for i in 0..state.units() {
            let p = presence_v303(state, i, obj.pos, threat_of(incoming, i));
            if state.player[i] == player { mine += p; } else { theirs += p; }
        }
        total += if mine + theirs <= 0.0 {
            if obj.owner == 0 { 0.5 } else if obj.owner == player { 1.0 } else { 0.0 }
        } else { mine / (mine + theirs) };
    }
    total / state.objectives.len() as f64
}

/// The evolved-hand-eval registry (NML-1073 evolved-eval lane, step 2). Every
/// call site keeps calling `score_hand`/`score_with` at variant 0 unchanged;
/// only `Rollout::blend_score` reads `Knobs::eval_variant` and comes through
/// here. The `match` deliberately has no arm past 0 — an evolved variant
/// registers a new arm later, this commit only adds the seam.
/// `acts::read_act_header` refuses any other value before a header is ever
/// played, so the fallback arm is an invariant, not a live path.
pub fn score_hand_variant(state: &State, player: i64, incoming: Incoming, eval_variant: i64) -> f64 {
    match eval_variant {
        0 => score_hand(state, player, incoming),
        303 => score_hand_v303(state, player, incoming),
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
        return score_hand_variant(state, player, incoming, eval_variant);
    };
    match fit.mode {
        FitMode::Residual => combine_residual(
            score_hand_variant(state, player, incoming, eval_variant),
            fit.score_fit(state, statics, player, incoming),
            fit.scale,
        ),
        FitMode::Blend => {
            let fb = fit.blend;
            (1.0 - fb) * score_hand_variant(state, player, incoming, eval_variant)
                + fb * fit.score_fit(state, statics, player, incoming)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{combine_residual, score_hand, score_hand_variant, NO_INCOMING};
    use crate::acts::read_act_header;
    use crate::io::state_from_json;
    use crate::state::ProfileCache;

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
        let direct = score_hand(&state, 1, NO_INCOMING);
        let via_seam = score_hand_variant(&state, 1, NO_INCOMING, 0);
        assert_eq!(direct, via_seam, "variant 0 must be byte-identical to the direct call");
        assert_eq!(direct, 0.5, "no objectives -> score_hand's trivial branch");
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
}
