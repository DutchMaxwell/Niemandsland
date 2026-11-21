extends GdUnitTestSuite
## The authored T-R1 surface sets in the town shader (plan R9, lead 21.11.): coursed stone, plaster, timber and earth are read when the library has them cached and the shader keeps its
## procedural surface otherwise. The headless run has a dummy renderer, so the shader is pinned by source and the binding by the library's own cache state.

const SHADER := "res://shaders/ruintown_board.gdshader"
const DEV_LIB := "/home/andreaskesberg/nml-mission/wave1116/ruintown_assets/lib_dev"


func test_no_cached_set_means_every_set_is_off_and_the_shader_keeps_its_procedural_look() -> void:
	var lib: TiefwerkLibrary = auto_free(TiefwerkLibrary.new(BoardgenTheme.TOWN_LIBRARY))
	var sets := BoardgenGreybox.town_sets(lib)
	assert_object(sets["t_on"]).is_equal(Vector4.ZERO)
	for suffix in ["stone", "plaster", "timber", "earth"]:
		assert_bool(sets.has("t_" + suffix)).is_false()   # nothing bound: the shader's sampler stays at its default and t_on = 0 says do not read it
	var table := BoardgenGreybox.town_sets(auto_free(TiefwerkLibrary.new(BoardgenTheme.TOWN_LIBRARY)))
	assert_dict(table).is_equal(sets)


func test_a_manifest_without_files_in_the_cache_is_still_off() -> void:
	var lib: TiefwerkLibrary = auto_free(TiefwerkLibrary.new(BoardgenTheme.TOWN_LIBRARY))
	lib.apply_manifest_text(JSON.stringify({"godot_version": "4.6", "base_url": "https://cdn/", "sets": {"plaster": {"tile_in": 3.0, "albedo": {"url": "a.ctex", "sha256": "town_missing_a", "size": 1},
		"normal": {"url": "n.ctex", "sha256": "town_missing_n", "size": 1}, "orm": {"url": "o.ctex", "sha256": "town_missing_o", "size": 1}}}}))
	assert_object(BoardgenGreybox.town_sets(lib)["t_on"]).is_equal(Vector4.ZERO)


func test_the_shader_reads_the_four_sets_with_a_procedural_fallback_and_the_means_match_the_theme() -> void:
	var src := FileAccess.get_file_as_string(SHADER)
	for u in ["uniform sampler2D t_stone", "uniform sampler2D t_plaster", "uniform sampler2D t_timber", "uniform sampler2D t_earth", "uniform sampler2D n_stone", "uniform vec4 t_on = vec4(0.0);"]:
		assert_bool(src.contains(u)).override_failure_message("missing `%s`" % u).is_true()
	assert_bool(src.contains("if (t_on.x < 0.5) {\n		return false;")).override_failure_message("a missing stone set must fall back to the procedural stone").is_true()
	assert_bool(src.contains("ALBEDO = pow(alb, vec3(2.2)) * tex_ratio;")).is_true()   # the set's detail is a ratio to its mean: the palette tone survives
	assert_bool(src.contains("clamp(texture(t, uv).rgb / mean, vec3(0.3), vec3(2.6))")).is_true()
	var rx := RegEx.new()
	rx.compile("const vec3 MEAN_([A-Z]+) = vec3\\(([0-9.]+), ([0-9.]+), ([0-9.]+)\\);")
	var seen := 0
	for m in rx.search_all(src):
		var want: Vector3 = BoardgenTheme.TOWN_SET_MEANS[m.get_string(1).to_lower()]
		assert_vector(Vector3(float(m.get_string(2)), float(m.get_string(3)), float(m.get_string(4)))).is_equal_approx(want, Vector3.ONE * 0.0005)
		seen += 1
	assert_int(seen).is_equal(4)


func test_the_staged_dev_library_binds_all_four_sets_when_the_renderer_can_load_them() -> void:
	if not DirAccess.dir_exists_absolute(DEV_LIB):
		return   # the assets lane's staged folder is not on this machine
	OS.set_environment("NML_RUINTOWN_LIB_DIR", DEV_LIB)
	var lib: TiefwerkLibrary = auto_free(TiefwerkLibrary.new(BoardgenTheme.TOWN_LIBRARY))
	OS.unset_environment("NML_RUINTOWN_LIB_DIR")
	var sets := BoardgenGreybox.town_sets(lib)
	if (sets["t_on"] as Vector4) == Vector4.ZERO:
		return   # a dummy renderer cannot load the GPU-compressed textures: nothing to assert here, the real-display capture does
	assert_object(sets["t_on"]).is_equal(Vector4.ONE)
	assert_float((sets["t_tile"] as Vector4).x).is_equal_approx(1.3, 0.001)   # coursed stone at 0.24 in courses
