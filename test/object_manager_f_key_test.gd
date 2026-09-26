extends GdUnitTestSuite


## Regiment frontage moved to B (uitop Job A), so Shift+F is the fan's clear-all again.
func test_shift_f_clears_every_sight_fan() -> void:
	var manager: ObjectManager = auto_free(ObjectManager.new())
	add_child(manager)
	var calls: Array = []
	manager.sight_fan_toggle = func(nodes: Array, clear_all: bool) -> void:
		calls.append([nodes, clear_all])
	var event := InputEventKey.new()
	event.keycode = KEY_F
	event.pressed = true
	event.shift_pressed = true
	manager._unhandled_input(event)
	assert_array(calls).is_equal([[[], true]])


func test_plain_f_still_reaches_the_sight_fan() -> void:
	var manager: ObjectManager = auto_free(ObjectManager.new())
	add_child(manager)
	var calls: Array = []
	manager.sight_fan_toggle = func(_nodes: Array, clear_all: bool) -> void:
		calls.append(clear_all)
	var event := InputEventKey.new()
	event.keycode = KEY_F
	event.pressed = true
	manager._unhandled_input(event)
	assert_int(calls.size()).is_equal(1)
	assert_bool(calls[0]).is_false()
