extends Node3D
## Renders ONE infantry model (veteran master brother) three ways, close-up, varying ONLY the albedo
## resolution so the "washout" question is answered on a real model: 2048² BC7 (current bake) vs
## 4096² BC7 (proposed) vs 4096² RAW (ground truth). Same mesh, same ORM, same lighting/angle. RUN
## VIA F6 on a real GPU. Saves 3 full-frame captures to user://ctex_rescompare/. Throwaway.

const PATCH := "res://bb_ctex_patch.json"
const KEY := "battle_brothers/veteran master brother"
const CACHE := "user://cache/"
const OUT := "user://ctex_rescompare/"
const RAW_ALBEDO_PNG := "user://ctex_detail/_raw_albedo.png"   # 4096² RGBA extracted from the raw GLB
const BC7_4K := "user://cache/albedo4k_bc7.ctex"              # 4096² BC7 baked from that
const TARGET_H := 3.2   # big — camera crops to the upper body/chest

var _label: Label
var _mesh: Mesh

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_setup_view()
	await _run()


func _setup_view() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.55, 1.35)   # close, aimed at the chest
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
	print("[RESCMP] ", s)


func _run() -> void:
	var patch: Dictionary = JSON.parse_string(FileAccess.open(PATCH, FileAccess.READ).get_as_text())
	var e: Dictionary = patch[KEY]
	var c: Dictionary = e["ctex"]
	_mesh = _first_mesh(_load_glb(CACHE + str(c["mesh"]["url"])))
	var orm_p := CACHE + str(c["textures"]["orm"]["url"])
	var albedo_2k := CACHE + str(c["textures"]["albedo"]["url"])

	# A) current 2048² BC7
	await _shoot(_mat(CtexLoader.load_ctex(albedo_2k), orm_p), "2048² BC7 (current bake)", "1_2048_bc7")
	# B) proposed 4096² BC7
	await _shoot(_mat(CtexLoader.load_ctex(BC7_4K), orm_p), "4096² BC7 (proposed)", "2_4096_bc7")
	# C) ground truth 4096² RAW (uncompressed)
	await _shoot(_mat(_raw_albedo_texture(), orm_p), "4096² RAW (ground truth)", "3_4096_raw")

	_log("DONE — 3 renders in user://ctex_rescompare/  (%s)" % ProjectSettings.globalize_path(OUT))


## A material with the given albedo + the shared ORM (metallic/roughness driven fully; no AO).
func _mat(albedo: Texture2D, orm_path: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	if albedo != null:
		m.albedo_texture = albedo
	var orm := CtexLoader.load_ctex(orm_path)
	if orm != null:
		m.metallic = 1.0
		m.roughness = 1.0
		m.roughness_texture = orm
		m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		m.metallic_texture = orm
		m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	return m


func _raw_albedo_texture() -> Texture2D:
	var img := Image.load_from_file(RAW_ALBEDO_PNG)
	if img == null:
		return null
	return ImageTexture.create_from_image(img)


func _shoot(mat: Material, caption: String, base: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	for s in range(_mesh.get_surface_count()):
		mi.set_surface_override_material(s, mat)
	var box := mi.get_aabb()
	var s := TARGET_H / box.size.y
	mi.scale = Vector3(s, s, s)
	mi.position = -box.get_center() * s
	add_child(mi)
	_log(caption)
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
	if node == null:
		return null
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
