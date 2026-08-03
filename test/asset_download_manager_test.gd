extends GdUnitTestSuite
## Tests AssetDownloadManager cache addressing + is_cached (no network involved).


## Fake downloader for the NML-958 duel tests: counts how often two requests for the
## SAME final cache path run at once (the bug), and how many downloads happened at all.
class RaceProbeManager extends AssetDownloadManager:
	static var active: Dictionary = {}   # final cache path -> currently running requests
	static var overlaps: int = 0
	static var performed: int = 0

	func _perform_request(_url: String, sha256: String) -> bool:
		var key := cache_path(sha256)
		if int(active.get(key, 0)) > 0:
			overlaps += 1
		active[key] = int(active.get(key, 0)) + 1
		performed += 1
		for _i in range(3):
			await get_tree().process_frame   # keep the download "in flight" for a while
		var f := FileAccess.open(key, FileAccess.WRITE)
		f.store_string("payload")
		f.close()
		active[key] = int(active.get(key, 0)) - 1
		return true


## Fake downloader whose request never completes (stalled download).
class StuckProbeManager extends AssetDownloadManager:
	signal never_completes

	func _perform_request(_url: String, _sha256: String) -> bool:
		await never_completes
		return false


func _mgr() -> AssetDownloadManager:
	var m := AssetDownloadManager.new()
	add_child(m)
	return auto_free(m)


## Fire-and-forget ensure; records the result once it lands (mirrors how the two
## menu libraries kick off their downloads in the same frame).
func _ensure_into(m: AssetDownloadManager, sha: String, results: Dictionary, tag: String) -> void:
	results[tag] = await m.ensure("https://cdn.invalid/" + sha, sha)


func test_cache_path_is_content_addressed() -> void:
	var m := _mgr()
	assert_str(m.cache_path("abc123")).is_equal("user://model_cache/abc123.glb")


func test_empty_sha_is_not_cached() -> void:
	var m := _mgr()
	assert_bool(m.is_cached("")).is_false()


func test_is_cached_reflects_file_presence() -> void:
	var m := _mgr()
	var sha := "deadbeef_adm_cachetest"
	var path := m.cache_path(sha)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	assert_bool(m.is_cached(sha)).is_false()

	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()
	assert_bool(m.is_cached(sha)).is_true()

	DirAccess.remove_absolute(path)  # cleanup
	assert_bool(m.is_cached(sha)).is_false()


## NML-958: two libraries (menu music + diorama war ambience) ensure the same asset
## in the same frame. Without a cross-instance guard both stream into the SAME .part
## file; the loser hashes a half-written or already-renamed file into a bogus
## "sha256 mismatch". The second caller must instead wait and reuse the winner's file.
func test_concurrent_managers_do_not_duel_on_the_same_file() -> void:
	RaceProbeManager.active = {}
	RaceProbeManager.overlaps = 0
	RaceProbeManager.performed = 0
	var a := RaceProbeManager.new()
	var b := RaceProbeManager.new()
	add_child(a)
	add_child(b)
	auto_free(a)
	auto_free(b)
	var sha := "adm_nml958_race"
	var path := a.cache_path(sha)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	var results := {}
	_ensure_into(a, sha, results, "a")
	_ensure_into(b, sha, results, "b")
	var frames := 0
	while results.size() < 2 and frames < 120:
		await get_tree().process_frame
		frames += 1

	assert_int(results.size()).is_equal(2)
	assert_str(str(results.get("a", ""))).is_equal(path)
	assert_str(str(results.get("b", ""))).is_equal(path)
	assert_int(RaceProbeManager.overlaps).is_equal(0)
	assert_int(RaceProbeManager.performed).is_equal(1)
	DirAccess.remove_absolute(path)  # cleanup


## NML-958 guard edge: a manager freed mid-download (e.g. leaving the menu) must
## release its claim, or every later download of the same file would wait forever.
func test_guard_is_released_when_a_downloading_manager_is_freed() -> void:
	var sha := "adm_nml958_freed"
	var stuck := StuckProbeManager.new()
	add_child(stuck)
	RaceProbeManager.active = {}
	RaceProbeManager.overlaps = 0
	RaceProbeManager.performed = 0
	var b := RaceProbeManager.new()
	add_child(b)
	auto_free(b)
	var path := b.cache_path(sha)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

	_ensure_into(stuck, sha, {}, "stuck")
	await get_tree().process_frame   # let the stuck manager claim the download
	stuck.free()                     # scene swap: the node vanishes mid-download

	var results := {}
	_ensure_into(b, sha, results, "b")
	var frames := 0
	while results.size() < 1 and frames < 120:
		await get_tree().process_frame
		frames += 1

	assert_str(str(results.get("b", ""))).is_equal(path)
	DirAccess.remove_absolute(path)  # cleanup
