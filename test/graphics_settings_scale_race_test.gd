extends GdUnitTestSuite
## GraphicsSettings defers the render-scale change by two drawn frames (Performance boundary, see
## apply_rendering_settings). A second preset inside that window must win: Performance -> Low has to end at Low's 1.0,
## not at Performance's 0.77 written late by the first, stale coroutine. Headless never draws, so the test emits
## frame_post_draw itself.

var _preset_before: int
var _scale_before: float


func before_test() -> void:
	_preset_before = _graphics().current_preset
	_scale_before = get_tree().root.scaling_3d_scale


func after_test() -> void:
	_graphics().apply_preset(_preset_before)   # apply_preset persists: hand the player's choice back
	_draw_frames(2)
	get_tree().root.scaling_3d_scale = _scale_before


func _graphics() -> Node:
	return get_tree().root.get_node("GraphicsSettings")


func _draw_frames(count: int) -> void:
	for i in count:
		RenderingServer.emit_signal("frame_post_draw")


func test_the_last_preset_wins_the_deferred_render_scale() -> void:
	var graphics := _graphics()
	get_tree().root.scaling_3d_scale = 1.0
	graphics.apply_preset(graphics.QualityPreset.PERFORMANCE)   # 0.77, deferred by two drawn frames
	graphics.apply_preset(graphics.QualityPreset.LOW)           # 1.0 inside that window
	_draw_frames(3)
	assert_float(get_tree().root.scaling_3d_scale).override_failure_message(
		"Performance -> Low within two frames left the render scale at %.2f" % get_tree().root.scaling_3d_scale) \
		.is_equal_approx(1.0, 0.001)
