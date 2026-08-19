extends GdUnitTestSuite
## #338 — the round-over check must WAIT on embarked human cargo. Passengers are
## deliberately not in the eligible pool (nothing may auto-activate them), so the
## predicate human_cargo_pending() is the round's memory that a choice is still
## owed: disembark, or "Stay aboard" (which spends the activation inside).


var _mgr: OPRArmyManager
var _solo: SoloController


func before_test() -> void:
	_mgr = auto_free(OPRArmyManager.new())
	_solo = auto_free(SoloController.new())
	_solo.army_manager = _mgr
	_solo.human_slot = 1
	_solo.ai_slot = 2


func _unit(id: String, n: int, rules: Array, pid: int = 1) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": pid, "special_rules": rules, "name": id}
	for i in range(n):
		var m: ModelInstance = ModelInstance.new()
		m.unit = u
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		u.models.append(m)
	_mgr.game_units[id] = u
	return u


func test_pending_lists_embarked_cargo_and_clears_when_spent() -> void:
	var apc := _unit("apc", 1, ["Transport(6)"])
	var squad := _unit("squad", 3, [])
	assert_bool(_mgr.set_unit_embarked(squad, apc, true)).is_true()
	# The passenger is pending — and exactly it, not the transport.
	var pending: Array = _solo.human_cargo_pending()
	assert_int(pending.size()).is_equal(1)
	assert_object(pending[0]).is_same(squad)
	# It must NOT be auto-activatable: is_eligible stays false for human cargo.
	assert_bool(_solo.is_eligible(squad)).is_false()
	# "Stay aboard" (or any activation spend) clears the debt — the round may close.
	squad.is_activated = true
	assert_bool(_solo.human_cargo_pending().is_empty()).is_true()


func test_pending_ignores_ai_cargo_disembarked_and_reserve_transports() -> void:
	var apc := _unit("apc", 1, ["Transport(6)"])
	var squad := _unit("squad", 3, [])
	assert_bool(_mgr.set_unit_embarked(squad, apc, true)).is_true()
	# AI-owned cargo is the AI's own bookkeeping (#230) — never in the human debt.
	squad.unit_properties["player_id"] = 2
	assert_bool(_solo.human_cargo_pending().is_empty()).is_true()
	squad.unit_properties["player_id"] = 1
	# A transport still in Ambush reserve is off the table WITH its cargo (TC-081).
	apc.unit_properties["ambush_reserve"] = true
	assert_bool(_solo.human_cargo_pending().is_empty()).is_true()
	apc.unit_properties["ambush_reserve"] = false
	# Disembarked = no transport_of = no debt.
	assert_bool(_mgr.set_unit_embarked(squad, null, false)).is_true()
	assert_bool(_solo.human_cargo_pending().is_empty()).is_true()


func test_embarked_radial_offers_the_stay_choice() -> void:
	var items: Array = RadialMenu.create_embarked_model_menu("APC")
	var ids: Array = []
	for it in items:
		ids.append(it.id)
	assert_bool(ids.has("disembark")).is_true()
	assert_bool(ids.has("stay_embarked")).is_true()
