extends GdUnitTestSuite
## A controller must be able to confirm and go back in the menu: ui_accept and ui_cancel keep their keys
## and gain the two face buttons (A confirms, B goes back). RED on main: both lacked a joypad event.


func _has_joypad_button(action: StringName, button: JoyButton) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button:
			return true
	return false


func _has_key(action: StringName, key: Key) -> bool:
	for event: InputEvent in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).keycode == key:
			return true
	return false


func test_a_face_button_confirms() -> void:
	assert_bool(_has_joypad_button(&"ui_accept", JOY_BUTTON_A)).is_true()


func test_b_face_button_goes_back() -> void:
	assert_bool(_has_joypad_button(&"ui_cancel", JOY_BUTTON_B)).is_true()


func test_the_keys_are_kept() -> void:
	for key: Key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		assert_bool(_has_key(&"ui_accept", key)).override_failure_message("ui_accept lost key %d" % key).is_true()
	assert_bool(_has_key(&"ui_cancel", KEY_ESCAPE)).is_true()
