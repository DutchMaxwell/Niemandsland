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
	for fn in ["vec3 stone_rows(", "vec3 cobble("]:   # (texture plan step 6: stone() lays its fixed course through stone_rows())
		var body := src.substr(src.find(fn), 1800)
		assert_bool(body.contains("keep(")).override_failure_message("%s does not fade with the pixel footprint" % fn).is_true()
	assert_bool(src.contains("keep(p.y, TILE_H)")).is_true()   # the roof tiles
	assert_bool(src.contains("keep(xz.y, BOARD_W)")).is_true()   # the floor boards


## Plan TEX step 3: the brick-nogging courses (0.12 in) and the lath (0.09 in, bare and behind lost plaster) were full-contrast two-tone
## stripes (a zebra that shimmered at the start camera); now one dull tone with a thin joint whose fade is keyed on the joint width.
func test_the_nogging_and_lath_are_one_dull_tone_with_a_thin_joint_that_fades_on_its_own_width() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	var grit := FileAccess.get_file_as_string("res://shaders/ruintown_grit.gdshaderinc")
	assert_bool(src.contains("keep(uv.y, 0.024)")).override_failure_message("the nogging joint does not fade on its width").is_true()
	assert_bool(src.contains("keep(uv.y, 0.0225)")).override_failure_message("the bare lath gap does not fade on its width").is_true()
	assert_bool(grit.contains("keep(uv.y, 0.0225)")).override_failure_message("the lath behind lost plaster does not fade").is_true()
	for pin: String in ["step(0.5, fract(y / 0.12))", "step(0.5, fract(uv.y / 0.09))", "vec3(0.42, 0.22, 0.16)", "wood * 1.4, wood * 0.6", "wood * 1.3, wood * 0.55"]:
		assert_bool((src + grit).contains(pin)).override_failure_message("the half-and-half zebra is back: " + pin).is_false()


## Look review 25.11. (R1): the flat tops of tiers, towers and the wall were laid in 1.8 in bands of 0.45 - 0.75 in courses with 0.5 - 1.1 in flags, 1.5 - 2.5 x
## the accepted fine house stone. The flag band is now <= 1.1 in, its widest course <= 0.45 in, the flags <= 0.45 in base length, and the fracture lines the flag
## length that stone_rows() lays (one constant, or the cracks run across the joints).
func test_the_flag_tops_are_laid_in_fine_courses() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	var fn := src.substr(src.find("vec3 flag_row("), 700)
	var band := RegEx.create_from_string("float band = floor\\(y / ([0-9.]+)\\);").search(fn)
	assert_object(band).is_not_null()
	assert_float(float(band.get_string(1))).override_failure_message("flag band %s in" % band.get_string(1)).is_less_equal(1.1)
	var course := RegEx.create_from_string("float c0 = ([0-9.]+) \\+ ([0-9.]+) \\* mod").search(fn)
	assert_object(course).is_not_null()
	var widest := float(course.get_string(1)) + 2.0 * float(course.get_string(2))
	assert_float(widest).override_failure_message("widest flag course %.2f in" % widest).is_less_equal(0.45)
	var lay := RegEx.create_from_string("stone_rows\\(xz, seed, fr, ([0-9.]+),").search(src)
	assert_object(lay).is_not_null()
	assert_float(float(lay.get_string(1))).override_failure_message("flag length %s in" % lay.get_string(1)).is_less_equal(0.45)
	assert_bool(src.contains("float fl_l = %s * (" % lay.get_string(1))).override_failure_message("the fracture does not use the flag length").is_true()


## Look review 25.11. (R5): the cobble relief read only under a lamp - under the two moons its bent normals cancel. The setts carry a light-independent
## cavity term (joints darker, crowns a little lighter, the mean kept; it fades with the pixel footprint like the setts) and a 0.09 in relief depth. Measured
## at the market square from both player sides: luma std / mean 0.178 / 0.161 -> 0.268 / 0.259, board mean luma +0.6 %, the lamp's saturated streak 0.205 -> 0.178.
func test_the_setts_carry_their_own_relief_without_a_light() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	for name: String in ["SETT_DEPTH_IN", "SETT_CAVITY"]:
		assert_bool(src.contains("const float %s = " % name)).override_failure_message("const %s missing" % name).is_true()
		if not src.contains("const float %s = " % name):
			return
	assert_float(_const(src, "SETT_DEPTH_IN")).is_greater_equal(0.09)
	assert_float(_const(src, "SETT_CAVITY")).override_failure_message("no cavity term on the setts").is_greater_equal(0.4)
	assert_bool(src.contains("depth_in = SETT_DEPTH_IN;")).is_true()
	assert_bool(src.contains("alb *= mix(1.0, mix(1.0 - SETT_CAVITY, 1.0 + 0.35 * SETT_CAVITY, smoothstep(0.1, 0.6, crown)), keep(xz.x, SETT_W));")).override_failure_message("the cavity term is not keyed on the crown and faded with the footprint").is_true()
