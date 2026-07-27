extends GdUnitTestSuite
## 023/URGENT-024: the D6 root cause was a click over the dock UI falling through to the 3D selection
## pipeline, which deselected the unit, hid the card, and nulled the action target. The first fix
## over-blocked (a full-rect STOP HUD root occluded EVERY click → nothing selectable).
##
## Both halves are still pinned — but the mechanism changed. The dock used to be protected by two
## hand-rolled guards, object_manager._control_blocks_world_click() and UnitDock.occludes_point();
## both are deleted. World picking now runs in _unhandled_input, which the engine reaches only after
## the GUI has had the event, so the dock is protected iff it obeys the click-ownership invariant:
##   interactive surface → STOP at its own root   (tab, strip panel, cards: they own their clicks)
##   transparent holder  → IGNORE                 (the full-rect dock root, the fan holder)
## Break either half and the old bug is back: a STOP holder makes the table unselectable, an
## un-owned surface lets clicks fall through and deselect the unit under the card.
## The HUD-wide half of the same invariant lives in test/ui_click_ownership_test.gd.


func _dock() -> UnitDock:
	var dock: UnitDock = auto_free(UnitDock.new())
	add_child(dock)
	return dock


func test_dock_holders_are_ignore_so_the_table_behind_them_stays_clickable() -> void:
	var dock := _dock()
	await get_tree().process_frame
	# The dock root is PRESET_FULL_RECT: as a STOP control it would occlude the entire table.
	assert_int(dock.mouse_filter) \
		.override_failure_message("the full-rect UnitDock root must be IGNORE, or it swallows every world click (URGENT-024)") \
		.is_equal(Control.MOUSE_FILTER_IGNORE)
	# The fan holder is a bare Control behind the cards; the cards themselves own their clicks.
	assert_object(dock._strip).is_not_null()
	assert_int(dock._strip.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_dock_surfaces_are_stop_so_clicks_on_them_never_reach_the_world() -> void:
	var dock := _dock()
	await get_tree().process_frame
	assert_object(dock._tab).is_not_null()
	assert_int(dock._tab.mouse_filter) \
		.override_failure_message("the dock tab must be STOP or a click on it also picks/deselects on the table") \
		.is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(dock._strip_panel).is_not_null()
	assert_int(dock._strip_panel.mouse_filter) \
		.override_failure_message("the strip panel must be STOP — it is the surface the fan cards sit on, and it must keep owning clicks while it tweens closed") \
		.is_equal(Control.MOUSE_FILTER_STOP)
	assert_object(dock._presented).is_not_null()
	assert_int(dock._presented.mouse_filter) \
		.override_failure_message("the presented card must be STOP or clicking it deselects the unit and the card vanishes (the D6 bug)") \
		.is_equal(Control.MOUSE_FILTER_STOP)
