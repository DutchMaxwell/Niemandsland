class_name BoardgenDressKit
extends RefCounted
## The module kit of the ruin-town dressing (docs/adr/0004-dressing-materials-and-kit-manifest.md): the manifest (assets/ruintown_dress.json: one entry per module with its numbers, plus the materials / ground / sets blocks) and the
## module meshes. A module's GLB comes from the town's BoardgenKit (cached_path: the dev folder NML_RUINTOWN_KIT_DIR or the delivery cache); every surface keeps its own name = the shared material it is drawn
## with (the GLB's material name), so the merge can put all modules of one material into one surface. `force_stub` (tests) draws every module as a box of its aabb: no GLB needed. Meshes are in metres.

const MANIFEST_PATH := "res://assets/ruintown_dress.json"
const IN_M := 0.0254

var meta: Dictionary = {}   # the parsed manifest
var _kit: BoardgenKit
var _force_stub := false
static var _meshes: Dictionary = {}   # GLB path -> parsed ArrayMesh, shared by every board


func _init(kit: BoardgenKit, force_stub := false) -> void:
	_kit = kit
	_force_stub = force_stub
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	meta = data if typeof(data) == TYPE_DICTIONARY else {}


## The manifest entry of a module ({} when the manifest does not know it).
func module(name: String) -> Dictionary:
	return meta.get("modules", {}).get(name, {})


## True when every module of `names` can be drawn: all are in the manifest and either the stub kit is forced, or none is a stub and the town kit is usable for them (Medium and up, every GLB cached).
func usable(names: Array) -> bool:
	if not names.all(func(n: String) -> bool: return not module(n).is_empty()):
		return false
	return _force_stub or (names.all(func(n: String) -> bool: return not module(n)["stub"]) and _kit.usable(names))


## The module's mesh in metres, one surface per material named by it; null when its GLB is not cached (or does not parse). Under force_stub a box of the module's aabb with one surface named by its first material.
## A vegetation CARD module (`veg.card`) names its ct_veg surface `ct_veg_card`: cards and modelled plants are two variants of one shader and cannot share a surface.
func mesh(name: String) -> ArrayMesh:
	var m := module(name)
	if m.is_empty():
		return null
	var card := bool((m.get("veg", {}) as Dictionary).get("card", false))
	if _force_stub:
		return _box(m, card)
	var path := _kit.cached_path(name)
	if path.is_empty():
		return null
	var key := path + ("#card" if card else "")
	if not _meshes.has(key):
		_meshes[key] = _parse(path, card)
	return _meshes[key]


static func surface_name(material: String, card: bool) -> String:
	return material + "_card" if card and material == "ct_veg" else material


static func _box(m: Dictionary, card := false) -> ArrayMesh:
	var lo := Vector3(m["aabb_in"][0][0], m["aabb_in"][0][1], m["aabb_in"][0][2]) * IN_M
	var hi := Vector3(m["aabb_in"][1][0], m["aabb_in"][1][1], m["aabb_in"][1][2]) * IN_M
	var box := BoxMesh.new()
	box.size = hi - lo
	var arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours := PackedColorArray()
	for i in verts.size():
		verts[i] += (lo + hi) * 0.5
		colours.append(Color(0.5, 0.5, 0.5, 0.0))   # the contract's neutral tint (x 0.5) and no grime
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_name(0, surface_name(m["materials"][0], card))
	return out


static func _parse(path: String, card := false) -> ArrayMesh:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("BoardgenDressKit: cannot parse %s" % path)
		return null
	var root := doc.generate_scene(state)
	if root == null:
		return null
	var found := [root] if root is MeshInstance3D else root.find_children("*", "MeshInstance3D", true, false)
	var src: ArrayMesh = (found[0] as MeshInstance3D).mesh as ArrayMesh if not found.is_empty() else null
	var out: ArrayMesh = null
	if src != null:
		out = ArrayMesh.new()
		for s in src.get_surface_count():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
			var mat := src.surface_get_material(s)
			out.surface_set_name(s, surface_name(mat.resource_name if mat != null else "", card))
	root.free()
	return out
