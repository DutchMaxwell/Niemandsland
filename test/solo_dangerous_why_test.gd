extends GdUnitTestSuite
## rules-must-log: the move record that reports dangerous_models also names WHY avoidance was off or did
## not hold (data.dangerous_why). Logging only — no behaviour change.

const IN2M := 0.0254

var _mgr: OPRArmyManager
var _solo: SoloController
var _epoch0: int


func before_test() -> void:
	_epoch0 = AiActRecorder.rules_epoch
	_mgr = auto_free(OPRArmyManager.new())
	_solo = auto_free(SoloController.new())
	add_child(_solo)
	_solo.army_manager = _mgr
	_solo.human_slot = 1
	_solo.ai_slot = 2
	_set_strip(3.0, 5.0)


func after_test() -> void:
	AiActRecorder.rules_epoch = _epoch0   # statics leak across gdUnit tests - restore


func _set_strip(z0: float, z1: float, kind: int = TerrainRules.TerrainType.DANGEROUS) -> void:
	_solo.terrain_type_at = func(p: Vector3) -> int:
		var z_in := p.z / IN2M
		return kind if z_in >= z0 and z_in <= z1 else TerrainRules.TerrainType.NONE


func _unit(id: String, n: int, z_in: float = 0.0) -> GameUnit:
	var u: GameUnit = auto_free(GameUnit.new())
	u.unit_id = id
	u.unit_properties = {"player_id": 2, "special_rules": [], "name": id, "quality": 4, "defense": 4}
	for i in range(n):
		var m := ModelInstance.new()
		m.unit = u
		m.is_alive = true
		m.wounds_max = 1
		m.wounds_current = 1
		m.node = auto_free(Node3D.new())
		add_child(m.node)
		m.node.global_position = Vector3(float(i) * 1.5 * IN2M, 0, z_in * IN2M)
		u.models.append(m)
	_mgr.game_units[id] = u
	return u


func _why() -> String:
	var rec: Dictionary = _solo.decision_log.back() if not _solo.decision_log.is_empty() else {}
	return str((rec.get("data", {}) as Dictionary).get("dangerous_why", "<none>"))


func test_goal_inside_the_field_is_named() -> void:
	_set_strip(10.0, 16.0)
	var u := _unit("Walkers", 2)
	_solo._execute_move(u, Vector3(0, 0, 13.0 * IN2M), 12.0, false)
	assert_str(_why()).contains("goal inside DANGEROUS ground")


func test_standing_in_the_field_at_start_is_named() -> void:
	_set_strip(-1.0, 1.0)
	var u := _unit("Campers", 2)
	_solo._execute_move(u, Vector3(0, 0, 12.0 * IN2M), 6.0, false)
	assert_str(_why()).contains("stood in/at the field edge at start")


func test_stall_through_plan_is_named() -> void:
	var u := _unit("Pair", 2, 2.0)
	_solo._execute_move(u, Vector3(0, 0, 14.0 * IN2M), 12.0, false)
	assert_str(_why()).contains("stall through-plan (toll")


func _move_rec() -> Dictionary:
	for i in range(_solo.decision_log.size() - 1, -1, -1):
		var rec := _solo.decision_log[i] as Dictionary
		if str(rec.get("kind", "")) == "move" and str(rec.get("why", "")) != "band clamp":
			return rec
	return {}


## Rules 3.6: a move over 6" through a ruin takes the Dangerous test, so the ruin is routed around when a detour exists.
func test_long_move_routes_around_unstable_ruins() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_solo.terrain_type_at = func(p: Vector3) -> int:
		var z_in := p.z / IN2M
		var x_in := p.x / IN2M
		return TerrainRules.TerrainType.RUINS if z_in >= 1.0 and z_in <= 4.0 and x_in >= -2.0 and x_in <= 2.0 \
			else TerrainRules.TerrainType.NONE
	var u := _unit("Great Beast", 1)
	_solo._execute_move(u, Vector3(0, 0, 12.0 * IN2M), 12.0, false)
	var data := _move_rec().get("data", {}) as Dictionary
	assert_int(int(data.get("dangerous_models", -1))) \
		.override_failure_message("the long move crossed the unstable ruin instead of routing around it") \
		.is_equal(0)
	assert_float(float(data.get("achieved_in", 0.0))) \
		.override_failure_message("routing around the ruin stalled the move (%.2f\" of 12)" % float(data.get("achieved_in", 0.0))) \
		.is_greater(10.0)
	# rules-must-log: the applied avoid is named in the move record.
	assert_bool(bool(data.get("unstable_avoid", false))).is_true()
	assert_str(str(_move_rec().get("why", ""))).contains("unstable ruins")


## The avoid is a preference, not a wall: with no detour the stall escalation lifts it and the unit still moves.
func test_a_ruin_across_the_whole_lane_does_not_stall_the_move() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_set_strip(3.0, 5.0, TerrainRules.TerrainType.RUINS)
	_solo._execute_move(_unit("Pair", 2, 2.0), Vector3(0, 0, 14.0 * IN2M), 12.0, false)
	assert_float(float((_move_rec().get("data", {}) as Dictionary).get("achieved_in", 0.0))) \
		.override_failure_message("a ruin across the lane stalled the move: the through-plan could not lift the avoid") \
		.is_greater(10.0)


## A base-exact 6" Advance (float32 noise) must not hard-avoid: a full-width ruin holds an avoiding model at its edge.
func test_an_exact_six_inch_advance_does_not_avoid_the_ruin() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_set_strip(3.0, 5.0, TerrainRules.TerrainType.RUINS)
	var u := _unit("Walker", 1)
	var models := _solo._moving_models(u)
	var delta := Vector3(0, 0, 6.0 * IN2M + 5e-7)   # float32 noise on an exact 6" Advance
	var out := _solo._plan_positions(u, models, _solo._positions_of(models), delta, false, [], true, true)
	assert_float((out[0] as Vector3).z / IN2M) \
		.override_failure_message("a 6\" Advance was held at the ruin edge: the over-6\" test has no epsilon") \
		.is_greater(5.0)


## A goal inside the ruin lifts the avoid on purpose; the record must say so, not "despite avoidance".
func test_a_goal_inside_a_ruin_is_named() -> void:
	AiActRecorder.rules_epoch = AiActRecorder.EPOCH_73_V36
	_set_strip(8.0, 12.0, TerrainRules.TerrainType.RUINS)
	_solo._execute_move(_unit("Beast", 1), Vector3(0, 0, 10.0 * IN2M), 12.0, false)
	assert_str(_why()).contains("goal inside an Unstable ruin")
