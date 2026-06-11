extends GdUnitTestSuite
## Tests the atmosphere preset layer: every atmosphere preset references an existing
## lighting preset, lighting presets carry every key the blend interpolates, and the
## 2-second blend reproduces its endpoints exactly (including the sun-angle wrap).

const AtmosphereScript = preload("res://scripts/atmosphere_controller.gd")
const LightingScript = preload("res://scripts/lighting_controller.gd")


func _atmosphere_with_lighting() -> Array:
	# A real lighting controller on minimal scene nodes, driven by the atmosphere.
	var light: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	add_child(auto_free(env))

	var lighting: Node = auto_free(Node.new())
	lighting.set_script(LightingScript)
	add_child(lighting)
	lighting.initialize(light, env, null)

	var atmosphere: Node = auto_free(AtmosphereScript.new())
	add_child(atmosphere)
	atmosphere.initialize(lighting, env, null, null)
	return [atmosphere, lighting, light]


func test_atmosphere_presets_reference_existing_lighting_presets() -> void:
	for preset_name in AtmosphereScript.PRESETS:
		var lighting_name: String = AtmosphereScript.PRESETS[preset_name]["lighting"]
		assert_bool(LightingScript.PRESETS.has(lighting_name)) \
				.override_failure_message("Atmosphere '%s' references unknown lighting preset '%s'"
						% [preset_name, lighting_name]).is_true()


func test_lighting_presets_carry_all_blend_keys() -> void:
	var required: Array = AtmosphereScript._BLEND_FLOAT_SETTERS.keys() \
			+ AtmosphereScript._BLEND_COLOR_SETTERS.keys() + ["sun_angle_h", "sun_angle_v"]
	for preset_name in LightingScript.PRESETS:
		var preset: Dictionary = LightingScript.PRESETS[preset_name]
		for key: String in required:
			assert_bool(preset.has(key)) \
					.override_failure_message("Lighting preset '%s' lacks blend key '%s'"
							% [preset_name, key]).is_true()


func test_instant_apply_reaches_the_target_values() -> void:
	var nodes := _atmosphere_with_lighting()
	var atmosphere: Node = nodes[0]
	var lighting: Node = nodes[1]
	var light: DirectionalLight3D = nodes[2]

	atmosphere.apply_atmosphere("Night", true)
	var target: Dictionary = LightingScript.PRESETS["Night"]
	assert_float(light.light_energy).is_equal_approx(target["sun_energy"], 0.001)
	assert_float(lighting.current_preset["ambient_energy"]).is_equal_approx(target["ambient_energy"], 0.001)
	assert_float(lighting.current_preset["sun_angle_h"]).is_equal_approx(target["sun_angle_h"], 0.01)
	assert_str(atmosphere.get_current_atmosphere()).is_equal("Night")


func test_blend_endpoints_reproduce_from_and_to() -> void:
	var nodes := _atmosphere_with_lighting()
	var atmosphere: Node = nodes[0]
	var lighting: Node = nodes[1]

	atmosphere.apply_atmosphere("Day", true)
	var from: Dictionary = lighting.current_preset.duplicate()
	var to: Dictionary = LightingScript.PRESETS["Night"]

	atmosphere._apply_blend(0.0, from, to, {}, AtmosphereScript.PRESETS["Night"],
			Color.WHITE, 1.0)
	assert_float(lighting.current_preset["sun_energy"]).is_equal_approx(from["sun_energy"], 0.001)

	atmosphere._apply_blend(1.0, from, to, {}, AtmosphereScript.PRESETS["Night"],
			Color.WHITE, 1.0)
	assert_float(lighting.current_preset["sun_energy"]).is_equal_approx(to["sun_energy"], 0.001)
	assert_float(lighting.current_preset["glow_intensity"]).is_equal_approx(to["glow_intensity"], 0.001)


func test_sun_angle_blend_takes_the_short_way_around() -> void:
	var nodes := _atmosphere_with_lighting()
	var atmosphere: Node = nodes[0]
	var lighting: Node = nodes[1]

	var from := {"sun_angle_h": 170.0, "sun_angle_v": 45.0}
	var to := {"sun_angle_h": -170.0, "sun_angle_v": 45.0}
	atmosphere._apply_blend(0.5, from, to, {}, AtmosphereScript.PRESETS["Day"],
			Color.WHITE, 1.0)
	# Halfway between 170 and -170 the short way is +/-180, NOT 0.
	assert_float(absf(lighting.current_preset["sun_angle_h"])).is_equal_approx(180.0, 0.5)