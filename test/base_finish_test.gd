extends GdUnitTestSuite
## One table material/map pair serves every base; quality changes restore the old finish.
const TableScript := preload("res://scripts/table.gd")

func test_base_finish_uses_shared_maps_and_keeps_material_identity() -> void:
	var original: int = GraphicsSettings.current_preset
	var table: Node = auto_free(TableScript.new())
	table._build_ground_material()
	var mat: ShaderMaterial = table.get_base_top_material()
	for tier in [2, 1, 4, 0]:
		GraphicsSettings.apply_preset(tier)
		table._update_base_top_material()
		assert_object(table.get_base_top_material()).is_same(mat)
		assert_bool(mat.get_shader_parameter("flock_enabled") == (tier >= 2)).is_true()
		if tier >= 2:
			assert_object(mat.get_shader_parameter("flock_height")).is_same(table._detail_height_tex)
			assert_object(mat.get_shader_parameter("flock_normal")).is_same(table._detail_normal_tex)
		assert_float(BaseDecor.rim_material().roughness).is_equal_approx(0.42 if tier >= 2 else BaseDecor.RIM_ROUGHNESS, 0.0001)
	GraphicsSettings.apply_preset(original)
	RenderingServer.emit_signal("frame_post_draw")
	RenderingServer.emit_signal("frame_post_draw")
