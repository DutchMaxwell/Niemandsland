extends GdUnitTestSuite
## The menu's pages draw their buttons at the mockups' scale (house.css .btn 17 px weight 500 with 18 px side
## padding, .btn.primary the same at weight 600), not at the table's (14-15 px regular, 6 px side padding). Gap
## review 27.11.: "Prepare table", "Start", "Load", "Create table" read small and thin on five pages; the one
## cause is menu_theme(), which raised the size but kept theme()'s regular font and 6 px boxes.


func _button(theme: Theme, variant: StringName) -> Button:
	var holder: Control = auto_free(Control.new())
	holder.theme = theme
	add_child(holder)
	var b := HouseStyle.button("Prepare table", variant, HouseStyle.MENU_H_ACTION)
	holder.add_child(b)
	return b


func _weight(b: Button) -> int:
	var f := b.get_theme_font(&"font") as FontVariation
	if f == null:
		return 400
	return int(f.variation_opentype.get(TextServerManager.get_primary_interface().name_to_tag("wght"), 400))


func test_the_menus_gold_action_is_large_semibold_and_padded() -> void:
	var b := _button(HouseStyle.menu_theme(), HouseStyle.PRIMARY)
	assert_int(b.get_theme_font_size(&"font_size")).is_equal(17)
	assert_int(_weight(b)).is_equal(600)
	assert_float(b.get_theme_stylebox(&"normal").content_margin_left).is_equal(18.0)
	assert_float(b.get_theme_stylebox(&"hover").content_margin_right).is_equal(18.0)


func test_the_menus_ghost_button_is_medium_and_padded() -> void:
	for variant: StringName in [HouseStyle.BUTTON, HouseStyle.DANGER_BUTTON]:
		var b := _button(HouseStyle.menu_theme(), variant)
		assert_int(b.get_theme_font_size(&"font_size")).is_equal(17)
		assert_int(_weight(b)).is_equal(500)
		assert_float(b.get_theme_stylebox(&"normal").content_margin_left).is_equal(18.0)


func test_a_menu_segment_has_room_beside_its_text() -> void:
	var b := _button(HouseStyle.menu_theme(), HouseStyle.SEGMENT)
	assert_float(b.get_theme_stylebox(&"normal").content_margin_left).is_equal(16.0)


func test_the_tables_windows_keep_their_scale() -> void:
	var b := _button(HouseStyle.theme(), HouseStyle.PRIMARY)
	assert_int(b.get_theme_font_size(&"font_size")).is_equal(HouseStyle.FONT_ACTION)
	assert_float(b.get_theme_stylebox(&"normal").content_margin_left).is_equal(float(HouseStyle.PAD_BUTTON_X))


func test_icon_buttons_keep_no_side_padding() -> void:
	var b := _button(HouseStyle.menu_theme(), HouseStyle.ICON)
	assert_float(b.get_theme_stylebox(&"normal").content_margin_left).is_equal(0.0)


## A menu dropdown's arrow is the thin 12 px chevron of the mockups, 14 px from the edge (gap review 27.11.: about 24 px
## bold on 03b, the engine's small arrow on 05; red before).
func test_a_menu_dropdown_has_the_thin_chevron() -> void:
	var holder: Control = auto_free(Control.new())
	holder.theme = HouseStyle.menu_theme()
	add_child(holder)
	for variation: StringName in [&"", HouseStyle.BUTTON]:
		var pick := OptionButton.new()
		pick.theme_type_variation = variation
		holder.add_child(pick)
		var arrow := pick.get_theme_icon(&"arrow")
		assert_int(arrow.get_width()).is_less_equal(14)
		assert_object(arrow).is_same(HouseStyle.menu_theme().get_icon(&"arrow", &"OptionButton"))
		assert_int(pick.get_theme_constant(&"arrow_margin")).is_equal(14)
