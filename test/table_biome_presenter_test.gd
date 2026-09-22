extends GdUnitTestSuite
## TableBiomePresenter (display only): table ids map onto the reference profiles, and the dressing stays
## off where it must (headless CI runs, the master switch). Lifecycle on the real table: see the e2e suite.

const TableScript := preload("res://scripts/table.gd")
const Biomes := preload("res://scripts/visual/reference_biomes.gd")


func test_every_table_biome_maps_to_its_own_reference_profile() -> void:
	for table_id in TableScript.BIOMES:
		var reference_id := TableBiomePresenter.reference_biome(table_id)
		# get_profile falls back to grassland for unknown ids, so compare the profile's own name.
		assert_str(str(Biomes.get_profile(reference_id)["name"])) \
			.override_failure_message("table biome %s has no reference profile of its own (got %s)" % [table_id, reference_id]) \
			.is_equal(reference_id)
	assert_str(TableBiomePresenter.reference_biome("temperate_grassland")).is_equal("grassland")
	assert_str(TableBiomePresenter.reference_biome("urban_ruins")).is_equal("urban_ruins")


func test_headless_and_switched_off_runs_are_not_dressed() -> void:
	var presenter: TableBiomePresenter = auto_free(TableBiomePresenter.new())
	var table: Node3D = auto_free(TableScript.new())   # never added to the tree: only table_size is read
	presenter.set("_table", table)
	assert_bool(presenter.should_dress()).is_false()   # gdUnit runs headless
	presenter.allow_headless = true
	assert_bool(presenter.should_dress()).is_true()
	presenter.enabled = false
	assert_bool(presenter.should_dress()).is_false()


func test_density_follows_preset_and_caps_large_tables() -> void:
	# Performance (0) and Low (1) are not dressed: today's battlemap table.
	assert_float(TableBiomePresenter.density_for(0, Vector2(6, 4))).is_equal(0.0)
	assert_float(TableBiomePresenter.density_for(1, Vector2(6, 4))).is_equal(0.0)
	# Medium on 6x4 and on a smaller table: the full table-tier density.
	assert_float(TableBiomePresenter.density_for(2, Vector2(6, 4))).is_equal_approx(1.0, 0.0001)
	assert_float(TableBiomePresenter.density_for(2, Vector2(4, 4))).is_equal_approx(1.0, 0.0001)
	# 240 x 240 in (20 x 20 ft): 16.7x the 6x4 area -> density falls so the instance count stays at 6x4's.
	var big := TableBiomePresenter.density_for(2, Vector2(20, 20))
	assert_float(big * 20.0 * 20.0).is_equal_approx(1.0 * 6.0 * 4.0, 0.001)
