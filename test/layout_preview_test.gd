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


## Gap review 28.11. (sheet 03c): the preview is the editor's picture with its caption laid on the board's lower edge,
## not under it; the board takes the whole box (red before: the caption 6 px below the board, 28 px kept for it).
func test_the_caption_lies_on_the_boards_lower_edge() -> void:
	var layout: SetupLayout = auto_free(SetupLayout.new())
	add_child(layout)
	layout.set_table(Vector2(6, 4), "gf")
	var preview: LayoutPreview = auto_free(LayoutPreview.new())
	preview.size = Vector2(660, 440)
	add_child(preview)
	preview.show_layout(layout)
	for _i in 2:
		await get_tree().process_frame
	var board := LayoutPreview.board_rect(Vector2(6, 4), Rect2(Vector2.ZERO, preview.size))
	var caption := Rect2(preview.tagline.position, preview.tagline.size)
	assert_bool(board.grow(0.5).encloses(caption)).override_failure_message("caption %s, board %s" % [caption, board]).is_true()
