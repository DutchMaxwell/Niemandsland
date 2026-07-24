class_name SpellsRegistry
extends RefCounted
## Solo-AI wave 6 — the SYSTEM-SCOPED faction spell-list loader. Reads the committed, text-free
## spell maps (assets/solo/spells_mechanics_<system>.json, emitted by tools/spells_mechanics_export.py
## from the maintainer's local registry + Army Forge cache) and answers "which spells does faction F
## field in game system S, with which mechanical encoding?".
##
## HARD INVARIANT (the RulesRegistry contract, extended to spells): spell lists are ALWAYS resolved
## by (game_system, faction) — never by faction alone across systems. A faction's spell list DIVERGES
## between the full-scale and skirmish-scale games (measured: 77 of 82 books published for 2+ systems
## have parameter-divergent lists — same spell names, different target counts / hits / ranges), so a
## name-only or faction-only lookup would resolve the WRONG mechanics.
##
## Lists are BOOK-ORDERED: the official Solo & Co-Op v3.5.0 cast procedure indexes the printed spell
## list with a D3+X roll and cycles forward — the committed order IS rule data, never sort it.
##
## Every reader returns an empty fallback when the map (or faction) is absent, so factions without
## spell data simply keep the pre-wave-6 behaviour (casting stays fully manual).

const MAP_PATH_TEMPLATE: String = "res://assets/solo/spells_mechanics_%s.json"

## Per-system parsed map cache (system slug -> Dictionary; a failed load caches {} so a missing file
## is probed once, not per lookup).
static var _cache: Dictionary = {}


## The full spell map of a system ({} when the asset is missing — every reader falls back).
static func map_for(system: String) -> Dictionary:
	var s := RulesRegistry.normalize_system(system)
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


## THE lookup: the BOOK-ORDERED spell entries of (system, faction). [] when the map or faction is
## unknown (the caller's conservative fallback: no automated casting for that faction).
static func spells_for(system: String, faction: String) -> Array:
	var m := map_for(system)
	if m.is_empty() or faction.is_empty():
		return []
	var factions: Dictionary = m.get("factions", {})
	var fmap: Dictionary = factions.get(faction, {})
	return fmap.get("spells", [])


## spells_for() addressed by a live unit (system/faction read from its import properties — the same
## seams RulesRegistry uses, so spells and rules always resolve for the SAME system+faction).
static func spells_for_unit(unit: GameUnit) -> Array:
	return spells_for(RulesRegistry.system_of_unit(unit), RulesRegistry.faction_of_unit(unit))


## One spell entry by name (for the human-side assist / tests); {} when unknown.
static func entry_for(system: String, faction: String, spell_name: String) -> Dictionary:
	for sp in spells_for(system, faction):
		if str((sp as Dictionary).get("name", "")) == spell_name:
			return sp
	return {}
