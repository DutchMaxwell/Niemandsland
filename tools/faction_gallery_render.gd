extends SceneTree
## QA tool: a FULL-FACTION in-game render gallery — the FACTION_PLAYBOOK "in-game screenshot pass",
## industrialized. It enumerates EVERY manifest key of a faction (base units + all loadout variants),
## spawns each through the REAL model pipeline (ModelLibrary download + OPRArmyManager fit / grounding /
## oval-orientation — nothing re-implemented), camera-fits a labeled tile per model, batches the tiles
## into contact-sheet montages grouped by unit family, and emits an automated anomaly report.
##
## It drives the SAME code the client uses at spawn time (opr_army_manager.gd `_create_unit_model`):
##   ModelLibrary.ensure_model          -> resolve + download the CDN GLB (honours NML_MANIFEST_URL)
##   OPRArmyManager._get_model_aabb      -> composed AABB (scale carried on any ancestor node)
##   OPRArmyManager._get_body_aabb       -> the named `body` box (contract v1.2, height + footprint cap)
##   OPRArmyManager._compute_model_fit   -> scale + y_offset (rider-constant fit, footprint cap, fit_scale)
##   OPRArmyManager._align_to_oval_long_axis  -> oval facing (manifest `long_axis` marker wins)
## Base dims come from the Army Forge book (embedded per-faction data table below) with the manifest
## `base_mm` override winning where present (precedence manifest > book), exactly like
## `_apply_manifest_base_overrides`. Per-entry `fit_scale` + `long_axis` are read live from the library.
##
## Automated anomaly flags (collected into <out_dir>/anomalies.md, one line per flag with numbers):
##   (a) HEIGHT  — rendered total/rider height vs a class band derived from base+Tough AND the fleet
##                 median of the plain-trooper group (catches wrong-scale bakes, e.g. the snake-regression).
##   (b) GROUND  — the model's lowest point sits well below the table (sunk / below-feet junk) or floats.
##   (c) OVERHANG— the fitted footprint grossly exceeds the base (oval facing/overhang, wide-hull creep).
##   (d) LOADFAIL— the CDN blob failed to resolve / instantiate (missing or broken).
## KNOWN in-rework families (snake riders + variants) are rendered + tagged "in rework", never alarmed.
##
## Usage (needs a REAL renderer — a virtual/headless Wayland compositor; NOT Godot's --headless):
##   NML_MANIFEST_URL=https://assets.niemandsland.xyz/model_manifest.mummified_pilot.json \
##   gamescope --backend headless -W 1280 -H 720 -- \
##     flatpak run --filesystem=home --socket=wayland --share=network org.godotengine.Godot \
##       --path <project> --rendering-driver vulkan -s res://tools/faction_gallery_render.gd -- \
##       <out_dir> [max_keys=0(all)] [faction=mummified_undead]

# === Constants ===

const TILE_PX: int = 512
## Caption bar height (px), overlaid on the bottom of each tile.
const CAP_BAR_PX: int = 100
const COLS: int = 5
## Target tiles per contact sheet (a family larger than this splits across consecutive sheets).
const SHEET_CAP: int = 24
## Frames to let the renderer settle (material + texture upload) before a capture.
const SETTLE_FRAMES: int = 12
## Frames to wait for the manifest override to load before giving up.
const MANIFEST_WAIT_FRAMES: int = 1200

const BG_COLOR: Color = Color(0.11, 0.12, 0.15)
const SHEET_BG: Color = Color(0.07, 0.08, 0.10, 1.0)
const GROUND_COLOR: Color = Color(0.26, 0.25, 0.24)
const BASE_COLOR: Color = Color(0.24, 0.34, 0.52)
const CAP_BG: Color = Color(0.0, 0.0, 0.0, 0.62)
const CAP_FG: Color = Color(0.95, 0.96, 0.98)

## Flag → border colour (priority high→low when a tile has several).
const FLAG_LOADFAIL: Color = Color(0.95, 0.15, 0.15)
const FLAG_HEIGHT: Color = Color(0.98, 0.45, 0.10)
const FLAG_OVERHANG: Color = Color(0.98, 0.85, 0.15)
const FLAG_GROUND: Color = Color(0.20, 0.75, 0.98)
const FLAG_REWORK: Color = Color(0.65, 0.45, 0.95)

# === Anomaly thresholds ===

const GROUND_SUNK_M: float = -0.005      # lowest point >5mm below the table plane → below-feet junk / sunk
const GROUND_FLOAT_M: float = 0.008      # lowest point >8mm above the base top → floating
const OVERHANG_LONG_RATIO: float = 2.0   # fitted long footprint / base long side
const OVERHANG_SHORT_RATIO: float = 2.5  # fitted short footprint / base short side (oval)
const RIDER_BODY_LO_MM: float = 20.0     # a mounted rider body should land on the 28mm trooper target
const RIDER_BODY_HI_MM: float = 42.0
const TROOPER_FLEET_DEV: float = 0.28    # ±28% off the plain-trooper fleet median → wrong-scale bake
## Height is judged against the fit's OWN Tough-derived intended target (not a fixed band), so a
## legitimately tall titan is not flagged. The JUDGED box is the one that DRIVES the fit: the `body`
## box when the GLB carries one (contract v1.2 — a banner/crest/spear legitimately extends the total
## above an on-target body), else the combined box. Taller-than-intended = a measurement bug
## (impossible via the min() fit); far-shorter-than-intended = footprint-slam / bad AABB.
const HEIGHT_OVER_TARGET: float = 1.15   # judged box / intended target above this → anomaly (too tall)
const HEIGHT_UNDER_TARGET: float = 0.40  # judged box / intended target below this → anomaly (slammed short)
const HEIGHT_ABS_MIN_MM: float = 8.0     # absolute degenerate floor
const HEIGHT_ABS_MAX_MM: float = 230.0   # absolute implausible ceiling
## With a body node the composed total may exceed the body (banner poles etc.) — but a total ABOVE this
## multiple of the body is fragment-shaped (the god-titan-crown class: stray geometry far above the
## model), worth a human glance.
const PARTS_DOMINANCE_MAX: float = 2.0

# === Per-faction Army Forge base data ===
# base-name (manifest key before '#', HYPHENS FOLDED TO SPACES like ModelLibrary._normalize_unit)
# -> [is_oval, long_mm, short_mm, tough]. round: long==short. The manifest `base_mm` override still
# wins over this at runtime (precedence manifest > book), so entries here are the book's recommendation.
const BASE_TABLE: Dictionary = {
	"royal champion": [false, 25, 25, 3],
	"skeleton leader": [false, 25, 25, 3],
	"skeleton warriors": [false, 25, 25, 0],
	"mummies": [false, 25, 25, 0],
	"royal guard": [false, 25, 25, 0],
	"skeleton archers": [false, 25, 25, 0],
	"guardian statues": [false, 40, 40, 3],
	"skeleton horsemen": [true, 60, 35, 0],
	"beast riders": [true, 60, 35, 0],
	"great snakes": [true, 90, 52, 3],
	"snake riders": [true, 90, 52, 3],
	"snakemen": [true, 75, 46, 3],
	"hunting beasts": [true, 60, 35, 0],
	"scarab swarms": [false, 40, 40, 3],
	"vultures": [false, 40, 40, 3],
	"great scorpion": [false, 60, 60, 6],
	"death casket": [true, 75, 46, 6],
	"skeleton giant": [false, 60, 60, 12],
	"war sphinx": [true, 120, 92, 12],
	"sphinx champion": [true, 120, 92, 12],
	"giant god statue": [false, 60, 60, 12],
	"skeleton chariot": [true, 120, 92, 6],
	"skull catapult": [true, 120, 92, 3],
	"desert titan": [false, 120, 120, 24],
	"god titan": [false, 120, 120, 24],
	"rammit den geddul": [false, 25, 25, 3],
	# manifest-only components (mounts / alt chariot) — sensible bases so their tiles frame + flag right
	"royal chariot": [true, 120, 92, 6],
	"skeletal steed": [true, 60, 35, 3],
	"skeleton beast": [true, 90, 52, 6],
	"war sphinx mount": [true, 120, 92, 12],
}
## Hero families whose loadout can add a MOUNT (→ is_mount + the mount's base drives the tile).
const HERO_FAMILIES: Array = ["royal champion", "skeleton leader"]
## mount-token (a '+'-separated variant slug part) -> [is_oval, long_mm, short_mm, tough].
const MOUNT_TABLE: Dictionary = {
	"steed": [true, 60, 35, 3],
	"snake": [true, 90, 52, 3],
	"sphinx": [true, 120, 92, 12],
	"beast": [true, 60, 35, 3],
	"flyingbeast": [true, 60, 35, 3],
	"chariot": [true, 120, 92, 6],
}
## Families flagged KNOWN-in-rework (rendered + tagged, never alarmed).
const REWORK_FAMILIES: Array = ["snake riders"]

var _lib: ModelLibrary = null
var _mgr: OPRArmyManager = null
var _faction: String = "mummified_undead"
var _rows: Array = []   # per key: Dictionary of measurements + flags + tile Image


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("Usage: -s res://tools/faction_gallery_render.gd -- <out_dir> [max_keys] [faction]")
		quit(1)
		return
	var out_dir: String = args[0]
	var max_keys: int = int(args[1]) if args.size() > 1 else 0
	_faction = (args[2] if args.size() > 2 else "mummified_undead").strip_edges().to_lower()
	DirAccess.make_dir_recursive_absolute(out_dir)

	_lib = ModelLibrary.new()
	get_root().add_child(_lib)   # _ready(): builds the downloader + honours NML_MANIFEST_URL
	if not await _await_manifest():
		push_error("faction_gallery_render: manifest never loaded for faction %s" % _faction)
		quit(1)
		return
	_mgr = OPRArmyManager.new()   # methods only; never entered into the tree (no autoloads needed)

	var keys: Array = _enumerate_keys()
	if keys.is_empty():
		push_error("faction_gallery_render: no manifest keys for %s/" % _faction)
		quit(1)
		return
	if max_keys > 0 and keys.size() > max_keys:
		keys = _coverage_subset(keys, max_keys)
	print("faction_gallery_render: %d keys to render for %s (out_dir=%s)" % [keys.size(), _faction, out_dir])

	var idx: int = 0
	for key in keys:
		idx += 1
		print("[%3d/%3d] %s" % [idx, keys.size(), key])
		var row: Dictionary = await _process_key(key)
		_rows.append(row)
		_mgr._scene_cache.clear()   # bound memory: one composed GLB parsed at a time

	_compute_anomalies()
	_build_sheets(out_dir)
	_write_report(out_dir)
	print("faction_gallery_render: DONE — %d tiles, out_dir=%s" % [_rows.size(), out_dir])
	_mgr.free()
	quit(0)


# === Manifest bootstrap ===

func _await_manifest() -> bool:
	# A cheap, faction-agnostic sentinel: the library has ANY key under "<faction>/".
	for _i in range(MANIFEST_WAIT_FRAMES):
		if _has_any_faction_key():
			print("faction_gallery_render: manifest loaded (%d total keys)" % _lib._models.size())
			return true
		await process_frame
	return _has_any_faction_key()


func _has_any_faction_key() -> bool:
	var prefix: String = _faction + "/"
	for k in _lib._models:
		if str(k).begins_with(prefix):
			return true
	return false


## All manifest keys for the faction (unit-name part after the '/'), sorted for stable family grouping.
func _enumerate_keys() -> Array:
	var prefix: String = _faction + "/"
	var out: Array = []
	for k in _lib._models:
		var s: String = str(k)
		if s.begins_with(prefix):
			out.append(s.substr(prefix.length()))
	out.sort()
	return out


## Time-box coverage: keep every base unit + the FIRST variant of each family, then pad with the rest
## in order until the budget is hit — so a partial run still spans the whole roster.
func _coverage_subset(keys: Array, budget: int) -> Array:
	var by_family: Dictionary = {}
	for k in keys:
		var fam: String = str(k).split("#", true, 1)[0]
		if not by_family.has(fam):
			by_family[fam] = []
		by_family[fam].append(k)
	var primary: Array = []
	var rest: Array = []
	for fam in by_family:
		var members: Array = by_family[fam]
		primary.append(members[0])                 # base (or first) of the family
		if members.size() > 1:
			primary.append(members[1])             # one variant
			for i in range(2, members.size()):
				rest.append(members[i])
	var picked: Array = primary.slice(0, budget)
	for k in rest:
		if picked.size() >= budget:
			break
		picked.append(k)
	picked.sort()
	return picked


# === Per-key spawn + measure + tile render ===

## Resolves a key's base spec: family base (book) → mount-swap for hero+mount variants → manifest
## `base_mm` override (wins). Returns { oval, long_mm, short_mm, tough, is_mount, family }.
func _resolve_spec(key: String) -> Dictionary:
	var parts: PackedStringArray = key.split("#", true, 1)
	var family: String = _fold(parts[0])
	var suffix: String = parts[1] if parts.size() > 1 else ""
	var tokens: PackedStringArray = suffix.split("+", false)

	var spec: Array = BASE_TABLE.get(family, [false, 25, 25, 0])
	var is_mount: bool = false
	if family in HERO_FAMILIES:
		for t in tokens:
			var tok: String = str(t).strip_edges().to_lower()
			if MOUNT_TABLE.has(tok):
				spec = MOUNT_TABLE[tok]
				is_mount = true
				break

	var oval: bool = bool(spec[0])
	var long_mm: int = int(spec[1])
	var short_mm: int = int(spec[2])
	var tough: int = int(spec[3])

	# Manifest base override wins (precedence manifest > book), mirroring _apply_manifest_base_overrides.
	var ovr: Dictionary = _lib.base_override_mm(_faction, key)
	var rv: Variant = ovr.get("round", "")
	if rv is int or rv is float or (rv is String and (rv as String) != "" and (rv as String).to_lower() != "none"):
		var parsed: Array = _parse_base(rv)
		oval = bool(parsed[0])
		long_mm = int(parsed[1])
		short_mm = int(parsed[2])

	return {"oval": oval, "long_mm": long_mm, "short_mm": short_mm, "tough": tough,
		"is_mount": is_mount, "family": family}


func _process_key(key: String) -> Dictionary:
	var spec: Dictionary = _resolve_spec(key)
	var family: String = spec["family"]
	var in_rework: bool = family in REWORK_FAMILIES
	var size_class: String = str(_lib._models.get(_faction + "/" + key, {}).get("ctex", {}).get("size_class", ""))
	var fit_scale: float = _lib.fit_scale(_faction, key)
	var axis_override: String = _lib.long_axis_override(_faction, key)
	var row: Dictionary = {
		"key": key, "family": family, "spec": spec, "size_class": size_class,
		"fit_scale": fit_scale, "in_rework": in_rework, "flags": [], "notes": [],
		"loadfail": false, "img": null,
	}

	var path: String = await _lib.ensure_model(_faction, key)
	if path.is_empty():
		row["loadfail"] = true
		row["notes"].append("blob did not resolve/download")
		row["img"] = await _render_fail_tile(key, "LOAD FAIL — no blob")
		return row
	var glb: Node3D = _mgr._instantiate_model(path)
	if glb == null:
		row["loadfail"] = true
		row["notes"].append("GLB failed to instantiate (%s)" % path.get_file())
		row["img"] = await _render_fail_tile(key, "LOAD FAIL — bad GLB")
		return row

	var aabb: AABB = _mgr._get_model_aabb(glb)
	var body: AABB = _mgr._get_body_aabb(glb)
	var has_body: bool = body.size.y > 0.0
	var body_elevated: bool = has_body \
		and (body.position.y - aabb.position.y) >= body.size.y * 0.25
	var rider_mode: bool = has_body and (bool(spec["is_mount"]) or body_elevated)

	var fit: Dictionary = _mgr._compute_model_fit(aabb, int(spec["long_mm"]), int(spec["tough"]), 0.0,
		int(spec["short_mm"]), false, body, bool(spec["is_mount"]), fit_scale)
	var scale: float = float(fit["scale"])
	var y_offset: float = float(fit["y_offset"])

	# Measurements (mm / m). combined_min_world: the whole model's lowest point in world space; the
	# base top is +0.003. total_h = whole model height; body_h = the rider/body box height.
	row["scale"] = scale
	row["total_h_mm"] = aabb.size.y * scale * 1000.0
	row["body_h_mm"] = (body.size.y * scale * 1000.0) if has_body else row["total_h_mm"]
	row["combined_min_world_m"] = y_offset + aabb.position.y * scale
	row["foot_long_mm"] = max(aabb.size.x, aabb.size.z) * scale * 1000.0
	row["foot_short_mm"] = min(aabb.size.x, aabb.size.z) * scale * 1000.0
	row["has_body"] = has_body
	row["rider_mode"] = rider_mode
	row["klass"] = _classify(spec, rider_mode)
	# The fit's OWN intended height target (Tough-derived): rider → the 28mm trooper anatomy; else the
	# base-long height target scaled by Tough, times the manifest fit_scale. Actual is judged against this.
	if rider_mode:
		row["target_mm"] = OPRArmyManager._height_target_mm(OPRArmyManager.RIDER_ANATOMY_BASE_MM)
	else:
		row["target_mm"] = OPRArmyManager._height_target_mm(int(spec["long_mm"])) \
			* _mgr._calculate_model_scale(int(spec["tough"])) * fit_scale
	row["is_trooper"] = (not bool(spec["oval"])) and int(spec["long_mm"]) <= 30 \
		and int(spec["tough"]) <= 1 and not rider_mode

	var cap2: String = "%.0f mm · %s" % [float(row["total_h_mm"]), _base_str(spec)]
	if rider_mode:
		cap2 += " · body %.0f" % float(row["body_h_mm"])
	if in_rework:
		cap2 += "  [REWORK]"
	row["img"] = await _render_model_tile(glb, spec, aabb, scale, y_offset, axis_override, key, cap2)
	return row


## Classifies a model for the height band: rider (mounted / composed rider), titan, large, cavalry,
## infantry — from the fit inputs + Tough (not the raw manifest size_class, which lumps giants with troops).
func _classify(spec: Dictionary, rider_mode: bool) -> String:
	if rider_mode:
		return "rider"
	var t: int = int(spec["tough"])
	var lng: int = int(spec["long_mm"])
	if t >= 12 or lng >= 110:
		return "titan"
	if t >= 6 or lng >= 60:
		return "large"
	if bool(spec["oval"]) or lng >= 45:
		return "cavalry"
	return "infantry"


# === Tile rendering (one SubViewport per model: 3D model + base, 2D caption overlay) ===

func _render_model_tile(glb: Node3D, spec: Dictionary, aabb: AABB, scale: float,
		y_offset: float, axis_override: String, key: String, caption2: String) -> Image:
	var vp: SubViewport = _new_viewport()
	var world := Node3D.new()
	vp.add_child(world)
	_add_environment(world)

	var unit := Node3D.new()
	world.add_child(unit)
	_add_base(unit, spec)

	glb.scale = Vector3(scale, scale, scale)
	glb.position.y = y_offset
	var oval: bool = bool(spec["oval"])
	_mgr._align_to_oval_long_axis(glb, aabb, oval,
		float(spec["short_mm"]) * 0.001, float(spec["long_mm"]) * 0.001, false, axis_override)
	_mgr._brighten_trellis_materials(glb)
	unit.add_child(glb)

	var top_m: float = y_offset + (aabb.position.y + aabb.size.y) * scale
	var base_long_m: float = float(spec["long_mm"]) * 0.001
	var foot_long_m: float = max(aabb.size.x, aabb.size.z) * scale
	var extent: float = maxf(maxf(top_m, base_long_m), foot_long_m)
	extent = maxf(extent, 0.02)
	var center := Vector3(0.0, top_m * 0.5 + 0.004, 0.0)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = extent * 1.55
	cam.near = 0.001
	cam.far = 100.0
	var dir: Vector3 = Vector3(0.5, 0.42, 1.0).normalized()
	world.add_child(cam)
	cam.look_at_from_position(center + dir * maxf(1.5, extent * 6.0), center, Vector3.UP)
	cam.make_current()

	_add_caption(vp, key, caption2)
	return await _capture(vp)


func _render_fail_tile(key: String, msg: String) -> Image:
	var vp: SubViewport = _new_viewport()
	var cr := ColorRect.new()
	cr.color = Color(0.32, 0.06, 0.06)
	cr.size = Vector2(TILE_PX, TILE_PX)
	vp.add_child(cr)
	_add_caption(vp, key, msg)
	return await _capture(vp)


func _new_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = Vector2i(TILE_PX, TILE_PX)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	return vp


func _add_environment(world: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 1.15
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 32.0, 0.0)
	sun.light_energy = 1.5
	world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, -120.0, 0.0)
	fill.light_energy = 0.5
	world.add_child(fill)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.0, 3.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = GROUND_COLOR
	gmat.roughness = 1.0
	ground.material_override = gmat
	world.add_child(ground)


func _add_base(unit: Node3D, spec: Dictionary) -> void:
	var base := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.height = 0.003
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	base.mesh = mesh
	if bool(spec["oval"]):
		base.scale = Vector3(float(spec["short_mm"]) * 0.001, 1.0, float(spec["long_mm"]) * 0.001)
	else:
		var d: float = float(spec["long_mm"]) * 0.001
		base.scale = Vector3(d, 1.0, d)
	base.position.y = 0.0015
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BASE_COLOR
	mat.roughness = 0.7
	base.material_override = mat
	unit.add_child(base)


## A 2D caption bar (Control children of the SubViewport draw over the 3D). Filled just before capture
## from the live row so the height number matches the measured value.
func _add_caption(vp: SubViewport, key: String, base_str: String) -> void:
	var bar := ColorRect.new()
	bar.color = CAP_BG
	bar.position = Vector2(0, TILE_PX - CAP_BAR_PX)
	bar.size = Vector2(TILE_PX, CAP_BAR_PX)
	vp.add_child(bar)
	var label := Label.new()
	label.position = Vector2(10, TILE_PX - CAP_BAR_PX + 8)
	label.size = Vector2(TILE_PX - 20, CAP_BAR_PX - 12)
	label.add_theme_color_override("font_color", CAP_FG)
	label.add_theme_font_size_override("font_size", 19)
	label.text = "%s\n%s" % [key, base_str]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vp.add_child(label)


func _capture(vp: SubViewport) -> Image:
	for _i in range(SETTLE_FRAMES):
		await process_frame
	var img: Image = vp.get_texture().get_image()
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	vp.queue_free()
	return img


func _base_str(spec: Dictionary) -> String:
	if bool(spec["oval"]):
		return "%d×%dmm oval" % [int(spec["long_mm"]), int(spec["short_mm"])]
	return "Ø%dmm round" % int(spec["long_mm"])


# === Anomaly analysis ===

func _compute_anomalies() -> void:
	# Fleet median of the plain-trooper group (round <=30mm base, Tough<=1, no rider) — the wrong-scale
	# reference. Derived from the fleet itself so a whole-fleet shift doesn't false-flag.
	var trooper_h: Array = []
	for r in _rows:
		if r.get("loadfail", false) or r.get("in_rework", false):
			continue
		if bool(r.get("is_trooper", false)):
			# The judged box (body when present) — a crest/banner must not skew the fleet reference.
			trooper_h.append(float(r["body_h_mm"]) if bool(r.get("has_body", false)) else float(r["total_h_mm"]))
	var trooper_median: float = _median(trooper_h)

	for r in _rows:
		if r.get("loadfail", false):
			r["flags"] = ["LOADFAIL"]
			continue
		var flags: Array = []
		var notes: Array = r["notes"]
		var klass: String = str(r["klass"])
		var total_h: float = float(r["total_h_mm"])
		var body_h: float = float(r["body_h_mm"])
		var min_w: float = float(r["combined_min_world_m"])
		var spec: Dictionary = r["spec"]

		# (b) grounding
		if min_w < GROUND_SUNK_M:
			flags.append("GROUND")
			notes.append("lowest point %.1fmm below table (sunk / below-feet geometry)" % (min_w * 1000.0))
		elif min_w > GROUND_FLOAT_M:
			flags.append("GROUND")
			notes.append("lowest point %.1fmm above base top (floating)" % ((min_w - 0.003) * 1000.0))

		# (c) overhang
		var long_ratio: float = float(r["foot_long_mm"]) / maxf(1.0, float(spec["long_mm"]))
		var short_ratio: float = float(r["foot_short_mm"]) / maxf(1.0, float(spec["short_mm"]))
		if long_ratio > OVERHANG_LONG_RATIO or (bool(spec["oval"]) and short_ratio > OVERHANG_SHORT_RATIO):
			flags.append("OVERHANG")
			notes.append("footprint %.0f×%.0fmm vs base %d×%dmm (%.1fx long, %.1fx short)" % [
				float(r["foot_long_mm"]), float(r["foot_short_mm"]),
				int(spec["long_mm"]), int(spec["short_mm"]), long_ratio, short_ratio])

		# (a) height — the box that DRIVES the fit (body when present, contract v1.2) vs the fit's OWN
		# Tough-derived intended target. A banner/crest/spear on an on-target body is CORRECT and must
		# not flag; a total far above the body is fragment-shaped and does.
		var target: float = float(r.get("target_mm", 0.0))
		var judged_h: float = body_h if bool(r.get("has_body", false)) else total_h
		if r.get("in_rework", false):
			pass   # in-rework families are not height-alarmed
		elif total_h < HEIGHT_ABS_MIN_MM or total_h > HEIGHT_ABS_MAX_MM:
			flags.append("HEIGHT")
			notes.append("total height %.1fmm implausible (abs sanity %.0f-%.0fmm)" % [
				total_h, HEIGHT_ABS_MIN_MM, HEIGHT_ABS_MAX_MM])
		elif klass == "rider":
			if body_h < RIDER_BODY_LO_MM or body_h > RIDER_BODY_HI_MM:
				flags.append("HEIGHT")
				notes.append("rider body %.1fmm off the ~28mm trooper target [%.0f-%.0f] (rider/body-node?)" % [
					body_h, RIDER_BODY_LO_MM, RIDER_BODY_HI_MM])
		elif target > 0.0 and judged_h > target * HEIGHT_OVER_TARGET:
			flags.append("HEIGHT")
			notes.append("%s %.1fmm is %.2fx the Tough-derived target %.1fmm (too tall / measurement bug)" % [
				"body" if bool(r.get("has_body", false)) else "total", judged_h, judged_h / target, target])
		elif target > 0.0 and judged_h < target * HEIGHT_UNDER_TARGET:
			flags.append("HEIGHT")
			notes.append("%s %.1fmm is %.2fx the Tough-derived target %.1fmm (footprint-slam / bad AABB)" % [
				"body" if bool(r.get("has_body", false)) else "total", judged_h, judged_h / target, target])
		elif bool(r.get("has_body", false)) and total_h > body_h * PARTS_DOMINANCE_MAX:
			flags.append("HEIGHT")
			notes.append("total %.1fmm is %.1fx the body %.1fmm — fragment-shaped geometry far above the model" % [
				total_h, total_h / maxf(0.1, body_h), body_h])
		elif bool(r.get("is_trooper", false)) and trooper_median > 0.0 \
				and absf(judged_h - trooper_median) > trooper_median * TROOPER_FLEET_DEV:
			flags.append("HEIGHT")
			notes.append("trooper height %.1fmm deviates >%.0f%% from trooper fleet median %.1fmm" % [
				judged_h, TROOPER_FLEET_DEV * 100.0, trooper_median])

		r["flags"] = flags
		r["trooper_median"] = trooper_median


func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s: Array = a.duplicate()
	s.sort()
	var n: int = s.size()
	if n % 2 == 1:
		return float(s[n / 2])
	return (float(s[n / 2 - 1]) + float(s[n / 2])) * 0.5


# === Contact-sheet montage ===

func _build_sheets(out_dir: String) -> void:
	# Greedily pack whole families (contiguous, in sorted order) into sheets of <= SHEET_CAP tiles; a
	# family larger than the cap splits across consecutive sheets. Flagged tiles get a coloured border.
	var families: Array = []          # ordered [ {name, rows:[...]} ]
	var seen: Dictionary = {}
	for r in _rows:
		var fam: String = str(r["family"])
		if not seen.has(fam):
			seen[fam] = families.size()
			families.append({"name": fam, "rows": []})
		families[seen[fam]]["rows"].append(r)

	var sheets: Array = []             # [ {label, rows:[...]} ]
	var cur: Array = []
	var cur_fams: Array = []
	for fam in families:
		var frows: Array = fam["rows"]
		if frows.size() > SHEET_CAP:
			if not cur.is_empty():
				sheets.append({"label": ", ".join(cur_fams), "rows": cur})
				cur = []
				cur_fams = []
			var off: int = 0
			var part: int = 1
			while off < frows.size():
				var chunk: Array = frows.slice(off, off + SHEET_CAP)
				sheets.append({"label": "%s (part %d)" % [fam["name"], part], "rows": chunk})
				off += SHEET_CAP
				part += 1
			continue
		if cur.size() + frows.size() > SHEET_CAP and not cur.is_empty():
			sheets.append({"label": ", ".join(cur_fams), "rows": cur})
			cur = []
			cur_fams = []
		cur.append_array(frows)
		cur_fams.append(fam["name"])
	if not cur.is_empty():
		sheets.append({"label": ", ".join(cur_fams), "rows": cur})

	var n: int = 1
	_sheet_index = []
	for sh in sheets:
		var fname: String = "sheet_%02d_%s.png" % [n, _slug(str(sh["rows"][0]["family"]))]
		_render_sheet(sh["rows"], out_dir.path_join(fname))
		_sheet_index.append({"file": fname, "label": sh["label"], "count": sh["rows"].size()})
		n += 1


var _sheet_index: Array = []


func _render_sheet(rows: Array, out_path: String) -> void:
	var n: int = rows.size()
	var ncols: int = mini(COLS, n)
	var nrows: int = int(ceil(float(n) / float(COLS)))
	var sheet := Image.create(ncols * TILE_PX, nrows * TILE_PX, false, Image.FORMAT_RGBA8)
	sheet.fill(SHEET_BG)
	for i in range(n):
		var r: Dictionary = rows[i]
		var col: int = i % COLS
		var rw: int = i / COLS
		var ox: int = col * TILE_PX
		var oy: int = rw * TILE_PX
		var tile: Image = r["img"]
		if tile != null:
			if tile.get_format() != Image.FORMAT_RGBA8:
				tile.convert(Image.FORMAT_RGBA8)
			sheet.blit_rect(tile, Rect2i(0, 0, TILE_PX, TILE_PX), Vector2i(ox, oy))
		var flags: Array = r.get("flags", [])
		if r.get("in_rework", false):
			_draw_border(sheet, ox, oy, FLAG_REWORK, 6)
		if not flags.is_empty():
			_draw_border(sheet, ox, oy, _flag_color(flags), 8)
	var err: int = sheet.save_png(out_path)
	if err != OK:
		push_error("faction_gallery_render: save_png failed (%d) for %s" % [err, out_path])
	else:
		print("faction_gallery_render: wrote %s (%d tiles)" % [out_path, n])


func _flag_color(flags: Array) -> Color:
	if "LOADFAIL" in flags:
		return FLAG_LOADFAIL
	if "HEIGHT" in flags:
		return FLAG_HEIGHT
	if "OVERHANG" in flags:
		return FLAG_OVERHANG
	if "GROUND" in flags:
		return FLAG_GROUND
	return FLAG_LOADFAIL


func _draw_border(img: Image, ox: int, oy: int, color: Color, t: int) -> void:
	for y in range(TILE_PX):
		for x in range(TILE_PX):
			if x < t or x >= TILE_PX - t or y < t or y >= TILE_PX - t:
				img.set_pixel(ox + x, oy + y, color)


# === Report ===

func _write_report(out_dir: String) -> void:
	var anomalies: Array = []
	var clean: Array = []
	var rework: Array = []
	for r in _rows:
		if r.get("in_rework", false):
			rework.append(r)
			continue
		if r.get("flags", []).is_empty():
			clean.append(str(r["key"]))
		else:
			anomalies.append(r)

	var lines: Array = []
	lines.append("# %s — in-game render gallery: anomaly report" % _faction)
	lines.append("")
	lines.append("Coverage: %d models rendered. Anomalies: %d. Clean: %d. In-rework: %d." % [
		_rows.size(), anomalies.size(), clean.size(), rework.size()])
	lines.append("Trooper fleet median height: %.1fmm (wrong-scale reference)." % _trooper_median())
	lines.append("")
	lines.append("Height rule: the fit-driving box (`body` when present, else combined) vs the fit's OWN Tough-derived ")
	lines.append("target (_height_target(base)×1.05^(T/3)×fit_scale); flag if >%.2fx (too tall) or <%.2fx (footprint-slam), " % [
		HEIGHT_OVER_TARGET, HEIGHT_UNDER_TARGET])
	lines.append("rider body outside %.0f-%.0fmm, total >%.1fx body (fragment-shaped), or abs outside %.0f-%.0fmm." % [
		RIDER_BODY_LO_MM, RIDER_BODY_HI_MM, PARTS_DOMINANCE_MAX, HEIGHT_ABS_MIN_MM, HEIGHT_ABS_MAX_MM])
	lines.append("Ground: sunk < -5mm below table, float > +8mm above base. Overhang: >2.0x long or >2.5x short.")
	lines.append("")
	lines.append("## Anomalies (%d)" % anomalies.size())
	lines.append("")
	if anomalies.is_empty():
		lines.append("_All clean — no anomalies flagged._")
	else:
		for r in anomalies:
			var s: Dictionary = r["spec"]
			lines.append("- **%s** [%s] `%s` base=%s h=%.1fmm body=%.1fmm foot=%.0f×%.0fmm minY=%.1fmm — %s" % [
				str(r["key"]), "/".join(r["flags"]), str(r["klass"]), _base_str(s),
				float(r["total_h_mm"]), float(r["body_h_mm"]),
				float(r["foot_long_mm"]), float(r["foot_short_mm"]),
				float(r["combined_min_world_m"]) * 1000.0, "; ".join(r["notes"])])
	lines.append("")
	lines.append("## Known in-rework (not alarmed) (%d)" % rework.size())
	lines.append("")
	for r in rework:
		lines.append("- _%s_ — snake-rider rework (saddle seating / recalibration); h=%.1fmm body=%.1fmm%s" % [
			str(r["key"]), float(r.get("total_h_mm", 0.0)), float(r.get("body_h_mm", 0.0)),
			("" if r.get("flags", []).is_empty() else "  (would-flag: %s)" % "/".join(r["flags"]))])
	lines.append("")
	lines.append("## Clean bill (%d)" % clean.size())
	lines.append("")
	clean.sort()
	lines.append(", ".join(clean))
	lines.append("")
	lines.append("## Contact sheets")
	lines.append("")
	for s in _sheet_index:
		lines.append("- `%s` — %d tiles — %s" % [str(s["file"]), int(s["count"]), str(s["label"])])
	lines.append("")

	var f := FileAccess.open(out_dir.path_join("anomalies.md"), FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines))
		f.close()
		print("faction_gallery_render: wrote anomalies.md")
	else:
		push_error("faction_gallery_render: could not write anomalies.md")

	# Machine-readable measurements alongside, for any downstream tooling.
	var jrows: Array = []
	for r in _rows:
		jrows.append({
			"key": r["key"], "family": r["family"], "class": r.get("klass", ""),
			"size_class": r.get("size_class", ""), "in_rework": r.get("in_rework", false),
			"loadfail": r.get("loadfail", false), "flags": r.get("flags", []),
			"base_mm": _base_str(r["spec"]), "fit_scale": r.get("fit_scale", 1.0),
			"total_h_mm": r.get("total_h_mm", 0.0), "body_h_mm": r.get("body_h_mm", 0.0),
			"target_mm": r.get("target_mm", 0.0),
			"foot_long_mm": r.get("foot_long_mm", 0.0), "foot_short_mm": r.get("foot_short_mm", 0.0),
			"min_world_mm": r.get("combined_min_world_m", 0.0) * 1000.0, "notes": r.get("notes", []),
		})
	var jf := FileAccess.open(out_dir.path_join("measurements.json"), FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify({"faction": _faction, "count": _rows.size(), "models": jrows}, "  "))
		jf.close()


func _trooper_median() -> float:
	for r in _rows:
		if r.has("trooper_median"):
			return float(r["trooper_median"])
	return 0.0


# === Small helpers ===

## Fold '-'/'_' to spaces + collapse, matching ModelLibrary._normalize_unit so table keys line up.
func _fold(s: String) -> String:
	var t: String = s.strip_edges().to_lower().replace("-", " ").replace("_", " ")
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t


func _slug(s: String) -> String:
	return s.replace(" ", "_").replace("#", "_").replace("+", "_")


## Parse an AF base value ("80", 80, "90x52") -> [is_oval, long_mm, short_mm].
func _parse_base(v: Variant) -> Array:
	if v is int or v is float:
		return [false, int(v), int(v)]
	var s: String = str(v).strip_edges().to_lower()
	if s.contains("x"):
		var p: PackedStringArray = s.split("x")
		if p.size() >= 2 and p[0].is_valid_int() and p[1].is_valid_int():
			var a: int = p[0].to_int()
			var b: int = p[1].to_int()
			return [true, maxi(a, b), mini(a, b)]
	if s.is_valid_int():
		return [false, s.to_int(), s.to_int()]
	return [false, 25, 25]
