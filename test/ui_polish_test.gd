extends GdUnitTestSuite
## Shared UI polish tokens + helpers (UiPolish), the basis for matching the rest of
## the UI to the polished reference screens.


func test_tokens_are_distinct() -> void:
	assert_bool(UiPolish.ACCENT == UiPolish.SUCCESS).is_false()
	assert_bool(UiPolish.DESTRUCTIVE == UiPolish.WARNING).is_false()


func test_hex_is_six_digits_no_hash() -> void:
	assert_str(UiPolish.hex(Color(1, 0, 0))).is_equal("ff0000")


func test_set_dialog_margins_applies_all_sides() -> void:
	var m: MarginContainer = auto_free(MarginContainer.new())
	UiPolish.set_dialog_margins(m, 18)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		assert_int(m.get_theme_constant(side)).is_equal(18)


func test_primary_button_sets_height_keeps_width() -> void:
	var b: Button = auto_free(Button.new())
	b.custom_minimum_size = Vector2(120, 0)
	UiPolish.primary_button(b)
	assert_int(int(b.custom_minimum_size.x)).is_equal(120)
	assert_int(int(b.custom_minimum_size.y)).is_equal(UiPolish.BUTTON_HEIGHT)


func test_sunken_panel_style_is_rounded_glass() -> void:
	var s := UiPolish.sunken_panel_style()
	assert_int(s.corner_radius_top_left).is_equal(12)
	assert_int(s.border_width_left).is_greater(0)
