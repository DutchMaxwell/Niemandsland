extends GdUnitTestSuite
## Phase-1 step 5b: AiPlanner.plan — the 1-ply pick in mission currency.
## WHICH unit activates is part of the pick; the input state stays pure;
## the intent record carries the sentence, the numbers and the runner-up.

const IN2M := 0.0254


func _unit(pid: int, positions: Array, uid: String) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4, "defense": 4,
		"special_rules": []}
	for p in positions:
		var m := ModelInstance.new()
		m.is_alive = true
		m.wounds_current = 1
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = p
		m.node = n
		u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "CCW"
	ow.range_value = 0
	ow.attacks = 4
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


## Taker (P2) stands 6" from a neutral objective, Idler (P2) 40" out in the
## void, one enemy 30" off. The match-winning activation is Taker rushing
## the objective — the planner must pick that pair, not just any legal move.
func _state() -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var taker := _unit(2, [Vector3(6.0 * IN2M, 0, 0)], "Taker")
	var idler := _unit(2, [Vector3(40.0 * IN2M, 0, 40.0 * IN2M)], "Idler")
	var enemy := _unit(1, [Vector3(-30.0 * IN2M, 0, 0)], "Enemy")
	army.game_units = {"Taker": taker, "Idler": idler, "Enemy": enemy}
	return BattleSim.capture(army, func() -> Array: return [Vector3.ZERO],
		func(_i: int) -> int: return 0)


func test_picks_the_matchwinning_unit_and_action() -> void:
	var state := _state()
	var pick := AiPlanner.plan(state, 2)
	assert_bool(pick["used"]).is_true()
	assert_str(str(pick["unit_key"])).is_equal("Taker")
	assert_int(int((pick["action"] as Dictionary)["kind"])).is_equal(AiDecision.Action.RUSH)
	var exp: Dictionary = pick["expectation"]
	assert_float(float(exp["after"])).is_greater(float(exp["before"]))
	assert_that(pick["runner_up"]).is_not_equal({})
	assert_str(str(pick["intent"])).contains("Taker").contains("rush objective 1")
	# purity: planning spent nothing on the input state
	assert_bool((state["units"]["Taker"] as Dictionary)["activated"]).is_false()


func test_activated_units_are_out_of_the_pick() -> void:
	var state := _state()
	(state["units"]["Taker"] as Dictionary)["activated"] = true
	assert_str(str(AiPlanner.plan(state, 2)["unit_key"])).is_equal("Idler")


func test_nothing_left_returns_unused() -> void:
	var state := _state()
	(state["units"]["Taker"] as Dictionary)["activated"] = true
	(state["units"]["Idler"] as Dictionary)["activated"] = true
	assert_that(AiPlanner.plan(state, 2)).is_equal({"used": false})


func test_shaken_unit_only_recovers() -> void:
	var state := _state()
	(state["units"]["Idler"] as Dictionary)["activated"] = true
	(state["units"]["Taker"] as Dictionary)["shaken"] = true
	var pick := AiPlanner.plan(state, 2)
	assert_str(str(pick["unit_key"])).is_equal("Taker")
	assert_int(int((pick["action"] as Dictionary)["kind"])).is_equal(AiDecision.Action.HOLD)
	assert_bool((pick["action"] as Dictionary).has("shoot")).is_false()


func test_plan_is_deterministic() -> void:
	var state := _state()
	assert_that(AiPlanner.plan(state, 2)).is_equal(AiPlanner.plan(state, 2))
