extends GdUnitTestSuite
## BoardgenDressMaterials (plan RUINTOWN_DRESSING step 7): the kit manifest's eleven materials become six set materials of
## ruintown_dress.gdshader and five plain ones; a set that is not cached gives a flat material in its tone, never null. The
## headless run has a dummy renderer, so the shader is pinned by source (it compiles on the real renderer: the PR's display check).

const SHADER := "res://shaders/ruintown_dress.gdshader"
## The bundled manifest of step 3; checked as well once it is on main.
const BUNDLED := "res://assets/ruintown_dress.json"
## The `materials` block of the kit manifest (dress_kit K0, 22.11.), without the step-14 keys.
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
## Declared for a later step and not set in v1 (the ground sets' parallax).
const RESERVED := ["height_tex"]


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


func _check_eleven(meta: Dictionary, stone_big_in: float, count := 11) -> void:
	var mats := BoardgenDressMaterials.make(meta, _lib(["flags", "plaster", "roof_tiles", "coursed_stone", "timber"]))
	assert_int(mats.size()).is_equal(count)
	for name: String in mats:
		assert_str(mats[name].resource_name).is_equal(name)
		assert_bool(mats[name] is ShaderMaterial).override_failure_message(name).is_equal(name in TEXTURED)
	var stone: ShaderMaterial = mats["ct_stone_big"]
	assert_float(stone.get_shader_parameter("tile_in")).is_equal_approx(stone_big_in, 0.0001)
	assert_float((mats["ct_stone"] as ShaderMaterial).get_shader_parameter("tile_in")).is_equal_approx(3.0, 0.0001)
	assert_bool(stone.get_shader_parameter("world_uv")).is_true()
	assert_bool(mats["ct_roof"].get_shader_parameter("world_uv")).is_false()   # roofs keep their mesh UVs
	assert_object(stone.get_shader_parameter("orm_tex")).is_not_null()
	var lit: StandardMaterial3D = mats["ct_glass_lit"]
	assert_bool(lit.emission_enabled).is_true()
	assert_float(lit.emission_energy_multiplier).is_equal_approx(2.0, 0.0001)
	assert_float(mats["ct_iron"].metallic).is_equal_approx(0.7, 0.0001)


func test_the_manifest_gives_eleven_named_materials() -> void:
	_check_eleven(META, 5.5)   # the K0 nominal numbers of the copy above


func test_the_bundled_manifest_gives_twelve_named_materials_once_it_is_on_main() -> void:
	if not FileAccess.file_exists(BUNDLED):
		return   # step 3 (lane CORE) copies it in; until then the copy above is the manifest
	_check_eleven(JSON.parse_string(FileAccess.get_file_as_string(BUNDLED)), 3.6, 12)   # the twelfth is ct_veg (vegetation, a flat placeholder until step 14b)   # PINNED to the stone scale ruled 22.11. (ct_stone_big 3.6 in, ct_stone 3.0 in): a later drift of the manifest goes red here


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
		assert_bool(u in SET_UNIFORMS or u in RESERVED).override_failure_message("`%s` is declared but not set" % u).is_true()
	assert_object(sm.shader).is_equal(load(SHADER))
	assert_bool(src.contains("NORMAL_MAP_DEPTH = normal_depth;")).is_true()
	assert_int(src.count("texture(albedo_tex")).override_failure_message("one continuous lookup per set").is_equal(1)
