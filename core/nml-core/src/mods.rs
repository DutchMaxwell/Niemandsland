//! The LIVE modifier ledger — `main._solo_spell_mods` (main.gd:370) as a
//! per-unit record list on `State`, and the role/scope reads that spend it.
//!
//! WHY NOT `State.mods`: that field is the f64 EV stamp of
//! `BattleSim._apply_cast_effect` (battle_sim.gd:1309-1323). The table's own
//! imagination writes it and reads it nowhere — battle_sim.gd:1529 says so
//! ("not wired to a consumer yet") — so the twin must stay blind there or it
//! stops mirroring. This ledger is the DICE path's own bookkeeping, the one
//! `main.gd` actually reads back at a roll (`_solo_spell_hit_mod` :3789,
//! `_solo_spell_hit_mod_vs` :3800, the casting sum :3294, the morale sum
//! :8288), and it is written and read on the TRAY path only.

use std::rc::Rc;

use crate::rules::base_rule_name;
use crate::state::State;

/// One `_solo_record_spell_mod` record (main.gd:3649-3670), reduced to the
/// fields this core has a consumer for. `def_mod` / `range_in` / `advance_in` /
/// `rush_in` are deliberately ABSENT: the table reads them at seams
/// (`_solo_defense_parts`, the props stamps) this port has never had, and a
/// field nothing reads is the very gap block B2b exists to close.
#[derive(Debug, Clone)]
pub struct LiveMod {
    pub hit_mod: i64,
    pub casting_mod: i64,
    pub morale_mod: i64,
    /// `grants_rule` — the rule name the record hands the WHOLE joined chain
    /// (`_solo_apply_grant` main.gd:3730), "" for a plain modifier.
    pub grants_rule: Rc<str>,
    /// `effect.scope` — "" / "melee" / "shooting" / "charging", the GDScript's
    /// own strings (`AiSpell.mods_for` ai_spell.gd:390-394).
    pub scope: Rc<str>,
    /// `beneficiary == "attackers"` — the modifier belongs to whoever attacks
    /// the bearer, and never joins the bearer's own net (main.gd:3652).
    pub attackers: bool,
    /// `duration == "once"` — spent by the first exchange that could have used
    /// it (`_solo_consume_once_mods` main.gd:3823).
    pub once: bool,
}

/// `AiSpell.mods_for`'s `role` argument (ai_spell.gd:346-355). The two roles
/// this port has no seam for yet — "defense" and "range"/"speed" — are absent
/// for the same reason their fields are.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    AttackerOwn,
    VsTarget,
    Casting,
    Morale,
    Grant,
}

/// `AiSpell.mods_for` ai_spell.gd:364-400, one record.
pub fn matches(r: &LiveMod, role: Role, melee: bool) -> bool {
    // "charging" is never applied here — the GDScript's own v1 limitation.
    match (&*r.scope, melee) {
        ("charging", _) | ("melee", false) | ("shooting", true) => return false,
        _ => {}
    }
    match role {
        Role::AttackerOwn => !r.attackers && r.hit_mod != 0,
        Role::VsTarget => r.attackers && r.hit_mod != 0,
        Role::Casting => r.casting_mod != 0,
        Role::Morale => r.morale_mod != 0,
        Role::Grant => !r.grants_rule.is_empty(),
    }
}

/// The net of one role over `_solo_mods_of_chain` (main.gd:3812) — the unit's
/// OWN records plus its host's, because a joined hero shares the unit's tokens.
pub fn sum(state: &State, i: usize, role: Role, melee: bool, f: impl Fn(&LiveMod) -> i64) -> i64 {
    let mut total = 0;
    for u in [Some(i), state.attached_to[i]].into_iter().flatten() {
        for r in &state.buffs[u] {
            if matches(r, role, melee) {
                total += f(r);
            }
        }
    }
    total
}

/// Does unit `i` carry a live rule GRANT of `rule`? The overlay
/// `_solo_apply_grant` (main.gd:3730) writes the granted name onto the whole
/// JOINED CHAIN — bearer, host and attached heroes — so the read walks all
/// three, one hop wider than `sum`'s self+host. Scope-BLIND, like the overlay
/// itself. Name comparison is `AiEv.has_exact_rule` (ai_ev.gd:92-99): the base
/// name, so "Unstoppable (spell)" answers "Unstoppable" and "Unstoppable Mark"
/// does not.
pub fn granted(state: &State, i: usize, rule: &str) -> bool {
    let mut who: Vec<usize> = vec![i];
    if let Some(h) = state.attached_to[i] {
        who.push(h);
    }
    who.extend(state.attached[i].iter().copied());
    who.iter().any(|&u| {
        state.buffs[u]
            .iter()
            .any(|r| !r.grants_rule.is_empty() && base_rule_name(&r.grants_rule) == rule)
    })
}

/// `_solo_spend_once_mods` main.gd:3844-3869 — every `once` record on the unit
/// AND its host that matches one of `roles` goes. Removing the record IS the
/// grant revocation here: this port keeps no second overlay to strip.
pub fn spend_once(state: &mut State, i: usize, roles: &[Role], melee: bool) {
    let host = state.attached_to[i];
    for u in [Some(i), host].into_iter().flatten() {
        state.buffs[u]
            .retain(|r| !(r.once && roles.iter().any(|&role| matches(r, role, melee))));
    }
}
