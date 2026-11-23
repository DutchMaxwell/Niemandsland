extends GdUnitTestSuite
## BoardgenDress (PLAN_RUINTOWN_DRESSING step 8): which class draws which plan box, the planner interface with fake planners on the stub kit, the two nodes of a build, and the off switch.
## The switches are static: every test puts them back.

const CLASSES := ["houses", "tiers", "ladders", "walls", "towers", "ground", "props", "clutter"]


func after_test() -> void:
	BoardgenDress.test_mode = ""
	BoardgenDress.test_planners = {}


func _layout(seed: int, theme := "ruintown") -> Dictionary:
	return (ClassDB.instantiate("NmlCore") as Object).boardgen_layout_themed(seed, theme)


## A planner script made at run time: `count` placements of `module`, and a build_extra that adds a node.
func _fake(modules: Array, module: String, count: int) -> GDScript:
	var s := GDScript.new()
	s.source_code = "extends RefCounted\nconst MODULES: Array[String] = %s\nstatic func plan(_layout: Dictionary, _ctx: Dictionary) -> Array[Dictionary]:\n\tvar out: Array[Dictionary] = []\n\tfor i in %d:\n\t\tout.append({\"module\": \"%s\", \"xf\": Transform3D(Basis(), Vector3(i * 0.05, 0.0, 0.0)), \"cls\": \"houses\"})\n\treturn out\nstatic func build_extra(_layout: Dictionary, parent: Node3D, _ctx: Dictionary) -> void:\n\tvar n := Node3D.new()\n\tn.name = \"Extra\"\n\tparent.add_child(n)\n" % [str(modules), count, module]
	s.reload()
	return s


## Every class empty (null = no planner) so the files that other lanes add later do not change these tests.
func _only(houses: GDScript) -> void:
	BoardgenDress.test_planners = {}
	for c in CLASSES:
		BoardgenDress.test_planners[c] = null
	BoardgenDress.test_planners["houses"] = houses


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


func test_the_planner_is_the_test_double_when_one_is_set_else_the_file_or_null() -> void:
	var fake := _fake(["dr_litter_straw"], "dr_litter_straw", 1)
	BoardgenDress.test_planners = {"houses": fake, "tiers": null}
	assert_object(BoardgenDress.planner("houses")).is_same(fake)
	assert_object(BoardgenDress.planner("tiers")).is_null()
	BoardgenDress.test_planners = {}
	assert_object(BoardgenDress.planner("no_such_class")).is_null()


func test_setup_is_false_when_the_dressing_is_off_on_a_deepworks_board_or_without_a_planner() -> void:
	_only(_fake([], "dr_litter_straw", 1))   # no modules needed: usable without the stub kit, so only the switches decide
	var on: BoardgenDress = auto_free(BoardgenDress.new())
	assert_bool(on.setup(_layout(41))).is_true()   # the control: a town, not switched off, a usable class
	BoardgenDress.test_mode = "off"
	var off: BoardgenDress = auto_free(BoardgenDress.new())
	assert_bool(off.setup(_layout(41))).is_false()
	BoardgenDress.test_mode = ""
	var deep: BoardgenDress = auto_free(BoardgenDress.new())
	assert_bool(deep.setup(_layout(41, "deepworks"))).is_false()   # a Deepworks board never creates a dressing
	_only(null)
	var none: BoardgenDress = auto_free(BoardgenDress.new())
	assert_bool(none.setup(_layout(41))).is_false()   # no class is usable
	assert_dict(none.classes()).is_empty()


func test_a_build_with_a_fake_planner_has_both_nodes_the_expected_triangles_and_the_extras() -> void:
	_only(_fake(["dr_litter_straw"], "dr_litter_straw", 7))
	BoardgenDress.test_mode = "stub"
	var dress: BoardgenDress = auto_free(BoardgenDress.new())
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
	assert_int((mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()).is_equal(7 * 36)   # 7 boxes x 12 triangles
	assert_str(mesh.mesh.surface_get_material(0).resource_name).is_equal(mesh.mesh.surface_get_name(0))   # bound by name
	assert_int((shadow.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX] as PackedInt32Array).size()).is_equal(7 * 36)
	assert_object(dress.get_node_or_null("Extra")).is_not_null()   # build_extra ran
