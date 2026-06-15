class_name HazardsLibrary
extends Node
## Resolves the minefield hazard textures (anti-tank mine top, warning sign) to image
## files delivered on demand from R2.
##
## A small bundled manifest (assets/hazards_manifest.json) maps each panel name ->
## { url, sha256, size }. The WebPs live on Cloudflare R2 and are downloaded + cached
## locally the first time a map with dangerous terrain is shown; until then the
## renderer keeps its holographic props (see terrain_overlay.gd). Mirrors
## ContainersLibrary; see docs/ASSET_DELIVERY.md.
## Art recipe lives in the offline asset-pipeline repo.

# === Constants ===

const BUNDLED_MANIFEST_PATH: String = "res://assets/hazards_manifest.json"
const CACHE_DIR: String = "user://hazards_cache"
const FILE_EXTENSION: String = "webp"
const MODEL_FILE_EXTENSION: String = "glb"

## Panels the minefield renderer draws.
const RUNTIME_PANELS: Array[String] = ["mine_top", "warning_sign"]

# === Private variables ===

var _downloader: AssetDownloadManager = null
var _model_downloader: AssetDownloadManager = null
var _panels: Dictionary = {}    # panel name -> { url, sha256, size }
var _models: Dictionary = {}    # model name -> { url, sha256, size } (textured GLBs, e.g. lava_crater)
var _base_url: String = ""      # optional prefix for relative entry URLs
var _textures: Dictionary = {}  # panel name -> Texture2D (decoded once, then reused)
## Parsed hazard-model PackedScenes keyed by cached file PATH, shared across instances
## (the in-game overlay and the menu diorama both build hazards). Parse once, reuse.
static var _model_scene_cache: Dictionary = {}

# === Lifecycle ===

func _ready() -> void:
	_downloader = AssetDownloadManager.new()
	_downloader.name = "HazardsDownloadManager"
	_downloader.cache_dir = CACHE_DIR
	_downloader.file_extension = FILE_EXTENSION
	add_child(_downloader)
	_model_downloader = AssetDownloadManager.new()
	_model_downloader.name = "HazardModelsDownloadManager"
	_model_downloader.cache_dir = CACHE_DIR
	_model_downloader.file_extension = MODEL_FILE_EXTENSION
	add_child(_model_downloader)
	_load_bundled_manifest()

# === Public API ===

func has_panel(panel: String) -> bool:
	return _panels.has(panel)


## True when every runtime panel is already in the local cache (sync, no network).
func all_panels_cached() -> bool:
	for panel in RUNTIME_PANELS:
		if get_cached_path(panel).is_empty():
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
## Returns true when the full set is available afterwards, false otherwise.
func ensure_all_panels() -> bool:
	var ok := true
	for panel in RUNTIME_PANELS:
		var entry: Dictionary = _panels.get(panel, {})
		if entry.is_empty():
			ok = false
			continue
		var path: String = await _downloader.ensure(_resolve_url(entry), entry.get("sha256", ""))
		if path.is_empty():
			ok = false
	return ok


## Ensures a SINGLE panel is cached (downloads it if missing). Awaitable; true if the
## panel is available afterwards. For panels OUTSIDE RUNTIME_PANELS (e.g. the volcanic
## lava pool) that must not gate the mine/warning-sign set.
func ensure_panel(panel: String) -> bool:
	var entry: Dictionary = _panels.get(panel, {})
	if entry.is_empty():
		return false
	var path: String = await _downloader.ensure(_resolve_url(entry), entry.get("sha256", ""))
	return not path.is_empty()


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
		push_warning("HazardsLibrary: failed to decode panel '%s' from %s" % [panel, path])
		return null
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_textures[panel] = tex
	return tex

# === Models (GLB hazard props, e.g. the volcanic lava crater) ===

## Whether a hazard model's GLB is in the manifest at all.
func has_model(name: String) -> bool:
	return _models.has(name)


## Local path if the model's GLB is already cached, else "" (sync, no network).
func get_cached_model_path(name: String) -> String:
	var entry: Dictionary = _models.get(name, {})
	if entry.is_empty():
		return ""
	var sha: String = entry.get("sha256", "")
	return _model_downloader.cache_path(sha) if _model_downloader.is_cached(sha) else ""


## Ensures a single model's GLB is cached (downloads if missing). Awaitable; true if available.
func ensure_model(name: String) -> bool:
	var entry: Dictionary = _models.get(name, {})
	if entry.is_empty():
		return false
	var path: String = await _model_downloader.ensure(_resolve_url(entry), entry.get("sha256", ""))
	return not path.is_empty()


## Instantiable scene for a cached hazard GLB (parsed once via runtime glTF, then packed +
## cached so subsequent spawns instance instead of re-parsing). Null if not cached/parseable.
func get_model_scene(name: String) -> PackedScene:
	var path := get_cached_model_path(name)
	if path.is_empty():
		return null
	if _model_scene_cache.has(path):
		return _model_scene_cache[path]
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		push_warning("HazardsLibrary: failed to parse GLB '%s' from %s" % [name, path])
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

## TRELLIS material fixes (mirrors TreesLibrary): non-metallic so fill light reads diffuse;
## regenerate mipmaps + anisotropic filtering for runtime glTF textures (which Godot loads
## without a mip chain, godotengine/godot#100481) so they don't shimmer.
static func _fix_runtime_materials(node: Node) -> void:
	var to_check: Array[Node] = [node]
	while not to_check.is_empty():
		var current: Node = to_check.pop_back()
		to_check.append_array(current.get_children())
		if not current is MeshInstance3D:
			continue
		var mi := current as MeshInstance3D
		if mi.mesh == null:
			continue
		for surface_idx in range(mi.mesh.get_surface_count()):
			var mat: Material = mi.mesh.surface_get_material(surface_idx)
			if not mat is StandardMaterial3D:
				continue
			var adjusted := mat.duplicate() as StandardMaterial3D
			adjusted.metallic = 0.0
			adjusted.roughness = 0.9
			adjusted.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
			adjusted.albedo_texture = _ensure_texture_mipmaps(adjusted.albedo_texture)
			adjusted.normal_texture = _ensure_texture_mipmaps(adjusted.normal_texture)
			mi.mesh.surface_set_material(surface_idx, adjusted)


static func _ensure_texture_mipmaps(tex: Texture2D) -> Texture2D:
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.has_mipmaps() or img.is_compressed():
		return tex
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func _set_owner_recursive(node: Node, scene_owner: Node) -> void:
	for child: Node in node.get_children():
		child.owner = scene_owner
		_set_owner_recursive(child, scene_owner)


# === Private helpers ===

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


## Parses a hazards manifest JSON string into the in-memory index (used by tests).
func apply_manifest_text(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_base_url = AssetCDN.expand(data.get("base_url", ""))
	var panels: Variant = data.get("panels", {})
	if typeof(panels) == TYPE_DICTIONARY:
		_panels = panels
	var models: Variant = data.get("models", {})
	if typeof(models) == TYPE_DICTIONARY:
		_models = models
