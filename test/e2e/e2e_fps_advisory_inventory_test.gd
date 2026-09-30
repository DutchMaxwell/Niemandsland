extends GdUnitTestSuite
## E2E — the low-framerate advisory, row 40 of the UI inventory (uimenus step 10): the text "Low framerate may be
## destabilising your online connection.", Lower Graphics Quality (one tier down, with a toast) and Dismiss; it
## shows only in a multiplayer session (the 8 s under 18 fps trigger is main.gd's and untouched). The 20 s
## auto-hide is a tween and is not waited for here. Real main.tscn; the graphics preset is put back.
## test_inventory_check_names_a_removed_control proves the presence check can fail.

const E2EBoot := preload("res://test/e2e/e2e_boot.gd")

var _runner: GdUnitSceneRunner
var _main: Node
var _root_before: Array
var _preset_before := 0


func before_test() -> void:
	E2EBoot.arm_harness_mode()
	_root_before = E2EBoot.root_children(get_tree())
	_preset_before = GraphicsSettings.current_preset
	_runner = scene_runner(E2EBoot.MAIN_SCENE)
	_main = _runner.scene()
	await _runner.simulate_frames(4)


func after_test() -> void:
	GraphicsSettings.apply_preset(_preset_before)
	E2EBoot.free_stray_root_nodes(get_tree(), _root_before)


func _panel() -> Control:
	var p := _main.get_node_or_null("UI/FpsAdvisory") as Control
	return p if p != null and not p.is_queued_for_deletion() else null


func _button(text: String) -> Button:
	for n: Node in _panel().find_children("*", "Button", true, false):
		if (n as Button).text == text:
			return n as Button
	return null


func _missing() -> Array:
	var missing: Array = []
	if _panel() == null:
		return ["panel"]
	for t: String in ["Lower Graphics Quality", "Dismiss"]:
		if _button(t) == null:
			missing.append("button: %s" % t)
	var has_text := false
	for l: Node in _panel().find_children("*", "Label", true, false):
		if (l as Label).text == "Low framerate may be destabilising your online connection.":
			has_text = true
	if not has_text:
		missing.append("label: the warning")
	return missing


func test_the_advisory_has_its_words_and_both_buttons() -> void:
	_main._show_fps_advisory()
	await _runner.simulate_frames(2)
	assert_array(_missing()).override_failure_message("advisory controls missing: %s" % str(_missing())).is_empty()


func test_lower_graphics_quality_goes_one_tier_down_and_closes_the_advisory() -> void:
	GraphicsSettings.apply_preset(3)
	_main._show_fps_advisory()
	await _runner.simulate_frames(2)
	_button("Lower Graphics Quality").pressed.emit()
	await _runner.simulate_frames(2)
	assert_int(GraphicsSettings.current_preset).is_equal(2)
	assert_object(_panel()).override_failure_message("the advisory stayed up").is_null()


func test_lowest_tier_stays_the_lowest() -> void:
	GraphicsSettings.apply_preset(0)
	_main._show_fps_advisory()
	await _runner.simulate_frames(2)
	_button("Lower Graphics Quality").pressed.emit()
	assert_int(GraphicsSettings.current_preset).is_equal(0)


func test_dismiss_closes_it_and_changes_nothing() -> void:
	GraphicsSettings.apply_preset(3)
	_main._show_fps_advisory()
	await _runner.simulate_frames(2)
	_button("Dismiss").pressed.emit()
	await _runner.simulate_frames(2)
	assert_object(_panel()).is_null()
	assert_int(GraphicsSettings.current_preset).is_equal(3)


func test_no_advisory_outside_a_multiplayer_session() -> void:
	_main._fps_low_since_ms = Time.get_ticks_msec() - 20000
	_main._check_fps_advisory()
	await _runner.simulate_frames(2)
	assert_object(_panel()).override_failure_message("the advisory showed in a solo game").is_null()


func test_the_advisory_wears_the_house_style() -> void:
	_main._show_fps_advisory()
	await _runner.simulate_frames(2)
	assert_object(_panel().theme).is_same(HouseStyle.theme())
	assert_that((_panel().get_theme_stylebox(&"panel") as StyleBoxFlat).bg_color).is_equal(HouseStyle.warning_box().bg_color)
	for t: String in ["Lower Graphics Quality", "Dismiss"]:
		assert_str(String(_button(t).theme_type_variation)).is_equal(String(HouseStyle.BUTTON))
	assert_int(_panel().mouse_filter).override_failure_message("the advisory must own its clicks").is_equal(Control.MOUSE_FILTER_STOP)


func test_inventory_check_names_a_removed_control() -> void:
	_main._show_fps_advisory()
	await _runner.simulate_frames(2)
	assert_array(_missing()).is_empty()
	var dismiss := _button("Dismiss")
	var parent := dismiss.get_parent()
	parent.remove_child(dismiss)
	var missing := _missing()
	parent.add_child(dismiss)
	assert_array(missing).contains_exactly(["button: Dismiss"])
