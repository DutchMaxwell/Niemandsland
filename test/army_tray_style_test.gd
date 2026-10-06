extends GdUnitTestSuite
var _old_preset: int

func before_test() -> void:
	_old_preset = GraphicsSettings.current_preset

func after_test() -> void:
	GraphicsSettings.current_preset = _old_preset
	GraphicsSettings.settings_applied.emit("restored")

func _tray(tier: int) -> Node3D:
	GraphicsSettings.current_preset = tier
	var root: Node3D = auto_free(Node3D.new())
	add_child(root)
	var objects := Node3D.new()
	root.add_child(objects)
	var manager: OPRArmyManager = auto_free(OPRArmyManager.new())
	manager.object_manager = objects
	return manager._create_army_tray(1, "Test army", OPRArmyManager.PLAYER_COLORS[1])

func _materials(tray: Node3D) -> Array:
	var result: Array = []
	for child in tray.get_children():
		if child is MeshInstance3D:
			result.append(child.material_override)
	return result

func test_live_quality_change_restores_original_materials_without_changing_collision() -> void:
	var tray := _tray(GraphicsSettings.QualityPreset.LOW)
	var originals := _materials(tray)
	var shape: CollisionShape3D
	for child in tray.get_children():
		if child is CollisionShape3D:
			shape = child
	var bounds: Vector3 = shape.shape.size
	var place := tray.global_transform
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.ULTRA
	GraphicsSettings.settings_applied.emit("Ultra")
	assert_bool(_materials(tray)[0] is ShaderMaterial).is_true()
	assert_object(tray.get_node_or_null("ArmyTrayStyle/TraySupport")).is_not_null()
	assert_vector(shape.shape.size).is_equal(bounds)
	assert_bool(tray.global_transform.is_equal_approx(place)).is_true()
	assert_bool(tray.is_in_group("army_tray")).is_true()
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.LOW
	GraphicsSettings.settings_applied.emit("Low")
	assert_array(_materials(tray)).is_equal(originals)
	var support := tray.get_node_or_null("ArmyTrayStyle/TraySupport")
	if support != null:
		assert_bool(support.visible).is_false()

func test_new_dressed_tray_mutes_bands_and_keeps_readable_staging_labels() -> void:
	var tray := _tray(GraphicsSettings.QualityPreset.MEDIUM)
	assert_bool(_materials(tray)[0] is ShaderMaterial).is_true()
	for child in tray.get_children():
		if child is MeshInstance3D and child.mesh is PlaneMesh:
			var mat: StandardMaterial3D = child.material_override
			assert_float(mat.albedo_color.a).is_less(0.1)
			assert_int(mat.shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_PER_PIXEL)
	for label in ["Ambush", "Scout"]:
		var node: Label3D = tray.get_node("AmbushScoutLabel_" + label)
		assert_str(node.text).is_equal(label)
		assert_bool(node.visible).is_true()
