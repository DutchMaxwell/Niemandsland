class_name AssetDownloadManager
extends Node
## Downloads game assets (3D models) on demand from a CDN and caches them locally,
## content-addressed by sha256. Only assets actually needed (e.g. an imported
## army's models) are fetched; cached files are reused across armies and sessions.
## See docs/ASSET_DELIVERY.md.

# === Constants ===

const DEFAULT_CACHE_DIR: String = "user://model_cache"
const CHUNK_SIZE: int = 65536  # 64 KiB streamed to disk

# Cache location + file extension. The defaults suit the GLB model cache; BiomeLibrary
# overrides them (WebP battlemap cache) before the node enters the tree.
var cache_dir: String = DEFAULT_CACHE_DIR
var file_extension: String = "glb"

# === Signals ===

signal download_completed(sha256: String, local_path: String, success: bool)
signal progress_updated(done: int, total: int)

# === Private variables ===

var _http: HTTPRequest = null
var _request_active: bool = false

# === Lifecycle ===

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(cache_dir)
	_http = HTTPRequest.new()
	_http.download_chunk_size = CHUNK_SIZE
	add_child(_http)

# === Public API ===

## Local cache path for a content hash.
func cache_path(sha256: String) -> String:
	return cache_dir.path_join("%s.%s" % [sha256, file_extension])


func is_cached(sha256: String) -> bool:
	return not sha256.is_empty() and FileAccess.file_exists(cache_path(sha256))


## Ensures a single asset is cached, downloading it if missing. Awaitable.
## Returns the local cache path on success, or "" on failure.
func ensure(url: String, sha256: String) -> String:
	if url.is_empty() or sha256.is_empty():
		return ""
	if is_cached(sha256):
		return cache_path(sha256)
	var ok: bool = await _download(url, sha256)
	return cache_path(sha256) if ok else ""


## Ensures a batch of assets is cached (serial downloads), emitting progress.
## entries: Array of { "url": String, "sha256": String }. Awaitable.
func ensure_batch(entries: Array) -> Dictionary:
	var result: Dictionary = {}
	var total: int = entries.size()
	var done: int = 0
	for entry: Dictionary in entries:
		var sha: String = entry.get("sha256", "")
		var path: String = await ensure(entry.get("url", ""), sha)
		if not path.is_empty():
			result[sha] = path
		done += 1
		progress_updated.emit(done, total)
	return result

# === Private helpers ===

## Serialises access to the single shared HTTPRequest: one node can only serve one
## request at a time, so later callers wait their turn instead of failing with ERR_BUSY
## (e.g. picking a biome in the table-size dialog while the default biome battlemap from
## table._ready() is still downloading — the pick used to fail silently with no retry).
func _download(url: String, sha256: String) -> bool:
	while _request_active:
		await get_tree().process_frame
	if is_cached(sha256):
		return true  # an identical queued request landed while we waited
	_request_active = true
	var ok: bool = await _perform_request(url, sha256)
	_request_active = false
	return ok


func _perform_request(url: String, sha256: String) -> bool:
	var tmp: String = cache_path(sha256) + ".part"
	_http.download_file = tmp
	if _http.request(url) != OK:
		download_completed.emit(sha256, "", false)
		return false

	var res: Array = await _http.request_completed
	var result_code: int = res[0]
	var http_code: int = res[1]
	if result_code != HTTPRequest.RESULT_SUCCESS or http_code < 200 or http_code >= 300:
		DirAccess.remove_absolute(tmp)
		download_completed.emit(sha256, "", false)
		return false

	# Verify integrity before trusting the file.
	if FileAccess.get_sha256(tmp).to_lower() != sha256.to_lower():
		DirAccess.remove_absolute(tmp)
		push_warning("AssetDownloadManager: sha256 mismatch for %s" % url)
		download_completed.emit(sha256, "", false)
		return false

	DirAccess.rename_absolute(tmp, cache_path(sha256))
	download_completed.emit(sha256, cache_path(sha256), true)
	return true
