extends GdUnitTestSuite
## CtexLoader: the .ctex version guard + material-build error paths. The actual .ctex decode
## (ResourceLoader.load on a user:// path → CompressedTexture2D, BC7, mipmaps) is verified manually
## against a real baked asset — see HANDOFF_modelforge_texture_pipeline.md — since a .ctex fixture
## isn't checked into the repo.

const Ctex := preload("res://scripts/ctex_loader.gd")


func _engine_mm() -> String:
	var v: Dictionary = Engine.get_version_info()
	return "%d.%d" % [int(v["major"]), int(v["minor"])]


# ===== version guard =====

func test_compatible_on_matching_engine() -> void:
	# The running engine's own major.minor must be accepted, incl. a patch-qualified manifest value.
	assert_bool(Ctex.ctex_compatible(_engine_mm())).is_true()
	assert_bool(Ctex.ctex_compatible(_engine_mm() + ".2")).is_true()


func test_incompatible_on_mismatch_or_empty() -> void:
	assert_bool(Ctex.ctex_compatible("0.0")).is_false()   # clearly different major.minor
	assert_bool(Ctex.ctex_compatible("")).is_false()      # no version -> fall back to raw GLB


# ===== load_ctex error paths =====

func test_load_ctex_missing_is_null() -> void:
	assert_object(Ctex.load_ctex("")).is_null()
	assert_object(Ctex.load_ctex("user://does_not_exist_%d.ctex" % 123456)).is_null()


# ===== build_material with absent textures =====

func test_build_material_empty_is_bare() -> void:
	var mat := Ctex.build_material("", "", "")
	assert_object(mat).is_not_null()
	assert_object(mat.albedo_texture).is_null()
	assert_bool(mat.normal_enabled).is_false()
	assert_bool(mat.ao_enabled).is_false()


func test_build_material_missing_paths_skip_textures() -> void:
	var mat := Ctex.build_material("user://nope_a.ctex", "user://nope_n.ctex", "user://nope_o.ctex")
	assert_object(mat.albedo_texture).is_null()
	assert_object(mat.normal_texture).is_null()
	assert_object(mat.roughness_texture).is_null()


# ===== load_ctex shares one texture per file (CACHE_MODE_REUSE) =====

## A real .ctex from this project's own import cache (every imported PNG/SVG has one), copied to a
## content-addressed-style user:// path like the ctex downloader's cache_path(sha).
func _real_ctex_copy(dest: String) -> String:
	for f in DirAccess.get_files_at("res://.godot/imported"):
		if str(f).ends_with(".ctex"):
			var bytes := FileAccess.get_file_as_bytes("res://.godot/imported/" + str(f))
			var out := FileAccess.open(dest, FileAccess.WRITE)
			if out == null or bytes.is_empty():
				return ""
			out.store_buffer(bytes)
			out.close()
			return dest
	return ""


## Ratmen weight follow-up (PLAN 22.09. 23:40): every model instance loaded its own copy of each
## .ctex (CACHE_MODE_IGNORE), so a 20-model unit uploaded the same BC7 texture 20 times. The ctex
## cache paths are content-addressed (sha256 file names), so a same-path reload can never be stale:
## the same file must come back as the SAME texture.
func test_the_same_ctex_file_loads_as_one_shared_texture() -> void:
	var path := _real_ctex_copy("user://ctex_reuse_probe_%d.ctex" % Time.get_ticks_usec())
	assert_str(path).override_failure_message("fixture: no imported .ctex found under res://.godot/imported").is_not_empty()
	var first := Ctex.load_ctex(path)
	var second := Ctex.load_ctex(path)
	assert_object(first).is_not_null()
	assert_bool(first == second) \
		.override_failure_message("two models loading the same .ctex got two textures (one GPU upload each)") \
		.is_true()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
