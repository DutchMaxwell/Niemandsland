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
use std::sync::{Mutex, OnceLock};

use serde_json::Value;

/// `RulesRegistry.SYSTEMS` / `DEFAULT_SYSTEM` — rules_registry.gd:18-19.
pub const SYSTEMS: [&str; 5] = ["gf", "gff", "aof", "aofs", "aofr"];
const DEFAULT_SYSTEM: &str = "gf";
const COMMON: &str = "common";

/// Hero aura rules for a game system.
/// Today every system uses GF 3.6 values (`reach_in: 6.0`, `min_tough: 9`, `joins: true`).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct HeroAura {
    pub reach_in: f64,
    pub min_tough: i64,
    pub joins: bool,
}

/// System-wide rules header: one struct per game book so core branches read book fields instead of
/// scattered system-string comparisons. Every field holds today's behaviour (zero outcome change for any system).
#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Book {
    pub system: &'static str,
    pub chain_in: f64,
    pub hero_aura: HeroAura,
    pub blast_spread_in: Option<f64>,
    pub vertical_moves: bool,
    pub default_board_in: [f64; 2],
}

const DEFAULT_HERO_AURA: HeroAura = HeroAura {
    reach_in: crate::sim::HERO_AURA_REACH_IN,
    min_tough: crate::sim::HERO_AURA_TOUGH,
    joins: true,
};

const BOOK_GF: Book = Book {
    system: "gf",
    chain_in: crate::mv::MAX_CHAIN_IN,
    hero_aura: DEFAULT_HERO_AURA,
    blast_spread_in: None,
    vertical_moves: false,
    default_board_in: [72.0, 48.0],
};

// The 3.6 Firefight book prints a 9 in chain (beginner's guide p.7); today's 6 in stays until the epoch-gated
// Firefight rules flip it, because a different chain changes how a `gff` game plays.
const BOOK_GFF: Book = Book {
    system: "gff",
    chain_in: crate::mv::SKIRMISH_CHAIN_IN,
    hero_aura: DEFAULT_HERO_AURA,
    blast_spread_in: None,
    vertical_moves: false,
    default_board_in: [48.0, 48.0],
};

const BOOK_AOF: Book = Book {
    system: "aof",
    chain_in: crate::mv::MAX_CHAIN_IN,
    hero_aura: DEFAULT_HERO_AURA,
    blast_spread_in: None,
    vertical_moves: false,
    default_board_in: [72.0, 48.0],
};

// The 3.6 Skirmish book prints 6 in (beginner's guide p.7), the same as today.
const BOOK_AOFS: Book = Book {
    system: "aofs",
    chain_in: crate::mv::SKIRMISH_CHAIN_IN,
    hero_aura: DEFAULT_HERO_AURA,
    blast_spread_in: None,
    vertical_moves: false,
    default_board_in: [48.0, 48.0],
};

const BOOK_AOFR: Book = Book {
    system: "aofr",
    chain_in: crate::mv::MAX_CHAIN_IN,
    hero_aura: DEFAULT_HERO_AURA,
    blast_spread_in: None,
    vertical_moves: false,
    default_board_in: [72.0, 48.0],
};

/// Return the static `Book` header for `system` (case/whitespace tolerant; empty or unknown folds to `"gf"`).
pub fn book(system: &str) -> &'static Book {
    match system.trim() {
        "gf" | "" => &BOOK_GF,
        "gff" => &BOOK_GFF,
        "aof" => &BOOK_AOF,
        "aofs" => &BOOK_AOFS,
        "aofr" => &BOOK_AOFR,
        other => match other.to_ascii_lowercase().as_str() {
            "gf" => &BOOK_GF,
            "gff" => &BOOK_GFF,
            "aof" => &BOOK_AOF,
            "aofs" => &BOOK_AOFS,
            "aofr" => &BOOK_AOFR,
            _ => &BOOK_GF,
        },
    }
}

/// F12 (analysis/SILENT_FAILURES_2026-09-13.md): an unrecognised system used to
/// fold onto `"gf"` in silence — a typo'd `game_system` played the wrong book
/// and said nothing. Count the folds per distinct input and name the input once
/// on stderr; the fold itself is unchanged (recording the fact is this step).
fn note_folded_system(input: &str) -> usize {
    static FOLDS: OnceLock<Mutex<HashMap<String, usize>>> = OnceLock::new();
    let mut folds = FOLDS
        .get_or_init(|| Mutex::new(HashMap::new()))
        .lock()
        .unwrap();
    let count = folds
        .entry(input.to_string())
        .and_modify(|c| *c += 1)
        .or_insert(1);
    if *count == 1 {
        eprintln!(
            "rules: unrecognised system {:?} folded to \"{}\"",
            input, DEFAULT_SYSTEM
        );
    }
    *count
}

/// `RulesRegistry.normalize_system` rules_registry.gd:28-30.
pub fn normalize_system(system: &str) -> String {
    let s = system.trim().to_lowercase();
    if SYSTEMS.contains(&s.as_str()) {
        s
    } else {
        note_folded_system(&s);
        DEFAULT_SYSTEM.to_string()
    }
}

/// 3.6 army-list folder -> committed map key for the nine renamed books
/// (`test/v36/dat_02_test.gd` RENAMED): the daemon books lost their
/// Wormhole/Rift prefix, the GF Saurian Starhost book gained a plural "s". A
/// list keeps the folder it was built against, so an alias still names the SAME
/// book in the SAME system — never a cross-system guess. `None` for non-aliases.
/// ONE table for BOTH registries: the spell book and the faction rules map.
fn faction_alias(system: &str, faction: &str) -> Option<String> {
    for sub in ["change", "lust", "plague", "war"] {
        let of = format!("daemons_of_{sub}");
        let wormhole = format!("wormhole_daemons_of_{sub}");
        let rift = format!("rift_daemons_of_{sub}");
        if faction != of && faction != wormhole && faction != rift {
            continue;
        }
        let canonical = match system {
            "gf" | "aof" => of,
            "gff" => wormhole,
            "aofs" | "aofr" => rift,
            _ => return None,
        };
        return (faction != canonical.as_str()).then_some(canonical);
    }
    let canonical = match (system, faction) {
        ("gf", "saurian_starhost") => "saurian_starhosts",
        ("gff", "saurian_starhosts") => "saurian_starhost",
        _ => return None,
    };
    Some(canonical.to_string())
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

/// `base_rule_name(rule) == base` without the `String` it allocates — the grant reads compare one base
/// name against every live record on every `ctx_live` call, so the allocation was a self-play hotspot.
pub fn base_rule_is(rule: &str, base: &str) -> bool {
    rule.trim().split('(').next().unwrap_or("").trim() == base
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
/// Why a switch exists at all: the frozen pre-NML-1105 corpora predate the
/// aura expansion `tools/core_selfplay.gd` does run today — since NML-1105 it
/// attaches the joined heroes and calls `OPRArmyManager.expand_auras_of`
/// (:568-570); `list_to_profile.LEGACY_CORE_SELFPLAY` replays them on
/// purpose. In them a "Furious Aura" carrier never got the plain "Furious":
/// under the old prefix match the aura label answered the "Furious" query by
/// accident, and the frozen corpora recorded that answer into board column 18
/// (the flag) and column 13 (melee EV, through `ctx_for`'s `furious`).
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

/// The table's Spawn target regex (main.gd:17486-17491,
/// `^[^(]+\((.+) \[(\d+)\]\)$`): `Spawn(Rat Swarm [10])` -> `("Rat Swarm", 10)`.
/// `None` for the bare name, a malformed bracket, or a non-positive count —
/// the table's beat never mints off the first two; a `Spawn(X [0])` string
/// the regex WOULD match is read here as no target at all (a zero-model copy
/// is not a summon), so it never demands a template either.
pub fn spawn_rule_target(rule: &str) -> Option<(String, i64)> {
    let s = rule.trim();
    let open = s.find('(')?;
    let inner = s[open + 1..].strip_suffix(')')?.trim();
    let bracket = inner.rfind(" [")?;
    let name = inner[..bracket].trim();
    let count = inner[bracket + 2..].strip_suffix(']')?.trim().parse::<i64>().ok()?;
    if name.is_empty() || count <= 0 {
        return None;
    }
    Some((name.to_string(), count))
}

/// The ONE raw-Spawn reader for both `spawn_of` (the statics read) and the
/// loader's template check: the FIRST parametrised `Spawn(<name> [<n>])`
/// string in the list — the same first-match order the beat's own read uses,
/// so the two can never disagree about which string names the template.
/// SPLIT step 1: the `Split(<name> [<n>])` family rides the SAME template
/// seam — a standing Split carrier must find its `spawn:` template like a
/// Spawn carrier does (io.rs `spawn_templates_of`). SPAWN FIRST: the
/// historical first-match order is preserved verbatim for any record that
/// carries a Spawn string, so every existing record resolves the template it
/// always did; a Split string answers only when no Spawn string does.
pub fn spawn_target_rule(rules: &[String]) -> Option<(String, String, i64)> {
    rules.iter().find_map(|r| {
        if !rule_name_matches(r, "Spawn") {
            return None;
        }
        spawn_rule_target(r).map(|(name, count)| (r.trim().to_string(), name, count))
    })
    .or_else(|| {
        rules.iter().find_map(|r| {
            if !rule_name_matches(r, "Split") {
                return None;
            }
            spawn_rule_target(r).map(|(name, count)| (r.trim().to_string(), name, count))
        })
    })
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
    /// A boolean knob whose PRINTED default is `true` (`bool(sp.get(k, true))`).
    pub fn param_b_or(&self, key: &str, fallback: bool) -> bool {
        match self.params.get(key) {
            Some(Value::Bool(b)) => *b,
            _ => fallback,
        }
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
    /// The system this map belongs to — the alias table is system-scoped.
    system: String,
    common: HashMap<String, Entry>,
    factions: HashMap<String, HashMap<String, Entry>>,
    /// The record epoch this map answers at (`Registries::set_rules_epoch`).
    /// Gates the 3.6 folder aliases (`acts::PENDING_EPOCH_RULES_ALIAS`): below
    /// the gate an old folder keeps its old common-only read, byte-exact.
    rules_epoch: u32,
}

impl RulesMap {
    /// The faction key a lookup reads: its own key when the map holds one, else
    /// the 3.6 same-system alias once the rules epoch has reached the gate.
    fn resolved_faction(&self, faction: &str) -> Option<String> {
        if self.factions.contains_key(faction) {
            return Some(faction.to_string());
        }
        if !crate::acts::rule_on(self.rules_epoch, crate::acts::PENDING_EPOCH_RULES_ALIAS) {
            return None;
        }
        let alias = faction_alias(&self.system, faction)?;
        self.factions.contains_key(&alias).then_some(alias)
    }

    /// `RulesRegistry.lookup` rules_registry.gd:57-66 — faction first, then common.
    /// A 3.6 renamed folder falls back to its same-system alias (gated, see above).
    pub fn lookup(&self, faction: &str, rule_name: &str) -> Option<&Entry> {
        if self.empty {
            return None;
        }
        if !faction.is_empty() && faction != COMMON {
            if let Some(f) = self.resolved_faction(faction).and_then(|k| self.factions.get(&k)) {
                if let Some(e) = f.get(rule_name) {
                    return Some(e);
                }
            }
        }
        self.common.get(rule_name)
    }

    /// The faction's OWN rule names (no common fallback), alias-resolved — the
    /// rule SET a 3.6 old folder and its canonical folder must share.
    pub fn faction_rule_names(&self, faction: &str) -> Vec<String> {
        let mut names: Vec<String> = self
            .resolved_faction(faction)
            .and_then(|k| self.factions.get(&k))
            .map(|m| m.keys().cloned().collect())
            .unwrap_or_default();
        names.sort();
        names
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
#[derive(Debug, Clone, Default)]
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
    /// `effect.grants_rule` — the rule name a "buff"/"debuff" cast hands its
    /// target(s), "" when the spell has none (DEFECT_LEDGER #33: a
    /// `grants_rule`-only spell had no field to parse it into at all, so
    /// Animate Spirit/Infuse Bloodthirst/Terror Seeker/Inspiring Bots/Mending
    /// Bots burned their pick and tokens for nothing). Same shape as
    /// `UtilityBuff.grants_rule` (unit.rs).
    pub grants_rule: String,
    /// Top-level `needs_los` — rules 3.6 (D-SPELL-LOS): a spell needs line of
    /// sight only when its own entry says so. Absent means false: the spell
    /// reaches any target in range, seen or not.
    pub needs_los: bool,
    /// `effect.scope` ("shooting", "melee", "attacking") — which attacks a stamped modifier or grant reads on, "" when the
    /// spell has none. The table lands a buff by name AND scope (CC-4b: parsed only, nothing reads it yet).
    pub scope: String,
    /// `target.kind` — "model" resolves as a unit of one (no Blast fan-out, main.gd:5799-5800), "unit" is the normal case;
    /// "" when the entry has none, which the table reads as a unit (CC-4b: parsed only, nothing reads it yet).
    pub target_kind: String,
}

/// The `effect.modifier` fields `BattleSim._apply_cast_effect` reads
/// (battle_sim.gd:976-982); everything else in that dict is a no-op there.
/// `casting_mod` rides along parsed (the catalogue's 18 debuff rows carry it)
/// but only from epoch 62 does `apply_cast_effect` WRITE it into the target's
/// `Mods.casting` snapshot slot — below 62 the field parses and then sits
/// inert, so every earlier record replays byte-exact.
#[derive(Debug, Clone, Copy, Default)]
pub struct SpellModifier {
    pub present: bool,
    pub hit_mod: f64,
    pub def_mod: f64,
    pub morale_mod: f64,
    pub casting_mod: f64,
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
    /// Mechanics files that could not be READ — absent or unreadable — as
    /// `path.display()`, in first-failure order, once per path (a cached
    /// system never re-reads, so it never re-pushes).
    missing: Vec<String>,
    /// The record epoch every rules map answers at (0 = pre-epoch, aliases off).
    /// `UnitStatic::build_for`/`unit::ctx_for` stamp the record's own epoch.
    rules_epoch: u32,
}

impl Registries {
    pub fn new(repo_root: &str) -> Registries {
        Registries {
            root: repo_root.to_string(),
            ..Default::default()
        }
    }

    /// The record epoch this registry answers at — the 3.6 folder aliases
    /// (`acts::PENDING_EPOCH_RULES_ALIAS`) switch on from 93, so a pre-93 record
    /// replays its old common-only faction reads byte-exact. Cached maps are
    /// re-stamped; a map loaded later inherits the stamp in `rules_for`.
    pub fn set_rules_epoch(&mut self, rules_epoch: u32) {
        self.rules_epoch = rules_epoch;
        for map in self.rules.values_mut() {
            map.rules_epoch = rules_epoch;
        }
    }

    pub fn rules_for(&mut self, system: &str) -> &RulesMap {
        let s = normalize_system(system);
        if !self.rules.contains_key(&s) {
            let path = Path::new(&self.root)
                .join("assets/solo")
                .join(format!("rules_mechanics_{s}.json"));
            let text = std::fs::read_to_string(&path);
            if text.is_err() {
                self.missing.push(path.display().to_string());
            }
            let map = match text.ok().and_then(|t| serde_json::from_str::<Value>(&t).ok()) {
                Some(v) => {
                    let mut factions = HashMap::new();
                    if let Some(obj) = v.get("factions").and_then(|f| f.as_object()) {
                        for (fk, fv) in obj {
                            factions.insert(fk.clone(), entries_of(fv));
                        }
                    }
                    RulesMap {
                        empty: false,
                        system: s.clone(),
                        rules_epoch: self.rules_epoch,
                        common: entries_of(v.get("common").unwrap_or(&Value::Null)),
                        factions,
                    }
                }
                None => RulesMap {
                    empty: true,
                    system: s.clone(),
                    rules_epoch: self.rules_epoch,
                    ..Default::default()
                },
            };
            self.rules.insert(s.clone(), map);
        }
        &self.rules[&s]
    }

    /// The faction's own rule names under `system`, alias-resolved at the
    /// registry's current epoch — the rule SET the alias test compares.
    pub fn faction_rule_names(&mut self, system: &str, faction: &str) -> Vec<String> {
        let s = normalize_system(system);
        self.rules_for(&s).faction_rule_names(faction)
    }

    /// `SpellsRegistry.spells_for` spells_registry.gd:63-81 — [] when the map or
    /// the faction is unknown (conservative: that faction simply never casts).
    /// A 3.6 renamed folder falls back to its same-system alias (`faction_alias`).
    pub fn spells_for(&mut self, system: &str, faction: &str) -> &[Spell] {
        let s = normalize_system(system);
        if !self.spells.contains_key(&s) {
            let path = Path::new(&self.root)
                .join("assets/solo")
                .join(format!("spells_mechanics_{s}.json"));
            let text = std::fs::read_to_string(&path);
            if text.is_err() {
                self.missing.push(path.display().to_string());
            }
            let mut by_faction: HashMap<String, Vec<Spell>> = HashMap::new();
            if let Some(v) = text.ok().and_then(|t| serde_json::from_str::<Value>(&t).ok()) {
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
        let by_faction = &self.spells[&s];
        if let Some(v) = by_faction.get(faction) {
            return v.as_slice();
        }
        if let Some(alias) = faction_alias(&s, faction) {
            if let Some(v) = by_faction.get(&alias) {
                return v.as_slice();
            }
        }
        &[]
    }

    /// The mechanics files this registry could not READ, in first-failure
    /// order, once per path — a player's bug report can quote the path.
    /// A file that READS but does not PARSE is not missing: it yields the
    /// empty map under the old contract and stays the caller's
    /// "registry empty" case.
    pub fn missing_files(&self) -> &[String] {
        &self.missing
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
        grants_rule: eff
            .and_then(|v| v.get("grants_rule"))
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string(),
        needs_los: e.get("needs_los").and_then(|v| v.as_bool()).unwrap_or(false),
        scope: eff.and_then(|v| v.get("scope")).and_then(|v| v.as_str()).unwrap_or("").to_string(),
        target_kind: e.get("target").and_then(|t| t.get("kind")).and_then(|v| v.as_str()).unwrap_or("").to_string(),
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
        casting_mod: f("casting_mod"),
        range_in: f("range_in"),
        advance_in: f("advance_in"),
        rush_in: f("rush_in"),
    }
}

/// A rule name that outlives the registry read, for the `Copy` dice contexts (`Ctx`) that name a rule in a log line: each distinct name is
/// leaked once (the registry holds a few hundred), so the same name always comes back as the same `&'static str`.
pub(crate) fn intern(name: &str) -> &'static str {
    use std::sync::{Mutex, OnceLock};
    static NAMES: OnceLock<Mutex<std::collections::HashSet<&'static str>>> = OnceLock::new();
    let mut seen = NAMES.get_or_init(Default::default).lock().unwrap_or_else(|e| e.into_inner());
    if let Some(&known) = seen.get(name) {
        return known;
    }
    let leaked: &'static str = Box::leak(name.to_string().into_boxed_str());
    seen.insert(leaked);
    leaked
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

    /// Every caster faction slug present in the committed fixtures
    /// (`core/nml-core-py/tests/python/fixtures`, `core/nml-core/tests/fixtures`,
    /// `test/fixtures`; JSON/JSONL objects with `caster_value > 0`, scanned
    /// 2026-11-19) must resolve a non-empty spell book. (system, faction_folder).
    const FIXTURE_CASTER_SLUGS: [(&str, &str); 41] = [
        ("gf", "alien_hives"), ("gf", "battle_brothers"), ("gf", "blessed_sisters"),
        ("gf", "blood_brothers"), ("gf", "change_disciples"), ("gf", "daemons_of_change"),
        ("gf", "elven_jesters"), ("gf", "havoc_brothers"), ("gf", "high_elf_fleets"),
        ("gf", "human_defense_force"), ("gf", "human_inquisition"),
        ("gf", "knight_prime_brothers"), ("gf", "lust_disciples"), ("gf", "machine_cults"),
        ("gf", "robot_legions"), ("gf", "saurian_starhosts"), ("gf", "soul_snatcher_cults"),
        ("gf", "titan_lords"), ("gf", "titan_lords_change_disciples"),
        ("gf", "titan_lords_lust_disciples"), ("gf", "titan_lords_plague_disciples"),
        ("gf", "wolf_prime_brothers"),
        ("aof", "beastmen"), ("aof", "change_disciples"), ("aof", "chivalrous_kingdoms"),
        ("aof", "daemons_of_change"), ("aof", "daemons_of_lust"), ("aof", "daemons_of_plague"),
        ("aof", "daemons_of_war"), ("aof", "deep_sea_elves"), ("aof", "dwarves"),
        ("aof", "giant_tribes_lust_disciples"), ("aof", "giant_tribes_plague_disciples"),
        ("aof", "havoc_warriors"), ("aof", "human_empire"), ("aof", "mummified_undead"),
        ("aof", "ratmen"), ("aof", "saurians"), ("aof", "shadow_stalkers"),
        ("aof", "sky_city_dwarves"), ("aof", "wood_elves"),
    ];

    #[test]
    fn every_fixture_caster_faction_slug_resolves_a_spell_book() {
        let root = format!("{}/../..", env!("CARGO_MANIFEST_DIR"));
        let mut reg = Registries::new(&root);
        let zero: Vec<String> = FIXTURE_CASTER_SLUGS
            .iter()
            .filter(|(system, faction)| reg.spells_for(system, faction).is_empty())
            .map(|(system, faction)| format!("{system}/{faction}"))
            .collect();
        assert!(zero.is_empty(), "caster factions resolve ZERO spell books: {}", zero.join(", "));
    }

    /// The 3.6 renamed books (`test/v36/dat_02_test.gd` RENAMED,
    /// `scripts/model_library.gd` FOLDER_ALIASES): a list stamps the folder it was
    /// built against; the map keys its 3.6 book. Each slug resolves the SAME book.
    const V36_SPELL_BOOK_ALIASES: [(&str, &str, &str); 22] = [
        ("gf", "wormhole_daemons_of_change", "daemons_of_change"),
        ("gf", "wormhole_daemons_of_lust", "daemons_of_lust"),
        ("gf", "wormhole_daemons_of_plague", "daemons_of_plague"),
        ("gf", "wormhole_daemons_of_war", "daemons_of_war"),
        ("gf", "saurian_starhost", "saurian_starhosts"),
        ("aof", "rift_daemons_of_change", "daemons_of_change"),
        ("aof", "rift_daemons_of_lust", "daemons_of_lust"),
        ("aof", "rift_daemons_of_plague", "daemons_of_plague"),
        ("aof", "rift_daemons_of_war", "daemons_of_war"),
        ("gff", "daemons_of_change", "wormhole_daemons_of_change"),
        ("gff", "daemons_of_lust", "wormhole_daemons_of_lust"),
        ("gff", "daemons_of_plague", "wormhole_daemons_of_plague"),
        ("gff", "daemons_of_war", "wormhole_daemons_of_war"),
        ("gff", "saurian_starhosts", "saurian_starhost"),
        ("aofs", "daemons_of_change", "rift_daemons_of_change"),
        ("aofs", "daemons_of_lust", "rift_daemons_of_lust"),
        ("aofs", "daemons_of_plague", "rift_daemons_of_plague"),
        ("aofs", "daemons_of_war", "rift_daemons_of_war"),
        ("aofr", "daemons_of_change", "rift_daemons_of_change"),
        ("aofr", "daemons_of_lust", "rift_daemons_of_lust"),
        ("aofr", "daemons_of_plague", "rift_daemons_of_plague"),
        ("aofr", "daemons_of_war", "rift_daemons_of_war"),
    ];

    #[test]
    fn every_v36_renamed_spell_book_alias_resolves_its_committed_book() {
        let root = format!("{}/../..", env!("CARGO_MANIFEST_DIR"));
        let mut reg = Registries::new(&root);
        let mut zero = Vec::new();
        for (system, alias, canonical) in V36_SPELL_BOOK_ALIASES {
            let alias_book: Vec<String> =
                reg.spells_for(system, alias).iter().map(|s| s.name.clone()).collect();
            let canonical_book: Vec<String> =
                reg.spells_for(system, canonical).iter().map(|s| s.name.clone()).collect();
            assert!(!canonical_book.is_empty(), "{system}/{canonical} is not a committed book");
            if alias_book.is_empty() {
                zero.push(format!("{system}/{alias}"));
            } else {
                assert_eq!(alias_book, canonical_book, "{system}/{alias} must resolve {canonical}");
            }
        }
        assert!(zero.is_empty(), "3.6 folder aliases resolve ZERO spell books: {}", zero.join(", "));
    }

    /// The RULES side of the same rename: `rules_mechanics_<system>.json` keys
    /// only the 3.6 folder, so an old-folder unit resolved ZERO faction rules
    /// (the granted-reach lookup then missed its spells' granted rules). Gated at
    /// `PENDING_EPOCH_RULES_ALIAS`: at 92 the old common-only read stays, from 93
    /// each alias resolves its canonical faction's rule set.
    #[test]
    fn every_v36_renamed_rules_folder_alias_resolves_the_same_rule_set_from_93() {
        let root = format!("{}/../..", env!("CARGO_MANIFEST_DIR"));
        let mut reg = Registries::new(&root);
        reg.set_rules_epoch(crate::acts::PENDING_EPOCH_RULES_ALIAS - 1);
        let mut leaked = Vec::new();
        for (system, alias, _canonical) in V36_SPELL_BOOK_ALIASES {
            if !reg.faction_rule_names(system, alias).is_empty() {
                leaked.push(format!("{system}/{alias}"));
            }
        }
        assert!(
            leaked.is_empty(),
            "below the gate an old folder resolved faction rules: {}",
            leaked.join(", ")
        );
        reg.set_rules_epoch(crate::acts::PENDING_EPOCH_RULES_ALIAS);
        for (system, alias, canonical) in V36_SPELL_BOOK_ALIASES {
            let alias_set = reg.faction_rule_names(system, alias);
            let canonical_set = reg.faction_rule_names(system, canonical);
            assert!(
                !canonical_set.is_empty(),
                "{system}/{canonical} is not a committed faction section"
            );
            assert_eq!(alias_set, canonical_set, "{system}/{alias} must resolve {canonical}");
        }
    }

    /// CC-4b: the spell entry's `effect.scope` and `target.kind` parse; an entry without them reads "" for both. RED: the two
    /// fields not read in `spell_of` -> every non-empty assertion below sees "".
    #[test]
    fn a_spell_entry_carries_its_scope_and_its_target_kind() {
        let root = format!("{}/../..", env!("CARGO_MANIFEST_DIR"));
        let mut reg = Registries::new(&root);
        let by_name = |reg: &mut Registries, faction: &str, name: &str| {
            let spells = reg.spells_for("gf", faction);
            spells.iter().find(|s| s.name == name).unwrap_or_else(|| panic!("{name} is not in the gf {faction} book")).clone()
        };
        let sight = by_name(&mut reg, "battle_brothers", "Advanced Sight");
        assert_eq!((sight.scope.as_str(), sight.target_kind.as_str()), ("shooting", "unit"));
        let assault = by_name(&mut reg, "havoc_brothers", "Dark Assault");
        assert_eq!((assault.scope.as_str(), assault.target_kind.as_str()), ("melee", "unit"));
        let shriek = by_name(&mut reg, "alien_hives", "Hive Shriek");
        assert_eq!((shriek.scope.as_str(), shriek.target_kind.as_str()), ("", "model"), "a damage spell has no scope");
        let bare = spell_of(&serde_json::json!({"name": "Bare", "effect": {"kind": "damage"}}));
        assert_eq!((bare.scope.as_str(), bare.target_kind.as_str()), ("", ""), "absent = \"\"");
    }

    /// SPLIT step 1: a parametrised `Split(<name> [<n>])` string names a
    /// template exactly like a Spawn string does — the recorder stamps it
    /// under `spawn:<carrier>:<Split string>` and the loader must demand it.
    /// RED while `spawn_target_rule` matches only "Spawn".
    #[test]
    fn split_strings_name_a_template_like_spawn_does() {
        assert_eq!(
            spawn_target_rule(&["Split(Goblin Mob [4])".into()]),
            Some(("Split(Goblin Mob [4])".to_string(), "Goblin Mob".to_string(), 4))
        );
        // The historical read keeps its FIRST-match order: a carrier with both
        // strings names the SPAWN template, exactly as every loaded record
        // read it — no existing record resolves a different string.
        assert_eq!(
            spawn_target_rule(&["Split(Goblin Mob [4])".into(), "Spawn(Rat Swarm [2])".into()])
                .map(|(raw, _, _)| raw),
            Some("Spawn(Rat Swarm [2])".to_string())
        );
    }

    #[test]
    fn folded_systems_are_counted_not_silent() {
        // F12: the fold onto "gf" says so — a per-input count (the one-line
        // warning is the eprintln in note_folded_system) and an unchanged fold.
        // Distinct input on purpose: tests run in parallel and share the map.
        assert_eq!(note_folded_system("zz-f12-unknown"), 1, "the fold is named");
        assert_eq!(note_folded_system("zz-f12-unknown"), 2, "and counted");
        assert_eq!(normalize_system("ZZ-F12-UNKNOWN "), "gf", "fold unchanged");
        assert_eq!(note_folded_system("zz-f12-unknown"), 4, "as \"zz-f12-unknown\"");
        assert_eq!(normalize_system("gf"), "gf");
    }

    /// Firefight step 4: `Book` + `book()` table for all five systems matches today's behaviour.
    /// `gf` equals `MAX_CHAIN_IN`, `HERO_AURA_TOUGH`, `HERO_AURA_REACH_IN`; `gff`/`aofs` keep
    /// `SKIRMISH_CHAIN_IN` (6 in) and 48x48 default board; unknown folds to `gf`.
    #[test]
    fn book_header_matches_todays_behaviour_for_all_five_systems() {
        let cases: [(&str, f64, [f64; 2]); 5] = [
            ("gf", crate::mv::MAX_CHAIN_IN, [72.0, 48.0]),
            ("gff", crate::mv::SKIRMISH_CHAIN_IN, [48.0, 48.0]),
            ("aof", crate::mv::MAX_CHAIN_IN, [72.0, 48.0]),
            ("aofs", crate::mv::SKIRMISH_CHAIN_IN, [48.0, 48.0]),
            ("aofr", crate::mv::MAX_CHAIN_IN, [72.0, 48.0]),
        ];
        assert_eq!(cases.len(), SYSTEMS.len());
        for (sys, chain_in, board_in) in cases {
            let b = book(sys);
            assert_eq!(b.system, sys, "system tag for {sys}");
            assert_eq!(b.chain_in, chain_in, "chain_in for {sys}");
            assert_eq!(b.hero_aura.reach_in, crate::sim::HERO_AURA_REACH_IN, "reach_in for {sys}");
            assert_eq!(b.hero_aura.min_tough, crate::sim::HERO_AURA_TOUGH, "min_tough for {sys}");
            assert!(b.hero_aura.joins, "joins stays true today for {sys}");
            assert_eq!(b.blast_spread_in, None, "blast spread stays off today for {sys}");
            assert!(!b.vertical_moves, "vertical moves stay off today for {sys}");
            assert_eq!(b.default_board_in, board_in, "default_board_in for {sys}");
        }
        assert_eq!(book(" GF ").system, "gf");
        assert_eq!(book("GFF").chain_in, crate::mv::SKIRMISH_CHAIN_IN);
        assert_eq!(book("").system, "gf");
        assert_eq!(book("unknown-system").system, "gf");
    }
}

