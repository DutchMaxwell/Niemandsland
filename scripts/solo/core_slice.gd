class_name CoreSlice
extends RefCounted
## One core P4.D-6: WHICH units the core door takes at the shooting door. The slice is DATA (assets/solo/core_slice_allow.json):
## a MODE and a set of GROUPS, so the predicate reads either way. Every unit rule and every weapon rule is resolved through
## `RulesRegistry.lookup(system, faction, name)` to a primitive; the groups LIST primitives (and the group "attached_heroes"
## lists attachments):
##   mode "allow": a unit is taken when every rule it carries is LISTED (allow by group). With no group, nothing with a rule.
##   mode "deny":  a unit is taken when no rule it carries is listed (the groups are the deny-list; allow by default).
## In both modes a rule the registry has no primitive for (unknown name, unautomated entry) is refused, and a shooter with no
## OPR profile never passes (a target needs none: `as_target`). The shipped file is mode "allow" with NO group: exactly the old
## `CoreActivation.is_plain`. Melee is not part of it: the human door's Charge selector stays refused in `human_shoot`.
## Each group is `{"primitives": [...], "step": "P4.D-n", "golden": "<fixture>", "parity": "<scenario>"}`.

const PATH := "res://assets/solo/core_slice_allow.json"
const SCHEMA := "nml-core-slice-v1"
const MODES := ["allow", "deny"]

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
	_loaded = {"mode": "allow", "primitives": {}, "attached": false}
	var path := path_override if not path_override.is_empty() else PATH
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else null
	if not (data is Dictionary) or str(data.get("schema", "")) != SCHEMA or str(data.get("door", "")) != "shoot" \
			or not MODES.has(str(data.get("mode", "allow"))):
		push_error("CoreSlice: %s is missing or not a %s file for the shoot door - the slice is empty" % [path, SCHEMA])
		return _loaded
	_loaded["mode"] = str(data.get("mode", "allow"))
	for g in data.get("groups", {}):
		for p in data["groups"][g].get("primitives", []):
			_loaded["primitives"][str(p)] = str(g)
	_loaded["attached"] = (data.get("groups", {}) as Dictionary).has("attached_heroes")
	return _loaded


## "Tough(3)" -> "Tough", "Fear (spell)" -> "Fear" (a rule entry is a string or a {"name": ...} dictionary).
static func rule_label(r) -> String:
	return RulesRegistry.base_rule_name(str((r as Dictionary).get("name", "")) if r is Dictionary else str(r))


## `gu`'s rule `label` is one the slice takes: listed in "allow", not listed in "deny"; no primitive = no.
static func _rule_taken(gu: GameUnit, label: String) -> bool:
	var c := config()
	var prims: Dictionary = c["primitives"]
	var allow: bool = c["mode"] == "allow"
	if allow and prims.is_empty():
		return false
	var p: Variant = RulesRegistry.lookup(RulesRegistry.system_of_unit(gu), RulesRegistry.faction_of_unit(gu), label).get("primitive")
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
	if not gu.source_data is OPRApiClient.OPRUnit:
		return out if as_target else out + ["non_opr"]
	for w in (gu.source_data as OPRApiClient.OPRUnit).weapons:
		for r in w.special_rules:
			if not _rule_taken(gu, rule_label(r)):
				out.append("weapon_rule:" + rule_label(r))
	return out


static func takes(gu: GameUnit, as_target := false) -> bool:
	return refusals(gu, as_target).is_empty()
