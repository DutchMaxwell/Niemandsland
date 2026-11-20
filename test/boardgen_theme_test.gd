extends GdUnitTestSuite
## The theme table of a generated board (BoardgenTheme) and the ruin-town greybox: the town draws none of the Deepworks dressing (no pipe,
## lamp or tank), knows its own surface kinds and colours, and marks the level-0 rest of a half-collapsed house as a yard. The town layout
## is the recorded seed-42 one with its `theme` key set, so this suite stands on its own (no live core needed).

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const DEEPWORKS_DRESSING := ["Props", "Landmarks", "Debris", "Sumps", "Rails"]


func _fixture() -> Dictionary:
	return str_to_var(FileAccess.get_file_as_string(FIXTURE))


func _town() -> Dictionary:
	var layout := _fixture()
	layout["theme"] = "RuinTown"
	return layout


func _built(layout: Dictionary) -> BoardgenGreybox:
	var node: BoardgenGreybox = auto_free(BoardgenGreybox.new())
	add_child(node)
	node.build(layout)
	return node


func test_a_town_board_draws_no_pipe_lamp_or_tank() -> void:
	var node := _built(_town())
	for dressing in DEEPWORKS_DRESSING:
		assert_object(node.find_child(dressing, false, false)).override_failure_message("a town board built %s" % dressing).is_null()
	assert_object(node.find_child("Surfaces", false, false)).is_not_null()
	assert_object(node.find_child("Colliders", false, false)).is_not_null()
	assert_str(node.layout_theme).is_equal("RuinTown")


func test_a_deepworks_board_keeps_all_its_dressing() -> void:
	var node := _built(_fixture())
	for dressing in DEEPWORKS_DRESSING:
		assert_object(node.find_child(dressing, false, false)).override_failure_message("a Deepworks board lost %s" % dressing).is_not_null()


func test_the_theme_table_names_shader_kinds_and_one_colour_per_kind() -> void:
	var town := BoardgenTheme.of(_town())
	assert_str(town["id"]).is_equal("RuinTown")
	assert_str((town["shader"] as Shader).resource_path).is_equal("res://shaders/ruintown_board.gdshader")
	assert_int(town["palette"].size()).is_equal(town["kinds"].size())
	assert_array(town["kinds"].slice(0, BoardgenGreybox.KINDS.size())).is_equal(BoardgenGreybox.KINDS)   # the town extends the Deepworks seven
	assert_array(town["dressing"]).is_empty()
	for layout in [_fixture(), {"theme": "Nowhere"}]:   # no key, or an id the table does not know = Deepworks
		var deep := BoardgenTheme.of(layout)
		assert_str(deep["id"]).is_equal("Deepworks")
		assert_array(deep["kinds"]).is_equal(BoardgenGreybox.KINDS)
		assert_array(deep["dressing"]).is_equal(DEEPWORKS_DRESSING)
		assert_str((deep["shader"] as Shader).resource_path).is_equal("res://shaders/tiefwerk_board.gdshader")


func test_a_town_marks_the_level_0_rest_of_a_terrace_as_a_yard() -> void:
	var town := _town()
	var want := 0
	for c: Dictionary in town["cells"]:
		want += int(c["level"] == 0 and c["lot_kind"] == "Terrace" and not c["street"])
	assert_int(want).is_greater(0)
	var area := 0.0
	for b in BoardgenGreybox.plan(town):
		assert_bool(BoardgenTheme.TOWN_KINDS.has(b["kind"])).override_failure_message("the town plan has a kind its shader lacks: %s" % b["kind"]).is_true()
		if b["kind"] == "yard":
			area += (b["hi"].x - b["lo"].x) * (b["hi"].z - b["lo"].z)
	assert_float(area).is_equal(want * 9.0)
	for b in BoardgenGreybox.plan(_fixture()):
		assert_str(b["kind"]).is_not_equal("yard")


func test_the_town_material_gets_its_shader_and_a_palette_and_each_box_its_town_kind() -> void:
	var town := _town()
	var mat := (_built(town).find_child("Surfaces", false, false) as MultiMeshInstance3D).material_override as ShaderMaterial
	assert_str(mat.shader.resource_path).is_equal("res://shaders/ruintown_board.gdshader")
	assert_int((mat.get_shader_parameter("palette") as PackedColorArray).size()).is_equal(BoardgenTheme.TOWN_KINDS.size())
	for b in BoardgenGreybox.plan(town):
		assert_float(BoardgenGreybox.custom_data(b, BoardgenTheme.TOWN_KINDS).r).is_equal(float(BoardgenTheme.TOWN_KINDS.find(b["kind"])))


func test_the_town_has_no_tiefwerk_mist_or_steam_and_a_deepworks_board_keeps_both() -> void:
	assert_array(BoardgenTheme.of(_town())["atmosphere"]).is_empty()
	assert_array(BoardgenTheme.of(_fixture())["atmosphere"]).is_equal(["Mist", "Steam"])
	var node := _built(_town())
	node.refresh_atmosphere()
	assert_object(node.get_node_or_null("Mist")).is_null()
	assert_object(node.get_node_or_null("Steam")).is_null()