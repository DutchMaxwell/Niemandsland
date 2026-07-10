extends SceneTree
## QA tool: top-down comparison render for oval-base mount orientation (QA round 4).
##
## Builds the serpent units side by side with the REAL fit + orientation pipeline
## (_get_model_aabb / _get_body_aabb / _compute_model_fit / _align_to_oval_long_axis) on their
## in-game oval bases (the AF parse puts the long side into DEPTH/Z), and captures a straight
## TOP-DOWN orthographic view: every model's length must lie along its base's LONG axis
## (vertical in the image). An X-long serpent export that lies horizontally (across the short
## side) is the bug this render proves fixed.
##
## Usage (needs a real renderer — a virtual Wayland compositor works; NOT --headless):
##   godot --path <project> -s res://tools/mount_orientation_render.gd -- \
##     <snake_riders.glb> <champion_snake.glb> <great_snakes.glb> <out.png>

const IMAGE_SIZE: Vector2i = Vector2i(1600, 900)
const SETTLE_FRAMES: int = 12
const BASE_THICKNESS_M: float = 0.003
const BACKGROUND_COLOR: Color = Color(0.13, 0.14, 0.16)
const BASE_COLOR: Color = Color(0.24, 0.35, 0.55)
const LABEL_COLOR: Color = Color(0.92, 0.92, 0.92)

## In-game oval dims: width (X, short) / depth (Z, long — the AF parse always puts the long side
## into depth). snake riders + great snakes 90x52 units; champion mount = Royal Snake 75x46.
const CASES: Array = [
	{"label": "snake riders (90x52)", "long_mm": 90, "short_mm": 52, "tough": 3, "is_mount": false,
		"width_mm": 52, "depth_mm": 90, "x": 0.0},
	{"label": "champion#greatweapon+snake (75x46)", "long_mm": 75, "short_mm": 46, "tough": 3, "is_mount": true,
		"width_mm": 46, "depth_mm": 75, "x": 0.17},
	{"label": "great snakes (90x52)", "long_mm": 90, "short_mm": 52, "tough": 3, "is_mount": false,
		"width_mm": 52, "depth_mm": 90, "x": 0.34},
]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < CASES.size() + 1:
		push_error("Usage: -s res://tools/mount_orientation_render.gd -- <snake_riders.glb> <champion_snake.glb> <great_snakes.glb> <out.png>")
		quit(1)
		return
	var out_path: String = args[CASES.size()]

	# Fixed-size SubViewport: deterministic capture resolution regardless of the window size the
	# (virtual) compositor grants.
	var viewport := SubViewport.new()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	_add_environment(world)

	var mgr: OPRArmyManager = OPRArmyManager.new()
	for i in range(CASES.size()):
		var c: Dictionary = CASES[i]
		if not _add_model(world, mgr, args[i], c):
			push_error("mount_orientation_render: failed to load %s" % args[i])
			quit(1)
			return
		_add_label(world, str(c["label"]), Vector3(float(c["x"]), 0.01, -0.085))
	mgr.free()

	_add_label(world, "top-down: every model's length must run along its oval's LONG axis (vertical)",
		Vector3(0.17, 0.01, 0.105))
	_add_camera(world)

	for i in range(SETTLE_FRAMES):
		await process_frame
	var img: Image = viewport.get_texture().get_image()
	var err: int = img.save_png(out_path)
	if err != OK:
		push_error("mount_orientation_render: save_png failed (%d) for %s" % [err, out_path])
		quit(1)
		return
	print("mount_orientation_render: wrote %s" % out_path)
	quit(0)


## Builds one unit (oval base + fitted, ORIENTED GLB) at its case slot. false on load failure.
func _add_model(world: Node3D, mgr: OPRArmyManager, glb_path: String, c: Dictionary) -> bool:
	var glb: Node3D = mgr._instantiate_model(glb_path)
	if glb == null:
		return false
	var aabb: AABB = mgr._get_model_aabb(glb)
	var body: AABB = mgr._get_body_aabb(glb)
	var fit: Dictionary = mgr._compute_model_fit(aabb, int(c["long_mm"]), int(c["tough"]), 0.0,
		int(c["short_mm"]), false, body, bool(c["is_mount"]))
	var scale: float = float(fit["scale"])

	var unit := Node3D.new()
	unit.position = Vector3(float(c["x"]), 0.0, 0.0)
	world.add_child(unit)

	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.height = BASE_THICKNESS_M
	base_mesh.top_radius = 0.5
	base_mesh.bottom_radius = 0.5
	base.mesh = base_mesh
	base.scale = Vector3(float(c["width_mm"]) * 0.001, 1.0, float(c["depth_mm"]) * 0.001)
	base.position.y = BASE_THICKNESS_M / 2.0
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = BASE_COLOR
	base_mat.roughness = 0.7
	base.material_override = base_mat
	unit.add_child(base)

	glb.scale = Vector3(scale, scale, scale)
	glb.position.y = float(fit["y_offset"])
	mgr._align_to_oval_long_axis(glb, aabb, true,
		float(c["width_mm"]) * 0.001, float(c["depth_mm"]) * 0.001, false)
	mgr._brighten_trellis_materials(glb)
	unit.add_child(glb)
	return true


func _add_environment(world: Node3D) -> void:
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
	sun.rotation_degrees = Vector3(-75.0, 20.0, 0.0)
	sun.light_energy = 1.4
	world.add_child(sun)

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(3.0, 3.0)
	ground.mesh = plane
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.30, 0.29, 0.27)
	gmat.roughness = 1.0
	ground.material_override = gmat
	world.add_child(ground)


## A flat label lying on the ground plane (readable from the top-down camera).
func _add_label(world: Node3D, text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.pixel_size = 0.00016
	label.modulate = LABEL_COLOR
	label.outline_size = 8
	label.position = pos
	label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)  # face straight up, toward the camera
	world.add_child(label)


func _add_camera(world: Node3D) -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Straight top-down: forward = -Y, screen-up = world +Z (the ovals' LONG axis is vertical).
	# Vertical extent 0.26 m at 16:9 → ~0.46 m horizontal: frames the three ovals with margin.
	cam.size = 0.26
	cam.position = Vector3(0.17, 0.8, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	world.add_child(cam)
	cam.make_current()
