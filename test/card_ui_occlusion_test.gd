extends GdUnitTestSuite
## 023/URGENT-024: the D6 root cause was a click over the dock UI falling through to the 3D selection
## pipeline, which deselected the unit, hid the card, and nulled the action target. The first fix
## over-blocked (a full-rect STOP HUD root occluded EVERY click → nothing selectable). These pin BOTH
## halves of the occlusion decision: a genuine HUD widget (small STOP control) occludes, but a
## transparent full-viewport STOP container does NOT — so field clicks over the open scene still select.


func _mk(mouse_filter: int, s: Vector2) -> Control:
	var c: Control = auto_free(Control.new())
	c.mouse_filter = mouse_filter
	c.size = s
	add_child(c)
	return c


func test_widget_occludes_but_fullrect_container_ignore_pass_and_null_do_not() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var widget := _mk(Control.MOUSE_FILTER_STOP, Vector2(120, 60))       # dock card / chip / panel
	var container := _mk(Control.MOUSE_FILTER_STOP, vp)                  # transparent HUD root
	var ignore_ctrl := _mk(Control.MOUSE_FILTER_IGNORE, Vector2(120, 60))
	var pass_ctrl := _mk(Control.MOUSE_FILTER_PASS, Vector2(120, 60))
	await get_tree().process_frame

	assert_bool(om._control_blocks_world_click(widget)).is_true()
	# Inverse regression (URGENT-024): a full-viewport container must NOT occlude — field clicks work.
	assert_bool(om._control_blocks_world_click(container)).is_false()
	assert_bool(om._control_blocks_world_click(ignore_ctrl)).is_false()
	assert_bool(om._control_blocks_world_click(pass_ctrl)).is_false()
	assert_bool(om._control_blocks_world_click(null)).is_false()


func test_presented_card_is_a_stop_widget_so_clicks_on_it_are_occluded() -> void:
	var dock: UnitDock = auto_free(UnitDock.new())
	add_child(dock)
	await get_tree().process_frame
	assert_object(dock._presented).is_not_null()
	assert_int(dock._presented.mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)
	# The card is smaller than the viewport → a genuine widget → occludes (no fall-through deselect).
	var om: ObjectManager = auto_free(ObjectManager.new())
	assert_bool(om._control_blocks_world_click(dock._presented)).is_true()
