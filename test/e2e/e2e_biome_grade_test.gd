extends GdUnitTestSuite
const Boot := preload("res://test/e2e/e2e_boot.gd")
var _before: Array
var _preset: int

func before_test() -> void:
	Boot.arm_harness_mode()
	_before = Boot.root_children(get_tree())
	_preset = GraphicsSettings.current_preset

func after_test() -> void:
	GraphicsSettings.apply_preset(_preset)
	Boot.free_stray_root_nodes(get_tree(), _before)

func test_each_biome_keeps_its_grade_through_moods_and_restores_low(timeout := 120000) -> void:
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.HIGH)
	var runner := scene_runner(Boot.MAIN_SCENE)
	var main := runner.scene()
	await runner.simulate_frames(10)
	main._table_biome_presenter.allow_headless = true
	var env: Environment = main.get_node("WorldEnvironment").environment
	var table: Node = main.get_node("Table")
	var tints := {}
	for biome in table.BIOMES:
		table.set_biome(biome)
		await get_tree().create_timer(0.7).timeout
		await runner.simulate_frames(2)
		var lut := env.adjustment_color_correction as GradientTexture1D
		assert_object(lut).is_not_null()
		if lut == null:
			continue
		tints[lut.gradient.get_color(1).to_html()] = true
		main.atmosphere_controller.apply_atmosphere("Overcast", true)
		await runner.simulate_frames(2)
		assert_object(env.adjustment_color_correction).is_same(lut)
		assert_float(env.glow_bloom).is_equal_approx(0.0, 0.0001)
	assert_int(tints.size()).is_equal(6)
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.LOW)
	await get_tree().create_timer(0.6).timeout
	assert_object(env.adjustment_color_correction).is_null()
	main.lighting_controller.set_contrast(1.07)
	assert_float(env.adjustment_contrast).is_equal_approx(1.07, 0.0001)
