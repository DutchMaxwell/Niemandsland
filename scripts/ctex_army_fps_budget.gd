extends Node3D
## Army-scale FRAME-TIME test for the per-base decimation BUDGET. RUN VIA F6 on a real GPU (headless =
## dummy renderer). Loads 9 distinct 25mm-infantry meshes from the w12 decimation ladders at a chosen
## level (NML_FPS_LEVEL = "full" | "86000") with their EMBEDDED materials, instances them to
## TOTAL_INSTANCES across a table, and measures avg/min FPS, triangles/frame and texture VRAM (vsync
## off, so headroom above the refresh shows). Run once with "full" and once with "86000" to see the
## FPS payoff of the 86k infantry budget at a realistic 2-army worst case. Throwaway scene.

const U_DIR := "user://"
const OUT := "user://ctex_fps/"
# The 9 infantry ladders built for the decimation study (each has lvl_<native>.glb + lvl_086000.glb).
const MODELS: Array[String] = ["w12_assault", "w12_goblin", "w12_pathfinder", "w12_exosuit",
	"w12_winged_elf", "w12_eternal", "w12_saurian", "w12_highelf_acolyte", "w12_orc"]
const TOTAL_INSTANCES := 200   # realistic worst case: 2 large hordes
const GRID_COLS := 20
const SPACING := 1.3

var _label: Label
var _meshes: Array = []
var _measuring := false
var _fps_samples: Array = []
var _warmup := 60
var _frames := 0
var _tris := 0
var _level := "full"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var lvl := OS.get_environment("NML_FPS_LEVEL")
	if not lvl.is_empty():
		_level = lvl
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
	print("[FPS-BUDGET] ", s.replace("\n", " | "))


func _build() -> void:
	for dir_name in MODELS:
		var glb := _pick_glb(U_DIR + dir_name, _level)
		if glb.is_empty():
			continue
		_log("Loading %s (%s) …" % [dir_name, _level])
		var node := _load_glb(glb)
		var mesh := _first_mesh(node)
		if mesh != null:
			_meshes.append(mesh)
		await get_tree().process_frame
	if _meshes.is_empty():
		_log("NO meshes — run the w12 decimation first")
		return

	for i in range(TOTAL_INSTANCES):
		var mi := MeshInstance3D.new()
		mi.mesh = _meshes[i % _meshes.size()]   # embedded surface materials ride along
		var col := i % GRID_COLS
		var row := i / GRID_COLS
		mi.position = Vector3((col - GRID_COLS / 2.0) * SPACING, 0.0, -row * SPACING)
		add_child(mi)
	_log("Placed %d instances (%s) — warming up …" % [TOTAL_INSTANCES, _level])
	_measuring = true


# Pick the ladder glb for the level: "full" = highest tris; otherwise nearest to the numeric level.
func _pick_glb(dir_path: String, level: String) -> String:
	var d := DirAccess.open(dir_path)
	if d == null:
		return ""
	var tris_list: Array = []
	for f in d.get_files():
		if f.begins_with("lvl_") and f.ends_with(".glb"):
			tris_list.append(int(str(f).trim_prefix("lvl_").trim_suffix(".glb")))
	if tris_list.is_empty():
		return ""
	tris_list.sort()
	var pick: int = tris_list[-1]   # full = max
	if level != "full":
		var target := int(level)
		var best: int = tris_list[-1]
		for t in tris_list:
			if abs(int(t) - target) < abs(best - target):
				best = int(t)
		pick = best
	return "%s/lvl_%06d.glb" % [dir_path, pick]


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
	var msg := "ARMY-SCALE FPS — level=%s\n  instances: %d (%d unit types)\n  triangles/frame: %s\n  FPS avg: %.0f   min: %.0f   (vsync off)\n  texture VRAM: %.0f MB" % [
		_level, TOTAL_INSTANCES, _meshes.size(), _commas(_tris), avg, lo, texmem]
	_log(msg)
	var f := FileAccess.open(OUT + "fps_budget_%s.txt" % _level, FileAccess.WRITE)
	if f:
		f.store_string(msg)
		f.close()
	if not Engine.is_editor_hint():
		await get_tree().create_timer(0.3).timeout
		get_tree().quit()


func _first_mesh(node: Node3D) -> Mesh:
	if node == null:
		return null
	for n in node.find_children("*", "MeshInstance3D", true, false):
		if (n as MeshInstance3D).mesh != null:
			return (n as MeshInstance3D).mesh
	return null


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
