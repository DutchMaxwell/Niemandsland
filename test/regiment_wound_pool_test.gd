extends GdUnitTestSuite
## Regiment pooled-tough wound counter: pure static logic. A regiment is treated as a
## single Tough(pool_max) entity for the wound counter (AoF:R v3.5.1 p.9 "Remove
## Casualties" — models are removed from the back rank). No nodes, no network.


# ===== pool_max =====


func test_pool_max_sums_tough_values() -> void:
	# 10 Tough(1) models -> pool 10.
	assert_int(Regiment.pool_max([1, 1, 1, 1, 1, 1, 1, 1, 1, 1])).is_equal(10)
	# A Tough(2) hero + 9 Tough(1) squadmates -> pool 11.
	assert_int(Regiment.pool_max([2, 1, 1, 1, 1, 1, 1, 1, 1, 1])).is_equal(11)
	# A Tough(3) monster alone -> pool 3.
	assert_int(Regiment.pool_max([3])).is_equal(3)


func test_pool_max_empty_is_zero() -> void:
	assert_int(Regiment.pool_max([])).is_equal(0)


func test_pool_max_clamps_zero_tough_to_one() -> void:
	# A model without Tough parses as 0; the counter treats it as Tough(1).
	assert_int(Regiment.pool_max([0, 0])).is_equal(2)


# ===== is_pooled_tough1 =====


func test_is_pooled_tough1_all_ones_is_true() -> void:
	assert_bool(Regiment.is_pooled_tough1([1, 1, 1, 1, 1, 1, 1, 1, 1, 1])).is_true()


func test_is_pooled_tough1_with_tough2_is_false() -> void:
	# A Tough(2) hero in a Tough(1) squad -> classic per-model wounds, not pooled.
	assert_bool(Regiment.is_pooled_tough1([2, 1, 1, 1, 1, 1, 1, 1, 1, 1])).is_false()


func test_is_pooled_tough1_all_tough2_is_false() -> void:
	assert_bool(Regiment.is_pooled_tough1([2, 2, 2])).is_false()


func test_is_pooled_tough1_empty_is_false() -> void:
	assert_bool(Regiment.is_pooled_tough1([])).is_false()


func test_is_pooled_tough1_single_tough1_is_true() -> void:
	assert_bool(Regiment.is_pooled_tough1([1])).is_true()


# ===== alive_mask_for_wounds =====


func test_alive_mask_no_wounds_all_alive() -> void:
	# 10 Tough(1) models, 0 wounds -> all alive.
	var mask := Regiment.alive_mask_for_wounds([1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 0)
	assert_int(mask.size()).is_equal(10)
	for alive in mask:
		assert_bool(alive).is_true()


func test_alive_mask_tough1_two_wounds_kills_back_two() -> void:
	# 10 Tough(1) models, 2 wounds -> back 2 dead, front 8 alive (index 0 = front).
	var mask := Regiment.alive_mask_for_wounds([1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 2)
	assert_bool(mask[9]).is_false()  # rearmost dead
	assert_bool(mask[8]).is_false()  # second-rearmost dead
	assert_bool(mask[7]).is_true()   # rest alive
	assert_bool(mask[0]).is_true()


func test_alive_mask_tough2_two_wounds_kills_one_model() -> void:
	# 10 Tough(2) models, 2 wounds -> only the rearmost dies (2 wounds = 1 Tough(2) model).
	var mask := Regiment.alive_mask_for_wounds([2, 2, 2, 2, 2, 2, 2, 2, 2, 2], 2)
	assert_bool(mask[9]).is_false()
	assert_bool(mask[8]).is_true()


func test_alive_mask_tough2_three_wounds_kills_one_and_wounds_next() -> void:
	# 10 Tough(2), 3 wounds: model[9] dead (2 wounds), model[8] wounded (1/2) but alive.
	var mask := Regiment.alive_mask_for_wounds([2, 2, 2, 2, 2, 2, 2, 2, 2, 2], 3)
	assert_bool(mask[9]).is_false()
	assert_bool(mask[8]).is_true()
	assert_bool(mask[0]).is_true()


func test_alive_mask_mixed_tough_back_dies_first() -> void:
	# Front Tough(2) hero, 9 Tough(1) squadmates behind. 3 wounds: back 3 squadmates dead.
	var toughs := [2, 1, 1, 1, 1, 1, 1, 1, 1, 1]
	var mask := Regiment.alive_mask_for_wounds(toughs, 3)
	assert_bool(mask[9]).is_false()
	assert_bool(mask[8]).is_false()
	assert_bool(mask[7]).is_false()
	assert_bool(mask[6]).is_true()
	# The front hero (index 0) survives (3 wounds absorbed by 3 squadmates).
	assert_bool(mask[0]).is_true()


func test_alive_mask_full_pool_all_dead() -> void:
	var toughs := [1, 1, 1, 1, 1]
	var mask := Regiment.alive_mask_for_wounds(toughs, 5)
	for alive in mask:
		assert_bool(alive).is_false()


func test_alive_mask_overkill_clamps_to_all_dead() -> void:
	# More wounds than the pool -> everyone dead (no negative wraparound).
	var mask := Regiment.alive_mask_for_wounds([1, 1, 1], 99)
	for alive in mask:
		assert_bool(alive).is_false()


# ===== wounds_on_model =====


func test_wounds_on_model_tough1_alive_is_zero() -> void:
	# 10 Tough(1), 2 wounds: model[0] (front) has 0 wounds.
	assert_int(Regiment.wounds_on_model([1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 2, 0)).is_equal(0)


func test_wounds_on_model_tough1_dead_model_has_one_wound() -> void:
	# model[9] (rear) is dead (1 wound on it = its full Tough).
	assert_int(Regiment.wounds_on_model([1, 1, 1, 1, 1, 1, 1, 1, 1, 1], 2, 9)).is_equal(1)


func test_wounds_on_model_tough2_partial_wound() -> void:
	# 10 Tough(2), 3 wounds: model[8] has 1 wound (alive), model[9] has 2 (dead).
	assert_int(Regiment.wounds_on_model([2, 2, 2, 2, 2, 2, 2, 2, 2, 2], 3, 8)).is_equal(1)
	assert_int(Regiment.wounds_on_model([2, 2, 2, 2, 2, 2, 2, 2, 2, 2], 3, 9)).is_equal(2)


func test_wounds_on_model_out_of_range_is_zero() -> void:
	assert_int(Regiment.wounds_on_model([1, 1, 1], 1, 5)).is_equal(0)
	assert_int(Regiment.wounds_on_model([1, 1, 1], 1, -1)).is_equal(0)


# ===== to_dict round-trip =====


func test_to_dict_persists_wounds_taken() -> void:
	var reg := Regiment.new()
	reg.frontage = 5
	reg.wounds_taken = 3
	var d := reg.to_dict()
	assert_int(d["frontage"]).is_equal(5)
	assert_int(d["wounds_taken"]).is_equal(3)
