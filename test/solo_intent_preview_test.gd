extends GdUnitTestSuite
## Automodus 0.3.15 step 1.1: the executor preview guard. While _preview_depth > 0 the one executor
## (execute_intent) must not broadcast a move batch and must not append a decision record.
## Step 1.2: preview_intent runs that executor in a sandbox and lands where the real execution lands.

const IN2M := 0.0254


class FakeNet extends Node:
	var batches := 0
	var activations := 0
	var casts := 0

	func is_multiplayer_active() -> bool:
		return true

	func broadcast_move_batch(_batch: Array) -> void:
		batches += 1

	func broadcast_unit_activation(_unit: GameUnit) -> void:
		activations += 1

	func broadcast_unit_casts(_unit: GameUnit) -> void:
		casts += 1


## Stands in for a caster's cast plan: the real one spends tokens and broadcasts them (_plan_member_cast).
class CastingSolo extends SoloController:
	func _plan_casts(unit: GameUnit, _report: Dictionary = {}) -> Array:
		_broadcast_casts(unit)
		return []


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


func _rig(net: Node, enemy_in := 20.0, models := 1, solo: SoloController = null) -> Array:
	var spots: Array = []
	for i in models:
		spots.append(Vector3(0, 0, (i - (models - 1) / 2.0) * 1.5 * IN2M))
	var attacker := _unit(2, "Attacker", spots)
	var enemy := _unit(1, "Foe", [Vector3(enemy_in * IN2M, 0, 0)])
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units[attacker.unit_id] = attacker
	army.game_units[enemy.unit_id] = enemy
	army.current_round = 1
	if solo == null:
		solo = auto_free(SoloController.new())
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


func _spots(unit: GameUnit) -> Array:
	return unit.models.map(func(m: ModelInstance) -> Vector3: return m.node.global_position)


func _landing(preview: Dictionary) -> Array:
	return preview["landing"].map(func(spot: Dictionary) -> Vector3: return spot["pos"])


func test_preview_lands_where_the_execution_lands() -> void:
	for row in [[AiDecision.Action.CHARGE, 8.0], [AiDecision.Action.ADVANCE, 20.0], [AiDecision.Action.RUSH, 20.0]]:
		var net: FakeNet = auto_free(FakeNet.new())
		add_child(net)
		var rig := _rig(net, row[1], 3)
		var solo: SoloController = rig[0]
		var unit: GameUnit = rig[1]
		var intent := solo.player_intent(unit, row[0], rig[2])
		solo.last_move_paths = [{"sentinel": true}]
		solo._sidestep_budget = 1
		var start := _spots(unit)
		var log_size := solo.decision_log.size()
		var preview: Dictionary = solo.preview_intent(intent, func(_r: Dictionary) -> Array: return _spots(unit))
		var landing := _landing(preview)
		# (a) nothing the preview touched stays touched, nothing left the machine
		assert_array(_spots(unit)).is_equal(start)
		assert_int(solo.decision_log.size()).is_equal(log_size)
		assert_array(solo.last_move_paths).is_equal([{"sentinel": true}])
		assert_int(solo._sidestep_budget).is_equal(1)
		assert_int(net.batches + net.activations + net.casts).is_equal(0)
		assert_array(preview["lines"]).is_equal(landing)   # the probe saw the models at their landing
		assert_float(landing[1].distance_to(start[1])).is_greater(1.0 * IN2M)   # it really moved
		assert_array(_landing(solo.preview_intent(intent))).is_equal(landing)   # a second preview: identical
		# (b) the real execution (plus main's charge snap) lands on the preview
		solo.execute_intent(intent, ActIntent.blank_report(unit))
		var gap: float = solo.nearest_melee_gap_in(unit, rig[2])
		if row[0] == AiDecision.Action.CHARGE and gap <= SoloController.MELEE_ENGAGE_IN:
			solo.snap_charge(unit, rig[2])
		var verb := AiDecision.action_name(row[0])
		for i in landing.size():
			var off: float = _spots(unit)[i].distance_to(landing[i])
			assert_float(off).override_failure_message("%s model %d off by %f m" % [verb, i, off]).is_less_equal(1e-4)


func test_a_preview_never_plans_casts_or_broadcasts() -> void:
	var net: FakeNet = auto_free(FakeNet.new())
	add_child(net)
	var rig := _rig(net, 20.0, 1, auto_free(CastingSolo.new()))
	var solo: SoloController = rig[0]
	var intent := solo.player_intent(rig[1], AiDecision.Action.RUSH, rig[2])
	intent["source"] = "ai"   # an AI intent plans its casts after the move; a player intent never does
	solo.preview_intent(intent)
	assert_int(net.batches + net.activations + net.casts).is_equal(0)
	solo.execute_intent(intent, ActIntent.blank_report(rig[1]))
	assert_int(net.casts).is_equal(1)   # control: the real execution does reach the cast seam
