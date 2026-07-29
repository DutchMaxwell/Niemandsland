extends SceneTree
## QA tool: perspective render of committed chalk trails + inch stamps on a LIGHT table
## (NML-234). The maintainer's finding was that the stamp is tiny, thin-stroked and white
## on light ground — this capture reproduces exactly that viewing situation (player-angle
## camera, bright surface) so before/after crops prove the readability fix.
##
## Usage (needs a real renderer — NOT --headless):
##   godot --path <project> -s res://tools/chalk_stamp_render.gd -- <out.png>

const IMAGE_SIZE: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 12
## Bright bone/sand table — the worst-case background from the finding.
const TABLE_COLOR: Color = Color(0.82, 0.78, 0.68)


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1:
		push_error("Usage: -s res://tools/chalk_stamp_render.gd -- <out.png>")
		quit(1)
		return
	var out_path: String = args[0]

	var viewport := SubViewport.new()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	_add_environment(world)

	var trails := MoveTrails.new()
	world.add_child(trails)

	# Two committed moves, one per player colour: a straight advance and a curved arc,
	# 25 mm bases. Committed trails persist until activation end, so the stamps hold.
	var straight := PackedVector2Array([Vector2(-0.16, 0.06), Vector2(0.05, 0.02)])
	trails.commit_trail(1, "u1", "Test Unit A", 0, straight, 0.0125, 1, 1)
	var arc := PackedVector2Array([
		Vector2(-0.10, -0.10), Vector2(-0.02, -0.13), Vector2(0.07, -0.11), Vector2(0.13, -0.05),
	])
	trails.commit_trail(2, "u2", "Test Unit B", 0, arc, 0.0125, 1, 2)

	_add_camera(world)

	for i in range(SETTLE_FRAMES):
		await process_frame
	var img: Image = viewport.get_texture().get_image()
	var err: int = img.save_png(out_path)
	if err != OK:
		push_error("chalk_stamp_render: save_png failed (%d) for %s" % [err, out_path])
		quit(1)
		return
	print("chalk_stamp_render: wrote %s" % out_path)
	quit(0)


func _add_environment(world: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.58, 0.62)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 1.0, 1.0)
	env.ambient_light_energy = 1.2
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-70.0, 25.0, 0.0)
	sun.light_energy = 1.3
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(2.0, 2.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = TABLE_COLOR
	gmat.roughness = 1.0
	ground.material_override = gmat
	world.add_child(ground)


func _add_camera(world: Node3D) -> void:
	# Player-angle perspective view, roughly how the table is read during a game.
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.42, 0.38)
	cam.rotation_degrees = Vector3(-48.0, 0.0, 0.0)
	cam.fov = 50.0
	world.add_child(cam)
	cam.make_current()
