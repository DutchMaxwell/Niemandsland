extends GdUnitTestSuite

const Idle := preload("res://scripts/visual/bone_texture_payload.gd")

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
