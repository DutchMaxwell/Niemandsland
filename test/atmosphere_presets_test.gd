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

func test_night_is_a_readable_full_moon_night() -> void:
	var night: Dictionary = LightingScript.PRESETS["Night"]
	# bluish moonlight strong enough to read the table, with ambient fill so shadows are not black
	assert_float(night["sun_energy"]).is_greater_equal(1.2)
	assert_float(night["ambient_energy"]).is_greater_equal(0.25)
	assert_float(night["sun_color"].b).is_greater(night["sun_color"].r)
	# still clearly night: far dimmer than the day key
	assert_float(night["sun_energy"]).is_less(LightingScript.PRESETS["Default"]["sun_energy"])


func test_only_night_shows_the_moon() -> void:
	for preset_name in AtmosphereScript.PRESETS:
		var expected := 1.0 if preset_name == "Night" else 0.0
		assert_float(AtmosphereScript.PRESETS[preset_name].get("moon", 0.0)).is_equal(expected)


func test_blend_fades_the_moon_in_the_sky_shader() -> void:
	var rig := _atmosphere_with_lighting()
	var atmosphere: Node = rig[0]
	var sky := ShaderMaterial.new()
	sky.shader = load("res://shaders/space_skybox.gdshader")
	var env: Environment = atmosphere._world_env.environment
	env.sky = Sky.new()
	env.sky.sky_material = sky
	var preset: Dictionary = AtmosphereScript.PRESETS["Night"]
	atmosphere._apply_blend(1.0, {}, LightingScript.PRESETS["Night"], {"moon": 0.0}, preset, Color.WHITE, 1.0)
	assert_float(float(sky.get_shader_parameter("moon_strength"))).is_equal(1.0)
	atmosphere._apply_blend(0.5, {}, LightingScript.PRESETS["Night"], {"moon": 0.0}, preset, Color.WHITE, 1.0)
	assert_float(float(sky.get_shader_parameter("moon_strength"))).is_equal(0.5)


## Look review 4: the skirmish systems (Firefight gff, AoF Skirmish aofs) start at Night when the player has not picked a mood himself - and the look is the
## Night LIGHTING preset the maintainer approved (look1125d), even on the ruin town, which re-applies its own dusk one frame after every atmosphere change.
## Every other system keeps the standard Sunset; a mood the player picked is saved and wins over every system default, also after a restart.
func test_skirmish_systems_default_to_the_night_look_unless_the_player_picked_a_mood() -> void:
	assert_str(AtmosphereScript.default_preset_for("gff", "")).is_equal("Night")
	assert_str(AtmosphereScript.default_preset_for("aofs", "")).is_equal("Night")
	for big: String in ["gf", "aof", "aofr", ""]:
		assert_str(AtmosphereScript.default_preset_for(big, "")).override_failure_message("%s changed its default" % big).is_equal(AtmosphereScript.DEFAULT_PRESET)
	assert_str(AtmosphereScript.default_preset_for("gff", "Rain")).is_equal("Rain")
	var path := "user://atmosphere_default_test.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
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
	atmosphere.config_path = path
	add_child(atmosphere)
	atmosphere.initialize(lighting, env, null, null)
	# a stand-in for the ruin town: one frame after every atmosphere change it re-applies its own dusk (BoardgenGreybox._dusk_again)
	atmosphere.atmosphere_changed.connect(func(_n: String) -> void: (func() -> void: lighting.set_sun_energy(99.0)).call_deferred())
	atmosphere.apply_default_for_system("gff")
	await await_idle_frame()
	assert_str(atmosphere.get_current_atmosphere()).is_equal("Night")
	assert_str(str(lighting.current_preset.get("name", ""))).override_failure_message("the skirmish default is not the Night lighting look").is_equal(str(LightingScript.PRESETS["Night"]["name"]))
	assert_float(light.light_energy).override_failure_message("the town's dusk replaced the Night look").is_equal_approx(float(LightingScript.PRESETS["Night"]["sun_energy"]), 0.001)
	atmosphere.apply_default_for_system("gf")
	await await_idle_frame()
	assert_str(atmosphere.get_current_atmosphere()).is_equal("Sunset")
	atmosphere.choose_atmosphere("Rain")
	atmosphere.apply_default_for_system("gff")
	await await_idle_frame()
	assert_str(atmosphere.get_current_atmosphere()).override_failure_message("the system default beat the player's pick").is_equal("Rain")
	var again: Node = auto_free(AtmosphereScript.new())   # a restart: the saved pick comes back and still wins
	again.config_path = path
	add_child(again)
	again.initialize(lighting, env, null, null)
	assert_str(again.get_chosen_atmosphere()).override_failure_message("the pick was not saved").is_equal("Rain")
	again.apply_default_for_system("aofs")
	assert_str(again.get_current_atmosphere()).is_equal("Rain")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## Look review 4: the table's game system announces a change, so the mood can follow the system's default.
func test_the_army_manager_announces_the_table_system() -> void:
	var manager: Node = auto_free(OPRArmyManager.new())
	var seen: Array = []
	manager.table_system_changed.connect(func(s: String) -> void: seen.append(s))
	manager.table_system = "gff"
	manager.table_system = "gff"
	manager.table_system = "gf"
	assert_array(seen).is_equal(["gff", "gf"])
