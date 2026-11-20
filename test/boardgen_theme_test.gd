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


## The recorded layout with one landmark of every kind (a fountain, a statue plinth, a pool, a hall mark) standing on the board's cells.
func _town_with_every_landmark() -> Dictionary:
	var layout := _town()
	layout["landmarks"] = [{"kind": "TankCluster", "x": 2, "z": 6, "w": 2, "h": 2, "turn": 0, "terrain": 2, "solid": true},
		{"kind": "Crane", "x": 6, "z": 6, "w": 1, "h": 1, "turn": 0, "terrain": 2, "solid": true},
		{"kind": "Sump", "x": 9, "z": 6, "w": 2, "h": 2, "turn": 0, "terrain": 1, "solid": false},
		{"kind": "PumpHouse", "x": 12, "z": 6, "w": 2, "h": 2, "turn": 0, "terrain": 0, "solid": false}]
	return layout


func test_a_town_draws_each_landmark_as_plain_boxes_inside_its_footprint() -> void:
	var layout := _town_with_every_landmark()
	var by_landmark := {}
	for b in BoardgenGreybox.plan(layout):
		if b.has("landmark"):
			by_landmark[b["landmark"]] = by_landmark.get(b["landmark"], []) + [b]
	assert_int(by_landmark.size()).is_equal(4)
	if by_landmark.size() != 4:
		return
	for i in 4:
		var lm: Dictionary = layout["landmarks"][i]
		var lo := Vector2(lm["x"], lm["z"]) * 3.0 - Vector2(24.0, 24.0)
		var hi := lo + Vector2(lm["w"], lm["h"]) * 3.0
		for b: Dictionary in by_landmark[i]:
			assert_bool(b["lo"].x >= lo.x - 0.001 and b["lo"].z >= lo.y - 0.001 and b["hi"].x <= hi.x + 0.001 and b["hi"].z <= hi.y + 0.001).override_failure_message("%s draws outside its footprint" % lm["kind"]).is_true()
			match lm["kind"]:
				"TankCluster", "Crane":
					assert_array([b["kind"], b["solid"], b["hi"].y]).is_equal(["stone", true, 2.5])
					assert_vector(b["hi"] - b["lo"]).is_equal_approx(Vector3(lm["w"] * 3.0, 2.5, lm["h"] * 3.0), Vector3.ONE * 0.001)   # the whole footprint, no taller than the core's container
				"Sump":
					assert_array([b["kind"], b["solid"]]).is_equal(["hazard", false])
					assert_float(b["hi"].y).is_less(0.08)
				"PumpHouse":
					assert_array([b["kind"], b["solid"]]).is_equal(["rim", false])
					assert_float(b["hi"].y - b["lo"].y).is_equal_approx(0.3, 0.001)
	assert_int(by_landmark[3].size()).is_equal(4)   # the rim is four slabs
	var rim_area := 0.0
	for b: Dictionary in by_landmark[3]:
		rim_area += (b["hi"].x - b["lo"].x) * (b["hi"].z - b["lo"].z)
	assert_float(rim_area).is_equal_approx(6.0 * 6.0 - 5.4 * 5.4, 0.001)   # a 0.3 in line round the 6 x 6 in footprint, no overlap, no gap


func test_a_deepworks_plan_has_no_landmark_boxes_and_the_town_gets_the_solid_ones_a_collider() -> void:
	var deep := _fixture()
	deep["landmarks"] = _town_with_every_landmark()["landmarks"]
	assert_bool(BoardgenGreybox.plan(deep).any(func(b: Dictionary) -> bool: return b.has("landmark"))).is_false()   # Deepworks draws its landmarks as meshes
	var layout := _town_with_every_landmark()
	var solids := BoardgenGreybox.plan(layout).filter(func(b: Dictionary) -> bool: return b.has("landmark") and b["solid"])
	assert_int(solids.size()).is_equal(2)
	var body := _built(layout).find_child("Colliders", false, false) as StaticBody3D
	assert_int(body.get_child_count()).is_equal(BoardgenGreybox.plan(layout).filter(func(b: Dictionary) -> bool: return b["solid"]).size())


func _put(layout: Dictionary, x: int, z: int, level: int, kind: String) -> void:
	var c: Dictionary = layout["cells"][z * 16 + x]
	c["level"] = level
	c["lot_kind"] = kind
	c["street"] = false


## The recorded town with an intact house (2 x 2, lot 99), a wall run (stair 3 in, ridge 6 in, tower 9 in, breach at ground) and a garden plot.
func _town_with_wall_house_and_plot() -> Dictionary:
	var layout := _town()
	for dz in 2:
		for dx in 2:
			_put(layout, dx, dz, 0, "Roofed")
	layout["lots"].append({"id": 99, "x": 0, "z": 0, "w": 2, "h": 2, "sector": [0, 0], "kind": "Roofed"})
	for spec in [[5, 5, 1], [5, 6, 2], [5, 7, 3], [5, 8, 0]]:
		_put(layout, spec[0], spec[1], spec[2], "Wall")
	_put(layout, 8, 5, 0, "Rough")
	return layout


func test_a_town_draws_its_wall_its_plots_and_its_intact_houses_with_kinds_of_their_own() -> void:
	var boxes := BoardgenGreybox.plan(_town_with_wall_house_and_plot())
	var of := func(kind: String) -> Array: return boxes.filter(func(b: Dictionary) -> bool: return b["kind"] == kind)
	var roofed: Array = of.call("roofed")
	assert_int(roofed.size()).is_greater(0)
	for b: Dictionary in roofed:
		assert_array([b["solid"], b["hi"].y]).is_equal([true, 2.5])   # the body is as high as the core's solid
	var ridge: Array = of.call("ridge")
	assert_int(ridge.size()).is_equal(2)   # the ridge and the chimney of lot 99
	for b: Dictionary in ridge:
		assert_array([b["ridge"], b["solid"], b["lo"].y, b["hi"].y > 2.5]).is_equal([99, false, 2.5, true])   # above the body, visual only
	var wall_tops: Array = of.call("wall").map(func(b: Dictionary) -> float: return b["hi"].y)
	wall_tops.sort()
	assert_array(wall_tops).is_equal([3.0, 6.0, 9.0])
	assert_int(of.call("rubble").size()).is_equal(1)
	assert_int(of.call("rough").size()).is_equal(1)


func test_a_deepworks_plan_never_uses_the_town_kinds() -> void:
	var layout := _town_with_wall_house_and_plot()
	layout.erase("theme")
	for b in BoardgenGreybox.plan(layout):
		assert_bool(BoardgenGreybox.KINDS.has(b["kind"])).override_failure_message("a Deepworks box of kind %s" % b["kind"]).is_true()
