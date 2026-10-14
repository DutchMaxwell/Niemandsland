extends GdUnitTestSuite
## rules-must-log: the move record that reports dangerous_models also names WHY avoidance was off or did
## not hold (data.dangerous_why). Logging only — no behaviour change.

const IN2M := 0.0254

var _mgr: OPRArmyManager
var _solo: SoloController


func before_test() -> void:
	_mgr = auto_free(OPRArmyManager.new())
	_solo = auto_free(SoloController.new())
	add_child(_solo)
	_solo.army_manager = _mgr
	_solo.human_slot = 1
	_solo.ai_slot = 2
	_set_strip(3.0, 5.0)


func _set_strip(z0: float, z1: float) -> void:
	_solo.terrain_type_at = func(p: Vector3) -> int:
		var z_in := p.z / IN2M
		return TerrainRules.TerrainType.DANGEROUS if z_in >= z0 and z_in <= z1 \
			else TerrainRules.TerrainType.NONE


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
