//! `AiPlanner.candidates` (ai_planner.gd:909-940) and every helper it reaches —
//! the LIVE planner menu, the set the 1-ply search pays a full rollout per entry
//! for. Tactical points, not a grid: hold; hold + best-EV shoot; one rush per
//! objective; one charge on the best hurtable target; one retreat point away
//! from the nearest threat; the patient safe advance; the second wave.
//!
//! Iteration is strictly in the state's CAPTURE order (`enemy_keys`,
//! `nearest_enemy`, `second_wave`'s two unit walks) and every argmax keeps the
//! FIRST winner (`>`, never `>=`) — both are load-bearing, because the GDScript
//! walks Dictionaries whose insertion order is roster order.
//!
//! Two seams the corpus this was gated on does not stamp, mirrored as ABSENT
//! rather than omitted:
//!   * `state["los_blocked"]` — the arena never wires it, so `_safe_advance`'s
//!     open-fire-line penalty (ai_planner.gd:773-785) can never fire. It is NOT
//!     ported: it probes sight from an enemy centre to the CANDIDATE POINT, and
//!     no capture records that. See the note at the call site.
//!   * `SoloController.forces_hold` — no unit in the arena corpus carries
//!     Immobile or Artillery, so the early return is ported but ungated.

use serde::Deserialize;

use crate::combat::{melee_ev, profile_ev, shoot_ev, SIX_P};
use crate::geom::{self, V3};
use crate::sim::{ctx_of, melee_profiles_of, profiles_of, Scratch, ADVANCE, CHARGE, HOLD, RUSH};
use crate::state::{State, Weapon};
use crate::terrain::{gives_cover, Terrain};
use crate::unit::{Ctx, ShootProfile, UnitStatic};
use crate::{CONTACT_IN, IN2M};

/// `AiPlanner.RETREAT_GOAL_IN` ai_planner.gd:11 — a far marker; the band clamp
/// in `resolve` turns it into one move away, so the MENU never clamps it.
pub const RETREAT_GOAL_IN: f64 = 100.0;
/// `AiPlanner.SAFE_LINE_COVER_BONUS_IN` ai_planner.gd:12 (D22).
pub const SAFE_LINE_COVER_BONUS_IN: f64 = 6.0;
/// `AiPlanner.SAFE_LINE_OPEN_LINE_PENALTY_IN` ai_planner.gd:13 (D22).
pub const SAFE_LINE_OPEN_LINE_PENALTY_IN: f64 = 2.0;
/// `SoloController.FUTILE_CHARGE_EV` solo_controller.gd:1390 — the bar a charge
/// target must clear before it may enter the menu at all.
pub const FUTILE_CHARGE_EV: f64 = 0.2;
/// `SeparationChecker.DEFAULT_BASE_RADIUS_M` — `edge_gap_in`'s per-model fallback.
pub const DEFAULT_BASE_RADIUS_M: f64 = 0.016;
/// The half-inch grid `_safe_advance` probes safety on (ai_planner.gd:756).
pub const SAFE_STEP_IN: f64 = 0.5;
/// How many of the safest points the D22 scoring probes (ai_planner.gd:768).
pub const SAFE_FRONTIER: usize = 8;
/// `_second_wave`'s three thresholds — ai_planner.gd:1157, :1181, :1187.
pub const WAVE_RING_IN: f64 = 3.0;
pub const WAVE_FRIEND_MIN_IN: f64 = 4.0;
pub const WAVE_IDLE_MIN_IN: f64 = 9.0;
/// The support distance a second wave stops at: next round's rush plus 2".
pub const WAVE_SUPPORT_SLACK_IN: f64 = 2.0;

/// One planner candidate, in the PLAIN form `AiPlanner._plain_candidates`
/// (ai_planner.gd:108-116) writes into `trace.menus` — a Vector3 `dest`
/// flattened by `BattleSim._plain_vec3` (:1445) and everything else verbatim.
/// `patient` and `wave` are FLAGS the GDScript only stamps on the candidate that
/// carries them; `wave` carries the REASON string, not a bool.
#[derive(Debug, Clone, Default, Deserialize)]
pub struct Candidate {
    pub unit: String,
    pub kind: i64,
    #[serde(default)]
    pub dest: Option<[f64; 3]>,
    #[serde(default)]
    pub shoot: Option<String>,
    #[serde(default)]
    pub charge: Option<String>,
    #[serde(default)]
    pub patient: bool,
    #[serde(default)]
    pub wave: Option<String>,
}

impl Candidate {
    pub fn new(unit: &str, kind: i64) -> Candidate {
        Candidate { unit: unit.to_string(), kind, ..Candidate::default() }
    }
}

/// The two menu constants a parity test has to be able to MOVE, so that green
/// can be shown to be earned rather than accidental. Every shipping call uses
/// `Tuning::default()`, which is the GDScript's own pair of numbers; the tests
/// perturb one at a time and count the candidates that then stop matching.
#[derive(Debug, Clone, Copy)]
pub struct Tuning {
    /// `AiPlanner.SAFE_LINE_COVER_BONUS_IN` — 6.0 in the game.
    pub cover_bonus_in: f64,
    /// The p.13 Strider/Flying difficult-terrain exemption inside the charge gate.
    pub honour_no_difficult: bool,
    /// Whether the CALLER wired a charge-legality gate at all. `state[
    /// "charge_illegal"]` is a Callable the arena stamps (solo_controller.gd:
    /// 3002) and `tools/core_selfplay.gd` never does — and both menu sites read
    /// it as `illegal_cb.is_valid() and illegal_cb.call(...)` (ai_planner.gd:
    /// 1024/1308), so a gateless caller offers charges the gate would refuse.
    /// `false` reproduces THAT menu; `true` (the default, and every arena
    /// corpus) keeps the gate. The act corpus records the same bit per
    /// activation as `charge_gate` (act_recorder.gd:73).
    pub charge_gate: bool,
    /// NML-1161 — whether the menu's shoot leg asks the RESOLVE's whole
    /// question. `AiPlanner._best_shoot` (ai_planner.gd:1372-1385) tests
    /// `BattleSim.sees` alone, while `BattleSim.resolve` (:770-773) ANDs it
    /// with `_los_clear`; on the TABLE that costs nothing, because no real game
    /// ever stamps `state["los_blocked"]` and `_los_clear` is true for every
    /// pair. In self-play it is the whole defect: `tools/core_selfplay.gd:675`
    /// DOES stamp it, so the menu offers shots the resolve then silently drops,
    /// and a dropped volley leaves a state bit-identical to plain HOLD — which
    /// the eval scores equal and the argmax's first-wins tie-break hands to the
    /// do-nothing. `false` (the default, and every corpus) reproduces the
    /// GDScript menu exactly; `true` makes the two legs ask one question.
    pub shoot_los: bool,
    /// NML-1157 — the MENU reads a joined unit the way GF Advanced Rules
    /// v3.5.1 p.14 writes it ("when a Hero joins a unit, they count as part of
    /// that unit"), and a unit offers the charge it can REACH as well as the
    /// one it scores best.
    ///
    /// Two halves, one bit, because they are the same mistake seen twice: with
    /// the hero its own target, `charge_score` (`:195`) always prefers the
    /// smallest strike-back on the board, and with exactly ONE charge
    /// candidate per unit that preference costs the whole activation. Measured
    /// on `~/selfplay_out/gen0_teacher`, 796 replayed activations: 544 of 787
    /// charge offers (69 %) name a joined hero, only 51 (6 %) name the nearest
    /// enemy, and 134 of the 144 activations with an enemy inside 2" are
    /// offered a charge at somebody else instead.
    ///
    /// Default OFF: every recorded corpus replays with the identical menu, so
    /// GATE G2 (`tests/menu.rs`) and the act corpora do not move.
    pub target_units: bool,
    /// W1 (AUDIT_rulebook_flanks_2026-09-02, top-1) — the ADVANCE+shoot leg of
    /// `AiPlanner.candidates_wide` (ai_planner.gd:1145-1157). Every shoot
    /// target in this menu hangs on HOLD, so the search can only fire by
    /// STANDING STILL; the table added this leg on 16.08. for exactly that
    /// reason ("the policy could fire only by standing still ... it moved and
    /// stopped fighting"), and the engine has always resolved the pair
    /// (`sim.rs:3102` fires a volley for HOLD **and** ADVANCE). `true` offers,
    /// per enemy the unit could shoot AFTER its advance, one ADVANCE at that
    /// enemy's centre carrying the shot. Default OFF, so every recorded corpus
    /// replays with the identical menu.
    pub wide_shoot: bool,
}

impl Default for Tuning {
    fn default() -> Self {
        Tuning {
            cover_bonus_in: SAFE_LINE_COVER_BONUS_IN,
            honour_no_difficult: true,
            charge_gate: true,
            shoot_los: false,
            target_units: false,
            wide_shoot: false,
        }
    }
}

/// `SoloController.forces_hold` solo_controller.gd:6867-6872 — Immobile and
/// Artillery may only Hold (p.13/p.57), so the menu for a carrier ends after
/// its two holds.
pub fn forces_hold(unit_rules: &[String]) -> bool {
    unit_rules.iter().any(|r| {
        let s = r.trim();
        s.starts_with("Immobile") || s.starts_with("Artillery")
    })
}

/// `AiArchetype.max_range_inches` ai_archetype.gd:60-64 over `_range`
/// (:69-75), which reads `range_value` — the very number
/// `BattleSim._unit_profile` (:1466) writes as the profile weapon's `range`.
/// A unit whose source is not an OPR unit has no weapons in its profile either,
/// so the `w = []` guard of `_safe_advance` (ai_planner.gd:718-720) needs no
/// separate port.
pub fn max_range_inches(weapons: &[Weapon]) -> i64 {
    let mut best = 0i64;
    for w in weapons {
        best = best.max(w.range as i64);
    }
    best
}

/// `AiPlanner._enemy_keys` ai_planner.gd:1217-1224 — living units of the other
/// side, in the state's own iteration (capture) order.
pub fn enemy_keys(state: &State, i: usize) -> Vec<usize> {
    enemy_keys_tuned(state, i, false)
}

/// The same list under `Tuning::target_units`: a joined Hero is PART of its
/// host (GF v3.5.1 p.14), so while the host still has living models the hero is
/// not a target of its own. The shipped table has never let one be named —
/// `solo_controller.gd:1197` ("a joined hero is PART of its host unit — you
/// target the unit, never the hero alone"), `main.gd:8452` `_solo_combat_unit`
/// and `main.gd:9166` all resolve a hero to its host — and this crate already
/// applies the identical guard in `tray_breath_attack` (`sim.rs:411`) and Hit &
/// Run (`sim.rs:890`). A hero whose host is dead "fights on alone" (p.14) and
/// stays a target, which is why the guard reads the HOST's `alive`.
pub fn enemy_keys_tuned(state: &State, i: usize, target_units: bool) -> Vec<usize> {
    let player = state.player[i];
    (0..state.units())
        .filter(|&k| state.player[k] != player && state.alive[k] > 0)
        .filter(|&k| {
            !target_units || !matches!(state.attached_to[k], Some(h) if state.alive[h] > 0)
        })
        .collect()
}

/// `AiPlanner._below_half` ai_planner.gd:1203-1206 — v0: model count against the
/// snapshot's POSITION SLOTS, deliberately conservative.
fn below_half(state: &State, i: usize) -> bool {
    state.alive[i] * 2 <= state.positions[i].len() as i64
}

/// `AiPlanner._gap_m` ai_planner.gd:790-796 — smallest model-to-model distance
/// (metres) after shifting `a` by `offset`. `minf` is an f64 min over f32 lengths.
fn gap_m(a: &[[f64; 3]], offset: V3, b: &[[f64; 3]]) -> f64 {
    let mut best = f64::INFINITY;
    for pa in a {
        let pa = geom::add(geom::to_f32(*pa), offset);
        for pb in b {
            let d = geom::length(geom::sub(pa, geom::to_f32(*pb))) as f64;
            if d < best {
                best = d;
            }
        }
    }
    best
}

/// `AiPlanner._best_shoot` ai_planner.gd:1227-1243 — best-EV visible target.
/// `best_ev` starts at 0.0 and the comparison is strict, so a pairing worth
/// exactly nothing never becomes the pick.
///
/// `shoot_los` (NML-1161) adds the resolve's second half, `State::los_clear`,
/// so the menu cannot offer a target the resolve will refuse. See
/// `Tuning::shoot_los` for why the GDScript needs no such switch and the
/// trainer does. NML-1157's `target_units` rides the same `Tuning`: both menu
/// legs ask ONE object which targets are legal to name.
pub fn best_shoot(
    state: &State,
    statics: &[UnitStatic],
    i: usize,
    sc: &mut Scratch,
    tuning: Tuning,
) -> Option<usize> {
    let us = &statics[state.roster.profile[i]];
    let mut best = None;
    let mut best_ev = 0.0f64;
    for e in enemy_keys_tuned(state, i, tuning.target_units) {
        if !state.sees(i, state.key(e)) || (tuning.shoot_los && !state.los_clear(i, e)) {
            continue;
        }
        let ut = &statics[state.roster.profile[e]];
        let d = geom::dist_in(&state.positions[i], &state.positions[e]);
        profiles_of(us, state.alive[i], d, sc);
        let att = ctx_of(us, state, i);
        let def = ctx_of(ut, state, e);
        let ev = shoot_ev(&us.shoot, &sc.keep, &sc.attacks, &att, &def, d);
        if ev > best_ev {
            best_ev = ev;
            best = Some(e);
        }
    }
    best
}

/// W1 — `AiPlanner.candidates_wide`'s ADVANCE+shoot leg (ai_planner.gd:
/// 1145-1157), the one action this menu has never been able to express: every
/// shoot target hangs on HOLD, so a search that wants to fire has to stand
/// still. The table added this leg on 16.08. after measuring the cost (the
/// clone stood still in 3.5 % of activations, rushed in 85 %, and its
/// clone-vs-clone games ended with a median 62 survivors against tree-vs-tree's
/// 54 — "it moved and stopped fighting"), and `sim::resolve` has always fired
/// the volley for ADVANCE as well as HOLD (`sim.rs:3102`).
///
/// Which enemies come back: those the HOLD-shoot leg's own two gates accept —
/// `State::sees`, plus `State::los_clear` under `Tuning::shoot_los` — scored
/// from the POST-ADVANCE distance instead of the standing one. The GDScript
/// gate is `_can_shoot_at(su, tu, max(gap - advance_in, 0))` (ai_planner.gd:
/// 1154-1155): the OPTIMISTIC gap, closing straight in at the full band, worst
/// case on purpose so the menu never deletes a shot the move could have set up.
/// `best_shoot`'s own bar (`shoot_ev > 0`, strict) is the bar here, so a target
/// out of every barrel's reach after the move scores 0 and never enters.
///
/// Sight is NOT re-probed at the destination: `sees`/`los_pairs` are recorded
/// per unit PAIR, not per point, so the post-advance answer does not exist in
/// the state. The advance band is the state's own `bands[i].advance` — the
/// GDScript adds `max_activation_advance_bonus_in` (Bounding/Quick/Teleport) on
/// top, which this crate does not model at all; the effect is a slightly
/// TIGHTER gate than the table's, i.e. this never offers a shot the GDScript
/// would refuse.
///
/// Capture order, first-wins, one entry per enemy — the same iteration every
/// other leg of this menu uses.
pub fn advance_shoots(
    state: &State,
    statics: &[UnitStatic],
    i: usize,
    sc: &mut Scratch,
    tuning: Tuning,
) -> Vec<usize> {
    let us = &statics[state.roster.profile[i]];
    let advance_in = state.bands[i].advance;
    let mut out = Vec::new();
    for e in enemy_keys_tuned(state, i, tuning.target_units) {
        if !state.sees(i, state.key(e)) || (tuning.shoot_los && !state.los_clear(i, e)) {
            continue;
        }
        let d = (geom::dist_in(&state.positions[i], &state.positions[e]) - advance_in).max(0.0);
        profiles_of(us, state.alive[i], d, sc);
        let att = ctx_of(us, state, i);
        let def = ctx_of(&statics[state.roster.profile[e]], state, e);
        if shoot_ev(&us.shoot, &sc.keep, &sc.attacks, &att, &def, d) > 0.0 {
            out.push(e);
        }
    }
    out
}

/// `AiEv.charge_score` ai_ev.gd:537-553 — the charge matchup tie-break: wounds
/// we deal (thinned first-order by the defender's Counter strike-first) minus
/// the wounds their strike-back deals, risk-weighted by our Fearless and Banner.
fn charge_score(
    ours: &[ShootProfile],
    our_attacks: &[i64],
    us: &Ctx,
    theirs: &[ShootProfile],
    their_attacks: &[i64],
    them: &Ctx,
) -> f64 {
    let mut dealt = melee_ev(ours, our_attacks, us, them, true);
    let mut counter_first = 0.0f64;
    for (k, p) in theirs.iter().enumerate() {
        if p.range <= 0 && p.counter {
            counter_first += profile_ev(p, their_attacks[k], them, us, 0.0, false);
        }
    }
    let pool = (us.models as f64 * us.tough.max(1) as f64).max(1.0);
    dealt *= (1.0 - counter_first / pool).clamp(0.0, 1.0);
    let taken = melee_ev(theirs, their_attacks, them, us, false);
    let mut risk_weight = if us.fearless { 0.5 } else { 1.0 };
    risk_weight *= (1.0 - us.morale_bonus as f64 * SIX_P).max(0.0);
    dealt - taken * risk_weight
}

/// `AiPlanner._best_charge` ai_planner.gd:1287-1318 — best hurtable melee target
/// by `charge_score`, with the controller's charge-legality gate and the futile
/// bar applied first.
///
/// NML-1073 S1d: the gate's `gap_in` is the RAW base-edge gap, clamped at 0 and
/// nothing subtracted — exactly what the TABLE's own charge re-gate passes
/// (`charge_illegal_why` -> `nearest_melee_gap_in`, solo_controller.gd:1406 /
/// :8042). S1b took `CHARGE_CONTACT_MARGIN_IN` off here, which widened the
/// menu's band by 0.25" against the body's and shifted the 6" difficult-cap
/// verdict inside the (5.75", 6.25"] window. The GDScript dropped that
/// subtraction at both menu sites (ai_planner.gd:1029-1030, :1303-1304); this
/// twin follows it.
pub fn best_charge(
    state: &State,
    terrain: &Terrain,
    statics: &[UnitStatic],
    i: usize,
    sc: &mut Scratch,
    tuning: Tuning,
) -> Option<usize> {
    let us_static = &statics[state.roster.profile[i]];
    if us_static.melee.is_empty() {
        return None;
    }
    melee_profiles_of(us_static, state.alive[i], sc);
    let our_attacks = sc.attacks.clone();
    let centre_us = geom::centre(&state.positions[i]);
    let mut best = None;
    let mut best_score = f64::NEG_INFINITY;
    for e in enemy_keys_tuned(state, i, tuning.target_units) {
        let gap_in = geom::edge_gap_in(
            &state.positions[i],
            &state.radii[i],
            &state.positions[e],
            &state.radii[e],
            DEFAULT_BASE_RADIUS_M,
        )
        .max(0.0);
        let centre_them = geom::centre(&state.positions[e]);
        if tuning.charge_gate
            && crate::gate::charge_illegal_tuned(
                state,
                terrain,
                i,
                e,
                gap_in,
                Some(centre_us),
                Some(centre_them),
                tuning.honour_no_difficult,
            )
        {
            continue;
        }
        let ut = &statics[state.roster.profile[e]];
        let us = ctx_of(us_static, state, i);
        let them = ctx_of(ut, state, e);
        if melee_ev(&us_static.melee, &our_attacks, &us, &them, true) < FUTILE_CHARGE_EV {
            continue;
        }
        melee_profiles_of(ut, state.alive[e], sc);
        let s = charge_score(&us_static.melee, &our_attacks, &us, &ut.melee, &sc.attacks, &them);
        if s > best_score {
            best_score = s;
            best = Some(e);
        }
    }
    best
}

/// NML-1157 — the nearest enemy this unit could actually REACH: the smallest
/// base-edge gap among the targets the charge gate and the futile bar both
/// accept. `best_charge` answers "who is the best matchup"; with one candidate
/// per unit that is the only question the search ever gets asked, and the
/// answer is a far hero. This answers "who is standing in front of me", and
/// `candidates_tuned` carries BOTH so there is a target decision to make.
///
/// The gate runs unconditionally here, not under `Tuning::charge_gate`: this
/// candidate is new, so it has no gateless GDScript to reproduce, and without
/// the gate "reachable" would not mean anything — `charge_illegal_tuned`
/// (`gate.rs:47`) is what carries the rush band, Melee Shrouding and the p.11
/// difficult corridor.
pub fn nearest_chargeable(
    state: &State,
    terrain: &Terrain,
    statics: &[UnitStatic],
    i: usize,
    sc: &mut Scratch,
    tuning: Tuning,
) -> Option<usize> {
    let us_static = &statics[state.roster.profile[i]];
    if us_static.melee.is_empty() {
        return None;
    }
    melee_profiles_of(us_static, state.alive[i], sc);
    let our_attacks = sc.attacks.clone();
    let us = ctx_of(us_static, state, i);
    let mut best = None;
    let mut best_gap = f64::INFINITY;
    for e in enemy_keys_tuned(state, i, tuning.target_units) {
        let gap_in = geom::edge_gap_in(
            &state.positions[i],
            &state.radii[i],
            &state.positions[e],
            &state.radii[e],
            DEFAULT_BASE_RADIUS_M,
        )
        .max(0.0);
        if gap_in >= best_gap {
            continue;
        }
        if crate::gate::charge_illegal_tuned(
            state,
            terrain,
            i,
            e,
            gap_in,
            None,
            None,
            tuning.honour_no_difficult,
        ) {
            continue;
        }
        let them = ctx_of(&statics[state.roster.profile[e]], state, e);
        if melee_ev(&us_static.melee, &our_attacks, &us, &them, true) < FUTILE_CHARGE_EV {
            continue;
        }
        best_gap = gap_in;
        best = Some(e);
    }
    best
}

/// `AiPlanner._nearest_enemy` ai_planner.gd:1285-1294.
pub fn nearest_enemy(state: &State, i: usize) -> Option<usize> {
    let mut best = None;
    let mut best_d = f64::INFINITY;
    for e in enemy_keys(state, i) {
        let d = geom::dist_in(&state.positions[i], &state.positions[e]);
        if d < best_d {
            best_d = d;
            best = Some(e);
        }
    }
    best
}

/// One enemy's threat footprint inside `_safe_advance` (ai_planner.gd:722-728).
struct Threat<'a> {
    positions: &'a [[f64; 3]],
    reach: f64,
}

/// `AiPlanner._safe_advance` ai_planner.gd:690-787 — the PATIENT advance:
/// toward the nearest objective, stopped at the strongest safety still
/// available (tier 1: outside every gun's reach; tier 2: outside every charge
/// reach). `None` when even charge safety is already lost or there is nothing to
/// walk toward.
pub fn safe_advance(state: &State, terrain: &Terrain, i: usize, tuning: Tuning) -> Option<Candidate> {
    let centre = geom::centre(&state.positions[i]);
    let mut best_d = f64::INFINITY;
    let mut goal: V3 = [0.0, 0.0, 0.0];
    for o in &state.objectives {
        let d = geom::length(geom::sub(geom::to_f32(o.pos), centre)) as f64;
        if d < best_d {
            best_d = d;
            goal = geom::to_f32(o.pos);
        }
    }
    if best_d.is_infinite() || best_d < 0.001 {
        return None;
    }
    let dir = geom::normalized(geom::sub(goal, centre));
    let band_m = state.bands[i].advance * IN2M;
    let mut full: Vec<Threat> = Vec::new();
    let mut charge_only: Vec<Threat> = Vec::new();
    for e in enemy_keys(state, i) {
        let w = &state.profile(e).weapons;
        let bands = state.bands[e];
        let charge_in = bands.rush + CONTACT_IN;
        full.push(Threat {
            positions: &state.positions[e],
            reach: (max_range_inches(w) as f64 + bands.advance).max(charge_in) * IN2M,
        });
        charge_only.push(Threat { positions: &state.positions[e], reach: charge_in * IN2M });
    }
    if full.is_empty() {
        return None;
    }
    let positions = &state.positions[i];
    for threats in [&full, &charge_only] {
        let zero: V3 = [0.0, 0.0, 0.0];
        if threats.iter().any(|e| gap_m(positions, zero, e.positions) <= e.reach) {
            continue; // this tier's safety is already lost — try the weaker tier
        }
        // D22 (grill 15.08.): among SAFE points, cover earns a bonus and every
        // OPEN enemy fire line beyond the first costs. Safety stays a half-inch
        // grid; the scoring probes only the safe frontier.
        let step = SAFE_STEP_IN * IN2M;
        let mut safe_ts: Vec<f64> = Vec::new();
        // The GDScript accumulates `t += step` in f64 — NOT `i * step`; the two
        // drift apart within a dozen steps and would move the frontier slice.
        let mut t = step;
        while t <= band_m + 0.0001 {
            let off = geom::mul(dir, t);
            if !threats.iter().any(|e| gap_m(positions, off, e.positions) <= e.reach) {
                safe_ts.push(t);
            }
            t += step;
        }
        if safe_ts.is_empty() {
            continue;
        }
        let frontier = &safe_ts[safe_ts.len().saturating_sub(SAFE_FRONTIER)..];
        let mut best_t = 0.0f64;
        let mut best_sc = f64::NEG_INFINITY;
        for &ft in frontier {
            let pnt = geom::add(centre, geom::mul(dir, ft));
            let mut s = ft / IN2M;
            if terrain.is_valid() && gives_cover(terrain.type_at(pnt)) {
                s += tuning.cover_bonus_in;
            }
            // OPEN-FIRE-LINE PENALTY, ai_planner.gd:773-785. It probes
            // `los_blocked(_centre(enemy), pnt)` — the PROBE POINT, which no
            // capture records, so until NML-1073 M3-5 this branch was absent
            // (the arena never stamps the seam and its corpora carry no
            // `los_pairs` at all). With the board in hand the probe is a
            // question the terrain can answer directly, which is the same
            // source `state["los_blocked"]` reads in `tools/core_selfplay.gd`.
            // Guarded exactly as the GDScript guards it — `los_blocked.
            // is_valid()`, i.e. a state that carries a sight matrix at all —
            // so a corpus without the seam keeps the old, penalty-free menu.
            if state.los_pairs.is_some() && terrain.is_valid() {
                let mut open_lines = 0i64;
                for e in enemy_keys(state, i) {
                    if !terrain.los_blocked(geom::centre(&state.positions[e]), pnt) {
                        open_lines += 1;
                    }
                    if open_lines >= 4 {
                        break;
                    }
                }
                s -= SAFE_LINE_OPEN_LINE_PENALTY_IN * (open_lines - 1).max(0) as f64;
            }
            if s > best_sc {
                best_sc = s;
                best_t = ft;
            }
        }
        if best_t > 0.001 {
            let mut c = Candidate::new(state.key(i), ADVANCE);
            c.dest = Some(geom::to_f64(geom::add(centre, geom::mul(dir, best_t))));
            c.patient = true;
            return Some(c);
        }
    }
    None
}

/// `AiPlanner._second_wave` ai_planner.gd:1141-1200 (D21/D23) — a follow-up move
/// toward where it is needed: a contested marker first, then a battered friend,
/// then the nearest FAR marker for an idle rear unit. The stop point is support
/// distance, so next round's rush reaches the goal.
pub fn second_wave(state: &State, i: usize) -> Option<Candidate> {
    let centre = geom::centre(&state.positions[i]);
    let me = state.player[i];
    let mut goal: Option<V3> = None;
    let mut why = "";
    let mut best_d = f64::INFINITY;
    let ring = WAVE_RING_IN * IN2M;
    for o in &state.objectives {
        let op = geom::to_f32(o.pos);
        let (mut friend_in, mut enemy_in) = (false, false);
        for f in 0..state.units() {
            if state.alive[f] <= 0 || f == i {
                continue;
            }
            let near = state.positions[f]
                .iter()
                .any(|pp| geom::length(geom::sub(geom::to_f32(*pp), op)) as f64 <= ring);
            if near {
                if state.player[f] == me {
                    friend_in = true;
                } else {
                    enemy_in = true;
                }
            }
        }
        if friend_in && enemy_in {
            let d = geom::length(geom::sub(op, centre)) as f64;
            if d < best_d {
                best_d = d;
                goal = Some(op);
                why = "contested marker";
            }
        }
    }
    if goal.is_none() {
        for f in 0..state.units() {
            if f == i || state.player[f] != me || state.alive[f] <= 0 {
                continue;
            }
            if state.shaken[f] || below_half(state, f) {
                let fc = geom::centre(&state.positions[f]);
                let d2 = geom::length(geom::sub(fc, centre)) as f64;
                if d2 > WAVE_FRIEND_MIN_IN * IN2M && d2 < best_d {
                    best_d = d2;
                    goal = Some(fc);
                    why = "battered friend";
                }
            }
        }
    }
    if goal.is_none() {
        for o in &state.objectives {
            let op = geom::to_f32(o.pos);
            let d3 = geom::length(geom::sub(op, centre)) as f64;
            if d3 / IN2M > WAVE_IDLE_MIN_IN && d3 < best_d {
                best_d = d3;
                goal = Some(op);
                why = "idle reserve moves up";
            }
        }
    }
    let goal = goal?;
    let rush_in = state.bands[i].rush;
    let dist_in = geom::length(geom::sub(goal, centre)) as f64 / IN2M;
    if dist_in <= 0.001 {
        return None;
    }
    let stop_in = (dist_in - (rush_in + WAVE_SUPPORT_SLACK_IN)).max(0.0);
    // `goal - (goal - centre).normalized() * stop_in * IN2M` — TWO f32 scalar
    // multiplies, left to right, then an f32 subtract.
    let step = geom::mul(geom::mul(geom::normalized(geom::sub(goal, centre)), stop_in), IN2M);
    let mut c = Candidate::new(state.key(i), ADVANCE);
    c.dest = Some(geom::to_f64(geom::sub(goal, step)));
    c.wave = Some(why.to_string());
    Some(c)
}

/// `AiPlanner.candidates` ai_planner.gd:909-940 — the live planner menu, in
/// build order. `unit` is the ROSTER index of the activating unit.
///
/// The GDScript reads `state["terrain_at"]` and `state["charge_illegal"]` off
/// the state; here they arrive as the header-built `Terrain` and the pure
/// `gate::charge_illegal`, which is the same truth by construction (NML-1073
/// M2-0d). `Knobs` is deliberately absent: the menu reads no search knob.
pub fn candidates(
    state: &State,
    terrain: &Terrain,
    statics: &[UnitStatic],
    unit: usize,
) -> Vec<Candidate> {
    let mut sc = Scratch::default();
    candidates_in(state, terrain, statics, unit, &mut sc)
}

/// Same menu against a caller-owned scratch buffer, so a sweep over a whole act
/// allocates once instead of per unit.
pub fn candidates_in(
    state: &State,
    terrain: &Terrain,
    statics: &[UnitStatic],
    unit: usize,
    sc: &mut Scratch,
) -> Vec<Candidate> {
    candidates_tuned(state, terrain, statics, unit, sc, Tuning::default())
}

/// One CHARGE candidate aimed at `e`, built the way both menu sites build it:
/// the destination is the TARGET UNIT'S CENTRE (`ai_planner.gd:1035`), which is
/// what `resolve`'s rigid arm then walks toward.
fn charge_at(state: &State, key: &str, e: usize) -> Candidate {
    let mut c = Candidate::new(key, CHARGE);
    c.dest = Some(geom::to_f64(geom::centre(&state.positions[e])));
    c.charge = Some(state.key(e).to_string());
    c
}

/// The same menu with the parity `Tuning` exposed — see `Tuning`. Shipping code
/// calls `candidates`/`candidates_in`; only the red proofs pass anything else.
pub fn candidates_tuned(
    state: &State,
    terrain: &Terrain,
    statics: &[UnitStatic],
    unit: usize,
    sc: &mut Scratch,
    tuning: Tuning,
) -> Vec<Candidate> {
    let key = state.key(unit);
    let mut out = vec![Candidate::new(key, HOLD)];
    if let Some(e) = best_shoot(state, statics, unit, sc, tuning) {
        let mut c = Candidate::new(key, HOLD);
        c.shoot = Some(state.key(e).to_string());
        out.push(c);
    }
    // NML-1020 lab half: Immobile/Artillery may only Hold (p.13/p.57) — the menu
    // for carriers ends here, so no playout can ever imagine them moving.
    if forces_hold(&state.profile(unit).special_rules) {
        return out;
    }
    for o in &state.objectives {
        let mut c = Candidate::new(key, RUSH);
        c.dest = Some(o.pos);
        out.push(c);
    }
    let scored = best_charge(state, terrain, statics, unit, sc, tuning);
    if let Some(e) = scored {
        out.push(charge_at(state, key, e));
    }
    // NML-1157: the SECOND charge candidate — the one this unit can reach. Only
    // when it is a different unit from the best-scoring one, so a menu never
    // carries the same charge twice.
    if tuning.target_units {
        if let Some(e) = nearest_chargeable(state, terrain, statics, unit, sc, tuning) {
            if Some(e) != scored {
                out.push(charge_at(state, key, e));
            }
        }
    }
    if let Some(t) = nearest_enemy(state, unit) {
        let centre = geom::centre(&state.positions[unit]);
        let away = geom::sub(centre, geom::centre(&state.positions[t]));
        if geom::length(away) as f64 > 0.001 {
            // `away.normalized() * RETREAT_GOAL_IN * IN2M` — two f32 scalar
            // multiplies. The goal is NOT clamped here: `resolve` owns the band.
            let step = geom::mul(geom::mul(geom::normalized(away), RETREAT_GOAL_IN), IN2M);
            let mut c = Candidate::new(key, ADVANCE);
            c.dest = Some(geom::to_f64(geom::add(centre, step)));
            out.push(c);
        }
    }
    if let Some(c) = safe_advance(state, terrain, unit, tuning) {
        out.push(c);
    }
    if let Some(c) = second_wave(state, unit) {
        out.push(c);
    }
    // W1: appended LAST, so an OFF menu is byte-identical and an ON menu only
    // ever GROWS at the tail — every recorded candidate keeps its index, which
    // is the imitation label the policy corpus trains on. The count is one per
    // shootable enemy and the search's `top_k` bounds what any of them cost.
    if tuning.wide_shoot {
        for e in advance_shoots(state, statics, unit, sc, tuning) {
            let mut c = Candidate::new(key, ADVANCE);
            c.dest = Some(geom::to_f64(geom::centre(&state.positions[e])));
            c.shoot = Some(state.key(e).to_string());
            out.push(c);
        }
    }
    out
}
