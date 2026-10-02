extends GdUnitTestSuite
## R3 (Map editor plan): the header button says what it clears ("Clear terrain"), asks first in a house sheet
## that names what is and is not touched, and one Ctrl+Z brings the terrain back.

const SCENE := preload("res://scenes/map_layout.tscn")

var _ed: Control


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	await get_tree().process_frame
	_ed.place_prefab(TerrainPrefabs.keys()[0], Vector2i(10, 10), 0, false, false)
	_ed.free_cells[Vector2i(2, 2)] = _ed.TerrainType.FOREST
	_ed.mission_objectives.assign([Vector2(20, 20)])


func after_test() -> void:
	_ed = null


func test_r3_button_is_named_for_what_it_clears() -> void:
	assert_str(_ed.clear_button.text).is_equal("Clear terrain")


func test_r3_pressing_clear_asks_and_clears_nothing_yet() -> void:
	_ed.clear_button.pressed.emit()
	var sheet := _ed.get_node_or_null("ClearConfirm")
	assert_object(sheet).override_failure_message("R3 — no confirm sheet").is_not_null()
	assert_int(_ed.placed_pieces.size()).override_failure_message("R3 — cleared without asking").is_equal(1)
	assert_int(_ed.free_cells.size()).is_equal(1)
	if sheet != null:
		var texts: Array = []
		for l: Node in sheet.find_children("*", "Label", true, false):
			texts.append((l as Label).text)
		var all := " ".join(texts)
		assert_str(all).contains("Ctrl+Z").contains("Objectives and deployment zones are not touched")


func test_r3_cancel_keeps_everything() -> void:
	_ed.clear_button.pressed.emit()
	var cancel := _ed.get_node("ClearConfirm").find_child("CancelClearButton", true, false) as Button
	cancel.pressed.emit()
	assert_int(_ed.placed_pieces.size()).is_equal(1)
	assert_int(_ed.free_cells.size()).is_equal(1)


func test_r3_confirm_clears_terrain_only_and_one_undo_restores_it() -> void:
	var undo_before: int = _ed._undo_stack.size()
	_ed.clear_button.pressed.emit()
	(_ed.get_node("ClearConfirm").find_child("ConfirmClearButton", true, false) as Button).pressed.emit()
	assert_int(_ed.placed_pieces.size()).is_equal(0)
	assert_int(_ed.free_cells.size()).is_equal(0)
	assert_int(_ed.mission_objectives.size()).override_failure_message("R3 — objectives were cleared too").is_equal(1)
	assert_int(_ed._undo_stack.size()).is_equal(undo_before + 1)
	_ed.undo()
	assert_int(_ed.placed_pieces.size()).is_equal(1)
	assert_int(_ed.free_cells.size()).is_equal(1)
