extends GdUnitTestSuite
## R6 (Map editor plan): Load onto a non-empty map asks first, and the old map becomes an undo step (the undo
## stack is no longer wiped). Loading onto an empty map just loads.

const SCENE := preload("res://scenes/map_layout.tscn")
const FILE := "user://r6_test_layout.json"

var _ed: Control


func before_test() -> void:
	_ed = auto_free(SCENE.instantiate())
	add_child(_ed)
	await get_tree().process_frame
	# a saved map with ONE piece at (4,4)
	_ed.place_prefab(TerrainPrefabs.keys()[0], Vector2i(4, 4), 0, false, false)
	_ed.save_layout(FILE)
	_ed.placed_pieces.clear()
	_ed.free_cells.clear()
	_ed._undo_stack.clear()
	_ed._rebuild_derived()


func after_test() -> void:
	DirAccess.remove_absolute(FILE)
	_ed = null


func _confirm() -> Control:
	return _ed.get_node_or_null("LoadConfirm")


func test_r6_load_onto_an_empty_map_loads_without_asking() -> void:
	_ed._on_load_file_selected(FILE)
	assert_object(_confirm()).is_null()
	assert_int(_ed.placed_pieces.size()).is_equal(1)


func test_r6_load_onto_a_non_empty_map_asks_first() -> void:
	_ed.place_prefab(TerrainPrefabs.keys()[1], Vector2i(12, 12), 0, false, false)
	_ed._on_load_file_selected(FILE)
	assert_object(_confirm()).override_failure_message("R6 — Load replaced a non-empty map without asking").is_not_null()
	assert_int(_ed.placed_pieces.size()).is_equal(1)
	assert_bool(_ed.placed_pieces[0]["origin"] == Vector2i(12, 12)).is_true()  # still the current map
	(_confirm().find_child("CancelLoadButton", true, false) as Button).pressed.emit()
	assert_bool(_ed.placed_pieces[0]["origin"] == Vector2i(12, 12)).is_true()


func test_r6_confirmed_load_keeps_the_old_map_as_an_undo_step() -> void:
	_ed.place_prefab(TerrainPrefabs.keys()[1], Vector2i(12, 12), 0, false, false)
	_ed._on_load_file_selected(FILE)
	(_confirm().find_child("ConfirmLoadButton", true, false) as Button).pressed.emit()
	assert_bool(_ed.placed_pieces[0]["origin"] == Vector2i(4, 4)).is_true()
	assert_bool(_ed._undo_stack.is_empty()).override_failure_message("R6 — Load wiped the undo stack").is_false()
	_ed.undo()
	assert_int(_ed.placed_pieces.size()).is_equal(1)
	assert_bool(_ed.placed_pieces[0]["origin"] == Vector2i(12, 12)).override_failure_message("R6 — Undo did not bring the old map back").is_true()
