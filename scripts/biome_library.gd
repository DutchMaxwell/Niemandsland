class_name BiomeLibrary
extends Node
## Resolves table biome battlemaps to image files delivered on demand from a CDN.
##
## A small bundled manifest (assets/biome_manifest.json) maps each biome key ->
## { url, sha256, size }. The heavy battlemap WebPs live on Cloudflare R2 and are
## downloaded + cached locally only when a biome is selected; the bundled
## table_surface_default.png is the offline fallback. Mirrors ModelLibrary for minis.
## See docs/ASSET_DELIVERY.md.

# === Constants ===

const BUNDLED_MANIFEST_PATH: String = "res://assets/biome_manifest.json"
const CACHE_DIR: String = "user://biome_cache"
const FILE_EXTENSION: String = "webp"

# === Private variables ===

var _downloader: AssetDownloadManager = null
var _biomes: Dictionary = {}   # biome key -> { url, sha256, size }
var _base_url: String = ""     # optional prefix for relative entry URLs

# === Lifecycle ===

func _ready() -> void:
	_downloader = AssetDownloadManager.new()
	_downloader.name = "BiomeDownloadManager"
	_downloader.cache_dir = CACHE_DIR
	_downloader.file_extension = FILE_EXTENSION
	add_child(_downloader)
	_load_bundled_manifest()

# === Public API ===

func has_biome(biome_key: String) -> bool:
	return _biomes.has(biome_key)


## Returns the local path if the biome's battlemap is already cached, else "" (sync).
func get_cached_path(biome_key: String) -> String:
	var entry: Dictionary = _biomes.get(biome_key, {})
	if entry.is_empty():
		return ""
	var sha: String = entry.get("sha256", "")
	return _downloader.cache_path(sha) if _downloader.is_cached(sha) else ""


## Ensures the biome's battlemap is cached (downloads if needed). Awaitable.
## Returns the local cache path on success, or "" if the biome is unavailable
## (e.g. before the first R2 publish, or offline) so the caller can keep the fallback.
func ensure_biome(biome_key: String) -> String:
	var entry: Dictionary = _biomes.get(biome_key, {})
	if entry.is_empty():
		return ""
	return await _downloader.ensure(_resolve_url(entry), entry.get("sha256", ""))

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


## Parses a biome manifest JSON string into the in-memory index (also used by tests).
func apply_manifest_text(text: String) -> void:
	var data: Variant = JSON.parse_string(text)
	if typeof(data) != TYPE_DICTIONARY:
		return
	_base_url = data.get("base_url", "")
	var biomes: Variant = data.get("biomes", {})
	if typeof(biomes) == TYPE_DICTIONARY:
		_biomes = biomes
