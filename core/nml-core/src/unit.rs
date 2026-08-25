//! The per-unit STATIC layer: everything `resolve`/`reply_threat` read off a
//! live `GameUnit`, resolved once per game.
//!
//! Three GDScript functions are folded in here, in their original order:
//!   * `AiShooting.profiles_in_range` ai_shooting.gd:14-26 + `merge_identical`
//!     :63-77 + `_profile` :90-152 — the ranged weapon profiles;
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

use crate::combat::{armored_defense, BANNER_MORALE_BONUS, REGENERATION_TARGET, SELF_REPAIR_TARGET};
use crate::rules::{
    base_rule_name, has_special_rule, rule_rating, unit_rating, Registries, Spell,
};
use crate::state::{Profile, Weapon};

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
    pub stealth: bool,
    pub evasive: bool,
    pub fortified: bool,
    pub guarded: bool,
    pub ranged_shrouding: bool,
    pub shielded: bool,
    pub in_cover: bool,
    pub regeneration: bool,
    pub regen_target: i64,
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
    /// Merged + stamped RANGED profiles, unfiltered (range > 0, any distance).
    pub shoot: Vec<ShootProfile>,
    pub model_count: i64,
    pub wounds_max: Vec<i64>,
    pub quality: i64,
    pub fearless: bool,
    pub is_caster: bool,
    pub spells: Vec<Spell>,
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
        stealth: rule_on_all_models(p, "Stealth"),
        evasive: rule_on_all_models(p, "Evasive"),
        fortified: rule_on_all_models(p, "Fortified"),
        // Guarded OR Versatile Defense — ai_ev.gd:157-158.
        guarded: rule_on_all_models(p, "Guarded") || rule_on_all_models(p, "Versatile Defense"),
        ranged_shrouding: rule_on_all_models(p, "Ranged Shrouding"),
        shielded: rule_on_all_models(p, "Shielded"),
        in_cover: false,
        regeneration: regen_target(reg, p) > 0,
        regen_target: regen_target(reg, p),
    }
}

impl UnitStatic {
    pub fn build(reg: &mut Registries, p: &Profile) -> UnitStatic {
        // --- profiles_in_range(weapons, 0.0): every ranged weapon (ai_shooting.gd:14-26) ---
        let mut raw: Vec<ShootProfile> = Vec::new();
        for w in &p.weapons {
            // `AiShooting._field_i(w, "range_value", 0)` — an int read; the
            // recorded value is `OPRWeapon.range_value`, already an integer.
            let rng_in = w.range as i64;
            if rng_in <= 0 {
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
        let mut shoot = merge_identical(raw);

        // --- stamp_sergeant (ai_ev.gd:203-274) ---
        let mut unimplemented: Vec<Unimplemented> = Vec::new();
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

        // --- _profiles_of's UNIT-level striker scan (battle_sim.gd:722-733) ---
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

        let is_caster = has_special_rule(&p.special_rules, "Caster")
            || has_special_rule(&p.special_rules, "Caster Group");
        let spells = if is_caster {
            reg.spells_for(&p.game_system, &p.faction_folder).to_vec()
        } else {
            Vec::new()
        };

        UnitStatic {
            ctx: ctx_for(reg, p),
            shoot,
            model_count: p.model_count,
            wounds_max: p.wounds_max.clone(),
            quality: p.quality,
            fearless: has_special_rule(&p.special_rules, "Fearless"),
            is_caster,
            spells,
            unimplemented,
        }
    }
}
