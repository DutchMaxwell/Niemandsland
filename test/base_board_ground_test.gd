extends GdUnitTestSuite
## Ticket BASE-GROUND: a model on a generated board stood on a disc of the BIOME ground (a base on cobbles showed grass). The board bakes its own
## surfaces from above (BoardgenGroundBake) and hands the texture to the table's shared base-top material; both base-top shaders sample it by
## world xz; the board leaving hands the bases back to the biome.

const TableScript := preload("res://scripts/table.gd")
const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const BAKE := "res://scripts/boardgen_ground_bake.gd"   # loaded by path: on a tree without it the test fails instead of not parsing
const BASE_SHADERS := ["res://shaders/base_terrain_top.gdshader", "res://shaders/visual/reference_ground_table.gdshader"]


class StubTable extends Node3D:   # what the board needs of table.gd
	var ground: Texture2D = null
	var rect := Rect2(1, 1, 1, 1)
	var calls := 0

	func set_flat_rect(_rect: Rect2) -> void:
		pass

	func set_board_ground(albedo: Texture2D, at: Rect2) -> void:
		ground = albedo
		rect = at
		calls += 1


func test_the_table_hands_the_board_ground_to_every_base_and_takes_it_back() -> void:
	var table: TableScript = auto_free(TableScript.new())
	assert_bool(table.has_method("set_board_ground")).override_failure_message("the table has no board-ground hook").is_true()
	if not table.has_method("set_board_ground"):
		return
	var mat := table.get_base_top_material()
	assert_bool(mat.get_shader_parameter("has_board") == true).is_false()   # (unset = null: the shader default false)
	var tex := ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	table.call("set_board_ground", tex, Rect2(-0.5, -0.25, 1.0, 0.5))
	assert_bool(mat.get_shader_parameter("has_board")).is_true()
	assert_object(mat.get_shader_parameter("board_albedo")).is_same(tex)
	assert_that(mat.get_shader_parameter("board_rect")).is_equal(Vector4(-0.5, -0.25, 1.0, 2.0))
	table.call("set_board_ground", null, Rect2())
	assert_bool(mat.get_shader_parameter("has_board")).is_false()
	assert_object(mat.get_shader_parameter("board_albedo")).is_null()


func test_both_base_top_shaders_sample_the_board_ground() -> void:
	for path: String in BASE_SHADERS:
		var names := (load(path) as Shader).get_shader_uniform_list(true).map(func(u: Dictionary) -> String: return u["name"])
		for want: String in ["board_albedo", "has_board", "board_rect"]:
			assert_bool(names.has(want)).override_failure_message("%s lacks %s" % [path, want]).is_true()


func test_the_bake_keeps_the_board_aspect_and_caps_its_size() -> void:
	assert_bool(ResourceLoader.exists(BAKE)).override_failure_message("no ground bake").is_true()
	if not ResourceLoader.exists(BAKE):
		return
	var bake: GDScript = load(BAKE)
	assert_that(bake.pixels(Vector2(1.2192, 1.2192))).is_equal(Vector2i(2032, 2032))
	assert_that(bake.pixels(Vector2(1.2192, 0.6096))).is_equal(Vector2i(2032, 1016))
	assert_that(bake.pixels(Vector2(6.0, 3.0))).is_equal(Vector2i(4096, 2048))


func test_a_board_leaving_gives_the_bases_back_to_the_biome() -> void:
	var table: StubTable = auto_free(StubTable.new())
	add_child(table)
	var board := BoardgenGreybox.attach(table, str_to_var(FileAccess.get_file_as_string(FIXTURE)))
	await get_tree().process_frame   # the bake is deferred; headless it draws nothing and hands nothing over
	assert_object(table.ground).is_null()
	table.remove_child(board)
	board.free()
	assert_int(table.calls).is_greater(0)
	assert_bool(table.rect.has_area()).override_failure_message("the board left and the bases kept its ground").is_false()
