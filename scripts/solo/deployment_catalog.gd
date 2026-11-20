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
## The board the top-level `styles` map is stated for (the per-board entries live under `boards`).
const DEFAULT_BOARD_IN := Vector2(72, 48)

## Built-in fallback == today's one implicit deployment style, stated as data.
const FRONT_LINE: Dictionary = {
	"family": "standard",
	"zones": {
		"1": [[[-36, -24], [36, -24], [36, -12], [-36, -12]]],
		"2": [[[-36, 12], [36, 12], [36, 24], [-36, 24]]],
	},
}

static var _cache: Dictionary = {}
static var _boards: Dictionary = {}   # "48x48" -> {style id -> style}: the catalogue's per-board entries
static var _runtime: Dictionary = {}   # D14.4 styles registered at run time (valid on every board)
static var _loaded := false


static func reset_cache() -> void:
	_cache = {}
	_boards = {}
	_runtime = {}
	_loaded = false


static func _catalog() -> Dictionary:
	if not _loaded:
		_loaded = true
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string(CATALOG_PATH))
		if parsed is Dictionary and (parsed as Dictionary).get("styles") is Dictionary:
			_cache = (parsed as Dictionary)["styles"]
			var boards: Variant = (parsed as Dictionary).get("boards")
			_boards = boards if boards is Dictionary else {}
		else:
			push_warning("[DEPLOYMENTS] catalog missing/unparseable at %s — FRONT_LINE fallback only" % CATALOG_PATH)
			_cache = {}
	return _cache


## D14.4: a style that only exists at run time (VIP Escort's disc around the marker, whose centre is
## chosen at the table). Registered into the cache, so every consumer that asks `get_style(id)` finds it;
## `reset_cache()` forgets it.
static func register_style(id: String, style: Dictionary) -> void:
	_catalog()[id] = style
	_runtime[id] = style


## Catalogue board key in whole inches ("48x48"): the key deployment.rs `board_size_key` builds.
static func board_key(board_in: Vector2) -> String:
	return "%dx%d" % [roundi(board_in.x), roundi(board_in.y)]


## The styles DEFINED for a board, by the lookup deployment.rs `catalog_zones_for_board` does: `boards[key]`, and for
## 72 x 48 the top-level `styles`; plus the styles registered at run time. {} = none defined for this board.
static func styles_for_board(board_in: Vector2 = DEFAULT_BOARD_IN) -> Dictionary:
	_catalog()
	var key := board_key(board_in)
	var out: Dictionary = _cache.duplicate() if key == board_key(DEFAULT_BOARD_IN) else {}
	var per_board: Variant = _boards.get(key)
	if per_board is Dictionary:
		out.merge(per_board as Dictionary, true)
	out.merge(_runtime, true)
	return out


## A role-agnostic disc zone (both player keys, like the D4a styles) around `centre_in` (table inches).
static func disc_style(centre_in: Vector2, r_in: float) -> Dictionary:
	var zone := [{"disc": {"c": [centre_in.x, centre_in.y], "r_in": r_in}}]
	return {"name": "Disc around the marker", "family": "attack_defend", "zones": {"1": zone, "2": zone.duplicate(true)}}


## What the table offers on a board: its defined styles; a board the catalogue does not describe at all (a custom
## size) keeps today's behaviour, the top-level styles, instead of losing every style.
static func _offered(board_in: Vector2) -> Dictionary:
	var defined := styles_for_board(board_in)
	return defined if not defined.is_empty() else _catalog()


static func style_ids(board_in: Vector2 = DEFAULT_BOARD_IN) -> Array:
	var ids: Array = _offered(board_in).keys()
	ids.sort()
	return ids if not ids.is_empty() else ["front_line"]


## The deployment style for `id` on a board (default 72 x 48 = today's table); an id the board does not define
## returns that board's front_line (loudly), so a stale save or a typo'd env can never select a style that does
## not exist - and a 48 x 48 table never gets a 72 x 48 polygon.
static func get_style(id: String, board_in: Vector2 = DEFAULT_BOARD_IN) -> Dictionary:
	var c := _offered(board_in)
	if c.has(id):
		return c[id]
	if id != "front_line":
		push_warning("[DEPLOYMENTS] style id '%s' is not defined for board %s — falling back to front_line" % [id, board_key(board_in)])
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
		if poly is Dictionary:   # D4a: a disc primitive {"disc": {"c": [x, z], "r_in": r}}
			var d: Dictionary = (poly as Dictionary).get("disc", {})
			var c: Array = d.get("c", [0, 0])
			if p.distance_to(Vector2(c[0], c[1])) <= float(d.get("r_in", 0.0)):
				return true
			continue
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
static func zone_test(id: String, player: int, board_in: Vector2 = DEFAULT_BOARD_IN) -> Callable:
	var style := get_style(id, board_in)
	return func(p_m: Vector2) -> bool:
		return in_zone(style, player, p_m / IN2M)


## `player`'s zone as polygons in centered table inches, a disc approximated by `segments` points —
## what the overlay draws (the exact disc test stays in `in_zone`).
static func zone_polygons(style: Dictionary, player: int, segments: int = 48) -> Array:
	var out: Array = []
	var polys: Variant = (style.get("zones", {}) as Dictionary).get(str(player))
	if not (polys is Array):
		return out
	for poly in polys:
		var pts := PackedVector2Array()
		if poly is Dictionary:
			var d: Dictionary = (poly as Dictionary).get("disc", {})
			var c: Array = d.get("c", [0, 0])
			for i in segments:
				var a := TAU * float(i) / float(segments)
				pts.append(Vector2(c[0], c[1]) + Vector2(cos(a), sin(a)) * float(d.get("r_in", 0.0)))
		else:
			for xz in poly:
				pts.append(Vector2(xz[0], xz[1]))
		out.append(pts)
	return out
