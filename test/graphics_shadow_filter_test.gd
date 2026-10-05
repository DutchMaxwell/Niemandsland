extends GdUnitTestSuite
## Observe runtime filter submissions: downgrading must restore the old global quality.

class ShadowProbe extends "res://scripts/graphics_settings.gd":
	var submitted: Array[int] = []
	func _ready() -> void:
		apply_preset(current_preset)
	func _set_shadow_filter_quality(quality: RenderingServer.ShadowQuality) -> void:
		submitted.append(quality)


func test_live_preset_round_trip_submits_shadow_quality_every_time() -> void:
	var original: int = GraphicsSettings.current_preset
	var probe: ShadowProbe = auto_free(ShadowProbe.new())
	probe.current_preset = GraphicsSettings.QualityPreset.LOW
	add_child(probe)
	for tier in [3, 1, 4, 2, 0, 1]:
		probe.apply_preset(tier)
	assert_array(probe.submitted).is_equal([3, 4, 3, 5, 3, 3, 3])
	# The old implementation always used these project defaults, even on Low/Performance.
	assert_int(ProjectSettings.get_setting("rendering/lights_and_shadows/directional_shadow/soft_shadow_filter_quality")).is_equal(3)
	assert_int(ProjectSettings.get_setting("rendering/lights_and_shadows/positional_shadow/soft_shadow_filter_quality")).is_equal(3)
	GraphicsSettings.apply_preset(original)
	RenderingServer.emit_signal("frame_post_draw")
	RenderingServer.emit_signal("frame_post_draw")


func test_shadow_contact_policy_survives_light_edits_and_restores_low() -> void:
	var original: int = GraphicsSettings.current_preset
	var sun: DirectionalLight3D = auto_free(DirectionalLight3D.new())
	add_child(sun)
	sun.directional_shadow_split_1 = 0.15
	var world: WorldEnvironment = auto_free(WorldEnvironment.new())
	world.environment = Environment.new()
	var light: Node = auto_free(load("res://scripts/lighting_controller.gd").new())
	light.initialize(sun, world)
	for tier in [2, 1, 3, 0, 4, 1]:
		GraphicsSettings.apply_preset(tier)
		light.set_shadow_bias(0.03)
		light.set_shadow_normal_bias(1.0)
		assert_float(sun.shadow_bias).is_equal_approx(0.01 if tier >= 2 else 0.03, 0.0001)
		assert_float(sun.shadow_normal_bias).is_equal_approx(0.15 if tier >= 2 else 1.0, 0.0001)
		assert_float(sun.directional_shadow_split_1).is_equal_approx(0.30 if tier >= 2 else 0.15, 0.0001)
	GraphicsSettings.apply_preset(original)
	RenderingServer.emit_signal("frame_post_draw")
	RenderingServer.emit_signal("frame_post_draw")
