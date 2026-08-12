class_name MissionCatalog
extends RefCounted
## Missions wave M1 — the data catalog behind mission selection AND ladder
## rotation (one source, both consumers). Reads the committed catalog
## (assets/solo/missions.json); every reader falls back to the built-in
## DUEL entry when the file or the id is absent, so today's behaviour is
## byte-identical whenever data is missing — data refines, never breaks.
## M1 ships the model only; game/arena consumers arrive in later steps.

const CATALOG_PATH: String = "res://assets/solo/missions.json"

## Built-in fallback == today's one implicit mission, stated as data.
const DUEL: Dictionary = {
	"family": "face_off", "rounds": 4, "scoring": "end",
	"deployment": "front_line",
	"markers": {"count": "d3+2", "placement": "alternate",
		"min_gap_in": 9, "outside_zones_in": 9},
}

static var _cache: Dictionary = {}
static var _loaded := false


static func reset_cache() -> void:
	_cache = {}
	_loaded = false


static func _catalog() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary and (parsed as Dictionary).get("missions") is Dictionary:
			_cache = (parsed as Dictionary)["missions"]
		else:
			push_warning("[MISSIONS] catalog missing/unparseable at %s — DUEL fallback only" % CATALOG_PATH)
			_cache = {}
	return _cache


static func mission_ids() -> Array:
	var ids: Array = _catalog().keys()
	ids.sort()
	return ids if not ids.is_empty() else ["duel"]


## The mission definition for `id`; unknown ids return DUEL (loudly), so a
## stale save or a typo'd env can never select a mission that does not exist.
static func get_mission(id: String) -> Dictionary:
	var c := _catalog()
	if c.has(id):
		return c[id]
	if id != "duel":
		push_warning("[MISSIONS] unknown mission id '%s' — falling back to duel" % id)
	return c.get("duel", DUEL)


## Resolve a marker count spec ("d3+2" or int) into a concrete count using
## the caller's rng (arena passes its seeded rng => deterministic per seed).
static func marker_count(mission: Dictionary, rng: RandomNumberGenerator) -> int:
	var spec: Variant = (mission.get("markers", {}) as Dictionary).get("count", "d3+2")
	if spec is float or spec is int:
		return maxi(1, int(spec))
	var s := str(spec).strip_edges().to_lower()
	if s.begins_with("d3+") and s.substr(3).is_valid_int():
		return rng.randi_range(1, 3) + int(s.substr(3))
	push_warning("[MISSIONS] bad marker count spec '%s' — using d3+2" % s)
	return rng.randi_range(1, 3) + 2
