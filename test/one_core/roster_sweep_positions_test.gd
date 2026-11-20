extends GdUnitTestSuite
## The roster sweep's position compare (`RosterSweep.positions_near`): a formation is the same formation whichever slot each model sits in. `_pos`
## sorts by x, and two mirror models of a formation are equal in x up to float noise, so the table half and the core half could list them in swapped
## order; the old index-by-index compare then paired the wrong two (a false 2.5" difference for models 0.00004" apart, the 6 `foe` rows of the 20.11.
## melee census). Pure function, no scene.

const RosterSweep := preload("res://test/one_core/roster_sweep.gd")


func test_mirror_models_listed_in_swapped_order_are_the_same_formation() -> void:
	# The census rows: the table lists (-1.27) first, the core's float noise put its (+1.27) model first. RED on the index-by-index compare.
	var table := [Vector2(5.976993, -1.266022), Vector2(5.976993, 1.266022), Vector2(7.0, 0.0)]
	var core := [Vector2(5.976949, 1.265998), Vector2(5.977009, -1.266047), Vector2(7.0, 0.0)]
	assert_bool(RosterSweep.positions_near(table, core)).is_true()
	assert_bool(RosterSweep.positions_near(core, table)).is_true()


func test_a_real_shift_a_missing_model_and_a_far_model_still_differ() -> void:
	var base := [Vector2(5.0, 1.0), Vector2(5.0, -1.0)]
	assert_bool(RosterSweep.positions_near(base, [Vector2(5.0, -1.0), Vector2(5.0, 1.0)])).is_true()
	assert_bool(RosterSweep.positions_near(base, [Vector2(5.0, 1.0), Vector2(5.0, -0.98)])).is_false()
	assert_bool(RosterSweep.positions_near(base, [Vector2(5.0, 1.0)])).is_false()
	assert_bool(RosterSweep.positions_near(base, [Vector2(5.0, 1.0), Vector2(5.0, 1.0)])).is_false()
	assert_bool(RosterSweep.positions_near([], [])).is_true()
