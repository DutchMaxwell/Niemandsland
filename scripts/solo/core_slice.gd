class_name CoreSlice
extends RefCounted
## One core P4.D-6: WHICH units the core door takes at the shooting door. The slice is DATA (assets/solo/core_slice_allow.json):
## a MODE and a set of GROUPS, so the predicate reads either way. Every unit rule and every weapon rule is resolved through
## `RulesRegistry.lookup(system, faction, name)` to a primitive; the groups LIST primitives (and the group "attached_heroes"
## lists attachments):
##   mode "allow": a unit is taken when every rule it carries is LISTED (allow by group). With no group, nothing with a rule.
##   mode "deny":  a unit is taken when no rule it carries is listed (the groups are the deny-list; allow by default).
## In both modes a rule the registry has no primitive for (unknown name, unautomated entry) is refused, and a shooter with no
## OPR profile never passes (a target needs none: `as_target`). C-19: the slice the AI door reads is the measured deny-list
## (DENY_PATH, mode "deny") unless `NML_CORE_SLICE=allow` (or `plain`) asks for the old shipped allow file (PATH: mode "allow"
## with one group, the move-through rules), the way back for one release. The HUMAN door (`*_human` below) is not switched
## by C-19 (the gate measured the AI door): it reads PATH until DS-109, or the live slice when the env or a test seam names one.
## Melee is not part of it: the human door's Charge selector stays refused in `human_shoot`.
## Each group is `{"primitives": [...], "step": "P4.D-n", "golden": "<fixture>", "parity": "<scenario>"}`.

const PATH := "res://assets/solo/core_slice_allow.json"
## C-19: the measured deny-list (mode "deny"), the AI door's slice unless env NML_CORE_SLICE=allow|plain picks PATH (the way back).
const DENY_PATH := "res://assets/solo/core_slice_deny.json"
const SCHEMA := "nml-core-slice-v1"
const MODES := ["allow", "deny"]
## P4.D-48: the AI charge door's own slice (door "melee"), read through `refusals_in`. Allow mode, no group = no rule at all.
const MELEE_PATH := "res://assets/solo/core_slice_melee.json"

## TEST SEAM (the RulesRegistry.map_path_override pattern): a path that replaces PATH. Empty in production, always.
static var path_override := ""
## {} = not read yet; else {"mode": "allow"|"deny", "primitives": {primitive: group}, "attached": bool (listed)}.
static var _loaded: Dictionary = {}


static func reset_cache() -> void:
	_loaded = {}


## The mode, the listed primitives and whether attachments are listed. A missing or malformed file is the EMPTY allow slice
## (the table shoots everything with a rule) and says so once: refusing is the safe direction, never silent.
static func config() -> Dictionary:
	if not _loaded.is_empty():
		return _loaded
	_loaded = {"mode": "allow", "primitives": {}, "attached": false, "inert": {}, "deny_names": {}, "unmapped_inert": false}
	var live := path_override.is_empty()
	var path := live_path()
	# Each file belongs to one door: the melee file only through MELEE_PATH, every other path (shipped, deny, a test file) is the shoot door's.
	var door := "melee" if path == MELEE_PATH else "shoot"
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (data is Dictionary) or str(data.get("schema", "")) != SCHEMA or str(data.get("door", "")) != door \
			or not MODES.has(str(data.get("mode", "allow"))):
		push_error("CoreSlice: %s is missing or not a %s file for the %s door - the slice is empty" % [path, SCHEMA, door])
		return _loaded
	_loaded["mode"] = str(data.get("mode", "allow"))
	for g in data.get("groups", {}):
		for p in data["groups"][g].get("primitives", []):
			_loaded["primitives"][str(p)] = str(g)
	_loaded["attached"] = (data.get("groups", {}) as Dictionary).has("attached_heroes")
	# Deny mode only: rule names with no effect on a volley (list-building rules, an item's own label) - taken although the
	# registry gives them no primitive. Each carries its reason in the file.
	if _loaded["mode"] == "deny":
		_loaded["inert"] = data.get("inert", {})
		_loaded["deny_names"] = data.get("deny_names", {})   # one rule NAME refused where its primitive is shared
		_loaded["unmapped_inert"] = bool(data.get("unmapped_inert", false))
	if live:
		print(mode_line())   # C-19: one line per load of the live slice (once per process outside the tests), so a log names the slice in use
	return _loaded


## C-19: env NML_CORE_SLICE=allow (or plain) is the way back to the shipped allow file. Unset, `deny` or any other value:
## the deny-list, the default (read with the slice, cached with it).
static func allow_switched() -> bool:
	var raw := OS.get_environment("NML_CORE_SLICE").to_lower()
	return raw == "allow" or raw == "plain"


## C-19: the file the AI door's slice reads (the test seam first, then the env, then the deny-list).
static func live_path() -> String:
	if not path_override.is_empty():
		return path_override
	return PATH if allow_switched() else DENY_PATH


## C-19: the file the HUMAN door reads. Not switched by C-19: PATH unless the env or a test seam names a slice (an explicit
## `NML_CORE_SLICE=deny` still selects the deny-list for both doors, as before). DS-109 makes this `live_path()`.
static func human_path() -> String:
	if path_override.is_empty() and OS.get_environment("NML_CORE_SLICE").to_lower() != "deny":
		return PATH
	return live_path()


## C-19: the startup line that names the slice in use (what `config()` prints when the live slice loads).
static func mode_line() -> String:
	var ai := live_path()
	var human := human_path()
	return "[CORE] shoot slice: AI door %s (%s), human door %s (%s)%s" % [
		_mode_of(ai), ai.get_file(), _mode_of(human), human.get_file(),
		"; the way back is NML_CORE_SLICE=allow" if ai == DENY_PATH else ""]


static func _mode_of(path: String) -> String:
	return "deny" if path == DENY_PATH else "allow"


## "Tough(3)" -> "Tough", "Fear (spell)" -> "Fear" (a rule entry is a string or a {"name": ...} dictionary).
static func rule_label(r) -> String:
	return RulesRegistry.base_rule_name(str((r as Dictionary).get("name", "")) if r is Dictionary else str(r))


## `gu`'s rule `label` is one the slice takes: listed in "allow", not listed in "deny"; no primitive = no.
static func _rule_taken(gu: GameUnit, label: String) -> bool:
	var c := config()
	if (c["inert"] as Dictionary).has(label):
		return true
	if (c["deny_names"] as Dictionary).has(label):
		return false
	var prims: Dictionary = c["primitives"]
	var allow: bool = c["mode"] == "allow"
	if allow and prims.is_empty():
		return false
	var entry: Dictionary = RulesRegistry.lookup(RulesRegistry.system_of_unit(gu), RulesRegistry.faction_of_unit(gu), label)
	if entry.is_empty() and bool(c["unmapped_inert"]):
		return true   # a name no map knows (an upgrade's own label): neither side reads it, the rules it grants are listed apart
	var p: Variant = entry.get("primitive")
	return p is String and prims.has(p) == allow


## Why the slice refuses `gu` - the labels the P4.D-3 census counts ("unit_rule:<name>", "attached", "non_opr",
## "weapon_rule:<name>"); [] = the core door takes it. `as_target`: a target needs no OPR profile (P4.D-13b).
static func refusals(gu: GameUnit, as_target := false) -> Array:
	var out: Array = []
	for r in gu.get_special_rules():
		if not _rule_taken(gu, rule_label(r)):
			out.append("unit_rule:" + rule_label(r))
	var c := config()
	if (gu.has_attached_heroes() or gu.is_attached()) and c["attached"] != (c["mode"] == "allow"):
		out.append("attached")
	# Deny mode takes a joined hero with its unit, so the hero's own unit and weapon rules must pass the list too (allow
	# mode refuses every attachment above; its labels stay as they were).
	if c["mode"] == "deny":
		# A joined unit whose own models are all dead is shot as its living hero. The core's lone-hero target exists from
		# EPOCH_83_LONE_HERO_TARGET (below it the core shoots the dead host at the host's Defense and says nothing), so a volley
		# at such a target under an older stamp (a replay, a pinned test) stays on the table; current games go to the core.
		if as_target and AiActRecorder.rules_epoch < AiActRecorder.EPOCH_83_LONE_HERO_TARGET and gu.get_alive_count() <= 0 \
				and gu.get_attached_heroes().any(func(h) -> bool: return h is GameUnit and (h as GameUnit).get_alive_count() > 0):
			out.append("lone_hero_target")
		for hero in gu.get_attached_heroes():
			for r in refusals(hero as GameUnit, true):
				if r != "attached" and not out.has(r):
					out.append(r)
	if not gu.source_data is OPRApiClient.OPRUnit:
		return out if as_target else out + ["non_opr"]
	for w in (gu.source_data as OPRApiClient.OPRUnit).weapons:
		for r in w.special_rules:
			if not _rule_taken(gu, rule_label(r)):
				out.append("weapon_rule:" + rule_label(r))
	return out


## C-18 (shadow only): `refusals` under the slice file at `path` (e.g. DENY_PATH) without switching the live slice.
static var _cache_by_path := {}


static func refusals_in(path: String, gu: GameUnit, as_target := false) -> Array:
	var live := [path_override, _loaded]
	path_override = path
	_loaded = _cache_by_path.get(path, {})
	var out := refusals(gu, as_target)
	_cache_by_path[path] = _loaded
	path_override = live[0]
	_loaded = live[1]
	return out


static func takes(gu: GameUnit, as_target := false) -> bool:
	return refusals(gu, as_target).is_empty()


## C-19: `refusals` / `takes` for the HUMAN door (`human_path`): the live slice when the human door reads it too, else the file
## the human door keeps until DS-109 (read through `refusals_in`, cached apart, the live slice untouched).
static func refusals_human(gu: GameUnit, as_target := false) -> Array:
	var path := human_path()
	return refusals(gu, as_target) if path == live_path() else refusals_in(path, gu, as_target)


static func takes_human(gu: GameUnit, as_target := false) -> bool:
	return refusals_human(gu, as_target).is_empty()


## P4.D-48: why the charge door refuses `gu` (charger, or the charged `as_target`), the same labels as `refusals`.
static func melee_refusals(gu: GameUnit, as_target := false) -> Array:
	return refusals_in(MELEE_PATH, gu, as_target)


## P4.D-37: `gu` carries a unit or weapon rule whose registry primitive is one of `primitives` (the slice's own lookup).
static func carries(gu: GameUnit, primitives: Array) -> bool:
	var labels: Array = gu.get_special_rules().map(rule_label)
	if gu.source_data is OPRApiClient.OPRUnit:
		for w in (gu.source_data as OPRApiClient.OPRUnit).weapons:
			labels.append_array(w.special_rules.map(rule_label))
	var system := RulesRegistry.system_of_unit(gu)
	var faction := RulesRegistry.faction_of_unit(gu)
	return labels.any(func(l) -> bool: return primitives.has(RulesRegistry.lookup(system, faction, l).get("primitive")))
