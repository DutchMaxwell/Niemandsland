extends Node3D
## Standalone VRAM A/B test for the ModelForge .ctex pipeline. RUN VIA F5 on a real GPU — a headless
## / dummy renderer reports no real texture VRAM. Downloads the heavy_sword mesh (geometry GLB) + its
## albedo/ORM .ctex from R2, renders the sword with the .ctex material, and reports
## Performance.RENDER_TEXTURE_MEM_USED for the SAME textures as raw RGBA (decompressed) vs .ctex (BC7).
## Expectation (from the producer): ~43.6 MB raw → ~11.8 MB .ctex. See
## HANDOFF_modelforge_texture_pipeline.md. Not shipped — a throwaway measurement scene.

const BASE := "https://assets.niemandsland.xyz/"
const UA := "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36"
const MESH_SHA := "2f594fb35778ca218070f401c9e9eb7b4c42abaa6f1eb8861e3a11aa5847c78c"
const ALBEDO_SHA := "1c1c8709e2c22056a36091ab85bb30f418cba1add2f57bddc33ef23027718dca"
const ORM_SHA := "0df4c479343843b9ae12a8fbfe5927848c10f807399ef9ba0e47af6120cc826e"
const CACHE := "user://cache/"

var _label: Label
var _mesh: Mesh = null

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(CACHE)
	_setup_view()
	await _run()


func _setup_view() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.2, 1.2)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-50.0, -35.0, 0.0)
	add_child(key)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.08, 0.09, 0.11)
	e.ambient_light_color = Color(0.4, 0.4, 0.45)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var cl := CanvasLayer.new()
	add_child(cl)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.position = Vector2(24, 24)
	cl.add_child(_label)
	_log("Downloading heavy_sword mesh + .ctex from R2 …")


func _log(s: String) -> void:
	if _label:
		_label.text = s
	print("[CTEX-VRAM] ", s.replace("\n", " | "))


func _run() -> void:
	for entry in [[MESH_SHA, ".glb"], [ALBEDO_SHA, ".ctex"], [ORM_SHA, ".ctex"]]:
		if not await _download(entry[0] + entry[1]):
			_log("Download FAILED: %s%s — check network / R2." % [entry[0], entry[1]])
			return
	_mesh = _load_mesh(CACHE + MESH_SHA + ".glb")
	await _measure()


func _download(fname: String) -> bool:
	var dst := CACHE + fname
	if FileAccess.file_exists(dst):
		return true
	var http := HTTPRequest.new()
	add_child(http)
	http.download_file = dst
	var err := http.request(BASE + fname, ["User-Agent: " + UA])
	if err != OK:
		http.queue_free()
		return false
	var res: Array = await http.request_completed
	http.queue_free()
	return int(res[1]) == 200 and FileAccess.file_exists(dst)


## Load a geometry GLB downloaded to user:// → the first Mesh, or null (falls back to a box).
func _load_mesh(path: String) -> Mesh:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var scene := doc.generate_scene(state)
	if scene == null:
		return null
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh != null:
			return (mi as MeshInstance3D).mesh
	return null


func _measure() -> void:
	var albedo_path := CACHE + ALBEDO_SHA + ".ctex"
	var orm_path := CACHE + ORM_SHA + ".ctex"
	var base := await _texmem()

	# A) .ctex (BC7, stays compressed in VRAM)
	var mat_ctex := CtexLoader.build_material(albedo_path, "", orm_path, false)  # heavy_sword: no normal, no AO
	_add_sword(mat_ctex, Vector3(-0.35, 0.0, 0.0))
	var used_ctex := await _texmem() - base

	# B) raw RGBA (the SAME textures decompressed — what today's raw-GLB path costs)
	var mat_raw := _raw_material(albedo_path, orm_path)
	_add_sword(mat_raw, Vector3(0.35, 0.0, 0.0))
	var used_raw := await _texmem() - base - used_ctex

	var ratio := float(used_raw) / float(maxi(used_ctex, 1))
	_log("heavy_sword textures (albedo + ORM, 2048²)\n  .ctex (BC7):  %s\n  raw (RGBA):   %s\n  ratio:        %.2fx smaller\n  (baseline %s — left = .ctex, right = raw)"
		% [_mb(used_ctex), _mb(used_raw), ratio, _mb(base)])


func _texmem() -> int:
	for _i in range(4):
		await get_tree().process_frame
	return int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))


func _add_sword(mat: Material, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	if _mesh != null:
		mi.mesh = _mesh
		for s in range(_mesh.get_surface_count()):
			mi.set_surface_override_material(s, mat)
	else:
		var box := BoxMesh.new()
		box.size = Vector3(0.4, 0.4, 0.4)
		mi.mesh = box
		mi.material_override = mat
	mi.position = pos
	add_child(mi)


## The raw-RGBA equivalent material: decompress each .ctex image → ImageTexture (uncompressed).
func _raw_material(albedo_path: String, orm_path: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var a := CtexLoader.load_ctex(albedo_path)
	if a != null:
		mat.albedo_texture = _decompressed(a)
	var o := CtexLoader.load_ctex(orm_path)
	if o != null:
		var t := _decompressed(o)
		mat.roughness_texture = t
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic_texture = t
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
	return mat


func _decompressed(tex: Texture2D) -> ImageTexture:
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	return ImageTexture.create_from_image(img)


func _mb(bytes: int) -> String:
	return "%.1f MB" % (float(bytes) / 1048576.0)
