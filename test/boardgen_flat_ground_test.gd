extends GdUnitTestSuite
## A generated board owns its footprint: the game table's ground has mounds under trees and 7 mm ridges along its terrain walls (vertex relief in
## reference_ground_body.gdshaderinc), the board's skin is 1 mm thick, so every ridge poked through the garden plots of the ruin town as lime slabs (21.11.).
## The board tells the table (the generic Table.set_flat_rect hook) to keep its rect flat and clears it when it leaves; the table's own side is test/table_flat_rect_test.gd.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const BODY := "res://shaders/visual/reference_ground_body.gdshaderinc"
const Menu := preload("res://scripts/menu_battlefield.gd")


class StubTable extends Node3D:   # what the board needs of table.gd: the hook that keeps a rect of the ground flat
	var flat := Rect2()
	var calls := 0

	func set_flat_rect(rect: Rect2) -> void:
		flat = rect
		calls += 1


func test_a_board_asks_the_table_to_keep_its_rect_flat_and_gives_the_relief_back_when_it_leaves() -> void:
	var table: StubTable = auto_free(StubTable.new())
	add_child(table)
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	var board := BoardgenGreybox.attach(table, layout)
	var half := 8.0 * float(layout["cell_in"]) * BoardgenGreybox.INCHES_TO_METERS + BoardgenGreybox.RELIEF_MARGIN_M   # 16 cells off the centre, plus the margin
	assert_float(table.flat.position.x).is_equal_approx(-half, 0.0005)
	assert_float(table.flat.position.y).is_equal_approx(-half, 0.0005)
	assert_float(table.flat.end.x).is_equal_approx(half, 0.0005)
	assert_float(table.flat.end.y).is_equal_approx(half, 0.0005)
	table.remove_child(board)
	board.free()
	assert_bool(table.flat.has_area()).override_failure_message("the board left and the ground stayed flat").is_false()


func test_a_table_slot_without_the_hook_is_left_alone() -> void:
	var table: Node3D = auto_free(Menu.MenuSurface.new())   # the main menu's stand-in sits in the table slot: no set_flat_rect
	add_child(table)
	var board := BoardgenGreybox.attach(table, str_to_var(FileAccess.get_file_as_string(FIXTURE)))
	table.remove_child(board)
	board.free()   # (no error: it has no ground to flatten)


func test_the_ground_shader_returns_no_relief_inside_the_flat_rect_and_the_presenter_asks_the_table_for_it() -> void:
	var body := FileAccess.get_file_as_string(BODY)
	assert_str(body).contains("uniform vec4 flat_rect")
	var start := body.find("float full_relief")
	var relief := body.substr(start, body.find("varying vec2 ground_xz") - start)
	assert_str(relief).contains("flat_rect.xy")   # the guard sits INSIDE full_relief, before its sum
	assert_str(relief).contains("return 0.0;")
	assert_str(FileAccess.get_file_as_string("res://scripts/visual/grassland_reference.gd")).contains("sync_flat(table)")
