extends GdUnitTestSuite
## Solo-AI M2: AiArchetype classifies a unit's fighting style from its weapon attack volume
## (range_value == 0 = melee). Pure — weapons given as {range_value, attacks} dicts.


func _w(rng: int, atk: int) -> Dictionary:
	return {"range_value": rng, "attacks": atk}


func test_melee_only_is_melee() -> void:
	assert_int(AiArchetype.classify([_w(0, 2), _w(0, 1)])).is_equal(AiArchetype.Type.MELEE)


func test_ranged_only_is_shooting() -> void:
	assert_int(AiArchetype.classify([_w(24, 1), _w(18, 2)])).is_equal(AiArchetype.Type.SHOOTING)


func test_ranged_dominant_over_base_ccw_is_shooting() -> void:
	# Rifle A2 + base CCW A1 → ranged (2) >= 2x melee (1) → Shooting.
	assert_int(AiArchetype.classify([_w(24, 2), _w(0, 1)])).is_equal(AiArchetype.Type.SHOOTING)


func test_even_split_is_hybrid() -> void:
	# Rifle A1 + CCW A1 → neither dominates → Hybrid.
	assert_int(AiArchetype.classify([_w(24, 1), _w(0, 1)])).is_equal(AiArchetype.Type.HYBRID)


func test_melee_dominant_is_melee() -> void:
	# Great weapon A4 + pistol A1 → melee (4) >= 2x ranged (1) → Melee.
	assert_int(AiArchetype.classify([_w(0, 4), _w(12, 1)])).is_equal(AiArchetype.Type.MELEE)


func test_empty_is_melee() -> void:
	assert_int(AiArchetype.classify([])).is_equal(AiArchetype.Type.MELEE)


func test_has_ranged_and_max_range() -> void:
	assert_bool(AiArchetype.has_ranged([_w(0, 2)])).is_false()
	assert_bool(AiArchetype.has_ranged([_w(0, 2), _w(18, 1)])).is_true()
	assert_int(AiArchetype.max_range_inches([_w(0, 2), _w(18, 1), _w(24, 1)])).is_equal(24)
	assert_int(AiArchetype.max_range_inches([_w(0, 2)])).is_equal(0)
