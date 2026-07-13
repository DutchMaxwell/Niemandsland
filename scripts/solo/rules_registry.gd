class_name RulesRegistry
extends RefCounted
## Solo-AI wave 5 — the SYSTEM-SCOPED special-rules mechanics loader. Reads the committed, text-free
## mechanics maps (assets/solo/rules_mechanics_<system>.json, emitted by tools/rules_mechanics_export.py
## from the maintainer's local registry) and answers "which primitive automates rule R, with which
## parameter knobs, for THIS game system and faction?".
##
## HARD INVARIANT — lookups are ALWAYS keyed (game_system, faction, name) with a fallback to
## (game_system, "common", name), NEVER by name alone across systems: 154 of 383 cross-system rule
## names diverge (the skirmish-scale games rewrite Banner/Musician/auras/ranges), so the same name can
## mean different parameters in GF vs GFF vs AoF-Skirmish. The game system at runtime is the imported
## army's `gameSystem` field (carried into unit_properties["game_system"]); a system-selection UI is a
## later package.
##
## Every reader returns a caller-supplied fallback when the map (or the rule) is absent, so the
## wave-1..4 behaviour is byte-identical whenever data is missing — data refines, never breaks.

const SYSTEMS: Array = ["gf", "gff", "aof", "aofs", "aofr"]
const DEFAULT_SYSTEM: String = "gf"
const COMMON: String = "common"
const MAP_PATH_TEMPLATE: String = "res://assets/solo/rules_mechanics_%s.json"

## Per-system parsed map cache (system slug -> Dictionary; a failed load caches {} so a missing file
## is probed once, not per lookup).
static var _cache: Dictionary = {}


## A known system slug, or DEFAULT_SYSTEM for anything unknown/empty (pre-import units, tests).
static func normalize_system(system: String) -> String:
	var s := system.strip_edges().to_lower()
	return s if SYSTEMS.has(s) else DEFAULT_SYSTEM


## The full mechanics map of a system ({} when the asset is missing — every reader falls back).
static func map_for(system: String) -> Dictionary:
	var s := normalize_system(system)
	if _cache.has(s):
		return _cache[s]
	var parsed: Dictionary = {}
	var path := MAP_PATH_TEMPLATE % s
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var data: Variant = JSON.parse_string(f.get_as_text())
			if data is Dictionary:
				parsed = data
	_cache[s] = parsed
	return parsed


## Clear the cache (tests / a future hot-reload seam).
static func reset_cache() -> void:
	_cache = {}


## THE lookup: the mechanics entry for `rule_name` — the faction's own entry first, then the system's
## common (core) entry. {} when the rule is unknown to the map. `rule_name` is the base name (rating
## stripped: "Armor(4)" -> "Armor" — callers strip via base_rule_name).
static func lookup(system: String, faction: String, rule_name: String) -> Dictionary:
	var m := map_for(system)
	if m.is_empty():
		return {}
	var factions: Dictionary = m.get("factions", {})
	if not faction.is_empty() and faction != COMMON and factions.has(faction):
		var fmap: Dictionary = factions[faction]
		if fmap.has(rule_name):
			return fmap[rule_name]
	var common: Dictionary = m.get("common", {})
	return common.get(rule_name, {})


## Whether the map resolves `rule_name` to an automating primitive for (system, faction).
static func has_primitive(system: String, faction: String, rule_name: String) -> bool:
	return str(lookup(system, faction, rule_name).get("primitive", "")) != ""


## One parameter knob of a rule's mechanics entry; `fallback` when the map/rule/param is absent —
## the byte-identical seam: fallbacks are the wave-1..4 hardcoded constants.
static func param(system: String, faction: String, rule_name: String, key: String, fallback: Variant) -> Variant:
	var entry := lookup(system, faction, rule_name)
	if entry.is_empty():
		return fallback
	var params: Dictionary = entry.get("params", {})
	return params.get(key, fallback)


## param() addressed by a live unit (system/faction read from its import properties).
static func unit_param(unit: GameUnit, rule_name: String, key: String, fallback: Variant) -> Variant:
	return param(system_of_unit(unit), faction_of_unit(unit), rule_name, key, fallback)


## The DERIVED modeled-rule token list of a system (wave-5: data replaces main.gd's hardcoded
## SOLO_MODELED_RULES wherever the map is present). `fallback` when the map is missing.
static func modeled_tokens(system: String, fallback: Array = []) -> Array:
	var m := map_for(system)
	var tokens: Array = m.get("modeled", [])
	return tokens if not tokens.is_empty() else fallback


## The DERIVED decision-relevant token list (main.gd's SOLO_DECISION_RULES seam).
static func decision_tokens(system: String, fallback: Array = []) -> Array:
	var m := map_for(system)
	var tokens: Array = m.get("decision", [])
	return tokens if not tokens.is_empty() else fallback


## The game system a unit was imported for (unit_properties["game_system"], stamped by the army
## import from the list's gameSystem field); DEFAULT_SYSTEM when absent (manual/test units).
static func system_of_unit(unit: GameUnit) -> String:
	if unit == null:
		return DEFAULT_SYSTEM
	return normalize_system(str(unit.unit_properties.get("game_system", "")))


## The unit's faction slug (unit_properties["faction_folder"], the normalised army-book name — the
## same slugs the mechanics maps key their faction sections by). "" when unknown -> common-only lookup.
static func faction_of_unit(unit: GameUnit) -> String:
	if unit == null:
		return ""
	return str(unit.unit_properties.get("faction_folder", ""))


## Base rule name of a rule string: rating + whitespace stripped ("Armor(4)" -> "Armor").
static func base_rule_name(rule: String) -> String:
	return rule.strip_edges().get_slice("(", 0).strip_edges()


## Whether a unit carries `rule_name` AND the map resolves it for the unit's (system, faction) —
## the wave-5 gate for the new data-driven primitives: a rule fires only where its book actually
## fields it (system-scoped; no cross-system bleed). Falls back to the plain rule check when the
## map is absent (test/dev builds without assets).
static func unit_rule_active(unit: GameUnit, rule_name: String) -> bool:
	if unit == null or not unit.has_special_rule(rule_name):
		return false
	var m := map_for(system_of_unit(unit))
	if m.is_empty():
		return true
	return has_primitive(system_of_unit(unit), faction_of_unit(unit), rule_name)
