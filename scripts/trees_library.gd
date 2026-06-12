class_name TreesLibrary
extends Node
## Resolves the deciduous-tree billboard panels to image files delivered on demand from R2.
##
## A small bundled manifest (assets/trees_manifest.json) maps each panel name ->
## { url, sha256, size }. The keyed-alpha tree WebPs live on Cloudflare R2 and are
## downloaded + cached locally the first time a map with forests is shown; until then
## the renderer keeps its procedural fallback tree (see terrain_overlay.gd). Textures
## are decoded from the WebP bytes at runtime so the authored hard alpha edges survive
## (alpha scissor needs them). Mirrors RuinsLibrary; see docs/ASSET_DELIVERY.md.
## Art recipe: tools/model_forge/generate_trees.py.

# === Constants ===

const BUNDLED_MANIFEST_PATH: String = "res://assets/trees_manifest.json"
const CACHE_DIR: String = "user://trees_cache"
const FILE_EXTENSION: String = "webp"
const MODEL_FILE_EXTENSION: String = "glb"

## Tree billboard panels the renderer draws: three deciduous silhouettes (side view)
## plus their bird's-eye crowns (the horizontal "crown cap" hiding the X from above).
const RUNTIME_PANELS: Array[String] = [
	"tree_a", "tree_b", "tree_c",
	"tree_a_top", "tree_b_top", "tree_c_top",
]

## The side-view variants a tree picks from (each pairs with "<name>_top").
const TREE_VARIANTS: Array[String] = ["tree_a", "tree_b", "tree_c"]

# === Private variables ===

var _downloader: AssetDownloadManager = null
var _model_downloader: AssetDownloadManager = null
var _panels: Dictionary = {}    # panel name -> { url, sha256, size }
var _models: Dictionary = {}    # variant name -> { url, sha256, size } (textured GLBs)
var _base_url: String = ""      # optional prefix for relative entry URLs
var _textures: Dictionary = {}  # panel name -> Texture2D (decoded once, then reused)
## Parsed tree-model PackedScenes keyed by their cached file PATH (theme-aware), shared
## across ALL TreesLibrary instances for the whole app session. Each terrain overlay
## (in-game AND the menu diorama, rebuilt on every return to the menu) used to own its
## cache and re-parse the ~3 large tree GLBs from scratch — that was the bulk of the
## multi-second menu rebuild. Static = parse once, reuse everywhere.
static var _model_scene_cache: Dictionary = {}

# === Lifecycle ===

func _ready() -> void:
	_downloader = AssetDownloadManager.new()
	_downloader.name = "TreesDownloadManager"
	_downloader.cache_dir = CACHE_DIR
	_downloader.file_extension = FILE_EXTENSION
	add_child(_downloader)
	_model_downloader = AssetDownloadManager.new()
	_model_downloader.name = "TreeModelsDownloadManager"
	_model_downloader.cache_dir = CACHE_DIR
	_model_downloader.file_extension = MODEL_FILE_EXTENSION
	add_child(_model_downloader)
	_load_bundled_manifest()

# === Public API ===

func has_panel(panel: String) -> bool:
	return _panels.has(panel)


## True when every runtime panel of the given biome theme (name prefix, e.g.
## "desert_") is already in the local cache (sync, no network).
func all_panels_cached(theme_prefix: String = "") -> bool:
	for panel in RUNTIME_PANELS:
		if get_cached_path(theme_prefix + panel).is_empty():
			return false
	return true


## Returns the local path if the panel is already cached, else "" (sync).
func get_cached_path(panel: String) -> String:
	var entry: Dictionary = _panels.get(panel, {})
	if entry.is_empty():
		return ""
	var sha: String = entry.get("sha256", "")
	return _downloader.cache_path(sha) if _downloader.is_cached(sha) else ""


## Ensures every runtime panel is cached (downloads the missing ones). Awaitable.
## Returns true when the full set is available afterwards, false otherwise (e.g.
## offline) so the caller can keep its fallback.
func ensure_all_panels(theme_prefix: String = "") -> bool:
	var ok := true
	for panel in RUNTIME_PANELS:
		var entry: Dictionary = _panels.get(theme_prefix + panel, {})
		if entry.is_empty():
			ok = false
			continue
		var path: String = await _downloader.ensure(_resolve_url(entry), entry.get("sha256", ""))
		if path.is_empty():
			ok = false
	return ok


## Decoded texture for a cached panel (mipmapped; decoded once, then reused).
## Returns null if the panel is not cached or fails to decode.
func get_texture(panel: String) -> Texture2D:
	if _textures.has(panel):
		return _textures[panel]
	var path := get_cached_path(panel)
	if path.is_empty():
		return null
	var bytes := FileAccess.get_file_as_bytes(path)
	var img := Image.new()
	if img.load_webp_from_buffer(bytes) != OK:
		push_warning("TreesLibrary: failed to decode panel '%s' from %s" % [panel, path])
		return null
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[panel] = tex
	return tex


## True when every tree variant's textured GLB is already in the local cache (sync).
func all_models_cached(theme_prefix: String = "") -> bool:
	if _models.is_empty():
		return false
	for variant in TREE_VARIANTS:
		if get_cached_model_path(theme_prefix + variant).is_empty():
			return false
	return true


## Returns the local path if the variant's GLB is already cached, else "" (sync).
func get_cached_model_path(variant: String) -> String:
	var entry: Dictionary = _models.get(variant, {})
	if entry.is_empty():
		return ""
	var sha: String = entry.get("sha256", "")
	return _model_downloader.cache_path(sha) if _model_downloader.is_cached(sha) else ""


## Ensures every tree variant's GLB is cached (downloads the missing ones). Awaitable.
## Returns true when the full set is available afterwards, false otherwise.
func ensure_all_models(theme_prefix: String = "") -> bool:
	if _models.is_empty():
		return false
	var ok := true
	for variant in TREE_VARIANTS:
		var entry: Dictionary = _models.get(theme_prefix + variant, {})
		if entry.is_empty():
			ok = false
			continue
		var path: String = await _model_downloader.ensure(_resolve_url(entry), entry.get("sha256", ""))
		if path.is_empty():
			ok = false
	return ok


## Instantiable scene for a cached tree GLB (parsed once via runtime glTF, then packed
## so subsequent spawns instance instead of re-parsing — the meshes stay shared).
## Returns null if the variant is not cached or fails to parse.
func get_model_scene(variant: String) -> PackedScene:
	var path := get_cached_model_path(variant)
	if path.is_empty():
		return null
	if _model_scene_cache.has(path):
		return _model_scene_cache[path]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("TreesLibrary: failed to parse tree GLB '%s' from %s" % [variant, path])
		return null
	var scene_root := doc.generate_scene(state)
	if scene_root == null:
		return null
	_fix_runtime_materials(scene_root)
	_set_owner_recursive(scene_root, scene_root)
	var packed := PackedScene.new()
	var ok := packed.pack(scene_root)
	scene_root.free()
	if ok != OK:
		return null
	_model_scene_cache[path] = packed
	return packed

# === Private helpers ===

static func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = scene_owner
		_set_owner_recursive(child, scene_owner)


## TRELLIS material fixes, mirroring opr_army_manager's mini loader: non-metallic so
## fill light reads as diffuse, and regenerated mipmaps + anisotropic filtering for
## runtime glTF textures, which Godot loads without a mip chain
## (godotengine/godot#100481) so they would shimmer and alias.
static func _fix_runtime_materials(node: Node) -> void:
	var nodes_to_check: Array[Node] = [node]
	while not nodes_to_check.is_empty():
		var current: Node = nodes_to_check.pop_back()
		nodes_to_check.append_array(current.get_children())
		if not current is MeshInstance3D:
			continue
		var mesh_instance := current as MeshInstance3D
		if mesh_instance.mesh == null:
			continue
		for surface_idx in range(mesh_instance.mesh.get_surface_count()):
			var mat: Material = mesh_instance.mesh.surface_get_material(surface_idx)
			if not mat is StandardMaterial3D:
				continue
			var adjusted := mat.duplicate() as StandardMaterial3D
			adjusted.metallic = 0.0
			adjusted.roughness = 0.9
			adjusted.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			adjusted.albedo_texture = _ensure_texture_mipmaps(adjusted.albedo_texture)
			adjusted.normal_texture = _ensure_texture_mipmaps(adjusted.normal_texture)
			mesh_instance.mesh.surface_set_material(surface_idx, adjusted)


static func _ensure_texture_mipmaps(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.has_mipmaps() or img.is_compressed():
		return tex
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _resolve_url(entry: Dictionary) -> String:
	var url: String = entry.get("url", "")
	if url.begins_with("http://") or url.begins_with("https://"):
		return url
	if not _base_url.is_empty():
		return _base_url.path_join(url)
	return url


func _load_bundled_manifest() -> void:
	if not FileAccess.file_exists(BUNDLED_MANIFEST_PATH):
		return
	apply_manifest_text(FileAccess.get_file_as_string(BUNDLED_MANIFEST_PATH))


## Parses a trees manifest JSON string into the in-memory index (also used by tests).
func apply_manifest_text(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_base_url = data.get("base_url", "")
	var panels: Variant = data.get("panels", {})
	if typeof(panels) == TYPE_DICTIONARY:
		_panels = panels
	var models: Variant = data.get("models", {})
	if typeof(models) == TYPE_DICTIONARY:
		_models = models
