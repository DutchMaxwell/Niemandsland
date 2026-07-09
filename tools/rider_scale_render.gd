extends SceneTree
## QA tool: offscreen comparison render for the rider-constant mount scale (QA round 3).
##
## Builds the foot Royal Champion, the steed champion and the flying-beast champion side by side
## using the REAL fit pipeline (_get_model_aabb / _get_body_aabb / _compute_model_fit /
## _align_to_oval_long_axis) with the exact spawn parameters of the QA list, and draws a vertical
## measure bar spanning each model's rider `body` extent — the acceptance criterion made visible:
## all three bars must be the same length (±5%), wherever the rider sits (a rider on a mount is
## HIGHER, but not BIGGER). An ORTHOGRAPHIC camera keeps lengths comparable (no perspective).
##
## Usage (needs a real renderer — a virtual Wayland compositor works; NOT --headless):
##   godot --path <project> -s res://tools/rider_scale_render.gd -- \
##     <foot.glb> <steed.glb> <flyingbeast.glb> <out.png>

const IMAGE_SIZE: Vector2i = Vector2i(1600, 900)
## Frames to let the renderer settle (material/mipmap upload) before the capture.
const SETTLE_FRAMES: int = 12
const BASE_THICKNESS_M: float = 0.003
const BACKGROUND_COLOR: Color = Color(0.13, 0.14, 0.16)
const BASE_COLOR: Color = Color(0.24, 0.35, 0.55)
const LINE_COLOR: Color = Color(0.95, 0.25, 0.2)
const LABEL_COLOR: Color = Color(0.92, 0.92, 0.92)

## The three cases, mirroring tools/rider_scale_check.gd (QA list LlY4ue1_JOKN).
const CASES: Array = [
	{"label": "foot champion", "long_mm": 25, "short_mm": -1, "tough": 3, "is_mount": false,
		"oval": false, "width_mm": 25, "depth_mm": 25, "x": 0.0},
	{"label": "#greatweapon+steed", "long_mm": 60, "short_mm": 35, "tough": 3, "is_mount": true,
		"oval": true, "width_mm": 60, "depth_mm": 35, "x": 0.14},
	{"label": "#flyingbeast+greatweapon", "long_mm": 160, "short_mm": 122, "tough": 18, "is_mount": true,
		"oval": true, "width_mm": 160, "depth_mm": 122, "x": 0.38},
]


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < CASES.size() + 1:
		push_error("Usage: -s res://tools/rider_scale_render.gd -- <foot.glb> <steed.glb> <flyingbeast.glb> <out.png>")
		quit(1)
		return
	var out_path: String = args[CASES.size()]

	# Render into a fixed-size SubViewport: the capture resolution is deterministic regardless of
	# whatever window size the (virtual) compositor grants the main window.
	var viewport := SubViewport.new()
	viewport.size = IMAGE_SIZE
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	_add_environment(world)

	var mgr: OPRArmyManager = OPRArmyManager.new()
	var foot_body_mm: float = 0.0
	for i in range(CASES.size()):
		var c: Dictionary = CASES[i]
		var m: Dictionary = _add_model(world, mgr, args[i], c)
		if m.is_empty():
			push_error("rider_scale_render: failed to load %s" % args[i])
			quit(1)
			return
		var body_mm: float = float(m["body_h"]) * 1000.0
		if i == 0:
			foot_body_mm = body_mm
		var label_text: String = "%s\nrider body %.1f mm (%.2fx foot)" % [c["label"], body_mm, body_mm / foot_body_mm]
		_add_label(world, label_text, Vector3(float(c["x"]), 0.15, 0.0))
		# The measure bar: rider body bottom -> top, next to the model. Equal bars == the hard rule.
		_add_measure_bar(world, float(c["x"]) + float(c["long_mm"]) * 0.0005 + 0.012,
			float(m["body_bottom"]), float(m["body_top"]))
	mgr.free()

	_add_label(world, "rider-constant scale: every rider body bar must match the foot bar (+-5%)",
		Vector3(0.19, 0.23, 0.0))
	_add_camera(world)

	for i in range(SETTLE_FRAMES):
		await process_frame
	var img: Image = viewport.get_texture().get_image()
	var err: int = img.save_png(out_path)
	if err != OK:
		push_error("rider_scale_render: save_png failed (%d) for %s" % [err, out_path])
		quit(1)
		return
	print("rider_scale_render: wrote %s (foot body height %.2f mm)" % [out_path, foot_body_mm])
	quit(0)


## Builds one unit (base + fitted GLB) at its case slot; returns {body_h, body_bottom, body_top}
## (world metres — body_h is the rider/body EXTENT, the acceptance metric), or {} on load failure.
func _add_model(world: Node3D, mgr: OPRArmyManager, glb_path: String, c: Dictionary) -> Dictionary:
	var glb: Node3D = mgr._instantiate_model(glb_path)
	if glb == null:
		return {}
	var aabb: AABB = mgr._get_model_aabb(glb)
	var body: AABB = mgr._get_body_aabb(glb)
	var fit: Dictionary = mgr._compute_model_fit(aabb, int(c["long_mm"]), int(c["tough"]), 0.0,
		int(c["short_mm"]), false, body, bool(c["is_mount"]))
	var scale: float = float(fit["scale"])

	var unit := Node3D.new()
	unit.position = Vector3(float(c["x"]), 0.0, 0.0)
	world.add_child(unit)

	# Base plate, same construction as the spawn path (oval = unit cylinder scaled to width/depth).
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.height = BASE_THICKNESS_M
	if bool(c["oval"]):
		base_mesh.top_radius = 0.5
		base_mesh.bottom_radius = 0.5
		base.scale = Vector3(float(c["width_mm"]) * 0.001, 1.0, float(c["depth_mm"]) * 0.001)
	else:
		base_mesh.top_radius = float(c["long_mm"]) * 0.0005
		base_mesh.bottom_radius = float(c["long_mm"]) * 0.0005
	base.mesh = base_mesh
	base.position.y = BASE_THICKNESS_M / 2.0
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = BASE_COLOR
	base_mat.roughness = 0.7
	base.material_override = base_mat
	unit.add_child(base)

	glb.scale = Vector3(scale, scale, scale)
	glb.position.y = float(fit["y_offset"])
	mgr._align_to_oval_long_axis(glb, aabb, bool(c["oval"]),
		float(c["width_mm"]) * 0.001, float(c["depth_mm"]) * 0.001, false)
	mgr._brighten_trellis_materials(glb)
	unit.add_child(glb)

	var body_box: AABB = body if body.size.y > 0.0 else aabb
	return {
		"body_h": body_box.size.y * scale,
		"body_bottom": float(fit["y_offset"]) + body_box.position.y * scale,
		"body_top": float(fit["y_offset"]) + (body_box.position.y + body_box.size.y) * scale,
	}


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
	sun.rotation_degrees = Vector3(-52.0, 28.0, 0.0)
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


## A thin vertical emissive measure bar spanning a rider body's world extent, placed next to its
## model. All three bars visually equal == the acceptance criterion.
func _add_measure_bar(world: Node3D, x: float, bottom_y: float, top_y: float) -> void:
	var bar := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.0012, maxf(0.0001, top_y - bottom_y), 0.0012)
	bar.mesh = box
	bar.position = Vector3(x, (bottom_y + top_y) / 2.0, 0.1)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = LINE_COLOR
	mat.emission_enabled = true
	mat.emission = LINE_COLOR
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar.material_override = mat
	world.add_child(bar)


func _add_label(world: Node3D, text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 40
	label.pixel_size = 0.00018
	label.modulate = LABEL_COLOR
	label.outline_size = 8
	label.position = pos
	world.add_child(label)


func _add_camera(world: Node3D) -> void:
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# Vertical extent 0.34 m at 16:9 → ~0.60 m horizontal: frames the lineup incl. the 160mm base.
	cam.size = 0.34
	cam.position = Vector3(0.20, 0.12, 0.9)
	world.add_child(cam)
	cam.make_current()
