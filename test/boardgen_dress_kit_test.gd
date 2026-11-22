extends GdUnitTestSuite
## BoardgenDressKit (PLAN_RUINTOWN_DRESSING step 3): the bundled manifest has the contract's shape, a stub module is a box of its aabb, and a GLB written at run time comes back with one named
## surface per material and its UV, COLOR and TANGENT. No network, no kit folder.

const DIR := "user://boardgen_dress_kit_test"
const MATERIALS := ["ct_stone", "ct_stone_big", "ct_plaster", "ct_timber", "ct_roof", "ct_flags", "ct_iron", "ct_clay", "ct_glass_lit", "ct_glass_dark", "ct_matte"]
const KEYS := ["family", "role", "len_in", "height_in", "tris", "materials", "aabb_in", "proud_in", "openings", "shadow", "tags", "stub"]   # the contract's keys; the forge adds more (batch, tri_cap, mount_in, bytes ...) and the test tolerates them
const K1 := ["dr_house_tb_plain_a", "dr_house_tb_door", "dr_gable_tb_s3", "dr_gable_st_s6", "dr_roof_s3_mid_a", "dr_roof_s6_verge", "dr_chimney_a", "dr_house_st_quoin"]


func _dress(force_stub := false, dir := "") -> BoardgenDressKit:
	var kit := BoardgenKit.new("ruintown")
	kit.local_dir = dir
	add_child(kit)
	auto_free(kit)
	return BoardgenDressKit.new(kit, force_stub)


## A two-surface module (one quad each) with UV, COLOR and TANGENT, the surfaces on materials named like the manifest's, written to DIR/<name>.glb.
func _fixture(name: String) -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	var mesh := ArrayMesh.new()
	for s in 2:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(s, 0, 0), Vector3(s + 1, 0, 0), Vector3(s + 1, 1, 0), Vector3(s, 1, 0)])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
		arrays[Mesh.ARRAY_TANGENT] = PackedFloat32Array([1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1, 1, 0, 0, 1])
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray([Color(0.5, 0.4, 0.3, 0.2), Color(0.5, 0.4, 0.3, 0.2), Color(0.5, 0.4, 0.3, 0.2), Color(0.5, 0.4, 0.3, 0.2)])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := StandardMaterial3D.new()
		mat.resource_name = ["ct_stone", "ct_timber"][s]
		mesh.surface_set_material(s, mat)
	var holder := MeshInstance3D.new()
	holder.mesh = mesh
	var state := GLTFState.new()
	var doc := GLTFDocument.new()
	doc.append_from_scene(holder, state)
	doc.write_to_filesystem(state, "%s/%s.glb" % [DIR, name])
	holder.free()


func test_the_bundled_manifest_has_the_contract_shape() -> void:
	var meta := _dress().meta
	for k in ["version", "materials", "ground", "sets", "licence", "modules"]:
		assert_bool(meta.has(k)).is_true()
	var modules: Dictionary = meta["modules"]
	assert_int(modules.size()).is_equal(93)
	for name: String in modules:
		var m: Dictionary = modules[name]
		for k in KEYS:
			assert_bool(m.has(k)).is_true()
		assert_bool(m["tris"] > 0 and (not m.has("tri_cap") or m["tris"] <= m["tri_cap"])).is_true()   # within the forge's cap for its family, when it states one
		assert_bool(m["materials"].size() > 0).is_true()
		for mat: String in m["materials"]:
			assert_bool(MATERIALS.has(mat) and meta["materials"].has(mat)).is_true()
		assert_int(m["aabb_in"].size()).is_equal(2)
		assert_bool(m["proud_in"].has("flat") and m["proud_in"].has("low") and m["proud_in"].has("high")).is_true()
		assert_bool(m["shadow"].size() >= 1 and m["shadow"].size() <= 3).is_true()
	for n in K1:
		assert_bool(modules.has(n)).is_true()
	assert_int(meta["materials"].size()).is_equal(MATERIALS.size())
	for g in ["cobbles", "earth", "yard_flags", "deck_flags", "deck_boards", "walk_flags", "rubble", "plot"]:
		assert_bool(meta["ground"].has(g)).is_true()


func test_an_unknown_module_has_no_entry_no_mesh_and_is_never_usable() -> void:
	var dress := _dress(true)
	assert_dict(dress.module("dr_nope")).is_empty()
	assert_object(dress.mesh("dr_nope")).is_null()
	assert_bool(dress.usable(["dr_nope"])).is_false()   # not even under the stub kit
	assert_bool(dress.usable(["dr_house_tb_plain_a", "dr_nope"])).is_false()


func test_a_stub_module_is_a_box_of_its_aabb_on_one_surface_named_by_its_first_material() -> void:
	var dress := _dress(true)
	for name in ["dr_house_tb_plain_a", "dr_roof_s6_mid_a", "dr_junk_barrels", "dr_ladder_top"]:
		var m := dress.module(name)
		var mesh := dress.mesh(name)
		assert_int(mesh.get_surface_count()).is_equal(1)
		assert_str(mesh.surface_get_name(0)).is_equal(m["materials"][0])
		var box := mesh.get_aabb()
		var lo := Vector3(m["aabb_in"][0][0], m["aabb_in"][0][1], m["aabb_in"][0][2]) * 0.0254
		var hi := Vector3(m["aabb_in"][1][0], m["aabb_in"][1][1], m["aabb_in"][1][2]) * 0.0254
		assert_vector(box.position).is_equal_approx(lo, Vector3(0.0001, 0.0001, 0.0001))
		assert_vector(box.end).is_equal_approx(hi, Vector3(0.0001, 0.0001, 0.0001))
		var arrays := mesh.surface_get_arrays(0)
		assert_bool(arrays[Mesh.ARRAY_COLOR] != null and arrays[Mesh.ARRAY_TANGENT] != null and arrays[Mesh.ARRAY_TEX_UV] != null).is_true()


func test_usable_means_known_not_a_stub_and_cached_unless_the_stub_kit_is_forced() -> void:
	_fixture("dr_chimney_a")
	var dress := _dress(false, DIR)
	dress.meta = dress.meta.duplicate(true)
	dress.meta["modules"]["dr_chimney_a"]["stub"] = false
	dress.meta["modules"]["dr_litter_straw"]["stub"] = true
	assert_bool(dress.usable(["dr_chimney_a"])).is_true()   # built, and its GLB is in the dev folder
	assert_bool(dress.usable(["dr_litter_straw"])).is_false()   # a stub entry
	dress.meta["modules"]["dr_chimney_a"]["stub"] = true
	assert_bool(dress.usable(["dr_chimney_a"])).is_false()   # a stub flag alone is enough to refuse
	dress.meta["modules"]["dr_roof_s3_verge"]["stub"] = false
	assert_bool(dress.usable(["dr_roof_s3_verge"])).is_false()   # built on paper, GLB not cached
	assert_bool(_dress(true).usable(["dr_litter_straw", "dr_roof_s3_verge"])).is_true()


func test_a_glb_comes_back_with_its_surface_names_and_vertex_data() -> void:
	_fixture("dr_chimney_a")
	var dress := _dress(false, DIR)
	var mesh := dress.mesh("dr_chimney_a")
	assert_object(mesh).is_not_null()
	assert_int(mesh.get_surface_count()).is_equal(2)
	assert_str(mesh.surface_get_name(0)).is_equal("ct_stone")
	assert_str(mesh.surface_get_name(1)).is_equal("ct_timber")
	for s in 2:
		var arrays := mesh.surface_get_arrays(s)
		assert_int((arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(4)
		assert_bool(arrays[Mesh.ARRAY_TEX_UV] != null and (arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array).size() == 4).is_true()
		assert_bool(arrays[Mesh.ARRAY_COLOR] != null and (arrays[Mesh.ARRAY_COLOR] as PackedColorArray).size() == 4).is_true()
		assert_bool(arrays[Mesh.ARRAY_TANGENT] != null and (arrays[Mesh.ARRAY_TANGENT] as PackedFloat32Array).size() == 16).is_true()
	assert_object(dress.mesh("dr_chimney_a")).is_same(mesh)   # parsed once, then shared
	assert_object(_dress(false, DIR).mesh("dr_litter_straw")).is_null()   # in the manifest, not cached: no mesh
