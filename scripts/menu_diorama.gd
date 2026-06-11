class_name MenuDiorama
extends SubViewportContainer
## Live night-battlefield diorama behind the main menu: the production terrain
## renderer (textured ruin shells + war-torn fires + rubble), volumetric trees, a
## shipping container, grass, ground mist and a miniatures vignette under the Night
## lighting preset, framed by a slow long-lens orbit camera with depth of field.
##
## Composition deliberately does NOT use AtmosphereController (it persists every
## change to user://atmosphere.cfg and would clobber the player's in-game choice) —
## it wires LightingController("Night") + AtmosphericClouds + WarAmbience directly,
## exactly like the dev harnesses (tools/render_atmosphere.gd).
##
## Tier gating: PERFORMANCE renders the classic space-skybox-only backdrop; LOW+
## builds the diorama (fires/grass/mist densities self-gate per tier). All asset
## deliveries are progressive — cached R2 panels appear instantly, cold caches show
## the designed fallbacks and upgrade in place. Miniatures load from the local model
## cache ONLY (no network from the menu).

# === Constants ===

enum Mode { AUTO, FORCED, SKY_ONLY }

const TABLE_FEET := Vector2(4.0, 4.0)
const TABLE_METERS := Vector2(1.22, 1.22)
const CELL_M := 3.0 * 0.0254
const GRID_CENTER := 12  # 4x4 ft -> 24x24 grid

const SKYBOX_MATERIAL_PATH := "res://materials/space_skybox.tres"
## Diorama-mode sky boost only — RESTRAINED: the magenta nebula dominates as soon
## as much sky is visible (the full-strength Night values turned the whole screen
## pink in sky-only mode). Sky-only keeps the material's stock values entirely.
const NIGHT_STAR_BRIGHTNESS := 2.4
const NIGHT_NEBULA_INTENSITY := 0.35
const GROUND_SIZE_M := 2.2
const GROUND_COLOR := Color(0.16, 0.18, 0.12)  # dark night mud
const MIST_DENSITY_SCALE := 0.7
const MIST_FADE_IN_S := 3.0
const WAR_VOLUME_OFFSET_DB := -10.0  # menu soundscape is quieter than in-game

## Long-lens orbit: incommensurate sway periods make the drift seamless (no loop pop).
const CAM_FOV := 32.0
const CAM_RADIUS := 0.62
const CAM_HEIGHT_BASE := 0.16
const CAM_HEIGHT_SWAY := 0.015
const CAM_HEIGHT_PERIOD_S := 29.0
const CAM_AZIMUTH_BASE_DEG := 35.0
const CAM_AZIMUTH_SWAY_DEG := 6.0
const CAM_AZIMUTH_PERIOD_S := 36.0
const CAM_H_OFFSET := -0.10          # pushes the subject right, clear of the menu column
const CAM_PIVOT_LIFT_M := 0.05
const PARALLAX_YAW_RAD := 0.014      # ±0.8° mouse parallax
const PARALLAX_PITCH_RAD := 0.009    # ±0.5°
const PARALLAX_LERP_SPEED := 2.5
const SKY_ONLY_DRIFT_RAD_S := 0.012  # classic slow skybox pan (fallback mode)

## Hover reactivity: menu entries nudge the lens (small, slow — felt, not seen).
const FOV_LERP_SPEED := 1.5

## Idle attract mode: the orbit widens to a slow full tour while the UI sleeps.
const ATTRACT_RADIUS := 0.85
const ATTRACT_PERIOD_S := 75.0
const ATTRACT_BLEND_S := 3.0

## Depth of field (cinematic lens): focus on the ruin, soft far rolloff, slight
## near blur so the foreground container reads as a film foreground element.
const DOF_FAR_START_EXTRA_M := 0.18
const DOF_FAR_TRANSITION_M := 0.5
const DOF_NEAR_DISTANCE_M := 0.35
const DOF_NEAR_TRANSITION_M := 0.12
const DOF_BLUR_AMOUNT := 0.06

## Miniatures vignette: curated, cache-only picks (key -> placement). Cell-space
## offsets are relative to the grid; yaw faces the squad toward the ruin. Models are
## scaled to a per-entry target height (AABB-based, like the in-game base fit).
## A faint warm spill light over the squad (reads as firelight reaching them) so the
## minis don't vanish into the night silhouette.
const MINI_LIGHT_CELLS: Array[Vector2] = [Vector2(8.0, 13.8), Vector2(12.6, 13.2)]
const MINI_LIGHT_HEIGHT_M := 0.07
const MINI_LIGHT_ENERGY := 0.3
const MINI_LIGHT_RANGE_M := 0.3
const MINI_LIGHT_COLOR := Color(1.0, 0.72, 0.45)

## Two battle lines in front of the burning ruin: Battle Brothers (west, facing
## east) against Alien Hives (east, facing west). Yaw 0 faces -Z (north); -90 faces
## east, +90 faces west (these GLBs author their front toward +Z).
const MINI_VIGNETTE: Array[Dictionary] = [
	{"faction": "battle_brothers", "unit": "battle brothers", "cell": Vector2(8.4, 13.2), "yaw_deg": 102.0, "height_m": 0.034},
	{"faction": "battle_brothers", "unit": "battle brothers", "cell": Vector2(8.0, 14.0), "yaw_deg": 85.0, "height_m": 0.034},
	{"faction": "battle_brothers", "unit": "master brother", "cell": Vector2(7.6, 13.6), "yaw_deg": 95.0, "height_m": 0.036},
	{"faction": "battle_brothers", "unit": "assault brothers", "cell": Vector2(8.9, 14.5), "yaw_deg": 110.0, "height_m": 0.034},
	{"faction": "battle_brothers", "unit": "heavy exo suit", "cell": Vector2(7.2, 14.3), "yaw_deg": 90.0, "height_m": 0.046},
	{"faction": "battle_brothers", "unit": "apc", "cell": Vector2(6.4, 12.8), "yaw_deg": 120.0, "height_m": 0.052},
	{"faction": "alien_hives", "unit": "assault grunts", "cell": Vector2(11.8, 12.9), "yaw_deg": -96.0, "height_m": 0.036},
	{"faction": "alien_hives", "unit": "shooter grunts", "cell": Vector2(12.4, 13.5), "yaw_deg": -84.0, "height_m": 0.036},
	{"faction": "alien_hives", "unit": "hive warriors", "cell": Vector2(12.9, 12.7), "yaw_deg": -102.0, "height_m": 0.038},
	{"faction": "alien_hives", "unit": "prime warrior", "cell": Vector2(13.3, 13.4), "yaw_deg": -90.0, "height_m": 0.048},
]

# === Signals ===

## Emitted once after the first diorama frame has been drawn (entrance fade gate).
signal first_frame_rendered

# === Exports ===

@export var mode: Mode = Mode.AUTO

# === Private variables ===

var _viewport: SubViewport = null
var _camera: Camera3D = null
var _overlay: Node3D = null
var _war: WarAmbience = null
var _lighting: Node = null
var _diorama_built := false
var _drift_t := 0.0
var _sky_drift := 0.0
var _parallax := Vector2.ZERO
var _pivot := Vector3.ZERO
var _first_frame_emitted := false
var _fov_bias := 0.0
var _attract := false
var _attract_blend := 0.0

# === Lifecycle ===

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_setup()
	GraphicsSettings.settings_applied.connect(_on_graphics_settings_applied)


func _process(delta: float) -> void:
	if not is_instance_valid(_camera):
		return
	var vp: Vector2 = get_viewport_rect().size
	var m: Vector2 = get_viewport().get_mouse_position()
	var target := Vector2(m.x / maxf(vp.x, 1.0) - 0.5, m.y / maxf(vp.y, 1.0) - 0.5)
	_parallax = _parallax.lerp(target, delta * PARALLAX_LERP_SPEED)

	if not _diorama_built:
		# Sky-only fallback: the classic slow skybox pan + parallax.
		_sky_drift += delta * SKY_ONLY_DRIFT_RAD_S
		_camera.rotation = Vector3(-_parallax.y * 0.06, _sky_drift + _parallax.x * 0.10, 0.0)
		return

	_drift_t += delta
	_attract_blend = move_toward(_attract_blend, 1.0 if _attract else 0.0, delta / ATTRACT_BLEND_S)
	var azimuth := deg_to_rad(CAM_AZIMUTH_BASE_DEG) \
			+ deg_to_rad(CAM_AZIMUTH_SWAY_DEG) * sin(TAU * _drift_t / CAM_AZIMUTH_PERIOD_S) \
			+ _attract_blend * TAU * _drift_t / ATTRACT_PERIOD_S
	var radius := lerpf(CAM_RADIUS, ATTRACT_RADIUS, _attract_blend)
	var height := CAM_HEIGHT_BASE + CAM_HEIGHT_SWAY * sin(TAU * _drift_t / CAM_HEIGHT_PERIOD_S)
	_camera.position = _pivot + Vector3(cos(azimuth) * radius, height, sin(azimuth) * radius)
	_camera.look_at(_pivot, Vector3.UP)
	_camera.rotation.y += -_parallax.x * PARALLAX_YAW_RAD
	_camera.rotation.x += -_parallax.y * PARALLAX_PITCH_RAD
	_camera.fov = lerpf(_camera.fov, CAM_FOV + _fov_bias, delta * FOV_LERP_SPEED)

# === Public ===

## Pure gating rule (headless-testable): the diorama needs at least the LOW tier.
static func should_build_diorama(tier: int) -> bool:
	return tier > GraphicsSettings.QualityPreset.PERFORMANCE


## Quiet battlefield soundscape (distant war one-shots + fire crackle at the fires).
func set_ambience_enabled(on: bool) -> void:
	if _war != null:
		_war.set_war_sounds_enabled(on)


## The diorama's lighting controller (the menu Settings window binds against it).
func get_lighting_controller() -> Node:
	return _lighting


## Hover reactivity: small FOV nudge (negative = push-in) eased in _process.
func set_fov_bias(bias_deg: float) -> void:
	_fov_bias = bias_deg


## Idle attract mode: widens the orbit into a slow full tour (and back).
func set_attract(on: bool) -> void:
	_attract = on

# === Private: setup ===

func _setup() -> void:
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var tier: int = GraphicsSettings.current_preset
	_viewport.msaa_3d = Viewport.MSAA_2X if tier >= GraphicsSettings.QualityPreset.HIGH else Viewport.MSAA_DISABLED
	# LOW renders the diorama at half resolution (the night mood hides it well).
	stretch_shrink = 2 if tier == GraphicsSettings.QualityPreset.LOW else 1

	var world_env := _build_environment()
	_viewport.add_child(world_env)

	_camera = Camera3D.new()
	_camera.fov = CAM_FOV
	_viewport.add_child(_camera)

	# Sun + lighting controller exist in BOTH modes, so the menu Settings window can
	# always bind its lighting section (sky-only just has nothing lit to show).
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.shadow_enabled = tier >= GraphicsSettings.QualityPreset.MEDIUM
	_viewport.add_child(sun)
	_lighting = load("res://scripts/lighting_controller.gd").new()
	_viewport.add_child(_lighting)
	_lighting.initialize(sun, world_env, null)
	_lighting.apply_preset("Night")

	if _diorama_active():
		_build_diorama(tier)
	_await_first_frame()


## True when this menu instance should build the full diorama. AUTO requires the
## scene to be the live current_scene — gdUnit's scene_runner adds the menu under
## /root directly, so tests never trigger R2-backed 3D builds (same guard as the
## menu's update check).
func _diorama_active() -> bool:
	match mode:
		Mode.FORCED:
			return true
		Mode.SKY_ONLY:
			return false
		_:
			var scene_root: Node = owner if owner != null else self
			return should_build_diorama(GraphicsSettings.current_preset) \
					and get_tree().current_scene == scene_root


func _build_environment() -> WorldEnvironment:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	# Duplicate: the in-game sky shares this resource and must not inherit menu tweaks.
	var sky_material: ShaderMaterial = load(SKYBOX_MATERIAL_PATH).duplicate()
	if _diorama_active():
		# Mild night boost; the battlefield fills most of the frame and balances it.
		sky_material.set_shader_parameter("star_brightness", NIGHT_STAR_BRIGHTNESS)
		sky_material.set_shader_parameter("nebula_intensity", NIGHT_NEBULA_INTENSITY)
	sky.sky_material = sky_material
	env.sky = sky
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.12
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	return world_env


func _build_diorama(_tier: int) -> void:
	_diorama_built = true

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE_M, GROUND_SIZE_M)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = GROUND_COLOR
	ground_mat.roughness = 0.97
	ground.material_override = ground_mat
	_viewport.add_child(ground)

	# Battlefield: hero ruin + forest backdrop + foreground container, then fires.
	_overlay = load("res://scripts/terrain_overlay.gd").new()
	_viewport.add_child(_overlay)
	var segments: Array = []
	# Camera sits SE looking NW: backdrop content lives in the north/west cells,
	# the battle lines in the open SE foreground.
	segments.append_array(TerrainPrefabs.wall_segments_for("ruine_9x9", Vector2i(9, 10)))
	segments.append_array(TerrainPrefabs.wall_segments_for("ruine_9x6", Vector2i(4, 7)))
	segments.append_array(TerrainPrefabs.wall_segments_for("ruine_9x6", Vector2i(13, 7), 1))
	_overlay.update_wall_models(segments, TABLE_FEET, 0.0)
	var objects: Array = []
	objects.append_array(TerrainPrefabs.decoration_for("wald_9x9", Vector2i(6, 4)))
	objects.append_array(TerrainPrefabs.decoration_for("wald_9x9", Vector2i(3, 9)))
	objects.append_array(TerrainPrefabs.decoration_for("blocker_6x3", Vector2i(7, 12), null, 90))
	_overlay.update_placed_objects(objects, TABLE_FEET, 0.0)
	_overlay.set_fires_enabled(true)

	var grass := GrassField.new()
	_viewport.add_child(grass)
	grass.set_table_size(TABLE_METERS)
	grass.set_biome("temperate_grassland")

	var clouds: Node3D = load("res://scripts/atmospheric_clouds.gd").new()
	_viewport.add_child(clouds)
	clouds.set_table_size(TABLE_METERS)
	clouds.set_density_scale(MIST_DENSITY_SCALE)
	clouds.fade_in(MIST_FADE_IN_S)

	_build_minis()

	# Quiet battlefield soundscape. Child of the viewport: the 3D one-shots and the
	# crackle emitters must live in the diorama's World3D (its camera is the listener).
	_war = WarAmbience.new()
	_viewport.add_child(_war)
	_war.set_volume_offset_db(WAR_VOLUME_OFFSET_DB)
	_war.set_war_sounds_enabled(true)
	_overlay.fires_rebuilt.connect(func() -> void:
		_war.update_fire_crackle(_overlay.get_fire_positions()))
	_war.update_fire_crackle(_overlay.get_fire_positions())

	# Camera pivot + cinematic lens focused on the ruin.
	_pivot = _cell_to_local(Vector2(10.5, 11.5)) + Vector3(0.0, CAM_PIVOT_LIFT_M, 0.0)
	var attributes := CameraAttributesPractical.new()
	attributes.dof_blur_far_enabled = true
	attributes.dof_blur_far_distance = CAM_RADIUS + DOF_FAR_START_EXTRA_M
	attributes.dof_blur_far_transition = DOF_FAR_TRANSITION_M
	attributes.dof_blur_near_enabled = true
	attributes.dof_blur_near_distance = DOF_NEAR_DISTANCE_M
	attributes.dof_blur_near_transition = DOF_NEAR_TRANSITION_M
	attributes.dof_blur_amount = DOF_BLUR_AMOUNT
	_camera.attributes = attributes
	_camera.h_offset = CAM_H_OFFSET
	_process(0.0)  # place the camera before the first visible frame

# === Private: miniatures vignette ===

## Places the curated minis if (and only if) their GLBs are already in the local
## model cache — the menu never downloads models. Cold cache = no minis, no error.
func _build_minis() -> void:
	var library := ModelLibrary.new()
	_viewport.add_child(library)
	var placed := 0
	for entry in MINI_VIGNETTE:
		var path: String = library.get_cached_path(entry["faction"], entry["unit"])
		if path.is_empty():
			continue
		var model := _load_glb(path)
		if model == null:
			continue
		# Fit returns the grounding offset; apply it ON TOP of the cell position
		# (assigning position afterwards would wipe the lift and sink the mini).
		var ground_offset := _fit_to_height(model, entry["height_m"])
		model.position = _cell_to_local(entry["cell"]) + ground_offset
		model.rotation.y = deg_to_rad(entry["yaw_deg"])
		_viewport.add_child(model)
		placed += 1

	if placed > 0:
		for cell in MINI_LIGHT_CELLS:
			var spill := OmniLight3D.new()
			spill.position = _cell_to_local(cell) + Vector3(0.0, MINI_LIGHT_HEIGHT_M, 0.0)
			spill.light_color = MINI_LIGHT_COLOR
			spill.light_energy = MINI_LIGHT_ENERGY
			spill.omni_range = MINI_LIGHT_RANGE_M
			spill.shadow_enabled = false
			_viewport.add_child(spill)


## Runtime glTF load (user:// paths can't go through ResourceLoader).
func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


## Uniformly scales a model so its AABB height matches the target. Returns the
## position offset that centres it on x/z and puts its feet on y=0.
func _fit_to_height(model: Node3D, target_height_m: float) -> Vector3:
	var aabb := _combined_aabb(model)
	if aabb.size.y <= 0.0001:
		return Vector3.ZERO
	var fit := target_height_m / aabb.size.y
	model.scale = Vector3.ONE * fit
	var center := aabb.get_center()
	return Vector3(-center.x * fit, -aabb.position.y * fit, -center.z * fit)


## Model-space AABB with ALL nested transforms accumulated (GLB scenes nest meshes
## under armature/intermediate nodes; ignoring those offsets mis-grounds the minis).
func _combined_aabb(node: Node3D) -> AABB:
	return _accumulate_aabb(node, Transform3D.IDENTITY, AABB(), false)["aabb"]


func _accumulate_aabb(node: Node, xform: Transform3D, aabb: AABB, found: bool) -> Dictionary:
	if node is Node3D:
		xform = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_aabb: AABB = xform * (node as MeshInstance3D).get_aabb()
		aabb = mesh_aabb if not found else aabb.merge(mesh_aabb)
		found = true
	for child in node.get_children():
		var result := _accumulate_aabb(child, xform, aabb, found)
		aabb = result["aabb"]
		found = result["found"]
	return {"aabb": aabb, "found": found}

# === Private: helpers ===

func _cell_to_local(cell: Vector2) -> Vector3:
	return Vector3((cell.x - GRID_CENTER) * CELL_M, 0.0, (cell.y - GRID_CENTER) * CELL_M)


func _await_first_frame() -> void:
	if _first_frame_emitted:
		return
	RenderingServer.frame_post_draw.connect(func() -> void:
		if not _first_frame_emitted:
			_first_frame_emitted = true
			first_frame_rendered.emit(),
		CONNECT_ONE_SHOT)


## Live quality switches: rebuild when crossing the diorama boundary; inner systems
## (fires, grass, mist tiers) re-gate themselves.
func _on_graphics_settings_applied(_preset_name: String) -> void:
	if mode != Mode.AUTO:
		return
	if _diorama_built == _diorama_active():
		return
	for child in get_children():
		child.queue_free()
	_viewport = null
	_camera = null
	_overlay = null
	_war = null
	_lighting = null
	_diorama_built = false
	_first_frame_emitted = true  # no second entrance fade on a live rebuild
	_setup()
