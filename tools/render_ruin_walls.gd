extends Node
## Dev/reference tool: renders the APPROVED ruin-wall look (a 9x9" and a 9x6" ruin) to
## renders/ruin_walls_reference.png so the art can be judged - and the in-game material
## reproduced - without a GPU session. This is the authoritative spec for the shell-wall
## look that scripts/terrain_overlay.gd should adopt (see docs/HANDOFF_RUIN_WALLS.md).
##
## It deliberately mirrors the planned in-game pipeline:
##   * layout = two point-symmetric L-corners (arms = size-1), matching
##     TerrainPrefabs.wall_segments_for() and its "role" taper,
##   * each wall cell = a SHELL (front + back masonry quad + a plain-stone top cap) so it
##     has thickness and the window/opening reveals show stone, not the window texture,
##   * per-cell panel chosen by role: corner = full (random solid/topdmg/opening/window),
##     toward the free end = crumble_* (stepped taper), flipped so the wall steps DOWN to
##     the open end.
##
## Not shipped with the game. Run via the runner scene (software GL works, no GPU needed):
##   xvfb-run -a godot --display-driver x11 --rendering-driver opengl3 \
##     --audio-driver Dummy --path . res://tools/render_ruin_walls_runner.tscn

const OUT := "res://renders/ruin_walls_reference.png"
const TEX_DIR := "res://assets/terrain/props/ruins/"
const GRASS_TEX := "res://assets/terrain/biomes/temperate_grassland.png"
const I := 0.0254          # inches -> metres (matches terrain_overlay.INCHES_TO_METERS)
const TH := 0.4            # wall thickness, inches (shell depth)
const H := 2.5             # wall height, inches (matches WALL_HEIGHT_INCHES)
const CELL_IN := 3.0       # one grid cell, inches (GRID_SIZE_INCHES)

var _nrm: Texture2D = null
var _cache := {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_run.call_deferred()


# === Texture / material =======================================================

## Load a committed .webp straight from its bytes so the exact authored alpha survives
## regardless of the project's texture-import settings (alpha-scissor needs hard edges).
func _load(tex_name: String) -> Texture2D:
	var bytes := FileAccess.get_file_as_bytes(TEX_DIR + tex_name + ".webp")
	var img := Image.new()
	if img.load_webp_from_buffer(bytes) != OK:
		return load(TEX_DIR + tex_name + ".webp") as Texture2D
	return ImageTexture.create_from_image(img)


func _mat(tex_name: String, use_alpha: bool, flip: bool) -> StandardMaterial3D:
	var key := tex_name + ("_a" if use_alpha else "") + ("_f" if flip else "")
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = _load(tex_name)
	m.roughness = 0.93
	m.metallic = 0.0
	m.normal_enabled = true
	m.normal_texture = _nrm
	m.normal_scale = 1.4
	if use_alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if flip:
		# Mirror U so a crumble panel steps down toward the opposite (free) end.
		m.uv1_scale = Vector3(-1.0, 1.0, 1.0)
	_cache[key] = m
	return m


# === Geometry =================================================================

func _quad(parent: Node, size: Vector2, pos: Vector3, rot: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	mi.mesh = q
	mi.material_override = mat
	mi.rotation = rot
	mi.position = pos
	parent.add_child(mi)


## One wall cell as a shell: front + back masonry quad, plus a plain-stone top cap unless the
## panel is a crumble (whose stepped top must stay open). Collision is out of scope here - in
## game the wall stays a full-height Impassable box (see handoff); this is the visual shell.
func _wall(vp: Node, pos: Vector3, rot_y: float, tex_name: String, flip: bool) -> void:
	var is_crumble := tex_name.contains("crumble")
	var use_alpha := tex_name != "solid_a" and tex_name != "solid_b"
	var p := Node3D.new()
	p.position = pos
	p.rotation.y = rot_y
	vp.add_child(p)
	var h := H * I
	var w := CELL_IN * I
	var t := TH * I
	var face := _mat(tex_name, use_alpha, flip)
	var cap := _mat("solid_a", false, false)
	_quad(p, Vector2(w, h), Vector3(0, h / 2.0, t / 2.0), Vector3.ZERO, face)    # front
	_quad(p, Vector2(w, h), Vector3(0, h / 2.0, -t / 2.0), Vector3.ZERO, face)   # back
	if not is_crumble:
		_quad(p, Vector2(w, t), Vector3(0, h, 0), Vector3(-PI / 2.0, 0, 0), cap)  # flat top


func _corner(vp: Node, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(TH * I, H * I, TH * I)
	mi.mesh = box
	mi.material_override = _mat("solid_a", false, false)
	mi.position = pos + Vector3(0, H * I / 2.0, 0)
	vp.add_child(mi)


# === Layout (mirrors TerrainPrefabs.wall_segments_for + _crumble_role) =========

## Random "full" panel: 5% gothic window, 20% doorway opening, else solid/top-damaged.
func _pick_full() -> String:
	var r := _rng.randf()
	if r < 0.05:
		return "window"
	elif r < 0.25:
		return "opening_a"
	return ["solid_a", "solid_b", "topdmg_a"][_rng.randi() % 3]


## Panel for a cell `dist` steps from the corner along an arm of `arm_len` cells. Mirrors
## TerrainPrefabs._crumble_role: corner = full, free-end cells crumble.
func _panel(dist: int, arm_len: int, force_window: bool) -> String:
	if dist == 0:
		return "window" if force_window else _pick_full()
	if arm_len == 2:
		return "crumble_steep"
	if dist == arm_len - 1:
		return "crumble_b"
	if dist == arm_len - 2:
		return "crumble_a"
	return _pick_full()


func _cx(col: int, cells_x: int) -> float:
	return ((col + 0.5) * CELL_IN - cells_x * CELL_IN / 2.0) * I


func _cz(row: int, cells_y: int) -> float:
	return ((row + 0.5) * CELL_IN - cells_y * CELL_IN / 2.0) * I


## A ruin = two point-symmetric L-corners. Crumble flip is constant per arm so each arm
## steps DOWN toward its free end (north/east: no flip; west/south: flip).
func _ruin(vp: Node, off: Vector3, cells_x: int, cells_y: int, force_window: bool) -> void:
	var hx := cells_x * CELL_IN / 2.0 * I
	var hz := cells_y * CELL_IN / 2.0 * I
	var arm_x := cells_x - 1
	var arm_y := cells_y - 1
	# NW corner: north edge (cols 0..X-2, free end +X) + west edge (rows 0..Y-2, free end +Z)
	for c in range(arm_x):
		_wall(vp, off + Vector3(_cx(c, cells_x), 0, -hz), 0.0, _panel(c, arm_x, force_window), false)
	for r in range(arm_y):
		_wall(vp, off + Vector3(-hx, 0, _cz(r, cells_y)), PI / 2.0, _panel(r, arm_y, false), r > 0)
	# SE corner: south edge (cols X-1..1, free end -X) + east edge (rows Y-1..1, free end -Z)
	for k in range(arm_x):
		var col := cells_x - 1 - k
		_wall(vp, off + Vector3(_cx(col, cells_x), 0, hz), 0.0, _panel(k, arm_x, false), k > 0)
	for k2 in range(arm_y):
		var row := cells_y - 1 - k2
		_wall(vp, off + Vector3(hx, 0, _cz(row, cells_y)), PI / 2.0, _panel(k2, arm_y, false), false)
	_corner(vp, off + Vector3(-hx, 0, -hz))
	_corner(vp, off + Vector3(hx, 0, hz))


# === Scene ====================================================================

func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1700, 1000)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	get_tree().root.add_child(vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.6, 0.74)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.57, 0.6)
	env.ambient_light_energy = 0.9
	we.environment = env
	vp.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46.0, -36.0, 0.0)
	sun.light_energy = 1.5
	sun.shadow_enabled = true
	vp.add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.1, 0.8)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	var gtex := load(GRASS_TEX) as Texture2D
	if gtex != null:
		gmat.albedo_texture = gtex
	else:
		gmat.albedo_color = Color(0.32, 0.42, 0.22)
	gmat.roughness = 0.97
	ground.material_override = gmat
	vp.add_child(ground)

	_nrm = _load("normal")
	_rng.seed = 424242
	_ruin(vp, Vector3(-0.26, 0, 0.02), 3, 3, true)   # 9x9" (force a window so it is visible)
	_ruin(vp, Vector3(0.24, 0, 0.0), 3, 2, false)    # 9x6"

	var cam := Camera3D.new()
	cam.fov = 50.0
	vp.add_child(cam)
	cam.look_at_from_position(Vector3(0.0, 0.48, 0.66), Vector3(-0.02, 0.0, -0.04), Vector3.UP)

	for _i in range(30):
		await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))
	var img := vp.get_texture().get_image()
	img.save_png(OUT)
	print("RUIN_WALLS_RENDERED %dx%d -> %s" % [img.get_width(), img.get_height(), OUT])
	get_tree().quit()
