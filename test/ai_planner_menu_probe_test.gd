extends GdUnitTestSuite
## P0 menu-coverage probe (Plan B v2): AiPlanner.menu_covers answers whether
## the candidate menu can EXPRESS a move the decision tree chose. Measurement
## surface only — no decision reads it.

const IN2M := 0.0254


func _armed(pid: int, pos: Vector3, uid: String, weapon_range: int) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = uid
	u.unit_properties = {"player_id": pid, "name": uid, "quality": 4,
		"defense": 4, "special_rules": []}
	var m := ModelInstance.new()
	m.is_alive = true
	m.wounds_current = 1
	m.unit = u
	var n := Node3D.new()
	add_child(n)
	n.global_position = pos
	m.node = n
	u.models.append(m)
	var opr := OPRApiClient.OPRUnit.new()
	var ow := OPRApiClient.OPRWeapon.new()
	ow.name = "W"
	ow.range_value = weapon_range
	ow.attacks = 4
	ow.count = 1
	opr.weapons.append(ow)
	u.source_type = "opr"
	u.source_data = opr
	return u


func _state(units: Array, objectives: Array = []) -> Dictionary:
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	var gu := {}
	for u in units:
		gu[(u as GameUnit).unit_id] = u
	army.game_units = gu
	return BattleSim.capture(army, func() -> Array: return objectives,
		func(_i: int) -> int: return 0)


func test_rush_to_a_marker_is_on_the_menu() -> void:
	var marker := Vector3(20.0 * IN2M, 0, 0)
	var state := _state([_armed(2, Vector3.ZERO, "Grunts", 0)], [marker])
	var cov := AiPlanner.menu_covers(state, "Grunts", {"kind": AiDecision.Action.RUSH,
		"goal": marker, "band_m": 12.0 * IN2M})
	assert_str(str(cov["class"])).is_equal("move")
	assert_bool(cov["covered"]).is_true()
	assert_float(cov["best_in"]).is_less(0.001)


func test_a_walk_at_the_enemy_away_from_every_marker_is_not_on_the_menu() -> void:
	# The suspected menu ceiling: the tree may march straight at a foe, and the
	# menu only ever offers markers, a retreat and the support moves.
	var foe := _armed(1, Vector3(0, 0, 30.0 * IN2M), "Foe", 0)
	var state := _state([_armed(2, Vector3.ZERO, "Grunts", 0), foe],
		[Vector3(20.0 * IN2M, 0, 0)])
	var cov := AiPlanner.menu_covers(state, "Grunts", {"kind": AiDecision.Action.RUSH,
		"goal": Vector3(0, 0, 30.0 * IN2M), "band_m": 12.0 * IN2M})
	assert_bool(cov["covered"]).is_false()
	assert_bool(cov["loose"]).is_false()
	assert_float(cov["best_in"]).is_greater(6.0)


func test_hold_matches_only_on_the_same_victim() -> void:
	var state := _state([_armed(2, Vector3.ZERO, "Grunts", 24),
		_armed(1, Vector3(0, 0, 10.0 * IN2M), "Foe", 0),
		_armed(1, Vector3(0, 0, 12.0 * IN2M), "Other", 0)])
	var shot := AiPlanner._best_shoot(state, "Grunts")
	assert_str(shot).is_not_empty()
	var hit := AiPlanner.menu_covers(state, "Grunts",
		{"kind": AiDecision.Action.HOLD, "shoot": shot})
	assert_str(str(hit["class"])).is_equal("hold")
	assert_bool(hit["covered"]).is_true()
	var miss := AiPlanner.menu_covers(state, "Grunts",
		{"kind": AiDecision.Action.HOLD, "shoot": "Foe" if shot != "Foe" else "Other"})
	assert_bool(miss["covered"]).is_false()


func test_the_retreat_goal_compares_as_the_step_it_produces() -> void:
	# The menu's retreat carries a 100" convention goal; clamped to the band it
	# is the one move away the tree's kite also makes.
	var state := _state([_armed(2, Vector3.ZERO, "Grunts", 24),
		_armed(1, Vector3(0, 0, 10.0 * IN2M), "Foe", 0)],
		[Vector3(20.0 * IN2M, 0, 0)])
	var cov := AiPlanner.menu_covers(state, "Grunts", {"kind": AiDecision.Action.KITE,
		"goal": Vector3(0, 0, -6.0 * IN2M), "band_m": 6.0 * IN2M})
	assert_str(str(cov["class"])).is_equal("move")
	assert_bool(cov["covered"]).is_true()
