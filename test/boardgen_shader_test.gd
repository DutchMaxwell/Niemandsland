extends GdUnitTestSuite
## Source pins for the board shader's water (look pass 2). The headless test run has a dummy renderer, so these cannot look at pixels
## (the real-display capture does that); they pin the three decisions that made the puddles square before: the hash, the mask and the wall term.

const SHADER_PATH := "res://shaders/tiefwerk_board.gdshader"


func _source() -> String:
	return FileAccess.get_file_as_string(SHADER_PATH)


func _line_with(src: String, needle: String) -> String:
	for line in src.split("\n"):
		if line.contains(needle):
			return line
	return ""


func test_the_hash_is_not_the_lattice_correlated_one_that_drew_square_patches() -> void:
	var src := _source()
	assert_bool(src.contains("123.34")).is_false()
	assert_bool(src.contains("float h21(vec2 p)")).is_true()


func test_the_water_mask_is_world_space_noise_with_no_cell_grid_in_it() -> void:
	var field := _line_with(_source(), "float field =")
	assert_str(field).is_not_empty()
	assert_bool(field.contains("fbm(uv") and field.contains("warp") and field.contains("wd")).is_true()
	for grid_term in ["floor(", "cell_at(", "ivec2", "f.x", "f.y"]:
		assert_bool(field.contains(grid_term)).override_failure_message("the water mask reads the cell grid: %s" % grid_term).is_false()


func test_the_wall_term_is_the_euclidean_distance_to_the_nearest_taller_cell_in_the_3x3() -> void:
	var src := _source()
	assert_bool(src.contains("float wall_dist(vec2 g, ivec2 c, float h)")).is_true()
	assert_bool(_line_with(src, "best = min(best").contains("length(max(abs(g")).is_true()
	assert_bool(src.contains("float contact")).is_false()   # the 4-neighbour, cell-clipped contact distance is gone


func test_every_uniform_the_greybox_sets_is_declared() -> void:
	var declared := _source().split("\n")
	for name in ["cells", "board_cells", "cell_in", "board_origin"]:
		var found := false
		for line in declared:
			found = found or (line.begins_with("uniform ") and line.contains(" %s" % name))
		assert_bool(found).override_failure_message("uniform %s missing" % name).is_true()
