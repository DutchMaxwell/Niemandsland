extends GdUnitTestSuite
## Tests TreesLibrary manifest parsing + cache resolution (no network involved).
## Mirrors ruins_library_test.gd; see docs/ASSET_DELIVERY.md.


func _lib() -> TreesLibrary:
	var lib := TreesLibrary.new()
	add_child(lib)
	return auto_free(lib)


func _manifest(panels: Dictionary) -> String:
	return JSON.stringify({"version": 1, "base_url": "https://cdn/", "panels": panels})


func test_manifest_parse_and_has_panel() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_manifest({"tree_a": {"url": "t.webp", "sha256": "abc", "size": 10}}))
	assert_bool(lib.has_panel("tree_a")).is_true()
	assert_bool(lib.has_panel("nope")).is_false()


func test_unknown_panel_returns_empty_cached_path() -> void:
	var lib := _lib()
	assert_str(lib.get_cached_path("unknown")).is_equal("")


func test_all_panels_cached_false_before_download() -> void:
	var lib := _lib()
	var panels := {}
	for panel in TreesLibrary.RUNTIME_PANELS:
		panels[panel] = {"url": panel + ".webp", "sha256": "treeslib_missing_" + panel, "size": 1}
	lib.apply_manifest_text(_manifest(panels))
	assert_bool(lib.all_panels_cached()).is_false()


func test_get_cached_path_when_file_present() -> void:
	var lib := _lib()
	var sha := "treeslib_cachetest_123"
	lib.apply_manifest_text(_manifest({"tree_a": {"url": "t.webp", "sha256": sha, "size": 1}}))
	# Not downloaded yet → empty.
	assert_str(lib.get_cached_path("tree_a")).is_equal("")

	# Simulate a cached download.
	var path := "user://trees_cache/%s.webp" % sha
	DirAccess.make_dir_recursive_absolute("user://trees_cache")
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("x")
	f.close()

	assert_str(lib.get_cached_path("tree_a")).is_equal(path)
	DirAccess.remove_absolute(path)  # cleanup


func test_get_texture_uncached_panel_is_null() -> void:
	var lib := _lib()
	lib.apply_manifest_text(_manifest({"tree_a": {"url": "t.webp", "sha256": "treeslib_nofile", "size": 1}}))
	assert_object(lib.get_texture("tree_a")).is_null()
	assert_object(lib.get_texture("unknown")).is_null()


func test_bundled_manifest_covers_all_runtime_panels() -> void:
	# The committed assets/trees_manifest.json must list every panel the renderer draws.
	var lib := _lib()
	for panel in TreesLibrary.RUNTIME_PANELS:
		assert_bool(lib.has_panel(panel)).is_true()


func _mesh_with_material(material: StandardMaterial3D) -> MeshInstance3D:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.3, 0.5, 0.2))
	material.albedo_texture = ImageTexture.create_from_image(image)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, BoxMesh.new().get_mesh_arrays())
	mesh.surface_set_material(0, material)
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	return auto_free(instance)


func test_deciduous_grading_preserves_mesh_and_source_material() -> void:
	var source := StandardMaterial3D.new()
	source.roughness = 0.4
	var instance := _mesh_with_material(source)
	var original_mesh := instance.mesh
	var bounds := original_mesh.get_aabb()
	TreesLibrary._fix_runtime_materials(instance, true)
	var graded := instance.mesh.surface_get_material(0) as ShaderMaterial
	assert_object(graded).is_not_null()
	assert_object(instance.mesh).is_same(original_mesh)
	assert_that(instance.mesh.get_aabb()).is_equal(bounds)
	assert_float(source.roughness).is_equal_approx(0.4, 0.001)
	var texture: Texture2D = graded.get_shader_parameter("albedo_tex")
	assert_bool(texture.get_image().has_mipmaps()).is_true()


func test_themed_and_richer_tree_materials_keep_the_standard_path() -> void:
	for feature in ["themed", "cutout", "normal", "emission", "vertex_color"]:
		var source := StandardMaterial3D.new()
		if feature == "cutout":
			source.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		source.normal_enabled = feature == "normal"
		source.emission_enabled = feature == "emission"
		source.vertex_color_use_as_albedo = feature == "vertex_color"
		var instance := _mesh_with_material(source)
		TreesLibrary._fix_runtime_materials(instance, feature != "themed")
		var result := instance.mesh.surface_get_material(0) as StandardMaterial3D
		assert_object(result).is_not_null()
		assert_int(result.transparency).is_equal(source.transparency)
		assert_bool(result.normal_enabled).is_equal(source.normal_enabled)
		assert_bool(result.emission_enabled).is_equal(source.emission_enabled)
		assert_bool(result.vertex_color_use_as_albedo).is_equal(source.vertex_color_use_as_albedo)


func test_ground_cover_is_cosmetic_and_skips_themed_or_grouped_forests() -> void:
	var overlay: Node3D = auto_free(load("res://scripts/terrain_overlay.gd").new())
	var root: Node3D = auto_free(Node3D.new())
	var tree := MeshInstance3D.new()
	tree.mesh = BoxMesh.new()
	root.add_child(tree)
	var original_mesh := tree.mesh
	overlay._add_tree_ground_cover(root) # grouped forest: no table extent
	assert_int(root.get_child_count()).is_equal(1)
	overlay._last_obj_table_size = Vector2(6, 4)
	overlay._prop_theme = "desert_"
	overlay._add_tree_ground_cover(root)
	assert_int(root.get_child_count()).is_equal(1)
	overlay._prop_theme = ""
	overlay._add_tree_ground_cover(root)
	assert_int(root.get_child_count()).is_equal(2)
	var patch := root.get_node("TreeGroundCover") as MeshInstance3D
	assert_object(patch).is_not_null()
	assert_int(patch.get_child_count()).is_equal(0) # no collision bodies
	assert_int(patch.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_object(tree.mesh).is_same(original_mesh)
	assert_vector(patch.material_override.get_shader_parameter("table_half_extent")) \
		.is_equal_approx(Vector2(0.9144, 0.6096), Vector2(0.0001, 0.0001))
