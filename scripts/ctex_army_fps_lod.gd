extends Node3D
## Army-scale FRAME-TIME test WITH runtime LOD. Same as ctex_army_fps but each mesh gets meshoptimizer
## LODs generated at load (ImporterMesh.generate_lods) so Godot auto-switches detail by screen size:
## a model tiny on the table renders a low LOD (few tris), a model zoomed in renders full detail.
## RUN VIA F6 on a real GPU. Compare its FPS to ctex_army_fps (LOD off) at the same 200 instances —
## if LOD resolves the vertex wall, full geometry can ship as-is (crisp on zoom, fast on the table).

const PATCH := "res://bb_ctex_patch.json"
const CACHE := "user://cache/"
const OUT := "user://ctex_fps/"
const UNIT_TYPES := 10
const TOTAL_INSTANCES := 200
const GRID_COLS := 20
const SPACING := 1.3

var _label: Label
var _meshes: Array = []
var _measuring := false
var _fps_samples: Array = []
var _warmup := 60
var _frames := 0
var _tris := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_setup_view()
	await _build()


func _setup_view() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 18.0, 20.0)
	cam.look_at(Vector3(0.0, 0.0, -4.0), Vector3.UP)
	cam.far = 400.0
	add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-55.0, -35.0, 0.0)
	key.light_energy = 1.1
	key.shadow_enabled = true
	add_child(key)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.11, 0.13)
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 0.5
	we.environment = e
	add_child(we)
	var cl := CanvasLayer.new()
	add_child(cl)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 22)
	_label.position = Vector2(24, 20)
	cl.add_child(_label)


func _log(s: String) -> void:
	if _label:
		_label.text = s
	print("[FPS-LOD] ", s.replace("\n", " | "))


func _build() -> void:
	var patch: Dictionary = JSON.parse_string(FileAccess.open(PATCH, FileAccess.READ).get_as_text())
	var keys := patch.keys()
	keys.sort()
	var step: int = maxi(1, keys.size() / UNIT_TYPES)
	for i in range(0, keys.size(), step):
		if _meshes.size() >= UNIT_TYPES:
			break
		var e: Dictionary = patch[keys[i]]
		var c: Dictionary = e["ctex"]
		_log("Loading + LOD unit mesh %d/%d …" % [_meshes.size() + 1, UNIT_TYPES])
		var node := _load_glb(CACHE + str(c["mesh"]["url"]))
		var tex: Dictionary = c["textures"]
		CtexLoader.apply_to_mesh(node,
			CACHE + str(tex["albedo"]["url"]), "",
			(CACHE + str(tex["orm"]["url"]) if tex.has("orm") else ""), false)
		var packed := _flatten_with_lods(node)
		if not packed.is_empty():
			_meshes.append(packed)
		await get_tree().process_frame

	var placed := 0
	for i in range(TOTAL_INSTANCES):
		var src: Dictionary = _meshes[i % _meshes.size()]
		var mi := MeshInstance3D.new()
		mi.mesh = src["mesh"]
		for s in range(src["mats"].size()):
			mi.set_surface_override_material(s, src["mats"][s])
		var col := i % GRID_COLS
		var row := i / GRID_COLS
		mi.position = Vector3((col - GRID_COLS / 2.0) * SPACING, 0.0, -row * SPACING)
		add_child(mi)
		placed += 1
	_log("Placed %d instances (LOD on) — warming up …" % placed)
	_measuring = true


func _process(_dt: float) -> void:
	if not _measuring:
		return
	_frames += 1
	if _frames <= _warmup:
		return
	_fps_samples.append(Performance.get_monitor(Performance.TIME_FPS))
	_tris = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	if _fps_samples.size() >= 180:
		_measuring = false
		_report()


func _report() -> void:
	var total := 0.0
	var lo := 100000.0
	for f in _fps_samples:
		total += f
		lo = minf(lo, f)
	var avg := total / float(_fps_samples.size())
	var texmem := float(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED)) / 1048576.0
	var msg := "ARMY-SCALE FPS — LOD ON (full geo + runtime LODs)\n  instances: %d (%d unit types)\n  triangles/frame: %s  (auto-LOD at table zoom)\n  FPS avg: %.0f   min: %.0f   (vsync off)\n  texture VRAM: %.0f MB\n  rough Steam Deck est: ~%.0f FPS" % [
		TOTAL_INSTANCES, _meshes.size(), _commas(_tris), avg, lo, texmem, avg / 8.0]
	_log(msg)
	var f := FileAccess.open(OUT + "fps_lod.txt", FileAccess.WRITE)
	if f:
		f.store_string(msg)
		f.close()


## Grab the mesh + its override materials, then rebuild the mesh WITH meshoptimizer LODs so Godot
## renders a low LOD when the instance is small on screen (the army/table case).
func _flatten_with_lods(node: Node3D) -> Dictionary:
	for n in node.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null:
			continue
		var mats: Array = []
		for s in range(mi.mesh.get_surface_count()):
			mats.append(mi.get_surface_override_material(s))
		var im := ImporterMesh.new()
		for s in range(mi.mesh.get_surface_count()):
			im.add_surface(Mesh.PRIMITIVE_TRIANGLES, mi.mesh.surface_get_arrays(s), [], {}, null, "", 0)
		im.generate_lods(25.0, 60.0, [])
		return {"mesh": im.get_mesh(), "mats": mats}
	return {}


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _commas(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
