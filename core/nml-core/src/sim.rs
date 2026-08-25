//! `BattleSim.resolve` (battle_sim.gd:570-652) for every action kind the
//! rollout policy produces — HOLD, ADVANCE, RUSH, CHARGE — and
//! `BattleSim.reply_threat` (:1003-1024), the expected reply that prices the
//! planner's RICH leaf (ai_planner.gd:508-510).
//!
//! The two A/B seams are read from the corpus header (`Seams`, ai_planner.gd:
//! 483-489), never guessed: `spacing` switches the `_spacing_fraction` clamp
//! (battle_sim.gd:521-563, :590-592) on, `cast` switches the cast sub-phase
//! (:602-607) on — the latter is plan step M1-3b and is REPORTED, not faked.
//! With `cast` off the LEGACY spell rider inside the shoot branch runs (:621-628).

use crate::combat::{
    at_or_below_half, effective_attacks, melee_ev, morale_target, shoot_ev,
    should_test_shooting_morale,
};
use crate::geom;
use crate::io::{Action, Seams};
use crate::spell::spell_ev_of;
use crate::state::State;
use crate::unit::{Ctx, UnitStatic};
use crate::IN2M;

/// `BattleSim.CONTACT_IN` battle_sim.gd:655 — the charge's contact ring.
pub const CONTACT_IN: f64 = 1.0;
/// `SoloController.UNIT_SPACING_IN` solo_controller.gd:70 — the no-go buffer
/// every OTHER unit's models project around themselves.
pub const UNIT_SPACING_IN: f64 = 1.0;
/// `SeparationChecker.DEFAULT_BASE_RADIUS_M` separation_checker.gd:81 — the
/// fallback when a snapshot carries no radius for a model.
pub const DEFAULT_BASE_RADIUS_M: f64 = 0.016;
/// The `_spacing_fraction` binary search runs exactly 8 halvings
/// (battle_sim.gd:552) and the fallback sweep exactly 8 descending samples
/// (:558-561). Both counts are rule data: they set the granularity of the
/// clamp, so a different number is a different game.
pub const SPACING_BISECTIONS: usize = 8;
pub const SPACING_SAMPLES: usize = 8;

/// `AiDecision.Action` ai_decision.gd:16.
pub const HOLD: i64 = 0;
pub const ADVANCE: i64 = 1;
pub const RUSH: i64 = 2;
pub const CHARGE: i64 = 3;

/// Why a node could not be resolved by this port — reported by name with a
/// count, never silently skipped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Unsupported {
    /// An action kind outside HOLD/ADVANCE/RUSH/CHARGE — KITE (4) has no
    /// `resolve` branch of its own in the GDScript either.
    ActionKind(i64),
    /// The action names a unit the state does not carry.
    UnknownUnit,
    /// A MOVED unit that also shoots: `_los_clear` (battle_sim.gd:666-670)
    /// re-probes with the POST-move centre, and the recorded `los_pairs` of the
    /// pre-move state cannot answer that. Never occurs in the recorded corpus
    /// (`_policy_candidates` ai_planner.gd:517-545 pairs a shoot only with HOLD).
    MovedShootLos,
    /// The corpus was recorded with `NML_SIM_CAST=1`, so `resolve` ran the cast
    /// sub-phase (battle_sim.gd:856-984) — plan step M1-3b, not this port.
    CastPhase,
}

/// `BattleSim._los_clear` battle_sim.gd:666-670, read off the recorded answers.
/// No matrix = no `los_blocked` seam on the state = clear for every pair.
#[inline]
fn los_clear(state: &State, i: usize, j: usize) -> bool {
    match &state.los_pairs {
        None => true,
        Some(m) => m[i * state.units() + j],
    }
}

/// `BattleSim._wounds_left` battle_sim.gd:1057-1061.
#[inline]
fn wounds_left(state: &State, i: usize) -> i64 {
    state.wounds[i].iter().sum()
}

/// `BattleSim._below_half` battle_sim.gd:1066-1072 — a single-model unit
/// measures tough WOUNDS against the model's max, a multi-model unit its alive
/// count against its starting size.
fn below_half(state: &State, us: &UnitStatic, i: usize) -> bool {
    if us.model_count == 1 {
        return at_or_below_half(wounds_left(state, i), us.wounds_max.first().copied().unwrap_or(0));
    }
    at_or_below_half(state.alive[i], us.model_count)
}

/// `BattleSim._morale_fails_expected` battle_sim.gd:1082-1090 — Shaken always
/// fails; otherwise the quality target's fail chance, halved by Fearless, and a
/// fail at 50% or worse.
fn morale_fails_expected(state: &State, us: &UnitStatic, i: usize) -> bool {
    if state.shaken[i] {
        return true;
    }
    let mut fail_p = (morale_target(us.quality, state.morale_bonus[i]) - 1) as f64 / 6.0;
    if us.fearless {
        fail_p *= 0.5;
    }
    fail_p >= 0.5
}

/// `BattleSim._apply_expected_wounds` battle_sim.gd:1027-1054 — expected unsaved
/// wounds fill model by model in ARRAY order; the sub-wound remainder stays on
/// the TARGET as `wound_frac` and joins the next volley instead of being floored
/// away. `stochastic_rng` is null in every rollout node, so only the expectation
/// branch exists here.
fn apply_expected_wounds(state: &mut State, ti: usize, ev: f64) {
    let pool = state.wound_frac[ti] + ev;
    let mut left = pool.floor() as i64;
    state.wound_frac[ti] = pool - (left as f64);
    while left > 0 && !state.wounds[ti].is_empty() {
        let take = left.min(state.wounds[ti][0]);
        state.wounds[ti][0] -= take;
        left -= take;
        if state.wounds[ti][0] <= 0 {
            state.wounds[ti].remove(0);
            state.positions[ti].remove(0);
            // radii stay aligned with positions or the base-edge measure lies.
            if !state.radii[ti].is_empty() {
                state.radii[ti].remove(0);
            }
        }
    }
    state.alive[ti] = state.positions[ti].len() as i64;
}

/// `BattleSim._expected_shooting_morale` battle_sim.gd:1096-1105 — a shooting
/// fail is SHAKEN, never a Rout (Rout exists only in melee).
fn expected_shooting_morale(
    state: &mut State,
    us: &UnitStatic,
    ti: usize,
    alive_before: i64,
    wounds_before: i64,
) {
    if us.model_count == 1 {
        if state.alive[ti] > 0
            && wounds_left(state, ti) < wounds_before
            && below_half(state, us, ti)
            && morale_fails_expected(state, us, ti)
        {
            state.shaken[ti] = true;
        }
        return;
    }
    if should_test_shooting_morale(alive_before, state.alive[ti], us.model_count)
        && morale_fails_expected(state, us, ti)
    {
        state.shaken[ti] = true;
    }
}

/// `BattleSim._ctx_of(su)` battle_sim.gd:701-712, SHOOTING half: the static
/// template with the snapshot's live `alive` and `in_cover` written over it.
/// (`melee` only adds the fatigue flag, which no shooting call sets.)
#[inline]
fn ctx_of(us: &UnitStatic, state: &State, i: usize) -> Ctx {
    let mut c = us.ctx;
    c.models = state.alive[i];
    c.in_cover = state.in_cover[i];
    c
}

/// `BattleSim._ctx_of(su, true)` battle_sim.gd:701-708, MELEE half: the same
/// context plus the snapshot's fatigue flag, which the EV layer is blind to and
/// which turns the striker's to-hit into a flat unmodified 6 (p.9).
#[inline]
fn ctx_of_melee(us: &UnitStatic, state: &State, i: usize) -> Ctx {
    let mut c = ctx_of(us, state, i);
    c.fatigued = state.fatigued[i];
    c
}

/// Scratch buffers so a threat sweep allocates once per call, not per pair.
#[derive(Default)]
pub struct Scratch {
    keep: Vec<usize>,
    attacks: Vec<i64>,
}

/// `BattleSim._profiles_of(su, false, d)` battle_sim.gd:714-749 fused with the
/// distance gate of `AiShooting.profiles_in_range` (ai_shooting.gd:16-17): the
/// merged ranged set is precomputed per unit, so all that is left per call is
/// the range filter and the survivor scaling.
fn profiles_of(us: &UnitStatic, alive: i64, d: f64, sc: &mut Scratch) {
    sc.keep.clear();
    sc.attacks.clear();
    for (i, p) in us.shoot.iter().enumerate() {
        if (p.range as f64) < d {
            continue;
        }
        sc.keep.push(i);
        sc.attacks.push(effective_attacks(p.attacks, alive, us.model_count));
    }
}

/// `BattleSim._profiles_of(su, true)` battle_sim.gd:714-749, MELEE half: every
/// melee profile strikes (no range gate), each with its survivor-scaled attack
/// count. Fills `sc.attacks` index-parallel to `us.melee`.
fn melee_profiles_of(us: &UnitStatic, alive: i64, sc: &mut Scratch) {
    sc.attacks.clear();
    for p in &us.melee {
        sc.attacks.push(effective_attacks(p.attacks, alive, us.model_count));
    }
}

/// `BattleSim._expected_melee_morale` battle_sim.gd:1111-1125 — the side that
/// dealt FEWER wounds tests (a tie means nobody); a fail at or below half is a
/// ROUT, and the loser leaves the board: wounds, positions and radii cleared,
/// `alive` 0. `wound_frac` is deliberately NOT cleared — the GDScript leaves it
/// standing too.
fn expected_melee_morale(
    state: &mut State,
    statics: &[UnitStatic],
    si: usize,
    su_before: i64,
    ti: usize,
    tu_before: i64,
) {
    let dealt_by_su = tu_before - wounds_left(state, ti);
    let dealt_by_tu = su_before - wounds_left(state, si);
    if dealt_by_su == dealt_by_tu {
        return;
    }
    let li = if dealt_by_su > dealt_by_tu { ti } else { si };
    let ul = &statics[state.roster.profile[li]];
    if state.alive[li] <= 0 || !morale_fails_expected(state, ul, li) {
        return;
    }
    if below_half(state, ul, li) {
        state.wounds[li].clear();
        state.positions[li].clear();
        state.radii[li].clear();
        state.alive[li] = 0;
    } else {
        state.shaken[li] = true;
    }
}

/// `BattleSim._spacing_fraction` battle_sim.gd:521-563 — the largest fraction
/// of `delta` that leaves every mover model clear of every OTHER alive unit's
/// models (horizontal distance only, the `control_gap_in` convention).
///
/// The three-case ladder is load-bearing and reproduced in order: (1) the full
/// move is legal -> 1.0 regardless of the start; (2) the START is legal -> an
/// 8-step binary search, which is monotone only from a clear start; (3) both
/// ends illegal -> 8 descending samples, largest legal wins, else 0.0.
fn spacing_fraction(state: &State, mi: usize, delta: geom::V3) -> f64 {
    // `Vector3.length_squared()` — f32, like every other Vector3 read.
    if delta[0] * delta[0] + delta[1] * delta[1] + delta[2] * delta[2] <= 0.0 {
        return 1.0;
    }
    let buffer_m = UNIT_SPACING_IN * IN2M;
    let mut obstacles: Vec<(geom::V3, f64)> = Vec::new();
    for oi in 0..state.units() {
        if oi == mi {
            continue;
        }
        let radii = &state.radii[oi];
        for (k, pos) in state.positions[oi].iter().enumerate() {
            let r = radii.get(k).copied().unwrap_or(DEFAULT_BASE_RADIUS_M);
            obstacles.push((geom::to_f32(*pos), r + buffer_m));
        }
    }
    if obstacles.is_empty() {
        return 1.0;
    }
    let legal = |t: f64| -> bool {
        let step = geom::mul(delta, t);
        for (i, own) in state.positions[mi].iter().enumerate() {
            let own_r = state.radii[mi].get(i).copied().unwrap_or(DEFAULT_BASE_RADIUS_M);
            let q = geom::add(geom::to_f32(*own), step);
            for (oc, r) in &obstacles {
                let flat: geom::V3 = [q[0] - oc[0], 0.0, q[2] - oc[2]];
                if (geom::length(flat) as f64) < r + own_r {
                    return false;
                }
            }
        }
        true
    };
    if legal(1.0) {
        return 1.0;
    }
    if legal(0.0) {
        let (mut lo, mut hi) = (0.0f64, 1.0f64);
        for _ in 0..SPACING_BISECTIONS {
            let mid = (lo + hi) * 0.5;
            if legal(mid) {
                lo = mid;
            } else {
                hi = mid;
            }
        }
        return lo;
    }
    for i in 0..SPACING_SAMPLES {
        let t = 1.0 - (i as f64) * 0.125;
        if legal(t) {
            return t;
        }
    }
    0.0
}

/// The reply-threat volley of `si` onto `ti`: `AiEv.shoot_ev(...) +
/// spell_ev_of(...)["ev"]` — battle_sim.gd:1016-1017, "magic is part of the
/// reply". Returns (ev, spell token cost); `reply_threat` discards the cost,
/// `resolve`'s shoot branch spends it.
fn volley_ev(
    statics: &[UnitStatic],
    state: &State,
    si: usize,
    ti: usize,
    d: f64,
    sc: &mut Scratch,
) -> (f64, i64) {
    let us = &statics[state.roster.profile[si]];
    let ut = &statics[state.roster.profile[ti]];
    profiles_of(us, state.alive[si], d, sc);
    let att = ctx_of(us, state, si);
    let def = ctx_of(ut, state, ti);
    let shooting = shoot_ev(&us.shoot, &sc.keep, &sc.attacks, &att, &def, d);
    let (sp_ev, sp_cost) = spell_ev_of(us.is_caster, &us.spells, state.casts[si], &def, d);
    (shooting + sp_ev, sp_cost)
}

/// `BattleSim.reply_threat` battle_sim.gd:1003-1024 — every living enemy
/// activates once and shoots its best-EV visible target. The result is indexed
/// by CAPTURE order; the GDScript keys it by unit key and
/// `AiMissionEval._objective_p` (:413) reads it back the same way.
///
/// V0 simplifications kept verbatim from :999-1002: shooting only (no charge
/// reply), capture-time sight lines, already-activated enemies still count.
/// The strict `>` and the `best_ev = 0.0` start are load-bearing: a pairing
/// worth exactly nothing never becomes the pick, so no entry is written.
pub fn reply_threat(statics: &[UnitStatic], state: &State, player: i64) -> Vec<f64> {
    let n = state.units();
    let mut incoming = vec![0.0f64; n];
    let mut sc = Scratch::default();
    for e in 0..n {
        if state.player[e] == player || state.alive[e] <= 0 {
            continue;
        }
        let mut best_key: Option<usize> = None;
        let mut best_ev = 0.0f64;
        for m in 0..n {
            if state.player[m] != player
                || state.alive[m] <= 0
                || !state.sees(e, state.key(m))
                || !los_clear(state, e, m)
            {
                continue;
            }
            let d = geom::dist_in(&state.positions[e], &state.positions[m]);
            let (ev, _) = volley_ev(statics, state, e, m, d, &mut sc);
            if ev > best_ev {
                best_ev = ev;
                best_key = Some(m);
            }
        }
        if let Some(m) = best_key {
            incoming[m] += best_ev;
        }
    }
    incoming
}

/// `BattleSim.resolve` battle_sim.gd:570-652 — one activation resolved IN
/// EXPECTATION on a clone, for HOLD, ADVANCE, RUSH and CHARGE.
///
/// `cover_dest` is the recorded terrain answer (the mover's cover at its
/// destination): the core carries no terrain grid, so the one boolean the
/// `terrain_at` Callable produces at :595 is supplied, not computed. Everything
/// else — positions, the spacing clamp, wounds, radii, flags, casts, melee and
/// morale — is computed here.
///
/// `seams` comes from the corpus header, so the port takes the same branch the
/// recording did. A corpus with `cast` on is REPORTED as unsupported rather
/// than resolved with the legacy rider, which would silently differ.
///
/// NOTE on the produced state's `los_pairs`: it is the PARENT's matrix, which
/// goes stale the moment a unit moves. Nothing in this port reads it afterwards
/// (the parity gate re-reads the recorded matrix of each state), and a chained
/// `resolve -> reply_threat` in Rust needs the terrain grid, which is M1-5 work.
pub fn resolve(
    statics: &[UnitStatic],
    state: &State,
    action: &Action,
    cover_dest: Option<bool>,
    seams: Seams,
) -> Result<State, Unsupported> {
    let kind = action.kind;
    if kind != HOLD && kind != ADVANCE && kind != RUSH && kind != CHARGE {
        return Err(Unsupported::ActionKind(kind));
    }
    if seams.cast {
        return Err(Unsupported::CastPhase);
    }
    let Some(&si) = state.roster.index.get(action.unit.as_str()) else {
        return Err(Unsupported::UnknownUnit);
    };
    let shoot_key = action.shoot.clone().unwrap_or_default();
    let pi_s = state.roster.profile[si];
    let mut next = state.clone();
    let was_shaken = next.shaken[si];
    let mut sc = Scratch::default();

    // --- move (battle_sim.gd:575-596) ---
    // `SoloController.sim_move_bands(su["unit"])` is a pure read of the unit's
    // rules (bands + the Musician bonus, solo_controller.gd:4966-4982), flattened
    // into the profile table at capture; RUSH and CHARGE share the rush band.
    let band_in = match kind {
        ADVANCE => next.profiles.list[pi_s].move_bands.advance,
        RUSH | CHARGE => next.profiles.list[pi_s].move_bands.rush,
        _ => 0.0,
    };
    let mut moved = false;
    if band_in > 0.0 && action.dest.is_some() && !next.positions[si].is_empty() {
        moved = true;
        let dest = geom::to_f32(action.dest.unwrap());
        let centre = geom::centre(&next.positions[si]);
        let mut delta = geom::sub(dest, centre);
        let reach_m = band_in * IN2M;
        if (geom::length(delta) as f64) > reach_m {
            delta = geom::mul(geom::normalized(delta), reach_m);
        }
        // NML-1068: RUSH and CHARGE share this same translation — one clamp
        // covers both (battle_sim.gd:590-592).
        if seams.spacing {
            delta = geom::mul(delta, spacing_fraction(&next, si, delta));
        }
        for p in next.positions[si].iter_mut() {
            *p = geom::to_f64(geom::add(geom::to_f32(*p), delta));
        }
        if let Some(c) = cover_dest {
            next.in_cover[si] = c;
        }
    }
    // NML_SIM_CAST off: no cast sub-phase (battle_sim.gd:602-607).

    // --- shoot (battle_sim.gd:608-630); HOLD and ADVANCE only ---
    if !shoot_key.is_empty() && (kind == HOLD || kind == ADVANCE) {
        if moved {
            return Err(Unsupported::MovedShootLos);
        }
        if let Some(&ti) = next.roster.index.get(shoot_key.as_str()) {
            if next.sees(si, &shoot_key) && los_clear(&next, si, ti) {
                let d = geom::dist_in(&next.positions[si], &next.positions[ti]);
                let alive_before = next.alive[ti];
                let wounds_before = wounds_left(&next, ti);
                // Seam OFF: the legacy spell rider (battle_sim.gd:621-628) —
                // the spell's EV joins the volley and the caster pays its cost.
                let (volley, sp_cost) = {
                    let us = &statics[pi_s];
                    let ut = &statics[next.roster.profile[ti]];
                    profiles_of(us, next.alive[si], d, &mut sc);
                    let att = ctx_of(us, &next, si);
                    let def = ctx_of(ut, &next, ti);
                    let shooting = shoot_ev(&us.shoot, &sc.keep, &sc.attacks, &att, &def, d);
                    let (sp_ev, sp_cost) =
                        spell_ev_of(us.is_caster, &us.spells, next.casts[si], &def, d);
                    if sp_ev > 0.0 {
                        (shooting + sp_ev, sp_cost)
                    } else {
                        (shooting, 0)
                    }
                };
                next.casts[si] -= sp_cost; // 0 unless the spell rider fired
                apply_expected_wounds(&mut next, ti, volley);
                let ut = &statics[next.roster.profile[ti]];
                expected_shooting_morale(&mut next, ut, ti, alive_before, wounds_before);
            }
        }
    }

    // --- charge (battle_sim.gd:631-646) ---
    // No sight check here, only the CONTACT_IN ring measured AFTER the move.
    if kind == CHARGE {
        let charge_key = action.charge.clone().unwrap_or_default();
        let ti = if charge_key.is_empty() {
            None
        } else {
            next.roster.index.get(charge_key.as_str()).copied()
        };
        if let Some(ti) = ti {
            if geom::dist_in(&next.positions[si], &next.positions[ti]) <= CONTACT_IN {
                let tu_before = wounds_left(&next, ti);
                let su_before = wounds_left(&next, si);
                // The charger strikes: charging profiles, its OWN fatigue state
                // (still the pre-charge one), the defender's plain context.
                let ev = {
                    let us = &statics[pi_s];
                    let ut = &statics[next.roster.profile[ti]];
                    let att = ctx_of_melee(us, &next, si);
                    let def = ctx_of(ut, &next, ti);
                    melee_profiles_of(us, next.alive[si], &mut sc);
                    melee_ev(&us.melee, &sc.attacks, &att, &def, true)
                };
                apply_expected_wounds(&mut next, ti, ev);
                next.fatigued[si] = true;
                if next.alive[ti] > 0 {
                    // Survivors strike back, already survivor-scaled by the
                    // updated `alive`. W-P1 parity (p.9): the strike-back
                    // fatigues the DEFENDER too.
                    let ev_back = {
                        let ut = &statics[next.roster.profile[ti]];
                        let us = &statics[pi_s];
                        let att = ctx_of_melee(ut, &next, ti);
                        let def = ctx_of(us, &next, si);
                        melee_profiles_of(ut, next.alive[ti], &mut sc);
                        melee_ev(&ut.melee, &sc.attacks, &att, &def, false)
                    };
                    apply_expected_wounds(&mut next, si, ev_back);
                    next.fatigued[ti] = true;
                }
                expected_melee_morale(&mut next, statics, si, su_before, ti, tu_before);
            }
        }
    }

    // --- shaken recovery (battle_sim.gd:648-650) ---
    if was_shaken && kind == HOLD && shoot_key.is_empty() {
        next.shaken[si] = false;
    }
    next.activated[si] = true;
    Ok(next)
}
