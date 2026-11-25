extends GdUnitTestSuite
## A generated Tiefwerk board is an undercity: the table's biome landscape (meadow,
## trees) is not dressed while one lies on the table, and comes back when it leaves.
## The ruin town keeps the landscape as distant land.

const TableScript := preload("res://scripts/table.gd")


func _presenter(table: Node3D) -> TableBiomePresenter:
	var presenter: TableBiomePresenter = auto_free(TableBiomePresenter.new())
	presenter.allow_headless = true  # gdUnit runs headless; the rule is under test
	presenter.set("_table", table)
	return presenter


## Never built: the group and the theme are all the presenter reads.
func _board(theme: String) -> BoardgenGreybox:
	var board := BoardgenGreybox.new()
	board.add_to_group(BoardgenGreybox.TABLE_OVERLAY_GROUP)
	board.layout_theme = theme
	return board


func test_a_tiefwerk_board_hides_the_biome_landscape_until_it_leaves() -> void:
	var table: Node3D = auto_free(TableScript.new())  # never in the tree
	var presenter := _presenter(table)
	assert_bool(presenter.should_dress()).is_true()
	var board := _board(BoardgenTheme.DEEPWORKS)
	table.add_child(board)
	var msg := "a meadow is dressed round the undercity"
	assert_bool(presenter.should_dress()).override_failure_message(msg).is_false()
	table.remove_child(board)
	board.free()
	msg = "the landscape did not come back when the board left"
	assert_bool(presenter.should_dress()).override_failure_message(msg).is_true()


func test_the_ruin_town_keeps_the_landscape() -> void:
	var table: Node3D = auto_free(TableScript.new())
	var presenter := _presenter(table)
	var board := _board(BoardgenTheme.RUIN_TOWN)
	table.add_child(board)
	assert_bool(presenter.should_dress()).is_true()
	table.remove_child(board)
	board.free()
