extends GdUnitTestSuite
## The relief of the town's surfaces (plan R2a ground, R2b walls and roofs): every pattern reports a height, the end of the fragment shader bends the normal from its gradient and sets roughness and
## occlusion. The headless run has a dummy renderer, so these pin the mechanism; the capture judges the look (street, macro: each sett has a lit and a shadow side under a lantern).

const SHADER := "res://shaders/ruintown_board.gdshader"


func test_the_height_becomes_a_bent_normal_with_occlusion_at_the_end_of_the_fragment_shader() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("float depth_in = 0.0;")).is_true()
	assert_bool(src.contains("NORMAL = normalize(abs(det) * NORMAL - grad);")).override_failure_message("the surface-gradient bump is missing").is_true()
	assert_bool(src.contains("AO = ao;")).is_true()
	assert_bool(src.contains("dFdx(h)") and src.contains("dFdy(h)")).is_true()   # the gradient of the height, not a tangent-space map


func test_the_patterns_report_their_height_and_fade_it_with_the_pixel_footprint() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	for fn in ["vec3 stone(", "vec3 cobble("]:
		var head := src.substr(src.find(fn), 160)
		assert_bool(head.contains("out float rel")).override_failure_message("%s does not report a height" % fn).is_true()
	assert_bool(src.contains("rel = mix(0.5, sett *")).is_true()   # a sett that is too fine for the pixel is flat again (no shimmer)
	assert_bool(src.contains("rel = mix(0.5, edge *")).is_true()
	# the ground is bumped: cobbles, earth, boards, flagstones each set a depth
	for needle in ["depth_in = 0.045;", "depth_in = 0.05;", "depth_in = 0.02;", "depth_in = 0.03;"]:
		assert_bool(src.contains(needle)).override_failure_message("no relief depth `%s`" % needle).is_true()


func test_roughness_follows_the_material_damp_joints_dry_crowns() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	assert_bool(src.contains("rough = mix(0.55, 0.8, smoothstep(0.3, 0.7, crown));")).is_true()   # joint damp 0.55, sett crown 0.8
	assert_bool(src.contains("rough = 0.95;")).is_true()   # packed earth

