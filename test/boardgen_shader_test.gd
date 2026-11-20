extends GdUnitTestSuite
## Source pins for the board shader's water (look pass 2). The headless test run has a dummy renderer, so these cannot look at pixels
## (the real-display capture does that); they pin the three decisions that made the puddles square before: the hash, the mask and the wall term.

const SHADER_PATH := "res://shaders/tiefwerk_board.gdshader"


const INCLUDES := ["res://shaders/tiefwerk_edges.gdshaderinc"]


## The board shader with its includes appended (the pins below do not care which file a function lives in).
func _source() -> String:
	var src := FileAccess.get_file_as_string(SHADER_PATH)
	for path: String in INCLUDES:
		src += "\n" + FileAccess.get_file_as_string(path)
	return src


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
	for name in ["cells", "board_cells", "cell_in", "board_origin", "detail"]:
		var found := false
		for line in declared:
			found = found or (line.begins_with("uniform ") and line.contains(" %s" % name))
		assert_bool(found).override_failure_message("uniform %s missing" % name).is_true()


func test_the_round_hatch_is_one_function_used_on_floors_decks_and_roofs() -> void:
	var src := _source()
	assert_bool(src.contains("vec4 hatch(vec2 fp, float R, float n)")).is_true()
	assert_int(src.count("hatch(")).override_failure_message("expected the definition plus floor, deck and roof uses").is_greater_equal(4)


func test_the_signage_is_bars_of_hashed_length_not_a_glyph_like_block_grid() -> void:
	var src := _source()
	assert_bool(src.contains("float row = floor((fp.y + 0.27) / 0.18)")).is_true()
	assert_bool(src.contains("fp.x * 7.0")).is_false()


func test_the_hazard_band_is_gated_per_tier_edge_and_the_plate_is_1_5_inches() -> void:
	var src := _source()
	assert_bool(_line_with(src, "hazard band only on some edges").contains("h21(")).is_true()
	assert_bool(src.contains("const float PLATE = 1.5;")).is_true()


func test_edge_wear_counts_real_edges_only_not_the_seams_between_the_boxes_of_one_level() -> void:
	var src := _source()
	assert_bool(src.contains("vec4 edge_wear(")).is_true()
	var gate := _line_with(src, "> p.y - 0.5")   # the surface goes on past this edge: a seam, no edge
	assert_str(gate).contains("cell_at(")
	assert_bool(src.contains("if (k != 5) {")).override_failure_message("ladders are free-standing: every edge of them is real").is_true()
	assert_str(_line_with(src, "a wall's foot is concave")).is_not_empty()


func test_the_edge_wear_is_gated_by_the_detail_uniform() -> void:
	var src := _source()
	assert_bool(src.contains("uniform float detail")).is_true()
	assert_str(_line_with(src, "vec4 ew =")).contains("detail > 0.5")


func test_the_box_size_reaches_the_fragment_and_the_bend_goes_through_the_view_matrix() -> void:
	var src := _source()
	assert_str(_line_with(src, "box_in = INSTANCE_CUSTOM.gba")).is_not_empty()
	assert_str(_line_with(src, "lpos = VERTEX * box_in")).is_not_empty()
	assert_str(_line_with(src, "NORMAL = normalize((VIEW_MATRIX")).contains("ew.yzw")
