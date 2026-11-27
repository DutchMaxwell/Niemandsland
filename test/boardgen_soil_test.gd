extends GdUnitTestSuite
## LOOK5 R20 (the ground is a material): source pins of the soil include. The headless run has a dummy renderer, so the real-display
## capture checks pixels; these pin the include, its feed and the two decisions that keep the ground fair and the palette tone.

const INC := "res://shaders/ruintown_soil.gdshaderinc"


func test_the_board_shader_includes_the_soil_and_the_soil_keeps_each_sets_colour() -> void:
	var board := FileAccess.get_file_as_string("res://shaders/ruintown_board.gdshader")
	assert_bool(board.contains('#include "res://shaders/ruintown_soil.gdshaderinc"')).is_true()
	var inc := FileAccess.get_file_as_string(INC)
	assert_str(inc).is_not_empty()
	for u in ["uniform sampler2DArray soil_alb", "uniform sampler2DArray soil_nrm", "uniform sampler2DArray soil_orh", "uniform float soil_on = 0.0", "uniform float soil_tile", "uniform vec3 soil_mean[4]"]:
		assert_bool(inc.contains(u)).override_failure_message("missing: %s" % u).is_true()
	assert_bool(inc.contains("/ max(soil_mean[")).override_failure_message("v2: no per-channel divide by the set's mean (it greyed every set, attempt 1)").is_false()
	assert_bool(inc.contains("r.c = a * (soil_ceiling(l) / la);")).is_true()   # a SCALAR gain: the set keeps its hue and grain
	assert_bool(inc.contains("textureGrad(soil_alb")).is_true()   # explicit gradients: no mip line at a layer seam
	for c in ["uniform float soil_tier = 1.0", "uniform float soil_fill_sat = 0.35", "const vec4 SOIL_RANK = vec4(1.15, 0.92, 0.85, 0.75)", "const float SOIL_BAND = 0.10"]:
		assert_bool(inc.contains(c)).override_failure_message("missing: %s" % c).is_true()
	assert_bool(inc.contains("SoilSample soil_blend(vec4 w, vec2 xz_in)")).is_true()


## A library whose maps are tiny in-memory textures (the headless renderer cannot load the GPU-compressed sets); `missing` names a set it does not have.
class FakeLib extends TiefwerkLibrary:
	var missing := ""
	func _init() -> void:
		super(BoardgenTheme.TOWN_LIBRARY)
	func set_texture(set_name: String, map: String) -> Texture2D:
		if set_name == missing:
			return null
		var img := Image.create(8 if map == "orm" else 16, 8 if map == "orm" else 16, true, Image.FORMAT_RGBA8)
		img.fill(Color(0.3, 0.2, 0.1))
		img.generate_mipmaps()
		return ImageTexture.create_from_image(img)
	func tile_in(_set_name: String) -> float:
		return 6.0


## LOOK5 S2: the four soil sets reach the material as three texture arrays of four layers each with their tile and means, or not at all.
func test_four_cached_soil_sets_become_three_arrays_and_one_missing_set_keeps_the_soil_off() -> void:
	assert_array(BoardgenTheme.TOWN_SOIL).is_equal(["soil_bare", "soil_mud", "soil_grass", "soil_verge"])
	assert_int(BoardgenTheme.TOWN_SOIL_MEANS.size()).is_equal(4)
	for name: String in BoardgenTheme.TOWN_SOIL:
		var c: Dictionary = BoardgenTheme.TOWN_SOIL_CONTRACT[name]
		var tpi := float(c["px"]) / float(c["tile_in"])
		assert_bool(tpi >= BoardgenTheme.TOWN_TEXELS_PER_IN.x and tpi <= BoardgenTheme.TOWN_TEXELS_PER_IN.y).is_true()
	var lib: FakeLib = auto_free(FakeLib.new())
	var soil := BoardgenGreybox.town_soil(lib)
	for key in ["soil_alb", "soil_nrm", "soil_orh"]:
		assert_object(soil.get(key)).override_failure_message("no %s" % key).is_not_null()
		if soil.has(key):
			assert_int((soil[key] as Texture2DArray).get_layers()).is_equal(4)
	assert_float(float(soil.get("soil_tile", 0.0))).is_equal(6.0)
	assert_int((soil.get("soil_mean", PackedVector3Array()) as PackedVector3Array).size()).is_equal(4)
	lib.missing = "soil_grass"
	assert_dict(BoardgenGreybox.town_soil(lib)).is_empty()
	var src := FileAccess.get_file_as_string("res://scripts/boardgen_greybox.gd")
	assert_bool(src.contains('_material.set_shader_parameter("soil_on", 1.0 if on and _soil_ok else 0.0)')).is_true()   # Medium and up, not Compatibility, all cached


## LOOK5 S6 (Lane S v2): the earth reads the soil under soil_on - the painted branch is skipped, not computed and overwritten; the weights come from the green map's
## three channels; the Night fill carries the soil colour (soil_fill_sat); soil_tier follows the preset.
func test_the_yard_is_a_material_and_the_fill_carries_the_soil() -> void:
	var board := FileAccess.get_file_as_string("res://shaders/ruintown_board.gdshader")
	assert_bool(board.contains("if (soil_on < 0.5) {\n\t\t\t\tvec2 cp = xz * 3.0;")).override_failure_message("the painted earth must be skipped under soil_on").is_true()
	assert_bool(board.contains("vec4 w = vec4(max(1.0 - gm.r - gm.g, 0.0) * (1.0 - gm.b), gm.g * (1.0 - gm.b), gm.r * (1.0 - gm.b), gm.b);")).is_true()
	assert_bool(board.contains("vec3 f = mix(vec3(dot(soil_s, LUMA)) * vec3(0.92, 1.0, 1.10), soil_s, soil_fill_sat);")).is_true()
	assert_bool(board.contains("uniform float soil_debug = 0.0;")).is_true()
	# (S6 v3 B0) the debug exit draws the heaviest class only: a sum of the weights let a bare + grass mix pass for verge (red + green = yellow)
	assert_bool(board.contains("w.x * vec3(")).override_failure_message("the soil debug exit must not sum the weights' colours").is_false()
	assert_bool(board.contains("soil_dbg = w.x >= max(max(w.y, w.z), w.w) ? vec3(1.0, 0.0, 0.0)")).is_true()
	assert_bool(board.contains("soil_dbg = vec3(4.0 * sm.k.x * sm.k.y);")).is_true()
	var grey := FileAccess.get_file_as_string("res://scripts/boardgen_greybox.gd")
	assert_bool(grey.contains("BoardgenTownGreen.apply(mat, layout)")).is_true()
	assert_bool(grey.contains('_material.set_shader_parameter("soil_tier"')).is_true()
