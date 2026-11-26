extends GdUnitTestSuite
## Source pins for the town's water shader (look plan R18 / R17). The headless run has a dummy renderer, so the shader is pinned by source
## (it compiles on the real renderer: the launch smoke and the PR's display check).

const SHADER_PATH := "res://shaders/ruintown_water.gdshader"
const UNIFORMS := ["deep", "shallow", "sky_tint", "sky_energy", "half_in", "octagon", "bank_in", "ring_strength", "scum", "clock", "fresnel_floor", "ripple_slope", "sheen"]


func _source() -> String:
	return FileAccess.get_file_as_string(SHADER_PATH)


func test_the_water_shader_exists_with_its_uniforms() -> void:
	var src := _source()
	assert_str(src).is_not_empty()
	assert_bool(src.begins_with("//") and src.contains("shader_type spatial;")).is_true()
	for u: String in UNIFORMS:
		assert_object(RegEx.create_from_string("uniform \\w+ " + u + "\\b").search(src)).override_failure_message("no uniform " + u).is_not_null()


func test_the_water_reads_no_depth_or_screen_texture() -> void:
	var src := _source()
	for needle: String in ["hint_depth_texture", "hint_screen_texture", "hint_normal_roughness_texture"]:
		assert_bool(src.contains(needle)).override_failure_message("the water uses " + needle).is_false()


func test_the_water_mirrors_the_sky_and_folds_its_noise_by_the_half_turn() -> void:
	var src := _source()
	assert_bool(src.contains("EMISSION = sky_tint * sky_energy * (fres")).override_failure_message("no analytic sky mirror: a black probe makes a hole").is_true()
	assert_bool(src.contains("lp.y >= 0.0 ? -lp : lp")).override_failure_message("the noise is not folded by the half turn").is_true()
	assert_bool(src.contains("TIME * 0.03 * clock")).override_failure_message("the ripples ignore the clock (stills must freeze)").is_true()
