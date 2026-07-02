extends GdUnitTestSuite
## 014: localize the D6 "presented-card buttons do nothing" bug HEADLESSLY via LAYOUT inspection (rects
## + mouse_filter + tree order all compute without rendering; only actual GUI input simulation needs a
## real display, which this deliberately avoids — raw Viewport.push_input does not drive the gui pipeline
## headlessly). It asserts the click-REACHABILITY of every action button: each is inside the presented
## card, the card is on-screen and not overflowing, and no FOREIGN control covers the button. If a real
## overlay/overflow regression is introduced, this fails and names the covering control.


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
	dock.present_unit(unit)
	dock._presented.visible = true
	dock._presented.position = dock._presented_rest_pos()
	dock._presented.scale = Vector2.ONE
	dock._presented.rotation = 0.0
	dock._presented.modulate.a = 1.0


## Foreign controls (outside the dock subtree) that cover `point`, visible + not IGNORE — a real
## click-swallower would show up here.
func _foreign_covers(dock: UnitDock, point: Vector2) -> Array:
	var out: Array = []
	for c in get_tree().root.find_children("*", "Control", true, false):
		var ctrl := c as Control
		if ctrl == null or dock.is_ancestor_of(ctrl) or ctrl == dock:
			continue
		if ctrl.is_visible_in_tree() and ctrl.mouse_filter == Control.MOUSE_FILTER_STOP \
				and ctrl.get_global_rect().has_point(point):
			out.append("%s(%s)" % [ctrl.name, ctrl.get_class()])
	return out


func test_action_buttons_are_reachable_not_swallowed_or_overflowing() -> void:
	var dock: UnitDock = auto_free(UnitDock.new())
	add_child(dock)
	dock.size = get_viewport().get_visible_rect().size
	dock._layout()
	_present(dock, _mk_unit())
	await get_tree().process_frame
	await get_tree().process_frame

	var card_rect: Rect2 = dock._presented.get_global_rect()
	var view_rect := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	# The card must be fully on-screen and not have ballooned past its fixed size (overflow bug).
	assert_bool(view_rect.encloses(card_rect)).is_true()
	assert_vector(dock._presented.size).is_equal(Vector2(dock.PCARD_W, dock.PCARD_H))

	for i in range(dock._p_actions.get_child_count()):
		var btn := dock._p_actions.get_child(i) as Button
		if btn == null or not btn.visible:
			continue
		var brect: Rect2 = btn.get_global_rect()
		var center: Vector2 = brect.get_center()
		# Each button sits INSIDE the card (no content overflow pushing it off the face)…
		assert_bool(card_rect.encloses(brect)) \
			.override_failure_message("button %d '%s' rect %s escapes the card %s" % [i, btn.text, brect, card_rect]) \
			.is_true()
		# …and NO foreign control (an external HUD overlay) covers its centre.
		var foreign := _foreign_covers(dock, center)
		assert_array(foreign) \
			.override_failure_message("button %d '%s' centre %s is covered by foreign control(s): %s" % [i, btn.text, center, foreign]) \
			.is_empty()
