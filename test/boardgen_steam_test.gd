extends GdUnitTestSuite
## The vent steam of a boardgen layout (BoardgenSteam): a few vents on bare wall faces, a hood that stays in the wall strip, one plume per
## vent, two draw calls, nothing physical, one seed always the same, gone with the mist setting. Stands on the recorded seed 42 layout.

const FIXTURE := "res://test/fixtures/boardgen/layout_42.txt"
const CELL_IN := 3.0


func _fixture() -> Dictionary:
	return str_to_var(FileAccess.get_file_as_string(FIXTURE))


func after_test() -> void:
	GraphicsSettings.show_board_mist = true


func test_one_seed_has_the_same_vents_and_another_seed_others() -> void:
	var layout := _fixture()
	var first := BoardgenSteam.vents(layout)
	assert_int(first.size()).is_between(1, BoardgenSteam.MAX_VENTS)
	randomize()   # the global generator must not matter
	assert_array(BoardgenSteam.vents(layout)).is_equal(first)
	var other := _fixture()
	other["seed"] = 43
	assert_bool(BoardgenSteam.vents(other) == first).is_false()


func test_a_vent_is_on_a_wall_face_of_open_floor_outside_the_deployment_and_off_a_ladder_foot_and_apart() -> void:
	var layout := _fixture()
	var cells: Array = layout["cells"]
	var feet := {}
	for c: Dictionary in layout["connectors"]:
		feet[Vector2i(c["low_xz"][0], c["low_xz"][1])] = true
	var vents := BoardgenSteam.vents(layout)
	for v in vents:
		var cell: Vector2i = v["cell"]
		var floor_cell: Dictionary = cells[cell.y * layout["nx"] + cell.x]
		var wall: Vector2i = cell + v["d"]
		assert_int(floor_cell["level"]).is_equal(0)
		assert_str(floor_cell["lot_kind"]).is_not_equal("Hazard")
		assert_int(int(floor_cell.get("deploy", 0))).is_equal(0)
		assert_bool(feet.has(cell)).is_false()
		assert_int(cells[wall.y * layout["nx"] + wall.x]["level"]).is_greater(0)   # a tier wall is there
		for other in vents:
			if other != v:
				assert_float(v["at"].distance_to(other["at"])).is_greater_equal(BoardgenSteam.MIN_GAP_IN)


func test_no_vent_sits_on_a_wall_face_that_a_prop_already_uses() -> void:
	var layout := _fixture()
	var props := BoardgenProps.plan(layout)
	for v in BoardgenSteam.vents(layout):
		for p in props:
			var at := Vector2(p["xf"].origin.x, p["xf"].origin.z) / BoardgenSteam.INCHES_TO_METERS
			assert_float(at.distance_to(v["at"])).is_greater_equal(BoardgenSteam.PROP_CLEAR_IN - 0.001)


func test_the_hood_stays_in_the_wall_strip_and_above_the_heads_of_the_models() -> void:
	assert_float(BoardgenSteam.HOOD_IN.z + 0.02).is_less_equal(BoardgenProps.STRIP_IN)   # nothing that is not flat reaches further than the strip
	assert_float(BoardgenSteam.VENT_Y_IN - BoardgenSteam.HOOD_IN.y * 0.5).is_greater_equal(1.1)   # clear of a 28 mm miniature


func _board(layout: Dictionary) -> BoardgenGreybox:
	var node: BoardgenGreybox = auto_free(BoardgenGreybox.new())
	add_child(node)
	node.build(layout)
	return node


func test_the_steam_is_two_multimeshes_a_hood_with_slats_and_puffs_per_vent_with_nothing_physical() -> void:
	var layout := _fixture()
	var steam := _board(layout).get_node_or_null("Steam") as BoardgenSteam
	assert_object(steam).is_not_null()
	var n := BoardgenSteam.vents(layout).size()
	var hoods := steam.get_node("Hoods") as MultiMeshInstance3D
	var plumes := steam.get_node("Plumes") as MultiMeshInstance3D
	assert_int(hoods.multimesh.instance_count).is_equal(n * (2 + BoardgenSteam.SLATS))   # hood, grille and slats
	assert_int(plumes.multimesh.instance_count).is_equal(n * BoardgenSteam.PUFFS)   # a handful of billowing puffs per vent
	assert_int(steam.get_child_count()).is_equal(2)
	for part in [hoods, plumes]:
		assert_int((part as GeometryInstance3D).cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(steam.find_children("*", "CollisionObject3D", true, false).size()).is_equal(0)


func test_the_setting_removes_and_restores_the_steam_with_the_mist() -> void:
	var node := _board(_fixture())
	assert_object(node.get_node_or_null("Steam")).is_not_null()
	GraphicsSettings.show_board_mist = false
	assert_object(node.get_node_or_null("Steam")).is_null()
	assert_object(node.get_node_or_null("GroundFog")).is_null()
	GraphicsSettings.show_board_mist = true
	assert_object(node.get_node_or_null("Steam")).is_not_null()
	assert_object(node.get_node_or_null("GroundFog")).is_not_null()


func test_the_floor_in_front_of_a_vent_gets_thicker_mist() -> void:
	var layout := _fixture()
	var v := BoardgenSteam.vents(layout)[0]
	var cell: Vector2i = v["cell"]
	var plain := BoardgenMist.density(layout)[(cell.y * layout["nx"] + cell.x) * 2]
	var vented := BoardgenMist.density(layout, [cell])[(cell.y * layout["nx"] + cell.x) * 2]
	assert_int(vented).is_greater_equal(int(0.75 * 255) - 1)
	assert_int(vented).is_greater_equal(plain)


func test_no_vent_stands_behind_a_landmark() -> void:
	var layout := _fixture()
	var free := BoardgenSteam.vents(layout)
	assert_int(free.size()).is_greater(0)
	var cell: Vector2i = free[0]["cell"]
	layout["landmarks"] = [{"kind": "TankCluster", "x": cell.x, "z": cell.y, "w": 2, "h": 2}]   # a cluster on the first vent's own floor cell
	for v in BoardgenSteam.vents(layout):
		assert_bool(absi(v["cell"].x - cell.x) <= 1 and absi(v["cell"].y - cell.y) <= 1).override_failure_message("a vent next to a landmark: %s" % str(v["cell"])).is_false()


func test_the_puff_shader_faces_the_camera_billows_and_is_lit_by_the_board_lamps() -> void:
	var src := FileAccess.get_file_as_string("res://shaders/tiefwerk_steam.gdshader")
	assert_bool(src.contains("INV_VIEW_MATRIX[0].xyz * VERTEX.x + INV_VIEW_MATRIX[1].xyz * VERTEX.y")).is_true()   # a sprite: never edge-on, from any camera
	assert_bool(src.contains("float size = mix(") and src.contains("pow(t, 0.6)")).is_true()   # a puff swells as it rises
	assert_bool(src.contains("uniform vec3 lamps[8]") and src.contains("float back = ")).is_true()   # warm backlight
	var steam := _board(_fixture()).get_node_or_null("Steam") as BoardgenSteam
	var lamps: PackedVector3Array = ((steam.get_node("Plumes") as MultiMeshInstance3D).material_override as ShaderMaterial).get_shader_parameter("lamps")
	assert_int(lamps.size()).is_equal(BoardgenSteam.LAMP_SLOTS)
	assert_float(lamps[0].y).is_less(10.0)   # the board has lamps: the first slot is a real one, in metres
