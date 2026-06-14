extends GdUnitTestSuite
## RegimentFormation: ranks-and-files layout for Age of Fantasy: Regiments.
## Pure/static — no nodes, no network. See docs notes in regiment_formation.gd.

const CELL := 0.025  # 25mm square base


func _uniform(n: int) -> Array:
	var fps: Array = []
	for i in range(n):
		fps.append(Vector2(CELL, CELL))
	return fps


# ===== default_frontage =====


func test_default_frontage_follows_convention() -> void:
	assert_int(RegimentFormation.default_frontage(1)).is_equal(1)
	assert_int(RegimentFormation.default_frontage(5)).is_equal(5)
	assert_int(RegimentFormation.default_frontage(10)).is_equal(5)
	assert_int(RegimentFormation.default_frontage(3)).is_equal(3)
	assert_int(RegimentFormation.default_frontage(6)).is_equal(3)
	# 7 is neither /5 nor /3 -> capped at 5
	assert_int(RegimentFormation.default_frontage(7)).is_equal(5)


# ===== rank_count =====


func test_rank_count() -> void:
	assert_int(RegimentFormation.rank_count(10, 5)).is_equal(2)
	assert_int(RegimentFormation.rank_count(8, 5)).is_equal(2)
	assert_int(RegimentFormation.rank_count(5, 5)).is_equal(1)
	assert_int(RegimentFormation.rank_count(1, 1)).is_equal(1)


# ===== local_offsets =====


func test_ten_models_at_frontage_five_form_two_full_ranks() -> void:
	var offs := RegimentFormation.local_offsets(_uniform(10), 5)
	assert_int(offs.size()).is_equal(10)
	# Front rank (index 0) toward +Z, rear rank (-Z); two ranks => +/- half a cell.
	assert_float(offs[0].z).is_equal_approx(CELL / 2.0, 0.0001)
	assert_float(offs[5].z).is_equal_approx(-CELL / 2.0, 0.0001)
	# 5-wide centred: columns at -2..+2 cells.
	assert_float(offs[0].x).is_equal_approx(-2.0 * CELL, 0.0001)
	assert_float(offs[2].x).is_equal_approx(0.0, 0.0001)
	assert_float(offs[4].x).is_equal_approx(2.0 * CELL, 0.0001)
	# File alignment: model 5 sits directly behind model 0.
	assert_float(offs[5].x).is_equal_approx(offs[0].x, 0.0001)


func test_partial_rear_rank_is_centred() -> void:
	# 8 models @ 5 => front rank of 5, rear rank of 3 (centred on its own count).
	var offs := RegimentFormation.local_offsets(_uniform(8), 5)
	assert_int(offs.size()).is_equal(8)
	# Rear rank = indices 5,6,7 -> centred at columns -1,0,+1.
	assert_float(offs[5].x).is_equal_approx(-1.0 * CELL, 0.0001)
	assert_float(offs[6].x).is_equal_approx(0.0, 0.0001)
	assert_float(offs[7].x).is_equal_approx(1.0 * CELL, 0.0001)


func test_rerank_after_casualties_is_relayout() -> void:
	# Removing 2 from a 10-block (re-lay 8) shrinks the rear rank to 3.
	var offs := RegimentFormation.local_offsets(_uniform(8), 5)
	assert_int(offs.size()).is_equal(8)
	assert_int(RegimentFormation.rank_count(8, 5)).is_equal(2)


func test_single_large_model_is_one_block() -> void:
	var offs := RegimentFormation.local_offsets(_uniform(1), 1)
	assert_int(offs.size()).is_equal(1)
	assert_vector(offs[0]).is_equal(Vector3.ZERO)


func test_empty_returns_empty() -> void:
	assert_int(RegimentFormation.local_offsets([], 5).size()).is_equal(0)


func test_gap_widens_spacing() -> void:
	var offs := RegimentFormation.local_offsets(_uniform(2), 2, 0.01)
	# Two models side by side, cell = 25mm + 10mm gap = 35mm -> +/- 17.5mm.
	assert_float(offs[0].x).is_equal_approx(-0.0175, 0.0001)
	assert_float(offs[1].x).is_equal_approx(0.0175, 0.0001)
