class_name AssetDownloadManager
extends Node
## Downloads game assets (3D models) on demand from a CDN and caches them locally,
## content-addressed by sha256. Only assets actually needed (e.g. an imported
## army's models) are fetched; cached files are reused across armies and sessions.
## See docs/ASSET_DELIVERY.md.

# === Constants ===

const DEFAULT_CACHE_DIR: String = "user://model_cache"
const CHUNK_SIZE: int = 65536  # 64 KiB streamed to disk
## Per-request total timeout. HTTPRequest defaults to 0 (NEVER times out): a stalled/never-
## completing download (R2 hiccup, dead connection, missing object that hangs instead of 404)
## would leave `request_completed` un-emitted, `_request_active` stuck true, and the serial
## download loop — plus the army loading overlay — hung forever. Generous enough for the largest
## GLBs (~28 MB) on a slow link; a true stall now fails cleanly and falls back to a placeholder.
const REQUEST_TIMEOUT_SEC: float = 120.0

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
	_http.timeout = REQUEST_TIMEOUT_SEC  # never hang forever on a stalled download
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

## Download a batch with BOUNDED PARALLELISM (a small pool of its own HTTPRequests, so the shared
## serial _http path is untouched) + per-item bounded retry. Each entry writes to its EXPLICIT
## `path`, so a caller can mix .glb meshes and .ctex textures in one batch. entries:
## [{url, sha256, path}]. Emits progress_updated(done, total) as items finish. Awaitable.
func ensure_batch_parallel(entries: Array, max_concurrent: int = 5, retries: int = 2) -> void:
	var total: int = entries.size()
	if total == 0:
		return
	var state: Dictionary = {"next": 0, "done": 0}
	var pool: int = clampi(max_concurrent, 1, total)
	for _i in range(pool):
		_batch_worker(entries, state, total, retries)   # fire concurrent workers (no await here)
	while int(state["done"]) < total:
		await get_tree().process_frame


## One worker: pulls entries off the shared cursor and downloads them on its OWN HTTPRequest until the
## batch is exhausted. Multiple run concurrently (they interleave at each request await).
func _batch_worker(entries: Array, state: Dictionary, total: int, retries: int) -> void:
	var http := HTTPRequest.new()
	http.download_chunk_size = CHUNK_SIZE
	http.timeout = REQUEST_TIMEOUT_SEC
	add_child(http)
	while int(state["next"]) < entries.size():
		var my: int = int(state["next"])
		state["next"] = my + 1
		var e: Dictionary = entries[my]
		await _download_to(http, str(e.get("url", "")), str(e.get("sha256", "")), str(e.get("path", "")), retries)
		state["done"] = int(state["done"]) + 1
		progress_updated.emit(int(state["done"]), total)
	http.queue_free()


## Download url → path on the given HTTPRequest, sha-verified, up to retries+1 attempts. True on success.
func _download_to(http: HTTPRequest, url: String, sha256: String, path: String, retries: int) -> bool:
	if url.is_empty() or sha256.is_empty() or path.is_empty():
		return false
	if FileAccess.file_exists(path):
		return true
	var tmp: String = path + ".part"
	for _attempt in range(maxi(retries, 0) + 1):
		http.download_file = tmp
		if http.request(url) != OK:
			await get_tree().process_frame
			continue
		var res: Array = await http.request_completed
		var okc: bool = int(res[0]) == HTTPRequest.RESULT_SUCCESS and int(res[1]) >= 200 and int(res[1]) < 300
		if okc and FileAccess.get_sha256(tmp).to_lower() == sha256.to_lower():
			DirAccess.rename_absolute(tmp, path)
			download_completed.emit(sha256, path, true)
			return true
		if FileAccess.file_exists(tmp):
			DirAccess.remove_absolute(tmp)
	push_warning("AssetDownloadManager: '%s' failed after %d attempt(s)" % [url, maxi(retries, 0) + 1])
	download_completed.emit(sha256, "", false)
	return false


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
