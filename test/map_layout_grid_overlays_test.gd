extends GdUnitTestSuite
## A10 (Map editor plan): the canvas overlays (deployment zones P1 = accent / P2 = danger, snap points,
## objectives, distance warnings, walls, placed objects, piece preview and selection outline) take their
## colours from HouseStyle tokens and their text from the house font - no colour literals, no Open Sans.
## Terrain-type fills stay data (TERRAIN_COLORS in map_layout.gd).

const PATH := "res://scripts/map_layout_grid.gd"
const FUNCS := ["_draw_deployment_zones", "_draw_custom_zones", "_draw_boundary_snap_points", "_draw_mission_objectives",
	"_draw_sandbox_terrain", "_draw_objective_distance_warnings", "_draw_wall_segments", "_draw_placed_objects",
	"_draw_prefab_preview", "_draw_selected_piece_outline"]


func _func_source(fn: String) -> String:
	var text := FileAccess.get_file_as_string(PATH)
	var start := text.find("func %s(" % fn)
	var end := text.find("\nfunc ", start + 1)
	return text.substr(start, (end if end >= 0 else text.length()) - start)


func test_a10_overlay_functions_hold_no_raw_colours_or_fallback_font() -> void:
	var raw := RegEx.create_from_string("Color\\((?!HouseStyle\\.|OBJECTIVE)")
	for fn in FUNCS:
		var src := _func_source(fn)
		assert_str(src).override_failure_message("%s not found" % fn).is_not_empty()
		assert_bool(raw.search(src) != null).override_failure_message("A10 — %s has a raw Color( literal" % fn).is_false()
		for needle in ["Color.WHITE", "ThemeDB.fallback_font"]:
			assert_bool(src.contains(needle)).override_failure_message("A10 — %s still contains %s" % [fn, needle]).is_false()


func test_a10_player_zones_are_accent_and_danger() -> void:
	var consts: Dictionary = (load(PATH) as Script).get_script_constant_map()
	assert_bool(consts.has("ZONE_FILL_P1") and consts.has("ZONE_EDGE_P2")).override_failure_message("A10 — no zone consts").is_true()
	if not consts.has("ZONE_FILL_P1"):
		return
	assert_bool(Color(consts["ZONE_EDGE_P1"], 1.0) == Color(HouseStyle.ACCENT, 1.0)).is_true()
	assert_bool(Color(consts["ZONE_EDGE_P2"], 1.0) == Color(HouseStyle.DANGER, 1.0)).is_true()
	assert_bool(consts["OBJECTIVE"] == HouseStyle.GOLD).is_true()
