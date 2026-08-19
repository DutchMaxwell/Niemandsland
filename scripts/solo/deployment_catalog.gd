class_name DeploymentCatalog
extends RefCounted
## Missions wave M2a — the deployment-style catalog (the six standard
## Face-Off deployment zones, stated as data). Reads the committed catalog
## (assets/solo/deployments.json); every reader falls back to the built-in
## FRONT_LINE entry when the file or the id is absent, so today's behaviour
## is byte-identical whenever data is missing — data refines, never breaks.
## M2a ships the model only; game/arena consumers arrive in later steps.

const CATALOG_PATH: String = "res://assets/solo/deployments.json"
const IN2M := 0.0254   # catalog polygons are centered table inches; the table is metres

## Built-in fallback == today's one implicit deployment style, stated as data.
const FRONT_LINE: Dictionary = {
	"family": "standard",
	"zones": {
		"1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
		"2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]],
	},
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
		if parsed is Dictionary and (parsed as Dictionary).get("styles") is Dictionary:
			_cache = (parsed as Dictionary)["styles"]
		else:
			push_warning("[DEPLOYMENTS] catalog missing/unparseable at %s — FRONT_LINE fallback only" % CATALOG_PATH)
			_cache = {}
	return _cache


static func style_ids() -> Array:
	var ids: Array = _catalog().keys()
	ids.sort()
	return ids if not ids.is_empty() else ["front_line"]


## The deployment style for `id`; unknown ids return FRONT_LINE (loudly), so
## a stale save or a typo'd env can never select a style that does not exist.
static func get_style(id: String) -> Dictionary:
	var c := _catalog()
	if c.has(id):
		return c[id]
	if id != "front_line":
		push_warning("[DEPLOYMENTS] unknown style id '%s' — falling back to front_line" % id)
	return c.get("front_line", FRONT_LINE)


## True when `p` (centered table inches) lands inside any polygon of
## `style`'s zone for `player`. A missing player key is simply false — no
## zone data, no claim.
static func in_zone(style: Dictionary, player: int, p: Vector2) -> bool:
	var zones: Dictionary = style.get("zones", {})
	var polys: Variant = zones.get(str(player))
	if not (polys is Array):
		return false
	for poly in polys:
		var pts := PackedVector2Array()
		for xz in poly:
			pts.append(Vector2(xz[0], xz[1]))
		if Geometry2D.is_point_in_polygon(p, pts):
			return true
	return false


## M2b — the zone as a WORLD-SPACE probe: Callable(Vector2 metres) -> bool
## over `player`'s polygons of style `id`. The deploy machinery treats
## "outside the zone" like blocking terrain, so the spot search polygon-
## checks every candidate base. Conversion to catalog inches happens here.
static func zone_test(id: String, player: int) -> Callable:
	var style := get_style(id)
	return func(p_m: Vector2) -> bool:
		return in_zone(style, player, p_m / IN2M)
