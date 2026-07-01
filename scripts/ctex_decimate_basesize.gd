extends Node3D
## Per-base-size decimation-threshold harness. RUN VIA F6 on a real GPU (headless = dummy renderer,
## get_image() is null). Renders ONE Blender-decimated ladder (assault brothers, user://decimate_glbs/,
## 286k→11k in 25k steps) at the TRUE on-table apparent size for each base tier (25 / 32 / 40 mm), with
## the camera at the in-game closest zoom (min_zoom = 0.06 m — the "zoomed all the way in on one model"
## worst case). Holding the model constant and varying only apparent size isolates the axis
## apparent-size → triangle-floor; a real larger-base sculpt is more complex, so a 40 mm floor found
## here is a conservative LOWER bound. Saves user://decimate_basesize/base_<mm>/tris_<NNNNNN>.png +
## a per-base full-res reference; tools/decimate_analysis.py then SSIM-diffs each step vs full to find
## the point at which we must NOT decimate. Deterministic capture: SubViewport, TAA off, MSAA 8x.

const PATCH := "res://bb_ctex_patch.json"
const CACHE := "user://cache/"
const GLB_DIR := "user://decimate_glbs/"
const OUT := "user://decimate_basesize/"
const KEY := "battle_brothers/assault brothers"

# Base tiers to probe (mm). Real-world mini height scales linearly with base size; REF_HEIGHT_M is a
# 25 mm-base infantry mini's world height (in-game minis are scaled so the base fits base_size). 80 mm
# stands in for every large base (monsters/vehicle ovals): above the frame-fill knee (~61 mm) they all
# render identically, since the player backs the camera off until the model fits.
const BASE_SIZES_MM: Array[int] = [25, 32, 40, 50, 60, 80]
const REF_HEIGHT_M := 0.032          # 25 mm-base infantry ≈ 32 mm tall in world (1 unit = 1 m)
const REF_BASE_MM := 25.0

# Camera: default FOV, a near-eye-level 3/4 angle (silhouette + face faceting both visible under a
# raking key light). Apparent size = the closest sensible inspection: the player zooms to MIN_ZOOM but
# no closer, and for a model too big to fit there, backs off until it fills FILL_FRACTION of the frame.
const MIN_ZOOM_M := 0.06             # camera_controller.gd min_zoom (closest single-model zoom)
const FILL_FRACTION := 0.85          # a backed-off large model fills this fraction of frame height
const CAM_FOV_DEG := 75.0            # Godot Camera3D default
const CAM_NEAR := 0.005
const CAM_ELEV_DEG := 20.0           # camera above the model
const CAM_AZIM_DEG := 25.0           # 3/4 yaw
const VIEW_PX := 1440                # higher res for detail closeups

var _label: Label
var _mat: StandardMaterial3D
var _viewport: SubViewport
var _cam: Camera3D
# Env overrides (empty = default): NML_LADDER_DIR, NML_OUT_DIR, NML_BASES ("40,60,80"),
# NML_EMBEDDED_MAT ("1" = use the GLB's own material instead of the assault-brothers .ctex).
var _glb_dir: String
var _out: String
var _bases: Array = BASE_SIZES_MM
var _use_embedded: bool

func _ready() -> void:
	_glb_dir = _env("NML_LADDER_DIR", GLB_DIR)
	_out = _env("NML_OUT_DIR", OUT)
	_use_embedded = OS.get_environment("NML_EMBEDDED_MAT") == "1"
	var b := OS.get_environment("NML_BASES")
	if not b.is_empty():
		_bases = []
		for tok in b.split(","):
			_bases.append(int(tok))
	DirAccess.make_dir_recursive_absolute(_out)
	_mat = null if _use_embedded else _build_material()
	_setup_hud()
	_setup_viewport()
	await _run()


func _env(name: String, fallback: String) -> String:
	var v := OS.get_environment(name)
	return v if not v.is_empty() else fallback


# === Setup ===

func _build_material() -> StandardMaterial3D:
	# Shipped look via the .ctex material (assault brothers). Falls back to the GLB's embedded material
	# (override left null) when the .ctex files aren't cached, so the scene still runs.
	if not FileAccess.file_exists(PATCH):
		return null
	var patch: Dictionary = JSON.parse_string(FileAccess.open(PATCH, FileAccess.READ).get_as_text())
	if not patch.has(KEY):
		return null
	var tex: Dictionary = patch[KEY]["ctex"]["textures"]
	var mat := CtexLoader.build_material(CACHE + str(tex["albedo"]["url"]), "",
		(CACHE + str(tex["orm"]["url"]) if tex.has("orm") else ""), false)
	return mat if mat.albedo_texture != null else null


func _setup_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 26)
	_label.position = Vector2(28, 24)
	cl.add_child(_label)


func _setup_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(VIEW_PX, VIEW_PX)
	_viewport.transparent_bg = false
	_viewport.msaa_3d = Viewport.MSAA_8X
	_viewport.use_taa = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_cam = Camera3D.new()
	_cam.fov = CAM_FOV_DEG
	_cam.near = CAM_NEAR
	_cam.far = 10.0
	_viewport.add_child(_cam)

	# Front-lit 3-point setup (lights come FROM the camera hemisphere so the camera-facing FRONT is
	# well lit — the old key was behind the model, leaving dark materials' fronts in shadow). Camera
	# sits at azim 25°/elev 20°; key/fill are near it, rim behind for edge separation.
	_add_light(38.0, 30.0, 1.9)     # key: front, slightly right + above
	_add_light(-28.0, 14.0, 1.35)   # fill: front-left, low — strongly lifts front shadows
	_add_light(160.0, 55.0, 0.55)   # rim/top-back: separates dark tops from white bg

	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	# NML_WHITE_BG=1 → white backdrop so silhouette faceting stands out for evaluation.
	var white := OS.get_environment("NML_WHITE_BG") == "1"
	e.background_color = Color(1.0, 1.0, 1.0) if white else Color(0.10, 0.11, 0.13)
	e.ambient_light_color = Color(0.62, 0.62, 0.67)
	e.ambient_light_energy = 1.1    # lifted so dark materials still read
	# Filmic tonemap lifts shadows (dark raiders/orc) while rolling off highlights (gold armour won't
	# blow out) — a plain linear boost would clip the bright models.
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.35
	we.environment = e
	_viewport.add_child(we)


# Add a DirectionalLight3D coming FROM (azim, elev) — positioned there and aimed at the origin, so the
# model's front (camera side) is lit for evaluation regardless of material darkness.
func _add_light(azim_deg: float, elev_deg: float, energy: float) -> void:
	var l := DirectionalLight3D.new()
	var el := deg_to_rad(elev_deg)
	var az := deg_to_rad(azim_deg)
	l.position = Vector3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
	l.look_at(Vector3.ZERO, Vector3.UP)
	l.light_energy = energy
	_viewport.add_child(l)


func _log(s: String) -> void:
	if _label:
		_label.text = s
	print("[BASESIZE] ", s)


# === Run ===

func _run() -> void:
	var files := _ladder_files()
	if files.is_empty():
		_log("NO GLBs in %s — produce the Blender ladder first" % _glb_dir)
		return
	for base_mm in _bases:
		var dir := _out + "base_%d/" % base_mm
		DirAccess.make_dir_recursive_absolute(dir)
		var height := REF_HEIGHT_M * float(base_mm) / REF_BASE_MM
		_position_camera(height)
		var apx := _apparent_px(height)
		print("[BASESIZE] base %d mm: height %.4f m, cam %.4f m, apparent %d px (%.0f%% of frame)"
			% [base_mm, height, _cam.position.length(), apx, 100.0 * apx / VIEW_PX])
		for f in files:
			var tris: String = str(f).trim_prefix("lvl_").trim_suffix(".glb")
			_log("%d mm — %s tris (%d px)" % [base_mm, tris, apx])
			await _shoot(_glb_dir + str(f), dir + "tris_" + tris + ".png", height)
	_log("DONE — %d tiers × %d bases in %s"
		% [files.size(), _bases.size(), ProjectSettings.globalize_path(_out)])
	# Quit when run from the CLI (batch render); harmless under F6 (closes the scene).
	if not Engine.is_editor_hint():
		await get_tree().create_timer(0.5).timeout
		get_tree().quit()


# Closest sensible inspection distance for a model of the given world height: the player zooms to
# MIN_ZOOM but no closer; a model too big to fit there is backed off until it fills FILL_FRACTION of
# the frame. Below the frame-fill knee (~61 mm base) distance = MIN_ZOOM (apparent size grows with
# base); above it, distance grows so apparent size caps at frame-fill.
func _position_camera(height_m: float) -> void:
	var half_tan := tan(deg_to_rad(CAM_FOV_DEG) * 0.5)
	var fit := height_m / (FILL_FRACTION * 2.0 * half_tan)
	var distance: float = maxf(MIN_ZOOM_M, fit)
	var elev := deg_to_rad(CAM_ELEV_DEG)
	var azim := deg_to_rad(CAM_AZIM_DEG)
	_cam.position = distance * Vector3(
		cos(elev) * sin(azim), sin(elev), cos(elev) * cos(azim))
	_cam.look_at(Vector3.ZERO, Vector3.UP)


# Apparent on-screen height of the model in pixels at the current camera distance.
func _apparent_px(height_m: float) -> int:
	var half_tan := tan(deg_to_rad(CAM_FOV_DEG) * 0.5)
	var visible_h := 2.0 * _cam.position.length() * half_tan
	return int(round(height_m / visible_h * VIEW_PX))


func _ladder_files() -> Array:
	var files: Array = []
	var d := DirAccess.open(_glb_dir)
	if d:
		for f in d.get_files():
			if f.ends_with(".glb"):
				files.append(f)
	files.sort()
	files.reverse()   # high tris → low
	return files


func _shoot(glb: String, out_path: String, height_m: float) -> void:
	var node := _load_glb(glb)
	if node == null:
		return
	var pivot := Node3D.new()
	_viewport.add_child(pivot)
	pivot.add_child(node)
	await get_tree().process_frame
	# Aggregate world AABB + apply the shipped material (override; null keeps embedded).
	var box := AABB()
	var first := true
	var found := false
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		found = true
		if _mat != null:
			mi.material_override = _mat
		var a := mi.global_transform * mi.mesh.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	if not found:
		pivot.queue_free()
		return
	# Scale to the base tier's TRUE world height, center at origin (camera orbits the origin).
	var s: float = height_m / box.size.y
	pivot.scale = Vector3(s, s, s)
	pivot.position = -box.get_center() * s
	await _capture(out_path)
	pivot.queue_free()
	for _i in range(4):
		await get_tree().process_frame


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _capture(path: String) -> void:
	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := _viewport.get_texture().get_image()
	if img != null:
		img.save_png(path)
