extends GdUnitTestSuite
const Boot := preload("res://test/e2e/e2e_boot.gd")
var _before: Array
var _preset: int
var _strength: Variant

func before_test() -> void:
	Boot.arm_harness_mode()
	_before = Boot.root_children(get_tree())
	_preset = GraphicsSettings.current_preset
	_strength = GraphicsSettings.get("biome_grade_strength")

func after_test() -> void:
	if _strength != null:
		GraphicsSettings.call("set_biome_grade_strength", _strength)
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
	var picker := main.lighting_panel.find_child("BiomeGradeStrengthOption", true, false) as OptionButton
	assert_object(picker).is_not_null()
	if picker == null:
		return
	var previous := 0.0
	for strength in range(3):
		picker.select(strength)
		picker.item_selected.emit(strength)
		var curve := env.adjustment_color_correction as GradientTexture1D
		var delta := absf(curve.gradient.get_color(1).r - 0.5)
		assert_float(delta).is_greater(previous)
		previous = delta
		GraphicsSettings.set("biome_grade_strength", -1)
		GraphicsSettings.load_settings()
		assert_int(GraphicsSettings.get("biome_grade_strength")).is_equal(strength)
	GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.LOW)
	await get_tree().create_timer(0.6).timeout
	assert_object(env.adjustment_color_correction).is_null()
	main.lighting_controller.set_contrast(1.07)
	assert_float(env.adjustment_contrast).is_equal_approx(1.07, 0.0001)
