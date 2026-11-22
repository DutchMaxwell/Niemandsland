extends GdUnitTestSuite
## The tabletop scale of the town's surfaces (plan R1, decision D-R2: true 1:56 x ~1.4): the headless run has a dummy renderer, so these pin the shader's feature sizes and the analytic fade
## that keeps 0.14 in setts from crawling (the real-display capture judges the pixels).

const SHADER := "res://shaders/ruintown_board.gdshader"


func _const(src: String, name: String) -> float:
	var rx := RegEx.new()
	rx.compile("const float %s = ([0-9.]+);" % name)
	var m := rx.search(src)
	assert_object(m).override_failure_message("const %s missing" % name).is_not_null()
	return float(m.get_string(1))


func test_the_feature_sizes_are_the_tabletop_scale_not_the_toy_brick_set() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	# targets of D-R2 (+-15 %): setts 0.14 x 0.11, a wall course 0.24, tiles 0.16 x 0.13, floor boards 0.18
	assert_float(_const(src, "SETT_W")).is_equal_approx(0.14, 0.02)
	assert_float(_const(src, "SETT_H")).is_equal_approx(0.11, 0.017)
	assert_float(_const(src, "COURSE")).is_equal_approx(0.24, 0.036)
	assert_float(_const(src, "TILE_W")).is_equal_approx(0.16, 0.024)
	assert_float(_const(src, "TILE_H")).is_equal_approx(0.13, 0.02)
	assert_float(_const(src, "BOARD_W")).is_equal_approx(0.18, 0.027)
	# a pawn base (~1 in) covers at least six setts across; a wall course is at most a fifth of a ~1.25 in pawn
	assert_float(1.0 / _const(src, "SETT_W")).is_greater_equal(6.0)
	assert_float(_const(src, "COURSE") * 5.0).is_less_equal(1.25)


func test_the_old_chunky_constants_are_gone_and_the_cell_grid_line_with_them() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	for old in ["/ 0.62", "/ 0.42", "floor(p.y * 4.0)", "along / 0.45", "stone(uv, seed, 0.55, 1.0", "stone(xz, seed, 1.0, 1.4"]:
		assert_bool(src.contains(old)).override_failure_message("the shader still has the old unit `%s`" % old).is_false()
	assert_bool(src.contains("float grid = 1.0;")).is_true()   # no faint 3 in cell line to count on the table


func test_every_fine_pattern_fades_to_its_mean_with_the_pixel_footprint() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("float keep(float coord, float size)")).is_true()
	assert_bool(src.contains("fwidth(coord)")).is_true()
	for fn in ["vec3 stone(", "vec3 cobble("]:
		var body := src.substr(src.find(fn), 1800)
		assert_bool(body.contains("keep(")).override_failure_message("%s does not fade with the pixel footprint" % fn).is_true()
	assert_bool(src.contains("keep(p.y, TILE_H)")).is_true()   # the roof tiles
	assert_bool(src.contains("keep(xz.y, BOARD_W)")).is_true()   # the floor boards


## Plan TEX step 3: the brick-nogging courses (0.12 in) and the lath (0.09 in, bare and behind lost plaster) were full-contrast stripes
## that shimmered at the start camera (alias 11.0 on their pixels vs 4.9 without them); they fade to the mean of their two tones instead.
func test_the_nogging_and_lath_stripes_fade_with_the_pixel_footprint_and_are_dull() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	var grit := FileAccess.get_file_as_string("res://shaders/ruintown_grit.gdshaderinc")
	assert_bool(src.contains("keep(uv.y, 0.12)")).override_failure_message("the brick nogging courses do not fade").is_true()
	assert_bool(src.contains("keep(uv.y, 0.09)")).override_failure_message("the bare lath does not fade").is_true()
	assert_bool(grit.contains("keep(uv.y, 0.09)")).override_failure_message("the lath behind lost plaster does not fade").is_true()
	assert_bool(src.contains("vec3(0.42, 0.22, 0.16)")).override_failure_message("the saturated nogging tone is back").is_false()
	assert_bool(src.contains("wood * 1.4, wood * 0.6")).override_failure_message("the full-contrast lath tones are back").is_false()
