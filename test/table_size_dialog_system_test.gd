extends GdUnitTestSuite
## PLAN_GAME_SYSTEM_SWITCH step 10: the table-setup dialog offers only the biomes the selected game system offers
## (assets/terrain_systems.json): a fantasy table has no urban ruins and no alien jungle. A hidden biome is never selected;
## a selection that became hidden falls back to the first biome on offer. gf (the default) offers the six it always did.
## Red proof: on main there was no system on the dialog - an aofs table showed urban ruins.

var dialog: TableSizeDialog


func before_test() -> void:
	dialog = auto_free(TableSizeDialog.new())
	add_child(dialog)


func _visible() -> Array:
	return dialog._biome_buttons.keys().filter(func(k: String) -> bool: return dialog._biome_buttons[k].visible)


func test_the_default_system_offers_all_six_biomes() -> void:
	assert_str(dialog.selected_system).is_equal("gf")
	assert_int(_visible().size()).is_equal(6)


func test_a_fantasy_table_loses_the_grimdark_only_biomes() -> void:
	for system in ["aof", "aofs", "aofr"]:
		dialog.set_system(system)
		assert_array(_visible()).contains_exactly_in_any_order(["temperate_grassland", "arid_desert", "frozen_tundra", "volcanic_ash"])
		assert_bool(dialog._biome_buttons.urban_ruins.visible).override_failure_message("%s shows urban ruins" % system).is_false()
		dialog._select_biome("alien_jungle")
		assert_str(dialog.selected_biome).override_failure_message("a hidden biome was selected").is_not_equal("alien_jungle")


func test_a_grimdark_table_keeps_all_of_them() -> void:
	dialog.set_system("aofs")
	dialog.set_system("gff")
	assert_int(_visible().size()).is_equal(6)
	dialog._select_biome("urban_ruins")
	assert_str(dialog.selected_biome).is_equal("urban_ruins")


func test_a_selection_that_became_hidden_falls_back_to_the_first_on_offer() -> void:
	dialog._select_biome("urban_ruins")
	dialog.set_system("aof")
	assert_str(dialog.selected_biome).is_equal("temperate_grassland")   # first on offer in the dialog's order
	assert_bool(dialog._create.disabled).is_false()   # the dialog is still confirmable
	dialog._select_biome("arid_desert")
	dialog.set_system("aofs")   # a selection that stays on offer stays
	assert_str(dialog.selected_biome).is_equal("arid_desert")


func test_the_system_filter_sits_on_top_of_the_callers_list() -> void:
	dialog.set_biomes(["grassland", "alien_jungle", "urban_ruins"], "grassland")   # the caller offers three
	dialog.set_system("aofs")
	assert_array(_visible()).is_equal(["temperate_grassland"])
	assert_str(dialog.selected_biome).is_equal("temperate_grassland")


func test_an_unknown_system_folds_to_the_default() -> void:
	dialog.set_system("nonsense")
	assert_str(dialog.selected_system).is_equal("gf")
