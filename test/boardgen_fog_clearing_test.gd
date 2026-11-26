extends GdUnitTestSuite
## BoardgenFogClearing (LOOK5 F1): the clearing that keeps a ground fog off the models is a piece of its own, with no
## fog and no theme in it, so any fog over the board can sample it.


func test_a_model_at_the_centre_clears_its_spot_and_nothing_two_inches_out() -> void:
	var board: Node3D = auto_free(Node3D.new())
	add_child(board)
	var clearing := BoardgenFogClearing.new(Vector2(24.0, 24.0))
	var model := Node3D.new()
	model.add_to_group(BoardgenFogClearing.MODEL_GROUP)
	board.add_child(model)
	clearing.update(board, get_tree())
	assert_float(clearing.at(Vector2.ZERO)).is_equal_approx(1.0, 0.01)
	assert_float(clearing.at(Vector2(2.0, 0.0))).is_equal(0.0)
	assert_float(clearing.at(Vector2(0.0, -2.0))).is_equal(0.0)
	assert_object(clearing.texture).is_not_null()
	assert_int(clearing.texture.get_width()).is_equal(int(24.0 / BoardgenFogClearing.CLEAR_TEXEL_IN))
