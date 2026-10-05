class_name CtexLoader
extends RefCounted
## Loads offline-baked .ctex (CompressedTexture2D) textures — downloaded from R2 to user://cache —
## and builds a StandardMaterial3D that stays GPU-compressed in VRAM (BC7 albedo/ORM, BC5 normals).
## See HANDOFF_modelforge_texture_pipeline.md. The manifest carries, alongside the legacy raw-GLB
## `url` (fallback), a `ctex` block: { godot_version, mesh:{url,sha256,size}, textures:{albedo,
## normal?,orm?} }. .ctex is engine-version-coupled (godot#108024) — the version guard falls back
## to the raw GLB on a mismatch. Runtime-load path verified 2026-07-01 (ResourceLoader.load on a
## user:// .ctex → CompressedTexture2D, format 22 = FORMAT_BPTC_RGBA, mipmaps intact).

## True if a `ctex` block baked for `manifest_godot_version` is safe to load on THIS engine. Compares
## major.minor (the manifest may carry "4.6" or "4.6.2"); on mismatch the caller uses the raw GLB.
static func ctex_compatible(manifest_godot_version: String) -> bool:
	if manifest_godot_version.is_empty():
		return false
	var v: Dictionary = Engine.get_version_info()
	var engine_mm := "%d.%d" % [int(v.get("major", 0)), int(v.get("minor", 0))]
	return manifest_godot_version == engine_mm or manifest_godot_version.begins_with(engine_mm + ".")


## Equal texture sets share a material, provided ALL other rendering properties match.
## Weak values and resource IDs in keys do not retain an unloaded army's textures.
static var _material_cache: Dictionary = {}


static func _shared_material(base: Material, changes: Dictionary) -> StandardMaterial3D:
	var source := base as StandardMaterial3D
	if source == null:
		source = StandardMaterial3D.new()
	var signature: Array = []
	for prop in source.get_property_list():
		var key: String = prop.name
		if not (int(prop.usage) & PROPERTY_USAGE_STORAGE) or key.begins_with("resource_") or key.begins_with("metadata/"):
			continue
		var value: Variant = changes.get(key, source.get(key))
		signature.append(key)
		signature.append(value.get_instance_id() if value is Resource else value)
	if _material_cache.has(signature):
		var existing: StandardMaterial3D = _material_cache[signature].get_ref()
		if existing != null:
			return existing
	var material := source.duplicate() as StandardMaterial3D
	for key in changes:
		material.set(key, changes[key])
	_material_cache[signature] = weakref(material)
	return material


## The only shared-material edit: table appearance, once before the first draw.
## Per-model effects must swap materials/overlays instead of mutating this resource.
static func brighten_once(material: StandardMaterial3D) -> void:
	if material.has_meta("ctex_brightened"):
		return
	material.metallic = 0.0
	material.metallic_texture = null
	material.roughness = 0.7
	material.roughness_texture = null
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.set_meta("ctex_brightened", true)


## Load a .ctex from a runtime (user://) path → CompressedTexture2D, or null if missing/unloadable.
## CACHE_MODE_REUSE: every model of a unit (and every unit sharing a texture) gets the SAME texture
## instead of its own upload of identical bytes. Safe because the cache is content-addressed
## (AssetDownloadManager.cache_path = <sha256>.ctex, verified .part → rename): one path, one content.
static func load_ctex(path: String) -> Texture2D:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	return ResourceLoader.load(path, "CompressedTexture2D", ResourceLoader.CACHE_MODE_REUSE) as Texture2D


## Build a StandardMaterial3D from downloaded .ctex paths (normal/orm may be "" / absent):
## albedo → albedo_texture (BC7 sRGB); normal → normal_texture + normal_enabled (BC5, reconstruct Z);
## orm → the glTF metallicRoughness texture: G→roughness, B→metallic. The R channel holds AO ONLY
## when the asset packs it (`orm_has_ao`); otherwise R is undefined, so AO is left off (else it would
## read roughness/metallic from an undefined channel).
static func build_material(albedo_path: String, normal_path: String = "", orm_path: String = "", orm_has_ao: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	var albedo := load_ctex(albedo_path)
	if albedo != null:
		mat.albedo_texture = albedo
	var normal := load_ctex(normal_path)
	if normal != null:
		mat.normal_enabled = true
		mat.normal_texture = normal
	var orm := load_ctex(orm_path)
	if orm != null:
		# CRITICAL: metallic/roughness textures are MULTIPLIED by the scalar factors. A fresh
		# StandardMaterial3D defaults metallic=0.0 → the metallic map would be nullified (the model
		# renders fully non-metallic / too bright). Set both factors to 1.0 so the ORM channels fully
		# drive them (matching glTF's default metallic/roughness factors of 1.0).
		mat.metallic = 1.0
		mat.roughness = 1.0
		mat.roughness_texture = orm
		mat.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
		mat.metallic_texture = orm
		mat.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
		if orm_has_ao:
			mat.ao_enabled = true
			mat.ao_texture = orm
			mat.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	return mat


## Apply downloaded .ctex textures onto a loaded ctex-mesh's OWN surface materials, PRESERVING each
## material's factors — so a class that ships a procedural metallic/roughness baked into the mesh
## (e.g. vehicles: albedo + normal, no ORM) keeps it, while a class with an ORM has metallic/roughness
## driven by the texture. Albedo always applied; normal/orm optional. This is the real per-model entry
## (build_material() is the from-scratch variant for a single prop).
static func apply_to_mesh(mesh_root: Node3D, albedo_path: String, normal_path: String = "", orm_path: String = "", orm_has_ao: bool = false) -> void:
	if mesh_root == null:
		return
	var albedo := load_ctex(albedo_path)
	var normal := load_ctex(normal_path)
	var orm := load_ctex(orm_path)
	for node in mesh_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			var changes := {}
			if albedo != null:
				changes["albedo_texture"] = albedo
			if normal != null:
				changes.merge({"normal_enabled": true, "normal_texture": normal})
			if orm != null:
				changes.merge({"metallic": 1.0, "roughness": 1.0,
					"roughness_texture": orm, "roughness_texture_channel": BaseMaterial3D.TEXTURE_CHANNEL_GREEN,
					"metallic_texture": orm, "metallic_texture_channel": BaseMaterial3D.TEXTURE_CHANNEL_BLUE})
				if orm_has_ao:
					changes.merge({"ao_enabled": true, "ao_texture": orm,
						"ao_texture_channel": BaseMaterial3D.TEXTURE_CHANNEL_RED})
			mi.set_surface_override_material(s, _shared_material(mi.mesh.surface_get_material(s), changes))


## Apply PER-SURFACE ctex materials (contract-v1 multi-material form, I1). `surfaces` = array of
## {surface: int, albedo: path, normal?: path}. Matched to Godot surfaces by index, verified equal to
## the glTF primitive index (Godot imports one surface per primitive, in order). Surfaces with no
## entry keep their base material. Brightness parity is applied afterwards by the caller
## (opr_army_manager._brighten_ctex_materials), same as the single-material path.
static func apply_materials_to_mesh(mesh_root: Node3D, surfaces: Array) -> void:
	if mesh_root == null:
		return
	var by_index: Dictionary = {}   # surface index -> {albedo: Texture2D, normal: Texture2D?}
	for s in surfaces:
		var entry: Dictionary = s
		var tex: Dictionary = {"albedo": load_ctex(str(entry.get("albedo", "")))}
		if entry.has("normal"):
			tex["normal"] = load_ctex(str(entry.get("normal", "")))
		by_index[int(entry.get("surface", -1))] = tex
	var global_index: int = 0
	for node in mesh_root.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.mesh == null:
			continue
		for s in range(mi.mesh.get_surface_count()):
			if by_index.has(global_index):
				var tex: Dictionary = by_index[global_index]
				var changes := {}
				if tex.get("albedo") != null:
					changes["albedo_texture"] = tex["albedo"]
				if tex.get("normal") != null:
					changes.merge({"normal_enabled": true, "normal_texture": tex["normal"]})
				mi.set_surface_override_material(s, _shared_material(mi.mesh.surface_get_material(s), changes))
			global_index += 1
