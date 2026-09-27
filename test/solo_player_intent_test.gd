extends GdUnitTestSuite
## Automodus A1 (NML-202): SoloController.player_intent() — the player's feeder into
## execute_intent(). Refusals move nothing and name why; a legal Charge carries the full
## Melee-Shrouding/Rapid-Charge-adjusted execution band even though the plain fixtures here
## never trigger either rule (charge_band_in == charge == 12" throughout).

const IN2M := 0.0254


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
		node.global_position = position
		model.node = node
		unit.models.append(model)
	return unit


func _controller(units: Array) -> SoloController:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	for unit in units:
		army.game_units[(unit as GameUnit).unit_id] = unit
	army.current_round = 1
	var solo: SoloController = auto_free(SoloController.new())
	add_child(solo)
	solo.setup(army, null, null, 1, 2)
	return solo


func test_charge_out_of_band_is_refused_with_the_reason() -> void:
	var attacker := _unit(2, "Attacker", [Vector3.ZERO])
	var target := _unit(1, "Target", [Vector3(20 * IN2M, 0, 0)])
	var solo := _controller([attacker, target])
	var intent := solo.player_intent(attacker, AiDecision.Action.CHARGE, target)
	assert_bool(intent.has("refused")).is_true()
	assert_str(str(intent.get("refused", ""))).contains("out of charge band")


func test_charge_in_band_returns_a_charge_intent_with_the_full_band() -> void:
	var attacker := _unit(2, "Attacker", [Vector3.ZERO])
	var target := _unit(1, "Target", [Vector3(8 * IN2M, 0, 0)])
	var solo := _controller([attacker, target])
	var intent := solo.player_intent(attacker, AiDecision.Action.CHARGE, target)
	assert_bool(intent.has("refused")).is_false()
	assert_int(int(intent["action"])).is_equal(AiDecision.Action.CHARGE)
	assert_float(float(intent["charge_band_in"])).is_equal_approx(12.0, 0.01)
	assert_str(str(intent["source"])).is_equal("player")


func test_slow_unit_advances_at_its_reduced_band() -> void:
	var attacker := _unit(2, "Slow Beast", [Vector3.ZERO])
	attacker.unit_properties["special_rules"] = ["Slow"]
	var target := _unit(1, "Target", [Vector3(2.0, 0, 0)])   # far — Advance never kites here
	var solo := _controller([attacker, target])
	var intent := solo.player_intent(attacker, AiDecision.Action.ADVANCE, target)
	assert_bool(intent.has("refused")).is_false()
	assert_int(int(intent["action"])).is_equal(AiDecision.Action.ADVANCE)
	assert_float(float(intent["band_in"])).is_equal_approx(4.0, 0.01)   # Slow: 6" - 2" (GF/AoF v3.5.1 p.13)


func test_immobile_unit_refuses_anything_but_hold() -> void:
	var attacker := _unit(2, "Turret", [Vector3.ZERO])
	attacker.unit_properties["special_rules"] = ["Immobile"]
	var target := _unit(1, "Target", [Vector3(1.0, 0, 0)])
	var solo := _controller([attacker, target])
	var intent := solo.player_intent(attacker, AiDecision.Action.RUSH, target)
	assert_bool(intent.has("refused")).is_true()
	assert_str(str(intent.get("refused", ""))).contains("Hold")


# ===== A2 suggest_target =====

func test_suggest_target_charge_picks_the_chargeable_enemy() -> void:
	var attacker := _unit(2, "Attacker", [Vector3.ZERO])
	var enemy := _unit(1, "Enemy", [Vector3(8 * IN2M, 0, 0)])
	var solo := _controller([attacker, enemy])
	assert_object(solo.suggest_target(attacker, AiDecision.Action.CHARGE)).is_equal(enemy)


func test_suggest_target_rush_picks_the_nearest_enemy_by_gap() -> void:
	var attacker := _unit(2, "Attacker", [Vector3.ZERO])
	var near := _unit(1, "Near", [Vector3(6 * IN2M, 0, 0)])
	var far := _unit(1, "Far", [Vector3(20 * IN2M, 0, 0)])
	var solo := _controller([attacker, near, far])
	assert_object(solo.suggest_target(attacker, AiDecision.Action.RUSH)).is_equal(near)


func test_suggest_target_advance_falls_back_to_nearest_enemy_with_no_shot() -> void:
	var attacker := _unit(2, "Attacker", [Vector3.ZERO])   # no weapons -> best_shoot_target_now is null
	var near := _unit(1, "Near", [Vector3(6 * IN2M, 0, 0)])
	var far := _unit(1, "Far", [Vector3(20 * IN2M, 0, 0)])
	var solo := _controller([attacker, near, far])
	assert_object(solo.suggest_target(attacker, AiDecision.Action.ADVANCE)).is_equal(near)
