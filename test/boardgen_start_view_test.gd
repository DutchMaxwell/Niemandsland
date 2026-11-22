extends GdUnitTestSuite
## The start view over a generated board (texture plan step 10, decision D-TEX3): 0.70 x the table diagonal instead of 0.95 while the board is on the table - when it arrives
## and after every reset of the view - and the table's 0.95 again once it leaves. Without a board nothing changes.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const PIVOT := preload("res://scripts/camera_controller.gd")
const DIAGONAL_M := 1.2192 * 1.41421356   # a 4 x 4 ft table


class StubTable extends Node3D:
	var table_size := Vector2(4, 4)


func _main() -> Node:
	var script := GDScript.new()
	script.source_code = "extends Node\nvar camera_pivot\n"
	script.reload()
	var main: Node = auto_free(Node.new())
	main.set_script(script)
	var pivot: Node3D = PIVOT.new()
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	pivot.add_child(cam)
	main.add_child(pivot)
	main.set("camera_pivot", pivot)
	var table := StubTable.new()
	table.name = "Table"
	main.add_child(table)
	add_child(main)
	return main


func _reset(pivot: Node3D) -> void:   # what main.gd's _adjust_camera_for_table_size does
	pivot.reset_view()
	pivot.adjust_for_table_size(Vector2(4, 4))


func test_without_a_board_the_start_view_is_the_tables() -> void:
	var pivot: Node3D = _main().get("camera_pivot")
	_reset(pivot)
	assert_float(pivot.get_zoom()).is_equal_approx(DIAGONAL_M * 0.95, 0.0005)
	pivot.adjust_for_table_size(Vector2(4, 4), 0.5)   # the explicit factor wins
	assert_float(pivot.get_zoom()).is_equal_approx(DIAGONAL_M * 0.5, 0.0005)


func test_a_board_brings_the_start_view_closer_until_it_leaves() -> void:
	var main := _main()
	var pivot: Node3D = main.get("camera_pivot")
	_reset(pivot)
	var board := BoardgenGreybox.attach(main.get_node("Table"), str_to_var(FileAccess.get_file_as_string(FIXTURE)))
	assert_float(pivot.get_zoom()).override_failure_message("the board arrived and the view stayed at 0.95").is_equal_approx(DIAGONAL_M * 0.70, 0.0005)
	_reset(pivot)
	assert_float(pivot.get_zoom()).override_failure_message("a reset of the view lost the board's start view").is_equal_approx(DIAGONAL_M * 0.70, 0.0005)
	main.get_node("Table").remove_child(board)
	board.free()
	_reset(pivot)
	assert_float(pivot.get_zoom()).override_failure_message("the board left and its start view stayed").is_equal_approx(DIAGONAL_M * 0.95, 0.0005)
