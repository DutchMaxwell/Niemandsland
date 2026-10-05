extends GdUnitTestSuite
## Earth and moss at the foot of free ruins and solids (S6-1, maintainer 05.10.: ruins "organically integrated"): one
## FootDressing decal child, 3" around the footprint, shown only on the grassland table and following biome changes
## (lead D12). A child of the piece, so it moves, turns and goes with it.


class StubTable extends Node3D:
	signal biome_changed(biome_name: String)
	var biome := "temperate_grassland"


var _table: StubTable


func before_test() -> void:
	_table = auto_free(StubTable.new())
	_table.add_to_group("table")
	add_child(_table)


func _dressing(n: Node) -> Decal:
	var found := n.find_children("FootDressing", "Decal", false, false)
	return found[0] as Decal if found.size() == 1 else null


func test_a_solid_and_a_ruin_carry_the_foot_dressing() -> void:
	var om: ObjectManager = auto_free(ObjectManager.new())
	add_child(om)
	om.solid_models_library().apply_manifest_text("{}")   # no model downloads in tests
	for spec: Array in [["blocker_6x3", ObjectManager.SandboxPropKind.BLOCKER, Vector2(6, 3)],
			["ruin_large_2f", ObjectManager.SandboxPropKind.RUIN, Vector2(9, 6)]]:
		var piece := om.spawn_sandbox_terrain(spec[0], spec[1], Vector3.ZERO, false)
		var d := _dressing(piece)
		assert_object(d).override_failure_message("%s has no foot dressing" % spec[0]).is_not_null()
		if d != null:
			var fp: Vector2 = spec[2]
			assert_vector(d.size).is_equal_approx(Vector3(fp.x + 6.0, 0.4, fp.y + 6.0) * 0.0254, Vector3.ONE * 0.0001)
			assert_bool(d.visible).is_true()


func test_the_dressing_shows_on_grassland_only() -> void:
	var solid: SandboxSolidProp = auto_free(SandboxSolidProp.new())
	solid.configure("blocker_6x3", 3, Vector2(6, 3))
	add_child(solid)
	var d := _dressing(solid)
	assert_object(d).is_not_null()
	if d == null:
		return
	_table.biome_changed.emit("arid_desert")
	assert_bool(d.visible).is_false()
	_table.biome_changed.emit("temperate_grassland")
	assert_bool(d.visible).is_true()
