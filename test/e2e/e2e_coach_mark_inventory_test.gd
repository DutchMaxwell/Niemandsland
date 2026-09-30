extends GdUnitTestSuite
## E2E — the coach-mark overlay, row 51 of the UI inventory (uimenus step 12): the screen dim with a spotlight
## hole, the instruction card with its progress line, SKIP LESSON and END TUTORIAL (always reachable), banner
## mode, the soft input mask (outside the hole absorbs clicks, inside falls through), a spotlight rect that can
## move every frame, hide_overlay. The overlay contract must survive any restyle: there is NO Next button — steps
## advance on real game signals only. test_inventory_check_names_a_removed_control proves the presence check can fail.

var _mark: TutorialCoachMark
var _skips := 0
var _ends := 0


func before_test() -> void:
	_skips = 0
	_ends = 0
	_mark = TutorialCoachMark.new()
	add_child(_mark)
	_mark.skip_lesson_pressed.connect(func() -> void: _skips += 1)
	_mark.end_pressed.connect(func() -> void: _ends += 1)
	await get_tree().process_frame


func after_test() -> void:
	_mark.queue_free()


func _button(text: String) -> Button:
	for n: Node in _mark.find_children("*", "Button", true, false):
		if (n as Button).text == text:
			return n as Button
	return null


func _missing() -> Array:
	var missing: Array = []
	for t: String in ["SKIP LESSON", "END TUTORIAL"]:
		if _button(t) == null:
			missing.append("button: %s" % t)
	if _mark._dim == null:
		missing.append("node: dim layer")
	if _mark._card == null or _mark._label == null or _mark._progress_label == null:
		missing.append("node: instruction card")
	return missing


func test_every_control_is_present_and_there_is_no_next_button() -> void:
	assert_array(_missing()).override_failure_message("coach mark controls missing: %s" % str(_missing())).is_empty()
	for n: Node in _mark.find_children("*", "Button", true, false):
		var t := (n as Button).text.to_upper()
		assert_bool(t.contains("NEXT") or t.contains("CONTINUE")).override_failure_message("a Next button must never exist: %s" % t).is_false()
	assert_int(_mark.layer).is_equal(128)


func test_spotlight_step_shows_text_progress_dim_and_masks_outside_the_hole() -> void:
	_mark.set_progress_text("LESSON 2/6 · IMPORTING ARMIES — STEP 1/3")
	_mark.show_step("Click Import.", Rect2(400, 300, 100, 60), true)
	await get_tree().process_frame
	assert_str(_mark._label.text).is_equal("Click Import.")
	assert_str(_mark._progress_label.text).is_equal("LESSON 2/6 · IMPORTING ARMIES — STEP 1/3")
	assert_bool(_mark._progress_label.visible).is_true()
	assert_bool(_mark._dim.visible).is_true()
	assert_int(_mark._dim.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	assert_bool(_mark._dim._has_point(Vector2(450, 330))).override_failure_message("the hole must let clicks through").is_false()
	assert_bool(_mark._dim._has_point(Vector2(10, 10))).override_failure_message("outside the hole must absorb clicks").is_true()


func test_unmasked_step_ignores_the_mouse() -> void:
	_mark.show_step("Drag a model.", Rect2(400, 300, 100, 60), false)
	assert_int(_mark._dim.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_banner_mode_is_the_card_only_without_dim_or_spotlight() -> void:
	_mark.show_banner("Orbit the camera.")
	await get_tree().process_frame
	assert_str(_mark._label.text).is_equal("Orbit the camera.")
	assert_bool(_mark._dim.visible).is_false()
	assert_bool(_mark._has_target).is_false()
	assert_bool(_mark.visible).is_true()
	assert_bool(_button("SKIP LESSON").is_visible_in_tree()).is_true()
	assert_bool(_button("END TUTORIAL").is_visible_in_tree()).is_true()


func test_progress_line_hides_when_empty() -> void:
	_mark.set_progress_text("x")
	_mark.set_progress_text("")
	assert_bool(_mark._progress_label.visible).is_false()


func test_the_spotlight_rect_follows_a_moving_target() -> void:
	_mark.show_step("Watch.", Rect2(100, 100, 50, 50), true)
	var first: Rect2 = _mark._target_rect
	_mark.set_target_rect(Rect2(300, 200, 50, 50))
	assert_bool(_mark._target_rect.position != first.position).is_true()
	assert_float(_mark._target_rect.get_center().x).is_equal_approx(325.0, 0.01)


func test_skip_lesson_and_end_tutorial_emit_and_stay_reachable_while_masked() -> void:
	_mark.show_step("Click Import.", Rect2(400, 300, 100, 60), true)
	await get_tree().process_frame
	assert_int(_button("SKIP LESSON").mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	_button("SKIP LESSON").pressed.emit()
	_button("END TUTORIAL").pressed.emit()
	assert_int(_skips).is_equal(1)
	assert_int(_ends).is_equal(1)


func test_hide_overlay_hides_and_stops_processing() -> void:
	_mark.show_banner("x")
	_mark.hide_overlay()
	assert_bool(_mark.visible).is_false()
	assert_bool(_mark.is_processing()).is_false()


func test_inventory_check_names_a_removed_control() -> void:
	assert_array(_missing()).is_empty()
	var end := _button("END TUTORIAL")
	var parent := end.get_parent()
	parent.remove_child(end)
	var missing := _missing()
	parent.add_child(end)
	assert_array(missing).contains_exactly(["button: END TUTORIAL"])
