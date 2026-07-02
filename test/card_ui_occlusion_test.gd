extends GdUnitTestSuite
## 023: the D6 root cause was a click over the dock UI falling through to the 3D selection pipeline,
## which deselected the unit, hid the card, and nulled the action target. These pin the UI-occlusion
## DECISION (ObjectManager blocks the world-click when the hovered control is a STOP HUD control) and
## that the presented card is such a STOP control, so a click on it is occluded (no fall-through
## deselect). Actual gui_get_hovered_control routing needs a display and stays out of scope.


func test_stop_control_blocks_world_click_null_and_ignore_do_not() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	var stop_ctrl: Control = auto_free(Control.new())
	stop_ctrl.mouse_filter = Control.MOUSE_FILTER_STOP
	var ignore_ctrl: Control = auto_free(Control.new())
	ignore_ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pass_ctrl: Control = auto_free(Control.new())
	pass_ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	assert_bool(om._control_blocks_world_click(stop_ctrl)).is_true()
	assert_bool(om._control_blocks_world_click(ignore_ctrl)).is_false()
	assert_bool(om._control_blocks_world_click(pass_ctrl)).is_false()
	assert_bool(om._control_blocks_world_click(null)).is_false()


func test_presented_card_is_a_stop_control_so_clicks_on_it_are_occluded() -> void:
	var dock: UnitDock = auto_free(UnitDock.new())
	add_child(dock)
	await get_tree().process_frame
	assert_object(dock._presented).is_not_null()
	# A STOP presented card is exactly what _control_blocks_world_click keys on → no fall-through deselect.
	assert_int(dock._presented.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	var om: ObjectManager = auto_free(ObjectManager.new())
	assert_bool(om._control_blocks_world_click(dock._presented)).is_true()
