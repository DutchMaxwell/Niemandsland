extends GdUnitTestSuite
## A13 (Map editor plan): the grep gate for the Map editor + Terrain shelf restyle (UI inventory rows 41, 42).
## Done = no HudTokens, no scene paint overrides, and every code-side paint override is a HouseStyle token.
## Layout-only overrides (separation / margins: add_theme_constant_override, theme_override_constants) are
## allowed - HouseStyle's own builders use them. Terrain-type colours are data (TERRAIN_COLORS), not overrides.
## Behaviour is pinned by test/e2e/e2e_map_editor_inventory_test.gd.

const SCRIPTS := ["res://scripts/map_layout.gd", "res://scripts/sandbox_terrain_shelf.gd", "res://scripts/map_layout_grid.gd"]
const SCENE := "res://scenes/map_layout.tscn"
const PAINT := ["add_theme_color_override", "add_theme_font_override", "add_theme_font_size_override", "add_theme_stylebox_override"]


func _lines(path: String) -> PackedStringArray:
	return FileAccess.get_file_as_string(path).split("\n")


func test_a13_no_hud_tokens_in_the_map_editor_or_the_shelf() -> void:
	for path in SCRIPTS + [SCENE]:
		for i in _lines(path).size():
			assert_bool(_lines(path)[i].contains("HudTokens")) \
				.override_failure_message("A13 — %s:%d still uses HudTokens" % [path, i + 1]).is_false()


func test_a13_scene_has_no_paint_overrides() -> void:
	for i in _lines(SCENE).size():
		var l := _lines(SCENE)[i]
		var paint := l.contains("theme_override_colors") or l.contains("theme_override_fonts") \
			or l.contains("theme_override_font_sizes") or l.contains("theme_override_styles")
		assert_bool(paint).override_failure_message("A13 — map_layout.tscn:%d has a paint override: %s" % [i + 1, l]).is_false()


func test_a13_code_side_paint_overrides_are_house_tokens_only() -> void:
	for path in SCRIPTS:
		for i in _lines(path).size():
			var l := _lines(path)[i]
			for p in PAINT:
				if l.contains(p + "("):
					assert_bool(l.contains("HouseStyle.")) \
						.override_failure_message("A13 — %s:%d paints with a non-token value: %s" % [path, i + 1, l.strip_edges()]).is_true()


func test_a13_canvas_and_shelf_use_no_default_font_or_window() -> void:
	assert_bool(FileAccess.get_file_as_string("res://scripts/map_layout_grid.gd").contains("ThemeDB.fallback_font")).is_false()
	assert_str(FileAccess.get_file_as_string("res://scripts/sandbox_terrain_shelf.gd")).not_contains("extends Window")
