extends GdUnitTestSuite
## Source pins for the board shader's water (look pass 2). The headless test run has a dummy renderer, so these cannot look at pixels
## (the real-display capture does that); they pin the three decisions that made the puddles square before: the hash, the mask and the wall term.

const SHADER_PATH := "res://shaders/tiefwerk_board.gdshader"


const INCLUDES := ["res://shaders/tiefwerk_noise.gdshaderinc", "res://shaders/tiefwerk_edges.gdshaderinc", "res://shaders/tiefwerk_relief.gdshaderinc",
	"res://shaders/tiefwerk_value.gdshaderinc"]


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

func test_the_sump_liquid_flows_ripples_and_stains_what_is_round_it() -> void:
	var src := _source()
	assert_bool(src.contains("float sump_dist(vec2 g, ivec2 c)")).is_true()   # the stain on the floor measures its distance to a pool cell
	assert_bool(_line_with(src, "float swell(vec2 q)") != "" and src.contains("TIME * 0.05")).is_true()   # the liquid moves
	assert_bool(src.contains("vec2 bubbles(vec2 q)") and src.contains("NORMAL = normalize((VIEW_MATRIX")).is_true()   # bubbles pop, ripples tilt the normal
	assert_bool(src.contains("} else if (k == 7) {")).is_true()   # the kerb has its own surface


func test_the_wall_relief_is_one_height_function_whose_gradient_is_the_normal() -> void:
	var src := _source()
	assert_bool(src.contains("float wall_height(vec2 uv, float px)")).is_true()
	assert_bool(src.contains("vec3 wall_relief(vec2 uv, vec3 n, float px, out float h0)")).is_true()
	assert_str(_line_with(src, "float hu =")).contains("wall_height(uv + vec2(DE, 0.0), px)")   # finite differences of that one function
	assert_str(_line_with(src, "return normalize(n - hu * tu")).is_not_empty()
	assert_str(_line_with(src, "nrel = wall_relief(")).is_not_empty()
	assert_str(_line_with(src, "NORMAL = normalize((VIEW_MATRIX")).contains("nrel")


func test_rivets_are_domes_and_features_below_a_pixel_fade_out() -> void:
	var src := _source()
	assert_bool(src.contains("float dome(float d, float r, float h)")).is_true()
	assert_str(_line_with(src, "float rv = length(vec2((fract(along / 0.25")).is_not_empty()   # a row along the frame, 0.25 in apart
	assert_str(_line_with(src, "h += dome(rv, 0.026, 0.02)")).contains("feature(0.05, px)")
	assert_bool(src.contains("float px = max(length(fwidth(uv)), 0.0001)")).is_true()


func test_the_painted_rivet_discs_stay_only_on_low_and_the_occlusion_moves_to_the_ao_output() -> void:
	var src := _source()
	assert_bool(src.contains("if (detail < 0.5) {   // Low keeps the painted rivets")).is_true()
	assert_str(_line_with(src, "ALBEDO = pow(alb")).contains("(detail > 0.5 ? 1.0 : ao)")
	assert_str(_line_with(src, "AO = detail > 0.5 ? ao : 1.0")).is_not_empty()
	assert_str(_line_with(src, "AO_LIGHT_AFFECT")).is_not_empty()
	assert_str(_line_with(src, "nrel = wall_relief(")).is_not_empty()
	assert_bool(src.contains("if (detail > 0.5) {\n\t\t\tfloat rh;")).override_failure_message("the wall relief is gated by the detail uniform").is_true()


func test_floor_deck_and_roof_relief_is_one_height_function_and_water_lies_level() -> void:
	var src := _source()
	assert_bool(src.contains("float top_height(vec2 uv, int k, vec2 half_board, float px)")).is_true()
	assert_bool(src.contains("vec3 top_relief(vec2 uv, int k, vec2 half_board, float px, float wet, out float h0)")).is_true()
	assert_str(_line_with(src, "float hu = (top_height(")).contains("/ DE")   # finite differences of the one function
	assert_str(_line_with(src, "float s = 1.0 - wet;")).is_not_empty()   # a puddle flattens the relief
	assert_str(_line_with(src, "wet = pud;")).is_not_empty()
	assert_str(_line_with(src, "nrel = top_relief(")).contains("wet")
	assert_str(_line_with(src, "nrel = top_relief(")).contains("me.y")   # and so does a sump's liquid
	assert_bool(src.contains("if (detail > 0.5) {\n\t\t\tfloat th;")).override_failure_message("the top relief is gated by the detail uniform").is_true()


func test_hatches_grates_and_deck_rivets_have_relief_with_the_albedo_shapes_of_the_same_size() -> void:
	var src := _source()
	assert_bool(src.contains("float hatch_height(vec2 fp, float R, float px)")).is_true()
	assert_int(src.count("hatch_height(")).override_failure_message("definition plus floor, deck and roof uses").is_greater_equal(4)
	assert_str(_line_with(src, "float bar = smoothstep(0.5, 0.58, f)")).is_not_empty()   # the grate's slots, 6 per inch like the albedo
	assert_str(_line_with(src, "rivet heads")).contains("dome(")
	assert_str(_line_with(src, "tread ribs")).is_not_empty()


func test_a_roof_has_one_look_per_lot_and_the_value_ladder_runs_floor_deck_roof_tower() -> void:
	var src := _source()
	assert_bool(src.contains("vec3 lot_hue(float lot)")).override_failure_message("the roof's colour must come from the lot id alone, never from a plate").is_true()
	assert_str(_line_with(src, "alb = value_top(")).contains("me.z")   # the lot id of the cell texture's blue channel
	assert_str(src.substr(src.find("alb = value_top(") - 40, 40)).contains("detail > 0.5")   # the finer look only: Low keeps main's colours
	var gains := {}
	for gain in ["FLOOR_GAIN", "DECK_GAIN", "ROOF_GAIN", "TOWER_GAIN"]:
		var line := _line_with(src, "const float %s =" % gain)
		assert_str(line).override_failure_message("%s missing" % gain).is_not_empty()
		gains[gain] = float(line.get_slice("=", 1).get_slice(";", 0))
	# the floor is darkened, a tower top is lifted over the roofs (the deck's own base value is lower than the roofs', so its gain may be above 1)
	assert_bool(gains["FLOOR_GAIN"] < 1.0 and gains["FLOOR_GAIN"] < gains["DECK_GAIN"] and gains["ROOF_GAIN"] < gains["TOWER_GAIN"]).is_true()
