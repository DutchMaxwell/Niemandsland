//! `RulesRegistry` (scripts/solo/rules_registry.gd) and `SpellsRegistry`
//! (scripts/solo/spells_registry.gd): the system-scoped mechanics maps that turn
//! a unit's printed rule names into parameter knobs.
//!
//! Both read the committed assets `assets/solo/rules_mechanics_<system>.json`
//! and `assets/solo/spells_mechanics_<system>.json` from a repo root handed in
//! on the command line — the same files the game loads through `res://`.
//!
//! HARD INVARIANT carried over verbatim (rules_registry.gd:9-13): a lookup is
//! ALWAYS keyed (system, faction, name) with a fallback to (system, "common",
//! name), never by name alone.

use std::collections::HashMap;
use std::path::Path;
use std::sync::atomic::{AtomicBool, Ordering};

use serde_json::Value;

/// `RulesRegistry.SYSTEMS` / `DEFAULT_SYSTEM` — rules_registry.gd:18-19.
const SYSTEMS: [&str; 5] = ["gf", "gff", "aof", "aofs", "aofr"];
const DEFAULT_SYSTEM: &str = "gf";
const COMMON: &str = "common";

/// `RulesRegistry.normalize_system` rules_registry.gd:28-30.
pub fn normalize_system(system: &str) -> String {
    let s = system.trim().to_lowercase();
    if SYSTEMS.contains(&s.as_str()) {
        s
    } else {
        DEFAULT_SYSTEM.to_string()
    }
}

/// `RulesRegistry.base_rule_name` rules_registry.gd:123-124 — "Armor(4)" -> "Armor".
pub fn base_rule_name(rule: &str) -> String {
    rule.trim()
        .split('(')
        .next()
        .unwrap_or("")
        .trim()
        .to_string()
}

/// `RulesRegistry.rule_rating` rules_registry.gd:139-145 — "Retaliate(3)" -> 3;
/// `fallback` when the text between the parentheses is not a plain integer.
pub fn rule_rating(rule: &str, fallback: i64) -> i64 {
    let s = rule.trim();
    let Some(open) = s.find('(') else {
        return fallback;
    };
    let inner = s[open + 1..].trim_end_matches(')').trim();
    // `String.is_valid_int()` accepts an optional leading sign and digits only.
    let body = inner.strip_prefix(['+', '-']).unwrap_or(inner);
    if !body.is_empty() && body.chars().all(|c| c.is_ascii_digit()) {
        inner.parse::<i64>().unwrap_or(fallback)
    } else {
        fallback
    }
}

/// `GameUnit.rule_name_matches` game_unit.gd — the EXACT rule name, or the name
/// followed by a parenthesised qualifier (the rating form "Tough(3)", the
/// " (spell)" grant mark). A bare prefix is NOT a match: "Fearless" is not
/// "Fear", "Caster Group" is not "Caster" (NML-1112).
pub fn rule_name_matches(candidate: &str, rule: &str) -> bool {
    let s = candidate.trim();
    if s == rule {
        return true;
    }
    if LEGACY_PREFIX_RULES.load(Ordering::Relaxed) {
        return s.starts_with(rule);
    }
    // `starts_with` guarantees `rule.len()` is a char boundary of `s`.
    s.starts_with(rule) && s[rule.len()..].trim_start().starts_with('(')
}

/// LEGACY REPLAY ONLY — restores the pre-NML-1112 PREFIX reading of every rule
/// name, and nothing else in this crate reads it. `false` (the default, and the
/// only setting a fresh corpus may use) is the shipped rule: exact name or
/// parametrised form.
///
/// Why a switch exists at all: `tools/core_selfplay.gd` runs no aura expansion
/// (see `list_to_profile.LEGACY_CORE_SELFPLAY`), so a unit that carries
/// "Furious Aura" never got the plain "Furious" the live import writes via
/// `OPRArmyManager._expand_auras`. Under the old prefix match the aura label
/// answered the "Furious" query by accident, and the frozen corpora recorded
/// that answer into board column 18 (the flag) and column 13 (melee EV, through
/// `ctx_for`'s `furious`).
///
/// NEITHER READING IS THE GAME-TRUE ONE. The prefix gave the rule to the aura's
/// CARRIER only; a real aura grants it to the whole unit. These corpora pin the
/// SEARCH LOOP, not the rule — a re-recorded corpus with a real aura expansion
/// (NML-1105, the core_selfplay.gd loader) will differ from both. Never set this
/// to make a new recording agree with an old one.
pub static LEGACY_PREFIX_RULES: AtomicBool = AtomicBool::new(false);

/// `GameUnit.has_special_rule` game_unit.gd — exact name or parametrised form,
/// which is why "Caster" finds "Caster(1)" but never "Caster Group".
pub fn has_special_rule(rules: &[String], rule: &str) -> bool {
    rules.iter().any(|r| rule_name_matches(r, rule))
}

/// `AiEv.unit_rating` ai_ev.gd:117-125 — rating X of a unit-level "Name(X)"
/// rule, 0 when absent; the leading "+" of "Deadly(+3)" is stripped.
pub fn unit_rating(rules: &[String], rule_name: &str) -> i64 {
    let prefix = format!("{rule_name}(");
    for r in rules {
        let s = r.trim();
        if s.starts_with(&prefix) && s.ends_with(')') {
            let inner = &s[prefix.len()..s.len() - 1];
            let cleaned: String = inner.chars().filter(|c| *c != '+').collect();
            // GDScript `int("")` is 0, and so is `int("abc")`.
            return gd_int(&cleaned).max(0);
        }
    }
    0
}

/// GDScript's `int(String)`: leading integer prefix, 0 when there is none.
fn gd_int(s: &str) -> i64 {
    let s = s.trim();
    let (sign, rest) = match s.strip_prefix('-') {
        Some(r) => (-1, r),
        None => (1, s.strip_prefix('+').unwrap_or(s)),
    };
    let digits: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    sign * digits.parse::<i64>().unwrap_or(0)
}

/// One mechanics entry: `{"primitive": ..., "params": {...}}`.
#[derive(Debug, Default, Clone)]
pub struct Entry {
    pub primitive: Option<String>,
    pub params: Value,
}

impl Entry {
    pub fn param_i(&self, key: &str, fallback: i64) -> i64 {
        match self.params.get(key) {
            Some(Value::Number(n)) => n.as_f64().map(|f| f as i64).unwrap_or(fallback),
            Some(Value::String(s)) => gd_int(s),
            _ => fallback,
        }
    }
    pub fn param_f(&self, key: &str, fallback: f64) -> f64 {
        match self.params.get(key) {
            Some(Value::Number(n)) => n.as_f64().unwrap_or(fallback),
            _ => fallback,
        }
    }
    pub fn param_b(&self, key: &str) -> bool {
        matches!(self.params.get(key), Some(Value::Bool(true)))
    }
    pub fn param_s(&self, key: &str) -> &str {
        match self.params.get(key) {
            Some(Value::String(s)) => s.as_str(),
            _ => "",
        }
    }
}

fn entries_of(map: &Value) -> HashMap<String, Entry> {
    let mut out = HashMap::new();
    if let Some(obj) = map.as_object() {
        for (k, v) in obj {
            out.insert(
                k.clone(),
                Entry {
                    primitive: v.get("primitive").and_then(|p| p.as_str()).map(String::from),
                    params: v.get("params").cloned().unwrap_or(Value::Null),
                },
            );
        }
    }
    out
}

/// One system's mechanics map. An ABSENT file is an empty map, and every reader
/// then answers with the caller's fallback — rules_registry.gd:15-16's
/// "data refines, never breaks" contract.
#[derive(Debug, Default)]
pub struct RulesMap {
    pub empty: bool,
    common: HashMap<String, Entry>,
    factions: HashMap<String, HashMap<String, Entry>>,
}

impl RulesMap {
    /// `RulesRegistry.lookup` rules_registry.gd:57-66 — faction first, then common.
    pub fn lookup(&self, faction: &str, rule_name: &str) -> Option<&Entry> {
        if self.empty {
            return None;
        }
        if !faction.is_empty() && faction != COMMON {
            if let Some(f) = self.factions.get(faction) {
                if let Some(e) = f.get(rule_name) {
                    return Some(e);
                }
            }
        }
        self.common.get(rule_name)
    }

    /// `RulesRegistry.has_primitive` rules_registry.gd:73-75 — an unautomated
    /// entry carries an explicit `"primitive": null`, which must NOT count.
    pub fn has_primitive(&self, faction: &str, rule_name: &str) -> bool {
        match self.lookup(faction, rule_name) {
            Some(e) => e.primitive.as_deref().map(|p| !p.is_empty()).unwrap_or(false),
            None => false,
        }
    }
}

/// One spell-list entry of `spells_mechanics_<system>.json`.
#[derive(Debug, Clone)]
pub struct Spell {
    pub name: String,
    pub status: String,
    pub threshold: i64,
    pub range_in: f64,
    pub target_count: i64,
    pub effect_kind: String,
    pub effect_hits: i64,
    pub weapon_rules: Vec<String>,
    /// `effect.beneficiary` — "attackers" means the modifier belongs to whoever
    /// attacks this unit, so it never joins the bearer's own hit/def net
    /// (battle_sim.gd:971-975, mirroring main.gd:3652).
    pub beneficiary: String,
    /// `effect.modifier`. `present` is the GDScript's `modifier.is_empty()`
    /// test: a NON-empty dict makes the cast a stamp even when every field the
    /// sim reads is zero (e.g. a `casting_mod`-only debuff).
    pub modifier: SpellModifier,
}

/// The six `effect.modifier` fields `BattleSim._apply_cast_effect` reads
/// (battle_sim.gd:976-982); everything else in that dict is a no-op there.
#[derive(Debug, Clone, Copy, Default)]
pub struct SpellModifier {
    pub present: bool,
    pub hit_mod: f64,
    pub def_mod: f64,
    pub morale_mod: f64,
    pub range_in: f64,
    pub advance_in: f64,
    pub rush_in: f64,
}

/// The registries, loaded once per repo root and cached per system slug.
#[derive(Debug, Default)]
pub struct Registries {
    root: String,
    rules: HashMap<String, RulesMap>,
    /// (system, faction) -> BOOK-ORDERED spell list (spells_registry.gd:13-14:
    /// the committed order IS rule data, never sort it).
    spells: HashMap<String, HashMap<String, Vec<Spell>>>,
}

impl Registries {
    pub fn new(repo_root: &str) -> Registries {
        Registries {
            root: repo_root.to_string(),
            ..Default::default()
        }
    }

    pub fn rules_for(&mut self, system: &str) -> &RulesMap {
        let s = normalize_system(system);
        if !self.rules.contains_key(&s) {
            let path = Path::new(&self.root)
                .join("assets/solo")
                .join(format!("rules_mechanics_{s}.json"));
            let map = match std::fs::read_to_string(&path)
                .ok()
                .and_then(|t| serde_json::from_str::<Value>(&t).ok())
            {
                Some(v) => {
                    let mut factions = HashMap::new();
                    if let Some(obj) = v.get("factions").and_then(|f| f.as_object()) {
                        for (fk, fv) in obj {
                            factions.insert(fk.clone(), entries_of(fv));
                        }
                    }
                    RulesMap {
                        empty: false,
                        common: entries_of(v.get("common").unwrap_or(&Value::Null)),
                        factions,
                    }
                }
                None => RulesMap {
                    empty: true,
                    ..Default::default()
                },
            };
            self.rules.insert(s.clone(), map);
        }
        &self.rules[&s]
    }

    /// `SpellsRegistry.spells_for` spells_registry.gd:49-55 — [] when the map or
    /// the faction is unknown (conservative: that faction simply never casts).
    pub fn spells_for(&mut self, system: &str, faction: &str) -> &[Spell] {
        let s = normalize_system(system);
        if !self.spells.contains_key(&s) {
            let path = Path::new(&self.root)
                .join("assets/solo")
                .join(format!("spells_mechanics_{s}.json"));
            let mut by_faction: HashMap<String, Vec<Spell>> = HashMap::new();
            if let Some(v) = std::fs::read_to_string(&path)
                .ok()
                .and_then(|t| serde_json::from_str::<Value>(&t).ok())
            {
                if let Some(fs) = v.get("factions").and_then(|f| f.as_object()) {
                    for (fk, fv) in fs {
                        let mut list = Vec::new();
                        if let Some(arr) = fv.get("spells").and_then(|s| s.as_array()) {
                            for e in arr {
                                list.push(spell_of(e));
                            }
                        }
                        by_faction.insert(fk.clone(), list);
                    }
                }
            }
            self.spells.insert(s.clone(), by_faction);
        }
        if faction.is_empty() {
            return &[];
        }
        match self.spells[&s].get(faction) {
            Some(v) => v.as_slice(),
            None => &[],
        }
    }
}

fn spell_of(e: &Value) -> Spell {
    let eff = e.get("effect");
    Spell {
        name: e.get("name").and_then(|v| v.as_str()).unwrap_or("").to_string(),
        // `str(entry.get("status", "unmodeled"))` — battle_sim.gd:783.
        status: e
            .get("status")
            .and_then(|v| v.as_str())
            .unwrap_or("unmodeled")
            .to_string(),
        threshold: e.get("threshold").and_then(|v| v.as_i64()).unwrap_or(1),
        range_in: e.get("range_in").and_then(|v| v.as_f64()).unwrap_or(0.0),
        target_count: e
            .get("target")
            .and_then(|t| t.get("count"))
            .and_then(|v| v.as_i64())
            .unwrap_or(1),
        effect_kind: eff
            .and_then(|v| v.get("kind"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        effect_hits: eff
            .and_then(|v| v.get("hits"))
            .and_then(|v| v.as_i64())
            .unwrap_or(0),
        weapon_rules: eff
            .and_then(|v| v.get("weapon_rules"))
            .and_then(|v| v.as_array())
            .map(|a| {
                a.iter()
                    .map(|r| r.as_str().unwrap_or("").to_string())
                    .collect()
            })
            .unwrap_or_default(),
        beneficiary: eff
            .and_then(|v| v.get("beneficiary"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        modifier: modifier_of(eff.and_then(|v| v.get("modifier"))),
    }
}

fn modifier_of(m: Option<&Value>) -> SpellModifier {
    let Some(obj) = m.and_then(|v| v.as_object()) else {
        return SpellModifier::default();
    };
    if obj.is_empty() {
        return SpellModifier::default(); // `modifier.is_empty()` — battle_sim.gd:966
    }
    let f = |k: &str| obj.get(k).and_then(|v| v.as_f64()).unwrap_or(0.0);
    SpellModifier {
        present: true,
        hit_mod: f("hit_mod"),
        def_mod: f("def_mod"),
        morale_mod: f("morale_mod"),
        range_in: f("range_in"),
        advance_in: f("advance_in"),
        rush_in: f("rush_in"),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ratings_and_prefixes_match_gdscript() {
        assert_eq!(base_rule_name("Armor(4)"), "Armor");
        assert_eq!(base_rule_name(" Tough (3) "), "Tough");
        assert_eq!(rule_rating("Retaliate(3)", 0), 3);
        assert_eq!(rule_rating("Retaliate", 7), 7);
        // `"+3".is_valid_int()` is true in Godot, so the rating parses.
        assert_eq!(rule_rating("Deadly(+3)", 0), 3);
        assert_eq!(rule_rating("Deadly(X)", 0), 0, "a non-numeric rating falls back");
        assert_eq!(unit_rating(&["Tough(3)".into()], "Tough"), 3);
        assert_eq!(unit_rating(&["Deadly(+3)".into()], "Deadly"), 3, "the + is stripped");
        assert_eq!(unit_rating(&["Tough".into()], "Tough"), 0);
        assert!(has_special_rule(&["Caster(1)".into()], "Caster"));
        assert!(!has_special_rule(&["Caster(1)".into()], "Fearless"));
        // NML-1112: exact name or parametrised form, never a bare prefix.
        assert!(!has_special_rule(&["Fearless".into()], "Fear"));
        assert!(!has_special_rule(&["Caster Group".into()], "Caster"));
        assert!(has_special_rule(&["Relentless (spell)".into()], "Relentless"));
        assert!(rule_name_matches("Tough(3)", "Tough"));
        assert!(!rule_name_matches("Toughness", "Tough"));
    }
}
