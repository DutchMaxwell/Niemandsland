extends SceneTree
## QA tool: in-game scale-comparison render for the Mummified Undead snake-rider `fit_scale` fix.
##
## Drives the REAL spawn pipeline exactly as the game does: a ModelLibrary (fed the staged manifest via
## the NML_MANIFEST_URL override, so `fit_scale` / `long_axis` come from the SAME code the client uses)
## resolves + downloads each unit's GLB from the CDN, then OPRArmyManager._get_model_aabb /
## _get_body_aabb / _compute_model_fit(..., entry_fit_scale) / _align_to_oval_long_axis(..., axis_override)
## size + orient every model — the pilot spawn path (opr_army_manager.gd lines ~1407-1416) with nothing
## re-implemented. It then lines the units up on a table for scale comparison and captures three shots:
##   <prefix>_elevation.png  orthographic side elevation with per-model height bars + measured mm,
##   <prefix>_table.png      a 3/4 perspective table view (grounding + facing + textures),
##   <prefix>_topdown.png    top-down of the oval-base serpents (length must run along the oval).
## A summary table + per-unit PASS/FAIL against the expected height window is printed.
##
## The fix under test adds `fit_scale ~= 0.381` to the four snake-rider UNIT keys so the ride-body
## regression (snake balloons to ~156mm) collapses back to its ~59mm cavalry size, while champion#snake
## (rider-fit) and great snakes (mount-fit) are untouched. The PRE-FIX column forces fit_scale=1.0 to
## show the regression side by side with the fixed model.
##
## Usage (needs a REAL renderer — a virtual/headless Wayland compositor; NOT Godot's --headless):
##   NML_MANIFEST_URL=http://127.0.0.1:<port>/model_manifest.mummified_pilot.json \
##   gamescope --backend headless -W 2560 -H 1080 -- \
##     flatpak run --filesystem=home --socket=wayland --share=network org.godotengine.Godot \
##       --path <project> --rendering-driver vulkan -s res://tools/snake_scale_render.gd -- <out_prefix>
## Optional 2nd arg: a local manifest .json path used as a fallback if NML_MANIFEST_URL does not load.

# === Constants ===

const IMAGE_SIZE: Vector2i = Vector2i(2560, 1080)
## Frames to let the renderer settle (material + texture upload) before a capture.
const SETTLE_FRAMES: int = 18
## Frames to wait for the manifest override to load (localhost fetch), before the fallback.
const MANIFEST_WAIT_FRAMES: int = 900
const FACTION: String = "mummified_undead"
## Column pitch along +X (metres). Wide enough for the tallest/widest column (the PRE-FIX snake).
const SPACING: float = 0.15
const BASE_THICKNESS_M: float = 0.003
const BASE_TOP_Y: float = BASE_THICKNESS_M
const BACKGROUND_COLOR: Color = Color(0.12, 0.13, 0.16)
const GROUND_COLOR: Color = Color(0.28, 0.27, 0.25)
const BASE_COLOR: Color = Color(0.22, 0.33, 0.52)
const BAR_COLOR: Color = Color(0.96, 0.28, 0.22)
const LABEL_COLOR: Color = Color(0.94, 0.94, 0.94)
const TITLE_COLOR: Color = Color(0.75, 0.88, 1.0)

## The comparison line-up. `fit_override` < 0 => read fit_scale from the manifest (the real path);
## a value >= 0 forces it (the PRE-FIX column pins 1.0 to reproduce the regression). Base dims mirror the
## Army Forge book (uid t-sIke2snonFSL6Q, gameSystem 4): snakes 90x52, champion mount 75x46, cavalry
## 60x35, infantry 25mm round. `expect_lo`/`expect_hi` bound the acceptance window (combined mm).
const CASES: Array = [
	{"label": "skeleton warriors", "unit": "skeleton warriors", "long_mm": 25, "short_mm": -1,
		"tough": 1, "is_mount": false, "oval": false, "fit_override": -1.0,
		"expect": "infantry ~28mm", "expect_lo": 22.0, "expect_hi": 36.0},
	{"label": "skeleton horsemen", "unit": "skeleton horsemen", "long_mm": 60, "short_mm": 35,
		"tough": 3, "is_mount": false, "oval": true, "fit_override": -1.0,
		"expect": "cavalry ~50mm", "expect_lo": 38.0, "expect_hi": 62.0},
	{"label": "snake riders  [FIXED]", "unit": "snake riders", "long_mm": 90, "short_mm": 52,
		"tough": 3, "is_mount": false, "oval": true, "fit_override": -1.0,
		"expect": "~59mm cavalry", "expect_lo": 50.0, "expect_hi": 68.0},
	{"label": "snake riders  [PRE-FIX]", "unit": "snake riders", "long_mm": 90, "short_mm": 52,
		"tough": 3, "is_mount": false, "oval": true, "fit_override": 1.0,
		"expect": "~156mm regressed", "expect_lo": 130.0, "expect_hi": 180.0},
	{"label": "royal champion#snake", "unit": "royal champion#snake", "long_mm": 75, "short_mm": 46,
		"tough": 3, "is_mount": true, "oval": true, "fit_override": -1.0,
		"expect": "~48mm unchanged", "expect_lo": 40.0, "expect_hi": 58.0},
	{"label": "great snakes", "unit": "great snakes", "long_mm": 90, "short_mm": 52,
		"tough": 3, "is_mount": false, "oval": true, "fit_override": -1.0,
		"expect": "~70mm monster", "expect_lo": 58.0, "expect_hi": 84.0},
]
## Indices of the oval-base serpents shown in the top-down orientation shot.
const TOPDOWN_INDICES: Array = [2, 4, 5]

var _lib: ModelLibrary = null
var _mgr: OPRArmyManager = null


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("Usage: -s res://tools/snake_scale_render.gd -- <out_prefix> [fallback_manifest.json]")
		quit(1)
		return
	var out_prefix: String = args[0]
	var fallback_manifest: String = args[1] if args.size() > 1 else ""

	_lib = ModelLibrary.new()
	get_root().add_child(_lib)   # _ready(): builds the downloader + honours NML_MANIFEST_URL
	if not await _await_manifest(fallback_manifest):
		push_error("snake_scale_render: manifest with mummified snake keys never loaded")
		quit(1)
		return

	_mgr = OPRArmyManager.new()   # methods only; never entered into the tree (no autoloads needed)
	var cases: Array = CASES.duplicate(true)
	for c in cases:
		var path: String = await _lib.ensure_model(FACTION, c["unit"])
		if path.is_empty():
			push_error("snake_scale_render: could not fetch model for %s" % c["unit"])
			quit(1)
			return
		c["path"] = path
		var manifest_fs: float = _lib.fit_scale(FACTION, c["unit"])
		c["fit_scale_used"] = float(c["fit_override"]) if float(c["fit_override"]) >= 0.0 else manifest_fs
		c["long_axis"] = _lib.long_axis_override(FACTION, c["unit"])

	# Measure once (for the summary + labels) from a throwaway build, then render the three shots.
	_measure_all(cases)
	_render_elevation(cases, out_prefix + "_elevation.png")
	await _settle()
	_render_table(cases, out_prefix + "_table.png")
	await _settle()
	_render_topdown(cases, out_prefix + "_topdown.png")
	await _settle()

	_print_summary(cases)
	_mgr.free()
	quit(0)


# === Manifest bootstrap ===

## Waits for the NML_MANIFEST_URL override to populate the mummified snake keys; on timeout applies a
## local fallback manifest file if one was given. Returns true once the keys are present.
func _await_manifest(fallback_manifest: String) -> bool:
	for _i in range(MANIFEST_WAIT_FRAMES):
		if _lib.has_model(FACTION, "snake riders"):
			print("snake_scale_render: manifest loaded via override (has snake riders)")
			return true
		await process_frame
	if not fallback_manifest.is_empty() and FileAccess.file_exists(fallback_manifest):
		print("snake_scale_render: override timed out — applying fallback manifest %s" % fallback_manifest)
		_lib.apply_manifest_text(FileAccess.get_file_as_string(fallback_manifest))
	return _lib.has_model(FACTION, "snake riders")


func _settle() -> void:
	for _i in range(SETTLE_FRAMES):
		await process_frame


# === Measurement ===

## Fills each case with the measured combined + rider-body heights (mm) using the real fit, without
## rendering — so the printed summary and the on-image labels agree.
func _measure_all(cases: Array) -> void:
	for c in cases:
		var glb: Node3D = _mgr._instantiate_model(c["path"])
		if glb == null:
			c["combined_mm"] = 0.0
			c["body_mm"] = 0.0
			c["scale"] = 0.0
			continue
		var aabb: AABB = _mgr._get_model_aabb(glb)
		var body: AABB = _mgr._get_body_aabb(glb)
		var fit: Dictionary = _mgr._compute_model_fit(aabb, int(c["long_mm"]), int(c["tough"]), 0.0,
			int(c["short_mm"]), false, body, bool(c["is_mount"]), float(c["fit_scale_used"]))
		var scale: float = float(fit["scale"])
		c["scale"] = scale
		c["combined_mm"] = aabb.size.y * scale * 1000.0
		c["body_mm"] = (body.size.y if body.size.y > 0.0 else aabb.size.y) * scale * 1000.0
		c["has_body"] = body.size.y > 0.0
		glb.free()


# === Shot builders ===

## Builds a fresh viewport + world with the given camera and returns {viewport, world}. The caller adds
## models then captures. A per-shot viewport keeps captures at IMAGE_SIZE regardless of window size.
func _new_scene() -> Dictionary:
	var vp := SubViewport.new()
	vp.size = IMAGE_SIZE
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	var world := Node3D.new()
	vp.add_child(world)
	return {"viewport": vp, "world": world}


func _render_elevation(cases: Array, out_path: String) -> void:
	var scene: Dictionary = _new_scene()
	var world: Node3D = scene["world"]
	_add_environment(world, Vector3(-52.0, 28.0, 0.0))
	for i in range(cases.size()):
		var c: Dictionary = cases[i]
		var x: float = float(i) * SPACING
		var top_y: float = _place_unit(world, c, x, false)
		# Height measure bar next to the model + a two-line label above it.
		_add_bar(world, x + float(c["long_mm"]) * 0.0006 + 0.010, BASE_TOP_Y, top_y)
		_add_label(world, "%s\n%.1f mm  (%s)" % [c["label"], float(c["combined_mm"]), c["expect"]],
			Vector3(x, top_y + 0.028, 0.0), true, 34, LABEL_COLOR)
	_add_label(world, "Mummified Undead — model scale comparison (real spawn fit; heights = rendered combined mm)",
		Vector3(float(cases.size() - 1) * SPACING * 0.5, 0.33, 0.0), true, 40, TITLE_COLOR)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.42
	cam.position = Vector3(float(cases.size() - 1) * SPACING * 0.5, 0.15, 1.2)
	world.add_child(cam)
	cam.make_current()
	await _capture(scene, out_path)


func _render_table(cases: Array, out_path: String) -> void:
	var scene: Dictionary = _new_scene()
	var world: Node3D = scene["world"]
	_add_environment(world, Vector3(-48.0, 35.0, 0.0))
	for i in range(cases.size()):
		var c: Dictionary = cases[i]
		var x: float = float(i) * SPACING
		var top_y: float = _place_unit(world, c, x, false)
		_add_label(world, "%s\n%.0f mm" % [c["label"], float(c["combined_mm"])],
			Vector3(x, top_y + 0.022, 0.0), true, 30, LABEL_COLOR)

	var center_x: float = float(cases.size() - 1) * SPACING * 0.5
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_PERSPECTIVE
	cam.fov = 38.0
	world.add_child(cam)   # look_at needs the node in-tree (global transform)
	cam.look_at_from_position(Vector3(center_x, 0.34, 0.78), Vector3(center_x, 0.045, 0.0), Vector3.UP)
	cam.make_current()
	await _capture(scene, out_path)


func _render_topdown(cases: Array, out_path: String) -> void:
	var scene: Dictionary = _new_scene()
	var world: Node3D = scene["world"]
	_add_environment(world, Vector3(-75.0, 20.0, 0.0))
	var slot: int = 0
	for idx in TOPDOWN_INDICES:
		var c: Dictionary = cases[idx]
		var x: float = float(slot) * 0.14
		_place_unit(world, c, x, false)
		_add_label(world, str(c["label"]), Vector3(x, 0.008, -0.075), false, 34, LABEL_COLOR)
		slot += 1
	_add_label(world, "top-down: each serpent's length must run along its oval LONG axis (vertical)",
		Vector3(0.14, 0.008, 0.09), false, 32, TITLE_COLOR)

	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 0.24
	cam.position = Vector3(0.14, 0.9, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	world.add_child(cam)
	cam.make_current()
	await _capture(scene, out_path)


## Instantiates a unit's GLB, fits + orients it on its base with the real pipeline, and adds a base
## plate. Returns the model's world top Y (metres). `flat_base` is unused hook for future round-only rows.
func _place_unit(world: Node3D, c: Dictionary, x: float, _flat_base: bool) -> float:
	var glb: Node3D = _mgr._instantiate_model(c["path"])
	if glb == null:
		return BASE_TOP_Y
	var aabb: AABB = _mgr._get_model_aabb(glb)
	var body: AABB = _mgr._get_body_aabb(glb)
	var fit: Dictionary = _mgr._compute_model_fit(aabb, int(c["long_mm"]), int(c["tough"]), 0.0,
		int(c["short_mm"]), false, body, bool(c["is_mount"]), float(c["fit_scale_used"]))
	var scale: float = float(fit["scale"])

	var unit := Node3D.new()
	unit.position = Vector3(x, 0.0, 0.0)
	world.add_child(unit)
	_add_base(unit, c)

	glb.scale = Vector3(scale, scale, scale)
	glb.position.y = float(fit["y_offset"])
	_mgr._align_to_oval_long_axis(glb, aabb, bool(c["oval"]),
		float(c["short_mm"]) * 0.001 if bool(c["oval"]) else float(c["long_mm"]) * 0.001,
		float(c["long_mm"]) * 0.001 if bool(c["oval"]) else float(c["long_mm"]) * 0.001,
		false, str(c["long_axis"]))
	_mgr._brighten_trellis_materials(glb)
	unit.add_child(glb)
	return float(fit["y_offset"]) + aabb.size.y * scale


func _add_base(unit: Node3D, c: Dictionary) -> void:
	var base := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.height = BASE_THICKNESS_M
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.5
	base.mesh = mesh
	if bool(c["oval"]):
		# AF ovals put the long side into depth (Z); width (X) is the short side.
		base.scale = Vector3(float(c["short_mm"]) * 0.001, 1.0, float(c["long_mm"]) * 0.001)
	else:
		var d: float = float(c["long_mm"]) * 0.001
		base.scale = Vector3(d, 1.0, d)
	base.position.y = BASE_THICKNESS_M / 2.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BASE_COLOR
	mat.roughness = 0.7
	base.material_override = mat
	unit.add_child(base)


# === Scene furniture ===

func _add_environment(world: Node3D, sun_euler: Vector3) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 1.1
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = sun_euler
	sun.light_energy = 1.4
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(4.0, 4.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = GROUND_COLOR
	gmat.roughness = 1.0
	ground.material_override = gmat
	world.add_child(ground)


## A thin vertical emissive bar spanning a model's world height, placed just beside it (elevation shot).
func _add_bar(world: Node3D, x: float, bottom_y: float, top_y: float) -> void:
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.0012, maxf(0.0001, top_y - bottom_y), 0.0012)
	bar.mesh = box
	bar.position = Vector3(x, (bottom_y + top_y) / 2.0, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = BAR_COLOR
	mat.emission_enabled = true
	mat.emission = BAR_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar.material_override = mat
	world.add_child(bar)


func _add_label(world: Node3D, text: String, pos: Vector3, billboard: bool, font_size: int,
		color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = 0.00016
	label.modulate = color
	label.outline_size = 10
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.position = pos
	if billboard:
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	else:
		label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)   # lie flat, face the top-down camera
	world.add_child(label)


# === Capture ===

func _capture(scene: Dictionary, out_path: String) -> void:
	await _settle()
	var vp: SubViewport = scene["viewport"]
	var img: Image = vp.get_texture().get_image()
	var err: int = img.save_png(out_path)
	if err != OK:
		push_error("snake_scale_render: save_png failed (%d) for %s" % [err, out_path])
	else:
		print("snake_scale_render: wrote %s" % out_path)
	vp.queue_free()


func _print_summary(cases: Array) -> void:
	print("=== snake_scale_render summary (combined height, real spawn fit) ===")
	var all_ok: bool = true
	for c in cases:
		var mm: float = float(c["combined_mm"])
		var ok: bool = mm >= float(c["expect_lo"]) and mm <= float(c["expect_hi"])
		all_ok = all_ok and ok
		print("%-26s fit_scale=%.4f scale=%.5f combined=%6.1fmm body=%6.1fmm  expect[%s]  %s" % [
			c["label"], float(c["fit_scale_used"]), float(c["scale"]), mm, float(c["body_mm"]),
			c["expect"], "PASS" if ok else "FAIL"])
	print("=== RESULT: %s ===" % ("PASS" if all_ok else "FAIL"))
