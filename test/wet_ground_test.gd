extends GdUnitTestSuite
## Rain soaks the table ground on High/Ultra only; every other mood, tier and the volcanic crust stay dry (0.0 = today's surface).

const Settings := preload("res://scripts/graphics_settings.gd")


func test_rain_wets_the_ground_on_high_and_ultra_only() -> void:
	assert_float(Settings.rainfall_for(Settings.QualityPreset.HIGH, "Rain", "temperate_grassland")).is_equal(1.0)
	assert_float(Settings.rainfall_for(Settings.QualityPreset.ULTRA, "Rain", "temperate_grassland")).is_equal(1.0)
	for tier in [Settings.QualityPreset.PERFORMANCE, Settings.QualityPreset.LOW, Settings.QualityPreset.MEDIUM]:
		assert_float(Settings.rainfall_for(tier, "Rain", "temperate_grassland")).is_equal(0.0)


func test_dry_moods_and_the_volcanic_crust_stay_dry() -> void:
	for mood in ["Day", "Sunset", "Night", "Overcast"]:
		assert_float(Settings.rainfall_for(Settings.QualityPreset.ULTRA, mood, "temperate_grassland")).is_equal(0.0)
	assert_float(Settings.rainfall_for(Settings.QualityPreset.ULTRA, "Rain", "volcanic_ash")).is_equal(0.0)


func test_the_ground_shader_carries_the_rainfall_uniform_at_zero() -> void:
	var source := FileAccess.get_file_as_string("res://shaders/visual/reference_ground_body.gdshaderinc")
	assert_str(source).contains("uniform float rainfall = 0.0;")
