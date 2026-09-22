class_name AssetDownloadManager
extends Node
## Downloads game assets (3D models) on demand from a CDN and caches them locally,
## content-addressed by sha256. Only assets actually needed (e.g. an imported
## army's models) are fetched; cached files are reused across armies and sessions.
## See docs/ASSET_DELIVERY.md.

# === Constants ===

const DEFAULT_CACHE_DIR: String = "user://model_cache"
## Max bytes read per poll. A non-threaded HTTPRequest polls ONCE PER FRAME, so throughput is capped
## at CHUNK_SIZE x FPS: 64 KiB made a 50 MB GLB need 200 s at 4 FPS (a model-loading stall); 4 MiB
## took 4.6 s (measured, localhost). The buffer only holds what arrived since the last frame.
const CHUNK_SIZE: int = 4 * 1024 * 1024
## Stall guard instead of HTTPRequest.timeout. That timeout is a TOTAL budget, so a big GLB on a
## slow link (or any file while frames stall) ran out of it with bytes still arriving; with NO
## timeout a dead connection would leave `request_completed` un-emitted and the loading overlay hung
## forever. An attempt now fails only when no new byte arrives for STALL_TIMEOUT_SEC of wall time
## AND STALL_MIN_FRAMES polls — the frame floor keeps a slow main loop from looking like a dead link.
const STALL_TIMEOUT_SEC: float = 30.0
const STALL_MIN_FRAMES: int = 60

# Cache location + file extension. The defaults suit the GLB model cache; BiomeLibrary
# overrides them (WebP battlemap cache) before the node enters the tree.
var cache_dir: String = DEFAULT_CACHE_DIR
var file_extension: String = "glb"
# Stall guard thresholds (tests shorten them).
var stall_timeout_sec: float = STALL_TIMEOUT_SEC
var stall_min_frames: int = STALL_MIN_FRAMES

# === Signals ===

signal download_completed(sha256: String, local_path: String, success: bool)
signal progress_updated(done: int, total: int)

# === Private variables ===

## Final cache paths ANY manager instance is currently downloading. Two libraries in
## one tree may ensure the same asset in the same frame (menu music + diorama war
## ambience, NML-958): without a cross-instance guard both stream into the SAME
## .part file, and the loser hashes a half-written or already-renamed file into a
## bogus "sha256 mismatch" (and keeps writing into the winner's verified file).
static var _in_flight: Dictionary = {}

var _http: HTTPRequest = null
var _request_active: bool = false
var _in_flight_key: String = ""  # _in_flight entry held by THIS instance

# === Lifecycle ===

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(cache_dir)
	_http = new_request()
	add_child(_http)


func _exit_tree() -> void:
	# A manager freed mid-download (e.g. leaving the menu) must release its claim,
	# or every later download of the same file would wait forever.
	if not _in_flight_key.is_empty():
		_in_flight.erase(_in_flight_key)
		_in_flight_key = ""

# === Public API ===

## Local cache path for a content hash.
func cache_path(sha256: String) -> String:
	return cache_dir.path_join("%s.%s" % [sha256, file_extension])


func is_cached(sha256: String) -> bool:
	return not sha256.is_empty() and FileAccess.file_exists(cache_path(sha256))


## An HTTPRequest configured for asset/manifest downloads: big chunks, no total timeout (pair every
## request with watch_stall). use_threads stays false on purpose: Godot 4.6's threaded client
## busy-waits for bytes (one core at 100 % per download, measured) and cancel_request() on a dead
## connection blocks the main thread forever (measured: never returned).
static func new_request() -> HTTPRequest:
	var http := HTTPRequest.new()
	http.download_chunk_size = CHUNK_SIZE
	http.timeout = 0.0
	http.use_threads = false
	return http


## Guards ONE in-flight request on `http` (call right after request() returned OK). On a stall it
## cancels the request and emits request_completed with RESULT_TIMEOUT — as HTTPRequest's own
## timeout does — so callers keep a plain `await http.request_completed`.
static func watch_stall(http: HTTPRequest, stall_sec: float = STALL_TIMEOUT_SEC,
		min_frames: int = STALL_MIN_FRAMES) -> void:
	var state: Dictionary = {"done": false}
	var on_done := func(_r: int, _c: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		state["done"] = true
	http.request_completed.connect(on_done, CONNECT_ONE_SHOT)
	var tree: SceneTree = http.get_tree()
	var seen: int = -1
	var since_ms: int = Time.get_ticks_msec()
	var idle_frames: int = 0
	while not state["done"]:
		await tree.process_frame
		if not is_instance_valid(http):
			return   # owner freed mid-download: nothing left to guard
		var got: int = http.get_downloaded_bytes()
		if got != seen:
			seen = got
			since_ms = Time.get_ticks_msec()
			idle_frames = 0
			continue
		idle_frames += 1
		if not state["done"] and idle_frames >= min_frames and Time.get_ticks_msec() - since_ms >= int(stall_sec * 1000.0):
			http.request_completed.disconnect(on_done)
			http.cancel_request()
			http.request_completed.emit(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
			return


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
		if not is_inside_tree():
			return   # owner left the tree mid-batch (the player left the menu): stop waiting quietly
		await get_tree().process_frame


## One worker: pulls entries off the shared cursor and downloads them on its OWN HTTPRequest until the
## batch is exhausted. Multiple run concurrently (they interleave at each request await).
func _batch_worker(entries: Array, state: Dictionary, total: int, retries: int) -> void:
	var http := new_request()
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
		if http.request(url, AssetCDN.headers()) != OK:   # honest product UA (bus 037)
			await get_tree().process_frame
			continue
		watch_stall(http, stall_timeout_sec, stall_min_frames)
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
	# Also wait while ANY other instance downloads the same file; when it succeeds,
	# the is_cached re-check below turns this call into a cache hit. (Resumed
	# coroutines run to their next await one at a time, so leaving the loop and
	# claiming the key below is race-free.)
	var key: String = cache_path(sha256)
	while _request_active or _in_flight.has(key):
		await get_tree().process_frame
	if is_cached(sha256):
		return true  # an identical queued request landed while we waited
	_request_active = true
	_in_flight[key] = true
	_in_flight_key = key
	var ok: bool = await _perform_request(url, sha256)
	_in_flight.erase(key)
	_in_flight_key = ""
	_request_active = false
	return ok


func _perform_request(url: String, sha256: String) -> bool:
	var tmp: String = cache_path(sha256) + ".part"
	_http.download_file = tmp
	if _http.request(url, AssetCDN.headers()) != OK:   # honest product UA (bus 037)
		download_completed.emit(sha256, "", false)
		return false
	watch_stall(_http, stall_timeout_sec, stall_min_frames)

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
