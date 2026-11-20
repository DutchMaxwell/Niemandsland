extends GdUnitTestSuite
## BoardgenKit (AAA step 13): manifest, cache lookup and the GLB parse through a fixture module written at run time. No network.

const DIR := "user://boardgen_kit_test"


func _kit() -> BoardgenKit:
	var kit := BoardgenKit.new()
	add_child(kit)
	return auto_free(kit)


## A one-surface GLB (a unit-ish sphere, so the LOD pass has triangles to drop) written to DIR/<name>.glb.
func _fixture(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var holder := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radial_segments = 32
	sphere.rings = 16
	holder.mesh = sphere
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	doc.append_from_scene(holder, state)
	doc.write_to_filesystem(state, "%s/%s.glb" % [DIR, name])
	holder.free()


func test_manifest_parse_and_unknown_module() -> void:
	var kit := _kit()
	kit.apply_manifest_text(JSON.stringify({"base_url": "https://cdn/", "models": {"rail_span": {"url": "r.glb", "sha256": "kit_missing_sha", "size": 1}}}))
	assert_bool(kit.has_module("rail_span")).is_true()
	assert_bool(kit.has_module("nope")).is_false()
	assert_str(kit.cached_path("rail_span")).is_equal("")   # in the manifest, not downloaded
	assert_bool(kit.all_cached(["rail_span"])).is_false()


func test_missing_module_returns_the_callers_fallback() -> void:
	var fallback := BoxMesh.new()
	assert_object(_kit().mesh_or("rail_span", fallback)).is_same(fallback)


func test_local_module_parses_onto_the_shared_material_with_lods() -> void:
	_fixture("fixture_sphere")
	var kit := _kit()
	kit.local_dir = DIR
	assert_bool(kit.all_cached(["fixture_sphere"])).is_true()
	var mesh := kit.mesh_or("fixture_sphere") as ArrayMesh
	assert_object(mesh).is_not_null()
	assert_object(mesh.surface_get_material(0)).is_same(BoardgenKit.material())
	assert_object(kit.mesh_or("fixture_sphere")).is_same(mesh)   # parsed once, then shared
	assert_int(BoardgenKit.with_lods(mesh).get_surface_lod_count(0)).is_greater(0)


func test_bundled_manifest_parses() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(BoardgenKit.BUNDLED_MANIFEST_PATH))
	assert_bool(typeof(data) == TYPE_DICTIONARY and data.has("models")).is_true()
