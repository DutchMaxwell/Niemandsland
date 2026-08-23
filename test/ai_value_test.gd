extends GdUnitTestSuite
## KUGEL v1 (NML-1045): the value net's forward pass, its character-C shaping,
## and the planner seam's OFF-guarantee. The trained net itself is judged by
## the W1/W2 gates on the board — these pin the plumbing.

const IN2M := 0.0254


## A net whose margin IS "my alive models minus theirs", built to the live row
## width so the PRODUCTION forward pass is what gets exercised. Two state units
## carry the two directions (a single ReLU unit could only ever report one).
func _alive_counter_net(width: int) -> Dictionary:
	var r0: Array = []
	var pick: Array = []
	pick.resize(width + 2)
	pick.fill(0.0)
	pick[3] = 1.0                      # board_rows col 3 = alive models
	r0.append(pick)
	var zero: Array = []
	zero.resize(width + 2)
	zero.fill(0.0)
	r0.append(zero)
	return {"kind": "value_v1", "in_dim": width, "hidden": 2, "pools": 3,
		"row_0_weight": r0, "row_0_bias": [0.0, 0.0],
		"row_2_weight": [[1.0, 0.0], [0.0, 0.0]], "row_2_bias": [0.0, 0.0],
		"state_0_weight": [[1.0, 0.0, -1.0, 0.0, 0.0, 0.0],
			[-1.0, 0.0, 1.0, 0.0, 0.0, 0.0]],
		"state_0_bias": [0.0, 0.0],
		"head_weight": [[1.0, -1.0]], "head_bias": [0.0]}


func _unit(pid: int, models: int, x_in: float) -> GameUnit:
	var u := GameUnit.new()
	u.unit_id = "p%d_%d" % [pid, models]
	u.unit_properties = {"player_id": pid, "name": "U%d" % pid, "quality": 4, "defense": 4}
	for i in range(models):
		var m := ModelInstance.new()
		m.is_alive = true
		var n := Node3D.new()
		add_child(n)
		n.global_position = Vector3((x_in + i) * IN2M, 0, 0)
		m.node = n
		u.models.append(m)
	return u


func test_margin_is_mirror_symmetric_on_a_real_captured_state() -> void:
	# The production path end to end: real capture -> board_rows -> pooling.
	# Four models against one: whoever asks, the answer must mirror exactly,
	# and the bigger side must read positive (rules out a seat/pool mix-up).
	var big := _unit(1, 4, 0.0)
	var small := _unit(2, 1, 20.0)
	var army: OPRArmyManager = auto_free(OPRArmyManager.new())
	army.game_units = {big.unit_id: big, small.unit_id: small}
	var state := BattleSim.capture(army, func() -> Array: return [],
		func(_i: int) -> int: return 0, 2, 4)
	var width := 0
	for raw in BattleSim.board_rows(state):
		width = maxi(width, (raw as Array).size())
	AiValue.set_net_for_test(_alive_counter_net(width))
	var m1 := AiValue.margin(state, 1)
	var m2 := AiValue.margin(state, 2)
	assert_bool(m1 > 0.0).is_true()
	assert_bool(m2 < 0.0).is_true()
	assert_float(m1).is_equal_approx(-m2, 0.0001)


func test_character_c_secures_first_then_pays_for_the_crush() -> void:
	# Below the threshold: steep — a small edge already reads as "winning",
	# so the search takes the safe win instead of gambling for more.
	var small := AiValue.shaped(0.10)
	var mid := AiValue.shaped(0.40)
	assert_bool(small > 0.5).is_true()
	assert_bool(mid > small).is_true()
	assert_bool(mid < 0.95).is_true()
	# Decided: MORE margin still pays (the crush clause), monotone to 1.0.
	var won := AiValue.shaped(0.60)
	var crushed := AiValue.shaped(1.00)
	assert_bool(crushed > won).is_true()
	assert_float(crushed).is_equal_approx(1.0, 0.0001)
	# Mirrored for the losing side.
	assert_float(AiValue.shaped(-1.0)).is_equal_approx(0.0, 0.0001)
	assert_float(AiValue.shaped(0.0)).is_equal_approx(0.5, 0.0001)


func test_no_net_or_zero_blend_leaves_the_leaf_untouched() -> void:
	# The OFF guarantee: without a net the seam IS the hand eval.
	AiValue.set_net_for_test({})
	assert_float(AiValue.blend_weight()).is_equal_approx(0.0, 0.0001)
	assert_bool(is_nan(AiValue.margin({"round": 1, "rounds_total": 4,
		"units": {}, "objectives": []}, 1))).is_true()
