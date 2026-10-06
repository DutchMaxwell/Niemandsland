extends GdUnitTestSuite

const Idle := preload("res://scripts/visual/bone_texture_idle.gd")

func _entry() -> Dictionary:
	return {"version": 1, "godot_version": "4.6", "frames": 216, "fps": 24.0,
		"bones": 57, "mesh": {"sha256": "a".repeat(64), "url": "mesh.res"},
		"poses": {"sha256": "b".repeat(64), "url": "poses.res"},
		"bounds": [-1.0, 0.0, -1.0, 2.0, 2.0, 2.0]}


func test_absent_or_invalid_payload_stays_static() -> void:
	assert_bool(Idle.valid_entry({})).is_false()
	var entry := _entry()
	assert_bool(Idle.valid_entry(entry)).is_true()
	entry.erase("poses")
	assert_bool(Idle.valid_entry(entry)).is_false()

	entry = _entry()
	entry.frames = 0
	assert_bool(Idle.valid_entry(entry)).is_false()
	entry = _entry()
	entry.version = 99
	assert_bool(Idle.valid_entry(entry)).is_false()
	entry = _entry()
	entry.fps = {"unexpected": true}
	assert_bool(Idle.valid_entry(entry)).is_false()
	entry = _entry()
	entry.materials = [{"surface": 0, "albedo": {"sha256": "missing"}}]
	assert_bool(Idle.valid_entry(entry)).is_false()


func test_json_manifest_round_trip_accepts_ctex_surface_indices() -> void:
	var entry := _entry()
	entry.materials = [{"surface": 0, "albedo": {"sha256": "c".repeat(64), "url": "texture.ctex"}}]
	var decoded: Dictionary = JSON.parse_string(JSON.stringify(entry))
	assert_bool(Idle.valid_entry(decoded)).is_true()


func test_manifest_requires_both_cached_blobs_and_preserves_legacy_entry() -> void:
	var lib: ModelLibrary = auto_free(ModelLibrary.new())
	lib._idle_assets = auto_free(AssetDownloadManager.new())
	lib._idle_assets.file_extension = "res"
	lib._idle_assets.cache_dir = "user://idle_test_%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(lib._idle_assets.cache_dir)
	var model := {"sha256": "original", "url": "static.glb", "idle": _entry()}
	lib.apply_manifest_text(JSON.stringify({"models": {"f/u": model, "f/old": {"sha256": "static"}}}))
	assert_bool(lib.get_idle_entry("f", "old").is_empty()).is_true()
	assert_bool(lib.idle_cached_paths("f", "u").is_empty()).is_true()
	var mesh_path := lib._idle_assets.cache_path(model.idle.mesh.sha256)
	var poses_path := lib._idle_assets.cache_path(model.idle.poses.sha256)
	FileAccess.open(mesh_path, FileAccess.WRITE).store_string("fixture")
	assert_bool(lib.idle_cached_paths("f", "u").is_empty()).is_true()
	FileAccess.open(poses_path, FileAccess.WRITE).store_string("fixture")
	assert_int(lib.idle_cached_paths("f", "u").size()).is_equal(3)
	assert_str(lib._entry("f", "u").sha256).is_equal("original")
	DirAccess.remove_absolute(mesh_path)
	DirAccess.remove_absolute(poses_path)
	DirAccess.remove_absolute(lib._idle_assets.cache_dir)


func test_settings_and_reduced_motion_gate_real_idle() -> void:
	for preset in [0, 1]:
		assert_bool(Idle.motion_allowed(preset, true, false)).is_false()
	for preset in [2, 3, 4]:
		assert_bool(Idle.motion_allowed(preset, true, false)).is_true()
		assert_bool(Idle.motion_allowed(preset, false, false)).is_false()
		assert_bool(Idle.motion_allowed(preset, true, true)).is_false()


func test_instances_have_reproducible_distinct_phases_without_gameplay_rng() -> void:
	var phases := {}
	seed(412)
	var expected := randi()
	seed(412)
	for i in 30:
		var identity := "warriors/%d" % i
		var phase := Idle.phase_for(identity)
		assert_float(phase).is_equal(Idle.phase_for(identity))
		assert_bool(phase >= 0.0 and phase < 1.0).is_true()
		phases[phase] = true
	assert_int(phases.size()).is_equal(30)
	assert_int(randi()).is_equal(expected)


func test_wrong_texture_dimensions_or_missing_joint_attributes_are_rejected() -> void:
	var array := ArrayMesh.new()
	var box := BoxMesh.new()
	array.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, box.get_mesh_arrays())
	var poses := ImageTexture.create_from_image(Image.create(171, 216, false, Image.FORMAT_RGBAF))
	assert_bool(Idle.valid_resources(array, poses, _entry())).is_false()
	assert_bool(Idle.valid_resources(null, poses, _entry())).is_false()


func test_graphics_preference_survives_save_load_and_same_preset_application() -> void:
	var previous := GraphicsSettings.idle_motion
	var preset := GraphicsSettings.current_preset
	GraphicsSettings.idle_motion = false
	GraphicsSettings.save_settings()
	GraphicsSettings.idle_motion = true
	GraphicsSettings.load_settings()
	assert_bool(GraphicsSettings.idle_motion).is_false()
	GraphicsSettings.apply_preset(preset)
	assert_bool(GraphicsSettings.idle_motion).is_false()
	GraphicsSettings.idle_motion = previous
	GraphicsSettings.save_settings()
