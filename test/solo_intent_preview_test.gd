extends GdUnitTestSuite
## Automodus 0.3.15 step 1.1: the executor preview guard. While _preview_depth > 0 the one executor
## (execute_intent) must not broadcast a move batch and must not append a decision record.

const IN2M := 0.0254


class FakeNet extends Node:
	var batches := 0

	func is_multiplayer_active() -> bool:
		return true

	func broadcast_move_batch(_batch: Array) -> void:
		batches += 1


func before_test() -> void:
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func _unit(pid: int, unit_name: String, positions: Array) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name.to_lower().replace(" ", "_")
	unit.unit_properties = {"player_id": pid, "name": unit_name, "quality": 4, "defense": 4,
		"special_rules": []}
	for position in positions:
		var model := ModelInstance.new()
		model.is_alive = true
		model.unit = unit
		var node := Node3D.new()
		add_child(node)
		node.set_meta("network_id", 7)
		node.global_position = position
		model.node = node
		unit.models.append(model)
	return unit


func _rig(net: Node) -> Array:
	var attacker := _unit(2, "Attacker", [Vector3.ZERO])
	var enemy := _unit(1, "Foe", [Vector3(20 * IN2M, 0, 0)])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units[attacker.unit_id] = attacker
	army.game_units[enemy.unit_id] = enemy
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, net, null, 1, 2)
	return [solo, attacker, enemy]


func test_a_preview_depth_execution_broadcasts_and_records_nothing() -> void:
	var net: FakeNet = auto_free(FakeNet.new())
	add_child(net)
	var rig := _rig(net)
	var solo: SoloController = rig[0]
	var before := solo.decision_log.size()
	solo._preview_depth = 1
	var intent := solo.player_intent(rig[1], AiDecision.Action.RUSH, rig[2])
	solo.execute_intent(intent, ActIntent.blank_report(rig[1]))
	assert_int(net.batches).is_equal(0)
	assert_int(solo.decision_log.size()).is_equal(before)


func test_depth_zero_execution_still_broadcasts_once() -> void:
	var net: FakeNet = auto_free(FakeNet.new())
	add_child(net)
	var rig := _rig(net)
	var solo: SoloController = rig[0]
	var intent := solo.player_intent(rig[1], AiDecision.Action.RUSH, rig[2])
	solo.execute_intent(intent, ActIntent.blank_report(rig[1]))
	assert_int(net.batches).is_equal(1)
