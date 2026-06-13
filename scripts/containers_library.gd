class_name ContainersLibrary
extends Node
## Resolves the shipping-container face textures to image files delivered on demand
## from R2.
##
## A small bundled manifest (assets/containers_manifest.json) maps each panel name ->
## { url, sha256, size }. The weathered container WebPs live on Cloudflare R2 and are
## downloaded + cached locally the first time a map with blockers is shown; until then
## the renderer keeps its holographic box (see terrain_overlay.gd). Mirrors
## TreesLibrary; see docs/ASSET_DELIVERY.md.
## Art recipe lives in the offline asset-pipeline repo.

# === Constants ===

const BUNDLED_MANIFEST_PATH: String = "res://assets/containers_manifest.json"
const CACHE_DIR: String = "user://containers_cache"
const FILE_EXTENSION: String = "webp"

## Container colourways; each pairs with the "_side" / "_end" / "_top" face panels.
const COLOURWAYS: Array[String] = ["container_red", "container_blue"]
const FACES: Array[String] = ["side", "end", "top"]

# === Private variables ===

var _downloader: AssetDownloadManager = null
var _panels: Dictionary = {}    # panel name -> { url, sha256, size }
var _base_url: String = ""      # optional prefix for relative entry URLs
var _textures: Dictionary = {}  # panel name -> Texture2D (decoded once, then reused)

# === Lifecycle ===

func _ready() -> void:
	_downloader = AssetDownloadManager.new()
	_downloader.name = "ContainersDownloadManager"
	_downloader.cache_dir = CACHE_DIR
	_downloader.file_extension = FILE_EXTENSION
	add_child(_downloader)
	_load_bundled_manifest()

# === Public API ===

func has_panel(panel: String) -> bool:
	return _panels.has(panel)


## True when every runtime panel of the given biome theme (name prefix, e.g.
## "tundra_") is already in the local cache (sync, no network).
func all_panels_cached(theme_prefix: String = "") -> bool:
	for colourway in COLOURWAYS:
		for face in FACES:
			if get_cached_path("%s%s_%s" % [theme_prefix, colourway, face]).is_empty():
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
func ensure_all_panels(theme_prefix: String = "") -> bool:
	var ok := true
	for colourway in COLOURWAYS:
		for face in FACES:
			var entry: Dictionary = _panels.get("%s%s_%s" % [theme_prefix, colourway, face], {})
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
		push_warning("ContainersLibrary: failed to decode panel '%s' from %s" % [panel, path])
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


## Parses a containers manifest JSON string into the in-memory index (used by tests).
func apply_manifest_text(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_base_url = AssetCDN.expand(data.get("base_url", ""))
	var panels: Variant = data.get("panels", {})
	if typeof(panels) == TYPE_DICTIONARY:
		_panels = panels
