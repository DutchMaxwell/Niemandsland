extends GdUnitTestSuite
## Tests AssetDownloadManager cache addressing + is_cached (no network involved).


func _mgr() -> AssetDownloadManager:
	var m := AssetDownloadManager.new()
	add_child(m)
	return auto_free(m)


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
