extends GdUnitTestSuite
const Biomes := preload("res://scripts/visual/reference_biomes.gd")
const RIG := "res://scripts/visual/table_lighting.gd"

func test_sunset_rig_and_weather_have_distinct_lights() -> void:
	assert_bool(FileAccess.file_exists(RIG)).is_true()
	if not FileAccess.file_exists(RIG):
		return
	var rig = load(RIG)
	var sunset: Dictionary = rig.values(Biomes.GRASSLAND, "Sunset")
	assert_float(sunset.sun_energy).is_equal_approx(3.0,0.001)
	assert_float(sunset.sun_angle_h).is_equal(-145.0)
	assert_float(sunset.sun_angle_v).is_equal(22.0)
	for mood in ["Night", "Rain", "Overcast"]:
		var weather: Dictionary = rig.values(Biomes.GRASSLAND,mood)
		# Night is a strong full-moon key (1.6, see the Night mood); it is still far below the sunset key.
		assert_float(weather.sun_energy).is_less(sunset.sun_energy * 0.6 if mood == "Night" else 1.0)
		assert_float(weather.sun_color.b).is_greater(weather.sun_color.r)
	var desert: Dictionary = rig.values(Biomes.ARID_DESERT,"Day")
	var tundra: Dictionary = rig.values(Biomes.FROZEN_TUNDRA,"Day")
	assert_float(desert.sun_energy).is_greater(tundra.sun_energy)
	assert_float(desert.ambient_color.r).is_greater(tundra.ambient_color.r)

func test_sunset_grade_matches_approved_frame_and_low_is_empty() -> void:
	var old := GraphicsSettings.current_preset
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.MEDIUM
	var grade: Dictionary = GraphicsSettings.biome_grade_values("temperate_grassland")
	var lut: GradientTexture1D = grade.adjustment_color_correction
	assert_int(lut.gradient.get_point_count()).is_equal(5)
	assert_float(grade.adjustment_contrast).is_equal_approx(1.12,0.001)
	GraphicsSettings.current_preset = GraphicsSettings.QualityPreset.LOW
	assert_dict(GraphicsSettings.biome_grade_values("temperate_grassland")).is_empty()
	GraphicsSettings.current_preset = old
