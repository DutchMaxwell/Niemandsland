extends GdUnitTestSuite
## #183: a charge may only be declared when the production movement corridor can
## reach base contact inside the granted band. A rejected declaration must leave
## the board untouched and let the normal action tree choose a useful fallback.

const IN2M := 0.0254
const FULL_HEIGHT_WALL := [[Vector2(0.18, -0.60), Vector2(0.18, 0.60)]]


func before_test() -> void:
	MovementPlanner.fast_planner = false
	MovementPlanner.fast_planner_guard = MovementPlanner.FAST_PLANNER_GUARD


func _unit(pid: int, unit_name: String, positions: Array, base: Dictionary = {}) -> GameUnit:
	var unit := GameUnit.new()
	unit.unit_id = unit_name.to_lower().replace(" ", "_")
	unit.unit_properties = {
		"player_id": pid,
		"name": unit_name,
		"quality": 4,
		"defense": 4,
		"special_rules": [],
		"base_is_oval": bool(base.get("oval", false)),
		"base_width_mm": int(base.get("width_mm", 32)),
		"base_depth_mm": int(base.get("depth_mm", 32)),
		"base_size_round": int(base.get("round_mm", 32)),
	}
	for position in positions:
		var model := ModelInstance.new()
		model.is_alive = true
		model.unit = unit
		var node := Node3D.new()
		add_child(node)
		node.global_position = position
		model.node = node
		unit.models.append(model)
	return unit


func _arm(unit: GameUnit, weapons: Array) -> void:
	var source := OPRApiClient.OPRUnit.new()
	for spec in weapons:
		var weapon := OPRApiClient.OPRWeapon.new()
		weapon.name = str(spec.get("name", "Weapon"))
		weapon.range_value = int(spec.get("range", 0))
		weapon.attacks = int(spec.get("attacks", 1))
		weapon.count = 1
		source.weapons.append(weapon)
	unit.source_type = "opr"
	unit.source_data = source


func _controller(units: Array, walls: Array = []) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	for unit in units:
		army.game_units[(unit as GameUnit).unit_id] = unit
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	if not walls.is_empty():
		solo.walls_provider = func() -> Array: return walls
	return solo


func _probe(solo: SoloController, attacker: GameUnit, target: GameUnit,
		band_in: float = 12.0) -> Dictionary:
	if not solo.has_method("charge_path_probe"):
		return {"reachable": true, "missing": true}
	return solo.call("charge_path_probe", attacker, target, band_in) as Dictionary


func _texts(report: Dictionary) -> String:
	var texts := PackedStringArray()
	for note in report.get("rule_notes", []):
		texts.append(str(note.get("text", note)) if note is Dictionary else str(note))
	return "\n".join(texts)


func _corridor_records(solo: SoloController) -> Array:
	return solo.decision_log.filter(func(record: Dictionary) -> bool:
		return str(record.get("rule", "")).begins_with("#183 charge declaration"))


func test_issue_183_blocked_corridor_is_rejected_before_activation_is_spent() -> void:
	var attacker := _unit(2, "Melee", [Vector3.ZERO])
	_arm(attacker, [{"name": "CCW", "range": 0, "attacks": 2}])
	var target := _unit(1, "Target", [Vector3(0.28, 0, 0)])
	var solo := _controller([attacker, target], FULL_HEIGHT_WALL)
	assert_float(solo.nearest_melee_gap_in(attacker, target)).is_less(12.0)
	assert_str(solo.charge_illegal_why(attacker, target, 12.0)).contains("corridor")
	var position_before := attacker.models[0].node.global_position
	var report := solo._act(attacker)
	assert_int(int(report.get("action", -1))).is_equal(AiDecision.Action.RUSH)
	assert_float(attacker.models[0].node.global_position.distance_to(position_before) / IN2M).is_greater(1.0)
	assert_str(_texts(report)).contains("rejected")
	assert_str(_texts(report)).contains("instead")
	assert_int(_corridor_records(solo).size()).is_equal(1)


func test_clean_lane_and_in_band_detour_remain_reachable() -> void:
	var attacker := _unit(2, "Attacker", [Vector3.ZERO])
	var target := _unit(1, "Target", [Vector3(0.28, 0, 0)])
	var clean := _controller([attacker, target])
	assert_bool(bool(_probe(clean, attacker, target)["reachable"])).is_true()

	var detour_attacker := _unit(2, "Detour Attacker", [Vector3.ZERO])
	var detour_target := _unit(1, "Detour Target", [Vector3(0.23, 0, 0)])
	var short_wall := [[Vector2(0.12, -0.035), Vector2(0.12, 0.035)]]
	var detour := _controller([detour_attacker, detour_target], short_wall)
	var probe := _probe(detour, detour_attacker, detour_target)
	assert_bool(bool(probe["reachable"])).is_true()
	var report := detour._act(detour_attacker)
	assert_int(int(report.get("action", -1))).is_equal(AiDecision.Action.CHARGE)
	assert_float(detour.nearest_melee_gap_in(detour_attacker, detour_target)) \
		.is_less_equal(SeparationChecker.BASE_CONTACT_EPSILON_INCHES)


func test_charge_snap_uses_the_longest_formation_route_budget() -> void:
	# Seed 71720: the nearest model had 0.9" left to snap, but another model's
	# route had spent the full 12" unit budget. The execution correctly refused
	# that snap; the declaration probe must make the same decision.
	assert_bool(SoloController.charge_snap_fits_unit_budget(0.9, 12.0, 12.0)).is_false()
	assert_bool(SoloController.charge_snap_fits_unit_budget(0.9, 10.8, 12.0)).is_true()


func test_oval_target_uses_live_base_shape_in_corridor_probe() -> void:
	var attacker := _unit(2, "Attacker", [Vector3.ZERO])
	var target := _unit(1, "Land Train", [Vector3(0.31, 0, 0)],
		{"oval": true, "width_mm": 50, "depth_mm": 100})
	var solo := _controller([attacker, target], FULL_HEIGHT_WALL)
	assert_float(solo.nearest_melee_gap_in(attacker, target)).is_less(12.0)
	var probe := _probe(solo, attacker, target)
	assert_bool(bool(probe.get("missing", false))).is_false()
	assert_bool(bool(probe["reachable"])).is_false()


func test_rejected_probe_is_pure_even_with_prewarm_cache_enabled() -> void:
	var attacker := _unit(2, "Attacker", [Vector3.ZERO])
	var target := _unit(1, "Target", [Vector3(0.28, 0, 0)])
	var solo := _controller([attacker, target], FULL_HEIGHT_WALL)
	solo.prewarm_enabled = true
	solo._plan_cache = {"sentinel": {"planned": [], "trails": [], "flow_order": []}}
	solo._plan_cache_order = ["sentinel"]
	solo._plan_cache_hits = 7
	solo.last_flow_order = [3, 1]
	solo.last_move_paths = [{"sentinel": true}]
	solo.decision_log = [{"kind": "sentinel"}]
	solo._rng.seed = 183
	var digest_before := solo.state_digest()
	var decisions_before := solo.decision_log.duplicate(true)
	var cache_before := solo._plan_cache.duplicate(true)
	var cache_order_before := solo._plan_cache_order.duplicate()
	var flow_before := solo.last_flow_order.duplicate()
	var paths_before := solo.last_move_paths.duplicate(true)
	var rng_before: int = solo._rng.state
	var probe := _probe(solo, attacker, target)
	assert_bool(bool(probe.get("missing", false))).is_false()
	assert_bool(bool(probe["reachable"])).is_false()
	assert_str(solo.state_digest()).is_equal(digest_before)
	assert_array(solo.decision_log).is_equal(decisions_before)
	assert_dict(solo._plan_cache).is_equal(cache_before)
	assert_array(solo._plan_cache_order).is_equal(cache_order_before)
	assert_array(solo.last_flow_order).is_equal(flow_before)
	assert_array(solo.last_move_paths).is_equal(paths_before)
	assert_int(solo._plan_cache_hits).is_equal(7)
	assert_int(solo._rng.state).is_equal(rng_before)


func test_rejected_charge_keeps_a_legal_ranged_volley() -> void:
	var attacker := _unit(2, "Hybrid", [Vector3.ZERO])
	_arm(attacker, [
		{"name": "Rifle", "range": 24, "attacks": 2},
		{"name": "CCW", "range": 0, "attacks": 3},
	])
	var target := _unit(1, "Target", [Vector3(0.28, 0, 0)])
	var solo := _controller([attacker, target], FULL_HEIGHT_WALL)
	var report := solo._act(attacker)
	assert_int(int(report.get("action", -1))).is_not_equal(AiDecision.Action.CHARGE)
	assert_bool(bool(report.get("can_shoot", false))).is_true()
	assert_str(_texts(report)).contains("instead")
	assert_int(_corridor_records(solo).size()).is_equal(1)


func test_blocked_corridor_does_not_claim_a_shooting_tree_charge_refusal() -> void:
	var attacker := _unit(2, "Shooter", [Vector3.ZERO])
	_arm(attacker, [
		{"name": "Rifle", "range": 24, "attacks": 2},
		{"name": "CCW", "range": 0, "attacks": 2},
	])
	var target := _unit(1, "Target", [Vector3(0.28, 0, 0)])
	var solo := _controller([attacker, target], FULL_HEIGHT_WALL)
	assert_bool(bool(_probe(solo, attacker, target)["reachable"])).is_false()
	var report := solo._act(attacker)
	assert_int(int(report.get("action", -1))).is_not_equal(AiDecision.Action.CHARGE)
	assert_bool(bool(report.get("can_shoot", false))).is_true()
	assert_str(_texts(report)).not_contains("rejected")
	assert_array(_corridor_records(solo)).is_empty()
