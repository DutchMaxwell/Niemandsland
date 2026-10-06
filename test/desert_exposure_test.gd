extends GdUnitTestSuite
const Biomes := preload("res://scripts/visual/reference_biomes.gd")
const Rig := preload("res://scripts/visual/table_lighting.gd")

func test_bright_sand_gets_lower_daylight_exposure_without_dimming_weather() -> void:
	for mood in ["Day", "Sunset"]:
		assert_float(Rig.values(Biomes.ARID_DESERT, mood).exposure).is_less(Rig.values(Biomes.GRASSLAND, mood).exposure * 0.8)
	for mood in ["Night", "Rain", "Overcast"]:
		assert_float(Rig.values(Biomes.ARID_DESERT, mood).exposure).is_equal(Rig.values(Biomes.GRASSLAND, mood).exposure)

func test_desert_sunset_curve_preserves_sand_contrast_and_low_gate() -> void:
	var old := GraphicsSettings.current_preset
	for tier in [GraphicsSettings.QualityPreset.MEDIUM, GraphicsSettings.QualityPreset.ULTRA]:
		GraphicsSettings.current_preset = tier
		var grade := GraphicsSettings.biome_grade_values("arid_desert", "Sunset")
		var curve: Gradient = (grade.adjustment_color_correction as GradientTexture1D).gradient
		var mid := curve.sample(0.5)
		assert_float(mid.r).is_less(0.51)
		assert_float(mid.r - mid.g).is_less(0.06)
		assert_float(grade.adjustment_saturation).is_greater(0.95)
		assert_float(grade.tonemap_agx_contrast).is_greater(1.15)
		assert_bool(curve.sample(0.0).is_equal_approx(Color.BLACK)).is_true()
		assert_bool(curve.sample(1.0).is_equal_approx(Color.WHITE)).is_true()
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.LOW
	assert_dict(GraphicsSettings.biome_grade_values("arid_desert", "Sunset")).is_empty()
	GraphicsSettings.current_preset = old
