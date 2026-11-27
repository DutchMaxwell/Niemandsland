extends GdUnitTestSuite
## The picture of step 04's layout (step 65.4): a top-down board on a 3-inch grid in the editor's colours.
## Red before the step: there is no res://scripts/layout_preview.gd.

const SCRIPT := "res://scripts/layout_preview.gd"


func _script() -> GDScript:
	assert_bool(ResourceLoader.exists(SCRIPT)).override_failure_message("no layout preview").is_true()
	return load(SCRIPT) if ResourceLoader.exists(SCRIPT) else null


func test_a_6_by_4_board_keeps_its_shape_in_the_rail_box() -> void:
	var preview := _script()
	if preview == null:
		return
	var board: Rect2 = preview.call("board_rect", Vector2(6, 4), Rect2(0, 0, 660, 441))
	assert_float(board.size.x / board.size.y).is_equal_approx(1.5, 0.001)
	assert_bool(Rect2(0, 0, 660, 441).encloses(board)).is_true()


func test_three_cells_give_three_rects_on_the_board() -> void:
	var preview := _script()
	if preview == null:
		return
	var board := Rect2(10, 10, 600, 400)
	var cells: Array[Vector2i] = [Vector2i(20, 20), Vector2i(21, 20), Vector2i(15, 18)]
	var rects: Array = preview.call("cell_rects", cells, 40, Vector2(6, 4), board)
	assert_int(rects.size()).is_equal(3)
	for rect: Rect2 in rects:
		assert_bool(board.encloses(rect)).override_failure_message(str(rect)).is_true()
