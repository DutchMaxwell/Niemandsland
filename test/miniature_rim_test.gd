extends GdUnitTestSuite
## Exercise both real miniature material paths and quality changes after loading.

var _preset_before: int


func before_test() -> void:
	_preset_before = GraphicsSettings.current_preset


func after_test() -> void:
	GraphicsSettings.apply_preset(_preset_before)
	RenderingServer.emit_signal("frame_post_draw")
	RenderingServer.emit_signal("frame_post_draw")


func _miniature_material(ctex: bool) -> StandardMaterial3D:
	var root: Node3D = auto_free(Node3D.new())
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)
	var source := StandardMaterial3D.new()
	source.rim = 0.4
	source.rim_tint = 0.15
	source.albedo_color = Color(0.2, 0.3, 0.4)
	source.normal_enabled = true
	mesh.mesh.surface_set_material(0, source)
	var manager: OPRArmyManager = auto_free(OPRArmyManager.new())
	if ctex:
		mesh.set_surface_override_material(0, source.duplicate())
		manager._brighten_ctex_materials(root)
	else:
		manager._brighten_trellis_materials(root)
	assert_bool(source.rim_enabled).is_false()
	assert_object(mesh.material_overlay).is_null()
	return mesh.get_active_material(0) as StandardMaterial3D


func test_both_material_paths_gain_a_subtle_rim_and_restore_low() -> void:
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.MEDIUM)
	for ctex in [false, true]:
		var mat := _miniature_material(ctex)
		for tier in [2, 3, 4, 1, 0, 2, 1]:
			GraphicsSettings.apply_preset(tier)
			assert_bool(mat.rim_enabled).is_equal(tier >= 2)
			assert_float(mat.rim).is_equal_approx(0.12 if tier >= 2 else 0.4, 0.0001)
			assert_float(mat.rim_tint).is_equal_approx(0.65 if tier >= 2 else 0.15, 0.0001)
			assert_bool(mat.normal_enabled).is_true()
			assert_float(mat.roughness).is_equal_approx(0.7, 0.0001)
			assert_str(mat.albedo_color.to_html()).is_equal(Color(0.2, 0.3, 0.4).to_html())


func test_materials_loaded_on_low_update_without_respawning() -> void:
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.LOW)
	var mat := _miniature_material(true)
	assert_bool(mat.rim_enabled).is_false()
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.HIGH)
	assert_bool(mat.rim_enabled).is_true()


func test_repeated_preparation_preserves_original_rim() -> void:
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.HIGH)
	var root: Node3D = auto_free(Node3D.new())
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	root.add_child(mesh)
	var mat := StandardMaterial3D.new()
	mat.rim_enabled = true
	mat.rim = 0.3
	mat.rim_tint = 0.2
	mesh.set_surface_override_material(0, mat)
	var manager: OPRArmyManager = auto_free(OPRArmyManager.new())
	manager._brighten_ctex_materials(root)
	manager._brighten_ctex_materials(root)
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.LOW)
	assert_bool(mat.rim_enabled).is_true()
	assert_float(mat.rim).is_equal_approx(0.3, 0.0001)
	assert_float(mat.rim_tint).is_equal_approx(0.2, 0.0001)


func test_quality_tracking_does_not_keep_unloaded_materials_alive() -> void:
	var mat := StandardMaterial3D.new()
	var ref: WeakRef = weakref(mat)
	GraphicsSettings.register_miniature_material(mat)
	mat = null
	assert_object(ref.get_ref()).is_null()
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.MEDIUM)
