extends GdUnitTestSuite
## Solo-AI M2: AiCombatMath turns rolled dice FACES into hits / wounds / morale outcomes per OPR core.


func test_count_hits_at_or_above_quality() -> void:
	# Quality 3+ → faces 6 and 3 hit, 2 and 1 miss.
	assert_int(AiCombatMath.count_hits([6, 3, 2, 1], 3)).is_equal(2)


func test_save_target_adds_ap() -> void:
	assert_int(AiCombatMath.save_target(4, 1)).is_equal(5)
	assert_int(AiCombatMath.save_target(4, 0)).is_equal(4)


func test_count_blocks_uses_defense_plus_ap() -> void:
	# Defense 4, AP 1 → save target 5 → only 6 and 5 block.
	assert_int(AiCombatMath.count_blocks([6, 5, 3], 4, 1)).is_equal(2)


func test_wounds_are_hits_minus_blocks() -> void:
	# 3 hits, saves [6,2,1] vs Defense 4 (target 4, no AP) → one block (6) → 2 wounds.
	assert_int(AiCombatMath.wounds(3, [6, 2, 1], 4, 0)).is_equal(2)


func test_wounds_never_negative() -> void:
	assert_int(AiCombatMath.wounds(1, [6, 6, 6], 4, 0)).is_equal(0)


func test_at_or_below_half() -> void:
	assert_bool(AiCombatMath.at_or_below_half(5, 10)).is_true()
	assert_bool(AiCombatMath.at_or_below_half(6, 10)).is_false()
	assert_bool(AiCombatMath.at_or_below_half(0, 0)).is_true()


func test_morale_pass_shaken_rout() -> void:
	# Quality 3+: a 5 passes.
	assert_int(AiCombatMath.morale_result(5, 3, false)).is_equal(AiCombatMath.Morale.PASSED)
	# A 2 fails; above half → Shaken.
	assert_int(AiCombatMath.morale_result(2, 3, false)).is_equal(AiCombatMath.Morale.SHAKEN)
	# A 2 fails; at/below half → Rout.
	assert_int(AiCombatMath.morale_result(2, 3, true)).is_equal(AiCombatMath.Morale.ROUT)
