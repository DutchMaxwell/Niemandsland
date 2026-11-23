extends GdUnitTestSuite
## BoardgenDressMesh: the merge of placements into one mesh with one surface per material (sorted, named), the vertex data kept as authored, and the shadow proxy.
## Runs on the stub kit (every module a box of its aabb), so no GLB is needed.

const NAMES := ["dr_house_tb_plain_a", "dr_house_st_plain_a", "dr_roof_s3_mid_a", "dr_ladder_3in", "dr_junk_barrels", "dr_litter_straw", "dr_lamp_post", "dr_chimney_a"]


func _dress() -> BoardgenDressKit:
	var kit := BoardgenKit.new("ruintown")
	add_child(kit)
	auto_free(kit)
	return BoardgenDressKit.new(kit, true)


func _xf(i: int) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, (i % 4) * PI * 0.5), Vector3((i % 37) - 18.0, (i % 5) * 0.01, (i % 23) - 11.0) * 0.0254 * 1.7)


func _placements(n: int) -> Array:
	var out := []
	for i in n:
		out.append({"module": NAMES[i % NAMES.size()], "xf": _xf(i), "cls": "test"})
	return out


func _tris(mesh: ArrayMesh) -> int:
	var n := 0
	for s in mesh.get_surface_count():
		n += (mesh.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func test_one_surface_per_material_sorted_and_named() -> void:
	var dress := _dress()
	var placements := _placements(NAMES.size())
	var want := {}
	for p: Dictionary in placements:
		want[dress.module(p["module"])["materials"][0]] = true   # a stub has one surface: its first material
	var merged := BoardgenDressMesh.merge(placements, dress)
	assert_int(merged.get_surface_count()).is_equal(want.size())
	var names: Array = want.keys()
	names.sort()
	for s in merged.get_surface_count():
		assert_str(merged.surface_get_name(s)).is_equal(names[s])
	assert_int(want.size()).is_greater(2)   # the placements really use several materials


func test_triangles_add_up_and_the_aabb_is_the_union_of_the_placed_aabbs() -> void:
	var dress := _dress()
	var placements := _placements(400)
	var merged := BoardgenDressMesh.merge(placements, dress)
	var tris := 0
	var union := AABB()
	for i in placements.size():
		var m := dress.mesh(placements[i]["module"])
		tris += _tris(m)
		var placed: AABB = (placements[i]["xf"] as Transform3D) * m.get_aabb()
		union = placed if i == 0 else union.merge(placed)
	assert_int(_tris(merged)).is_equal(tris)
	assert_vector(merged.get_aabb().position).is_equal_approx(union.position, Vector3(0.0001, 0.0001, 0.0001))
	assert_vector(merged.get_aabb().end).is_equal_approx(union.end, Vector3(0.0001, 0.0001, 0.0001))


func test_a_wrong_transform_fails_the_aabb_check() -> void:
	var dress := _dress()
	var placements := _placements(50)
	var merged := BoardgenDressMesh.merge(placements, dress)
	var moved := _placements(50)
	moved[3]["xf"] = Transform3D(Basis(), Vector3(5, 0, 0))   # one module put 5 m away
	var other := BoardgenDressMesh.merge(moved, dress)
	assert_bool(other.get_aabb().is_equal_approx(merged.get_aabb())).is_false()   # the check that compares the AABBs can fail


func test_the_vertex_data_is_kept_and_the_same_input_gives_the_same_arrays() -> void:
	var dress := _dress()
	var a := BoardgenDressMesh.merge(_placements(60), dress)
	var b := BoardgenDressMesh.merge(_placements(60), dress)
	assert_int(a.get_surface_count()).is_equal(b.get_surface_count())
	for s in a.get_surface_count():
		var x := a.surface_get_arrays(s)
		var y := b.surface_get_arrays(s)
		for k in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT, Mesh.ARRAY_COLOR, Mesh.ARRAY_TEX_UV, Mesh.ARRAY_INDEX]:
			assert_bool(x[k] != null).is_true()   # the attributes of the modules survive the merge (tangents are not generated here)
			assert_bool(var_to_bytes(x[k]) == var_to_bytes(y[k])).is_true()


func test_a_placement_without_a_mesh_is_skipped() -> void:
	var dress := _dress()
	var merged := BoardgenDressMesh.merge([{"module": "dr_nope", "xf": Transform3D(), "cls": "test"}, {"module": "dr_litter_straw", "xf": Transform3D(), "cls": "test"}], dress)
	assert_int(merged.get_surface_count()).is_equal(1)
	assert_int(_tris(BoardgenDressMesh.merge([], dress))).is_equal(0)


func test_1500_stub_placements_merge_in_under_half_a_second() -> void:
	var dress := _dress()
	var placements := _placements(1500)
	var t0 := Time.get_ticks_msec()
	var merged := BoardgenDressMesh.merge(placements, dress)
	var ms := Time.get_ticks_msec() - t0
	print("DRESS_MESH 1500 placements: %d surfaces, %d tris, %d ms" % [merged.get_surface_count(), _tris(merged), ms])
	assert_int(ms).is_less(500)


func test_the_shadow_proxy_is_one_surface_of_boxes_from_the_hulls() -> void:
	var dress := _dress()
	var placements := _placements(NAMES.size())
	var proxy := BoardgenDressMesh.shadow(placements, dress)
	assert_int(proxy.get_surface_count()).is_equal(1)
	var boxes := 0
	for p: Dictionary in placements:
		boxes += (dress.module(p["module"])["shadow"] as Array).size()
	assert_int(_tris(proxy)).is_equal(boxes * 12)
	assert_int(boxes).is_greater(0)
	assert_int(BoardgenDressMesh.shadow([], dress).get_surface_count()).is_equal(0)
	# a module WITHOUT the key casts its aabb shrunk by 0.05 in; flat pieces keep their thickness
	dress.meta = dress.meta.duplicate(true)
	dress.meta["modules"]["dr_junk_barrels"].erase("shadow")
	var one := BoardgenDressMesh.shadow([{"module": "dr_junk_barrels", "xf": Transform3D(), "cls": "test"}], dress)
	var a: Array = dress.module("dr_junk_barrels")["aabb_in"]
	var want := Vector3.ZERO
	for k in 3:
		var ext := float(a[1][k]) - float(a[0][k])
		want[k] = (ext - 0.1 if ext > 0.1 else ext) * 0.0254   # shrunk 0.05 in per side, a flat piece keeps its thickness
	assert_vector(one.get_aabb().size).is_equal_approx(want, Vector3(0.0001, 0.0001, 0.0001))


func test_a_module_with_an_empty_shadow_list_casts_nothing() -> void:
	var dress := _dress()
	dress.meta = dress.meta.duplicate(true)
	dress.meta["modules"]["dr_litter_straw"]["shadow"] = []   # flat litter and soft vegetation: no proxy
	var none := BoardgenDressMesh.shadow([{"module": "dr_litter_straw", "xf": Transform3D(), "cls": "test"}, {"module": "dr_litter_straw", "xf": Transform3D(), "cls": "test"}], dress)
	assert_int(none.get_surface_count()).is_equal(0)
	var mixed := BoardgenDressMesh.shadow([{"module": "dr_litter_straw", "xf": Transform3D(), "cls": "test"}, {"module": "dr_house_tb_plain_a", "xf": Transform3D(), "cls": "test"}], dress)
	assert_int(_tris(mixed)).is_equal((dress.module("dr_house_tb_plain_a")["shadow"] as Array).size() * 12)   # only the house panel's hulls


func test_card_and_modelled_vegetation_merge_into_two_surfaces() -> void:
	var dress := _dress()
	var placements := [{"module": "dr_veg_card_a", "xf": Transform3D(), "cls": "test"}, {"module": "dr_veg_grass_tuft", "xf": Transform3D(), "cls": "test"}, {"module": "dr_veg_plot_a", "xf": Transform3D(), "cls": "test"}, {"module": "dr_veg_moss_mat", "xf": Transform3D(), "cls": "test"}]
	var merged := BoardgenDressMesh.merge(placements, dress)
	assert_int(merged.get_surface_count()).is_equal(2)
	assert_str(merged.surface_get_name(0)).is_equal("ct_veg")
	assert_str(merged.surface_get_name(1)).is_equal("ct_veg_card")
	assert_int(_tris(merged)).is_equal(4 * 12)
	assert_int(BoardgenDressMesh.shadow(placements, dress).get_surface_count()).is_equal(0)   # soft vegetation casts no shadow proxy

