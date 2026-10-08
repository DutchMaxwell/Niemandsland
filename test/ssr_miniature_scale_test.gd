extends GdUnitTestSuite
## Screen-space reflections at miniature scale (High/Ultra): Medium and Low stay byte-identical to before.

const Settings := preload("res://scripts/graphics_settings.gd")


func test_high_and_ultra_use_short_miniature_scale_reflections() -> void:
	for tier in [Settings.QualityPreset.HIGH, Settings.QualityPreset.ULTRA]:
		var values := Settings.environment_values(Settings.PRESETS[tier], tier)
		assert_int(values["ssr_max_steps"]).is_equal(96)
		assert_float(values["ssr_depth_tolerance"]).is_less(0.05)
		assert_float(values["ssr_fade_out"]).is_less(1.6)


func test_medium_and_low_gain_no_reflection_keys_and_keep_the_legacy_fade() -> void:
	for tier in [Settings.QualityPreset.PERFORMANCE, Settings.QualityPreset.LOW, Settings.QualityPreset.MEDIUM]:
		var values := Settings.environment_values(Settings.PRESETS[tier], tier)
		for key in values:
			assert_bool(str(key).begins_with("ssr_") and key != "ssr_enabled").is_false()
		assert_float(Settings.ssr_fade_in_for(tier, 0.9)).is_equal(0.9)
		assert_float(Settings.ssr_fade_in_for(tier, 0.2)).is_equal(0.2)


func test_the_mood_strength_becomes_a_short_fade_in_on_high() -> void:
	assert_float(Settings.ssr_fade_in_for(Settings.QualityPreset.HIGH, 0.9)).is_equal_approx(0.03, 0.0001)
	assert_float(Settings.ssr_fade_in_for(Settings.QualityPreset.ULTRA, 0.0)).is_equal_approx(0.12, 0.0001)
	assert_float(Settings.ssr_fade_in_for(Settings.QualityPreset.ULTRA, 3.0)).is_equal_approx(0.02, 0.0001)
