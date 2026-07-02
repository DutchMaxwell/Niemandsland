extends GdUnitTestSuite
## D6: the presented-card action buttons must dispatch to the radial controller's card_* API — the same
## thing the radial menu does. This guards the ROUTING in UnitDock._card_action against silent
## regressions (Handover A shipped the buttons "routed but not playtested"). The click-REACHING layer is
## visual and is covered by the new per-action debug log + the maintainer's QA, not here.


class MockController:
	extends Node
	var calls: Array = []
	func card_toggle_activation(_u: Variant) -> void: calls.append("activation")
	func card_toggle_fatigued(_u: Variant) -> void: calls.append("fatigued")
	func card_toggle_shaken(_u: Variant) -> void: calls.append("shaken")
	func card_open_casts(_u: Variant) -> void: calls.append("casts")
	func card_open_wounds(_u: Variant) -> void: calls.append("wounds")
	func card_revive(_u: Variant) -> void: calls.append("revive")


func _mk_unit() -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "t1"
	u.unit_properties = {"name": "Test", "player_id": 1, "quality": 4, "defense": 3}
	var m := ModelInstance.new()
	m.is_alive = true
	u.models.append(m)
	return u


func test_card_action_routes_each_button_to_the_controller() -> void:
	var dock: UnitDock = auto_free(UnitDock.new())
	add_child(dock)                       # _ready builds the labels + action buttons
	var mock: MockController = auto_free(MockController.new())
	dock.set_radial_controller(mock)
	dock._presented_unit = _mk_unit()
	for kind in ["activation", "fatigued", "shaken", "wounds", "revive"]:
		dock._card_action(kind)
	assert_array(mock.calls).is_equal(["activation", "fatigued", "shaken", "wounds", "revive"])


func test_card_action_survives_a_null_controller() -> void:
	# The never-wired / dropped case: it lazily resolves (no "Main" in the test tree → warns + drops),
	# and must never crash.
	var dock: UnitDock = auto_free(UnitDock.new())
	add_child(dock)
	dock.set_radial_controller(null)
	dock._presented_unit = _mk_unit()
	dock._card_action("activation")
	assert_bool(true).is_true()
