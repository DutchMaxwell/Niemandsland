class_name BoardgenKit
extends Node
## Loader for the authored kit modules of the Tiefwerk board look (rails, ladders, pipes, lamps ...): small hard-surface GLBs in the
## project's GLB norm (metres, +Y up, origin on the mounting face, bevelled, baked AO in the vertex colours), delivered on demand from R2
## through assets/tiefwerk_manifest.json - the HazardsLibrary pattern, see docs/ASSET_DELIVERY.md. ONE shared material draws every module
## (vertex colour = part tone x baked AO, the MultiMesh instance colour = the tint), so the whole kit stays one material.
## get_mesh() is null until a module is cached: the caller keeps its own primitive, the procedural look is the fallback (offline, Low, web).
## Dev override: NML_TIEFWERK_KIT_DIR = a folder of <module>.glb files, read without manifest or network.
## Keyed by board theme: BoardgenKit.new("ruintown") reads res://assets/ruintown_manifest.json, caches in user://ruintown_cache and takes its dev
## folder from NML_RUINTOWN_KIT_DIR (the consts below are the default theme's, "tiefwerk").

const BUNDLED_MANIFEST_PATH := "res://assets/tiefwerk_manifest.json"
const CACHE_DIR := "user://tiefwerk_cache"
const DIR_ENV := "NML_TIEFWERK_KIT_DIR"
const DEFAULT_THEME := "tiefwerk"

signal prefetched(all_cached: bool)

var local_dir := ""   # a folder of <module>.glb (tests, dev); empty = the manifest and the cache
var theme_id := DEFAULT_THEME
var _downloader: AssetDownloadManager
var _modules: Dictionary = {}   # module name -> { url, sha256, size }
var _base_url := ""
static var _meshes: Dictionary = {}   # cached file PATH -> parsed Mesh, shared by every board
static var _material: StandardMaterial3D


func _init(theme := DEFAULT_THEME) -> void:   # (not _ready: a board builds before it is in the tree)
	theme_id = theme
	_downloader = AssetDownloadManager.new()
	_downloader.name = "TiefwerkKitDownloads"
	_downloader.cache_dir = cache_dir_of(theme)
	add_child(_downloader)
	local_dir = OS.get_environment(dir_env_of(theme))
	if FileAccess.file_exists(manifest_path_of(theme)):
		apply_manifest_text(FileAccess.get_file_as_string(manifest_path_of(theme)))


## The bundled manifest, the cache folder and the dev-folder variable of a theme's kit.
static func manifest_path_of(theme: String) -> String:
	return "res://assets/%s_manifest.json" % theme


static func cache_dir_of(theme: String) -> String:
	return "user://%s_cache" % theme


static func dir_env_of(theme: String) -> String:
	return "NML_%s_KIT_DIR" % theme.to_upper()


## Parses a manifest JSON string ({"base_url", "models": {name: {url, sha256, size}}}) into the index (also used by tests).
func apply_manifest_text(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_base_url = AssetCDN.expand(data.get("base_url", ""))
	_modules = data.get("models", {}) if typeof(data.get("models", {})) == TYPE_DICTIONARY else {}


## Every module the manifest lists (what a board may ask for).
func module_names() -> Array:
	return _modules.keys()


func has_module(module: String) -> bool:
	return _modules.has(module) or not _local_path(module).is_empty()


## The local GLB of a module, or "" when it is not cached (sync, no network).
func cached_path(module: String) -> String:
	var local := _local_path(module)
	if not local.is_empty():
		return local
	var sha: String = _modules.get(module, {}).get("sha256", "")
	return _downloader.cache_path(sha) if not sha.is_empty() and _downloader.is_cached(sha) else ""


## The kit is for Medium and up on the Forward+ renderer: Performance / Low and the web build (Compatibility) keep the procedural look and cost.
static func wanted_for(preset: int, compatibility: bool) -> bool:
	return preset >= GraphicsSettings.QualityPreset.MEDIUM and not compatibility


## True when the kit is wanted by the current preset / renderer AND every module of `names` is cached: the callers' one question.
func usable(names: Array) -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var graphics: Node = tree.root.get_node_or_null("GraphicsSettings") if tree != null else null
	var preset := int(graphics.current_preset) if graphics != null else GraphicsSettings.QualityPreset.MEDIUM
	return wanted_for(preset, RenderingServer.get_current_rendering_method() == "gl_compatibility") and all_cached(names)


func all_cached(names: Array) -> bool:
	return names.all(func(n: String) -> bool: return not cached_path(n).is_empty())


## One MultiMeshInstance3D named `node_name` under `parent` that draws `mesh` once per {xf, colour} item. A mesh that casts shadows is drawn
## again in every shadow cascade: small thin modules leave it off (the draw-call budget of the board). Returns the node (for a material_override).
static func add_multimesh(parent: Node3D, node_name: String, mesh: Mesh, items: Array, cast_shadows := true) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = items.size()
	for i in items.size():
		mm.set_instance_transform(i, items[i]["xf"])
		mm.set_instance_color(i, items[i]["colour"])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mmi)
	return mmi


## Downloads the missing modules among `names` (awaitable); emits prefetched(true) when every one is cached afterwards.
func prefetch(names: Array) -> void:
	if not is_inside_tree():
		return
	var todo: Array = []
	for n: String in names:
		var e: Dictionary = _modules.get(n, {})
		if cached_path(n).is_empty() and not e.is_empty():
			var url: String = e.get("url", "")
			todo.append({"url": url if url.begins_with("http") else _base_url.path_join(url), "sha256": e.get("sha256", ""), "path": _downloader.cache_path(e.get("sha256", ""))})
	await _downloader.ensure_batch_parallel(todo)
	prefetched.emit(all_cached(names))


## The module's mesh (every surface on the shared material, LODs generated), or `fallback` when it is not cached or does not parse.
func mesh_or(module: String, fallback: Mesh = null) -> Mesh:
	var path := cached_path(module)
	if path.is_empty():
		return fallback
	if not _meshes.has(path):
		_meshes[path] = _parse(path)
	return _meshes[path] if _meshes[path] != null else fallback


## The one material of the whole kit: the vertex colour (tone x AO) times the instance colour (tint), both read as sRGB like the other boardgen kits.
static func material() -> StandardMaterial3D:
	if _material == null:
		_material = StandardMaterial3D.new()
		_material.vertex_color_use_as_albedo = true
		_material.vertex_color_is_srgb = true
		_material.roughness = 0.6
		_material.metallic = 0.4
	return _material


func _local_path(module: String) -> String:
	var p := local_dir.path_join(module + ".glb")
	return p if not local_dir.is_empty() and FileAccess.file_exists(p) else ""


static func _parse(path: String) -> Mesh:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("BoardgenKit: cannot parse %s" % path)
		return null
	var root := doc.generate_scene(state)
	if root == null:
		return null
	var found := [root] if root is MeshInstance3D else root.find_children("*", "MeshInstance3D", true, false)   # a one-node glTF IS the mesh
	var mesh: ArrayMesh = (found[0] as MeshInstance3D).mesh as ArrayMesh if not found.is_empty() else null
	root.free()
	return with_lods(mesh).get_mesh() if mesh != null else null


## The mesh with its surfaces on the shared material and the LODs of the engine's simplifier (far views draw fewer triangles).
static func with_lods(mesh: ArrayMesh) -> ImporterMesh:
	var im := ImporterMesh.new()
	for s in mesh.get_surface_count():
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, mesh.surface_get_arrays(s), [], {}, material())
	im.generate_lods(25.0, 60.0, [])
	return im


## GEN-13: may a player lay a generated board of kit `theme` ("tiefwerk", "ruintown") now? {"state", "pct"}: "ready" (every
## module and texture set cached), "not_used" (this run draws no kit - headless, below Medium, Compatibility - nothing to wait
## for), or "waiting" with the cached share while the download runs under `holder` (the first ask starts it; ask again to
## follow it). The setup's board card asks this through main.gd's door before any board exists.
static func wait_state(holder: Node, theme: String) -> Dictionary:
	if DisplayServer.get_name() == "headless":
		return {"state": "not_used", "pct": 100}
	var kit := holder.get_node_or_null("KitWait_" + theme) as BoardgenKit
	if kit == null:
		kit = BoardgenKit.new(theme)
		kit.name = "KitWait_" + theme
		holder.add_child(kit)
		var made := TiefwerkLibrary.new(theme)
		made.name = "Sets"
		kit.add_child(made)
	if not kit.usable([]):
		return {"state": "not_used", "pct": 100}
	var lib := kit.get_node("Sets") as TiefwerkLibrary
	var names := kit.module_names()
	var done := names.filter(func(n: String) -> bool: return not kit.cached_path(n).is_empty()).size()
	var sets_ok := lib.set_names().is_empty() or lib.sets_cached()
	if done == names.size() and sets_ok:
		return {"state": "ready", "pct": 100}
	if not kit.has_meta("started"):
		kit.set_meta("started", true)
		kit.prefetch(names)
		if not sets_ok:
			lib.ensure_sets()
	return {"state": "waiting", "pct": int(100.0 * (done + int(sets_ok)) / (names.size() + 1))}
