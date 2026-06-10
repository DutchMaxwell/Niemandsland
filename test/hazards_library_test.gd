extends GdUnitTestSuite
## Tests HazardsLibrary manifest parsing + cache resolution (no network involved).
## Mirrors containers_library_test.gd; see docs/ASSET_DELIVERY.md.


func _lib() -> HazardsLibrary:
	var lib := HazardsLibrary.new()
	add_child(lib)
	return auto_free(lib)


func _manifest(panels: Dictionary) -> String:
	return JSON.stringify({"version": 1, "base_url": "https://cdn/", "panels": panels})


func test_manifest_parse_and_has_panel() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_manifest({"mine_top": {"url": "m.webp", "sha256": "abc", "size": 10}}))
	assert_bool(lib.has_panel("mine_top")).is_true()
	assert_bool(lib.has_panel("nope")).is_false()


func test_unknown_panel_returns_empty_cached_path() -> void:
	var lib := _lib()
	assert_str(lib.get_cached_path("unknown")).is_equal("")


func test_all_panels_cached_false_before_download() -> void:
	var lib := _lib()
	var panels := {}
	for panel in HazardsLibrary.RUNTIME_PANELS:
		panels[panel] = {"url": panel + ".webp", "sha256": "hazlib_missing_" + panel, "size": 1}
	lib.apply_manifest_text(_manifest(panels))
	assert_bool(lib.all_panels_cached()).is_false()


func test_get_cached_path_when_file_present() -> void:
	var lib := _lib()
	var sha := "hazlib_cachetest_123"
	lib.apply_manifest_text(_manifest({"mine_top": {"url": "m.webp", "sha256": sha, "size": 1}}))
	assert_str(lib.get_cached_path("mine_top")).is_equal("")

	var path := "user://hazards_cache/%s.webp" % sha
	DirAccess.make_dir_recursive_absolute("user://hazards_cache")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()

	assert_str(lib.get_cached_path("mine_top")).is_equal(path)
	DirAccess.remove_absolute(path)  # cleanup


func test_bundled_manifest_covers_all_runtime_panels() -> void:
	# The committed assets/hazards_manifest.json must list every panel the renderer draws.
	var lib := _lib()
	for panel in HazardsLibrary.RUNTIME_PANELS:
		assert_bool(lib.has_panel(panel)).is_true()