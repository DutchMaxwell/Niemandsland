extends GdUnitTestSuite

## CoreAssets stages the files the Rust core opens with std::fs (rules, spells, row
## vocab, shipped brain) out of the PCK into a real directory. An export that skips
## this hands the core an empty rules map without any error — so the copy must be
## complete and idempotent.

const DIR := "user://nml_core_test_stage/"


func before_test() -> void:
	_wipe()


func after_test() -> void:
	_wipe()


func _wipe() -> void:
	if not DirAccess.dir_exists_absolute(DIR):
		return
	for rel in CoreAssets.FILES:
		DirAccess.remove_absolute(DIR + rel)
	for sub in ["assets/solo/brains", "assets/solo", "assets", "data"]:
		DirAccess.remove_absolute(DIR + sub)
	DirAccess.remove_absolute(DIR)


func test_every_source_file_is_in_the_build() -> void:
	for rel in CoreAssets.FILES:
		assert_bool(FileAccess.file_exists("res://" + rel)).override_failure_message("missing source " + rel).is_true()


func test_stage_copies_every_file_byte_for_byte_and_is_idempotent() -> void:
	for rel in CoreAssets.FILES:
		assert_bool(FileAccess.file_exists(DIR + rel)).override_failure_message("RED: stale " + rel).is_false()
	assert_int(CoreAssets.stage(DIR)).is_equal(CoreAssets.FILES.size())
	for rel in CoreAssets.FILES:
		var src := FileAccess.get_file_as_bytes("res://" + rel)
		var dst := FileAccess.get_file_as_bytes(DIR + rel)
		assert_int(dst.size()).override_failure_message("size differs for " + rel).is_equal(src.size())
		assert_bool(dst == src).override_failure_message("bytes differ for " + rel).is_true()
	assert_int(CoreAssets.stage(DIR)).is_equal(0)


func test_stage_dir_is_versioned_and_root_is_a_directory() -> void:
	var ver := str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
	assert_str(CoreAssets.stage_dir()).is_equal("user://nml_core/%s/" % ver)
	var root := CoreAssets.root()
	assert_bool(DirAccess.dir_exists_absolute(root)).override_failure_message("root not a directory: " + root).is_true()
	assert_bool(FileAccess.file_exists(root.path_join("assets/solo/rules_mechanics_gf.json"))).is_true()
