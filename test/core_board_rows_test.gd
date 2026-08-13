extends GdUnitTestSuite
## E1b board-row schema (NML-995): the encoder corpus must carry mission
## objectives and the full unit status. Unit rows are 8 columns
## [player, x_in, z_in, alive, wounds_left, shaken, fatigued, activated];
## each objective adds a row [3, x_in, z_in, owner, 0, 0, 0, 0] — marker 3
## in the player slot, owner (0 neutral / 1 / 2) in the alive slot.

const IN2M := 0.0254

var CoreSelfplay := load("res://tools/core_selfplay.gd")


func _state() -> Dictionary:
	return {
		"round": 1,
		"rounds_total": 4,
		"units": {
			"p1_a": {"player": 1, "alive": 2, "positions": [Vector3(10 * IN2M, 0, 4 * IN2M), Vector3(12 * IN2M, 0, 4 * IN2M)],
				"wounds": [1, 2], "shaken": false, "fatigued": true, "activated": false},
			"p2_b": {"player": 2, "alive": 1, "positions": [Vector3(-6 * IN2M, 0, -8 * IN2M)],
				"wounds": [3], "shaken": true, "fatigued": false, "activated": true},
			"p2_dead": {"player": 2, "alive": 0, "positions": [Vector3.ZERO], "wounds": [0]},
		},
		"objectives": [
			{"pos": Vector3(16 * IN2M, 0, 0), "owner": 2},
			{"pos": Vector3(-16 * IN2M, 0, 0), "owner": 0},
		],
	}


func test_unit_rows_carry_full_status() -> void:
	var rows: Array = CoreSelfplay._board_rows(_state())
	var units := rows.filter(func(r: Variant) -> bool: return int(r[0]) != 3)
	assert_int(units.size()).is_equal(2)  # dead unit excluded
	for r in units:
		assert_int((r as Array).size()).is_equal(8)
	var a: Array = units.filter(func(r: Variant) -> bool: return int(r[0]) == 1)[0]
	# [player, x, z, alive, wounds, shaken, fatigued, activated]
	assert_float(a[1]).is_equal_approx(11.0, 0.11)  # centre of 10/12 in
	assert_int(int(a[3])).is_equal(2)
	assert_int(int(a[4])).is_equal(3)
	assert_int(int(a[5])).is_equal(0)
	assert_int(int(a[6])).is_equal(1)
	assert_int(int(a[7])).is_equal(0)
	var b: Array = units.filter(func(r: Variant) -> bool: return int(r[0]) == 2)[0]
	assert_int(int(b[5])).is_equal(1)
	assert_int(int(b[6])).is_equal(0)
	assert_int(int(b[7])).is_equal(1)


func test_objective_rows_present_with_owner() -> void:
	var rows: Array = CoreSelfplay._board_rows(_state())
	var objs := rows.filter(func(r: Variant) -> bool: return int(r[0]) == 3)
	assert_int(objs.size()).is_equal(2)
	var owned: Array = objs.filter(func(r: Variant) -> bool: return int(r[3]) == 2)
	assert_int(owned.size()).is_equal(1)
	assert_float(owned[0][1]).is_equal_approx(16.0, 0.11)
	assert_float(owned[0][2]).is_equal_approx(0.0, 0.11)
