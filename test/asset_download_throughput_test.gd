extends GdUnitTestSuite
## Downloads must not depend on the frame rate: the live manifest and big GLBs land while the main
## loop is slow (a model-loading stall), and a dead connection still fails instead of hanging.
## HTTPRequest is non-threaded, so it reads once per frame; the old client read 64 KiB per frame
## under a TOTAL timeout (15 s manifest, 120 s GLB) and lost both races on loaded machines.
## Transfers come from a local `python3 -m http.server`, stopped by its own pid.

const SERVE_DIR: String = "user://dlfix_throughput_test"

var _server_pid: int = -1
var _slow: Node = null


## Sleeps in every frame: holds the main loop at 1000 / ms FPS.
class SlowFrames extends Node:
	var ms: int = 250

	func _process(_delta: float) -> void:
		OS.delay_msec(ms)


func after_test() -> void:
	if _slow != null and is_instance_valid(_slow):
		_slow.free()
	_slow = null
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1
	OS.unset_environment("NML_MANIFEST_URL")
	for sub in ["cache", ""]:
		var dir := SERVE_DIR.path_join(sub)
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir.path_join(f))


func _slow_down(ms: int) -> void:
	_slow = SlowFrames.new()
	_slow.ms = ms
	add_child(_slow)


## Serves SERVE_DIR on a localhost port; the base URL, or "" if the server never came up.
func _start_server() -> String:
	var port := 20000 + randi() % 20000
	_server_pid = OS.create_process("python3", ["-m", "http.server", str(port), "--bind", "127.0.0.1",
		"--directory", ProjectSettings.globalize_path(SERVE_DIR)])
	var deadline := Time.get_ticks_msec() + 10000
	while _server_pid > 0 and Time.get_ticks_msec() < deadline:
		var tcp := StreamPeerTCP.new()
		tcp.connect_to_host("127.0.0.1", port)
		for _i in range(20):
			tcp.poll()
			if tcp.get_status() == StreamPeerTCP.STATUS_CONNECTED:
				tcp.disconnect_from_host()
				return "http://127.0.0.1:%d" % port
			OS.delay_msec(10)
		OS.delay_msec(100)
	return ""


## Writes `mib` MiB to SERVE_DIR/name; returns its sha256.
func _write_blob(file_name: String, mib: int) -> String:
	DirAccess.make_dir_recursive_absolute(SERVE_DIR)
	var path := SERVE_DIR.path_join(file_name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	var block := PackedByteArray()
	block.resize(1 << 20)
	for i in range(mib):
		block[0] = i % 256
		f.store_buffer(block)
	f.close()
	return FileAccess.get_sha256(path)


func _manager() -> AssetDownloadManager:
	var m := AssetDownloadManager.new()
	m.cache_dir = SERVE_DIR.path_join("cache")
	add_child(m)
	return auto_free(m)


func _batch_into(m: AssetDownloadManager, entries: Array, retries: int, state: Dictionary) -> void:
	await m.ensure_batch_parallel(entries, 1, retries)
	state["done"] = true


func _ensure_into(m: AssetDownloadManager, url: String, sha: String, out: Dictionary) -> void:
	out["path"] = await m.ensure(url, sha)


## Pumps frames until `state[key]` exists or `ms` pass; returns the elapsed ms.
func _wait_for(state: Dictionary, key: String, ms: int) -> int:
	var t0 := Time.get_ticks_msec()
	while not state.has(key) and Time.get_ticks_msec() - t0 < ms:
		await get_tree().process_frame
	return Time.get_ticks_msec() - t0


func test_requests_read_megabytes_per_frame_without_a_total_timeout() -> void:
	assert_int(AssetDownloadManager.CHUNK_SIZE).is_greater_equal(1 << 20)
	var http: HTTPRequest = _manager()._http
	assert_int(http.download_chunk_size).is_greater_equal(1 << 20)
	assert_float(http.timeout).is_equal(0.0)   # a total budget kills slow-but-live transfers
	assert_bool(http.use_threads).is_false()   # threaded: busy-waits a core, cancel can freeze


## 50 MB (the largest Ratmen blob is 60.8 MB) at ~4 FPS. The old client needed ~200 s for this,
## beyond its 120 s per-attempt timeout. The stall window is shortened to ~1 s here, so the ~5 s
## transfer also proves the guard counts PROGRESS, not total time.
func test_50mb_glb_downloads_while_the_main_loop_is_slow() -> void:
	var sha := _write_blob("big.glb", 50)
	var base := _start_server()
	assert_str(base).override_failure_message("python3 http.server did not start").is_not_empty()
	var m := _manager()
	m.set("stall_timeout_sec", 1.0)   # set(): a runtime no-op, not a parse error, on the old client
	m.set("stall_min_frames", 8)
	var dest := m.cache_path(sha)
	_slow_down(250)
	var state := {}
	_batch_into(m, [{"url": base + "/big.glb", "sha256": sha, "path": dest}], 0, state)
	var ms := await _wait_for(state, "done", 60000)
	assert_bool(FileAccess.file_exists(dest)) \
		.override_failure_message("50 MB not downloaded after %d ms at ~4 FPS" % ms).is_true()


## Slow boot frames (1 FPS) must not cost the live manifest: the old 64 KiB / 15 s client kept the
## bundled fallback on 5 of 6 loaded boots, so newly published factions showed as placeholders.
func test_live_manifest_arrives_while_the_main_loop_is_slow() -> void:
	assert_bool(FileAccess.file_exists("user://manifest_override.json")) \
		.override_failure_message("a local manifest override would bypass the fetch").is_false()
	DirAccess.make_dir_recursive_absolute(SERVE_DIR)
	var manifest := {"version": 1, "base_url": "{cdn}/", "padding": "x".repeat(2 << 20),
		"models": {"dlfix_probe/probe_unit": {"url": "p.glb", "sha256": "00", "size": 1}}}
	var f := FileAccess.open(SERVE_DIR.path_join("model_manifest.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(manifest))
	f.close()
	var base := _start_server()
	assert_str(base).override_failure_message("python3 http.server did not start").is_not_empty()
	OS.set_environment("NML_MANIFEST_URL", base + "/model_manifest.json")
	_slow_down(1000)
	var lib := ModelLibrary.new()
	var got := {}
	lib.manifest_refreshed.connect(func(n: int) -> void: got["n"] = n)
	add_child(lib)
	auto_free(lib)
	var ms := await _wait_for(got, "n", 30000)
	assert_bool(lib.has_model("dlfix_probe", "Probe Unit")) \
		.override_failure_message("live manifest not applied after %d ms at 1 FPS" % ms).is_true()


## Without a total timeout, the stall guard is all that stands between a dead link and a loading
## overlay that hangs forever: a server that accepts and never answers must FAIL both paths.
func test_stalled_download_fails_instead_of_hanging() -> void:
	var server := TCPServer.new()
	var port := 20000 + randi() % 20000
	assert_int(server.listen(port, "127.0.0.1")).is_equal(OK)
	var m := _manager()
	m.set("stall_timeout_sec", 1.0)
	m.set("stall_min_frames", 5)
	var url := "http://127.0.0.1:%d/dead.glb" % port
	var out := {}
	_ensure_into(m, url, "dlfix_stall_serial", out)
	var serial_ms := await _wait_for(out, "path", 15000)
	var state := {}
	_batch_into(m, [{"url": url, "sha256": "dlfix_stall_pool", "path": m.cache_path("dlfix_stall_pool")}], 0, state)
	var pool_ms := await _wait_for(state, "done", 15000)
	server.stop()
	assert_str(str(out.get("path", "<hung>"))) \
		.override_failure_message("serial ensure() still hanging after %d ms" % serial_ms).is_empty()
	assert_bool(state.has("done")) \
		.override_failure_message("parallel batch still hanging after %d ms" % pool_ms).is_true()
