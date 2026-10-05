extends GdUnitTestSuite
const Boot := preload("res://test/e2e/e2e_boot.gd")
var _before: Array
var _preset: int
var _style: Variant

func before_test() -> void:
	Boot.arm_harness_mode()
	_before = Boot.root_children(get_tree())
	_preset = GraphicsSettings.current_preset
	_style = GraphicsSettings.get("table_frame_style")

func after_test() -> void:
	if _style != null:
		GraphicsSettings.call("set_table_frame_style", _style)
	GraphicsSettings.apply_preset(_preset)
	Boot.free_stray_root_nodes(get_tree(), _before)

func test_frame_choices_default_to_today_and_survive_dressing_resize_and_low(timeout := 120000) -> void:
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.HIGH)
	var saved := ConfigFile.new()
	assert_int(saved.load("user://graphics_settings.cfg")).is_equal(OK)
	if saved.has_section_key("graphics", "table_frame_style"):
		saved.erase_section_key("graphics", "table_frame_style")
	saved.set_value("graphics", "table_frame_strength", 2)  # Old capture choice must not become the default.
	assert_int(saved.save("user://graphics_settings.cfg")).is_equal(OK)
	GraphicsSettings.load_settings()
	var original := StandardMaterial3D.new()
	assert_object(GraphicsSettings.table_frame_material(original, false)).is_same(original)
	var runner := scene_runner(Boot.MAIN_SCENE)
	var main := runner.scene()
	await runner.simulate_frames(10)
	var picker := main.lighting_panel.find_child("TableFrameOption", true, false) as OptionButton
	assert_object(picker).is_not_null()
	if picker == null:
		return
	assert_int(picker.selected).is_equal(0)
	assert_int(picker.item_count).is_equal(4)
	main._table_biome_presenter.allow_headless = true
	var table: Node = main.get_node("Table")
	for tier in [3, 1, 2, 1]:
		GraphicsSettings.apply_preset(tier)
		await get_tree().create_timer(0.6).timeout
		await main._table_biome_presenter.rebuild()
		for style in [0, 1, 2, 3, 0]:
			picker.select(style)
			picker.item_selected.emit(style)
			var shared := {}
			for child in table.get_children():
				if not child.has_meta("graphics_frame_original") or child.is_queued_for_deletion():
					continue
				var mat: Material = child.material_override
				if tier >= 2 and style > 0:
					assert_int(mat.get_shader_parameter("frame_strength")).is_equal(style - 1)
				else:
					var key := "graphics_frame_reference" if tier >= 2 else "graphics_frame_original"
					assert_object(mat).is_same(child.get_meta(key))
					var expected := Color(0.022, 0.026, 0.023) if tier >= 2 else Color(0.3, 0.2, 0.1)
					assert_bool(mat.albedo_color.is_equal_approx(expected)).is_true()
				var axis: bool = child.get_meta("graphics_frame_axis")
				if not shared.has(axis): shared[axis] = mat
				assert_object(mat).is_same(shared[axis])
			GraphicsSettings.set("table_frame_style", -1)
			GraphicsSettings.load_settings()
			assert_int(GraphicsSettings.get("table_frame_style")).is_equal(style)
		for wall in table.get_children():
			if wall is StaticBody3D and not wall.is_queued_for_deletion():
				assert_float(wall.get_child(0).shape.size.y).is_equal_approx(0.15, 0.0001)
		table.setup_table(Vector2(4, 4))
		await runner.simulate_frames(3)
