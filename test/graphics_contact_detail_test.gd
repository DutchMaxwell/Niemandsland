extends GdUnitTestSuite
## Detail AO must survive biome/mood layers and restore the exact cheap-tier baseline.

func test_contact_detail_survives_reference_and_mood_in_either_order() -> void:
	for tier in [2, 3, 4]:
		for preset_first in [true, false]:
			var env := Environment.new()
			var state := RenderState.new(env)
			var values := GraphicsSettings.environment_values(GraphicsSettings.PRESETS[tier], tier)
			if preset_first:
				state.set_layer("preset", values)
			state.set_layer("reference", {"ssao_radius": 0.035, "ssao_power": 1.4})
			state.set_layer("light", {"ssao_intensity": 0.4})
			state.set_layer("preset", values)
			assert_float(env.ssao_detail).is_equal_approx(0.65 if tier == 2 else 0.75, 0.0001)
			assert_float(env.ssao_radius).is_equal_approx(0.035, 0.0001)
			assert_float(env.ssao_intensity).is_equal_approx(0.4, 0.0001)
			state.set_layer("intro", {"ssao_enabled": false})
			assert_bool(env.ssao_enabled).is_false()
			state.set_layer("intro", {})
			assert_bool(env.ssao_enabled).is_true()


func test_low_and_performance_restore_detail_after_higher_tiers() -> void:
	var env := Environment.new()
	var state := RenderState.new(env)
	for tier in [2, 1, 3, 0, 4, 1]:
		state.set_layer("preset", GraphicsSettings.environment_values(GraphicsSettings.PRESETS[tier], tier))
		if tier <= 1:
			assert_bool(env.ssao_enabled).is_false()
			assert_float(env.ssao_detail).is_equal_approx(0.5, 0.0001)
