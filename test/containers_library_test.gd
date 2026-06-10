extends GdUnitTestSuite
## Tests ContainersLibrary manifest parsing + cache resolution (no network involved).
## Mirrors trees_library_test.gd; see docs/ASSET_DELIVERY.md.


func _lib() -> ContainersLibrary:
	var lib := ContainersLibrary.new()
	add_child(lib)
	return auto_free(lib)


func _manifest(panels: Dictionary) -> String:
	return JSON.stringify({"version": 1, "base_url": "https://cdn/", "panels": panels})


func test_manifest_parse_and_has_panel() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_manifest({"container_red_side": {"url": "c.webp", "sha256": "abc", "size": 10}}))
	assert_bool(lib.has_panel("container_red_side")).is_true()
	assert_bool(lib.has_panel("nope")).is_false()


func test_unknown_panel_returns_empty_cached_path() -> void:
	var lib := _lib()
	assert_str(lib.get_cached_path("unknown")).is_equal("")


func test_all_panels_cached_false_before_download() -> void:
	var lib := _lib()
	var panels := {}
	for colourway in ContainersLibrary.COLOURWAYS:
		for face in ContainersLibrary.FACES:
			var name := "%s_%s" % [colourway, face]
			panels[name] = {"url": name + ".webp", "sha256": "contlib_missing_" + name, "size": 1}
	lib.apply_manifest_text(_manifest(panels))
	assert_bool(lib.all_panels_cached()).is_false()


func test_get_cached_path_when_file_present() -> void:
	var lib := _lib()
	var sha := "contlib_cachetest_123"
	lib.apply_manifest_text(_manifest({"container_red_side": {"url": "c.webp", "sha256": sha, "size": 1}}))
	assert_str(lib.get_cached_path("container_red_side")).is_equal("")

	var path := "user://containers_cache/%s.webp" % sha
	DirAccess.make_dir_recursive_absolute("user://containers_cache")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()

	assert_str(lib.get_cached_path("container_red_side")).is_equal(path)
	DirAccess.remove_absolute(path)  # cleanup


func test_bundled_manifest_covers_all_faces() -> void:
	# The committed assets/containers_manifest.json must list every face the renderer draws.
	var lib := _lib()
	for colourway in ContainersLibrary.COLOURWAYS:
		for face in ContainersLibrary.FACES:
			assert_bool(lib.has_panel("%s_%s" % [colourway, face])).is_true()