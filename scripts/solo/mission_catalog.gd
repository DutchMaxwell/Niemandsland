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


## M3 — AUTOMATIC marker placement (grill 2026-08-12 D2): resolves the
## catalog's placement mode into centered table-inch positions. 'alternate'
## (Duel) returns [] on purpose — the players' hand-placement flow stays.
## deploy_zone_centres asks the DEPLOYMENT style for its zones (centroid of
## each player's first polygon), so Breakthrough follows whatever zones the
## game actually uses — one source, no drift.
static func marker_positions(mission: Dictionary, deployment_style: Dictionary,
		table_w_in := 72.0, table_d_in := 48.0) -> Array:
	var mode := str((mission.get("markers", {}) as Dictionary).get("placement", "alternate"))
	match mode:
		"quarter_centres":
			return [Vector2(-table_w_in / 4.0, -table_d_in / 4.0),
				Vector2(table_w_in / 4.0, -table_d_in / 4.0),
				Vector2(-table_w_in / 4.0, table_d_in / 4.0),
				Vector2(table_w_in / 4.0, table_d_in / 4.0)]
		"deploy_zone_centres":
			var out: Array = []
			for pk in ["1", "2"]:
				var polys: Variant = (deployment_style.get("zones", {}) as Dictionary).get(pk)
				if polys is Array and not (polys as Array).is_empty():
					var c := Vector2.ZERO
					var n := 0
					for xz in (polys as Array)[0]:
						c += Vector2(float(xz[0]), float(xz[1]))
						n += 1
					if n > 0:
						out.append(c / float(n))
			return out
		"table_centre":
			return [Vector2.ZERO]
	return []   # 'alternate' and unknown modes: hand placement flow
