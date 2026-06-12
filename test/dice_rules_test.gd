extends GdUnitTestSuite
## DiceRules: success evaluation (OPR GF/AoF Core Rules v3.5.1, p.1 "Quality
## Tests" / "Modifiers") and reroll-index selection for the dice tray.

# ===== is_success =====


func test_success_at_target() -> void:
	assert_bool(DiceRules.is_success(4, 4, 0)).is_true()
	assert_bool(DiceRules.is_success(3, 4, 0)).is_false()
	assert_bool(DiceRules.is_success(2, 2, 0)).is_true()
	assert_bool(DiceRules.is_success(5, 6, 0)).is_false()


func test_modifier_shifts_result() -> void:
	assert_bool(DiceRules.is_success(3, 4, 1)).is_true()
	assert_bool(DiceRules.is_success(4, 4, -1)).is_false()
	# Big stacked modifiers are legal in OPR (AP(4), Artillery -2, spell tokens).
	assert_bool(DiceRules.is_success(2, 6, 4)).is_true()
	assert_bool(DiceRules.is_success(5, 2, -4)).is_false()


func test_natural_six_always_succeeds_natural_one_always_fails() -> void:
	# OPR v3.5.1 p.1 "Modifiers": "Regardless of modifiers, rolls of 6 always
	# succeed, and rolls of 1 always fail."
	assert_bool(DiceRules.is_success(6, 6, -5)).is_true()
	assert_bool(DiceRules.is_success(1, 2, 5)).is_false()


func test_no_target_means_no_success() -> void:
	assert_bool(DiceRules.is_success(6, DiceRules.TARGET_NONE, 0)).is_false()

# ===== count_successes =====


func test_count_successes() -> void:
	assert_int(DiceRules.count_successes([1, 2, 3, 4, 5, 6] as Array[int], 4, 0)).is_equal(3)
	assert_int(DiceRules.count_successes([1, 2, 3, 4, 5, 6] as Array[int], 4, 1)).is_equal(4)
	assert_int(DiceRules.count_successes([] as Array[int], 4, 0)).is_equal(0)
	assert_int(DiceRules.count_successes([6, 6, 1] as Array[int], DiceRules.TARGET_NONE, 0)).is_equal(0)

# ===== reroll_indices =====


func test_reroll_failures_respects_target_and_modifier() -> void:
	var faces: Array[int] = [1, 2, 3, 4, 5, 6]
	assert_array(DiceRules.reroll_indices(faces, DiceRules.RerollMode.FAILURES, 4, 0)) \
		.is_equal([0, 1, 2] as Array[int])
	assert_array(DiceRules.reroll_indices(faces, DiceRules.RerollMode.FAILURES, 4, 1)) \
		.is_equal([0, 1] as Array[int])


func test_reroll_failures_without_target_picks_nothing() -> void:
	var faces: Array[int] = [1, 2, 3]
	assert_array(DiceRules.reroll_indices(faces, DiceRules.RerollMode.FAILURES,
		DiceRules.TARGET_NONE, 0)).is_empty()


func test_reroll_ones_and_sixes_use_natural_faces() -> void:
	var faces: Array[int] = [1, 6, 3, 1, 6]
	assert_array(DiceRules.reroll_indices(faces, DiceRules.RerollMode.ONES, 4, 2)) \
		.is_equal([0, 3] as Array[int])
	# "Bane" (v3.5.1) forces rerolls of UNMODIFIED 6s — the modifier is ignored.
	assert_array(DiceRules.reroll_indices(faces, DiceRules.RerollMode.SIXES, 4, -3)) \
		.is_equal([1, 4] as Array[int])


func test_reroll_all() -> void:
	assert_array(DiceRules.reroll_indices([2, 4] as Array[int], DiceRules.RerollMode.ALL,
		DiceRules.TARGET_NONE, 0)).is_equal([0, 1] as Array[int])
	assert_array(DiceRules.reroll_indices([] as Array[int], DiceRules.RerollMode.ALL, 4, 0)).is_empty()

# ===== reroll_mode_label =====


func test_reroll_mode_labels() -> void:
	assert_str(DiceRules.reroll_mode_label(DiceRules.RerollMode.FAILURES)).is_equal("fails")
	assert_str(DiceRules.reroll_mode_label(DiceRules.RerollMode.ONES)).is_equal("1s")
	assert_str(DiceRules.reroll_mode_label(DiceRules.RerollMode.SIXES)).is_equal("6s")
	assert_str(DiceRules.reroll_mode_label(DiceRules.RerollMode.ALL)).is_equal("all")
	assert_str(DiceRules.reroll_mode_label(DiceRules.REROLL_NONE)).is_empty()
