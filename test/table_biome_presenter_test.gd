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
	presenter.set("_table", Node3D.new())
	assert_bool(presenter.should_dress()).is_false()   # gdUnit runs headless
	presenter.allow_headless = true
	assert_bool(presenter.should_dress()).is_true()
	presenter.enabled = false
	assert_bool(presenter.should_dress()).is_false()
	presenter.get("_table").free()
