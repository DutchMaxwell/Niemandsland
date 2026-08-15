extends GdUnitTestSuite
## P0 menu-coverage probe (Plan B v2): AiPlanner.menu_covers answers whether
## the candidate menu can EXPRESS a move the decision tree chose. Measurement
## surface only — no decision reads it.

const IN2M := 0.0254


func _armed(pid: int, pos: Vector3, uid: String, weapon_range: int, melee := false) -> GameUnit:
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
	if melee:
		var cc := OPRApiClient.OPRWeapon.new()
		cc.name = "CCW"
		cc.range_value = 0
		cc.attacks = 4
		cc.count = 1
		opr.weapons.append(cc)
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


func test_the_wide_teacher_menu_offers_every_target() -> void:
	# P0b: the narrow menu carries ONE shoot target and ONE charge victim, so a
	# teacher who picks another one could never be labelled. The wide menu adds
	# the rest — measured ceiling, not a guess (P0 wave: hold 65%, charge 56%).
	var state := _state([_armed(2, Vector3.ZERO, "Grunts", 24, true),
		_armed(1, Vector3(0, 0, 10.0 * IN2M), "Foe", 0),
		_armed(1, Vector3(0, 0, 12.0 * IN2M), "Other", 0)])
	var narrow := AiPlanner.candidates(state, "Grunts")
	var wide := AiPlanner.candidates_wide(state, "Grunts")
	assert_int(wide.size()).is_greater(narrow.size())
	assert_int(wide.filter(func(c: Dictionary) -> bool: return c.has("shoot")).size()).is_equal(2)
	assert_int(wide.filter(func(c: Dictionary) -> bool: return c.has("charge")).size()).is_equal(2)
	var shot := AiPlanner._best_shoot(state, "Grunts")
	var mv := {"kind": AiDecision.Action.HOLD, "shoot": "Foe" if shot != "Foe" else "Other"}
	assert_bool(AiPlanner.menu_covers(state, "Grunts", mv)["covered"]).is_false()
	assert_bool(AiPlanner.menu_covers(state, "Grunts", mv, true)["covered"]).is_true()


func test_the_matched_index_is_the_training_label() -> void:
	# P1: "which entry did the teacher take" IS the label the clone learns, so
	# the index must point at the matching candidate, not merely say "yes".
	var state := _state([_armed(2, Vector3.ZERO, "Grunts", 24, true),
		_armed(1, Vector3(0, 0, 10.0 * IN2M), "Foe", 0),
		_armed(1, Vector3(0, 0, 12.0 * IN2M), "Other", 0)],
		[Vector3(20.0 * IN2M, 0, 0)])
	var cands := AiPlanner.candidates_wide(state, "Grunts")
	var hold := AiPlanner.menu_covers_in(cands, state, "Grunts",
		{"kind": AiDecision.Action.HOLD, "shoot": "Other"})
	assert_int(hold["idx"]).is_greater_equal(0)
	assert_str(str((cands[int(hold["idx"])] as Dictionary).get("shoot", ""))).is_equal("Other")
	var rush := AiPlanner.menu_covers_in(cands, state, "Grunts",
		{"kind": AiDecision.Action.RUSH, "goal": Vector3(20.0 * IN2M, 0, 0),
		"band_m": 12.0 * IN2M})
	assert_int(rush["idx"]).is_greater_equal(0)
	assert_int(int((cands[int(rush["idx"])] as Dictionary)["kind"])).is_equal(AiDecision.Action.RUSH)
	# an unexpressible move carries no label at all — sideways, where neither a
	# marker nor the retreat line points (straight back IS the retreat candidate)
	var miss := AiPlanner.menu_covers_in(cands, state, "Grunts",
		{"kind": AiDecision.Action.RUSH, "goal": Vector3(-40.0 * IN2M, 0, 0),
		"band_m": 12.0 * IN2M})
	assert_bool(miss["covered"]).is_false()
	assert_int(miss["idx"]).is_equal(-1)


func test_the_wide_menu_can_express_a_march_at_the_enemy() -> void:
	# Measured on the box (king_of_the_hill, ONE marker): the narrow menu is
	# marker-shaped, so movement coverage collapsed to 36%. The teacher menu
	# carries the tree's other destination — the enemy itself.
	var foe := _armed(1, Vector3(0, 0, 30.0 * IN2M), "Foe", 0)
	var state := _state([_armed(2, Vector3.ZERO, "Grunts", 0), foe],
		[Vector3(20.0 * IN2M, 0, 0)])
	var mv := {"kind": AiDecision.Action.RUSH, "goal": Vector3(0, 0, 30.0 * IN2M),
		"band_m": 12.0 * IN2M}
	assert_bool(AiPlanner.menu_covers(state, "Grunts", mv)["covered"]).is_false()
	assert_bool(AiPlanner.menu_covers(state, "Grunts", mv, true)["covered"]).is_true()
