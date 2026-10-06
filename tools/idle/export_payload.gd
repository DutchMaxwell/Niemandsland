extends SceneTree
## Offline converter for the proven real-idle GLBs. No synthetic weights and no network.
## godot --headless --path . -s res://tools/idle/export_payload.gd -- jobs.json

const FRAMES := 216
const FPS := 24.0
var failures: Array = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1:
		push_error("Expected jobs.json")
		quit(2)
		return
	var jobs: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	for job: Dictionary in jobs:
		await _export(job)
	print("IDLE_EXPORT_COMPLETE failures=", failures)
	quit(0 if failures.is_empty() else 1)

func _fail(job: Dictionary, reason: String) -> void:
	failures.append([job.key, reason])
	push_error("Idle export %s: %s" % [job.key, reason])

func _rel(node: Node3D, scene: Node3D) -> Transform3D:
	return scene.global_transform.affine_inverse() * node.global_transform

func _export(job: Dictionary) -> void:
	if not preload("idle_families.gd").allows(str(job.key), int(job.tail_bones)):
		_fail(job, "Only listed idle families with their proven tail-bone count are allowed")
		return
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(job.source, state) != OK:
		_fail(job, "Cannot load real idle GLB")
		return
	var scene := doc.generate_scene(state) as Node3D
	root.add_child(scene)
	var players := scene.find_children("*", "AnimationPlayer", true, false)
	if players.size() != 1:
		_fail(job, "Expected one real AnimationPlayer")
		scene.free()
		return
	var player := players[0] as AnimationPlayer
	var names := player.get_animation_list()
	var clip := ""
	for candidate in names:
		if candidate != "RESET":
			clip = candidate
	if clip.is_empty() or absf(player.get_animation(clip).length - FRAMES / FPS) > 0.1:
		_fail(job, "Expected the proven nine-second real idle")
		scene.free()
		return
	player.play(clip)
	player.pause()
	var ground := Transform3D(Basis(), Vector3(0, -float(job.feet_z), 0))
	var palette: Array = []
	var records: Array = []
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var frame := ground * _rel(mi, scene)
		var record := {"mi": mi, "frame": frame, "offset": palette.size(), "surfaces": []}
		if mi.skin != null:
			var skeleton := mi.get_node(mi.skeleton) as Skeleton3D
			for i in mi.skin.get_bind_count():
				var bone := skeleton.find_bone(mi.skin.get_bind_name(i)) if not mi.skin.get_bind_name(i).is_empty() else mi.skin.get_bind_bone(i)
				if bone < 0:
					_fail(job, "Unresolved bone binding")
					scene.free()
					return
				palette.append({"skeleton": skeleton, "bone": bone,
					"bind": mi.skin.get_bind_pose(i), "inverse_frame": frame.affine_inverse()})
		else:
			palette.append({"node": mi, "inverse_frame": frame.affine_inverse()})
		records.append(record)
	if palette.size() > 256:
		_fail(job, "Palette exceeds u8 joint index capacity")
		scene.free()
		return
	var packed := preload("export_mesh.gd").pack(records, job)
	if packed.is_empty():
		_fail(job, "Cannot pack real joint attributes")
		scene.free()
		return
	var output_mesh: ArrayMesh = packed.mesh
	var material_entries: Array = packed.materials
	var points: Array = packed.points
	var image := Image.create_empty(palette.size() * 3, FRAMES, false, Image.FORMAT_RGBAF)
	var bounds := AABB()
	var first := true
	for f in FRAMES:
		player.seek(f / FPS, true)
		for skeleton: Skeleton3D in scene.find_children("*", "Skeleton3D", true, false):
			skeleton.force_update_all_bone_transforms()
		await process_frame
		var transforms: Array[Transform3D] = []
		for b in palette.size():
			var item: Dictionary = palette[b]
			var matrix: Transform3D
			if item.has("skeleton"):
				matrix = ground * _rel(item.skeleton, scene) * item.skeleton.get_bone_global_pose(item.bone) * item.bind * item.inverse_frame
			else:
				matrix = ground * _rel(item.node, scene) * item.inverse_frame
			transforms.append(matrix)
			image.set_pixel(b*3, f, Color(matrix.basis.x.x, matrix.basis.y.x, matrix.basis.z.x, matrix.origin.x))
			image.set_pixel(b*3+1, f, Color(matrix.basis.x.y, matrix.basis.y.y, matrix.basis.z.y, matrix.origin.y))
			image.set_pixel(b*3+2, f, Color(matrix.basis.x.z, matrix.basis.y.z, matrix.basis.z.z, matrix.origin.z))
		# Bounding each influence-transformed surface box is conservative for convex normalized weights.
		# It covers ALL vertices/frames without an expensive vertex-by-frame CPU skin pass.
		for surface: Dictionary in points:
			var box: AABB = surface.box
			for b in surface.used:
				var transformed: AABB = transforms[b] * box
				bounds = transformed if first else bounds.merge(transformed)
				first = false
	if not preload("export_mesh.gd").save(output_mesh, image, bounds, palette.size(), material_entries, job):
		_fail(job, "Resource save failed")
		scene.free()
		return
	print("IDLE_EXPORTED ", job.key, " bones=", palette.size(), " surfaces=", output_mesh.get_surface_count())
	scene.free()
