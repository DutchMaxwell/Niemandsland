//! The ROLLOUT POLICY — `AiPlanner._policy_candidates` (ai_planner.gd:649-677)
//! and `AiPlanner._policy_step` (:602-624), the greedy brain that plays every
//! imagined activation after the opener.
//!
//! It is deliberately a SMALLER menu than `menu::candidates`: hold (with the
//! best-EV shoot), one rush to the NEAREST objective only, the counter-charge,
//! the patient advance. No retreat point, no per-objective rush, no second
//! wave — the search pays for depth here, not for breadth.
//!
//! Every helper is the one `menu.rs` already ports (`best_shoot`, `best_charge`,
//! `safe_advance`): the GDScript calls the SAME four statics from both menus, so
//! a second copy here would be a second thing to keep in step.
//!
//! Three parity rules run through the whole file and are load-bearing:
//!   * iteration is CAPTURE order, never hash order (the GDScript walks a
//!     Dictionary whose insertion order is roster order);
//!   * every argmax keeps the FIRST winner (`>`, never `>=`);
//!   * the build order of the candidate list is part of the contract, because
//!     `_policy_step`'s tie-break is "first seen wins".

use crate::acts::{rule_on, EPOCH_8_PLANNER_MENU};
use crate::gate;
use crate::io::{Action, Seams};
use crate::menu::{best_charge, best_shoot, safe_advance, Candidate, Tuning};
use crate::fitted::Fitted;
use crate::score::{score_with, NO_INCOMING};
use crate::mv::reach::ReachIndex;
use crate::sim::{
    reply_threat, resolve_on_board_reach, trace_rule, Scratch, Unsupported, ADVANCE, CHARGE, HOLD,
    RUSH,
};
use crate::state::State;
use crate::terrain::{self, Terrain};
use crate::unit::UnitStatic;
use crate::{geom, IN2M, Objective};

/// The table half's own log line (#813, solo_controller.gd:2251) — the core's
/// demotion trace rides the same words, so both layers log the same rule.
const RUSH_DEMOTION_RULE: &str = "GF v3.5.1 p.7: a rush capped to the advance distance forfeits the shot for nothing — chose advances (demoted)";

/// Everything an imagined activation needs that does not change during a
/// rollout: the per-unit static closure, the board and the two A/B seams the
/// recording ran with.
#[derive(Clone, Copy)]
pub struct Policy<'a> {
    pub statics: &'a [UnitStatic],
    pub terrain: &'a Terrain,
    pub seams: Seams,
    /// NML-1073 M4-7 — the round's tier-2 obstacle index, built once from the
    /// planner's ROOT state (`plan::plan_with_rollout`) and shared by every
    /// imagined activation. `None` whenever `seams.path` is off, and also when
    /// the header carried no board.
    pub reach: Option<&'a ReachIndex>,
    /// The menu tuning — `Tuning::default()` everywhere except in a red proof.
    pub tuning: Tuning,
    /// TEST SEAM, `None` in every shipping call: forces every imagined
    /// activation onto the rich (`Some(true)`) or the cheap (`Some(false)`)
    /// leaf, instead of R9's `turn == me` split. It exists so a parity gate can
    /// PROVE that split is load-bearing rather than assert green against a
    /// rollout that might be scoring both sides the same way by accident.
    pub force_leaf: Option<bool>,
    /// NML-1142 — the trained eval, or `None` for the hand eval. It is the
    /// CALLER's job to leave this `None` unless the activation's recorded
    /// `AiMissionEval.fit_mode` was on; `Search::admissible` declines a
    /// `fit_mode` act that reaches it without one rather than quietly playing
    /// the other brain.
    pub fit: Option<&'a Fitted>,
    /// NML-1158b step 5 — the ORDER-mode policy net, or `None` for the hand
    /// order alone. Same contract as `fit`: the CALLER leaves this `None`
    /// unless `ActStatics.policy_mode == Order`; `Search::admissible`
    /// declines an `Order` act that reaches it without one.
    pub policy_net: Option<&'a crate::policy::Policy>,
}

impl<'a> Policy<'a> {
    pub fn new(statics: &'a [UnitStatic], terrain: &'a Terrain, seams: Seams) -> Policy<'a> {
        Policy {
            statics,
            terrain,
            seams,
            reach: None,
            tuning: Tuning::default(),
            force_leaf: None,
            fit: None,
            policy_net: None,
        }
    }

    /// `AiPlanner._policy_candidates` ai_planner.gd:649-677 — the restricted
    /// rollout menu, in build order:
    ///   1. HOLD, carrying the best-EV shoot when one exists;
    ///   2. RUSH to the NEAREST objective (one entry, not one per marker);
    ///   3. CHARGE on `_best_charge`;
    ///   4. the patient `_safe_advance`.
    /// A SHAKEN unit gets its recovery hold and nothing else — the same rule
    /// `plan()` applies (:132-133).
    pub fn policy_candidates(
        &self,
        state: &State,
        unit: usize,
        sc: &mut Scratch,
    ) -> Vec<Candidate> {
        let key = state.key(unit);
        if state.shaken[unit] {
            return vec![Candidate::hold(key)];
        }
        let mut hold = Candidate::hold(key);
        if let Some(e) = best_shoot(state, self.statics, unit, sc, self.tuning) {
            hold.shoot = Some(state.key(e).to_string());
        }
        let mut out = vec![hold];
        // The NEAREST objective, measured from the unit centre in the engine's
        // own f32 — `((o["pos"] as Vector3) - _centre(su)).length()`.
        let centre = geom::centre(&state.positions[unit]);
        let mut best_d = f64::INFINITY;
        let mut dest: Option<Objective> = None;
        for o in &state.objectives {
            let d = geom::length(geom::sub(geom::to_f32(o.pos), centre)) as f64;
            if d < best_d {
                best_d = d;
                dest = Some(*o);
            }
        }
        if let Some(o) = dest {
            // #812 core half — GF v3.5.1 p.7: Rush forbids shooting, so a rush
            // whose EXECUTABLE distance (p.11 difficult cap, mv/step.rs:598)
            // cannot beat the advance band is dominated by advance + shoot.
            // Table parity (#813 table half, solo_controller.gd:2239-2244):
            // a Quick Shot carrier keeps the rush ("may shoot after using Rush
            // actions" — the volley is not forfeited), and the demotion needs
            // a legal target in range + LOS after the capped move — a capped
            // rush with NO shot forfeits nothing and stays RUSH.
            // Epoch-gated like the rule ports (acts::rule_on), so every record
            // below EPOCH_8_PLANNER_MENU replays its candidate menu byte-exact
            // (#821 is a NEW frozen gate: the epoch-7 fixtures were recorded
            // before the demotion existed and must keep their 109-wide menus).
            let quick_shot = self.statics[state.roster.profile[unit]].quick_shot_active
                || crate::mods::granted(state, unit, "Quick Shot");
            if rule_on(self.seams.rules_epoch, EPOCH_8_PLANNER_MENU)
                && !quick_shot
                && rush_dominated(state, self.terrain, unit, o.pos)
            {
                let shot = self
                    .seams
                    .moved_shoot
                    .then(|| best_shoot(state, self.statics, unit, sc, self.tuning))
                    .flatten();
                if shot.is_some()
                    && out.iter().any(|c| c.kind == ADVANCE && c.dest == Some(o.pos))
                {
                    trace_rule(
                        "rollout",
                        RUSH_DEMOTION_RULE,
                        &format!("{key}: rush to objective dropped — advance to the same goal exists"),
                    );
                } else if let Some(e) = shot {
                    let mut c = Candidate::new(key, ADVANCE);
                    c.dest = Some(o.pos);
                    c.shoot = Some(state.key(e).to_string());
                    trace_rule(
                        "rollout",
                        RUSH_DEMOTION_RULE,
                        &format!(
                            "{key}: rush demoted to advance — capped to {:.1}\" — shot available ({})",
                            state.bands[unit].advance,
                            state.key(e)
                        ),
                    );
                    out.push(c);
                } else {
                    // The table's own shape (solo_controller.gd:2243-2244):
                    // no target in range + LOS after the capped move, no
                    // demotion — the RUSH candidate stays on the menu.
                    let mut c = Candidate::new(key, RUSH);
                    c.dest = Some(o.pos);
                    out.push(c);
                }
            } else {
                let mut c = Candidate::new(key, RUSH);
                c.dest = Some(o.pos);
                out.push(c);
            }
        }
        // Counter-charges exist in the mental game too (diagnosis 07.08.):
        // without this a committed unit could never be punished in a rollout,
        // so early commitment looked free.
        if let Some(e) = best_charge(state, self.terrain, self.statics, unit, sc, self.tuning) {
            let mut c = Candidate::new(key, CHARGE);
            c.dest = Some(geom::to_f64(geom::centre(&state.positions[e])));
            c.charge = Some(state.key(e).to_string());
            out.push(c);
        }
        if let Some(c) = safe_advance(state, self.terrain, unit, self.tuning) {
            out.push(c);
        }
        out
    }

    /// `AiPlanner._policy_step` ai_planner.gd:602-624 — the best restricted move
    /// of `player`'s un-activated units, or `None` when the side is dry.
    ///
    /// `rich` prices the leaf with the reply threat (our own side, R9: the
    /// danger-blind cheap leaf marched the imagined own army into the same
    /// overextension on every line); the imagined OPPONENT is stepped cheap,
    /// which is the conservative enemy model.
    ///
    /// The `playout_net` branch (:603-604) is NOT ported: a net-guided playout
    /// runs `AiClone.menu_tuples` + a trained network, which is not rules code.
    /// A corpus recorded with one is declined by the caller, never approximated.
    pub fn policy_step(
        &self,
        state: &State,
        player: i64,
        rich: bool,
        sc: &mut Scratch,
    ) -> Result<Option<Candidate>, Unsupported> {
        let rich = self.force_leaf.unwrap_or(rich);
        let mut best: Option<Candidate> = None;
        let mut best_s = f64::NEG_INFINITY;
        for i in 0..state.units() {
            if !state.can_activate(i, player, self.seams.hero_attach) {
                continue;
            }
            for action in self.policy_candidates(state, i, sc) {
                let next = self.resolve(state, &action)?;
                let s = if rich {
                    let incoming = reply_threat(self.statics, &next, player);
                    score_with(&next, self.statics, player, &incoming, self.fit)
                } else {
                    score_with(&next, self.statics, player, NO_INCOMING, self.fit)
                };
                // `_record_node` (:617) sits here and is INERT without
                // NML_NODE_DUMP; the rollout it belongs to is byte-identical
                // with or without it, so this port has no counterpart.
                if s > best_s {
                    best_s = s;
                    best = Some(action);
                }
            }
        }
        Ok(best)
    }

    /// `BattleSim.resolve` against the live board — the one entry point every
    /// imagined activation goes through.
    pub fn resolve(&self, state: &State, c: &Candidate) -> Result<State, Unsupported> {
        let a: Action = c.action();
        resolve_on_board_reach(self.statics, state, &a, self.terrain, self.seams, self.reach)
    }
}

/// #812 core half — is the RUSH to `dest` dominated by an advance? Two arms,
/// both in INCHES (world positions are metres — `menu.rs:667` is the precedent):
///   * the goal already lies inside the advance band, so both actions reach it
///     and advance keeps the shot;
///   * the route cannot avoid difficult ground (the unit stands in it, or the
///     straight line crosses it), so `plain_move`'s p.11 cap (mv/step.rs:598)
///     shortens the rush to `DIFFICULT_MOVE_CAP_IN` — an executable rush at or
///     under the advance band. Strider/Flying are exempt via the recorded
///     p.13 read (`state.charge_no_difficult`), the same exemption the move
///     engine's `ignores_difficult` honours.
fn rush_dominated(state: &State, terrain: &Terrain, unit: usize, dest: [f64; 3]) -> bool {
    let centre = geom::centre(&state.positions[unit]);
    let dist_in = geom::length(geom::sub(geom::to_f32(dest), centre)) as f64 / IN2M;
    let advance_in = state.bands[unit].advance;
    if dist_in <= advance_in + 1e-6 {
        return true;
    }
    if state.charge_no_difficult[unit] || !terrain.is_valid() {
        return false;
    }
    let probe_r = state.charge_probe_r[unit];
    let capped = terrain::base_in_terrain(centre, probe_r, terrain, terrain::is_difficult)
        || gate::crosses_difficult(centre, geom::to_f32(dest), probe_r, terrain);
    capped && dist_in.min(gate::DIFFICULT_MOVE_CAP_IN) <= advance_in + 1e-6
}

/// `AiPlanner._other_player` ai_planner.gd:870-875 — the first unit of the other
/// side in CAPTURE order; `player` itself when the state has no such unit.
/// Note it does NOT skip the dead: a wiped-out side still answers as "the other
/// player", which is what lets `rollout_boundaries` detect a dry round instead
/// of spinning.
pub fn other_player(state: &State, player: i64) -> i64 {
    for i in 0..state.units() {
        if state.player[i] != player {
            return state.player[i];
        }
    }
    player
}

impl Candidate {
    /// The plain `{"unit","kind",...}` action dict `BattleSim.resolve` reads.
    pub fn action(&self) -> Action {
        Action {
            kind: self.kind,
            unit: self.unit.clone(),
            dest: self.dest,
            shoot: self.shoot.clone(),
            charge: self.charge.clone(),
            patient: self.patient,
            split: None,
            traced: None,
        }
    }

    /// `{"unit": key, "kind": AiDecision.Action.HOLD}` — the bare hold.
    pub fn hold(unit: &str) -> Candidate {
        Candidate::new(unit, HOLD)
    }
}
