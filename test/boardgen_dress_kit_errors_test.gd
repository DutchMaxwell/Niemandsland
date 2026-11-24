extends GdUnitTestSuite
## BoardgenDressKit's report: a module with errors is named by module with each error, a manifest
## that cannot be read names its file and leaves no specs, and the bundled manifest reports nothing.

const DIR := "user://boardgen_dress_kit_errors_test"
const MATERIALS := {"ct_matte": {}}


## The broken manifest written to user:// and handed to the kit.
func _write(file: String, body: String) -> String:
	DirAccess.make_dir_recursive_absolute(DIR)
	var path := "%s/%s.json" % [DIR, file]
	var handle := FileAccess.open(path, FileAccess.WRITE)
	handle.store_string(body)
	handle.close()
	return path


func _manifest(modules: Dictionary) -> String:
	return JSON.stringify({"materials": MATERIALS, "modules": modules})


func _kit(path: String) -> BoardgenDressKit:
	var town_kit := BoardgenKit.new("ruintown")
	add_child(town_kit)
	auto_free(town_kit)
	return BoardgenDressKit.new(town_kit, true, path)


## A valid module entry with `overrides` laid over it.
func _entry(overrides := {}) -> Dictionary:
	var base := {
		"family": "litter",
		"role": "litter",
		"tags": [],
		"materials": ["ct_matte"],
		"aabb_in": [[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]],
		"len_in": 1.0,
		"height_in": 1.0,
		"mount_in": 0.0,
		"proud_in": {"flat": 0.0, "low": 0.0, "high": 0.0},
		"openings": [],
		"stub": false,
	}
	base.merge(overrides, true)
	return base


func _has(kit: BoardgenDressKit, expected: String) -> bool:
	for line in kit.errors():
		if line.contains(expected):
			return true
	return false


func _assert_has(kit: BoardgenDressKit, expected: String) -> void:
	(
		assert_bool(_has(kit, expected))
		. override_failure_message("%s lacks '%s'" % [kit.errors(), expected])
		. is_true()
	)


func test_the_bundled_manifest_reports_no_errors() -> void:
	var kit := _kit(BoardgenDressKit.MANIFEST_PATH)
	assert_array(kit.errors()).is_empty()
	assert_bool(kit.spec_count() > 0).is_true()


func test_a_module_with_a_missing_key_names_the_module_and_the_error() -> void:
	var entry := _entry()
	entry.erase("family")
	var kit := _kit(_write("missing_key", _manifest({"dr_bad": entry})))
	_assert_has(kit, "module dr_bad: missing family")
	assert_int(kit.spec_count()).is_equal(1)  # the spec exists, broken as it is


func test_a_module_with_a_wrong_typed_value_and_a_non_object_entry_are_reported() -> void:
	var path := _write("wrong_type", _manifest({"dr_bad": _entry({"len_in": "2"}), "dr_odd": 5}))
	var kit := _kit(path)
	_assert_has(kit, "module dr_bad: len_in is not float")
	_assert_has(kit, "module dr_odd: not an object")
	assert_int(kit.spec_count()).is_equal(1)


func test_an_unknown_material_names_the_module_and_the_material() -> void:
	var modules := {"dr_bad": _entry({"materials": ["ct_nope"]})}
	var kit := _kit(_write("unknown_material", _manifest(modules)))
	_assert_has(kit, "module dr_bad: unknown material ct_nope")


func test_a_manifest_without_a_modules_block_names_the_file_and_leaves_no_specs() -> void:
	var path := _write("no_modules", JSON.stringify({"materials": MATERIALS}))
	var kit := _kit(path)
	_assert_has(kit, path)
	_assert_has(kit, "no modules block")
	assert_int(kit.spec_count()).is_equal(0)
	assert_object(kit.spec("dr_house_tb_plain_a")).is_null()


func test_an_unparsable_manifest_names_the_file_and_leaves_no_specs() -> void:
	var path := _write("unparsable", "{not json")
	var kit := _kit(path)
	_assert_has(kit, path)
	_assert_has(kit, "cannot be parsed")
	assert_int(kit.spec_count()).is_equal(0)
	assert_dict(kit.module("dr_house_tb_plain_a")).is_empty()
