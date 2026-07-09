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


func test_should_test_shooting_morale() -> void:
	# Took casualties (10 -> 4 of 10) and now at/below half → test.
	assert_bool(AiCombatMath.should_test_shooting_morale(10, 4, 10)).is_true()
	# Took casualties but still above half (10 -> 6 of 10) → no test.
	assert_bool(AiCombatMath.should_test_shooting_morale(10, 6, 10)).is_false()
	# No casualties this volley (unchanged) → no test, even at half.
	assert_bool(AiCombatMath.should_test_shooting_morale(5, 5, 10)).is_false()
	# Wiped out (alive_now 0) → gone, not routed via a morale test.
	assert_bool(AiCombatMath.should_test_shooting_morale(3, 0, 10)).is_false()
	# Exactly half after casualties (10 -> 5 of 10) → test.
	assert_bool(AiCombatMath.should_test_shooting_morale(10, 5, 10)).is_true()


func test_success_chance_bounds_and_values() -> void:
	# 2+ → 5/6, 4+ → 3/6, 6+ → 1/6 (a 6 always hits).
	assert_float(AiCombatMath.success_chance(2)).is_equal_approx(5.0 / 6.0, 0.0001)
	assert_float(AiCombatMath.success_chance(4)).is_equal_approx(3.0 / 6.0, 0.0001)
	assert_float(AiCombatMath.success_chance(6)).is_equal_approx(1.0 / 6.0, 0.0001)
	# Clamped: target <= 1 caps at 5/6 (a 1 always fails); target >= 7 floors at 1/6 (a 6 always saves).
	assert_float(AiCombatMath.success_chance(1)).is_equal_approx(5.0 / 6.0, 0.0001)
	assert_float(AiCombatMath.success_chance(9)).is_equal_approx(1.0 / 6.0, 0.0001)


func test_relentless_bonus_hits_only_beyond_9_inches() -> void:
	# Over 9": each unmodified 6 adds a hit.
	assert_int(AiCombatMath.relentless_bonus_hits([6, 6, 3, 1], 12.0)).is_equal(2)
	# At exactly 9" or closer: no bonus (the rule is "over 9").
	assert_int(AiCombatMath.relentless_bonus_hits([6, 6, 3, 1], 9.0)).is_equal(0)
	assert_int(AiCombatMath.relentless_bonus_hits([6, 6, 3, 1], 5.0)).is_equal(0)
	# No 6s → no bonus even at long range.
	assert_int(AiCombatMath.relentless_bonus_hits([5, 4, 3], 24.0)).is_equal(0)


func test_deadly_multiplier_is_tough_capped() -> void:
	# Deadly(3) vs a Tough(3) model → each unsaved wound counts triple.
	assert_int(AiCombatMath.deadly_multiplier(3, 3)).is_equal(3)
	# Deadly(6) vs Tough(3) → capped at the model's Tough (overkill lost).
	assert_int(AiCombatMath.deadly_multiplier(6, 3)).is_equal(3)
	# Deadly(2) vs Tough(3) → the full X (below the cap).
	assert_int(AiCombatMath.deadly_multiplier(2, 3)).is_equal(2)
	# Against a non-Tough unit (Tough 1) Deadly deals only 1 (per the p.10 clarification).
	assert_int(AiCombatMath.deadly_multiplier(3, 1)).is_equal(1)


func test_expected_wounds() -> void:
	# 6 attacks, hit on 4+ (1/2), target Def 4+ save fails on 1/2 → 6 × 0.5 × 0.5 = 1.5.
	assert_float(AiCombatMath.expected_wounds(6, 4, 4, 0)).is_equal_approx(1.5, 0.0001)
	# AP2 pushes the save to 6+ (through-chance 5/6): 6 × 0.5 × 5/6 = 2.5.
	assert_float(AiCombatMath.expected_wounds(6, 4, 4, 2)).is_equal_approx(2.5, 0.0001)
	# No attacks → no damage.
	assert_float(AiCombatMath.expected_wounds(0, 3, 5, 0)).is_equal_approx(0.0, 0.0001)
	# Higher AP never lowers expected damage (more wounds get through).
	assert_bool(AiCombatMath.expected_wounds(4, 3, 4, 3) >= AiCombatMath.expected_wounds(4, 3, 4, 0)).is_true()
