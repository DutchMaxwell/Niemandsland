extends GdUnitTestSuite
## The authored surfaces of the board (AAA step 10): the greybox wires exactly the uniforms the shader declares, only when all twelve
## textures are cached, and the shader's hook runs only behind t1_on and detail (so Low, web and an empty cache stay procedural).

const INCLUDE := "res://shaders/tiefwerk_t1.gdshaderinc"
const BOARD := "res://shaders/tiefwerk_board.gdshader"


## A library with every texture cached, except the one named in `missing` ("set/map").
class FakeLibrary extends TiefwerkLibrary:
	var missing := ""

	func set_texture(set_name: String, map: String) -> Texture2D:
		return null if "%s/%s" % [set_name, map] == missing else PlaceholderTexture2D.new()


func _wire(missing: String) -> Array:
	var lib := FakeLibrary.new()
	lib.missing = missing
	add_child(lib)
	auto_free(lib)
	var mat := ShaderMaterial.new()
	mat.shader = BoardgenGreybox.SHADER
	return [BoardgenGreybox.wire_surfaces(mat, lib), mat]


func test_every_uniform_the_greybox_wires_is_declared_in_the_include() -> void:
	var src := FileAccess.get_file_as_string(INCLUDE)
	assert_bool(src.contains("uniform float t1_on")).is_true()
	for i in BoardgenGreybox.T1_SETS.size():
		for short: String in BoardgenGreybox.T1_MAPS:
			assert_bool(src.contains("uniform sampler2D t1_%s_%d " % [short, i])).override_failure_message("t1_%s_%d is not declared" % [short, i]).is_true()


func test_a_full_cache_is_wired_and_switched_on() -> void:
	var r := _wire("")
	assert_bool(r[0]).is_true()
	assert_float(r[1].get_shader_parameter("t1_on")).is_equal(1.0)
	assert_object(r[1].get_shader_parameter("t1_nrm_3")).is_not_null()


func test_one_missing_texture_leaves_the_board_procedural() -> void:
	var r := _wire("concrete/orm")
	assert_bool(r[0]).is_false()
	assert_object(r[1].get_shader_parameter("t1_on")).is_null()


func test_the_shader_hook_sits_behind_t1_on_and_detail() -> void:
	var cond := ""
	for line in FileAccess.get_file_as_string(BOARD).split("\n"):
		if line.contains("t1_on > 0.5"):
			cond = line
	assert_bool(cond.contains("detail > 0.5") and cond.contains("k != 5")).override_failure_message("hook condition: %s" % cond).is_true()
