extends GdUnitTestSuite
## Broken-cloud sunlight (light islands): High and Ultra, Day only. A spot along the sun projects a cloud mask and the
## sun dims under the clouds; every other mood, Medium and below stay as they were.

const Settings := preload("res://scripts/graphics_settings.gd")
const LightingScript := preload("res://scripts/lighting_controller.gd")
const WorldScript := preload("res://scripts/visual/table_world.gd")


func test_islands_only_on_high_and_ultra_in_the_day() -> void:
	for tier in 5:
		for mood in ["Day", "Sunset", "Night", "Overcast", "Rain"]:
			assert_bool(Settings.cloud_light_enabled(tier, mood)) \
				.override_failure_message("tier %d %s" % [tier, mood]) \
				.is_equal(tier >= Settings.QualityPreset.HIGH and mood == "Day")


func test_the_sun_scale_dims_every_mood_value_and_restores_it() -> void:
	var lighting: Node = auto_free(LightingScript.new())
	var sun: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	lighting.set("_directional_light", sun)
	lighting.set_sun_energy(1.8)
	lighting.set_sun_scale(0.4)
	assert_float(sun.light_energy).is_equal_approx(0.72, 0.0001)
	lighting.set_sun_energy(1.5)   # a mood blend keeps writing the unscaled value
	assert_float(sun.light_energy).is_equal_approx(0.6, 0.0001)
	assert_float(float(lighting.current_preset.sun_energy)).is_equal_approx(1.5, 0.0001)
	lighting.set_sun_scale(1.0)
	assert_float(sun.light_energy).is_equal_approx(1.5, 0.0001)


func test_the_cloud_light_projects_a_soft_mask_through_its_shadow_pass() -> void:
	var spot: SpotLight3D = auto_free(WorldScript.make_cloud_light())
	assert_bool(spot.shadow_enabled).is_true()   # without its shadow pass the projector shows nothing
	assert_int(spot.shadow_caster_mask).is_equal(0)   # no caster in it: the projector alone carries the islands
	assert_object(spot.light_projector).is_not_null()
	var mask: Image = spot.light_projector.get_image()
	var lit := 0
	for y in range(0, mask.get_height(), 8):
		for x in range(0, mask.get_width(), 8):
			lit += 1 if mask.get_pixel(x, y).r > 0.5 else 0
	var samples := (mask.get_height() / 8) * (mask.get_width() / 8)
	assert_float(float(lit) / samples).is_between(0.25, 0.75)   # sun gaps and cloud shadow, neither dominates
