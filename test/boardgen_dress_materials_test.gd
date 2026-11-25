extends GdUnitTestSuite
## BoardgenDressMaterials (docs/adr/0004-dressing-materials-and-kit-manifest.md): the kit manifest's eleven materials become six set materials of
## ruintown_dress.gdshader and five plain ones; a set that is not cached gives a flat material in its tone, never null. The
## headless run has a dummy renderer, so the shader is pinned by source (it compiles on the real renderer: the PR's display check).

const SHADER := "res://shaders/ruintown_dress.gdshader"
const VEG_SOLID_SHADER := "res://shaders/ruintown_dress_veg_solid.gdshader"
const VEG_CARD_SHADER := "res://shaders/ruintown_dress_veg_card.gdshader"
const VEG_SOLID_SET := ["wrap", "backlight", "roughness", "albedo_scale"]
const VEG_CARD_SET := ["wrap", "backlight", "roughness", "alpha_scissor", "card_tone", "atlas", "atlas_dry"]
## The bundled manifest; checked as well when present.
const BUNDLED := "res://assets/ruintown_dress.json"
## The `materials` block of the first kit manifest, without the later vegetation and fine-stone keys: a frozen copy so the builder is tested independent of manifest edits.
const META := {"materials": {
	"ct_clay": {"colour": [0.28, 0.12, 0.07], "metallic": 0.0, "roughness": 0.85},
	"ct_flags": {"set": "flags", "tile_in": 1.8, "tone": [0.45, 0.45, 0.47], "uv": "world"},
	"ct_glass_dark": {"colour": [0.02, 0.022, 0.025], "metallic": 0.0, "roughness": 0.25},
	"ct_glass_lit": {"colour": [0.9, 0.6, 0.3], "emission": [1.0, 0.62, 0.3], "emission_energy": 2.0, "metallic": 0.0, "roughness": 0.4},
	"ct_iron": {"colour": [0.035, 0.033, 0.03], "metallic": 0.7, "roughness": 0.55},
	"ct_matte": {"colour": [1.0, 1.0, 1.0], "metallic": 0.0, "roughness": 0.92},
	"ct_plaster": {"set": "plaster", "tile_in": 6.0, "tone": [0.68, 0.62, 0.52], "uv": "world"},
	"ct_roof": {"set": "roof_tiles", "tile_in": 3.3, "tone": [0.42, 0.42, 0.44], "uv": "mesh"},
	"ct_stone": {"set": "coursed_stone", "tile_in": 3.0, "tone": [0.42, 0.45, 0.52], "uv": "world"},
	"ct_stone_big": {"set": "coursed_stone", "tile_in": 5.5, "tone": [0.4, 0.43, 0.5], "uv": "world"},
	"ct_timber": {"set": "timber", "tile_in": 3.25, "tone": [0.7, 0.66, 0.62], "uv": "mesh"}}}
const TEXTURED := ["ct_flags", "ct_plaster", "ct_roof", "ct_stone", "ct_stone_big", "ct_timber"]
const SET_UNIFORMS := ["albedo_tex", "normal_tex", "orm_tex", "tile_in", "world_uv", "tone", "normal_depth"]


## A library that answers a texture for the sets it is told are cached.
class FakeLib extends TiefwerkLibrary:
	var cached: Array = []
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGB8))

	func set_texture(set_name: String, _map: String) -> Texture2D:
		return tex if set_name in cached else null


func _lib(cached: Array) -> FakeLib:
	var lib: FakeLib = auto_free(FakeLib.new("ruintown"))
	lib.cached = cached
	return lib


func _check_eleven(meta: Dictionary, stone_big_in: float, count := 11, textured := TEXTURED, stone_fine_in := 0.0) -> void:
	var mats := BoardgenDressMaterials.make(meta, _lib(["flags", "plaster", "roof_tiles", "coursed_stone", "timber"]))
	assert_int(mats.size()).is_equal(count)
	for name: String in mats:
		assert_str(mats[name].resource_name).is_equal(name)
		assert_bool(mats[name] is ShaderMaterial).override_failure_message(name).is_equal(name in textured)
	var stone: ShaderMaterial = mats["ct_stone_big"]
	assert_float(stone.get_shader_parameter("tile_in")).is_equal_approx(stone_big_in, 0.0001)
	assert_float((mats["ct_stone"] as ShaderMaterial).get_shader_parameter("tile_in")).is_equal_approx(3.0, 0.0001)
	if stone_fine_in > 0.0:
		assert_float((mats["ct_stone_fine"] as ShaderMaterial).get_shader_parameter("tile_in")).is_equal_approx(stone_fine_in, 0.0001)
	assert_bool(stone.get_shader_parameter("world_uv")).is_true()
	assert_bool(mats["ct_roof"].get_shader_parameter("world_uv")).is_false()   # roofs keep their mesh UVs
	assert_object(stone.get_shader_parameter("orm_tex")).is_not_null()
	var lit: StandardMaterial3D = mats["ct_glass_lit"]
	assert_bool(lit.emission_enabled).is_true()
	assert_float(lit.emission_energy_multiplier).is_equal_approx(2.0, 0.0001)
	assert_float(mats["ct_iron"].metallic).is_equal_approx(0.7, 0.0001)


func test_the_manifest_gives_eleven_named_materials() -> void:
	_check_eleven(META, 5.5)   # the nominal numbers of the frozen copy above


func test_the_bundled_manifest_gives_thirteen_named_materials_once_it_is_on_main() -> void:
	if not FileAccess.file_exists(BUNDLED):
		return   # a checkout without the bundled manifest still runs the frozen copy above
	# thirteen manifest materials make FOURTEEN surface materials: ct_veg is one entry with a card variant (ct_veg on the solid vegetation shader, ct_veg_card on the card one).
	# PINNED to the current stone scale (ct_stone_big 3.6 in, ct_stone 3.0 in, ct_stone_fine 2.25 in): a later drift of the manifest goes red here.
	_check_eleven(JSON.parse_string(FileAccess.get_file_as_string(BUNDLED)), 3.6, 14, TEXTURED + ["ct_stone_fine", "ct_veg", "ct_veg_card"], 2.25)


func test_a_set_that_is_not_cached_gives_a_flat_material_in_its_tone() -> void:
	for lib: Variant in [_lib(["plaster"]), null]:
		var mats := BoardgenDressMaterials.make(META, lib)
		var flat: Material = mats["ct_stone"]
		assert_bool(flat is StandardMaterial3D).is_true()
		assert_object((flat as StandardMaterial3D).albedo_color).is_equal(Color(0.42, 0.45, 0.52))
		assert_object((flat as StandardMaterial3D).albedo_texture).is_null()
		assert_bool(mats["ct_plaster"] is ShaderMaterial).is_equal(lib != null)
		for name: String in mats:
			assert_object(mats[name]).is_not_null()


func test_the_shader_declares_every_uniform_the_script_sets() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	var rx := RegEx.new()
	rx.compile("(?m)^uniform \\w+ (\\w+)")
	var declared: Array = []
	for m in rx.search_all(src):
		declared.append(m.get_string(1))
	var sm: ShaderMaterial = BoardgenDressMaterials.make(META, _lib(["coursed_stone"]))["ct_stone"]
	for u: String in SET_UNIFORMS:
		assert_bool(u in declared).override_failure_message("the shader lacks `%s`" % u).is_true()
		assert_bool(sm.get_shader_parameter(u) != null).override_failure_message("the script never sets `%s`" % u).is_true()
	for u: String in declared:
		assert_bool(u in SET_UNIFORMS).override_failure_message("`%s` is declared but not set" % u).is_true()
	assert_object(sm.shader).is_equal(load(SHADER))
	assert_bool(src.contains("NORMAL_MAP_DEPTH = normal_depth;")).is_true()
	assert_int(src.count("texture(albedo_tex")).override_failure_message("one continuous lookup per set").is_equal(1)


func _veg_meta() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(BUNDLED))


func test_ct_veg_is_a_solid_material_with_a_card_variant() -> void:
	var meta := _veg_meta()
	for lib: Variant in [_lib(["grass_cards"]), _lib([]), null]:
		var mats := BoardgenDressMaterials.make(meta, lib)
		for name in ["ct_veg", "ct_veg_card"]:
			var sm := mats[name] as ShaderMaterial
			assert_object(sm).is_not_null()   # never null and never flat, with or without the atlas
			assert_str(sm.resource_name).is_equal(name)
			assert_float(sm.get_shader_parameter("wrap")).is_equal_approx(0.4, 0.0001)
			assert_float(sm.get_shader_parameter("backlight")).is_equal_approx(0.7, 0.0001)
		var solid := mats["ct_veg"] as ShaderMaterial
		var card := mats["ct_veg_card"] as ShaderMaterial
		assert_object(solid.shader).is_equal(load(VEG_SOLID_SHADER))
		assert_object(card.shader).is_equal(load(VEG_CARD_SHADER))
		assert_float(solid.get_shader_parameter("albedo_scale")).is_equal_approx(0.14, 0.0001)
		assert_float(card.get_shader_parameter("alpha_scissor")).is_equal_approx(0.4, 0.0001)
		assert_vector(card.get_shader_parameter("card_tone")).is_equal_approx(Vector3(0.15, 0.15, 0.15), Vector3(0.0001, 0.0001, 0.0001))


func test_a_variant_of_any_material_is_the_entry_with_the_variant_keys_laid_over_it() -> void:
	var meta := {"materials": {"ct_x": {"colour": [0.5, 0.5, 0.5], "roughness": 0.3, "variants": {"dark": {"colour": [0.1, 0.1, 0.1]}}}}}
	var mats := BoardgenDressMaterials.make(meta, null)
	assert_array(mats.keys()).contains_exactly_in_any_order(["ct_x", "ct_x_dark"])
	assert_object((mats["ct_x_dark"] as StandardMaterial3D).albedo_color).is_equal(Color(0.1, 0.1, 0.1))
	assert_float((mats["ct_x_dark"] as StandardMaterial3D).roughness).is_equal_approx(0.3, 0.0001)
	assert_str(mats["ct_x_dark"].resource_name).is_equal("ct_x_dark")


func test_the_card_atlas_is_the_set_when_cached_else_transparent_so_nothing_is_drawn() -> void:
	var meta := _veg_meta()
	var lib := _lib(["grass_cards"])
	var cached := BoardgenDressMaterials.make(meta, lib)["ct_veg_card"] as ShaderMaterial
	assert_object(cached.get_shader_parameter("atlas")).is_same(lib.tex)   # the library's texture
	assert_object(cached.get_shader_parameter("atlas_dry")).is_same(lib.tex)
	for none: Variant in [_lib([]), null]:
		var missing := BoardgenDressMaterials.make(meta, none)["ct_veg_card"] as ShaderMaterial
		assert_float((missing.get_shader_parameter("atlas") as ImageTexture).get_image().get_pixel(0, 0).a).is_equal(0.0)   # a card without its atlas draws nothing
		assert_object(missing.get_shader_parameter("atlas_dry")).is_same(missing.get_shader_parameter("atlas"))


## A shader's source with its #include files appended.
func _source(path: String) -> String:
	var src := FileAccess.get_file_as_string(path)
	var rx := RegEx.new()
	rx.compile("(?m)^#include \"([^\"]+)\"")
	for m in rx.search_all(src):
		src += "\n" + FileAccess.get_file_as_string(m.get_string(1))
	return src


func test_each_veg_shader_declares_exactly_the_uniforms_the_script_sets_and_keeps_its_contract() -> void:
	var mats := BoardgenDressMaterials.make(_veg_meta(), _lib(["grass_cards"]))
	var rx := RegEx.new()
	rx.compile("(?m)^uniform \\w+ (\\w+)")
	for spec: Array in [["ct_veg", VEG_SOLID_SHADER, VEG_SOLID_SET], ["ct_veg_card", VEG_CARD_SHADER, VEG_CARD_SET]]:
		var src := _source(spec[1])
		var expected: Array = spec[2]
		var declared: Array = []
		for m in rx.search_all(src):
			declared.append(m.get_string(1))
		var sm := mats[spec[0]] as ShaderMaterial
		for u: String in expected:
			assert_bool(u in declared).override_failure_message("%s lacks `%s`" % [spec[1], u]).is_true()
			assert_bool(sm.get_shader_parameter(u) != null).override_failure_message("the script never sets `%s`" % u).is_true()
		for u: String in declared:
			assert_bool(u in expected).override_failure_message("`%s` is declared in %s but not set" % [u, spec[1]]).is_true()
		for line in ["NORMAL = FRONT_FACING ? NORMAL : -NORMAL;", "render_mode cull_disabled", "DIFFUSE_LIGHT +="]:
			assert_bool(src.contains(line)).override_failure_message("%s lost `%s`" % [spec[1], line]).is_true()   # two-sided with one normal, wrapped + backlit light
	var solid := FileAccess.get_file_as_string(VEG_SOLID_SHADER)
	assert_bool(solid.contains("discard;") or solid.contains("texture(") or solid.contains("ALPHA")).override_failure_message("the solid shader must keep early depth: no discard, no texture, no alpha").is_false()
	assert_bool(FileAccess.get_file_as_string(VEG_CARD_SHADER).contains("ALPHA_SCISSOR_THRESHOLD = alpha_scissor;")).is_true()


## Look review 25.11. (R8): a plain material with every channel under 0.05 renders as a black hole under the specular-free moons (dark window glass on the
## tower caps and slits read as black rectangles). Dark, not a hole: no plain non-metal material of the bundled manifest is below 0.1 in every channel
## (measured at the play distance: glass at 0.06 still rendered at luma 2, at 0.12 / 0.132 / 0.15 at luma 15).
func test_no_plain_material_is_black() -> void:
	if not FileAccess.file_exists(BUNDLED):
		return
	var mats: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BUNDLED))["materials"]
	for name: String in mats:
		var m: Dictionary = mats[name]
		if m.has("set") or not m.has("colour") or float(m.get("metallic", 0.0)) >= 0.5:
			continue   # (a metal's colour is its reflectance: ct_iron is its own question, not this case's)
		var c: Array = m["colour"]
		assert_float(maxf(maxf(float(c[0]), float(c[1])), float(c[2]))).override_failure_message("%s colour %s is black" % [name, c]).is_greater_equal(0.1)
