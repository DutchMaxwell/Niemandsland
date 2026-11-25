extends GdUnitTestSuite
## The table round the ruin town (plan PLAN_RUINTOWN_TEXTURES step 8, D-TEX4 (a)): a plane of board size + 36 in a side under the town only, no collider, no shadow,
## gone with the board, its contact shadow on the table's rim; its far edge fades into the town sky's own colour (one shared formula, so the two cannot drift apart).

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"


class StubTable extends Node3D:   # what the surround reads of table.gd: the size in feet and the resize signal
	signal table_resized(size_feet: Vector2)
	var table_size := Vector2(4, 4)


func _town() -> Dictionary:
	var core: Object = ClassDB.instantiate("NmlCore") if ClassDB.class_exists("NmlCore") else null
	return core.boardgen_layout_themed(7, "ruintown") if core != null and core.has_method("boardgen_layout_themed") else {}


func test_the_deepworks_board_has_no_surround() -> void:
	var table: StubTable = auto_free(StubTable.new())
	add_child(table)
	var board := BoardgenGreybox.attach(table, str_to_var(FileAccess.get_file_as_string(FIXTURE)))
	assert_object(board.get_node_or_null("Surround")).is_null()
	assert_bool(board.is_in_group(BoardgenGreybox.HIDES_LANDSCAPE_GROUP)).override_failure_message("a meadow round the undercity").is_true()
	table.remove_child(board)
	board.free()


func test_the_board_and_the_presenter_name_the_same_landscape_group() -> void:
	assert_str(BoardgenGreybox.HIDES_LANDSCAPE_GROUP).is_equal(TableBiomePresenter.HIDES_LANDSCAPE_GROUP)


func test_the_town_stands_on_a_plank_table_that_leaves_with_it() -> void:
	var layout := _town()
	if layout.is_empty():
		return   # (no NmlCore binding in this run)
	var table: StubTable = auto_free(StubTable.new())
	add_child(table)
	var board := BoardgenGreybox.attach(table, layout)
	assert_bool(board.is_in_group(BoardgenGreybox.HIDES_LANDSCAPE_GROUP)).override_failure_message("the town keeps its landscape").is_false()
	var s := board.get_node_or_null("Surround") as MeshInstance3D
	assert_object(s).override_failure_message("the town has no surround: the void is back").is_not_null()
	if s == null:
		table.remove_child(board)
		board.free()
		return
	var side := float(layout["nx"]) * float(layout["cell_in"]) + 72.0
	assert_vector((s.mesh as PlaneMesh).size).is_equal_approx(Vector2(side, float(layout["nz"]) * float(layout["cell_in"]) + 72.0) * 0.0254, Vector2.ONE * 0.0001)
	assert_float(s.position.y).is_equal_approx(-0.002, 0.00001)
	assert_int(s.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_array(s.find_children("*", "CollisionObject3D", true, false)).is_empty()
	var mat := s.material_override as ShaderMaterial
	assert_str(mat.shader.resource_path).is_equal("res://shaders/ruintown_surround.gdshader")
	assert_vector(mat.get_shader_parameter("table_half")).is_equal_approx(Vector2(0.6246, 0.6246), Vector2.ONE * 0.0001)
	table.table_resized.emit(Vector2(6, 4))   # the table grows under the board: the contact shadow follows its rim
	assert_vector(mat.get_shader_parameter("table_half")).is_equal_approx(Vector2(0.9294, 0.6246), Vector2.ONE * 0.0001)
	var gone: WeakRef = weakref(s)
	table.remove_child(board)
	board.free()
	assert_object(gone.get_ref()).override_failure_message("the surround outlived its board").is_null()


func test_the_surround_fades_into_the_sky_by_the_same_formula() -> void:
	var sky := FileAccess.get_file_as_string("res://shaders/ruintown_sky.gdshader")
	var surround := FileAccess.get_file_as_string("res://shaders/ruintown_surround.gdshader")
	for src: String in [sky, surround]:
		assert_str(src).contains('#include "res://shaders/ruintown_sky.gdshaderinc"')
	assert_str(sky).contains("vec3 col = town_sky(EYEDIR);")
	assert_str(surround).contains("EMISSION = town_sky(")
	assert_str(surround).contains("* (1.0 - f)")   # the albedo goes to 0 where the sky colour takes over


## Look review 3: the key light has a visible disc in the town sky, exactly at the light's direction (LIGHT0_DIRECTION) - a pale moon for a cool key, a warm sun for a
## warm one. Sky shader only: nothing on the board.
func test_the_town_sky_shows_the_key_lights_disc_where_its_light_comes_from() -> void:
	var sky := FileAccess.get_file_as_string("res://shaders/ruintown_sky.gdshader")
	assert_str(sky).contains("dot(EYEDIR, LIGHT0_DIRECTION)")
	assert_str(sky).contains("LIGHT0_ENABLED")
	assert_str(sky).contains("uniform float disc_strength = 1.0;")
	assert_str(sky).contains("LIGHT0_COLOR")
