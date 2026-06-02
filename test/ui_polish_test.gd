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
	# Delegates to HudTokens (single source of truth) — radius matches the token,
	# not the old glassmorphism radius of 12.
	var s := UiPolish.sunken_panel_style()
	assert_int(s.corner_radius_top_left).is_equal(HudTokens.RADIUS)
	assert_int(s.border_width_left).is_greater(0)


func test_tokens_delegate_to_hud_tokens() -> void:
	# UiPolish must not re-introduce a second palette; every token resolves to HudTokens.
	assert_bool(UiPolish.ACCENT == HudTokens.CYAN).is_true()
	assert_bool(UiPolish.DESTRUCTIVE == HudTokens.DANGER).is_true()
	assert_bool(UiPolish.TEXT_MUTED == HudTokens.TEXT_MUTED).is_true()


func test_clamped_size_shrinks_oversized_dialog() -> void:
	# A 900px-tall dialog must be clamped to fit a 720p viewport (reachability).
	var s := UiPolish.clamped_size(Vector2i(500, 900), Vector2(1280, 720))
	assert_int(s.x).is_equal(500)              # width already fits -> unchanged
	assert_int(s.y).is_equal(int(720 * 0.9))   # height clamped to 90% of the viewport


func test_clamped_size_leaves_fitting_dialog_untouched() -> void:
	var s := UiPolish.clamped_size(Vector2i(550, 450), Vector2(1280, 720))
	assert_int(s.x).is_equal(550)
	assert_int(s.y).is_equal(450)


func test_clamped_size_never_below_floor() -> void:
	# Even in a tiny viewport a dialog keeps a usable minimum.
	var s := UiPolish.clamped_size(Vector2i(550, 450), Vector2(200, 150))
	assert_int(s.x).is_equal(240)
	assert_int(s.y).is_equal(180)
