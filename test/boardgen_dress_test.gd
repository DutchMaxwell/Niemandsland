extends GdUnitTestSuite
## BoardgenDress (docs/adr/0003-generated-board-dressing.md): which class draws which plan box, the planner interface with supplied planners on the stub kit, the two nodes of a build, and a board that stays undressed.

const CLASSES := ["houses", "tiers", "ladders", "walls", "towers", "ground", "props", "clutter"]


func _layout(seed: int, theme := "ruintown") -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(seed, theme)


## A stub dressing kit: a box per module, no GLB needed.
func _stub_kit() -> BoardgenDressKit:
	var kit := BoardgenKit.new(BoardgenTheme.TOWN_LIBRARY)
	add_child(kit)
	auto_free(kit)
	return BoardgenDressKit.new(kit, true)


## The planner list the constructor takes: one [class, Script] pair per class, null draws nothing.
func _planners(houses: Variant) -> Array:
	var out: Array = [["houses", houses]]
	for c in CLASSES:
		if c != "houses":
			out.append([c, null])
	return out


## A planner script made at run time: `count` placements of `module`, and a build_extra that adds a node.
func _fake(modules: Array, module: String, count: int) -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends RefCounted\nconst MODULES: Array[String] = %s\nstatic func plan(_layout: Dictionary, _ctx: Dictionary) -> Array[Dictionary]:\n\tvar out: Array[Dictionary] = []\n\tfor i in %d:\n\t\tout.append({\"module\": \"%s\", \"xf\": Transform3D(Basis(), Vector3(i * 0.05, 0.0, 0.0)), \"cls\": \"houses\"})\n\treturn out\nstatic func build_extra(_layout: Dictionary, parent: Node3D, _ctx: Dictionary) -> void:\n\tvar n := Node3D.new()\n\tn.name = \"Extra\"\n\tparent.add_child(n)\n" % [str(modules), count, module]
	s.reload()
	return s


## Every class empty (null = no planner) so planner files added later do not change these tests.
func _only(houses: Variant) -> Array:
	return _planners(houses)


func test_every_box_that_draws_itself_has_a_class() -> void:
	var seen := {}
	for s in [41, 25, 3, 7]:
		var layout := _layout(s)
		for b: Dictionary in BoardgenGreybox.plan(layout):
			var c := BoardgenDress.box_class(b)
			if BoardgenGreybox.draws_itself(b):
				assert_bool(CLASSES.has(c)).is_true()   # a drawn box no class takes would stay as the old look forever
			seen[c] = int(seen.get(c, 0)) + 1
	print("DRESS box classes: ", seen)
	for c in ["houses", "tiers", "ladders", "walls", "ground", "props", "clutter"]:
		assert_int(int(seen.get(c, 0))).is_greater(0)   # each class the mapping names really occurs on the boards


func test_a_house_and_a_hidden_wall_cell_have_no_class() -> void:
	var layout := _layout(41)
	var roofed := 0
	var hidden := 0
	for b: Dictionary in BoardgenGreybox.plan(layout):
		if b["kind"] == "roofed":
			assert_str(BoardgenDress.box_class(b)).is_empty()
			roofed += 1
		if b.get("hidden", false) and b["kind"] == "wall":   # the wall cells BoardgenTownSilhouette draws: their box only keeps the collider
			assert_str(BoardgenDress.box_class(b)).is_empty()
			hidden += 1
	assert_bool(roofed > 0 and hidden > 0).is_true()


func test_the_rules_of_the_mapping_on_hand_made_boxes() -> void:
	assert_str(BoardgenDress.box_class({"kind": "wood", "lean_to": true})).is_equal("houses")
	assert_str(BoardgenDress.box_class({"kind": "brick"})).is_equal("houses")
	assert_str(BoardgenDress.box_class({"kind": "wall", "merlon": true})).is_equal("walls")
	assert_str(BoardgenDress.box_class({"kind": "rubble", "prop": true})).is_equal("walls")
	assert_str(BoardgenDress.box_class({"kind": "rubble"})).is_equal("ground")
	assert_str(BoardgenDress.box_class({"kind": "stone", "party_stub": true, "prop": true})).is_equal("tiers")
	assert_str(BoardgenDress.box_class({"kind": "tier2"})).is_equal("tiers")
	assert_str(BoardgenDress.box_class({"kind": "ladder"})).is_equal("ladders")
	assert_str(BoardgenDress.box_class({"kind": "ladder", "lantern": true})).is_equal("props")
	assert_str(BoardgenDress.box_class({"kind": "hazard", "lm": "Sump"})).is_equal("ground")
	assert_str(BoardgenDress.box_class({"kind": "stone", "lm": "Crane"})).is_equal("props")
	assert_str(BoardgenDress.box_class({"kind": "wood", "prop": true})).is_equal("clutter")
	assert_str(BoardgenDress.box_class({"kind": "street"})).is_equal("ground")
	assert_str(BoardgenDress.box_class({"kind": "roofed"})).is_empty()


func test_a_supplied_list_replaces_the_planner_files_and_a_class_outside_it_draws_nothing() -> void:
	var fake := _fake(["dr_litter_straw"], "dr_litter_straw", 1)
	var dress: BoardgenDress = auto_free(BoardgenDress.new(_stub_kit(), _only(fake)))
	assert_bool(dress.setup(_layout(41))).is_true()
	assert_dict(dress.classes()).is_equal({"houses": true})   # the supplied list is the whole truth
	var none: BoardgenDress = auto_free(BoardgenDress.new(_stub_kit(), [["tiers", null]]))
	assert_bool(none.setup(_layout(41))).is_false()   # a class it does not name, and this one, draw nothing
	assert_dict(none.classes()).is_empty()


func test_setup_is_false_on_a_deepworks_board_or_without_a_planner() -> void:
	var fake := _fake([], "dr_litter_straw", 1)   # no modules needed: a usable class even without the stub kit
	var on: BoardgenDress = auto_free(BoardgenDress.new(null, _only(fake)))
	assert_bool(on.setup(_layout(41))).is_true()   # the control: a town with a usable class
	var deep: BoardgenDress = auto_free(BoardgenDress.new(null, _only(fake)))
	assert_bool(deep.setup(_layout(41, "deepworks"))).is_false()   # a Deepworks board never creates a dressing
	var none: BoardgenDress = auto_free(BoardgenDress.new(null, [["houses", null]]))
	assert_bool(none.setup(_layout(41))).is_false()   # no class is usable
	assert_dict(none.classes()).is_empty()


func test_a_build_with_a_supplied_planner_has_both_nodes_the_expected_triangles_and_the_extras() -> void:
	var fake := _fake(["dr_house_tb_plain_a"], "dr_house_tb_plain_a", 7)   # a module with one shadow hull (flat litter has none)
	var dress: BoardgenDress = auto_free(BoardgenDress.new(_stub_kit(), _only(fake)))
	var layout := _layout(41)
	assert_bool(dress.setup(layout)).is_true()
	assert_dict(dress.classes()).is_equal({"houses": true})
	dress.build(layout)
	var mesh := dress.get_node("DressMesh") as MeshInstance3D
	var shadow := dress.get_node("DressShadow") as MeshInstance3D
	assert_object(mesh).is_not_null()
	assert_object(shadow).is_not_null()
	assert_int(mesh.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
	assert_int(shadow.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY)
	assert_int(mesh.mesh.get_surface_count()).is_equal(1)
	assert_int((mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()).is_equal(7 * 36)   # the supplied 7 boxes, not the house file's many
	assert_str(mesh.mesh.surface_get_material(0).resource_name).is_equal(mesh.mesh.surface_get_name(0))   # bound by name
	assert_int((shadow.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()).is_equal(7 * 36)
	assert_object(dress.get_node_or_null("Extra")).is_not_null()   # build_extra ran
