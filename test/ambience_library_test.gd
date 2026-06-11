extends GdUnitTestSuite
## Tests AmbienceLibrary manifest parsing + cache resolution (no network involved).
## Mirrors hazards_library_test.gd; see docs/ASSET_DELIVERY.md.


func _lib() -> AmbienceLibrary:
	var lib := AmbienceLibrary.new()
	add_child(lib)
	return auto_free(lib)


func _manifest(sounds: Dictionary) -> String:
	return JSON.stringify({"version": 1, "base_url": "https://cdn/", "sounds": sounds})


func test_manifest_parse_and_has_sound() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_manifest({"rain_loop": {"url": "r.ogg", "sha256": "abc", "size": 10, "loop": true}}))
	assert_bool(lib.has_sound("rain_loop")).is_true()
	assert_bool(lib.has_sound("nope")).is_false()


func test_unknown_sound_returns_empty_cached_path() -> void:
	var lib := _lib()
	assert_str(lib.get_cached_path("unknown")).is_equal("")


func test_all_sounds_cached_false_before_download() -> void:
	var lib := _lib()
	var sounds := {}
	for sound in AmbienceLibrary.RUNTIME_SOUNDS:
		sounds[sound] = {"url": sound + ".ogg", "sha256": "amblib_missing_" + sound, "size": 1, "loop": false}
	lib.apply_manifest_text(_manifest(sounds))
	assert_bool(lib.all_sounds_cached()).is_false()


func test_get_cached_path_when_file_present() -> void:
	var lib := _lib()
	var sha := "amblib_cachetest_123"
	lib.apply_manifest_text(_manifest({"rain_loop": {"url": "r.ogg", "sha256": sha, "size": 1, "loop": true}}))
	assert_str(lib.get_cached_path("rain_loop")).is_equal("")

	var path := "user://ambience_cache/%s.ogg" % sha
	DirAccess.make_dir_recursive_absolute("user://ambience_cache")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()

	assert_str(lib.get_cached_path("rain_loop")).is_equal(path)
	DirAccess.remove_absolute(path)  # cleanup


func test_bundled_manifest_covers_all_runtime_sounds() -> void:
	# The committed assets/ambience_manifest.json must list every sound the
	# soundscape plays, and the loop flags must match the player expectations.
	var lib := _lib()
	for sound in AmbienceLibrary.RUNTIME_SOUNDS:
		assert_bool(lib.has_sound(sound)).is_true()
	assert_bool(lib._sounds["rain_loop"]["loop"]).is_true()
	assert_bool(lib._sounds["fire_crackle"]["loop"]).is_true()
	assert_bool(lib._sounds["thunder_a"]["loop"]).is_false()