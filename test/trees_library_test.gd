extends GdUnitTestSuite
## Tests TreesLibrary manifest parsing + cache resolution (no network involved).
## Mirrors ruins_library_test.gd; see docs/ASSET_DELIVERY.md.


func _lib() -> TreesLibrary:
	var lib := TreesLibrary.new()
	add_child(lib)
	return auto_free(lib)


func _manifest(panels: Dictionary) -> String:
	return JSON.stringify({"version": 1, "base_url": "https://cdn/", "panels": panels})


func test_manifest_parse_and_has_panel() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_manifest({"tree_a": {"url": "t.webp", "sha256": "abc", "size": 10}}))
	assert_bool(lib.has_panel("tree_a")).is_true()
	assert_bool(lib.has_panel("nope")).is_false()


func test_unknown_panel_returns_empty_cached_path() -> void:
	var lib := _lib()
	assert_str(lib.get_cached_path("unknown")).is_equal("")


func test_all_panels_cached_false_before_download() -> void:
	var lib := _lib()
	var panels := {}
	for panel in TreesLibrary.RUNTIME_PANELS:
		panels[panel] = {"url": panel + ".webp", "sha256": "treeslib_missing_" + panel, "size": 1}
	lib.apply_manifest_text(_manifest(panels))
	assert_bool(lib.all_panels_cached()).is_false()


func test_get_cached_path_when_file_present() -> void:
	var lib := _lib()
	var sha := "treeslib_cachetest_123"
	lib.apply_manifest_text(_manifest({"tree_a": {"url": "t.webp", "sha256": sha, "size": 1}}))
	# Not downloaded yet → empty.
	assert_str(lib.get_cached_path("tree_a")).is_equal("")

	# Simulate a cached download.
	var path := "user://trees_cache/%s.webp" % sha
	DirAccess.make_dir_recursive_absolute("user://trees_cache")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()

	assert_str(lib.get_cached_path("tree_a")).is_equal(path)
	DirAccess.remove_absolute(path)  # cleanup


func test_get_texture_uncached_panel_is_null() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_manifest({"tree_a": {"url": "t.webp", "sha256": "treeslib_nofile", "size": 1}}))
	assert_object(lib.get_texture("tree_a")).is_null()
	assert_object(lib.get_texture("unknown")).is_null()


func test_bundled_manifest_covers_all_runtime_panels() -> void:
	# The committed assets/trees_manifest.json must list every panel the renderer draws.
	var lib := _lib()
	for panel in TreesLibrary.RUNTIME_PANELS:
		assert_bool(lib.has_panel(panel)).is_true()