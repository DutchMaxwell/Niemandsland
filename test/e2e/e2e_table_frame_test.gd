extends GdUnitTestSuite
const Boot := preload("res://test/e2e/e2e_boot.gd")
var _before: Array
var _preset: int
var _strength: Variant

func before_test() -> void:
	Boot.arm_harness_mode()
	_before = Boot.root_children(get_tree())
	_preset = GraphicsSettings.current_preset
	_strength = GraphicsSettings.get("table_frame_strength")

func after_test() -> void:
	if _strength != null:
		GraphicsSettings.call("set_table_frame_strength", _strength)
	GraphicsSettings.apply_preset(_preset)
	Boot.free_stray_root_nodes(get_tree(), _before)

func test_frame_finish_survives_dressing_resize_and_low_round_trip(timeout := 120000) -> void:
	var runner := scene_runner(Boot.MAIN_SCENE)
	var main := runner.scene()
	await runner.simulate_frames(10)
	var picker := main.lighting_panel.find_child("TableFrameStrengthOption", true, false) as OptionButton
	assert_object(picker).is_not_null()
	if picker == null:
		return
	main._table_biome_presenter.allow_headless = true
	for tier in [3, 1, 2, 1]:
		GraphicsSettings.apply_preset(tier)
		await get_tree().create_timer(0.6).timeout
		await main._table_biome_presenter.rebuild()
		var table: Node = main.get_node("Table")
		var count := 0
		var shared := {}
		for child in table.get_children():
			if child is MeshInstance3D and child != table.get_node("TableMesh") and not child.is_queued_for_deletion():
				count += 1
				assert_bool(child.material_override is ShaderMaterial).is_equal(tier >= 2)
				var axis: bool = child.get_meta("graphics_frame_axis", false)
				if not shared.has(axis):
					shared[axis] = child.material_override
				assert_object(child.material_override).is_same(shared[axis])
				if tier >= 2:
					for strength in range(3):
						picker.select(strength)
						picker.item_selected.emit(strength)
						assert_int(child.material_override.get_shader_parameter("frame_strength")).is_equal(strength)
		assert_int(count).is_equal(4)
		GraphicsSettings.set("table_frame_strength", -1)
		GraphicsSettings.load_settings()
		assert_int(GraphicsSettings.get("table_frame_strength")).is_equal(2)
		for wall in table.get_children():
			if wall is StaticBody3D and not wall.is_queued_for_deletion():
				assert_float(wall.get_child(0).shape.size.y).is_equal_approx(0.15, 0.0001)
		table.setup_table(Vector2(4, 4))
		await runner.simulate_frames(3)
