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

## Panels the minefield renderer draws.
const RUNTIME_PANELS: Array[String] = ["mine_top", "warning_sign"]

# === Private variables ===

var _downloader: AssetDownloadManager = null
var _panels: Dictionary = {}    # panel name -> { url, sha256, size }
var _base_url: String = ""      # optional prefix for relative entry URLs
var _textures: Dictionary = {}  # panel name -> Texture2D (decoded once, then reused)

# === Lifecycle ===

func _ready() -> void:
	_downloader = AssetDownloadManager.new()
	_downloader.name = "HazardsDownloadManager"
	_downloader.cache_dir = CACHE_DIR
	_downloader.file_extension = FILE_EXTENSION
	add_child(_downloader)
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
