extends GdUnitTestSuite
## Tests BiomeLibrary manifest parsing + cache resolution (no network involved).


func _lib() -> BiomeLibrary:
	var l := BiomeLibrary.new()
	add_child(l)
	return auto_free(l)


func test_manifest_parse_and_has_biome() -> void:
	var lib := _lib()
	lib.apply_manifest_text(JSON.stringify({
		"version": 1,
		"base_url": "https://cdn/",
		"biomes": {"frozen_tundra": {"url": "t.webp", "sha256": "abc", "size": 10}},
	}))
	assert_bool(lib.has_biome("frozen_tundra")).is_true()
	assert_bool(lib.has_biome("nope")).is_false()


func test_unknown_biome_returns_empty_cached_path() -> void:
	var lib := _lib()
	assert_str(lib.get_cached_path("unknown")).is_equal("")


func test_get_cached_path_when_file_present() -> void:
	var lib := _lib()
	var sha := "biomelib_cachetest_123"
	lib.apply_manifest_text(JSON.stringify({
		"version": 1,
		"base_url": "",
		"biomes": {"frozen_tundra": {"url": "x.webp", "sha256": sha, "size": 1}},
	}))
	# Not downloaded yet → empty.
	assert_str(lib.get_cached_path("frozen_tundra")).is_equal("")

	# Simulate a cached download.
	var path := "user://biome_cache/%s.webp" % sha
	DirAccess.make_dir_recursive_absolute("user://biome_cache")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()

	assert_str(lib.get_cached_path("frozen_tundra")).is_equal(path)
	DirAccess.remove_absolute(path)  # cleanup
