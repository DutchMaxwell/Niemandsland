extends GdUnitTestSuite
## The blade clumps of the ruin town (LOOK4 G3): every clump stands on open earth or a plot where the green map grows, never in a keep-out, never above
## 0.38 in; the same seed gives the same clumps, the set is half-turn symmetric, the mesh is 5 blades x 5 triangles and the shader is the shared green.

const PER_SQ_IN := 6.0


func _layout(s: int) -> Dictionary:
	return ClassDB.instantiate("NmlCore").boardgen_layout_themed(s, "ruintown")


func test_every_clump_stands_where_the_green_grows_and_never_in_a_keep_out_or_too_tall() -> void:
	for s in [41, 25, 3]:
		var layout := _layout(s)
		var green := BoardgenTownGreen.map(layout)
		var cell := float(layout["cell_in"])
		var half := Vector2(layout["nx"], layout["nz"]) * cell * 0.5
		var clear := BoardgenDressRules.kept_clear(layout)
		var ladders := BoardgenDressRules._ladder_zones(layout)
		var clumps := BoardgenTownGrass.plan(layout, green, PER_SQ_IN)
		assert_int(clumps.size()).is_greater(500)
		for c: Dictionary in clumps:
			var p: Vector2 = c["at"]
			var i := int(floor((p.y + half.y) / cell)) * int(layout["nx"]) + int(floor((p.x + half.x) / cell))
			var where := "seed %d clump at %s" % [s, p]
			assert_bool(BoardgenGreybox._cell_kind(layout["cells"][i], true) in ["ground", "rough"]).override_failure_message(where + " off the earth").is_true()
			assert_bool(clear.has(i) or ladders.any(func(r: Rect2) -> bool: return r.has_point(p))).override_failure_message(where + " in a keep-out").is_false()
			assert_float(green.get_pixel(int((p.x + half.x) * 4.0), int((p.y + half.y) * 4.0)).r).override_failure_message(where + " on no cover").is_greater(0.0)
			assert_float(c["h"]).is_less_equal(BoardgenTownGrass.MAX_IN)
		for xf: Transform3D in BoardgenTownGrass.points(layout, green, PER_SQ_IN):
			assert_float((xf * Vector3(0.3, 1.0, 0.3)).y / Units.INCHES_TO_METERS).is_less_equal(BoardgenTownGrass.MAX_IN + 0.0001)   # the tip of a unit-high blade


func test_the_same_seed_gives_the_same_clumps_and_the_set_is_half_turn_symmetric() -> void:
	var layout := _layout(41)
	var green := BoardgenTownGreen.map(layout)
	var a := BoardgenTownGrass.plan(layout, green, PER_SQ_IN)
	assert_array(BoardgenTownGrass.plan(layout, green, PER_SQ_IN)).is_equal(a)
	var keys := {}
	for c: Dictionary in a:
		keys["%.4f/%.4f/%.4f" % [c["at"].x, c["at"].y, c["h"]]] = true
	for c: Dictionary in a:
		assert_bool(keys.has("%.4f/%.4f/%.4f" % [-c["at"].x, -c["at"].y, c["h"]])).override_failure_message("no half-turn twin for %s" % c["at"]).is_true()
	assert_array(BoardgenTownGrass.plan(_layout(25), BoardgenTownGreen.map(_layout(25)), PER_SQ_IN)).is_not_equal(a)


func test_the_clump_mesh_and_the_nodes() -> void:
	var mesh := BoardgenTownGrass.mesh()
	assert_int(mesh.get_surface_count()).is_equal(1)
	assert_int((mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()).is_equal(5 * 5 * 3)   # 5 blades x 5 triangles
	var layout := _layout(41)
	var node := BoardgenTownGrass.build(layout, BoardgenTownGreen.map(layout), PER_SQ_IN)
	assert_int(node.get_child_count()).is_equal(4)
	var total := 0
	for mi: MultiMeshInstance3D in node.get_children():
		assert_int(mi.cast_shadow).is_equal(GeometryInstance3D.SHADOW_CASTING_SETTING_OFF)
		total += mi.multimesh.instance_count
	assert_int(total).is_equal(BoardgenTownGrass.plan(layout, BoardgenTownGreen.map(layout), PER_SQ_IN).size())
	assert_int(node.find_children("*", "CollisionShape3D", true, false).size()).is_equal(0)
	node.free()
	var src := FileAccess.get_file_as_string("res://shaders/ruintown_grass.gdshader")
	assert_str(src).contains('#include "res://shaders/ruintown_green.gdshaderinc"').contains("green_tone(xz_in").contains('#include "res://shaders/ruintown_dress_veg.gdshaderinc"')
	assert_object(load("res://shaders/ruintown_grass.gdshader")).is_not_null()
