extends GdUnitTestSuite
## NML-1020 — Immobile/Artillery may only Hold (GF v3.5.1 p.13 / solo p.57).
## The parity workflow's adversarial trace caught the real-table bug: the
## planner/clone hook adopted plans OVER the tree's hold override. Two halves:
## the LAB menu never offers a carrier a move, and (game half, covered by the
## re-gate in solo_controller) an adopted plan collapses back to Hold.

const IN2M := 0.0254


func _unit(id: String, pid: int, n: int, rules: Array) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": pid, "name": id, "quality": 4, "defense": 4,
		"special_rules": rules}
	var od := OPRApiClient.OPRUnit.new()
	var w := OPRApiClient.OPRWeapon.new()
	w.name = "Cannon"
	w.range_value = 24
	w.attacks = 2
	od.weapons = [w] as Array[OPRApiClient.OPRWeapon]
	u.source_type = "opr"
	u.source_data = od
	for i in range(n):
		var m: ModelInstance = ModelInstance.new()
		m.unit = u
		m.is_alive = true
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		m.node.global_position = Vector3(float(i) * IN2M, 0, 0)
		u.models.append(m)
	return u


func _state_with(rules: Array) -> Dictionary:
	var gun := _unit("Gun", 1, 2, rules)
	var foe := _unit("Foe", 2, 2, [])
	for i in range(2):
		(foe.models[i] as ModelInstance).node.global_position = Vector3(float(i) * IN2M, 0, 10.0 * IN2M)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Gun": gun, "Foe": foe}
	return BattleSim.capture(army, func() -> Array: return [Vector3(0, 0, 5.0 * IN2M)],
		func(_i: int) -> int: return 0, 1, 4)


func _kinds(menu: Array) -> Dictionary:
	var out := {}
	for c in menu:
		out[int((c as Dictionary).get("kind", -1))] = true
	return out


func test_immobile_menu_is_hold_only_in_both_builders() -> void:
	for rules in [["Immobile"], ["Artillery"]]:
		var state := _state_with(rules)
		for menu in [AiPlanner.candidates(state, "Gun"), AiPlanner.candidates_wide(state, "Gun")]:
			var kinds := _kinds(menu)
			assert_bool(kinds.has(AiDecision.Action.HOLD)).is_true()
			assert_bool(kinds.has(AiDecision.Action.RUSH)) \
				.override_failure_message("a %s carrier was offered a MOVE (%s)" % [rules[0], str(menu)]) \
				.is_false()
			assert_bool(kinds.has(AiDecision.Action.CHARGE)).is_false()
			assert_bool(kinds.has(AiDecision.Action.ADVANCE)).is_false()


func test_mobile_unit_menu_still_offers_moves() -> void:
	var state := _state_with([])
	var kinds := _kinds(AiPlanner.candidates(state, "Gun"))
	assert_bool(kinds.has(AiDecision.Action.RUSH)).is_true()
