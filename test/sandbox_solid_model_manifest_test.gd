extends GdUnitTestSuite
## The picked shelf solids name their uploaded detailed models (maintainer upload word 05.10.), and the bundled hazards
## manifest carries each one with its sha256 and size, so the game downloads, checks and shows it; until then, or if
## anything fails, the bundled look stays (test/sandbox_solid_model_test.gd).

const PICKS := ["longhouse_6x3", "outcrop_6x3"]
const TEST_SHA := "0000fantasytable0test0model0ok"   # test-only cache name, never a real manifest sha


func after_test() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(HazardsLibrary.CACHE_DIR.path_join(TEST_SHA + ".glb")))


func test_the_picked_solids_name_an_uploaded_model() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(HazardsLibrary.BUNDLED_MANIFEST_PATH))
	var models: Dictionary = manifest.get("models", {})
	for id: String in PICKS:
		var model: String = ObjectManager.SANDBOX_SOLIDS[id].get("model", "")
		assert_str(model).override_failure_message("%s names no model" % id).is_not_empty()
		var entry: Dictionary = models.get(model, {})
		var sha: String = entry.get("sha256", "")
		assert_int(sha.length()).override_failure_message("%s: no sha256" % model).is_equal(64)
		assert_int(int(entry.get("size", 0))).is_greater(0)
		assert_str(str(entry.get("url", ""))).ends_with("?v=" + sha.left(8))


func test_a_cached_model_replaces_the_bundled_look() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	var lib := om.solid_models_library()
	lib.apply_manifest_text(JSON.stringify({"models": {"test_solid": {"url": "test.glb", "sha256": TEST_SHA}}}))
	var src := MeshInstance3D.new()
	src.mesh = BoxMesh.new()
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(src, state)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(HazardsLibrary.CACHE_DIR))
	assert_int(doc.write_to_filesystem(state, HazardsLibrary.CACHE_DIR.path_join(TEST_SHA + ".glb"))).is_equal(OK)
	src.free()
	var solid: SandboxSolidProp = om.spawn_sandbox_terrain("blocker_6x3", ObjectManager.SandboxPropKind.BLOCKER,
		Vector3.ZERO, false, 7401)
	var look := solid.get_children().filter(func(c: Node) -> bool: return c is MeshInstance3D)
	var before := solid.get_child_count()
	await om.apply_solid_model(solid, "test_solid")
	# A one-mesh GLB comes back with the mesh itself as the scene root, so count children instead of filtering types.
	assert_int(solid.get_child_count()).is_equal(before + 1)
	assert_bool(look.any(func(m: Node) -> bool: return m.visible)).is_false()
