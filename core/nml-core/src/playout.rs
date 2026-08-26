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

use crate::io::{Action, Seams};
use crate::menu::{best_charge, best_shoot, safe_advance, Candidate, Tuning};
use crate::score::{score, NO_INCOMING};
use crate::mv::reach::ReachIndex;
use crate::sim::{
    reply_threat, resolve_on_board_reach, Scratch, Unsupported, CHARGE, HOLD, RUSH,
};
use crate::state::State;
use crate::terrain::Terrain;
use crate::unit::UnitStatic;
use crate::{geom, Objective};

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
        if let Some(e) = best_shoot(state, self.statics, unit, sc) {
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
            let mut c = Candidate::new(key, RUSH);
            c.dest = Some(o.pos);
            out.push(c);
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
            if state.player[i] != player || state.activated[i] || state.alive[i] <= 0 {
                continue;
            }
            for action in self.policy_candidates(state, i, sc) {
                let next = self.resolve(state, &action)?;
                let s = if rich {
                    let incoming = reply_threat(self.statics, &next, player);
                    score(&next, player, &incoming)
                } else {
                    score(&next, player, NO_INCOMING)
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
        }
    }

    /// `{"unit": key, "kind": AiDecision.Action.HOLD}` — the bare hold.
    pub fn hold(unit: &str) -> Candidate {
        Candidate::new(unit, HOLD)
    }
}
