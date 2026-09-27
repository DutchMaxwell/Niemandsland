extends GdUnitTestSuite
## The main menu's terrain parses its tree GLBs on the worker pool (TerrainOverlay.defer_tree_model_parse ->
## TreesLibrary.prepare_models): the layout call returns without them, the billboards stand in, and the
## overlay upgrades to the GLB trees once they are ready. Inline, the three GLBs held the main thread for
## 1.78-1.92 s on every warm menu start (measured). The game table keeps the inline parse.
## Fixtures are generated here (a textured box GLB, flat WebP panels, unique hashes in the real cache dir),
## so no network and no downloaded asset is needed.

const OverlayScript := preload("res://scripts/terrain_overlay.gd")
const FIXTURE_MESH := "FixtureTreeTrunk"

var _files: Array[String] = []
var _model_paths: Array[String] = []


func after_test() -> void:
	for path in _model_paths:
		TreesLibrary._model_scene_cache.erase(path)
	for path in _files:
		DirAccess.remove_absolute(path)
	_files.clear()
	_model_paths.clear()


## A deferred overlay with a warm fixture theme: every panel and model cached on disk, nothing parsed.
func _overlay(defer: bool) -> Node3D:
	var overlay: Node3D = auto_free(OverlayScript.new())
	overlay.defer_tree_model_parse = defer
	add_child(overlay)
	var tag := "treeprep_%d_%d" % [Time.get_ticks_usec(), randi()]
	DirAccess.make_dir_recursive_absolute(TreesLibrary.CACHE_DIR)
	var panels := {}
	for panel in TreesLibrary.RUNTIME_PANELS:
		var sha := "%s_%s" % [tag, panel]
		var image := Image.create(16, 32, false, Image.FORMAT_RGBA8)
		image.fill(Color(0.3, 0.5, 0.2))
		var path := "%s/%s.webp" % [TreesLibrary.CACHE_DIR, sha]
		image.save_webp(path)
		_files.append(path)
		panels[panel] = {"url": panel + ".webp", "sha256": sha, "size": 1}
	var glb := _fixture_glb()
	var models := {}
	for variant in TreesLibrary.TREE_VARIANTS:
		var sha := "%s_%s_glb" % [tag, variant]
		var path := "%s/%s.glb" % [TreesLibrary.CACHE_DIR, sha]
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_buffer(glb)
		file.close()
		_files.append(path)
		_model_paths.append(path)
		models[variant] = {"url": variant + ".glb", "sha256": sha, "size": glb.size()}
	overlay._trees_library.apply_manifest_text(JSON.stringify(
		{"version": 1, "base_url": "https://cdn/", "panels": panels, "models": models}))
	return overlay


## A 0.4 x 1.0 x 0.4 box with an embedded 8x8 PNG albedo, metallic 1 (the material fix must set 0).
func _fixture_glb() -> PackedByteArray:
	var root := Node3D.new()
	var trunk := MeshInstance3D.new()
	trunk.name = FIXTURE_MESH
	var box := BoxMesh.new()
	box.size = Vector3(0.4, 1.0, 0.4)
	var material := StandardMaterial3D.new()
	material.metallic = 1.0
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.25, 0.45, 0.2))
	material.albedo_texture = ImageTexture.create_from_image(image)
	box.material = material
	trunk.mesh = box
	root.add_child(trunk)
	trunk.owner = root
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	doc.append_from_scene(root, state)
	var bytes := doc.generate_buffer(state)
	root.free()
	return bytes


func _layout() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 220922
	return TerrainPrefabs.decoration_for("wald_9x9", Vector2i(6, 9), rng)


func _fixture_trees(overlay: Node3D) -> Array[Node]:
	return overlay.find_children(FIXTURE_MESH, "MeshInstance3D", true, false)


func _billboards(overlay: Node3D) -> int:
	var count := 0
	for mesh: MeshInstance3D in overlay.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh is QuadMesh:
			count += 1
	return count


func test_deferred_layout_returns_before_the_parse_and_upgrades_after_it() -> void:
	var overlay := _overlay(true)
	var library: TreesLibrary = overlay._trees_library
	overlay.update_placed_objects(_layout(), Vector2(4, 4), 0)
	var objects: int = overlay._object_instances.size()
	assert_int(objects).is_greater(0)
	for path in _model_paths:
		assert_bool(TreesLibrary._model_scene_cache.has(path)).override_failure_message(
			"the layout call parsed %s on the main thread" % path).is_false()
	assert_int(_fixture_trees(overlay).size()).is_equal(0)
	assert_int(_billboards(overlay)).override_failure_message("no billboard stands in").is_greater(0)
	assert_bool(overlay._tree_models_ready()).is_false()

	assert_bool(await library.prepare_models("")).is_true()
	for path in _model_paths:
		assert_object(TreesLibrary._model_scene_cache.get(path)).is_not_null()
	var trees: Array[Node] = []
	for i in 120:
		trees = _fixture_trees(overlay)
		if not trees.is_empty():
			break
		await await_idle_frame()
	assert_int(trees.size()).override_failure_message("the overlay never showed the GLB trees").is_greater(0)
	if trees.is_empty():
		return
	# Upgraded in place: the same objects, not a second set on top (no rebuild nested in the layout call).
	assert_int(overlay._object_instances.size()).is_equal(objects)
	assert_bool(overlay._tree_models_ready()).is_true()
	assert_bool(TreesLibrary._model_jobs.is_empty()).is_true()
	# The worker's material fix, from CPU copies: non-metallic, mipmapped albedo.
	var material := (trees[0] as MeshInstance3D).mesh.surface_get_material(0) as StandardMaterial3D
	assert_float(material.metallic).is_equal(0.0)
	assert_bool(material.albedo_texture.get_image().has_mipmaps()).is_true()


func test_game_table_keeps_the_inline_parse() -> void:
	var overlay := _overlay(false)
	overlay.update_placed_objects(_layout(), Vector2(4, 4), 0)
	for path in _model_paths:
		assert_bool(TreesLibrary._model_scene_cache.has(path)).is_true()
	assert_int(_fixture_trees(overlay).size()).is_greater(0)
