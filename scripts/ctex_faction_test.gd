extends Node3D
## Faction-wide VRAM + visual A/B test for the .ctex pipeline. RUN VIA F5 on a real GPU (a headless
## / dummy renderer reports no real VRAM). Reads bb_ctex_patch.json (26 battle_brothers units, each
## a legacy raw-GLB `url` + a `ctex` block: mesh + textures.{albedo,orm}, godot_version). Assets must
## already be in user://cache/ (pre-downloaded). Per unit it shows LEFT = legacy raw GLB, RIGHT =
## .ctex (geometry GLB + CtexLoader BC7 material), measures Performance.RENDER_TEXTURE_MEM_USED for
## each, saves a side-by-side screenshot to user://ctex_test/, and writes vram.csv (+ a faction sum).
## See HANDOFF_modelforge_texture_pipeline.md. Throwaway measurement scene — not shipped.

const PATCH := "res://bb_ctex_patch.json"
const CACHE := "user://cache/"
const OUT := "user://ctex_test/"
const TARGET_H := 1.4      # normalize each unit to this height so a tank and a soldier frame alike
const HALF_X := 1.15       # raw at -HALF_X, ctex at +HALF_X

var _label: Label
var _rows: Array = []      # [unit, raw_bytes, ctex_bytes, guard_ok]
var _sum_raw := 0
var _sum_ctex := 0

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_setup_view()
	await _run()


func _setup_view() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 3.4)
	cam.look_at(Vector3.ZERO, Vector3.UP)
	add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
	key.light_energy = 1.2
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20.0, 140.0, 0.0)
	fill.light_energy = 0.4
	add_child(fill)
	var we := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.09, 0.10, 0.12)
	e.ambient_light_color = Color(0.5, 0.5, 0.55)
	e.ambient_light_energy = 0.5
	we.environment = e
	add_child(we)
	var cl := CanvasLayer.new()
	add_child(cl)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.position = Vector2(24, 20)
	cl.add_child(_label)


func _log(s: String) -> void:
	if _label:
		_label.text = s
	print("[BB-CTEX] ", s.replace("\n", " | "))


func _run() -> void:
	var f := FileAccess.open(PATCH, FileAccess.READ)
	if f == null:
		_log("Cannot open %s" % PATCH)
		return
	var patch: Dictionary = JSON.parse_string(f.get_as_text())
	var keys := patch.keys()
	keys.sort()
	var idx := 0
	for key in keys:
		idx += 1
		var short: String = str(key).get_file()
		_log("Unit %d/%d: %s — loading …" % [idx, keys.size(), short])
		await _measure_unit(idx, short, patch[key])
	_write_csv()
	var pct := 100.0 * (1.0 - float(_sum_ctex) / float(maxi(_sum_raw, 1)))
	_log("DONE — %d units. Faction VRAM: raw %s → .ctex %s  (%.1f%% saved)\nOutputs in user://ctex_test/  (%s)"
		% [keys.size(), _mb(_sum_raw), _mb(_sum_ctex), pct, ProjectSettings.globalize_path(OUT)])


func _measure_unit(idx: int, short: String, entry: Dictionary) -> void:
	var base := await _texmem()

	# LEFT: legacy raw GLB (its own embedded textures) at -HALF_X.
	var raw := _load_glb(CACHE + str(entry["url"]))
	var raw_root := _place(raw, -HALF_X)
	var raw_used := await _texmem() - base

	# RIGHT: .ctex — geometry GLB + CtexLoader BC7 material. Version guard: on mismatch fall back to
	# the legacy raw GLB (confirms the guard path). This batch has no normal + ORM has no AO.
	var ctex_block: Dictionary = entry.get("ctex", {})
	var guard_ok: bool = CtexLoader.ctex_compatible(str(ctex_block.get("godot_version", "")))
	var ctex_root: Node3D
	if guard_ok:
		var mesh := _load_glb(CACHE + str(ctex_block["mesh"]["url"]))
		var tex: Dictionary = ctex_block.get("textures", {})
		var albedo_p := CACHE + str(tex["albedo"]["url"]) if tex.has("albedo") else ""
		var orm_p := CACHE + str(tex["orm"]["url"]) if tex.has("orm") else ""
		var mat := CtexLoader.build_material(albedo_p, "", orm_p, false)
		_apply_material(mesh, mat)
		ctex_root = _place(mesh, HALF_X)
	else:
		ctex_root = _place(_load_glb(CACHE + str(entry["url"])), HALF_X)  # guard fallback = legacy
	var ctex_used := await _texmem() - base - raw_used

	await _capture(OUT + "%02d_%s.png" % [idx, short])
	_rows.append([short, raw_used, ctex_used, guard_ok])
	_sum_raw += raw_used
	_sum_ctex += ctex_used
	_log("Unit %d: %s — raw %s / .ctex %s%s" % [idx, short, _mb(raw_used), _mb(ctex_used),
		("" if guard_ok else "  [GUARD FALLBACK→legacy]")])

	# Free both so the next unit measures from a clean baseline.
	if is_instance_valid(raw_root):
		raw_root.queue_free()
	if is_instance_valid(ctex_root):
		ctex_root.queue_free()
	for _i in range(6):
		await get_tree().process_frame


## Load a GLB from user:// via GLTFDocument (runtime, outside the import system). Returns the scene.
func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


## Apply one material to every surface of every MeshInstance3D under `node`.
func _apply_material(node: Node3D, mat: Material) -> void:
	if node == null:
		return
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh != null:
			for s in range(m.mesh.get_surface_count()):
				m.set_surface_override_material(s, mat)


## Wrap, normalize (fit TARGET_H, centred) and place `node` at x. Returns the wrapper (null-safe).
func _place(node: Node3D, x: float) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	if node != null:
		root.add_child(node)
		var box := _combined_aabb(node)
		if box.size.y > 0.0001:
			var s := TARGET_H / box.size.y
			node.scale = Vector3(s, s, s)
			node.position = -box.get_center() * s
	root.position = Vector3(x, 0.0, 0.0)
	return root


func _combined_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a := m.get_aabb()
		a = m.transform * a
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box


func _texmem() -> int:
	for _i in range(4):
		await get_tree().process_frame
	return int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))


func _capture(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(path)


func _write_csv() -> void:
	var f := FileAccess.open(OUT + "vram.csv", FileAccess.WRITE)
	if f == null:
		return
	f.store_line("unit,raw_mb,ctex_mb,saved_pct,guard_ok")
	for r in _rows:
		var saved := 100.0 * (1.0 - float(int(r[2])) / float(maxi(int(r[1]), 1)))
		f.store_line("%s,%.2f,%.2f,%.1f,%s" % [r[0], float(int(r[1])) / 1048576.0, float(int(r[2])) / 1048576.0, saved, r[3]])
	f.store_line("TOTAL,%.2f,%.2f,%.1f," % [float(_sum_raw) / 1048576.0, float(_sum_ctex) / 1048576.0,
		100.0 * (1.0 - float(_sum_ctex) / float(maxi(_sum_raw, 1)))])
	f.close()


func _mb(bytes: int) -> String:
	return "%.1f MB" % (float(bytes) / 1048576.0)
