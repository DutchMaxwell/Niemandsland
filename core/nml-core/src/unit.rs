//! The per-unit STATIC layer: everything `resolve`/`reply_threat` read off a
//! live `GameUnit`, resolved once per game.
//!
//! Four GDScript functions are folded in here, in their original order:
//!   * `AiShooting.profiles_in_range` ai_shooting.gd:14-26 + `merge_identical`
//!     :63-77 + `_profile` :90-152 — the ranged weapon profiles;
//!   * `AiShooting.melee_profiles` :44-56 — the same shape at range 0, minus the
//!     Strafing filter, which lives in `profiles_in_range` alone;
//!   * `AiEv.stamp_sergeant` ai_ev.gd:203-274 — the registry-driven facets;
//!   * `AiEv.ctx_for` ai_ev.gd:135-165 + `_regen_target` :171-177 — the context.
//!
//! Merge-then-stamp is load-bearing, not convenience: `Devout` stamps `surge`
//! onto EVERY profile, so stamping first would let a Surge weapon and a plain
//! one collapse into one merged line that GDScript keeps apart (the merge
//! signature ai_shooting.gd:81-89 is taken before any stamping).
//!
//! Range filtering commutes with the merge — every member of a merge group has
//! the same `range` (it is part of the signature) — so the whole ranged set is
//! merged once here and filtered per call.

use std::rc::Rc;

use crate::combat::{
    armored_defense, BANNER_MORALE_BONUS, LONG_RANGE_IN, REGENERATION_TARGET, SELF_REPAIR_TARGET,
    SHROUD_CHARGE_PENALTY_IN, SHROUD_FLOOR_IN,
};
use crate::rules::{
    base_rule_name, has_special_rule, rule_rating, unit_rating, Registries, Spell,
};
use crate::state::{Profile, Profiles, Weapon};

/// `AiEv` unit context — `ctx_for`'s dictionary as a struct. `models`,
/// `in_cover` and `fatigued` are the DYNAMIC three `BattleSim._ctx_of`
/// (battle_sim.gd:701-712) writes over the template per call.
#[derive(Debug, Clone, Copy, Default)]
pub struct Ctx {
    pub quality: i64,
    pub defense: i64,
    pub morale_bonus: i64,
    pub tough: i64,
    pub models: i64,
    pub artillery: bool,
    pub furious: bool,
    pub fearless: bool,
    /// `Fear(X)` — the melee WINNER comparison and nothing else
    /// (`AiCombatMath.fear_adjusted_wounds` :338, main.gd:8110-8112). It never
    /// changes a wound applied, only which side ends up testing morale, so the
    /// D1 dice path needs it and the EV path — which never asks who won — does
    /// not.
    pub fear: i64,
    /// `main._solo_unpredictable_rule(striker, true)` :5414-5418 — the melee
    /// form of the Unpredictable die, EITHER variant: the melee-only
    /// "Unpredictable Fighter" on all models, or the generic army-book
    /// "Unpredictable" (exact rule AND registry-active). One die per melee
    /// phase, before any strike.
    pub unpredictable: bool,
    /// `RulesRegistry.unit_rule_active(unit, "No Retreat")` main.gd:8360 — a
    /// failed morale test counts as PASSED instead, and is paid for in
    /// self-wounds that cannot be ignored.
    pub no_retreat: bool,
    /// `main._solo_unit_has_unwieldy` :16675 — "strikes last when charging":
    /// the CHARGER's strikes swap BEHIND the defender's strike-back
    /// (main.gd:8073-8078). Counter and Impact keep their slots.
    pub unwieldy: bool,
    /// `Impact(X)` / `Heavy Impact(X)` / `Ravage(X)` ratings — read only by the
    /// melee side (`impact_ev` / `ravage_ev`, ai_ev.gd:497-529).
    pub impact: i64,
    pub heavy_impact: i64,
    pub ravage: i64,
    pub stealth: bool,
    pub evasive: bool,
    /// `Melee Evasion` — the melee twin of Evasive (ai_ev.gd:150).
    pub melee_evasion: bool,
    pub fortified: bool,
    pub guarded: bool,
    pub ranged_shrouding: bool,
    pub shielded: bool,
    pub in_cover: bool,
    /// `AiEv.ctx_for`'s third argument, which `BattleSim._ctx_of` never passes
    /// (battle_sim.gd:702) — always 0 in the sim, modelled for `impact_ev`.
    pub counter_models: i64,
    pub regeneration: bool,
    pub regen_target: i64,
    /// The DYNAMIC melee flag `BattleSim._ctx_of(su, true)` writes over the
    /// template (battle_sim.gd:705-707): a fatigued striker hits only on 6s.
    pub fatigued: bool,
}

/// One conditional-AP spec — the registry `params` block of a Shatter / Tear /
/// Disintegrate / Melee Slayer / Piercing Assault / Piercing Hunter / Slayer
/// entry, as `AiEv.stamp_conditional_ap` ai_ev.gd:283-315 hands it to
/// `AiCombatMath.conditional_ap_bonus`. Carried verbatim rather than resolved
/// here: the bonus depends on the DEFENDER, which the static layer never sees.
#[derive(Debug, Clone, Default)]
pub struct CondAp {
    pub ap_bonus: i64,
    pub charge_only: bool,
    /// The extra situational gate (`"ranged_over_or_charge"`), "" for none.
    pub gate: String,
    pub over_in: f64,
    pub condition: String,
    pub threshold: i64,
}

/// One merged, stamped weapon profile — `AiShooting._profile` ai_shooting.gd:90-152
/// plus the `stamp_sergeant` facets `profile_ev` actually reads.
#[derive(Debug, Clone, Default)]
pub struct ShootProfile {
    pub name: String,
    /// The MERGED raw attack count; the survivor scaling happens per call.
    pub attacks: i64,
    pub count: i64,
    pub range: i64,
    pub ap: i64,
    pub deadly: i64,
    pub blast: i64,
    pub hazardous: bool,
    pub relentless: bool,
    pub reliable: bool,
    pub strafing: bool,
    pub ignores_cover: bool,
    pub precise: bool,
    pub surge: bool,
    pub rending: bool,
    pub bane: bool,
    pub thrust: bool,
    pub unstoppable: bool,
    pub counter: bool,
    pub destructive: bool,
    pub shred: bool,
    pub indirect: bool,
    pub limited: bool,
    pub takedown: bool,
    pub rules: Vec<String>,
    // --- stamped facets (ai_ev.gd:203-274) ---
    pub versatile_attack: bool,
    pub on6_ap: i64,
    /// `AiEv.stamp_sergeant` :267-274 writes the bearer's own attack share here.
    /// ALWAYS 0 in this port — see `UnitStatic::unimplemented`.
    pub sergeant_attacks: i64,
    /// NML-1103 — `AiEv.stamp_conditional_ap` ai_ev.gd:296-313, read by
    /// `combat::profile_ev`. Stamped AFTER the merge, like every other facet.
    pub cond_ap: Vec<CondAp>,
}

impl ShootProfile {
    /// `AiShooting._merge_signature` ai_shooting.gd:81-89 — every key except the
    /// two summable ones. Compared field by field instead of stringified; the
    /// stamped facets are still at their defaults when this runs.
    fn merges_with(&self, o: &ShootProfile) -> bool {
        self.name == o.name
            && self.range == o.range
            && self.ap == o.ap
            && self.deadly == o.deadly
            && self.blast == o.blast
            && self.hazardous == o.hazardous
            && self.relentless == o.relentless
            && self.reliable == o.reliable
            && self.strafing == o.strafing
            && self.ignores_cover == o.ignores_cover
            && self.precise == o.precise
            && self.surge == o.surge
            && self.rending == o.rending
            && self.bane == o.bane
            && self.thrust == o.thrust
            && self.unstoppable == o.unstoppable
            && self.counter == o.counter
            && self.destructive == o.destructive
            && self.shred == o.shred
            && self.indirect == o.indirect
            && self.limited == o.limited
            && self.takedown == o.takedown
            && self.rules == o.rules
    }
}

/// A rule the port knows it does not implement, with the reason.
#[derive(Debug, Clone, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct Unimplemented {
    pub rule: String,
    pub why: String,
}

/// The immutable per-unit closure of `resolve`/`reply_threat`.
#[derive(Debug, Default)]
pub struct UnitStatic {
    pub ctx: Ctx,
    /// `Profile.name` — `GameUnit.get_name()`, which is what `_solo_tray_roll`
    /// signs every die with (main.gd:3199-3200, :6448).
    pub name: String,
    /// Merged + stamped RANGED profiles, unfiltered (range > 0, any distance).
    pub shoot: Vec<ShootProfile>,
    /// Merged + stamped MELEE profiles (range 0) — `AiShooting.melee_profiles`
    /// ai_shooting.gd:44-56, the set `_profiles_of(su, true)` builds.
    pub melee: Vec<ShootProfile>,
    pub model_count: i64,
    pub wounds_max: Vec<i64>,
    pub quality: i64,
    pub fearless: bool,
    pub is_caster: bool,
    pub spells: Vec<Spell>,
    /// `GameUnit.has_special_rule("Caster Group")` — the round-start refill
    /// resets such a unit to its BEARER COUNT instead of accumulating
    /// (ai_planner.gd:487-492 via game_unit.gd:426-434).
    pub caster_group: bool,
    /// `GameUnit.casts_per_round`, which `GameUnit._ready` sets from
    /// `get_caster_value()` (game_unit.gd:420) — the profile's `caster_value`
    /// IS that number.
    pub casts_per_round: i64,
    /// `RulesRegistry.unit_rule_active(gu, "Battleborn" | "Steadfast")`
    /// (rules_registry.gd:136-142) — the two rules that clear Shaken for free at
    /// a round start (ai_planner.gd:493-495). Static per unit, so the registry
    /// is read here once instead of per imagined round.
    pub battleborn_active: bool,
    pub steadfast_active: bool,
    /// Rules this unit carries that the port does NOT model — reported by name
    /// with a node count instead of being silently skipped.
    pub unimplemented: Vec<Unimplemented>,
}

fn weapon_has(w: &Weapon, rule: &str) -> bool {
    w.rules.iter().any(|r| r.trim().starts_with(rule))
}

/// `AiShooting._rating_of` ai_shooting.gd:176-182 — no max(0) here, unlike the
/// unit-level `AiEv.unit_rating`.
fn weapon_rating(w: &Weapon, rule_name: &str) -> i64 {
    let prefix = format!("{rule_name}(");
    for r in &w.rules {
        let s = r.trim();
        if s.starts_with(&prefix) && s.ends_with(')') {
            let inner: String = s[prefix.len()..s.len() - 1].chars().filter(|c| *c != '+').collect();
            return inner.parse::<i64>().unwrap_or(0);
        }
    }
    0
}

/// `AiShooting._profile` ai_shooting.gd:90-152.
fn base_profile(w: &Weapon, attacks: i64, range_in: i64) -> ShootProfile {
    let ap = weapon_rating(w, "AP");
    ShootProfile {
        name: w.name.clone(),
        attacks,
        count: w.count.max(1),
        range: range_in,
        // Hazardous grants AP(4) — ai_shooting.gd:104-107.
        ap: if weapon_has(w, "Hazardous") { ap.max(4) } else { ap },
        hazardous: weapon_has(w, "Hazardous"),
        deadly: weapon_rating(w, "Deadly"),
        relentless: weapon_has(w, "Relentless"),
        blast: weapon_rating(w, "Blast"),
        reliable: weapon_has(w, "Reliable"),
        strafing: weapon_has(w, "Strafing"),
        ignores_cover: weapon_has(w, "Ignores Cover"),
        precise: weapon_has(w, "Precise"),
        surge: weapon_has(w, "Surge"),
        rending: weapon_has(w, "Rending"),
        // Lacerate is a straight data-alias of Bane — ai_shooting.gd:126-129.
        bane: weapon_has(w, "Bane") || weapon_has(w, "Lacerate"),
        thrust: weapon_has(w, "Thrust"),
        unstoppable: weapon_has(w, "Unstoppable"),
        counter: weapon_has(w, "Counter"),
        destructive: weapon_has(w, "Destructive"),
        shred: weapon_has(w, "Shred"),
        indirect: weapon_has(w, "Indirect"),
        limited: weapon_has(w, "Limited"),
        takedown: weapon_has(w, "Takedown"),
        rules: w.rules.clone(),
        ..Default::default()
    }
}

/// `AiShooting.merge_identical` ai_shooting.gd:63-77 — Limited and Takedown keep
/// their own line (per-identity bookkeeping); first-appearance order is kept.
fn merge_identical(profiles: Vec<ShootProfile>) -> Vec<ShootProfile> {
    let mut out: Vec<ShootProfile> = Vec::with_capacity(profiles.len());
    for p in profiles {
        if p.limited || p.takedown {
            out.push(p);
            continue;
        }
        match out.iter_mut().position(|t| t.merges_with(&p)) {
            Some(i) => {
                out[i].attacks += p.attacks;
                out[i].count += p.count;
            }
            None => out.push(p),
        }
    }
    out
}

/// `AiEv.facet_applies` ai_ev.gd:105-110 — the melee/shooting gate of a
/// unit-level facet; `profile_range` 0 means a melee profile.
fn facet_applies(melee_only: bool, shooting_only: bool, profile_range: i64) -> bool {
    if melee_only && profile_range > 0 {
        return false;
    }
    if shooting_only && profile_range <= 0 {
        return false;
    }
    true
}

/// `AiEv.has_exact_rule` ai_ev.gd:88-96 — rating stripped, no prefix match.
fn has_exact_rule(rules: &[String], rule: &str) -> bool {
    rules.iter().any(|r| base_rule_name(r) == rule)
}

/// `AiEv.rule_on_all_models` ai_ev.gd:74-85 — the unit carries the rule AND
/// every ALIVE attached hero carries it too.
fn rule_on_all_models(p: &Profile, rule: &str) -> bool {
    if !has_special_rule(&p.special_rules, rule) {
        return false;
    }
    p.attached_hero_rules
        .iter()
        .all(|hr| has_special_rule(hr, rule))
}

/// `RulesRegistry.unit_rule_active` rules_registry.gd:132-137 — the unit carries
/// it AND the map fields it for this (system, faction). A MISSING map answers
/// true (the wave-1..4 fallback).
fn unit_rule_active(reg: &mut Registries, p: &Profile, rule: &str) -> bool {
    if !has_special_rule(&p.special_rules, rule) {
        return false;
    }
    let map = reg.rules_for(&p.game_system);
    if map.empty {
        return true;
    }
    map.has_primitive(&p.faction_folder, rule)
}

/// One `unit_rules_of_primitive` hit — rules_registry.gd:155-176.
struct PrimitiveHit {
    name: String,
    melee_only: bool,
    shooting_only: bool,
    extra_attack: bool,
    upgrades: String,
    cover_only: bool,
    ignores_cover: bool,
}

/// `RulesRegistry.unit_rules_of_primitive` rules_registry.gd:155-176 — every
/// effective rule (own + item-granted, each name once, in that order) whose
/// registry entry resolves to `primitive`.
fn rules_of_primitive(reg: &mut Registries, p: &Profile, primitive: &str) -> Vec<PrimitiveHit> {
    let mut out = Vec::new();
    let mut raws: Vec<&String> = p.special_rules.iter().collect();
    raws.extend(p.item_grants.iter());
    let map = reg.rules_for(&p.game_system);
    let mut seen: Vec<String> = Vec::new();
    for raw in raws {
        let n = base_rule_name(raw);
        if n.is_empty() || seen.iter().any(|s| *s == n) {
            continue;
        }
        seen.push(n.clone());
        if let Some(e) = map.lookup(&p.faction_folder, &n) {
            if e.primitive.as_deref() == Some(primitive) {
                out.push(PrimitiveHit {
                    name: n,
                    melee_only: e.param_b("melee_only"),
                    shooting_only: e.param_b("shooting_only"),
                    extra_attack: e.param_b("extra_attack"),
                    upgrades: e.param_s("upgrades").to_string(),
                    cover_only: e.param_b("cover_only"),
                    ignores_cover: e.param_b("ignores_cover"),
                });
            }
        }
    }
    let _ = rule_rating("", 0); // keep the import honest: ratings are unread here
    out
}

/// The capture-time registry reads that do NOT live on the profile — the ones
/// `BattleSim.capture` (battle_sim.gd:1329/1332) and
/// `AiActRecorder._stamp_gate_reads` (act_recorder.gd:251-256) take off the LIVE
/// `GameUnit` and write into the plain unit dict. A Godot-free capture has to
/// answer them from the same mechanics maps the search already loaded, or it
/// would need a second registry reader of its own.
#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct CaptureReads {
    /// `SoloController.morale_bonus_of` solo_controller.gd:5407-5423.
    pub morale_bonus: i64,
    /// `SoloController.is_aircraft` :5501.
    pub aircraft: bool,
    /// `u.has_special_rule("Strider") or u.has_special_rule("Flying")` — the p.13
    /// difficult-terrain exemption, a PLAIN rule-name read (no registry).
    pub charge_no_difficult: bool,
    /// `AiActRecorder._melee_shroud_params` :276-295 — `[penalty_in, floor_in]`.
    pub shroud: Option<[f64; 2]>,
}

/// `SoloController.morale_bonus_of`, evaluated over one member's rule list:
/// the named "Banner" (when the map fields it) and every DATA ALIAS whose entry
/// resolves to the Banner primitive.
fn banner_bonus_of(reg: &mut Registries, p: &Profile, rules: &[String]) -> i64 {
    let mut best = 0;
    let map = reg.rules_for(&p.game_system);
    if has_special_rule(rules, "Banner") && (map.empty || map.has_primitive(&p.faction_folder, "Banner")) {
        best = best.max(match map.lookup(&p.faction_folder, "Banner") {
            Some(e) => e.param_i("morale_bonus", BANNER_MORALE_BONUS),
            None => BANNER_MORALE_BONUS,
        });
    }
    let mut seen: Vec<String> = Vec::new();
    for raw in rules {
        let n = base_rule_name(raw);
        if n.is_empty() || n == "Banner" || seen.iter().any(|s| *s == n) {
            continue;
        }
        seen.push(n.clone());
        if let Some(e) = map.lookup(&p.faction_folder, &n) {
            if e.primitive.as_deref() == Some("Banner") {
                best = best.max(e.param_i("morale_bonus", 0));
            }
        }
    }
    best
}

/// `AiActRecorder._melee_shroud_params` act_recorder.gd:276-295 — the named rule
/// first, then the DATA aliases of the two Shrouding primitives, in that order.
fn melee_shroud_params(reg: &mut Registries, p: &Profile) -> Option<[f64; 2]> {
    if rule_on_all_models(p, "Melee Shrouding") {
        let map = reg.rules_for(&p.game_system);
        let e = map.lookup(&p.faction_folder, "Melee Shrouding");
        return Some(match e {
            Some(e) => [
                e.param_f("move_penalty_in", SHROUD_CHARGE_PENALTY_IN),
                e.param_f("floor_in", SHROUD_FLOOR_IN),
            ],
            None => [SHROUD_CHARGE_PENALTY_IN, SHROUD_FLOOR_IN],
        });
    }
    for prim in ["Melee Shrouding", "Ranged Shrouding"] {
        for hit in rules_of_primitive(reg, p, prim) {
            if hit.name == "Melee Shrouding"
                || hit.name == "Ranged Shrouding"
                || !rule_on_all_models(p, &hit.name)
            {
                continue;
            }
            let map = reg.rules_for(&p.game_system);
            let Some(e) = map.lookup(&p.faction_folder, &hit.name) else { continue };
            let pen = e.param_f("move_penalty_in", e.param_f("melee_move_penalty_in", 0.0));
            if pen <= 0.0 {
                continue;
            }
            return Some([pen, e.param_f("melee_floor_in", e.param_f("floor_in", SHROUD_FLOOR_IN))]);
        }
    }
    None
}

/// The four reads above for one unit profile.
pub fn capture_reads(reg: &mut Registries, p: &Profile) -> CaptureReads {
    let mut morale_bonus = banner_bonus_of(reg, p, &p.special_rules);
    for hero in &p.attached_hero_rules {
        morale_bonus = morale_bonus.max(banner_bonus_of(reg, p, hero));
    }
    CaptureReads {
        morale_bonus,
        aircraft: unit_rule_active(reg, p, "Aircraft"),
        charge_no_difficult: has_special_rule(&p.special_rules, "Strider")
            || has_special_rule(&p.special_rules, "Flying"),
        shroud: melee_shroud_params(reg, p),
    }
}

/// `AiEv._regen_target` ai_ev.gd:171-177.
fn regen_target(reg: &mut Registries, p: &Profile) -> i64 {
    if has_special_rule(&p.special_rules, "Regeneration")
        || has_special_rule(&p.special_rules, "Medical Training")
    {
        let map = reg.rules_for(&p.game_system);
        return match map.lookup(&p.faction_folder, "Regeneration") {
            Some(e) => e.param_i("ignore_target", REGENERATION_TARGET),
            None => REGENERATION_TARGET,
        };
    }
    if rule_on_all_models(p, "Self-Repair") {
        let map = reg.rules_for(&p.game_system);
        return match map.lookup(&p.faction_folder, "Self-Repair") {
            Some(e) => e.param_i("ignore_target", SELF_REPAIR_TARGET),
            None => SELF_REPAIR_TARGET,
        };
    }
    0
}

/// `AiEv.ctx_for` ai_ev.gd:135-165. `models` stays at the live-unit reading;
/// `BattleSim._ctx_of` overwrites it with the snapshot's `alive` on every call.
fn ctx_for(reg: &mut Registries, p: &Profile) -> Ctx {
    let armor = if unit_rule_active(reg, p, "Armor") {
        unit_rating(&p.special_rules, "Armor")
    } else {
        0
    };
    let morale_bonus = if unit_rule_active(reg, p, "Banner") {
        let map = reg.rules_for(&p.game_system);
        match map.lookup(&p.faction_folder, "Banner") {
            Some(e) => e.param_i("morale_bonus", BANNER_MORALE_BONUS),
            None => BANNER_MORALE_BONUS,
        }
    } else {
        0
    };
    Ctx {
        quality: p.quality,
        defense: armored_defense(p.defense, armor),
        morale_bonus,
        tough: unit_rating(&p.special_rules, "Tough").max(1),
        models: 1, // placeholder; `_ctx_of` always writes the snapshot's alive
        artillery: has_special_rule(&p.special_rules, "Artillery"),
        furious: has_special_rule(&p.special_rules, "Furious"),
        fearless: has_special_rule(&p.special_rules, "Fearless"),
        fear: unit_rating(&p.special_rules, "Fear"),
        no_retreat: unit_rule_active(reg, p, "No Retreat"),
        // BOTH variants, in `_solo_unpredictable_rule`'s own order and with its
        // own gates: the melee-only Fighter form needs the rule on every model,
        // the generic form an EXACT rule name plus a registry that fields it.
        unpredictable: rule_on_all_models(p, "Unpredictable Fighter")
            || (has_exact_rule(&p.special_rules, "Unpredictable")
                && unit_rule_active(reg, p, "Unpredictable")),
        // The table asks the whole joined chain (`_solo_joined_chain`
        // main.gd:16677). The port sees an attached hero only as a list of rule
        // NAMES, so the primitive layer answers for the unit itself and an exact
        // name answers for the heroes — an alias carried ONLY by a hero is the
        // one case this misses, and it is named in `resolve_melee_with_tray`.
        unwieldy: !rules_of_primitive(reg, p, "Unwieldy").is_empty()
            || p.attached_hero_rules.iter().any(|hr| has_exact_rule(hr, "Unwieldy")),
        impact: unit_rating(&p.special_rules, "Impact"),
        heavy_impact: unit_rating(&p.special_rules, "Heavy Impact"),
        ravage: unit_rating(&p.special_rules, "Ravage"),
        stealth: rule_on_all_models(p, "Stealth"),
        evasive: rule_on_all_models(p, "Evasive"),
        melee_evasion: rule_on_all_models(p, "Melee Evasion"),
        fortified: rule_on_all_models(p, "Fortified"),
        // Guarded OR Versatile Defense — ai_ev.gd:157-158.
        guarded: rule_on_all_models(p, "Guarded") || rule_on_all_models(p, "Versatile Defense"),
        ranged_shrouding: rule_on_all_models(p, "Ranged Shrouding"),
        shielded: rule_on_all_models(p, "Shielded"),
        in_cover: false,
        // HARD 0, and it stays 0: `BattleSim._ctx_of` never passes
        // `AiEv.ctx_for`'s third argument either (battle_sim.gd:702,
        // ai_ev.gd:135). The table counts the DEFENDER's alive models whose
        // melee weapons carry Counter (`SoloController.counter_models_of`), a
        // per-MODEL loadout read the capture does not carry — so Counter's
        // Impact reduction is inert in this port, and `resolve_melee_with_tray`
        // raises `counter_strikes_first` whenever it would have mattered.
        counter_models: 0,
        regeneration: regen_target(reg, p) > 0,
        regen_target: regen_target(reg, p),
        fatigued: false,
    }
}

/// The stamping pass `AiEv.stamp_sergeant` ai_ev.gd:203-291 runs over ONE
/// profile array. The melee and the ranged set each get their own call in
/// `BattleSim._profiles_of` (battle_sim.gd:719-720), so it runs twice here too;
/// the `facet_applies` gates read each profile's own range.
fn stamp(
    reg: &mut Registries,
    p: &Profile,
    shoot: &mut [ShootProfile],
    unimplemented: &mut Vec<Unimplemented>,
) {
    // 1. Versatile Attack, unit-wide (ai_ev.gd:209-217).
    if has_special_rule(&p.special_rules, "Versatile Attack")
        || !rules_of_primitive(reg, p, "Versatile Attack").is_empty()
    {
        for sp in shoot.iter_mut() {
            sp.versatile_attack = true;
        }
    }
    // 2. Ferocious = Surge on every weapon, EXACT match (ai_ev.gd:218-224).
    if p.special_rules.iter().any(|r| r.trim() == "Ferocious") {
        for sp in shoot.iter_mut() {
            sp.surge = true;
        }
    }
    // 3. Surge-family data aliases (ai_ev.gd:225-249). `extra_attack`
    //    (surge_attack) and the `within_in`/`over_in`/`surge_low` knobs are
    //    stamped by GDScript but NEVER read by profile_ev, so only the plain
    //    surge facet is carried; an alias that would set one of the others is
    //    reported instead of silently dropped.
    for hit in rules_of_primitive(reg, p, "Surge") {
        if hit.name == "Surge" || hit.name == "Ferocious" || !hit.upgrades.is_empty() {
            continue;
        }
        if hit.extra_attack {
            unimplemented.push(Unimplemented {
                rule: hit.name.clone(),
                why: "Surge/extra_attack (surge_attack) — stamped by ai_ev.gd:242-244 but not read by profile_ev".into(),
            });
            continue;
        }
        for sp in shoot.iter_mut() {
            if facet_applies(hit.melee_only, hit.shooting_only, sp.range) {
                sp.surge = true;
            }
        }
    }
    // 3b. Surge UPGRADE entries (ai_ev.gd:250-260) only move surge_low /
    //     surge_over_in, which profile_ev does not read.
    for hit in rules_of_primitive(reg, p, "Surge") {
        if hit.upgrades.is_empty() || !has_exact_rule(&p.special_rules, &hit.upgrades) {
            continue;
        }
        unimplemented.push(Unimplemented {
            rule: hit.name.clone(),
            why: "Surge upgrade (surge_low/surge_over_in) — stamped by ai_ev.gd:255-260 but not read by profile_ev".into(),
        });
    }
    // 4. Rending data aliases (ai_ev.gd:261-272).
    for hit in rules_of_primitive(reg, p, "Rending") {
        if hit.name == "Rending" {
            continue;
        }
        for sp in shoot.iter_mut() {
            if facet_applies(hit.melee_only, hit.shooting_only, sp.range) {
                sp.rending = true;
            }
        }
    }
    // 5. Cover-ignore facet from the Indirect primitive's alias form (ai_ev.gd:273-281).
    for hit in rules_of_primitive(reg, p, "Indirect") {
        if hit.name != "Indirect" && hit.cover_only && hit.ignores_cover {
            for sp in shoot.iter_mut() {
                if sp.range > 0 {
                    sp.ignores_cover = true;
                }
            }
        }
    }
    // 6. Sergeant (ai_ev.gd:282-291). Its share reads the LIVE alive count,
    //    which the static profile does not carry — reported, never guessed.
    if unit_rule_active(reg, p, "Sergeant") {
        unimplemented.push(Unimplemented {
            rule: "Sergeant".into(),
            why: "sergeant_attacks needs GameUnit.get_alive_count() at the moment of the call (ai_ev.gd:284) — not in the static profile".into(),
        });
    }
}

/// `BattleSim._profiles_of`'s UNIT-level striker scan (battle_sim.gd:722-733):
/// Bane / Rending / Unstoppable carried by the UNIT reach the dice in the game,
/// so they are OR-ed onto every profile — prefix scan, no registry gate.
fn stamp_unit_strikers(p: &Profile, shoot: &mut [ShootProfile]) {
    let mut u_bane = false;
    let mut u_rending = false;
    let mut u_unstop = false;
    for r in &p.special_rules {
        let rs = r.trim();
        if rs.starts_with("Bane") || rs.starts_with("Lacerate") {
            u_bane = true;
        } else if rs.starts_with("Rending") {
            u_rending = true;
        } else if rs.starts_with("Unstoppable") && !rs.contains(" in ") && !rs.contains(" when ") {
            u_unstop = true;
        }
    }
    for sp in shoot.iter_mut() {
        sp.bane |= u_bane;
        sp.rending |= u_rending;
        sp.unstoppable |= u_unstop;
    }
}

/// The registry read behind `AiEv.stamp_conditional_ap` ai_ev.gd:291-306: the
/// conditional-AP spec of ONE rule name (None when the book has no entry, or an
/// entry without a `condition` key — the presence of that key IS the gate) plus
/// the entry's `on6_ap`, which the same GDScript loop stamps on the way past.
fn cond_ap_of(reg: &mut Registries, p: &Profile, base: &str) -> (Option<CondAp>, i64) {
    let map = reg.rules_for(&p.game_system);
    let Some(e) = map.lookup(&p.faction_folder, base) else {
        return (None, 0);
    };
    let on6 = e.param_i("on6_ap", 0);
    if e.params.get("condition").is_none() {
        return (None, on6);
    }
    (
        Some(CondAp {
            ap_bonus: e.param_i("ap_bonus", 0),
            charge_only: e.param_b("charge_only"),
            gate: e.param_s("gate").to_string(),
            over_in: e.param_f("over_in", LONG_RANGE_IN),
            condition: e.param_s("condition").to_string(),
            threshold: e.param_i("threshold", 0),
        }),
        on6,
    )
}

/// `AiEv.stamp_conditional_ap` ai_ev.gd:283-315 — NML-1103. The pass
/// `BattleSim._profiles_of` (battle_sim.gd:927) runs right after `stamp_sergeant`,
/// on the melee and the ranged array alike. WEAPON rules stamp their own spec;
/// the MODEL-level members of the family (Slayer / Piercing Hunter: "when this
/// model shoots…") sit on the UNIT and are stamped onto every profile, deduped
/// against the weapon's own rules BY NAME.
fn stamp_conditional_ap(reg: &mut Registries, p: &Profile, shoot: &mut [ShootProfile]) {
    let mut unit_specs: Vec<(String, CondAp)> = Vec::new();
    for r in &p.special_rules {
        let base = base_rule_name(r);
        if let (Some(c), _) = cond_ap_of(reg, p, &base) {
            unit_specs.push((base, c));
        }
    }
    for sp in shoot.iter_mut() {
        let rules = sp.rules.clone();
        let mut seen: Vec<String> = Vec::new();
        for r in &rules {
            let base = base_rule_name(r);
            let (spec, on6) = cond_ap_of(reg, p, &base);
            if let Some(c) = spec {
                sp.cond_ap.push(c);
                seen.push(base);
            }
            // Crack's on-6-to-hit AP upgrade (:305-307) — a plain assignment in
            // GDScript, so the LAST rule of the weapon wins, not the largest.
            if on6 > 0 {
                sp.on6_ap = on6;
            }
        }
        for (n, c) in &unit_specs {
            if !seen.contains(n) {
                sp.cond_ap.push(c.clone());
            }
        }
    }
}

/// `AiShooting.profiles_in_range` ai_shooting.gd:14-26 — the merged RANGED set,
/// UNSTAMPED (the `AiEv.stamp_sergeant` pass belongs to `BattleSim._profiles_of`,
/// not to this function). `UnitStatic::build` calls it at 0.0 and stamps after;
/// `rows::board_rows` calls it at `EV_REF_DIST_IN` and stamps NOT AT ALL, which
/// is exactly what battle_sim.gd:206 does.
pub(crate) fn profiles_in_range(weapons: &[Weapon], dist_in: f64) -> Vec<ShootProfile> {
    let mut raw: Vec<ShootProfile> = Vec::new();
    for w in weapons {
        // `AiShooting._field_i(w, "range_value", 0)` — an int read; the
        // recorded value is `OPRWeapon.range_value`, already an integer.
        let rng_in = w.range as i64;
        if rng_in <= 0 || (rng_in as f64) < dist_in {
            continue;
        }
        if weapon_has(w, "Strafing") {
            continue; // NML-002: fires only through the move-through trigger
        }
        let attacks = w.attacks.max(0) * w.count.max(1);
        if attacks <= 0 {
            continue;
        }
        raw.push(base_profile(w, attacks, rng_in));
    }
    merge_identical(raw)
}

/// `AiShooting.melee_profiles` ai_shooting.gd:44-56 — every range-0 weapon, also
/// UNSTAMPED. Strafing is NOT excluded here: that filter lives in
/// `profiles_in_range` alone, and a melee weapon never carries the move-through
/// trigger.
pub(crate) fn melee_profiles(weapons: &[Weapon]) -> Vec<ShootProfile> {
    let mut raw: Vec<ShootProfile> = Vec::new();
    for w in weapons {
        if w.range as i64 > 0 {
            continue;
        }
        let attacks = w.attacks.max(0) * w.count.max(1);
        if attacks <= 0 {
            continue;
        }
        raw.push(base_profile(w, attacks, 0));
    }
    merge_identical(raw)
}

impl UnitStatic {
    pub fn build(reg: &mut Registries, p: &Profile) -> UnitStatic {
        let mut unimplemented: Vec<Unimplemented> = Vec::new();

        let mut shoot = profiles_in_range(&p.weapons, 0.0);
        stamp(reg, p, &mut shoot, &mut unimplemented);
        stamp_conditional_ap(reg, p, &mut shoot);
        stamp_unit_strikers(p, &mut shoot);

        let mut melee = melee_profiles(&p.weapons);
        // The same stamping runs on the melee array (`_profiles_of(su, true)`
        // battle_sim.gd:719-720 takes the identical path); a rule the port
        // cannot model is reported ONCE, not once per array.
        let mut melee_unimpl: Vec<Unimplemented> = Vec::new();
        stamp(reg, p, &mut melee, &mut melee_unimpl);
        stamp_conditional_ap(reg, p, &mut melee);
        stamp_unit_strikers(p, &mut melee);
        for u in melee_unimpl {
            if !unimplemented.contains(&u) {
                unimplemented.push(u);
            }
        }

        let is_caster = has_special_rule(&p.special_rules, "Caster")
            || has_special_rule(&p.special_rules, "Caster Group");
        let spells = if is_caster {
            reg.spells_for(&p.game_system, &p.faction_folder).to_vec()
        } else {
            Vec::new()
        };

        UnitStatic {
            ctx: ctx_for(reg, p),
            name: p.name.clone(),
            shoot,
            melee,
            model_count: p.model_count,
            wounds_max: p.wounds_max.clone(),
            quality: p.quality,
            fearless: has_special_rule(&p.special_rules, "Fearless"),
            is_caster,
            spells,
            caster_group: has_special_rule(&p.special_rules, "Caster Group"),
            casts_per_round: p.caster_value,
            battleborn_active: unit_rule_active(reg, p, "Battleborn"),
            steadfast_active: unit_rule_active(reg, p, "Steadfast"),
            unimplemented,
        }
    }
}

/// NML-1073 M2-5b — the derived per-unit closure for a profile TABLE, memoised
/// by that table's identity (`Rc::ptr_eq`).
///
/// `ProfileCache` hands back the same `Rc<Profiles>` for as long as the game's
/// dynamic reading holds, so this cache rebuilds `UnitStatic` only on the
/// activation where something actually changed — a hero falling, a spell
/// granting a rule — and never once per activation.
///
/// Bounded on purpose: a long game produces one distinct reading per such
/// event, and `ProfileCache` only ever asks for two of them (the header's and
/// the current one). Slot 0 — the header's table — is never evicted, so a game
/// that returns to its deployment reading finds it still here.
#[derive(Default)]
pub struct StaticsCache {
    entries: Vec<(Rc<Profiles>, Rc<Vec<UnitStatic>>)>,
    /// How many tables were rebuilt (a diagnostic — the cost this cache exists
    /// to keep off the per-activation path).
    pub builds: u64,
}

impl std::fmt::Debug for StaticsCache {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("StaticsCache")
            .field("entries", &self.entries.len())
            .field("builds", &self.builds)
            .finish()
    }
}

/// Distinct profile tables kept at once. Two is the steady state (the header's
/// and the current reading); the rest is slack for a game that flips back.
const STATICS_CACHE_CAP: usize = 4;

impl StaticsCache {
    pub fn new() -> StaticsCache {
        StaticsCache::default()
    }

    /// The closure for `profiles`, built once per distinct table.
    pub fn get(&mut self, reg: &mut Registries, profiles: &Rc<Profiles>) -> Rc<Vec<UnitStatic>> {
        if let Some((_, s)) = self.entries.iter().find(|(p, _)| Rc::ptr_eq(p, profiles)) {
            return Rc::clone(s);
        }
        let built: Vec<UnitStatic> =
            profiles.list.iter().map(|p| UnitStatic::build(reg, p)).collect();
        let rc = Rc::new(built);
        self.builds += 1;
        if self.entries.len() >= STATICS_CACHE_CAP {
            self.entries.remove(1); // slot 0 is the header's table — keep it
        }
        self.entries.push((Rc::clone(profiles), Rc::clone(&rc)));
        rc
    }
}
