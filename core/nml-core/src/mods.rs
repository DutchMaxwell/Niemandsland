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

use crate::acts::{rule_on, EPOCH_11_SOLO_GRANT_READS};
use crate::rules::base_rule_name;
use crate::state::State;

/// One `_solo_record_spell_mod` record (main.gd:3649-3670), reduced to the
/// fields this core has a consumer for. `range_in` / `advance_in` / `rush_in`
/// are deliberately ABSENT — and `advance_in`/`rush_in` must STAY absent: the
/// table's own move knob (`advance_in`/`rush_in`, main.gd:16980) rides the
/// recorded bands themselves (battle_sim.gd:1707 -> SoloController.sim_move_
/// bands -> move_bands_for_props), so a table-loaded row arrives with its
/// inches already folded into `State.bands`. The core's own move delta
/// (`move_mod` below) is written ONLY on rows this core recorded during its
/// own playout, which is what keeps a replay from double-counting. A field
/// nothing reads is the very gap block B2b exists to close. `def_mod` /
/// `defense_mod` / `ap_mod` are carried since seam 4 step 1 (epoch 7) — the
/// RECORD shape only; their READS are step 2 (PR 2), so nothing here folds
/// them yet.
#[derive(Debug, Clone)]
pub struct LiveMod {
    pub hit_mod: i64,
    pub casting_mod: i64,
    pub morale_mod: i64,
    /// `ap_mod` — the attacker-side AP knob (Piercing Debuff, gf).
    pub ap_mod: i64,
    /// `def_mod` — Defense Buff's flat Defense shift (aof human_empire).
    pub def_mod: i64,
    /// `defense_mod` — Defense Debuff's flat Defense shift (aof/gf ratmen).
    pub defense_mod: i64,
    /// `move_mod` — Great Musician's `+1"` on move actions. NON-ZERO ONLY on
    /// a row THIS core recorded (`sim::record_buff`): `io::PlainBuff`
    /// deliberately leaves the table's `advance_in`/`rush_in` unparsed,
    /// because the recorded `State.bands` already carry them
    /// (battle_sim.gd:1707 -> SoloController.sim_move_bands ->
    /// move_bands_for_props). Parsing them here would double-count every
    /// replay.
    pub move_mod: i64,
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
    /// The record's own name — the table's `spell` key (main.gd:3751), what
    /// `_solo_log_defense_parts` names each contribution by (main.gd:5560).
    /// SEAM 4 step 2: carried for the rules-must-log line only; no fold reads
    /// it, and the census never counts it (it is the record's NAME key, not a
    /// rule param).
    pub name: Rc<str>,
}

/// `AiSpell.mods_for`'s `role` argument (ai_spell.gd:346-355). The "range"
/// role this port has no seam for yet is absent for the same reason its
/// field is. `Defense` is the GDScript's own "defense" role
/// (ai_spell.gd:352) — its record knob `def_mod` is a "+/-X to defense rolls"
/// ROLL bonus, so `_solo_defense_vs` folds it `base - bonus` (main.gd:5510).
/// `Ap` is the attacker-side family of "attacker_own" for the flat AP knob
/// Piercing Debuff carries ("loses AP(+1) when attacking"). `Speed` is the
/// GDScript's own "speed" role (the Great Musician port, epoch 12).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Role {
    AttackerOwn,
    VsTarget,
    Casting,
    Morale,
    Grant,
    GrantVs,
    Ap,
    Defense,
    Speed,
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
        Role::Grant => !r.attackers && !r.grants_rule.is_empty(),
        Role::GrantVs => r.attackers && !r.grants_rule.is_empty(),
        Role::Ap => !r.attackers && r.ap_mod != 0,
        Role::Defense => !r.attackers && (r.def_mod != 0 || r.defense_mod != 0),
        // NO `attackers` filter — this mirrors `AiSpell.mods_for`'s "speed"
        // arm exactly (ai_spell.gd:396-398, which appends regardless of
        // `beneficiary`). The Utility-Buff call site hard-codes
        // `beneficiary: ""` (main.gd:16541) so the two readings cannot
        // diverge in practice; match the GDScript anyway.
        Role::Speed => r.move_mod != 0,
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

/// SEAM 4 step 2 — `sum` with the rules-must-log line on every FIRING record:
/// `[utility-buff] <name> — <kind> <+/-n> on <unit>` (the trace_rule shape,
/// NML_TRACE_RULES=1). `sum`'s own callers stay silent — the hit/casting/
/// morale reads predate the logging rule and their parity is pinned without
/// stderr.
pub fn sum_logged(
    state: &State,
    i: usize,
    role: Role,
    melee: bool,
    unit: &str,
    kind: &str,
    f: impl Fn(&LiveMod) -> i64,
) -> i64 {
    let mut total = 0;
    for u in [Some(i), state.attached_to[i]].into_iter().flatten() {
        for r in &state.buffs[u] {
            if matches(r, role, melee) {
                let v = f(r);
                if v != 0 {
                    total += v;
                    crate::sim::trace_rule("utility-buff", &r.name, &format!("{kind} {v:+} on {unit}"));
                }
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
/// does not. `beneficiary == "attackers"` records are NOT the bearer's own
/// grants (main.gd:3652 — they never join the bearer's own net): `granted_vs`
/// reads them for whoever attacks the bearer instead.
pub fn granted(state: &State, i: usize, rule: &str) -> bool {
    chain_grant(state, i, rule, false)
}

/// `AiSpell.attacker_grants_from_target` (ai_spell.gd:454-465) — the
/// `beneficiary == "attackers"` records on the TARGET's joined chain belong to
/// whoever ATTACKS it, never to the bearer itself (main.gd:3652). The
/// roll-seam half of `_solo_bridge_granted_flags` (main.gd:16676-16685):
/// called with the attack's target, it hands the striker the target's
/// attackers-side grants.
pub fn granted_vs(state: &State, target: usize, rule: &str) -> bool {
    chain_grant(state, target, rule, true)
}

fn chain_grant(state: &State, i: usize, rule: &str, attackers: bool) -> bool {
    let mut who: Vec<usize> = vec![i];
    if let Some(h) = state.attached_to[i] {
        who.push(h);
    }
    who.extend(state.attached[i].iter().copied());
    who.iter().any(|&u| {
        state.buffs[u].iter().any(|r| {
            r.attackers == attackers
                && !r.grants_rule.is_empty()
                && base_rule_name(&r.grants_rule) == rule
        })
    })
}

/// CENSUS rows 1-5 (maintainer decision 13.09., semantics §11.2): the SOLO
/// move-grant family as EVIDENCE-ONLY accessor reads. The recorded dynamic
/// band already carries each grant (movement_range_controller.gd:83-135), so
/// nothing here folds (semantics §2(a)); the caller logs. From
/// `EPOCH_19_MOVE_GRANTS_FOLD` the family folds for real at the move spend
/// (`sim.rs::solo_move_grant_delta_in`) and this accessor's caller stays
/// silent — a FRESH core-simulated game has no recorded band to carry the
/// grant. Gate: `EPOCH_11_SOLO_GRANT_READS` — a rules_epoch below 11 reads
/// nothing.
pub fn solo_move_grants(state: &State, i: usize, rules_epoch: u32) -> Vec<&'static str> {
    if !rule_on(rules_epoch, EPOCH_11_SOLO_GRANT_READS) {
        return Vec::new();
    }
    let mut out = Vec::new();
    if granted(state, i, "Slow") {
        out.push("Slow");
    }
    if granted(state, i, "Fast") {
        out.push("Fast");
    }
    if granted(state, i, "Swift") {
        out.push("Swift");
    }
    if granted(state, i, "Rapid Advance") {
        out.push("Rapid Advance");
    }
    if granted(state, i, "Rapid Rush") {
        out.push("Rapid Rush");
    }
    out
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
