extends GdUnitTestSuite
## The town's un-gridded ground (plan O2): the ground map the shader looks up, and the source pins that keep the wandering border to open ground only.

const SHADER := "res://shaders/ruintown_board.gdshader"
const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"


func _town() -> Dictionary:
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string(FIXTURE))
	layout["theme"] = "RuinTown"
	return layout


func test_the_ground_map_is_one_rgba_texel_per_cell_with_the_cells_kind_and_the_way_a_street_runs() -> void:
	var layout := _town()
	var kinds := BoardgenTheme.TOWN_KINDS
	var bytes := BoardgenGreybox.ground_map(layout, kinds)
	var nx: int = layout["nx"]
	assert_int(bytes.size()).is_equal(nx * int(layout["nz"]) * 4)
	for i in layout["cells"].size():
		var c: Dictionary = layout["cells"][i]
		assert_int(bytes[i * 4]).is_equal(kinds.find(BoardgenGreybox._cell_kind(c, true)))
		if c["street"]:
			assert_bool([0, 128, 255].has(bytes[i * 4 + 1])).is_true()


func test_a_straight_street_cell_runs_along_its_street_and_a_crossing_is_a_junction_with_its_middle() -> void:
	var cells: Array = []
	for i in 256:
		cells.append({"x": i % 16, "z": i / 16, "street": false, "lot_id": 0, "lot_kind": "Street", "level": 0})
	for k in 16:
		cells[8 * 16 + k]["street"] = true   # a street along x on row 8
	for k in 16:
		cells[k * 16 + 8]["street"] = true   # and one along z on column 8: a 1-cell crossing at (8, 8)
	var layout := {"nx": 16, "nz": 16, "cell_in": 3.0, "cells": cells}
	var bytes := BoardgenGreybox.ground_map(layout, BoardgenTheme.TOWN_KINDS)
	assert_int(bytes[(8 * 16 + 3) * 4 + 1]).is_equal(0)     # along x
	assert_int(bytes[(3 * 16 + 8) * 4 + 1]).is_equal(255)   # along z
	assert_int(bytes[(8 * 16 + 8) * 4 + 1]).is_equal(128)   # the crossing
	assert_int(bytes[(8 * 16 + 8) * 4 + 2]).is_between(126, 129)   # its middle is its own centre: offset 0
	# a 2 x 2 square on its own: a junction, and each cell's middle offset points at the square's centre (the lower right cell's points up and left)
	for c in cells:
		c["street"] = false
	for dz in 2:
		for dx in 2:
			cells[(8 + dz) * 16 + 8 + dx]["street"] = true
	bytes = BoardgenGreybox.ground_map(layout, BoardgenTheme.TOWN_KINDS)
	var lower_right := (9 * 16 + 9) * 4
	assert_int(bytes[lower_right + 1]).is_equal(128)
	assert_int(bytes[lower_right + 2]).is_less(100)   # the centre is to the left (x) ...
	assert_int(bytes[lower_right + 3]).is_less(100)   # ... and above (z)


func test_a_two_cell_wide_street_still_runs_along_its_length() -> void:
	var cells: Array = []
	for i in 256:
		cells.append({"x": i % 16, "z": i / 16, "street": i % 16 == 4 or i % 16 == 5, "lot_id": 0, "lot_kind": "Street", "level": 0})
	var bytes := BoardgenGreybox.ground_map({"nx": 16, "nz": 16, "cell_in": 3.0, "cells": cells}, BoardgenTheme.TOWN_KINDS)
	for z in 16:
		for x in [4, 5]:
			assert_int(bytes[(z * 16 + x) * 4 + 1]).is_equal(255)   # an artery 6 in wide is a street along z, not a field of junctions


func test_the_town_material_carries_the_ground_map_and_the_board_size() -> void:
	var layout := _town()
	var board: BoardgenGreybox = auto_free(BoardgenGreybox.new())
	add_child(board)
	board.build(layout)
	var mat := (board.find_child("Surfaces", false, false) as MultiMeshInstance3D).material_override as ShaderMaterial
	assert_object(mat.get_shader_parameter("ground_map")).is_not_null()
	assert_vector(mat.get_shader_parameter("board_cells")).is_equal(Vector2(layout["nx"], layout["nz"]))


## Source pins (the headless run has a dummy renderer: the capture does the pixels): the wandering lookup is only trusted on earth and street, so a RUINS, FOREST
## or DANGEROUS cell keeps its exact edge, and the ground has no cell grid line.
func test_the_border_only_wanders_between_earth_and_street_and_the_open_ground_has_no_grid_line() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("if (k <= 1) {")).is_true()
	assert_bool(src.contains("if (int(g.r * 255.0 + 0.5) <= 1) {")).override_failure_message("the bent lookup must only be accepted when it lands on earth or street").is_true()
	for line in src.split("\n"):
		if line.contains("cobble(xz, seed") or line.contains("tint * mix(0.78, 1.15, fbm(xz * 1.6 + seed))"):
			assert_bool(line.contains("* grid")).override_failure_message("no cell grid line on the open ground: " + line).is_false()
