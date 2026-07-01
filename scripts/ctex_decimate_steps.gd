extends Node3D
## Precise 25k-step decimation quality ladder. RUN VIA F6 on a real GPU. Loads the Blender-decimated
## assault-brothers GLBs from user://decimate_glbs/ (full 286k down to ~11k in 25k steps), applies the
## same .ctex material, and renders each CLOSE-UP with identical framing/lighting so every step is
## directly comparable to full. Saves user://ctex_decimate_steps/tris_NNNNNN.png (host assembles the
## big canvas: every step beside full). Decimation is Blender COLLAPSE — a real quality decimator.

const PATCH := "res://bb_ctex_patch.json"
const CACHE := "user://cache/"
const GLB_DIR := "user://decimate_glbs/"
const OUT := "user://ctex_decimate_steps/"
const KEY := "battle_brothers/assault brothers"

var _label: Label
var _mat: Material

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_setup_view()
	await _run()


func _setup_view() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.55, 1.15)
	cam.look_at(Vector3(0.0, 0.55, 0.0), Vector3.UP)
	add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-40.0, -35.0, 0.0)
	key.light_energy = 1.25
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12.0, 130.0, 0.0)
	fill.light_energy = 0.45
	add_child(fill)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.13)
	e.ambient_light_color = Color(0.55, 0.55, 0.6)
	e.ambient_light_energy = 0.55
	we.environment = e
	add_child(we)
	var cl := CanvasLayer.new()
	add_child(cl)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 26)
	_label.position = Vector2(28, 24)
	cl.add_child(_label)


func _log(s: String) -> void:
	if _label:
		_label.text = s
	print("[STEPS] ", s)


func _run() -> void:
	var patch: Dictionary = JSON.parse_string(FileAccess.open(PATCH, FileAccess.READ).get_as_text())
	var tex: Dictionary = patch[KEY]["ctex"]["textures"]
	_mat = CtexLoader.build_material(CACHE + str(tex["albedo"]["url"]), "",
		(CACHE + str(tex["orm"]["url"]) if tex.has("orm") else ""), false)

	var files: Array = []
	var d := DirAccess.open(GLB_DIR)
	if d:
		for f in d.get_files():
			if f.ends_with(".glb"):
				files.append(f)
	files.sort()
	files.reverse()   # high tris -> low
	if files.is_empty():
		_log("NO GLBs in " + GLB_DIR)
		return
	for f in files:
		var fname: String = str(f)
		var tris: String = fname.trim_prefix("lvl_").trim_suffix(".glb")
		_log("Rendering %s tris …" % tris)
		await _shoot(GLB_DIR + fname, "tris_" + tris)
	_log("DONE — %d steps in %s" % [files.size(), ProjectSettings.globalize_path(OUT)])


func _shoot(glb: String, base: String) -> void:
	var node := _load_glb(glb)
	if node == null:
		return
	var pivot := Node3D.new()
	add_child(pivot)
	pivot.add_child(node)
	await get_tree().process_frame   # let transforms settle
	# aggregate WORLD AABB (pivot still identity here) + apply material to every surface.
	var box := AABB()
	var first := true
	var found := false
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		found = true
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
	# normalize: 1.75 units tall, centered at origin — identical framing for every step.
	var s: float = 1.75 / box.size.y
	pivot.scale = Vector3(s, s, s)
	pivot.position = -box.get_center() * s
	await _capture(OUT + base + ".png")
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
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(path)
