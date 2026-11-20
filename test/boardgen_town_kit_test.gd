extends GdUnitTestSuite
## BoardgenTownKit (ruintown phase B): the authored roofs, chimneys, merlons and breach heaps stand where the procedural pieces stood, and the
## greybox swaps to them only when every module is there (dev folder of fixture GLBs written at run time; no network).

const DIR := "user://boardgen_town_kit_test"


func _town() -> Dictionary:
	var layout: Dictionary = str_to_var(FileAccess.get_file_as_string("res://test/fixtures/boardgen/layout_42.txt"))
	layout["theme"] = "RuinTown"
	for spec in [[0, 0, 0, "Roofed"], [1, 0, 0, "Roofed"], [5, 7, 3, "Wall"], [5, 8, 0, "Wall"], [5, 6, 2, "Wall"]]:
		var c: Dictionary = layout["cells"][spec[1] * 16 + spec[0]]
		c["level"] = spec[2]
		c["lot_kind"] = spec[3]
		c["street"] = false
	layout["lots"].append({"id": 99, "x": 0, "z": 0, "w": 2, "h": 1, "sector": [0, 0], "kind": "Roofed"})
	var placed := 0
	for z in range(15, 8, -1):   # a few more intact houses on free ground (a 2 x 1 pair of cells with no lot), so that at least one roof is a gable whatever the hashes pick
		for x in range(0, 15, 3):
			var a: Dictionary = layout["cells"][z * 16 + x]
			var b: Dictionary = layout["cells"][z * 16 + x + 1]
			if placed < 6 and a["lot_id"] == 0 and b["lot_id"] == 0 and not a["street"] and not b["street"] and a["level"] == 0 and b["level"] == 0:
				layout["lots"].append({"id": 100 + placed, "x": x, "z": z, "w": 2, "h": 1, "sector": [0, 0], "kind": "Roofed"})
				for c: Dictionary in [a, b]:
					c["lot_id"] = 100 + placed
					c["lot_kind"] = "Roofed"
				placed += 1
	return layout


func _count(plan: Dictionary, prefix: String) -> int:
	var n := 0
	for m: String in plan:
		if m.begins_with(prefix):
			n += plan[m].size()
	return n


func test_every_piece_gets_one_module_where_the_procedural_one_stood() -> void:
	var layout := _town()
	var plan := BoardgenTownKit.plan(layout)
	var roofs := BoardgenTownDressing.roofs(layout).filter(func(r: Dictionary) -> bool: return r["type"] == "gable").size()   # the kit draws the gable roofs; hips and catslides stay procedural
	assert_int(roofs).is_greater(0)
	assert_int(_count(plan, "roof_") - _count(plan, "roof_rafters")).is_equal(roofs)
	assert_int(_count(plan, "roof_rafters")).is_equal(_count(plan, "roof_broken"))   # a broken roof shows its frame
	assert_int(_count(plan, "chimney")).is_equal(BoardgenTownDressing.chimneys(layout).size())
	assert_int(_count(plan, "merlon")).is_equal(BoardgenTownDressing.merlons(layout).size() + BoardgenTownDressing.hall_merlons(layout).size())
	for m: String in plan:
		assert_bool(BoardgenTownKit.MODULES.has(m) or BoardgenTownKit.set_of(m) != "").is_true()   # a K-R1 module or an authored clutter one (A2 / A2b / A6, BoardgenTownClutter)


func test_a_breach_gets_a_heap_against_the_wall_end_facing_into_the_gap() -> void:
	var plan := BoardgenTownKit.plan(_town())   # breach (5, 8), wall above it at (5, 7); (5, 9) is open ground
	assert_int(_count(plan, "rubble_")).is_equal(1)
	var heap: String = plan.keys().filter(func(m: String) -> bool: return m.begins_with("rubble_"))[0]
	var xf: Transform3D = plan[heap][0]["xf"]
	assert_vector(xf.basis.z).is_equal_approx(Vector3(0, 0, 1), Vector3.ONE * 0.001)   # heaped into the breach (+z), not into the wall
	assert_float(xf.origin.z).is_equal_approx((8 - 8) * 3.0 * 0.0254, 0.0001)   # on the wall face: the breach cell's north edge


func test_the_kit_replaces_chimney_and_merlon_boxes_only() -> void:
	var layout := _town()
	assert_bool(BoardgenTownDressing.chimneys(layout).all(BoardgenTownKit.replaces)).is_true()
	assert_bool(BoardgenTownDressing.merlons(layout).all(BoardgenTownKit.replaces)).is_true()
	assert_bool(BoardgenTownKit.replaces({"kind": "wall", "solid": true})).is_false()
	assert_str(BoardgenTownKit.set_of("roof_gable_low")).is_equal("roof_tiles")
	assert_str(BoardgenTownKit.set_of("roof_rafters")).is_equal("timber")
	assert_str(BoardgenTownKit.set_of("merlon")).is_equal("coursed_stone")


func _built() -> BoardgenGreybox:
	var node: BoardgenGreybox = auto_free(BoardgenGreybox.new())
	node.build(_town())
	add_child(node)
	return node


func test_the_greybox_swaps_to_the_kit_only_when_every_module_is_there() -> void:
	assert_object(_built().get_node_or_null("TownKit")).is_null()   # no module: the procedural roofs stay
	DirAccess.make_dir_recursive_absolute(DIR)
	for m: String in BoardgenTownKit.MODULES:
		var holder := MeshInstance3D.new()
		holder.mesh = BoxMesh.new()
		var state := GLTFState.new()
		var doc := GLTFDocument.new()
		doc.append_from_scene(holder, state)
		doc.write_to_filesystem(state, "%s/%s.glb" % [DIR, m])
		holder.free()
	OS.set_environment("NML_RUINTOWN_KIT_DIR", ProjectSettings.globalize_path(DIR))
	var node := _built()
	OS.unset_environment("NML_RUINTOWN_KIT_DIR")
	assert_object(node.get_node_or_null("TownKit")).is_not_null()
	assert_int((node.get_node("TownDressing/Roofs") as MultiMeshInstance3D).multimesh.instance_count).is_equal(0)   # no prism under the kit roof
	var kinds := BoardgenTheme.TOWN_KINDS
	var surfaces := (node.get_node("Surfaces") as MultiMeshInstance3D).multimesh
	for i in surfaces.instance_count:
		assert_str(kinds[int(surfaces.get_instance_custom_data(i).r)]).is_not_equal("brick")   # no chimney box left
