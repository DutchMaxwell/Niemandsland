extends GdUnitTestSuite
## HudFrame + StatePanel — the tactical-HUD drawing building blocks.


func test_bracket_len_clamps_to_short_side() -> void:
	# Fits when there is room; clamps to 45% of the shorter side when cramped.
	assert_float(HudFrame.bracket_len(14.0, Vector2(200, 100))).is_equal_approx(14.0, 0.001)
	assert_float(HudFrame.bracket_len(14.0, Vector2(20, 20))).is_equal_approx(9.0, 0.001)


func test_hud_frame_ignores_mouse() -> void:
	var f: HudFrame = auto_free(HudFrame.new())
	add_child(f)  # triggers _ready
	assert_int(f.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_state_panel_modes_do_not_crash_and_show() -> void:
	var sp: StatePanel = auto_free(StatePanel.new())
	add_child(sp)
	sp.show_empty("NO DATA", "paste a link")
	assert_bool(sp.visible).is_true()
	sp.show_loading("LOADING", "fetching")
	assert_bool(sp.visible).is_true()
	sp.show_error("FAILED", "try again", "RETRY")
	assert_bool(sp.visible).is_true()
