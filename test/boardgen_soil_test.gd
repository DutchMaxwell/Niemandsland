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
