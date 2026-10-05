extends GdUnitTestSuite
## Quality changes preserve cheap-tier AA but keep 4x MSAA miniatures crisp.

var _preset_before: int


func before_test() -> void:
	_preset_before = GraphicsSettings.current_preset


func after_test() -> void:
	GraphicsSettings.apply_preset(_preset_before)
	RenderingServer.emit_signal("frame_post_draw")
	RenderingServer.emit_signal("frame_post_draw")


func test_medium_and_above_do_not_stack_fxaa_on_msaa() -> void:
	for tier in [2, 3, 4]:
		GraphicsSettings.apply_preset(tier)
		assert_int(get_tree().root.msaa_3d).is_equal(Viewport.MSAA_4X)
		assert_bool(get_tree().root.use_taa).is_false()
		assert_int(get_tree().root.screen_space_aa).is_equal(Viewport.SCREEN_SPACE_AA_DISABLED)


func test_low_and_performance_keep_fxaa_after_a_quality_round_trip() -> void:
	for tier in [0, 1]:
		GraphicsSettings.apply_preset(GraphicsSettings.QualityPreset.HIGH)
		GraphicsSettings.apply_preset(tier)
		assert_int(get_tree().root.msaa_3d).is_equal(tier)
		assert_int(get_tree().root.screen_space_aa).is_equal(Viewport.SCREEN_SPACE_AA_FXAA)


func test_taa_suppresses_fxaa_even_when_the_preset_requests_it() -> void:
	var settings: Dictionary = GraphicsSettings.PRESETS[1].duplicate()
	settings["use_taa"] = true
	settings["screen_space_aa"] = Viewport.SCREEN_SPACE_AA_FXAA
	GraphicsSettings.apply_rendering_settings(settings)
	assert_bool(get_tree().root.use_taa).is_true()
	assert_int(get_tree().root.screen_space_aa).is_equal(Viewport.SCREEN_SPACE_AA_DISABLED)
