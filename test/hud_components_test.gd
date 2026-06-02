extends GdUnitTestSuite
## HudFrame + SegmentedMeter — the tactical-HUD drawing building blocks.


func test_bracket_len_clamps_to_short_side() -> void:
	# Fits when there is room; clamps to 45% of the shorter side when cramped.
	assert_float(HudFrame.bracket_len(14.0, Vector2(200, 100))).is_equal_approx(14.0, 0.001)
	assert_float(HudFrame.bracket_len(14.0, Vector2(20, 20))).is_equal_approx(9.0, 0.001)


func test_hud_frame_ignores_mouse() -> void:
	var f: HudFrame = auto_free(HudFrame.new())
	add_child(f)  # triggers _ready
	assert_int(f.mouse_filter).is_equal(Control.MOUSE_FILTER_IGNORE)


func test_cell_width_accounts_for_gaps() -> void:
	# 3 cells, 2 gaps of 4px in 100px -> (100 - 8) / 3.
	assert_float(SegmentedMeter.cell_width(100.0, 3, 4.0)).is_equal_approx(92.0 / 3.0, 0.001)
	assert_float(SegmentedMeter.cell_width(50.0, 0, 4.0)).is_equal(0.0)


func test_meter_filled_clamps_to_segments() -> void:
	var m: SegmentedMeter = auto_free(SegmentedMeter.new())
	m.segments = 3
	m.filled = 5
	assert_int(m.filled).is_equal(3)
	m.filled = -2
	assert_int(m.filled).is_equal(0)


func test_meter_reducing_segments_reclamps_filled() -> void:
	var m: SegmentedMeter = auto_free(SegmentedMeter.new())
	m.segments = 5
	m.filled = 4
	m.segments = 2
	assert_int(m.filled).is_equal(2)
