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


# === step 16: the size follows the system as a PRESELECT ===

func test_the_skirmish_books_start_on_four_by_four_the_battle_books_on_six_by_four() -> void:
	for system in ["gff", "aofs"]:
		dialog.set_system(system)
		assert_str(dialog.selected_size).override_failure_message("%s did not preselect square" % system).is_equal("square")
		assert_vector(dialog.chosen_inches()).is_equal(Vector2(48, 48))
	for system in ["gf", "aof", "aofr"]:
		dialog.set_system(system)
		assert_str(dialog.selected_size).override_failure_message("%s did not preselect standard" % system).is_equal("standard")
		assert_vector(dialog.chosen_inches()).is_equal(Vector2(72, 48))


func test_a_size_picked_after_the_system_wins() -> void:
	dialog.set_system("aofs")
	dialog._select_size("standard")
	assert_str(dialog.selected_size).is_equal("standard")
	dialog._select_size("custom")
	assert_str(dialog.selected_size).is_equal("custom")
	assert_vector(dialog.chosen_inches()).is_equal(Vector2(72, 48))   # the custom values are kept as they were
	dialog.set_system("gff")   # choosing a system again preselects its board again
	assert_str(dialog.selected_size).is_equal("square")


func test_a_skirmish_table_can_be_confirmed_as_four_by_four() -> void:
	var picked: Array[Vector2] = []
	dialog.size_chosen.connect(func(v: Vector2) -> void: picked.append(v))
	dialog.set_system("aofs")
	dialog._confirm()
	assert_int(picked.size()).is_equal(1)
	assert_vector(picked[0]).is_equal(Vector2(4, 4))


# === step 20a: the first row of the setup (the dropdown on the title line) ===

func test_the_game_system_row_lists_the_five_official_names_and_drives_the_dialog() -> void:
	var option: OptionButton = dialog._system_option
	assert_int(option.item_count).is_equal(5)
	for i in GameSystem.IDS.size():
		assert_str(option.get_item_text(i)).is_equal(GameSystem.label(GameSystem.IDS[i]))
	assert_str(dialog.selected_system).is_equal("gf")
	assert_int(option.selected).is_equal(0)
	option.select(3)   # Age of Fantasy: Skirmish
	option.item_selected.emit(3)
	assert_str(dialog.selected_system).is_equal("aofs")
	assert_str(dialog.selected_size).is_equal("square")
	assert_bool(dialog._biome_buttons.urban_ruins.visible).is_false()
	dialog.set_system("gff")   # set from code: the row follows
	assert_int(option.selected).is_equal(1)


func test_a_fantasy_dialog_with_four_biomes_still_fits_1280x720() -> void:
	var original := get_tree().root.size
	get_tree().root.size = Vector2i(1280, 720)
	var d: TableSizeDialog = auto_free(TableSizeDialog.new())
	add_child(d)
	d.set_system("aofs")
	for _i in 4:
		await get_tree().process_frame
	assert_float(d._page.get_combined_minimum_size().y).override_failure_message("the page needs scrolling").is_less_equal(d._scroll.size.y)
	assert_bool(Rect2(Vector2.ZERO, d.get_visible_rect().size).encloses(d._create.get_global_rect())).override_failure_message("Create is outside the window").is_true()
	get_tree().root.size = original
