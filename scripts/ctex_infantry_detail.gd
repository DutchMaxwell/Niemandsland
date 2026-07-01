extends Node3D
## Close-up DETAIL A/B for the .ctex pipeline — infantry only (vehicles are a separate voxel-remesh
## problem). RUN VIA F6 on a real GPU. For each foot-infantry unit it renders the raw GLB and the
## .ctex version (fixed metallic material) LARGE + centred, as SEPARATE full-frame 1920×1080 captures
## (front + a 3/4 turn), so hand/gear/weapon detail is inspectable. Saves to user://ctex_detail/.
## Assets load from user://cache/ (pre-downloaded). See HANDOFF_modelforge_texture_pipeline.md.

const PATCH := "res://bb_ctex_patch.json"
const CACHE := "user://cache/"
const OUT := "user://ctex_detail/"
const TARGET_H := 1.75

# Foot infantry only (no vehicles/bikes/walkers) — the 40k-decimate class we want to vet up close.
const INFANTRY := [
	"battle_brothers/assault brothers",
	"battle_brothers/battle brothers",
	"battle_brothers/destroyers",
	"battle_brothers/elite pathfinder",
	"battle_brothers/heavy exo suit",
	"battle_brothers/master brother",
	"battle_brothers/master destroyer",
	"battle_brothers/pathfinders",
	"battle_brothers/support brothers",
	"battle_brothers/veteran assault brothers",
	"battle_brothers/veteran battle brothers",
	"battle_brothers/veteran master brother",
]

var _label: Label
var _pivot: Node3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	_setup_view()
	await _run()


func _setup_view() -> void:
	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 0.0, 1.75)   # close, figure fills the frame
	cam.look_at(Vector3.ZERO, Vector3.UP)
	add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -35.0, 0.0)
	key.light_energy = 1.25
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15.0, 135.0, 0.0)
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
	_pivot = Node3D.new()
	add_child(_pivot)
	var cl := CanvasLayer.new()
	add_child(cl)
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 20)
	_label.position = Vector2(24, 20)
	cl.add_child(_label)


func _log(s: String) -> void:
	if _label:
		_label.text = s
	print("[BB-DETAIL] ", s)


func _run() -> void:
	var f := FileAccess.open(PATCH, FileAccess.READ)
	var patch: Dictionary = JSON.parse_string(f.get_as_text())
	var idx := 0
	for key in INFANTRY:
		idx += 1
		if not patch.has(key):
			continue
		var short: String = str(key).get_file()
		var e: Dictionary = patch[key]
		_log("Infantry %d/%d: %s — rendering …" % [idx, INFANTRY.size(), short])
		# RAW
		await _shoot(_load_glb(CACHE + str(e["url"])), "%02d_%s_RAW" % [idx, short])
		# CTEX (fixed metallic material)
		var c: Dictionary = e["ctex"]
		var mesh := _load_glb(CACHE + str(c["mesh"]["url"]))
		var tex: Dictionary = c["textures"]
		var mat := CtexLoader.build_material(
			CACHE + str(tex["albedo"]["url"]), "",
			(CACHE + str(tex["orm"]["url"]) if tex.has("orm") else ""), false)
		_apply_material(mesh, mat)
		await _shoot(mesh, "%02d_%s_CTEX" % [idx, short])
	_log("DONE — %d infantry, front + 3/4 each.\nOutputs in user://ctex_detail/  (%s)"
		% [INFANTRY.size(), ProjectSettings.globalize_path(OUT)])


## Frame `node` centred + large, capture a FRONT and a 3/4-turn full-frame PNG, then free it.
func _shoot(node: Node3D, base: String) -> void:
	if node == null:
		return
	_pivot.add_child(node)
	var box := _combined_aabb(node)
	if box.size.y > 0.0001:
		var s := TARGET_H / box.size.y
		node.scale = Vector3(s, s, s)
		node.position = -box.get_center() * s
	_pivot.rotation_degrees = Vector3.ZERO
	await _capture(OUT + base + "_front.png")
	_pivot.rotation_degrees = Vector3(0.0, 35.0, 0.0)
	await _capture(OUT + base + "_34.png")
	node.queue_free()
	for _i in range(4):
		await get_tree().process_frame


func _load_glb(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


func _apply_material(node: Node3D, mat: Material) -> void:
	if node == null:
		return
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh != null:
			for s in range(m.mesh.get_surface_count()):
				m.set_surface_override_material(s, mat)


func _combined_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var a: AABB = m.transform * m.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box


func _capture(path: String) -> void:
	for _i in range(3):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img != null:
		img.save_png(path)
