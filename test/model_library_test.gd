extends GdUnitTestSuite
## Tests ModelLibrary manifest parsing + cache resolution (no network involved).


func _lib() -> ModelLibrary:
	var l := ModelLibrary.new()
	add_child(l)
	return auto_free(l)


func test_make_key_is_case_insensitive() -> void:
	assert_str(ModelLibrary.make_key("Alien_Hives", " Hive Lord ")).is_equal("alien_hives/hive lord")


func test_manifest_parse_and_has_model() -> void:
	var lib := _lib()
	lib.apply_manifest_text(JSON.stringify({
		"version": 1,
		"base_url": "https://cdn/",
		"models": {"alien_hives/hive lord": {"url": "h.glb", "sha256": "abc", "size": 10}},
	}))
	assert_bool(lib.has_model("alien_hives", "Hive Lord")).is_true()
	assert_bool(lib.has_model("alien_hives", "Nope")).is_false()


func test_no_entry_returns_empty_cached_path() -> void:
	var lib := _lib()
	assert_str(lib.get_cached_path("unknown", "unit")).is_equal("")


func test_get_cached_path_when_file_present() -> void:
	var lib := _lib()
	var sha := "modellib_cachetest_123"
	lib.apply_manifest_text(JSON.stringify({
		"version": 1,
		"base_url": "",
		"models": {"f/u": {"url": "x.glb", "sha256": sha, "size": 1}},
	}))
	# Not downloaded yet → empty.
	assert_str(lib.get_cached_path("f", "u")).is_equal("")

	# Simulate a cached download.
	var path := "user://model_cache/%s.glb" % sha
	DirAccess.make_dir_recursive_absolute("user://model_cache")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()

	assert_str(lib.get_cached_path("f", "u")).is_equal(path)
	DirAccess.remove_absolute(path)  # cleanup
