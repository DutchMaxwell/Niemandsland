extends GdUnitTestSuite
## Solo-AI M2 (goal 001 P3): AiShooting — ranged profiles in range, attack totals, AP extraction.


func _w(nm: String, rng: int, atk: int, count: int, rules: Array) -> Dictionary:
	return {"name": nm, "range_value": rng, "attacks": atk, "count": count, "special_rules": rules}


func test_profiles_filter_by_range_and_skip_melee() -> void:
	var weapons: Array = [
		_w("CCW", 0, 2, 10, []),              # melee — never shoots
		_w("Rifle", 24, 1, 10, []),           # in range at 18"
		_w("Pistol", 12, 1, 2, []),           # out of range at 18"
	]
	var profiles := AiShooting.profiles_in_range(weapons, 18.0)
	assert_int(profiles.size()).is_equal(1)
	assert_str(str(profiles[0]["name"])).is_equal("Rifle")
	assert_int(int(profiles[0]["attacks"])).is_equal(10)   # attacks × count


func test_profiles_carry_ap() -> void:
	var profiles := AiShooting.profiles_in_range([_w("Melter", 12, 1, 3, ["AP(4)", "Deadly(3)"])], 10.0)
	assert_int(int(profiles[0]["ap"])).is_equal(4)
	assert_int(int(profiles[0]["attacks"])).is_equal(3)


func test_profiles_carry_deadly_relentless_and_range() -> void:
	var profiles := AiShooting.profiles_in_range([_w("Sniper", 30, 1, 2, ["AP(1)", "Deadly(3)", "Relentless"])], 20.0)
	assert_int(int(profiles[0]["deadly"])).is_equal(3)
	assert_bool(bool(profiles[0]["relentless"])).is_true()
	assert_int(int(profiles[0]["range"])).is_equal(30)
	assert_int(int(profiles[0]["ap"])).is_equal(1)
	# A plain weapon carries the neutral defaults.
	var plain := AiShooting.profiles_in_range([_w("Rifle", 24, 1, 5, [])], 10.0)
	assert_int(int(plain[0]["deadly"])).is_equal(0)
	assert_bool(bool(plain[0]["relentless"])).is_false()


func test_boundary_range_counts_as_in_range() -> void:
	assert_int(AiShooting.profiles_in_range([_w("Rifle", 24, 1, 1, [])], 24.0).size()).is_equal(1)
	assert_int(AiShooting.profiles_in_range([_w("Rifle", 24, 1, 1, [])], 24.01).size()).is_equal(0)


func test_melee_profiles_take_only_range_zero_weapons() -> void:
	var weapons: Array = [_w("CCW", 0, 2, 5, []), _w("Claws", 0, 3, 1, ["AP(1)"]), _w("Rifle", 24, 1, 5, [])]
	var profiles := AiShooting.melee_profiles(weapons)
	assert_int(profiles.size()).is_equal(2)
	assert_int(int(profiles[0]["attacks"])).is_equal(10)   # 2 × 5
	assert_int(int(profiles[1]["ap"])).is_equal(1)


func test_total_attacks_sums_profiles() -> void:
	var profiles := AiShooting.profiles_in_range([_w("Rifle", 24, 1, 5, []), _w("Cannon", 30, 3, 1, ["AP(2)"])], 20.0)
	assert_int(AiShooting.total_attacks(profiles)).is_equal(8)
	assert_int(AiShooting.total_attacks([])).is_equal(0)
