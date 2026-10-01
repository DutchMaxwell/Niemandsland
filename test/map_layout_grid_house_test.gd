extends GdUnitTestSuite
## A9 (Map editor plan): the canvas chrome (table background, cell borders, grid lines, table edge, centre
## dot, symmetry axes, size label) takes its colours from HouseStyle tokens through named consts at the top
## of map_layout_grid.gd, and its label uses the house font - no colour literals in _draw / _draw_fine_grid.

const PATH := "res://scripts/map_layout_grid.gd"


func _func_source(fn: String) -> String:
	var text := FileAccess.get_file_as_string(PATH)
	var start := text.find("func %s(" % fn)
	var end := text.find("\nfunc ", start + 1)
	return text.substr(start, (end if end >= 0 else text.length()) - start)


func test_a9_draw_and_fine_grid_hold_no_colour_literals_or_fallback_font() -> void:
	for fn in ["_draw", "_draw_fine_grid"]:
		var src := _func_source(fn)
		assert_str(src).is_not_empty()
		for needle in ["Color(", "Color.WHITE", "ThemeDB.fallback_font"]:
			assert_bool(src.contains(needle)) \
				.override_failure_message("A9 — %s still contains %s" % [fn, needle]).is_false()


func test_a9_chrome_consts_are_house_tokens() -> void:
	var grid: Script = load(PATH)
	var consts: Dictionary = grid.get_script_constant_map()
	assert_bool(consts.has("GRID_BACKGROUND")).override_failure_message("A9 — no GRID_BACKGROUND const").is_true()
	if not consts.has("GRID_BACKGROUND"):
		return
	assert_bool(consts["GRID_BACKGROUND"] == HouseStyle.SHEET_FILL).is_true()
	assert_bool(consts["TABLE_EDGE"] == HouseStyle.INK).is_true()
	assert_bool(consts["RELIC_RING"] == HouseStyle.GOLD).is_true()
	assert_bool(consts["LABEL_INK"] == HouseStyle.INK).is_true()
