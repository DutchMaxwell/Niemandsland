extends GdUnitTestSuite
## E1b/v3 board-row schema (NML-995): the encoder corpus must carry mission
## objectives, full unit status AND the unit stat line. Unit rows are 12
## columns [player, x_in, z_in, alive, wounds_left, shaken, fatigued,
## activated, range_max_in, attacks_total, quality, defense]; each objective
## adds [3, x_in, z_in, owner, 0,0,0,0, 0,0,0,0] — marker 3 in the player
## slot, owner (0 neutral / 1 / 2) in the alive slot. Units without a
## readable OPRUnit stat line fall back to zeros in columns 9-12.

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
		assert_int((r as Array).size()).is_equal(12)
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
	for r in objs:
		assert_int((r as Array).size()).is_equal(12)
	var owned: Array = objs.filter(func(r: Variant) -> bool: return int(r[3]) == 2)
	assert_int(owned.size()).is_equal(1)
	assert_float(owned[0][1]).is_equal_approx(16.0, 0.11)
	assert_float(owned[0][2]).is_equal_approx(0.0, 0.11)


func test_stat_line_from_opr_unit() -> void:
	var ou := OPRApiClient.OPRUnit.new()
	ou.quality = 3
	ou.defense = 5
	var w1 := OPRApiClient.OPRWeapon.new()
	w1.range_value = 24
	w1.attacks = 2
	w1.count = 5
	var w2 := OPRApiClient.OPRWeapon.new()
	w2.range_value = 0   # melee
	w2.attacks = 3
	w2.count = 1
	ou.weapons = [w1, w2]
	var gu: GameUnit = auto_free(GameUnit.new())
	gu.source_data = ou
	var st := _state()
	(st["units"]["p1_a"] as Dictionary)["unit"] = gu
	var rows: Array = CoreSelfplay._board_rows(st)
	var a: Array = rows.filter(func(r: Variant) -> bool: return int(r[0]) == 1)[0]
	# [.., range_max, attacks_total, quality, defense]
	assert_int(int(a[8])).is_equal(24)
	assert_int(int(a[9])).is_equal(13)  # 2*5 + 3*1
	assert_int(int(a[10])).is_equal(3)
	assert_int(int(a[11])).is_equal(5)
	# unit without stat line falls back to zeros
	var b: Array = rows.filter(func(r: Variant) -> bool: return int(r[0]) == 2)[0]
	assert_int(int(b[8])).is_equal(0)
	assert_int(int(b[11])).is_equal(0)
