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
	assert_int(_count(plan, "merlon")).is_equal(BoardgenTownDressing.merlons(layout).size())
	for m: String in plan:
		assert_bool(BoardgenTownKit.MODULES.has(m) or BoardgenTownKit.set_of(m) != "").is_true()   # a K-R1 module or an authored clutter one (A2 / A2b / A6, BoardgenTownClutter)


func test_a_breach_gets_a_heap_against_the_wall_end_facing_into_the_gap() -> void:
	var plan := BoardgenTownKit.plan(_town())   # breach (5, 8), wall above it at (5, 7); (5, 9) is open ground
	assert_int(_count(plan, "rubble_") - _count(plan, "rubble_heap")).is_equal(1)   # (the yard heaps of BoardgenTownClutter are rubble_heap_a / b, not the breach heaps)
	var heap: String = plan.keys().filter(func(m: String) -> bool: return m.begins_with("rubble_") and not m.begins_with("rubble_heap"))[0]
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


## Kit batch A7: three merlon joint patterns and a broken one, and a capstone run on the FIELD edge of every wall top that drops there (inside the 0.5 in parapet line, 0.18 in high).
func test_merlon_variants_and_capstones_on_the_field_edge() -> void:
	var layout: Dictionary = ClassDB.instantiate("NmlCore").boardgen_layout_themed(41, "ruintown")
	var plan := BoardgenTownKit.plan(layout)
	assert_bool(plan.has("merlon") or plan.has("merlon_broken")).is_false()
	var kinds := 0
	for m in ["merlon_v1", "merlon_v2", "merlon_v3", "merlon_v4"]:
		kinds += 1 if plan.has(m) else 0
	assert_int(kinds).is_equal(4)
	assert_int(_count(plan, "merlon_v")).is_equal(BoardgenTownDressing.merlons(layout).size())
	var runs := 0
	for m in ["coping_a", "coping_b", "coping_c"]:
		for item: Dictionary in plan.get(m, []):
			runs += 1
			var p: Vector3 = item["xf"].origin / 0.0254 + Vector3(24, 0, 24)
			var edge := fposmod(p.x, 3.0)
			var c := Vector2i(int(p.x / 3.0), int(p.z / 3.0))
			var cd: Dictionary = layout["cells"][c.y * 16 + c.x]
			assert_str(cd["lot_kind"]).is_equal("Wall")
			assert_float(p.y).is_equal_approx(float(layout["level_in"][int(cd["level"])]), 0.001)   # on the wall's top
			assert_float(edge if c.x * 2 < 16 else 3.0 - edge).is_equal_approx(0.25, 0.001)   # 0.25 in in from the field edge
	assert_int(runs).is_greater(10)


## While an A7 module is not cached, the kit draws the older module in its frame: no merlon goes missing over a stale cache.
func test_a_variant_that_is_not_cached_draws_the_older_module() -> void:
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
	var drawn := 0
	for n in node.get_node("TownKit").get_children():
		if str(n.name).begins_with("merlon_v"):
			drawn += (n as MultiMeshInstance3D).multimesh.instance_count
	assert_int(drawn).is_greater(0)
	assert_int(drawn).is_equal(BoardgenTownDressing.merlons(_town()).size())


## Crows sit on battlements and on whole roof ridges only (no model stands there); with the A8 modules cached the crows and rats are the kit's meshes, not the stand-ins.
func test_crows_perch_where_nobody_stands_and_the_kit_critters_replace_the_stand_ins() -> void:
	var layout: Dictionary = ClassDB.instantiate("NmlCore").boardgen_layout_themed(7, "ruintown")
	var merlon_tops := BoardgenTownDressing.merlons(layout).map(func(m: Dictionary) -> float: return float(m["hi"].y))
	var ridge := 0
	for p: Vector3 in BoardgenTownLife.crow_perches(layout):
		if not merlon_tops.has(p.y):
			ridge += 1
			assert_float(p.y).is_greater(BoardgenTownDressing.BODY_IN)   # above every house's eaves line
	assert_int(ridge).is_greater(0)
	DirAccess.make_dir_recursive_absolute(DIR)
	for m: String in BoardgenTownKit.MODULES + ["crow_perched", "rat_running"]:
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
	var crows := node.find_child("Crows", true, false) as MultiMeshInstance3D
	var rats := node.find_child("Rats", true, false) as MultiMeshInstance3D
	assert_object(crows).is_not_null()
	assert_object(rats).is_not_null()
	assert_bool(crows.multimesh.mesh is PrismMesh).is_false()
	assert_bool(rats.multimesh.mesh is CapsuleMesh).is_false()
	for f in DirAccess.get_files_at(DIR):
		DirAccess.remove_absolute(DIR.path_join(f))
