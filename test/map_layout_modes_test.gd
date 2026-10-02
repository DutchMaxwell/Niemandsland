extends GdUnitTestSuite
## R1 (Map editor plan): the mode is four visible segments (Paint / Walls / Place / Move), the current one
## gold - no more cycle button. The editor opens in Place mode (what the 3D table renders) and the eraser
## ("Erase", formerly "None") is never pre-selected.

const SCENE := preload("res://scenes/map_layout.tscn")
const NAMES := ["ModePaintButton", "ModeWallsButton", "ModePlaceButton", "ModeMoveButton"]

var _ed: Control


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	await get_tree().process_frame


func after_test() -> void:
	_ed = null


func _btn(n: String) -> Button:
	return _ed.find_child(n, true, false) as Button


func _selected() -> Array:
	return NAMES.filter(func(n): return _btn(n) != null and HouseStyle.is_selected(_btn(n)))


func test_r1_four_mode_segments_exactly_one_selected() -> void:
	for n in NAMES:
		var b := _btn(n)
		assert_object(b).override_failure_message("R1 — %s missing" % n).is_not_null()
		if b != null:
			assert_str(String(b.theme_type_variation).trim_suffix(HouseStyle.SELECTED_SUFFIX)).is_equal(String(HouseStyle.SEGMENT))
	assert_array(_selected()).contains_exactly(["ModePlaceButton"])


func test_r1_each_segment_sets_its_mode_and_moves_the_gold() -> void:
	var expect := {"ModePaintButton": _ed.EditorMode.PAINT_CELLS, "ModeWallsButton": _ed.EditorMode.PLACE_WALLS,
		"ModePlaceButton": _ed.EditorMode.PLACE_PREFAB, "ModeMoveButton": _ed.EditorMode.MOVE_PIECES}
	for n in ["ModeMoveButton", "ModePaintButton", "ModeWallsButton", "ModePlaceButton"]:  # Move -> Paint is ONE click
		if _btn(n) != null:
			_btn(n).pressed.emit()
		assert_int(_ed.editor_mode).is_equal(expect[n])
		assert_array(_selected()).contains_exactly([n])


func test_r1_old_cycle_button_is_gone() -> void:
	for b: Node in _ed.find_children("*", "Button", true, false):
		assert_bool((b as Button).text.begins_with("Mode:")).override_failure_message("R1 — the old 'Mode: ...' cycle button is still there").is_false()
	assert_bool(_ed.has_method("_on_editor_mode_toggled")).is_false()


func test_r1_opens_in_place_mode_with_the_eraser_not_selected() -> void:
	assert_int(_ed.editor_mode).is_equal(_ed.EditorMode.PLACE_PREFAB)
	assert_bool(_ed.selected_terrain_type != _ed.TerrainType.NONE).is_true()
	assert_object(_ed.terrain_buttons.get_children().filter(func(b): return b.text == "None").front() if _ed.terrain_buttons.get_children().any(func(b): return b.text == "None") else null).is_null()
	var erase: Array = _ed.terrain_buttons.get_children().filter(func(b): return b.text == "Erase")
	assert_int(erase.size()).override_failure_message("R1 — no 'Erase' terrain button").is_equal(1)
	if erase.size() == 1:
		assert_bool((erase[0] as Button).button_pressed).is_false()
