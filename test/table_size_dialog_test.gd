extends GdUnitTestSuite
const TableScript := preload("res://scripts/table.gd")
var dialog: TableSizeDialog
var selections: Array[Vector2]
var cancellations: Array[bool]
func before_test() -> void:
	selections = []
	cancellations = []
	dialog = auto_free(TableSizeDialog.new())
	add_child(dialog)
	dialog.size_chosen.connect(func(value: Vector2) -> void: selections.append(value))
	dialog.cancelled.connect(func() -> void: cancellations.append(true))
func test_selection_does_not_create_a_table() -> void:
	dialog._select_size("square")
	dialog._select_biome("alien_jungle")
	assert_int(selections.size()).is_equal(0)
	assert_vector(dialog.chosen_inches()).is_equal(Vector2(48,48))
	assert_str(dialog.selected_biome).is_equal("alien_jungle")
func test_create_emits_selected_feet_exactly_once() -> void:
	dialog._select_size("square")
	dialog._confirm()
	dialog._confirm()
	dialog._on_close()
	assert_int(selections.size()).is_equal(1)
	assert_vector(selections[0]).is_equal(Vector2(4,4))
	assert_int(cancellations.size()).is_equal(0)
func test_cancel_never_confirms_default_size() -> void:
	dialog._select_size("custom")
	dialog._on_close()
	dialog._on_close()
	assert_int(cancellations.size()).is_equal(1)
	assert_int(selections.size()).is_equal(0)
func test_unit_switch_preserves_physical_size_and_custom_values() -> void:
	dialog._select_size("custom")
	dialog._width_input.text = "100"
	dialog._length_input.text = "60"
	dialog._on_dimensions_edited("")
	for i in 5:
		dialog._unit_option.select(1)
		dialog._on_units_changed(1)
		assert_str(dialog._width_input.text).is_equal("254")
		assert_str(dialog._length_input.text).is_equal("152.4")
		dialog._unit_option.select(0)
		dialog._on_units_changed(0)
	assert_vector(dialog.chosen_inches()).is_equal(Vector2(100,60))
	dialog._select_size("standard")
	dialog._select_size("custom")
	assert_vector(dialog.chosen_inches()).is_equal(Vector2(100,60))
func test_invalid_input_disables_create_without_silent_clamping() -> void:
	dialog._select_size("custom")
	for text in ["","abc","11.9","241","nan","inf"]:
		dialog._width_input.text = text
		dialog._on_dimensions_edited("")
		dialog._confirm()
		assert_bool(dialog._create.disabled).is_true()
	assert_int(selections.size()).is_equal(0)
func test_centimeter_limits_match_inches_and_accept_decimal_comma() -> void:
	dialog._select_size("custom")
	dialog._unit_option.select(1)
	dialog._on_units_changed(1)
	dialog._width_input.text = "30,48"
	dialog._length_input.text = "609.6"
	dialog._on_dimensions_edited("")
	assert_bool(dialog._create.disabled).is_false()
	dialog._confirm()
	assert_int(selections.size()).is_equal(1)
	assert_vector(selections[0]).is_equal(Vector2(1,20))
func test_unavailable_biomes_cannot_be_selected() -> void:
	dialog.set_biomes(["grassland","alien_jungle"],"grassland")
	dialog._select_biome("urban_ruins")
	assert_str(dialog.selected_biome).is_equal("temperate_grassland")
	assert_bool(dialog._biome_buttons.urban_ruins.visible).is_false()
func test_menu_ids_become_table_ids() -> void:
	# The menu hands over the diorama's ids (startup_menu.gd); the selection goes straight into
	# table.set_biome, which only knows table.gd's ids — "grassland" was rejected there.
	dialog.set_biomes(["urban_ruins","alien_jungle","grassland","arid_desert","frozen_tundra","volcanic_ash"],"grassland")
	assert_str(dialog.selected_biome).is_equal("temperate_grassland")
	assert_int(dialog._biome_keys.size()).is_equal(6)
	for key in dialog._biome_keys:
		assert_bool(TableScript.BIOMES.has(key)).override_failure_message("chooser id %s is unknown to the table" % key).is_true()
	assert_object(dialog._preview.texture).is_not_null()
func test_direct_start_offers_all_six_table_biomes() -> void:
	# main.gd's fallback chooser passes the table's own ids; grassland must not drop out.
	dialog.set_biomes(TableScript.BIOMES,"temperate_grassland")
	assert_int(dialog._biome_keys.size()).is_equal(6)
	assert_str(dialog.selected_biome).is_equal("temperate_grassland")
func test_footprint_follows_dimensions_without_changing_biome_image() -> void:
	var texture := dialog._preview.texture
	dialog._select_size("square")
	assert_vector(dialog._footprint.inches).is_equal(Vector2(48,48))
	assert_object(dialog._preview.texture).is_same(texture)
