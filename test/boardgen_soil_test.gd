extends GdUnitTestSuite
## LOOK5 R20 (the ground is a material): source pins of the soil include. The headless run has a dummy renderer, so the real-display
## capture checks pixels; these pin the include, its feed and the two decisions that keep the ground fair and the palette tone.

const INC := "res://shaders/ruintown_soil.gdshaderinc"


func test_the_board_shader_includes_the_soil_and_the_soil_is_folded_and_a_ratio() -> void:
	var board := FileAccess.get_file_as_string("res://shaders/ruintown_board.gdshader")
	assert_bool(board.contains('#include "res://shaders/ruintown_soil.gdshaderinc"')).is_true()
	var inc := FileAccess.get_file_as_string(INC)
	assert_str(inc).is_not_empty()
	for u in ["uniform sampler2DArray soil_alb", "uniform sampler2DArray soil_nrm", "uniform sampler2DArray soil_orh", "uniform float soil_on = 0.0", "uniform float soil_tile", "uniform vec3 soil_mean[4]"]:
		assert_bool(inc.contains(u)).override_failure_message("missing: %s" % u).is_true()
	assert_bool(inc.contains("vnoise(green_fold(xz_in) * 0.083)")).is_true()   # the tile break is folded by the half turn (D-G5)
	assert_bool(inc.contains("a / max(soil_mean[i]")).is_true()   # albedo as a ratio: the palette tone survives
	assert_bool(inc.contains("SoilSample soil_blend(vec4 w, vec2 xz_in)")).is_true()
	assert_bool(board.contains("soil_blend(")).override_failure_message("S1 is inert: nothing calls soil_blend yet").is_false()
