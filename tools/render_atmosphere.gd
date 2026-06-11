extends Node
## Dev tool: GPU verification of the battlefield atmosphere — war-torn ruin fires
## (flames, smoke, flickering light), the Night preset and the Rain preset with a
## forced lightning flash, rendered through the REAL controllers
## (terrain_overlay fires + lighting_controller + atmosphere_controller).
## Output: renders/atmosphere_fires.png / _night.png / _rain.png. Not shipped.
##   godot --path . res://tools/render_atmosphere_runner.tscn

const TABLE_FEET := Vector2(4.0, 4.0)
const FETCH_TIMEOUT_FRAMES := 1800
const SETTLE_FRAMES := 40
const RAIN_SETTLE_FRAMES := 160  # let the amount_ratio fade + drops fall


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1700, 1000)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_tree().root.add_child(vp)

	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.35, 0.42, 0.55)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.7, 0.7, 0.72)
	env.ambient_light_energy = 0.4
	env.glow_enabled = true
	world_env.environment = env
	vp.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	vp.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(1.4, 1.4)
	ground.mesh = plane
	var ground_mat := StandardMaterial3D.new()
	ground_mat.albedo_color = Color(0.32, 0.42, 0.24)
	ground_mat.roughness = 0.97
	ground.material_override = ground_mat
	vp.add_child(ground)

	var overlay: Node3D = load("res://scripts/terrain_overlay.gd").new()
	vp.add_child(overlay)

	var lighting: Node = load("res://scripts/lighting_controller.gd").new()
	vp.add_child(lighting)
	lighting.initialize(sun, world_env, null)

	var atmosphere: Node = load("res://scripts/atmosphere_controller.gd").new()
	vp.add_child(atmosphere)
	atmosphere.initialize(lighting, world_env, null, overlay)
	atmosphere.set_table_size(TABLE_FEET * 0.3048)

	# A 3x3 ruin + fires.
	var segments: Array = []
	segments.append_array(TerrainPrefabs.wall_segments_for("ruine_9x9", Vector2i(9, 10)))
	overlay.update_wall_models(segments, TABLE_FEET, 0.0)
	var frames := 0
	while not overlay._ruin_panels_ready() and frames < FETCH_TIMEOUT_FRAMES:
		await get_tree().process_frame
		frames += 1
	print("RUINS_READY=%s after %d frames" % [overlay._ruin_panels_ready(), frames])
	overlay.set_fires_enabled(true)
	print("FIRES=%d (positions=%d)" % [overlay._fire_instances.size(), overlay.get_fire_positions().size()])

	var cam := Camera3D.new()
	cam.fov = 45.0
	vp.add_child(cam)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))

	# Ruin centre: cells 9-11 x 10-12 on the 24-grid.
	var ruin := Vector3((10.0 - 12 + 0.5) * 3.0 * 0.0254, 0.0, (11.0 - 12 + 0.5) * 3.0 * 0.0254)

	# 1) Day closeup of a burning wall.
	cam.look_at_from_position(ruin + Vector3(0.16, 0.1, 0.2), ruin + Vector3(0, 0.02, 0), Vector3.UP)
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await _snap(vp, "res://renders/atmosphere_fires.png")

	# 2) Night preset.
	atmosphere.apply_atmosphere("Night", true)
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	await _snap(vp, "res://renders/atmosphere_night.png")

	# 3) Rain preset with a forced lightning flash mid-capture.
	atmosphere.apply_atmosphere("Rain", true)
	cam.look_at_from_position(ruin + Vector3(0.3, 0.3, 0.42), ruin, Vector3.UP)
	for _i in range(RAIN_SETTLE_FRAMES):
		await get_tree().process_frame
	atmosphere._rain.flash_lightning()
	for _i in range(3):
		await get_tree().process_frame
	await _snap(vp, "res://renders/atmosphere_rain.png")

	get_tree().quit()


func _snap(vp: SubViewport, path: String) -> void:
	for _i in range(8):
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	img.save_png(path)
	print("ATMOSPHERE_RENDERED %s" % path)
