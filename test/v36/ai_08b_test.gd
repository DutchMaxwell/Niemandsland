extends GdUnitTestSuite
## v3.6 row AI-08b: Crossing Strike is the 3.6 name of the weapon that attacks only when its bearer
## moves through an enemy unit (the 3.5 name is Strafing). On main the weapon-profile flag only knows
## the old name, so a 3.6 Crossing Strike weapon fires in every NORMAL volley (illegal) and never in
## the move-through set. The control: the 3.5 name keeps behaving exactly as before.


func _w(nm: String, rng: int, atk: int, rules: Array) -> Dictionary:
	return {"name": nm, "range_value": rng, "attacks": atk, "count": 1, "special_rules": rules}


func _names(profiles: Array) -> Array:
	var out: Array = []
	for p in profiles:
		out.append(str((p as Dictionary).get("name", "")))
	return out


func test_a_crossing_strike_weapon_never_joins_a_normal_volley() -> void:
	var weapons: Array = [_w("Twin Autocannon", 24, 4, ["Crossing Strike"]), _w("Lash Cannon", 24, 2, [])]
	assert_array(_names(AiShooting.profiles_in_range(weapons, 6.0))) \
		.override_failure_message("a Crossing Strike weapon fired in a normal volley") \
		.is_equal(["Lash Cannon"])


func test_a_crossing_strike_weapon_is_in_the_move_through_set_with_the_strafing_flag() -> void:
	var weapons: Array = [_w("Twin Autocannon", 24, 4, ["Crossing Strike"]), _w("Lash Cannon", 24, 2, [])]
	var set: Array = AiShooting.strafing_profiles(weapons)
	assert_int(set.size()).override_failure_message("only the Crossing Strike weapon belongs to the set") \
		.is_equal(1)
	if set.size() == 1:
		assert_str(str(set[0]["name"])).is_equal("Twin Autocannon")
		assert_bool(bool(set[0]["strafing"])) \
			.override_failure_message("the move-through weapon must carry the strafing flag").is_true()


func test_control_a_strafing_weapon_is_unchanged() -> void:
	var weapons: Array = [_w("Twin Autocannon", 24, 4, ["Strafing"]), _w("Lash Cannon", 24, 2, [])]
	assert_array(_names(AiShooting.profiles_in_range(weapons, 6.0))).is_equal(["Lash Cannon"])
	var set: Array = AiShooting.strafing_profiles(weapons)
	assert_int(set.size()).is_equal(1)
	assert_bool(bool(set[0]["strafing"])).is_true()
