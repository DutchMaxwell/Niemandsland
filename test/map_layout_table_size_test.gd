extends GdUnitTestSuite
## R7 (Map editor plan): changing the table size no longer wipes the map silently - the editor says what was
## cleared in one line, and the old map (terrain, objectives, table size) is one undo step.

const SCENE := preload("res://scenes/map_layout.tscn")

var _ed: Control


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	await get_tree().process_frame


func after_test() -> void:
	_ed = null


func _notice() -> Label:
	return _ed.find_child("TableSizeNotice", true, false) as Label


func test_r7_size_change_says_what_was_cleared_and_undo_brings_the_map_back() -> void:
	_ed.place_prefab(TerrainPrefabs.keys()[0], Vector2i(10, 10), 0, false, false)
	_ed.mission_objectives.assign([Vector2(30, 40), Vector2(50, 40)])
	var size0: Vector2 = _ed.table_size_feet
	_ed.set_table_size(Vector2(4, 4))
	assert_int(_ed.placed_pieces.size()).is_equal(0)
	assert_int(_ed.mission_objectives.size()).is_equal(0)
	assert_object(_notice()).override_failure_message("R7 — no notice label").is_not_null()
	if _notice() != null:
		assert_bool(_notice().visible).is_true()
		assert_str(_notice().text).contains("Table size changed").contains("1 piece").contains("2 objectives").contains("Ctrl+Z")
	_ed.undo()
	assert_int(_ed.placed_pieces.size()).override_failure_message("R7 — Undo did not restore the terrain").is_equal(1)
	assert_int(_ed.mission_objectives.size()).is_equal(2)
	assert_bool(_ed.table_size_feet == size0).override_failure_message("R7 — Undo did not restore the table size").is_true()
	if _notice() != null:
		assert_bool(_notice().visible).is_false()


func test_r7_changing_the_size_of_an_empty_map_is_silent_and_adds_no_undo_step() -> void:
	_ed.set_table_size(Vector2(4, 4))
	assert_bool(_notice() == null or not _notice().visible).is_true()
	assert_int(_ed._undo_stack.size()).is_equal(0)
