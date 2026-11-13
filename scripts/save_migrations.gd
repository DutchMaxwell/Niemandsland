class_name SaveMigrations
extends RefCounted
## Versioned .nml save migration (goal 002). One place decides whether a save can load: the current
## version passes through, SUPPORTED older versions migrate step by step up the chain, anything older
## (pre-alpha dev formats) or NEWER than this build fails with a clear message instead of loading into
## silent data damage. Rule (documented in ARCHITECTURE): whoever bumps SaveManager.SAVE_VERSION ships
## the matching migration step + a fixture test in the same change.
##
## History (git): 1.0 base (12/2025) · 1.1 GameUnits · 1.2 map/markers · 1.3 walls/objects ·
## 1.4 regiments (2026-06-13) · 1.5 sandbox terrain (2026-06-16, the only format the public alpha ever
## shipped) · 1.6 schema checkpoint (goal 002 — normalises the post-1.5 additions that rode in without a
## bump: per-model base size, dead-model parking, objective owners, spell lists).
##
## Per the maintainer's lock (F3): supported = everything since the alpha launch → 1.4 and up.

## Oldest version the chain can lift to current. Pre-alpha formats (< 1.4) are refused with a message.
const OLDEST_SUPPORTED := "1.4"


## Migrate `state` (parsed .nml root) to SaveManager.SAVE_VERSION.
## Returns {ok: bool, state: Dictionary, error: String, migrated_from: String}.
static func migrate(state: Dictionary) -> Dictionary:
	var version := str(state.get("version", ""))
	var current: String = SaveManager.SAVE_VERSION
	if version == current:
		return {"ok": true, "state": state, "error": "", "migrated_from": ""}
	if version.is_empty():
		return _fail("This file carries no save version — it does not look like a Niemandsland save.")
	if not _is_known_shape(version):
		return _fail("Unrecognised save version \"%s\"." % version)
	if _cmp(version, current) > 0:
		return _fail("This save was created by a NEWER game version (save %s, this build reads %s). Update the game to load it." % [version, current])
	if _cmp(version, OLDEST_SUPPORTED) < 0:
		return _fail("This save uses the pre-alpha format %s, which is no longer loadable (supported: %s and newer)." % [version, OLDEST_SUPPORTED])
	# Walk the chain one step at a time until we reach the current version.
	var migrated := state.duplicate(true)
	var from := version
	var guard := 0
	while from != current and guard < 16:
		guard += 1
		match from:
			"1.4":
				migrated = _migrate_1_4_to_1_5(migrated)
				from = "1.5"
			"1.5":
				migrated = _migrate_1_5_to_1_6(migrated)
				from = "1.6"
			"1.6":
				migrated = _migrate_1_6_to_1_7(migrated)
				from = "1.7"
			_:
				return _fail("No migration step from save version \"%s\" — this is a bug, please report it." % from)
	migrated["version"] = current
	return {"ok": true, "state": migrated, "error": "", "migrated_from": version}


## Whether `state` was played under the rules this build plays (`build_rules`, e.g. "3.6.0"). Only
## major.minor counts: 3.6.0 and 3.6.2 are the same rules. Returns "" when it may load, else the
## plain-words reason it cannot. A save without the "rules_version" key was made before 0.3.15.
static func rules_version_error(state: Dictionary, build_rules: String) -> String:
	var build := OPRApiClient._major_minor(build_rules)
	var saved := str(state.get("rules_version", ""))
	if saved.is_empty():
		return "This save carries no rules version (made before 0.3.15); this build plays rules %s and cannot load it." % build
	var saved_mm := OPRApiClient._major_minor(saved)
	if saved_mm != build:
		return "This save was made with rules %s; this build plays rules %s and cannot load it." % [
			saved if saved_mm.is_empty() else saved_mm, build]
	return ""


## Whether `state` (a migrated save) has the section shapes the loader's typed restore steps need. load_game asks
## BEFORE it clears the table: a damaged or wrongly generated file is refused with the current battle still
## standing, instead of clearing it (on a host: for every guest) and then failing halfway through the rebuild.
## Returns "" when it may load, else the plain-words reason it cannot.
static func payload_error(state: Dictionary) -> String:
	for key in ["table", "objects", "game_units"]:
		if not state.has(key):
			return _damaged("it has no \"%s\" section" % key)
	for key in ["table", "game_state", "army_names", "rule_descriptions", "player_spells"]:
		if state.has(key) and not state[key] is Dictionary:
			return _damaged("its \"%s\" section is not a record" % key)
	for key in ["objects", "game_units"]:
		if not state[key] is Array:
			return _damaged("its \"%s\" section is not a list" % key)
	for obj: Variant in state["objects"]:
		if obj is Dictionary and not _has_vec3_pose(obj):
			return _damaged("an object has a broken position or rotation")
	for unit: Variant in state["game_units"]:
		if not unit is Dictionary:
			continue
		var regiment: Variant = unit.get("regiment")
		if not (unit.get("models", []) is Array and unit.get("unit_properties", {}) is Dictionary
				and unit.get("model_positions", []) is Array and (regiment == null or regiment is Dictionary)):
			return _damaged("a unit has a broken model list")
		for model: Variant in unit.get("models", []):
			if not model is Dictionary:
				return _damaged("a unit has a broken model list")
		for pose: Variant in unit.get("model_positions", []):
			if pose != null and not (pose is Dictionary and _has_vec3_pose(pose)):
				return _damaged("a model has a broken position or rotation")
	return ""


static func _damaged(why: String) -> String:
	return "This save file is damaged (%s), so it was not loaded. The table was left as it was." % why


## A position / rotation the loader can read: absent, or a list whose first three entries are numbers (a
## shorter list reads as the origin).
static func _has_vec3_pose(entry: Dictionary) -> bool:
	for key in ["position", "rotation"]:
		var v: Variant = entry.get(key, [])
		if not v is Array:
			return false
		if (v as Array).size() >= 3:
			for i in 3:
				if not (v[i] is float or v[i] is int):
					return false
	return true


# === Steps (each lifts exactly one version) ===

## 1.4 → 1.5: sandbox terrain objects were ADDED in 1.5 — a 1.4 save simply has none. Nothing to
## transform; the step exists so the chain is explicit.
static func _migrate_1_4_to_1_5(state: Dictionary) -> Dictionary:
	return state


## 1.5 → 1.6: the schema checkpoint. Several fields shipped after 1.5 without a bump, so real "1.5"
## files vary; this step normalises them to the canonical 1.6 shape (all covered by reader defaults —
## made explicit here so 1.6 is a trustworthy schema marker):
## objective owners default to neutral, army_names/player_spells/rule_descriptions default to empty.
static func _migrate_1_5_to_1_6(state: Dictionary) -> Dictionary:
	if not state.has("rule_descriptions"):
		state["rule_descriptions"] = {}
	if not state.has("player_spells"):
		state["player_spells"] = {}
	if not state.has("army_names"):
		state["army_names"] = {}
	var table: Variant = state.get("table")
	if table is Dictionary and table.has("mission_objectives"):
		for obj in table["mission_objectives"]:
			if obj is Dictionary and not obj.has("owner"):
				obj["owner"] = 0
	return state


# === Version maths ===

## "1.5" → [1, 5]; tolerant of stray whitespace. Non-numeric parts land as 0.
static func _parts(v: String) -> Array:
	var out: Array = []
	for p in v.strip_edges().split("."):
		out.append(int(p))
	return out


## -1 / 0 / +1 for a < b / a == b / a > b (numeric, per segment; missing segments count as 0).
static func _cmp(a: String, b: String) -> int:
	var pa := _parts(a)
	var pb := _parts(b)
	for i in range(maxi(pa.size(), pb.size())):
		var xa: int = pa[i] if i < pa.size() else 0
		var xb: int = pb[i] if i < pb.size() else 0
		if xa != xb:
			return -1 if xa < xb else 1
	return 0


## A plausible version string: digits and dots only (guards against garbage in the field).
static func _is_known_shape(v: String) -> bool:
	if v.is_empty():
		return false
	for c in v:
		if not (c == "." or (c >= "0" and c <= "9")):
			return false
	return true


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "state": {}, "error": message, "migrated_from": ""}


## 1.6 → 1.7: Transport(X) embark state was ADDED in 1.7 (NML-105) — a 1.6 save simply has no
## embarked units (the keys live inside unit_properties and default to absent). Nothing to
## transform; the step exists so the chain is explicit.
static func _migrate_1_6_to_1_7(state: Dictionary) -> Dictionary:
	return state
