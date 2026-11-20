extends GdUnitTestSuite
## The table's own ground scatter stays off under a generated board: GrassField skips the tufts inside its keepout and fills the front
## of its multimesh with the rest (visible_instance_count; the headless renderer keeps no instance buffer to read back, so the suite
## counts), and a BoardgenGreybox on a table sets the keepout (and the "scatter_keepout" meta the biome dressing reads) to its
## footprint and clears both when it leaves.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"


func _grass(table: Vector2) -> GrassField:
	var grass := GrassField.new()
	add_child(auto_free(grass))
	grass.set_table_size(table)
	grass.set_biome(GrassField.GRASS_BIOME)
	return grass


func _drawn(grass: GrassField) -> int:
	return grass.multimesh.visible_instance_count


func test_a_keepout_skips_exactly_the_tufts_inside_it_and_clearing_it_brings_them_back() -> void:
	var grass := _grass(Vector2(1.0, 1.0))
	var all: int = grass.multimesh.instance_count
	assert_int(all).is_greater(1000)
	assert_int(_drawn(grass)).is_equal(all)
	grass.set_keepout(Rect2(-0.2, -0.2, 0.4, 0.3))   # 12 % of the table
	assert_int(_drawn(grass)).is_between(int(all * 0.84), int(all * 0.92))
	grass.set_keepout(Rect2(-1.0, -1.0, 2.0, 2.0))   # the whole table
	assert_int(_drawn(grass)).is_equal(0)
	grass.set_keepout(Rect2())
	assert_int(_drawn(grass)).is_equal(all)


func test_a_board_on_a_table_sets_the_keepout_to_its_footprint_and_clears_it_when_it_leaves() -> void:
	var table: Node3D = auto_free(Node3D.new())
	add_child(table)
	var grass := _grass(Vector2(1.3, 1.3))
	grass.name = "GrassField"
	grass.reparent(table)
	var all: int = grass.multimesh.instance_count
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	var board := BoardgenGreybox.attach(table, layout)
	var side := float(layout["nx"]) * float(layout["cell_in"]) * 0.0254   # 48 in of board on a 1.3 m table
	var rect: Rect2 = table.get_meta("scatter_keepout", Rect2())
	assert_float(rect.size.x).is_between(side, side + 0.05)
	assert_bool(rect.has_point(Vector2.ZERO)).is_true()
	assert_int(_drawn(grass)).is_between(1, int(all * 0.1))   # only the 5 % ring around the board still grows tufts
	table.remove_child(board)
	board.free()
	assert_bool((table.get_meta("scatter_keepout", Rect2()) as Rect2).has_area()).is_false()
	assert_int(_drawn(grass)).is_equal(all)
