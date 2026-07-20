extends GdUnitTestSuite
## Regression (maintainer screenshot 2026-07-20): rebuild() queue_freed the old strip cards but
## laid the fan out in the SAME frame — the still-attached corpses doubled the counted card set,
## so the panel came out double-wide with the real cards bunched in its right half. rebuild()
## must detach before freeing, and _layout_fan must only count live CardVisuals: the layout has
## to be IDEMPOTENT across repeated same-frame rebuilds.


func _unit(unit_name: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = unit_name
	u.unit_properties = {"name": unit_name, "cost": 100, "quality": 4, "defense": 4}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models = [m]
	return u


func _dock_with_units(names: Array) -> UnitDock:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	for n in names:
		var u := _unit(str(n))
		army.game_units[u.unit_id] = u
	var dock: UnitDock = auto_free(UnitDock.new())
	add_child(dock)
	dock.setup(army, null, null, null, null)
	return dock


func _live_cards(dock: UnitDock) -> Array:
	var live: Array = []
	for child in dock._strip.get_children():
		if child is CardVisual and not child.is_queued_for_deletion():
			live.append(child)
	return live


func test_repeated_rebuild_keeps_card_count_and_panel_width() -> void:
	var dock := _dock_with_units(["Alpha", "Bravo", "Charlie"])
	var w_first: float = dock._strip_panel.size.x
	assert_int(_live_cards(dock).size()).is_equal(3)
	# Second + third rebuild in the SAME frame (the bug's trigger): layout must not count the
	# just-freed corpses — width and live-card count stay exactly those of the first build.
	dock.rebuild()
	dock.rebuild()
	assert_int(_live_cards(dock).size()).is_equal(3)
	assert_float(dock._strip_panel.size.x).is_equal_approx(w_first, 0.5)


func test_fan_slots_start_at_the_left_margin_after_rebuild() -> void:
	var dock := _dock_with_units(["Alpha", "Bravo"])
	dock.rebuild()
	# The first LIVE card's spring target must sit at the strip's left margin — a consumed
	# corpse slot would leave a hole there (the screenshot's empty left half).
	var first: CardVisual = _live_cards(dock)[0]
	assert_float(first._target_pos.x).is_equal_approx(float(UnitDock.STRIP_SIDE_MARGIN), 0.5)


## Regression #2 (same screenshot): the rules rows are HFlowContainers — measured synchronously
## they claim ONE row, so a rule-heavy unit's card was sized too short and the wrapped rows
## painted past the card's bottom edge. After the deferred refit the card must be at least as
## tall as its content's true (laid-out) minimum height, up to the strip cap.
func test_card_grows_to_wrapped_rules_after_layout() -> void:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var u := _unit("Rulesy")
	u.unit_properties["special_rules"] = ["Ambush", "Tough(3)", "Battleborn", "Fearless",
		"Combat Shield", "Relentless", "Versatile Attack", "Shield Wall", "Counter", "Slow"]
	army.game_units[u.unit_id] = u
	var dock: UnitDock = auto_free(UnitDock.new())
	add_child(dock)
	dock.setup(army, null, null, null, null)
	# Let layout + the deferred refit run (two frames in the refit + one for the fan).
	for _i in range(4):
		await get_tree().process_frame
	var cv: CardVisual = _live_cards(dock)[0]
	var needed: float = minf(cv.content_min_height(), 240.0)
	assert_float(cv.size.y).is_greater_equal(needed - 0.5)
	# And the content really wraps (the test would be vacuous if one row fit): the needed
	# height must exceed the static minimum the old synchronous measure settled at.
	assert_float(needed).is_greater(float(UnitDock.STRIP_CARD_H))
