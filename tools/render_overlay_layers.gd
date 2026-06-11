extends Node
## Dev tool: GPU verification of the flat-overlay stacking (terrain tiles 1 mm,
## deployment zones 2 mm, objectives 3 mm above the table). Deliberately overlaps all
## three at the same spot and renders from a shallow grazing angle — where coplanar
## layers would z-fight first. Output: renders/overlay_layers.png (+ _top). Not shipped.
##   godot --path . res://tools/render_overlay_layers_runner.tscn

const TABLE_FEET := Vector2(4.0, 4.0)
const SETTLE_FRAMES := 30


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
	env.ambient_light_color = Color(0.75, 0.75, 0.78)
	env.ambient_light_energy = 0.8
	world_env.environment = env
	vp.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-55.0, -30.0, 0.0)
	sun.light_energy = 1.2
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

	# All three layers overlapping: forest tiles in the south band, front-line
	# deployment zones (cover the south band too) and objectives inside both.
	var cells := {}
	for x in range(6, 18):
		for y in range(14, 20):
			cells[Vector2i(x, y)] = overlay.TerrainType.FOREST
	overlay.update_overlay(cells, TABLE_FEET, 0.0)
	overlay.set_deployment_zones(overlay.DeploymentType.FRONT_LINE)
	overlay.update_objectives([
		Vector3(-0.2, 0.0, 0.42), Vector3(0.0, 0.0, 0.42), Vector3(0.2, 0.0, 0.42),
	], [0, 1, 2])

	var cam := Camera3D.new()
	cam.fov = 40.0
	vp.add_child(cam)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://renders"))

	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	# Shallow grazing angle across the overlapping stack (z-fighting reveals here).
	cam.look_at_from_position(Vector3(0.0, 0.05, 1.05), Vector3(0.0, 0.0, 0.3), Vector3.UP)
	await _snap(vp, "res://renders/overlay_layers.png")

	# Top-down for the layer ordering / colors.
	cam.look_at_from_position(Vector3(0.0, 0.9, 0.42), Vector3(0.0, 0.0, 0.41), Vector3.UP)
	await _snap(vp, "res://renders/overlay_layers_top.png")

	get_tree().quit()


func _snap(vp: SubViewport, path: String) -> void:
	for _i in range(8):
		await get_tree().process_frame
	var img := vp.get_texture().get_image()
	img.save_png(path)
	print("LAYERS_RENDERED %s" % path)
