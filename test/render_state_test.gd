extends GdUnitTestSuite
## RenderState — one owner of the contested Environment values: layers win in a fixed order, never by call order.


func test_the_higher_layer_wins_whatever_the_call_order() -> void:
	var preset_first := Environment.new()
	var reference_first := Environment.new()
	var a := RenderState.new(preset_first)
	a.set_layer("preset", {"sdfgi_enabled": true, "ssao_radius": 1.2})
	a.set_layer("reference", {"sdfgi_enabled": false, "ssao_radius": 0.035})
	var b := RenderState.new(reference_first)
	b.set_layer("reference", {"sdfgi_enabled": false, "ssao_radius": 0.035})
	b.set_layer("preset", {"sdfgi_enabled": true, "ssao_radius": 1.2})
	for env: Environment in [preset_first, reference_first]:
		assert_bool(env.sdfgi_enabled).is_false()
		assert_float(env.ssao_radius).is_equal_approx(0.035, 0.0001)


func test_a_cleared_layer_falls_back_to_the_layer_below_then_to_the_scene_value() -> void:
	var env := Environment.new()
	env.glow_bloom = 0.2   # the scene's own value
	var state := RenderState.new(env)
	state.set_layer("preset", {"glow_bloom": 0.05})
	state.set_layer("reference", {"glow_bloom": 0.1})
	assert_float(env.glow_bloom).is_equal_approx(0.1, 0.0001)
	state.set_layer("reference", {})
	assert_float(env.glow_bloom).is_equal_approx(0.05, 0.0001)
	state.set_layer("preset", {})
	assert_float(env.glow_bloom).is_equal_approx(0.2, 0.0001)


func test_merge_layer_changes_single_values_and_keeps_the_rest() -> void:
	var env := Environment.new()
	var state := RenderState.new(env)
	state.set_layer("light", {"glow_intensity": 0.9, "ssao_intensity": 0.4})
	state.merge_layer("light", {"glow_intensity": 1.3})
	assert_float(env.glow_intensity).is_equal_approx(1.3, 0.0001)
	assert_float(env.ssao_intensity).is_equal_approx(0.4, 0.0001)
