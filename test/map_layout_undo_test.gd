extends GdUnitTestSuite
## F4 (Map editor plan): a paint stroke that changes nothing must not light up Undo.

const SCENE := preload("res://scenes/map_layout.tscn")


func _editor() -> Control:
	var ed: Control = SCENE.instantiate()
	add_child(ed)
	auto_free(ed)
	return ed


func _stroke(ed: Control, mutate: Callable) -> void:
	if ed.has_method("_begin_stroke"):
		ed.call("_begin_stroke")
	else:
		ed._push_undo()  # what the pre-F4 code did at stroke start
	mutate.call()
	if ed.has_method("_end_stroke"):
		ed.call("_end_stroke")


func test_eraser_stroke_on_empty_cells_pushes_no_undo() -> void:
	var ed := _editor()
	ed.selected_terrain_type = ed.TerrainType.NONE
	_stroke(ed, func(): ed.free_cells.erase(Vector2i(3, 3)))
	assert_int(ed._undo_stack.size()) \
		.override_failure_message("F4 — a no-op stroke left an undo step") \
		.is_equal(0)


func test_real_stroke_pushes_exactly_one_undo_and_undo_restores() -> void:
	var ed := _editor()
	_stroke(ed, func(): ed.free_cells[Vector2i(3, 3)] = ed.TerrainType.RUINS)
	assert_int(ed._undo_stack.size()).is_equal(1)
	ed.undo()
	assert_bool(ed.free_cells.has(Vector2i(3, 3))).is_false()
