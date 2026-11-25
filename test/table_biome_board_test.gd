extends GdUnitTestSuite
## A board that must not stand in the table's landscape (a generated Tiefwerk board:
## an undercity has no meadow round it) joins HIDES_LANDSCAPE_GROUP: the table's biome
## landscape is not dressed while one lies on the table and comes back when it leaves.
## Which boards join the group is pinned on the board side (boardgen_surround_test).

const TableScript := preload("res://scripts/table.gd")


func _presenter(table: Node3D) -> TableBiomePresenter:
	var presenter: TableBiomePresenter = auto_free(TableBiomePresenter.new())
	presenter.allow_headless = true  # gdUnit runs headless; the rule is under test
	presenter.set("_table", table)
	return presenter


func test_a_board_that_hides_the_landscape_undresses_the_table_until_it_leaves() -> void:
	var table: Node3D = auto_free(TableScript.new())  # never in the tree
	var presenter := _presenter(table)
	assert_bool(presenter.should_dress()).is_true()
	var board := Node3D.new()
	board.add_to_group(TableBiomePresenter.HIDES_LANDSCAPE_GROUP)
	table.add_child(board)
	var msg := "a meadow is dressed round the undercity"
	assert_bool(presenter.should_dress()).override_failure_message(msg).is_false()
	table.remove_child(board)
	board.free()
	msg = "the landscape did not come back when the board left"
	assert_bool(presenter.should_dress()).override_failure_message(msg).is_true()


func test_any_other_child_of_the_table_keeps_the_landscape() -> void:
	var table: Node3D = auto_free(TableScript.new())
	var presenter := _presenter(table)
	var board := Node3D.new()
	table.add_child(board)
	assert_bool(presenter.should_dress()).is_true()
	table.remove_child(board)
	board.free()
