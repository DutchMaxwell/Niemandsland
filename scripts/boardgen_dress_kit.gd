class_name BoardgenDressKit
extends RefCounted
## The module kit of the ruin-town dressing (docs/adr/0004-dressing-materials-and-kit-manifest.md): the manifest (assets/ruintown_dress.json: one entry per module with its numbers, plus the materials / ground / sets blocks) and the
## module meshes. A module's GLB comes from the town's BoardgenKit (cached_path: the dev folder NML_RUINTOWN_KIT_DIR or the delivery cache); every surface keeps its own name = the shared material it is drawn
## with (the GLB's material name), so the merge can put all modules of one material into one surface. `force_stub` (tests) draws every module as a box of its aabb: no GLB needed. Meshes are in metres.
## A manifest that cannot be read, or a module it describes badly, is pushed as an error and kept in `errors()`; never traded for a silent default.

const MANIFEST_PATH := "res://assets/ruintown_dress.json"

var meta: Dictionary = {}  # the parsed manifest
var _kit: BoardgenKit
var _force_stub := false
var _specs: Dictionary = {}  # module name -> DressModuleSpec, built once here
var _errors := PackedStringArray()  # what the manifest or a module could not give, one line each
static var _meshes: Dictionary = {}  # GLB path -> parsed ArrayMesh, shared by every board


func _init(kit: BoardgenKit, force_stub := false, manifest_path := MANIFEST_PATH) -> void:
	_kit = kit
	_force_stub = force_stub
	_build(manifest_path)
	for line in _errors:
		push_error("BoardgenDressKit: " + line)


## Builds one spec per manifest module and records every problem; a manifest that cannot be read
## leaves the kit with no specs instead of a silent default.
func _build(path: String) -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		_errors.append("manifest %s cannot be parsed" % path)
		return
	meta = data
	var raw_modules: Variant = meta.get("modules")
	if typeof(raw_modules) != TYPE_DICTIONARY:
		_errors.append("manifest %s has no modules block" % path)
		return
	var raw_materials: Variant = meta.get("materials", {})
	var materials: Dictionary = raw_materials if typeof(raw_materials) == TYPE_DICTIONARY else {}
	if typeof(raw_materials) != TYPE_DICTIONARY:
		_errors.append("manifest %s: the materials block is not an object" % path)
	for name: String in raw_modules:
		var entry: Variant = raw_modules[name]
		if typeof(entry) != TYPE_DICTIONARY:
			_errors.append("module %s: not an object" % name)
			continue
		var spec := DressModuleSpec.from_manifest(name, entry, materials)
		_specs[name] = spec
		if not spec.errors.is_empty():
			_errors.append("module %s: %s" % [name, ", ".join(spec.errors)])


## Every problem of the last build, one line per module (or one for a broken manifest); the same
## lines are pushed as errors, so tests read this instead of catching engine output.
func errors() -> PackedStringArray:
	return _errors.duplicate()


## The number of specs the manifest gave (zero when the manifest or its modules block is broken).
func spec_count() -> int:
	return _specs.size()


## The typed spec of a module (null when the manifest does not know it).
func spec(name: String) -> DressModuleSpec:
	return _specs.get(name)


## The manifest entry of a module ({} when the manifest does not know it).
func module(name: String) -> Dictionary:
	return meta.get("modules", {}).get(name, {})


## True when every module of `names` can be drawn: all are in the manifest and either the stub kit is forced, or none is a stub and the town kit is usable for them (Medium and up, every GLB cached).
func usable(names: Array) -> bool:
	if not names.all(func(n: String) -> bool: return not module(n).is_empty()):
		return false
	return (
		_force_stub
		or (names.all(func(n: String) -> bool: return not module(n)["stub"]) and _kit.usable(names))
	)


## The module's mesh in metres, one surface per material named by it; null when its GLB is not cached (or does not parse). Under force_stub a box of the module's aabb with one surface named by its first material.
## A module with a `variant` (the vegetation cards: "card") names its surfaces of a material that lists that variant `<material>_<variant>`:
## the variants of a material are drawn with different shaders and cannot share a surface.
func mesh(name: String) -> ArrayMesh:
	var m := module(name)
	if m.is_empty():
		return null
	var variant := str(m.get("variant", ""))
	var materials: Dictionary = meta.get("materials", {})
	if _force_stub:
		return _box(m, variant, materials)
	var path := _kit.cached_path(name)
	if path.is_empty():
		return null
	var key := path + ("#" + variant if variant != "" else "")
	if not _meshes.has(key):
		_meshes[key] = _parse(path, variant, materials)
	return _meshes[key]


## The surface (and material) name of `material` drawn by a module of `variant`: `<material>_<variant>` when the material's
## manifest entry lists that variant under `variants`, else the material itself. `materials` = the manifest's materials block.
static func surface_name(material: String, variant: String, materials: Dictionary) -> String:
	var variants: Dictionary = (materials.get(material, {}) as Dictionary).get("variants", {})
	return material + "_" + variant if variant != "" and variants.has(variant) else material


static func _box(m: Dictionary, variant: String, materials: Dictionary) -> ArrayMesh:
	var lo := (
		Vector3(m["aabb_in"][0][0], m["aabb_in"][0][1], m["aabb_in"][0][2]) * Units.INCHES_TO_METERS
	)
	var hi := (
		Vector3(m["aabb_in"][1][0], m["aabb_in"][1][1], m["aabb_in"][1][2]) * Units.INCHES_TO_METERS
	)
	var box := BoxMesh.new()
	box.size = hi - lo
	var arrays := box.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colours := PackedColorArray()
	for i in verts.size():
		verts[i] += (lo + hi) * 0.5
		colours.append(Color(0.5, 0.5, 0.5, 0.0))  # the contract's neutral tint (x 0.5) and no grime
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_COLOR] = colours
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_name(0, surface_name(m["materials"][0], variant, materials))
	return out


static func _parse(path: String, variant: String, materials: Dictionary) -> ArrayMesh:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("BoardgenDressKit: cannot parse %s" % path)
		return null
	var root := doc.generate_scene(state)
	if root == null:
		return null
	var found := (
		[root] if root is MeshInstance3D else root.find_children("*", "MeshInstance3D", true, false)
	)
	var src: ArrayMesh = (
		(found[0] as MeshInstance3D).mesh as ArrayMesh if not found.is_empty() else null
	)
	var out: ArrayMesh = null
	if src != null:
		out = ArrayMesh.new()
		for s in src.get_surface_count():
			out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, src.surface_get_arrays(s))
			var mat := src.surface_get_material(s)
			out.surface_set_name(
				s, surface_name(mat.resource_name if mat != null else "", variant, materials)
			)
	root.free()
	return out
