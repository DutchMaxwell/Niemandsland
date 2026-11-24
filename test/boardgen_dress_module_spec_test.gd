extends GdUnitTestSuite
## DressModuleSpec: every bundled manifest module parses without errors, a broken entry collects its
## errors, the kit builds each spec once, and a module without a `shadow` key still resolves the
## shrink that BoardgenDressMesh used before.

const MANIFEST := "res://assets/ruintown_dress.json"


func _meta() -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	return data if typeof(data) == TYPE_DICTIONARY else {}


func _vec(a: Array) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2]))


func _kit() -> BoardgenDressKit:
	var town_kit := BoardgenKit.new("ruintown")
	add_child(town_kit)
	auto_free(town_kit)
	return BoardgenDressKit.new(town_kit, true)


## A valid manifest entry with `overrides` laid over it.
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


func test_every_bundled_module_parses_without_errors() -> void:
	var meta := _meta()
	for name: String in meta["modules"]:
		var entry: Dictionary = meta["modules"][name]
		var spec := DressModuleSpec.from_manifest(name, entry, meta["materials"])
		(
			assert_bool(spec.errors.is_empty())
			. override_failure_message("%s: %s" % [name, spec.errors])
			. is_true()
		)
		assert_str(spec.name).is_equal(name)
		assert_str(spec.family).is_equal(entry["family"])
		assert_str(spec.role).is_equal(entry["role"])
		assert_int(spec.tags.size()).is_equal(entry["tags"].size())
		assert_int(spec.materials.size()).is_equal(entry["materials"].size())
		assert_float(spec.len_in).is_equal(entry["len_in"])
		assert_float(spec.height_in).is_equal(entry["height_in"])
		assert_float(spec.mount_in).is_equal(entry["mount_in"])
		assert_float(spec.proud_flat).is_equal(entry["proud_in"]["flat"])
		assert_float(spec.proud_low).is_equal(entry["proud_in"]["low"])
		assert_float(spec.proud_high).is_equal(entry["proud_in"]["high"])
		assert_bool(spec.stub).is_equal(entry["stub"])
		assert_str(spec.variant).is_equal(str(entry.get("variant", "")))
		assert_vector(spec.aabb_lo).is_equal(_vec(entry["aabb_in"][0]))
		assert_vector(spec.aabb_hi).is_equal(_vec(entry["aabb_in"][1]))
		assert_array(spec.aabb_lo_in).is_equal(entry["aabb_in"][0])
		assert_array(spec.aabb_hi_in).is_equal(entry["aabb_in"][1])
		assert_int(spec.shadow_hulls.size()).is_equal(entry["shadow"].size())
		for i in entry["shadow"].size():
			assert_vector(spec.shadow_hulls[i][0]).is_equal(_vec(entry["shadow"][i][0]))
			assert_vector(spec.shadow_hulls[i][1]).is_equal(_vec(entry["shadow"][i][1]))


func test_the_kit_builds_each_spec_once_and_hands_out_the_same_object() -> void:
	var dress := _kit()
	var meta := _meta()
	for name: String in meta["modules"]:
		var spec := dress.spec(name)
		assert_object(spec).override_failure_message(name).is_not_null()
		assert_object(dress.spec(name)).is_same(spec)
		assert_bool(spec.errors.is_empty()).is_true()
	assert_object(dress.spec("dr_nope")).is_null()


func test_a_broken_entry_lists_its_errors_instead_of_pushing_them() -> void:
	var entry := _entry(
		{
			"aabb_in": [[2.0, 0.0, 0.0], [1.0, 1.0, 1.0]],
			"materials": ["ct_nope"],
			"variant": "nope",
		}
	)
	entry.erase("family")
	entry.erase("role")
	var spec := DressModuleSpec.from_manifest("broken", entry, _meta()["materials"])
	for expected in [
		"missing family",
		"missing role",
		"aabb_in lo above hi",
		"unknown material ct_nope",
		"unknown surface variant nope",
	]:
		(
			assert_bool(spec.errors.has(expected))
			. override_failure_message("%s lacks '%s'" % [spec.errors, expected])
			. is_true()
		)
	# a wrong type is reported, not silently coerced
	var bad := {"family": 3, "role": "r", "tags": "x", "materials": [], "len_in": "2"}
	var other := DressModuleSpec.from_manifest("bad", bad, {})
	for expected in [
		"family is not String",
		"tags is not Array",
		"len_in is not float",
		"missing stub",
		"missing aabb_in",
		"no materials",
	]:
		(
			assert_bool(other.errors.has(expected))
			. override_failure_message("%s lacks '%s'" % [other.errors, expected])
			. is_true()
		)


func test_shadow_hulls_of_a_module_without_the_key_equal_todays_shrink() -> void:
	var plain := DressModuleSpec.from_manifest(
		"plain", _entry({"aabb_in": [[0.0, 0.0, 0.0], [1.0, 2.0, 3.0]]}), _meta()["materials"]
	)
	assert_bool(plain.errors.is_empty()).is_true()
	assert_int(plain.shadow_hulls.size()).is_equal(1)
	assert_vector(plain.shadow_hulls[0][0]).is_equal(Vector3(0.05, 0.05, 0.05))
	assert_vector(plain.shadow_hulls[0][1]).is_equal(Vector3(0.95, 1.95, 2.95))
	# a flat piece keeps its thickness on the flat axis
	var flat := DressModuleSpec.from_manifest(
		"flat", _entry({"aabb_in": [[0.0, 0.0, 0.0], [1.0, 1.0, 0.04]]}), _meta()["materials"]
	)
	assert_vector(flat.shadow_hulls[0][0]).is_equal(Vector3(0.05, 0.05, 0.0))
	assert_vector(flat.shadow_hulls[0][1]).is_equal(Vector3(0.95, 0.95, 0.04))
	# a stated list is kept as it stands
	var stated := DressModuleSpec.from_manifest(
		"stated", _entry({"shadow": [[[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]]]}), _meta()["materials"]
	)
	assert_int(stated.shadow_hulls.size()).is_equal(1)
	assert_vector(stated.shadow_hulls[0][1]).is_equal(Vector3.ONE)
