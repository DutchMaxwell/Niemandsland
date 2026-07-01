extends Node3D
## Decimation QUALITY preview for small models. RUN VIA F6 on a real GPU. Takes one small infantry
## model (assault brothers), decimates it to several triangle tiers via Godot's meshoptimizer LODs
## (representative of a quality decimator), and renders each CLOSE-UP (upper body — where faceting
## shows) with the .ctex material, so the quality-vs-tris floor for small models is visible. Saves to
## user://ctex_decimate/. Answers "do small models look bad when decimated?" with data.

const PATCH := "res://bb_ctex_patch.json"
const CACHE := "user://cache/"
const OUT := "user://ctex_decimate/"
const KEY := "battle_brothers/assault brothers"

var _label: Label
var _mat: Material
var _base_arrays: Array

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
	print("[DECIM] ", s)


func _run() -> void:
	var patch: Dictionary = JSON.parse_string(FileAccess.open(PATCH, FileAccess.READ).get_as_text())
	var c: Dictionary = patch[KEY]["ctex"]
	var tex: Dictionary = c["textures"]
	var node := _load_glb(CACHE + str(c["mesh"]["url"]))
	var mesh := _first_mesh(node)
	_base_arrays = mesh.surface_get_arrays(0)
	_mat = CtexLoader.build_material(CACHE + str(tex["albedo"]["url"]), "",
		(CACHE + str(tex["orm"]["url"]) if tex.has("orm") else ""), false)

	# Tiers: full + the meshopt LOD chain (down to ~35k — its floor for this mesh, ≈ a realistic
	# small-model target). Renders the decimation quality curve at close-up.
	var base_tris: int = _base_arrays[Mesh.ARRAY_INDEX].size() / 3
	var lods := _lods(_base_arrays)               # ~143k / 71k / 35k
	var tiers: Array = [{"tris": base_tris, "indices": _base_arrays[Mesh.ARRAY_INDEX]}]
	tiers.append_array(lods)
	for t in tiers:
		var k: int = int(t["tris"])
		_log("Rendering ~%dk tris …" % [k / 1000])
		await _shoot(_arrays_with(t["indices"]), "tris_%06d" % k)
	_log("DONE — assault brothers at %d tiers in user://ctex_decimate/  (%s)"
		% [tiers.size(), ProjectSettings.globalize_path(OUT)])


## meshoptimizer LOD chain for a surface's arrays → [{tris, indices}] coarsening.
func _lods(arrays: Array) -> Array:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, null, "", 0)
	im.generate_lods(25.0, 60.0, [])
	var out: Array = []
	for i in range(im.get_surface_lod_count(0)):
		var idx: PackedInt32Array = im.get_surface_lod_indices(0, i)
		out.append({"tris": idx.size() / 3, "indices": idx})
	return out


func _arrays_with(indices: PackedInt32Array) -> Array:
	var a := _base_arrays.duplicate()
	a[Mesh.ARRAY_INDEX] = indices
	return a


func _shoot(arrays: Array, base: String) -> void:
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = _mat
	var box := m.get_aabb()
	var s := 1.75 / box.size.y
	mi.scale = Vector3(s, s, s)
	mi.position = -box.get_center() * s
	add_child(mi)
	await _capture(OUT + base + ".png")
	mi.queue_free()
	for _i in range(4):
		await get_tree().process_frame


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _first_mesh(node: Node3D) -> Mesh:
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh != null:
			return (mi as MeshInstance3D).mesh
	return null


func _capture(path: String) -> void:
	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(path)
