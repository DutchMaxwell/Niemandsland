extends GdUnitTestSuite
## D6/D8: headless reachability net for the presented card's action chips. Control rects + mouse_filter
## + tree order compute WITHOUT rendering, so this localizes the "buttons do nothing" class of bug on
## the live CardFace-on-CardVisual card: every CardFace action chip is inside the presented card, the
## card is on-screen, and no FOREIGN control covers a chip. (Actual GUI input delivery needs a display;
## raw push_input does not drive the gui pipeline headlessly, so that stays out of scope here.)


func _mk_unit() -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "t1"
	u.unit_properties = {"name": "Test", "player_id": 1, "quality": 4, "defense": 3}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func _present(dock: UnitDock, unit: GameUnit) -> void:
	dock._presented_unit = unit
	dock._fill_presented(unit)   # builds the CardFace content + sizes the card
	dock._presented.visible = true
	dock._presented.snap_to(dock._presented_rest_pos(), 0.0, 1.0)


## Foreign controls (outside the presented card) that cover `point`, visible + STOP — a real swallower.
func _foreign_covers(dock: UnitDock, point: Vector2) -> Array:
	var out: Array = []
	for c in get_tree().root.find_children("*", "Control", true, false):
		var ctrl := c as Control
		if ctrl == null or dock._presented.is_ancestor_of(ctrl) or ctrl == dock._presented:
			continue
		if ctrl.is_visible_in_tree() and ctrl.mouse_filter == Control.MOUSE_FILTER_STOP \
				and ctrl.get_global_rect().has_point(point):
			out.append("%s(%s)" % [ctrl.name, ctrl.get_class()])
	return out


func test_action_chips_are_reachable_not_swallowed() -> void:
	var dock: UnitDock = auto_free(UnitDock.new())
	add_child(dock)
	dock.size = get_viewport().get_visible_rect().size
	dock._layout()
	_present(dock, _mk_unit())
	await get_tree().process_frame
	await get_tree().process_frame

	var card_rect: Rect2 = dock._presented.get_global_rect()
	var view_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	assert_bool(view_rect.encloses(card_rect)).is_true()

	var buttons: Array = dock._presented.find_children("*", "Button", true, false)
	assert_int(buttons.size()).override_failure_message("no CardFace action chips found in the card").is_greater(0)
	for b in buttons:
		var btn := b as Button
		if btn == null or not btn.is_visible_in_tree():
			continue
		var brect: Rect2 = btn.get_global_rect()
		var center: Vector2 = brect.get_center()
		assert_bool(card_rect.grow(1.0).encloses(brect)) \
			.override_failure_message("chip '%s' rect %s escapes the card %s" % [btn.text, brect, card_rect]) \
			.is_true()
		var foreign := _foreign_covers(dock, center)
		assert_array(foreign) \
			.override_failure_message("chip '%s' centre %s covered by foreign control(s): %s" % [btn.text, center, foreign]) \
			.is_empty()
