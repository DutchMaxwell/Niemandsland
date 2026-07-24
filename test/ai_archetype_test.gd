extends GdUnitTestSuite
## Solo-AI: AiArchetype classifies a unit per the OPR Solo & Co-Op "Unit Types" rule — MELEE only if it
## has NO ranged weapon; otherwise HYBRID if its best melee weapon is stronger than its best ranged one,
## else SHOOTING. "Stronger" = attacks × (1 + AP). Weapons given as {range_value, attacks, special_rules}.


func _w(rng: int, atk: int, ap: int = 0) -> Dictionary:
	return {"range_value": rng, "attacks": atk, "special_rules": (["AP(%d)" % ap] if ap > 0 else [])}


func test_melee_only_is_melee() -> void:
	assert_int(AiArchetype.classify([_w(0, 2), _w(0, 1)])).is_equal(AiArchetype.Type.MELEE)


func test_ranged_only_is_shooting() -> void:
	assert_int(AiArchetype.classify([_w(24, 1), _w(18, 2)])).is_equal(AiArchetype.Type.SHOOTING)


func test_gun_plus_basic_ccw_is_shooting() -> void:
	# Rifle A2 + base CCW A1: the gun is the stronger weapon → Shooting.
	assert_int(AiArchetype.classify([_w(24, 2), _w(0, 1)])).is_equal(AiArchetype.Type.SHOOTING)


func test_equal_strength_favours_shooting_for_the_reach() -> void:
	# Rifle A1 + CCW A1: equal strength → Shooting wins the tie (a ranged weapon also has range).
	assert_int(AiArchetype.classify([_w(24, 1), _w(0, 1)])).is_equal(AiArchetype.Type.SHOOTING)


func test_dedicated_melee_weapon_with_a_pistol_is_hybrid_not_melee() -> void:
	# Great weapon A4 + pistol A1: it HAS a ranged weapon so it is never "Melee"; melee is stronger → Hybrid.
	assert_int(AiArchetype.classify([_w(0, 4), _w(12, 1)])).is_equal(AiArchetype.Type.HYBRID)


func test_battle_brothers_are_shooting() -> void:
	# The maintainer's case: Heavy Rifle (AP1) + Plasma Rifle (AP4) + basic CCW → the guns dominate → Shooting.
	assert_int(AiArchetype.classify([_w(24, 1, 1), _w(24, 1, 4), _w(0, 1)])).is_equal(AiArchetype.Type.SHOOTING)


func test_empty_is_melee() -> void:
	assert_int(AiArchetype.classify([])).is_equal(AiArchetype.Type.MELEE)


func test_has_ranged_and_max_range() -> void:
	assert_bool(AiArchetype.has_ranged([_w(0, 2)])).is_false()
	assert_bool(AiArchetype.has_ranged([_w(0, 2), _w(18, 1)])).is_true()
	assert_int(AiArchetype.max_range_inches([_w(0, 2), _w(18, 1), _w(24, 1)])).is_equal(24)
	assert_int(AiArchetype.max_range_inches([_w(0, 2)])).is_equal(0)
