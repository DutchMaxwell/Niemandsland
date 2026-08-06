extends GdUnitTestSuite
## BattleSim.resolve, movement half (phase-1 step 2a). One activation resolved
## on a CLONE: the whole unit translates toward the goal, clamped by the
## official move band (advance 6" / rush+charge 12" for plain infantry); the
## input state stays untouched; the actor comes back activation-spent.

const IN2M := 0.0254


func _state_with_grunts() -> Dictionary:
	var u := GameUnit.new()
	u.unit_id = "Grunts"
	u.unit_properties = {"player_id": 2, "name": "Grunts", "quality": 4, "defense": 4,
		"special_rules": []}
	for x in [0.0, 1.0]:
		var m := ModelInstance.new()
		m.is_alive = true
		m.unit = u
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3(x * IN2M, 0, 0)
		m.node = n
		u.models.append(m)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {"Grunts": u}
	return BattleSim.capture(army)


func _centre(state: Dictionary) -> Vector3:
	var c := Vector3.ZERO
	var ps: Array = (state["units"]["Grunts"] as Dictionary)["positions"]
	for p in ps:
		c += p as Vector3
	return c / ps.size()


func test_bands_clamp_toward_a_far_goal() -> void:
	var state := _state_with_grunts()
	var goal := Vector3(30.0 * IN2M, 0, 0.5 * IN2M)   # ~29.5" out — beyond every band
	var start := _centre(state)
	for pair in [[AiDecision.Action.ADVANCE, 6.0], [AiDecision.Action.RUSH, 12.0],
			[AiDecision.Action.CHARGE, 12.0]]:
		var next := BattleSim.resolve(state, {"unit": "Grunts", "kind": pair[0], "dest": goal})
		var moved: float = (_centre(next) - start).length() / IN2M
		assert_float(moved).is_equal_approx(pair[1], 0.01)
	var hold := BattleSim.resolve(state, {"unit": "Grunts", "kind": AiDecision.Action.HOLD,
		"dest": goal})
	assert_that(_centre(hold)).is_equal(start)


func test_goal_within_band_is_reached_exactly_and_coherence_kept() -> void:
	var state := _state_with_grunts()
	var goal := Vector3(4.0 * IN2M, 0, 0)
	var next := BattleSim.resolve(state, {"unit": "Grunts", "kind": AiDecision.Action.ADVANCE,
		"dest": goal})
	assert_that(_centre(next)).is_equal(goal)
	var ps: Array = (next["units"]["Grunts"] as Dictionary)["positions"]
	var gap: float = ((ps[1] as Vector3) - (ps[0] as Vector3)).length() / IN2M
	assert_float(gap).is_equal_approx(1.0, 0.001)   # rigid translate keeps the formation


func test_resolve_spends_activation_on_the_clone_only() -> void:
	var state := _state_with_grunts()
	var next := BattleSim.resolve(state, {"unit": "Grunts", "kind": AiDecision.Action.ADVANCE,
		"dest": Vector3(4.0 * IN2M, 0, 0)})
	assert_bool((next["units"]["Grunts"] as Dictionary)["activated"]).is_true()
	assert_bool((state["units"]["Grunts"] as Dictionary)["activated"]).is_false()
	assert_that(_centre(state)).is_equal(Vector3(0.5 * IN2M, 0, 0))
